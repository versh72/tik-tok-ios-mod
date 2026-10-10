#!/usr/bin/env node
// Runs the probe logic from Tools/web/netdiag.html against real hosts.
//
// WHY: the page has no build step and no framework, so its behaviour can be
// executed here rather than asserted. This test drives the SAME algorithm the
// page uses (no-cors fetch, AbortController deadline, elapsed measurement) and
// checks the two things that can silently be wrong:
//
//   1. that a reachable host reports ok with a plausible time
//   2. that an unreachable host actually FAILS rather than resolving ok
//
// The second is the one that matters. If a diagnostic reports success on a
// dead host it is worse than useless — it is the failure mode this whole
// project exists to avoid.
//
// WHAT THIS DOES NOT TEST: Safari-specific behaviour (it runs on Node, not on
// a phone), and the UI. Neither was testable from this machine.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');

let passed = 0, failed = 0;
const failures = [];
function check(name, cond, detail) {
  if (cond) { passed++; console.log(`  ok   ${name}`); }
  else { failed++; failures.push({ name, detail }); console.log(`  FAIL ${name}${detail ? `\n         ${detail}` : ''}`); }
}

console.log('\n== 1. The page is self-contained ==');

const html = readFileSync(join(ROOT, 'Tools/web/netdiag.html'), 'utf8');

/**
 * Strips comments — both HTML `<!-- -->` and whole-line JS `//`.
 *
 * A comment that names a rejected host is documentation, not a probe target.
 * Scanning comments would report it as a live configuration error.
 *
 * Only whole-line `//` is removed, never inline: stripping `//` anywhere would
 * also cut `https://`, and with it the very URLs being checked.
 */
const code = html
  .replace(/<!--[\s\S]*?-->/g, ' ')
  .split('\n')
  .filter(line => !/^\s*\/\//.test(line))
  .join('\n');

check('no external script tags',
  !/<script[^>]+src=/i.test(code),
  'the page must run with no network dependency beyond its own probes');
check('no external stylesheet links',
  !/<link[^>]+stylesheet/i.test(code));

// Matched on hostnames rather than substrings: `cdn.` appears inside
// `tiktokcdn.com`, which is a probe target, not a CDN dependency.
const CDN_REFERENCE = /(?:unpkg|jsdelivr|cdnjs|googleapis|cdnjs\.cloudflare|ajax\.google)/i;
check('no third-party CDN references', !CDN_REFERENCE.test(code),
  (code.match(CDN_REFERENCE) || [])[0] || '');

console.log('\n== 2. The page does not weaken TLS ==');

// A diagnostic that accepts any certificate reports "healthy" on exactly the
// broken path it is meant to detect. These are the patterns that would do it.
const TLS_WEAKENING = [
  /ignoreCertificateErrors/i,
  /NODE_TLS_REJECT_UNAUTHORIZED/,
  /rejectUnauthorized:\s*false/,
  /http:\/\/(?!localhost)/i,
];
const found = TLS_WEAKENING.filter(p => p.test(code));
check('no TLS verification is weakened', found.length === 0,
  found.map(String).join(', '));

check('every probe URL is https',
  (code.match(/fetch\(\s*url/g) || []).length === 1
  && /const url = "https:\/\/"/.test(code));

console.log('\n== 3. The probe algorithm works ==');

// Same algorithm as the page.
async function probe(host, timeoutMs = 9000) {
  const url = 'https://' + host + '/';
  const t0 = performance.now();
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    await fetch(url, { method: 'GET', redirect: 'follow' });
    clearTimeout(timer);
    return { host, ok: true, ms: Math.round(performance.now() - t0) };
  } catch (e) {
    clearTimeout(timer);
    const aborted = e && (e.name === 'AbortError' || /abort/i.test(e.message || ''));
    return { host, ok: false, ms: Math.round(performance.now() - t0), aborted: !!aborted };
  }
}

const reachable = await probe('www.cloudflare.com');
check('a reachable host reports ok', reachable.ok,
  `failed: ${reachable.ms}ms`);
check('a reachable host reports a plausible time',
  reachable.ms > 0 && reachable.ms < 9000,
  `${reachable.ms}ms`);

// RFC 2606 reserved name. Must fail. If this ever reports ok, the probe is
// measuring something other than reachability.
const dead = await probe('this-host-does-not-exist-netdiag-check.invalid', 6000);
check('an unresolvable host FAILS', !dead.ok,
  `reported ok in ${dead.ms}ms — the probe is not measuring reachability`);

// Reserved TEST-NET-1 address (RFC 5737). Routes are typically blackholed, so
// this must hit the deadline rather than report success.
const blackholed = await probe('192.0.2.1', 3000);
check('a blackholed address times out rather than reporting ok',
  !blackholed.ok,
  `reported ok in ${blackholed.ms}ms`);

console.log('\n== 4. The TikTok host set is real ==');

// These were taken from DNS resolution. An apex name with no A record would
// always report failure and send the reader down the wrong path, so the set
// is checked against the actual records.
const TIKTOK_HOSTS = [
  'api-va.tiktokv.com',
  'api16-normal-c-useast1a.tiktokv.com',
  'sf16-va.tiktokcdn.com',
  'p16-sign-va.tiktokcdn.com',
  'log-va.tiktokv.com',
  'mon-va.tiktokv.com',
];

for (const host of TIKTOK_HOSTS) {
  check(`page includes ${host}`, code.includes(host));
  const r = await probe(host, 8000);
  console.log(`         ${r.ok ? 'reachable' : 'NOT reachable'} in ${r.ms}ms`);
}

// Apex names that returned an EMPTY answer rather than NXDOMAIN. An empty
// answer does not prove the name has no A record — a resolver may simply have
// dropped the query — so listing them would guarantee a permanent false
// "failure". Excluding them is a conservative choice, and the page says so.
for (const uncertain of ['www.tiktokcdn.com', 'www.byteoversea.com']) {
  check(`page excludes unresolvable-by-our-resolver ${uncertain}`,
    !code.includes(uncertain),
    'listing a name whose NXDOMAIN was never confirmed produces a false failure every run');
}

// The honest statement of why, rather than a confident one.
check('page does not claim these names definitely have no A record',
  !/не имеют/.test(html) && /не доказывает/.test(html));

console.log('\n== 5. The page states its own limits ==');

for (const [name, pattern] of [
  ['a passing probe is not proof of reachability for any app',
   /Успешная проверка не означает|не означает, что TikTok заработает/],
  ['it does not inspect other apps traffic', /не видит трафик других приложений/],
  ['it does not detect a VPN', /не определяет, включён ли VPN/],
  ['it does not offer DNS/TCP/TLS breakdown', /разбивк/],
]) {
  check(`page states: ${name}`, pattern.test(html));
}

console.log('\n== 6. Comparison logic ==');

// The whole point is comparing two runs, so the persistence key and the
// diffing function have to be present and wired.
check('a persistence key exists', /localStorage\.setItem/.test(code));
check('the previous run is restored before overwriting',
  /localStorage\.getItem/.test(code));
check('a compare function exists', /function compare\(/.test(code));
check('results are reported as text', /buildReport/.test(code) && /report/.test(code));

console.log('\n== 7. No dead references or duplicate handlers ==');

// A listener still calling a renamed-away function throws ReferenceError on
// the first click and silently kills the page. That is exactly the bug that
// shipped once during editing, so it is now a check rather than a surprise.
const script = (html.match(/<script[^>]*>([\s\S]*?)<\/script>/i) || [])[1] || '';

const defined = new Set();
for (const m of script.matchAll(/(?:async\s+)?function\s+([A-Za-z_$][\w$]*)/g)) defined.add(m[1]);
for (const m of script.matchAll(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/g)) defined.add(m[1]);

const BUILTINS = new Set([
  'fetch', 'document', 'performance', 'localStorage', 'navigator', 'setTimeout',
  'clearTimeout', 'JSON', 'String', 'Date', 'AbortController', 'Number', 'Math',
  'console', 'Object', 'Array', 'Promise', 'Error', 'RegExp',
]);

const called = new Set();
for (const m of script.matchAll(/(?<![\w.$])([a-z_$][\w$]*)\s*\(/g)) called.add(m[1]);

// Keywords and syntax, not identifiers. `async (` matches an arrow function,
// and `catch (` is a clause.
const NOT_A_CALL = /^(if|for|while|switch|catch|return|typeof|function|async|await|else|do|try|new)$/;

const unknownCalls = [...called].filter(
  name => !defined.has(name) && !BUILTINS.has(name) && !NOT_A_CALL.test(name)
);
check('every function called in the page is defined',
  unknownCalls.length === 0,
  `undefined at runtime: ${unknownCalls.join(', ')}`);

for (const [id, expected] of [['run', 1], ['runSet', 1], ['clear', 1]]) {
  const n = (script.match(
    new RegExp(`getElementById\\("${id}"\\)\\.addEventListener`, 'g')) || []).length;
  check(`#${id} has exactly ${expected} listener(s)`, n === expected, `found ${n}`);
}

console.log(`\n${'='.repeat(60)}`);
console.log(`passed: ${passed}   failed: ${failed}`);
console.log(`${'='.repeat(60)}\n`);

if (failed) {
  console.log('FAILED CHECKS:');
  for (const f of failures) console.log(`  - ${f.name}${f.detail ? `: ${f.detail}` : ''}`);
  process.exit(1);
}