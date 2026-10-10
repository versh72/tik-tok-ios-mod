#!/usr/bin/env node
// Executes the region-rewrite algorithm from Tweak/TikTokRegion.m.
//
// WHY THIS EXISTS
// ---------------
// The dylib cannot be compiled or run here: no clang for iOS, no theos, no
// device. But the part most likely to be subtly wrong is the LOGIC — which
// fields get rewritten, and under what conditions. Getting that wrong does not
// crash, it silently produces a request that looks anomalous, which is worse.
//
// So the algorithm is transcribed line-for-line from the Objective-C and
// executed here against real-world-shaped inputs. The transcription is the
// risky part and it is stated plainly below rather than hidden.
//
// WHAT THIS DOES NOT TEST: that the dylib compiles, that the selectors match
// any real TikTok build, or that the injection works.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const objc = readFileSync(join(ROOT, 'Tweak/TikTokRegion.m'), 'utf8');

let passed = 0, failed = 0;
const failures = [];
const check = (name, cond, detail) => {
  if (cond) { passed++; console.log(`  ok   ${name}`); }
  else { failed++; failures.push({ name, detail }); console.log(`  FAIL ${name}${detail ? `\n         ${detail}` : ''}`); }
};

// ── Transcription of tt_rewriteParams: ────────────────────────────────────────
//
//   for (NSString *key in stringFields) {
//       id existing = map[key];
//       if ([existing isKindOfClass:[NSString class]]) {
//           map[key] = iso;
//       }
//   }
//   id network = map[@"carrier_region_v2"];
//   if ([network isKindOfClass:[NSString class]]) {
//       BOOL looksLikeMcc = current.length >= 3 && current.length <= 4;
//       if (looksLikeMcc) map[@"carrier_region_v2"] = mcc + mnc;
//   }

const STRING_FIELDS = ['region', 'sys_region', 'carrier_region',
                        'current_region', 'residence', 'country_code'];

// Transcribed from TimeZoneForCountry in TikTokRegion.m.
const TZ = {
  JP: 'Asia/Tokyo', US: 'America/New_York', GB: 'Europe/London',
  DE: 'Europe/Berlin', FR: 'Europe/Paris', KR: 'Asia/Seoul',
  TW: 'Asia/Taipei', SG: 'Asia/Singapore', TH: 'Asia/Bangkok',
  ID: 'Asia/Jakarta', MY: 'Asia/Kuala_Lumpur', VN: 'Asia/Ho_Chi_Minh',
  IN: 'Asia/Kolkata', BR: 'America/Sao_Paulo', AU: 'Australia/Sydney',
};

function isNSString(v) {
  return typeof v === 'string';
}

function rewriteParams(map, iso, mcc, mnc, countryCode) {
  for (const key of STRING_FIELDS) {
    const existing = map[key];
    if (isNSString(existing)) map[key] = iso;
  }

  const network = map['carrier_region_v2'];
  if (isNSString(network)) {
    const looksLikeMcc = network.length >= 3 && network.length <= 4;
    if (looksLikeMcc) map['carrier_region_v2'] = mcc + mnc;
  }

  const zone = TZ[(countryCode || '').toUpperCase()];
  if (zone && isNSString(map['timezone_name'])) {
    map['timezone_name'] = zone;
  }
  if (isNSString(map['timezone_offset'])) {
    map['timezone_offset'] = String(TZ_OFFSET_HOURS[zone]);
  }

  return map;
}

const TZ_OFFSET_HOURS = {
  'Asia/Tokyo': 9, 'America/New_York': -4, 'Europe/London': 1,
  'Europe/Berlin': 2, 'Europe/Paris': 2, 'Asia/Seoul': 9,
  'Asia/Taipei': 8, 'Asia/Singapore': 8, 'Asia/Bangkok': 7,
  'Asia/Jakarta': 7, 'Asia/Kuala_Lumpur': 8, 'Asia/Ho_Chi_Minh': 7,
  'Asia/Kolkata': 5.5, 'America/Sao_Paulo': -3, 'Australia/Sydney': 10,
};

console.log('\n== 1. Transcription still matches the Objective-C ==');

// If the .m file changes and this file does not, the test is validating
// something that is no longer shipped. That drift is the danger.
check('the field list in the .m matches the one executed here',
  (() => {
    const m = objc.match(/NSArray<NSString \*> \*stringFields = @\[([\s\S]*?)\];/);
    if (!m) return false;
    const fromObjc = [...m[1].matchAll(/"([^"]+)"/g)].map(x => x[1]);
    return fromObjc.length === STRING_FIELDS.length
      && fromObjc.every((v, i) => v === STRING_FIELDS[i]);
  })(),
  'update STRING_FIELDS above to match TikTokRegion.m');

check('the MCC length rule in the .m is 3..4',
  /length >= 3 && current\.length <= 4/.test(objc),
  'the JS above encodes the same rule; keep them in step');

console.log('\n== 2. Only fields the app already filled are rewritten ==');

{
  const params = {
    region: 'RU',
    sys_region: 'RU',
    carrier_region: 'RU',
    current_region: 'RU',
    residence: 'RU',
  };
  rewriteParams(params, 'jp', '440', '10');

  check('all five present region fields rewritten',
    ['region', 'sys_region', 'carrier_region', 'current_region', 'residence']
      .every(k => params[k] === 'jp'),
    JSON.stringify(params));
}

{
  // A Russian phone does not send residence/op_region. Inventing them would
  // itself be an anomaly — this is HushFeed's explicit design decision.
  const params = { region: 'RU', device_id: 'abc', app_version: '34.1' };
  rewriteParams(params, 'jp', '440', '10');

  check('absent fields are NOT invented',
    !('residence' in params) && !('current_region' in params) && !('op_region' in params),
    `unexpected keys: ${Object.keys(params).join(', ')}`);
  check('unrelated fields untouched',
    params.device_id === 'abc' && params.app_version === '34.1');
}

{
  // A non-string value means the app sent something else there. Overwriting it
  // would corrupt the field.
  const params = { region: 250, sys_region: null, carrier_region: 'RU' };
  rewriteParams(params, 'jp', '440', '10');

  check('non-string region value is left alone',
    params.region === 250, `became ${JSON.stringify(params.region)}`);
  check('null region value is left alone', params.sys_region === null);
  check('string region value in a mixed map IS rewritten', params.carrier_region === 'jp');
}

console.log('\n== 3. carrier_region_v2 is MCC-gated ==');

{
  const params = { carrier_region_v2: '250', region: 'RU' };
  rewriteParams(params, 'jp', '440', '10');
  check('a 3-digit MCC is replaced', params.carrier_region_v2 === '44010',
    `got ${params.carrier_region_v2}`);
}

{
  // Too long to be an MCC. Overwriting it would put garbage in the field.
  const params = { carrier_region_v2: 'not-an-mcc-value', region: 'RU' };
  rewriteParams(params, 'jp', '440', '10');
  check('a non-MCC value is left intact', params.carrier_region_v2 === 'not-an-mcc-value',
    `got ${params.carrier_region_v2}`);
}

{
  const params = { carrier_region_v2: 'RU', region: 'RU' };
  rewriteParams(params, 'jp', '440', '10');
  check('a 2-letter country code is NOT treated as an MCC',
    params.carrier_region_v2 === 'RU',
    `got ${params.carrier_region_v2} — 2 chars is a country, not a network code`);
}

console.log('\n== 4. Signal consistency ==');

// The region appears in several fields. If only some of them change, the
// request carries contradictory values, which is itself detectable.
{
  const params = {
    region: 'RU', sys_region: 'RU', carrier_region: 'RU',
    current_region: 'RU', residence: 'RU', carrier_region_v2: '250',
    timezone_name: 'Europe/Moscow', timezone_offset: '3',
  };
  rewriteParams(params, 'jp', '440', '10', 'JP');

  const regionValues = ['region', 'sys_region', 'carrier_region', 'current_region', 'residence']
    .map(k => params[k]);
  check('every region field ends up identical',
    new Set(regionValues).size === 1,
    `divergent: ${regionValues.join(', ')}`);

  check('carrier_region_v2 is consistent with the new region',
    params.carrier_region_v2 === '44010');

  // The gap the first run of this test found.
  check('timezone_name is rewritten to a real IANA zone, not the country code',
    params.timezone_name === 'Asia/Tokyo',
    `got ${params.timezone_name}`);
  check('timezone is not the raw country code',
    params.timezone_name !== 'jp' && !params.timezone_name.includes('jp'),
    'writing "jp" into a timezone field is what a naive port would do');
  check('timezone_offset follows the zone',
    params.timezone_offset === '9', `got ${params.timezone_offset}`);
}

{
  // Unknown country: leave the zone alone rather than write garbage.
  const params = { region: 'RU', timezone_name: 'Europe/Moscow' };
  rewriteParams(params, 'jp', '440', '10', 'ZZ');
  check('an unknown country leaves timezone_name alone',
    params.timezone_name === 'Europe/Moscow',
    `got ${params.timezone_name}`);
}

{
  // Same rules for a second target, to catch a hardcoded JPYan assumption.
  const params = {
    region: 'RU', timezone_name: 'Europe/Moscow', timezone_offset: '3',
  };
  rewriteParams(params, 'us', '310', '410', 'US');
  check('a second target region resolves correctly',
    params.region === 'us' && params.timezone_name === 'America/New_York',
    JSON.stringify(params));
}

console.log('\n== 5. Signing-time risk of the configuration ==');

{
  // From the research: X-Gorgon is derived from the query parameters. Changing
  // them invalidates the signature. This is a property of the approach, not a
  // bug in the code, and it is recorded so nobody mistakes this for a working
  // solution by accident.
  const params = { region: 'RU', _signature: 'X-Gorgon: abc123' };
  rewriteParams(params, 'jp', '440', '10');

  check('region changed while the signature was left as-is',
    params.region === 'jp' && params._signature === 'X-Gorgon: abc123');
  console.log('         ^ this dylib does NOT recompute X-Gorgon.');
  console.log('           The server may reject the request. That is the');
  console.log('           documented behaviour of X-Gorgon and is the reason');
  console.log('           whether region rewriting works at all is only');
  console.log('           knowable by running it on a device.');
}

console.log(`\n${'='.repeat(60)}`);
console.log(`passed: ${passed}   failed: ${failed}`);
console.log(`${'='.repeat(60)}\n`);

if (failed) {
  console.log('FAILED CHECKS:');
  for (const f of failures) console.log(`  - ${f.name}${f.detail ? `: ${f.detail}` : ''}`);
  process.exit(1);
}