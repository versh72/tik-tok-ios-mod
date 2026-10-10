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
//
// HushFeed writes ONLY current_region and residence. The hub fields
// (carrier_region, sys_region, region) are read but NOT written — they are
// handled by getter hooks. Writing them here would be redundant.
//
// The field names now live in RegionLogic.h, which is what the C test
// executes; the ObjC file only declares the macro names.
const logic = readFileSync(join(ROOT, 'Tweak/RegionLogic.h'), 'utf8');
const combined = src + '\n' + logic;

for (const field of ['current_region', 'residence']) {
  check(`rewrites ${field}`, logic.includes(`"${field}"`),
    'HushFeed-confirmed parameter set');
}

check('does NOT write hub fields (handled by getter hooks)',
  !src.includes('"region", @"sys_region", @"carrier_region"'),
  'HushFeed: "carrier_region, sys_region and region are the region hub\'s own answers... they are only looked at here, never written"');

check('only rewrites fields the app already filled',
  /isKindOfClass:\[NSString class\]/.test(src),
  'non-string values are passed as NULL so the C layer leaves them alone');
check('carrier_region_v2 only replaced when it parses as MCC',
  /strlen\(value\) != 3/.test(logic),
  'HushFeed isMcc: exactly 3 digits, not 3-4 chars');
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
console.log('\n== 9. The tested code IS the shipped code ==');

// The logic used to be duplicated: RegionLogic.h (tested by a real C test)
// and an inline copy in the ObjC method. A fix applied to one would silently
// not reach the other. The ObjC method must now delegate to the C layer.
const regionLogicH = readFileSync(join(ROOT, 'Tweak/RegionLogic.h'), 'utf8');

check('TikTokRegion.m includes RegionLogic.h',
  src.includes('../RegionLogic.h'),
  'without this the dylib carries its own copy of the rules');
check('tt_rewriteParams delegates to rl_rewrite_params',
  /rl_rewrite_params\s*\(/.test(src),
  'the C layer under test must be the one that runs');
check('no inline duplicate of the field list in the ObjC',
  !savedFieldsDuplicated(src),
  'a second copy of the rules in the .m can drift from the tested C');

check('RegionLogic.h defines the two written fields',
  regionLogicH.includes('RL_FIELD_CURRENT_REGION')
  && regionLogicH.includes('RL_FIELD_RESIDENCE'));
check('RegionLogic.h does NOT list hub fields as written',
  !/RL_FIELD_REGION.*RL_FIELD_RESIDENCE.*=\s*\{/.test(regionLogicH.replace(/\s+/g, ' ')),
  'HushFeed: hub fields are "only looked at here, never written"');
check('RegionLogic.h enforces exactly 3 digits for MCC',
  /strlen\(value\) != 3/.test(regionLogicH));
check('RegionLogic.h handles the sign-in path',
  /RL_SIGN_IN_PATH/.test(regionLogicH) && /rl_is_sign_in/.test(regionLogicH));
check('RegionLogic.h restores live sys_region and timezone on sign-in',
  /RL_FIELD_SYS_REGION/.test(regionLogicH)
  && /RL_FIELD_TIMEZONE_NAME/.test(regionLogicH)
  && /removed_count/.test(regionLogicH));

function savedFieldsDuplicated(source) {
  // Any inline array of field names in the .m is a second source of truth.
  return /NSArray<NSString \*> \*stringFields/.test(source)
    || /savedFields = @\[@"/.test(source);
}