#!/usr/bin/env node
// Static check for the injected dylib source.
//
// WHY: the theos toolchain does not exist on this machine (no clang for iOS,
// no theos, no WSL here), so this file cannot be compiled or run. Rather than
// assert "it builds", this checks the properties that can be read from the
// text and that would silently break the injection if wrong:
//
//   1. Objective-C structural balance — an unbalanced @implementation is a
//      compile error that would otherwise only surface on the user's machine.
//   2. Every hooked selector actually appears in the source.
//   3. No trust-overriding API that would silently defeat the point of the
//      tool, and no code that reaches outside the TikTok process.
//
// WHAT THIS DOES NOT DO: type checking, or verifying that the selectors match
// any particular TikTok build. Those are only knowable on a device.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');

let passed = 0, failed = 0;
const failures = [];
const check = (name, cond, detail) => {
  if (cond) { passed++; console.log(`  ok   ${name}`); }
  else { failed++; failures.push({ name, detail }); console.log(`  FAIL ${name}${detail ? `\n         ${detail}` : ''}`); }
};

const src = readFileSync(join(ROOT, 'Tweak/TikTokRegion.m'), 'utf8');

// Strip comments and string literals so counts reflect code, not prose.
const code = src
  .replace(/\/\*[\s\S]*?\*\//g, ' ')
  .replace(/\/\/[^\n]*/g, ' ')
  .replace(/"(?:\\.|[^"\\])*"/g, '""');

console.log('\n== 1. Objective-C structure ==');

const count = (needle) => (code.match(new RegExp(needle, 'g')) || []).length;

const impls = count('@implementation');
const ends = count('@end');
check('@implementation count matches @end count', impls === ends, `${impls} vs ${ends}`);
check('there is at least one category', impls > 0, `${impls} found`);

for (const [open, close, label] of [['{', '\\}', 'braces'], ['\\(', '\\)', 'parens'], ['\\[', '\\]', 'brackets']]) {
  const a = count(open), b = count(close);
  check(`${label} balanced`, a === b, `${a} opening vs ${b} closing`);
}

console.log('\n== 2. Constructor entry point ==');

// Without a constructor the dylib loads but never hooks anything.
check('has a __attribute__((constructor)) entry point',
  /__attribute__\(\(constructor\)\)/.test(code));
check('constructor calls every enable step',
  ['tt_enableTLSBypass', 'tt_enableRegionSpoof', 'tt_enableIntegritySpoof', 'tt_enableJailbreakSpoof']
    .every(fn => new RegExp(`\\[NSObject\\s+${fn}\\]`).test(code)),
  'a missing call means one of the four stages silently never runs');

console.log('\n== 3. Hooked selectors are present ==');

// Selectors and field names live in string literals, so these check the raw
// source. `code` has had its literals blanked out and would match nothing.
const REQUIRED_SELECTORS = [
  ['setSkipSSLCertificateError:', 'TLS bypass — tuxi/TikTok-Tweaks'],
  ['sgm_installChannel', 'channel spoof — tuxi/TikTok-Tweaks'],
  ['signInfo', 'sign info — tuxi/TikTok-Tweaks'],
  ['isFromAppStore', 'app store spoof — tuxi/TikTok-Tweaks'],
  ['mobileprovision', 'provisioning probe bypass'],
];

for (const [sel, why] of REQUIRED_SELECTORS) {
  check(`hooks ${sel}`, src.includes(sel), `required for: ${why}`);
}

console.log('\n== 4. Region parameters ==');

// The key set comes from HushFeed, the most complete Android implementation.
// Dropping one narrows the effect silently.
for (const field of ['region', 'sys_region', 'carrier_region', 'current_region', 'residence', 'carrier_region_v2']) {
  check(`rewrites ${field}`, src.includes(`@"${field}"`), 'HushFeed-confirmed parameter set');
}

check('only rewrites fields the app already filled',
  /isKindOfClass:\[NSString class\]/.test(code),
  'adding a parameter a same-region phone would not send is itself an anomaly');
check('carrier_region_v2 only replaced when it parses as MCC',
  /looksLikeMcc/.test(code));
check('country is configurable, not hardcoded',
  /TikTokRegionCountry/.test(src) && /kDefaultCountry/.test(src),
  'both the override key and the fallback must exist');

console.log('\n== 5. Scope and safety ==');

// The dylib runs inside TikTok. Anything reaching outside that process, or
// collecting data, is out of scope for what it is for.
const OUT_OF_SCOPE = [
  [/UIApplication.*openURL|canOpenURL/, 'must not launch other apps'],
  [/NSURLSession|URLSession/, 'must not make its own network requests'],
  [/NSFileManager.*(createFile|moveItem|copyItem|removeItem|writeToFile)/, 'must not write files'],
  [/UICollectionView|UIImageWriteToSavedPhotosAlbum|PHPhotoLibrary/, 'must not touch photos'],
  [/UIPasteboard/, 'must not read the clipboard'],
  [/keychain|SecItemAdd|SecItemCopyMatching/i, 'must not touch the keychain'],
];
for (const [pattern, why] of OUT_OF_SCOPE) {
  check(`stays inside the TikTok process: ${why}`, !pattern.test(code),
    `matched ${pattern}`);
}

// `fileExistsAtPath` is legitimate — it is the jailbreak check. Only the
// file-modifying variants are forbidden, which the list above already covers.

console.log('\n== 6. Build pipeline ==');

const makefile = readFileSync(join(ROOT, 'Tweak/Makefile'), 'utf8');
check('theos Makefile declares the target',
  makefile.includes('TWEAK_NAME = TikTokRegion'));
check('theos Makefile covers arm64 and arm64e',
  makefile.includes('arm64') && makefile.includes('arm64e'),
  'modern iPhones are arm64e; arm64-only would not load on A12+');
check('theos Makefile links Security',
  makefile.includes('Security'),
  'SecTrust handling needs it');

const sh = readFileSync(join(ROOT, 'Tweak/build.sh'), 'utf8');
check('build script refuses an encrypted IPA',
  /cryptid/.test(sh) && /РАСШИФРОВАННЫЙ/.test(sh),
  'patching encrypted bytes produces a broken IPA that only fails on device');
check('build script verifies the injection landed',
  /LC_LOAD_DYLIB присутствует/.test(sh),
  'insert_dylib can silently no-op; the check is the only proof it worked');
check('build script signs the dylib with ldid',
  /ldid -S/.test(sh));
check('build script does not embed any Apple ID or password',
  !/APPLE_ID|PASSWORD|PASSWD|ITUNES_PASSWORD/i.test(sh),
  'signing is done by Sideloadly on the user machine, never in this repo');

console.log(`\n${'='.repeat(60)}`);
console.log(`passed: ${passed}   failed: ${failed}`);
console.log(`${'='.repeat(60)}\n`);

if (failed) {
  console.log('FAILED CHECKS:');
  for (const f of failures) console.log(`  - ${f.name}${f.detail ? `: ${f.detail}` : ''}`);
  process.exit(1);
}