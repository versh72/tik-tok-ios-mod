#!/usr/bin/env node
// Static verification harness.
//
// WHY THIS EXISTS
// ---------------
// The Swift sources in this repository were written on a machine with no Swift
// toolchain (no `swift`, no `xcodebuild`, not macOS), so they have NOT been
// compiled. Rather than assert "it builds", this harness checks the
// invariants that can be checked by reading the text: file-manifest integrity,
// forbidden imports, forbidden APIs, secret-shaped literals, and that the test
// files reference symbols that actually exist in the sources.
//
// It does NOT replace `swift build` / `swift test`. It catches the class of
// mistakes that are cheap to make across many files and expensive to find on a
// device. Run `swift test` on macOS for the real thing.

import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, relative, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const PKG = join(ROOT, 'NetDiag');

let passed = 0;
let failed = 0;
const failures = [];

function check(name, condition, detail) {
  if (condition) {
    passed++;
    console.log(`  ok   ${name}`);
  } else {
    failed++;
    failures.push({ name, detail });
    console.log(`  FAIL ${name}${detail ? `\n         ${detail}` : ''}`);
  }
}

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    if (entry === '.git' || entry === '.build' || entry === 'DerivedData') continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

const swiftFiles = walk(PKG).filter(f => extname(f) === '.swift');
const sourceFiles = swiftFiles.filter(f => f.includes(`${sep}Sources${sep}`));
const testFiles = swiftFiles.filter(f => f.includes(`${sep}Tests${sep}`));
const rel = f => relative(ROOT, f).replaceAll('\\', '/');

const read = f => readFileSync(f, 'utf8');

/**
 * Removes comments and string literals from Swift source.
 *
 * Every check below inspects code, not prose. `// MARK: - Host` and a comment
 * saying "NEVPNManager requires a paid account" are documentation, and
 * scanning them would produce failures for text that is supposed to be there.
 */
function codeOnly(swift) {
  return swift
    .replace(/\/\*[\s\S]*?\*\//g, ' ')          // block comments
    .replace(/\/\/[^\n]*/g, ' ')               // line comments
    .replace(/"(?:\\.|[^"\\\n])*"/g, '""')      // string literals
    .replace(/""(?:[^"\n]|"\n)*""/g, '""');     // multi-line string literals
}

const allSourceText = sourceFiles.map(read).join('\n');
const allSourceCode = sourceFiles.map(f => codeOnly(read(f))).join('\n');

console.log('\n== 1. Package structure ==');

const manifestPath = join(PKG, 'Package.swift');
check('Package.swift exists', existsSync(manifestPath));

const manifest = existsSync(manifestPath) ? read(manifestPath) : '';
for (const target of ['NetDiagCore', 'NetDiagEngine', 'NetDiagUI', 'NetDiagCoreTests']) {
  check(`Package.swift declares target ${target}`,
    manifest.includes(`"${target}"`),
    `missing target declaration for ${target}`);
}
check('tools-version is declared',
  /swift-tools-version:\s*5\.\d+/.test(manifest),
  'no swift-tools-version found');

for (const dir of [
  'Sources/NetDiagCore', 'Sources/NetDiagEngine', 'Sources/NetDiagUI', 'Tests/NetDiagCoreTests'
]) {
const full = join(PKG, dir);
  check(`directory ${dir} exists`, existsSync(full));
  if (existsSync(full)) {
    // Recursive: the core keeps its files in subfolders (Models/,
    // Classification/, Redaction/, вЂ¦) rather than flat.
    const count = walk(full).filter(f => f.endsWith('.swift')).length;
    check(`directory ${dir} is non-empty`, count > 0, `${count} swift files`);
  }
}

console.log('\n== 2. Layer boundaries ==');

// The core must stay free of platform frameworks, otherwise the unit tests
// could not run anywhere and `swift test` would need a device.
const coreFiles = sourceFiles.filter(f => f.includes(`NetDiagCore${sep}`));
const forbiddenInCore = [
  ['import SwiftUI', 'SwiftUI'],
  ['import UIKit', 'UIKit'],
  ['import AppKit', 'AppKit'],
  ['import Network', 'Network framework'],
  ['import NetworkExtension', 'NetworkExtension'],
  ['import WebKit', 'WebKit'],
  ['import Security', 'Security'],
];
let coreViolations = [];
for (const file of coreFiles) {
  const code = codeOnly(read(file));
  for (const [needle, label] of forbiddenInCore) {
    if (code.includes(needle)) coreViolations.push(`${rel(file)}: ${label}`);
  }
}
check('NetDiagCore imports no UI or Network framework',
  coreViolations.length === 0,
  coreViolations.join('\n         '));

const engineViolations = [];
for (const file of sourceFiles.filter(f => f.includes(`NetDiagEngine${sep}`))) {
  const code = codeOnly(read(file));
  if (code.includes('import SwiftUI') || code.includes('import UIKit')) {
    engineViolations.push(rel(file));
  }
}
check('NetDiagEngine imports no UI framework', engineViolations.length === 0, engineViolations.join(', '));

const uiViolations = [];
for (const file of sourceFiles.filter(f => f.includes(`NetDiagUI${sep}`))) {
  if (codeOnly(read(file)).includes('import Network\n')) uiViolations.push(rel(file));
}
check('NetDiagUI does not reach around NetDiagEngine into Network',
  uiViolations.length === 0, uiViolations.join(', '));

console.log('\n== 3. Safety invariants ==');

// This is a diagnostic tool. Anything that would let it observe or alter
// traffic belonging to other applications is a design regression, so it is
// checked mechanically rather than trusted to review.
//
// Checked against code with comments and string literals stripped: the
// documentation in this project deliberately names these APIs to explain why
// it does not use them.
const forbiddenAnywhere = [
  [/NSAllowsArbitraryLoads/, 'ATS is not relaxed anywhere: all probes are https'],
  [/URLProtocol\s*\.\s*register|URLProtocol\.registerClass/, 'no URLProtocol interception'],
  [/setVerifyBlock[\s\S]{0,400}?complete\(\s*true\s*\)/, 'TLS verify block never blanket-accepts'],
  [/DYLD_INSERT_LIBRARIES/, 'no dylib injection'],
  [/MobileSubstrate|CydiaSubstrate|MSHookMessageEx|fishhook/, 'no jailbreak tweak API'],
  [/com\.apple\.developer\.networking\.networkextension/, 'no Network Extension entitlement'],
  [/\bNEVPNManager\b|\bNEVPNProtocol\b|packet-tunnel/, 'no VPN configuration API'],
  [/proc\/net\/tcp|tcpdump|SOCK_RAW/, 'no raw packet capture'],
  [/\bSecItemAdd\b|\bSecItemCopyMatching\b/, 'no keychain access'],
];
for (const [pattern, description] of forbiddenAnywhere) {
  check(description, !pattern.test(allSourceCode), `matched ${pattern} in source code`);
}

// Any code path that sets a session-level trust override would silently
// defeat the TLS check above, so look for the delegate methods too.
check('no URLSession trust-challenge override',
  !/didReceive\s+challenge/i.test(allSourceCode),
  'a didReceive challenge implementation would bypass system trust evaluation');

// @main must not be inside a package library target: SwiftPM forbids it.
const mainInLibrary = sourceFiles.filter(f => /@main/.test(read(f)));
check('no @main inside a package library target',
  mainInLibrary.length === 0,
  mainInLibrary.map(rel).join(', '));

const appEntry = join(ROOT, 'App', 'TikTokNetDiagApp.swift');
check('app entry point exists outside the package', existsSync(appEntry));
if (existsSync(appEntry)) check('app entry point declares @main', read(appEntry).includes('@main'));

// ATS: the app must not disable App Transport Security.
const infoPlist = join(ROOT, 'App', 'Info.plist');
check('Info.plist exists', existsSync(infoPlist));
if (existsSync(infoPlist)) {
  const plist = read(infoPlist);
  check('Info.plist does not disable ATS',
    !plist.includes('NSAppTransportSecurity') && !plist.includes('NSAllowsArbitraryLoads'));
}

console.log('\n== 4. Secret-shaped literals ==');

// A literal token, password or e-mail committed into a source file would be a
// real leak.
//
// Scoped to the shipped targets only. The test suite necessarily contains
// synthetic credentials вЂ” they are the input the redaction tests feed in вЂ” so
// scanning tests for this pattern would report the fixtures as leaks. Those
// are checked separately, below, for being recognisably fake.
const secretPatterns = [
  [/\b(?:password|passwd|pwd)\s*=\s*["'][^"']{4,}["']/i, 'hardcoded password assignment'],
  [/\bBearer\s+[A-Za-z0-9._-]{20,}/, 'hardcoded bearer token'],
  [/\bAKIA[0-9A-Z]{16}\b/, 'AWS access key id'],
  [/\bghp_[A-Za-z0-9]{36}\b/, 'GitHub token'],
  [/\bsk-[A-Za-z0-9]{32,}\b/, 'secret key'],
  [/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.(?:com|org|net|ru)\b/i, 'e-mail address literal'],
];
const secretHits = [];
for (const file of sourceFiles) {
  const lines = read(file).split('\n');
  lines.forEach((line, i) => {
    if (/^\s*(\/\/|\*)/.test(line)) return; // comments intentionally contain such words
    for (const [pattern, description] of secretPatterns) {
      if (pattern.test(line)) secretHits.push(`${rel(file)}:${i + 1} ${description}`);
    }
  });
}
check('no secret-shaped literals in shipped source',
  secretHits.length === 0, secretHits.join('\n         '));

// Test fixtures must be obviously synthetic: if a real credential ever gets
// pasted into a test to reproduce a bug, it must not be committed.
const REALISTIC_CREDENTIAL = [
  /\bAKIA[0-9A-Z]{16}\b/,
  /\bgh[pousr]_[A-Za-z0-9]{30,}\b/,
  /\b[xoxabprs]-[0-9A-Za-z-]{20,}\b/,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
];
const fixtureHits = [];
for (const file of testFiles) {
  const text = read(file);
  for (const pattern of REALISTIC_CREDENTIAL) {
    if (pattern.test(text)) fixtureHits.push(`${rel(file)}: ${pattern}`);
  }
}
check('no realistic credential formats in test fixtures',
  fixtureHits.length === 0, fixtureHits.join('\n         '));

console.log('\n== 5. Test-to-source coherence ==');

// Every type a test names must exist in the sources. Catches the most common
// cross-file break, which is a rename on one side only.
const declaredTypes = new Set();
for (const file of sourceFiles) {
  const text = read(file);
  for (const m of text.matchAll(/\b(?:struct|class|enum|protocol|extension)\s+([A-Z][A-Za-z0-9_]*)/g)) {
    declaredTypes.add(m[1]);
  }
}
check('source declares a non-trivial number of types',
  declaredTypes.size >= 20, `only found ${declaredTypes.size}`);

// Names provided by the standard library, XCTest or SwiftUI that a test may
// legitimately use without them existing in this package.
const externalNames = new Set([
  'XCTAssert', 'XCTAssertEqual', 'XCTAssertTrue', 'XCTAssertFalse', 'XCTAssertNil',
  'XCTAssertNotNil', 'XCTAssertThrowsError', 'XCTAssertNoThrow', 'XCTUnwrap',
  'XCTAssertGreaterThan', 'XCTAssertLessThan', 'XCTAssertNotEqual',
  'XCTFail', 'XCTestCase', 'Foundation',
  // Swift and Foundation types a test may use without this package declaring them.
  'String', 'Set', 'Array', 'Result', 'Error', 'Date', 'URL', 'TimeInterval',
  'UInt16', 'POSIXErrorCode', 'URLError', 'UUID', 'Int', 'Bool', 'Double',
  'NSLock', 'DispatchQueue', 'Locale', 'SwiftUI',
]);

// Identifiers are only harvested from type positions, not from prose: a bare
// scan would pick up every word in a `// MARK: - Happy path` comment and every
// fragment of a string literal.
const TYPE_POSITIONS = [
  /:\s*([A-Z][A-Za-z0-9_]*)/g,        // annotation: TypeName
  /\bas[?!]?\s+([A-Z][A-Za-z0-9_]*)/g, // cast: as TypeName
  /\bnew\s+([A-Z][A-Za-z0-9_]*)/g,
  /\b([A-Z][A-Za-z0-9_]*)\s*\(/g,      // construction: TypeName(
  /\bas[?!]?\s*\{/g,                   // (marker so the cast branch above runs)
];

const referencedTypes = new Set();
const locallyDefined = new Set();
for (const file of testFiles) {
  const text = read(file);
  // Anything the test file declares itself is not expected in the sources.
  for (const m of text.matchAll(/\b(?:struct|class|enum)\s+([A-Z][A-Za-z0-9_]*)/g)) {
    locallyDefined.add(m[1]);
  }
  const code = codeOnly(text);
  for (const pattern of TYPE_POSITIONS) {
    for (const m of code.matchAll(pattern)) {
      referencedTypes.add(m[1]);
    }
  }
}

const unknownRefs = [...referencedTypes].filter(
  name => !declaredTypes.has(name)
    && !locallyDefined.has(name)
    && !externalNames.has(name)
    && !name.startsWith('NS')
);
check('every type named by a test exists in the sources or the test file',
  unknownRefs.length === 0,
  unknownRefs.length ? unknownRefs.join(', ') : '');

// The XCTest classes must all be present and named consistently.
const testClassCount = testFiles.filter(f => /:\s*XCTestCase/.test(read(f))).length;
check('test files declare XCTestCase subclasses',
  testClassCount >= 6, `found ${testClassCount} test classes in ${testFiles.length} files`);

const xctAssertCount = testFiles.reduce(
  (sum, f) => sum + (read(f).match(/\bXCTAssert\w*/g) || []).length, 0);
check('test suite contains assertions', xctAssertCount >= 80, `found ${xctAssertCount} assertions`);

console.log('\n== 6. Protocol conformance of the fakes ==');

const coreText = coreFiles.map(read).join('\n');
for (const protocol of ['DNSResolving', 'TLSProbing', 'HTTPSProbing']) {
  check(`protocol ${protocol} is declared`, coreText.includes(`protocol ${protocol}`));
}
const coordinatorPresent = existsSync(join(PKG, 'Sources/NetDiagCore/Engines/ProbeCoordinator.swift'));
check('ProbeCoordinator lives in the testable core', coordinatorPresent);

// The fakes in the test file must actually satisfy the protocols.
const coordinatorTests = testFiles.find(f => read(f).includes('ProbeCoordinatorTests'));
if (coordinatorTests) {
  const text = codeOnly(read(coordinatorTests));
  for (const [fake, protocol] of [
    ['StubDNS', 'DNSResolving'],
    ['StubTLS', 'TLSProbing'],
    ['StubHTTPS', 'HTTPSProbing'],
  ]) {
    check(`${fake} conforms to ${protocol}`,
      new RegExp(`struct\\s+${fake}\\s*:\\s*${protocol}`).test(text),
      `${fake} does not declare conformance to ${protocol}`);
  }
}

console.log('\n== 7. Disclaimer presence ==');

// The central claim of the tool is that a passing probe does not prove an
// application works. That text must exist in the sources, not only in prose.
check('probe-is-not-proof disclaimer exists in sources',
  coreText.includes('does not establish'));
check('no-traffic-inspection disclaimer exists in sources',
  coreText.includes('does not read, log, intercept') || coreText.includes('РЅРµ С‡РёС‚Р°РµС‚, РЅРµ Р¶СѓСЂРЅР°Р»РёСЂСѓРµС‚'));
check('VPN-not-observable caveat exists in sources',
  coreText.includes('does not report whether a VPN is active'));

const disclaimerInReport = read(join(PKG, 'Sources/NetDiagCore/Report/ReportBuilder.swift'));
check('report embeds the disclaimer fields',
  disclaimerInReport.includes('disclaimerProbeIsNotAppProof')
  && disclaimerInReport.includes('disclaimerNoTrafficInspection'));

console.log('\n== 8. Documentation files ==');
for (const doc of [
  'README.md', 'RESEARCH.md', 'ARCHITECTURE.md', 'COMPATIBILITY.md',
  'PLAN.md', 'CI-BUILD.md',
  'ANDROID_ANALYSIS.md', 'IOS_ANALYSIS.md', 'IMPLEMENTATION_PLAN.md',
]) {
  const path = join(ROOT, doc);
  check(`${doc} exists`, existsSync(path));
  if (existsSync(path)) {
    check(`${doc} is non-trivial`, statSync(path).size > 1500, `${statSync(path).size} bytes`);
  }
}
check('COMPATIBILITY.md marks unverified rows as UNKNOWN',
  existsSync(join(ROOT, 'COMPATIBILITY.md'))
  && read(join(ROOT, 'COMPATIBILITY.md')).includes('UNKNOWN'));

// The no-Mac route is the one most people will actually take. It has to say
// so at the top of the README, not be buried.
const readme = read(join(ROOT, 'README.md'));
check('README leads with the no-Mac route', readme.includes('CI-BUILD.md'));
check('README states Xcode is macOS-only', /macOS-only/i.test(readme));
check('CI-BUILD.md states Swift Playgrounds is iPad-only',
  /iPad only/i.test(read(join(ROOT, 'CI-BUILD.md'))));

console.log('\n== 8b. Feasibility claims must stay evidence-backed ==');

// The central research conclusion is that an iOS mod is not achievable. That
// claim is only worth making if the supporting facts are recorded next to it.
const android = read(join(ROOT, 'ANDROID_ANALYSIS.md'));
const ios = read(join(ROOT, 'IOS_ANALYSIS.md'));
const arch = read(join(ROOT, 'ARCHITECTURE.md'));

check('Android analysis names the mechanism layer, not just the project',
  /TelephonyManager/.test(android) && /f_global_/.test(android));
check('Android analysis quotes HushFeed, the most complete implementation',
  android.includes('HushFeed') && /requestParams\(Map params\)/.test(android));
check('Android analysis records the negative result about tunnelling',
  /не маршрутизир/i.test(android),
  'the finding that no mod routes traffic is the load-bearing one');

// The correction to that finding. It was made after measuring the RU path, and
// the reasoning has to stay in the file, or the next reader will repeat the
// original mistake: reading an author's risk warning as proof of uselessness.
check('Android analysis records the CORRECTION to that finding',
  /ПОПРАВКА/.test(android) && /неверный вывод/.test(android),
  'the corrected conclusion must stay next to the original, not replace it silently');
check('Android analysis carries the measurement that drove the correction',
  /94\.243\.11\.85/.test(android) && /sf16-va\.tiktokcdn\.com/.test(android));
check('Android analysis states the measured scope rather than a global claim',
  /Что это доказывает/.test(android) && /маршрут до перечисленных хостов работает/.test(android),
  'the correction must say what was measured, not swap one overstatement for another');
check('iOS analysis points at the MITM alternative rather than a dead end',
  /прокси|MITM/i.test(ios) && /перехват/i.test(ios));
check('Android analysis states the apkw.ru APK was NOT downloaded',
  /UNVERIFIED/.test(android) && !/я скачал APK/i.test(android),
  'the APK contents were never verified and must not be implied otherwise');

check('iOS analysis cites the Team ID enforcement rule',
  /team identifier/i.test(ios));
check('iOS analysis records the TrollStore version ceiling',
  /17\.0/.test(ios) && /27\.0\.1/.test(ios),
  'both the ceiling and the current version must be present for the gap to be readable');
check('iOS analysis names the actual exploits, not a vague reference',
  /CVE-2022-26766/.test(ios) && /CVE-2023-41991/.test(ios));
check('iOS analysis states TrollStore is not a jailbreak',
  /не.*jailbreak|not a jailbreak|Is not a jailbreak/i.test(ios) || ios.includes('TrollStore is a'));

check('architecture carries the required hypothesis table',
  /Гипотеза/.test(arch) && /Подтверждение/.test(arch) && /Ограничения/.test(arch) && /Вывод/.test(arch));
check('architecture does not substitute a web client or another social network',
  /Веб-клиент/.test(arch) && /подменяет цель/.test(arch),
  'the brief forbids substituting a web client; the refusal must be explicit');
check('architecture explains why the diagnostic is not a substitute',
  /не подменяет/.test(arch) || /не подменяет цель/.test(arch));

// The six verification levels must be stated somewhere. Without them a reader
// sees "199 tests passing" and reasonably assumes the tweak works.
check('VERIFICATION.md exists and states the six levels',
  existsSync(join(ROOT, 'VERIFICATION.md'))
  && /Шесть уровней|уровней/.test(read(join(ROOT, 'VERIFICATION.md'))));
const verification = existsSync(join(ROOT, 'VERIFICATION.md'))
  ? read(join(ROOT, 'VERIFICATION.md')) : '';
check('VERIFICATION.md admits compilation was not achieved',
  /Компиляция/.test(verification) && /не достигнут/.test(verification),
  'claiming a higher level than was reached is the exact failure being guarded');
check('VERIFICATION.md records that build.sh syntax was never checked',
  /build\.sh/.test(verification) && /синтаксически не проверен/.test(verification),
  'a check that silently failed is worse than one that was never attempted');

// The overstatement corrected during audit must not come back.
check('Android analysis no longer claims absence of DPI',
  !/Блокировок и DPI нет/.test(android),
  'this was measured only at the / path; selective filtering was never tested');
check('Android analysis distinguishes what was measured from what was not',
  /Чего это НЕ доказывает/.test(android));
check('Android analysis records the DNS resolver contamination',
  /172\.19\.0\.2/.test(android),
  'every DNS observation in this project was made by the proxy resolver');

console.log('\n== 9. Cloud build workflow ==');

const workflowPath = join(ROOT, '.github', 'workflows', 'build-ios.yml');
check('GitHub Actions workflow exists', existsSync(workflowPath));

if (existsSync(workflowPath)) {
  const workflow = read(workflowPath);
  const workflowCode = workflow
    .replace(/\$[#][^\n]*/g, ' ')     // strip comments
    .replace(/"(?:[^"\\\n])*"/g, '""'); // strip literal strings

  check('workflow runs on a macOS runner', /runs-on:\s*macos/.test(workflow));
  check('workflow runs swift test',
  /swift\s+test/.test(workflow),
  'the whole point of the cloud route is that it runs the real test suite');
  check('workflow builds for the iphoneos SDK', /-sdk\s+iphoneos/.test(workflow));
  check('workflow disables code signing',
    /CODE_SIGNING_ALLOWED=NO/.test(workflow) && /CODE_SIGN_IDENTITY=/.test(workflow),
    'signing belongs on the owner\'s machine, not in CI');
  check('workflow targets arm64', /ARCHS=arm64/.test(workflow));
  check('workflow packages a Payload directory', /Payload/.test(workflow));
  check('workflow uploads an artifact',
    /actions\/upload-artifact/.test(workflow) && /\.ipa/.test(workflow));

  // The critical safety property: an Apple Account password must never end up
  // in a repository, and therefore must never be a CI secret.
  const credentialLeaks = [
    /secrets\.[A-Z_]*(APPLE|PASSWORD|PASSWD|ITUNES)[A-Z_]*/,
    /APPLE_ID_PASSWORD/i,
    /APPLE_ID\b/,
    /FASTLANE_PASSWORD/i,
    /MATCH_PASSWORD/i,
  ];
  const leaks = credentialLeaks.filter(p => p.test(workflowCode));
  check('workflow contains no Apple ID or password reference',
    leaks.length === 0,
    leaks.map(String).join(', '));

  check('CI-BUILD.md explains the unsigned-build split',
    /never leaves your machine|never reaches the cloud|never goes\s+anywhere near the cloud/i
      .test(read(join(ROOT, 'CI-BUILD.md'))));
}

const projectSpecPath = join(ROOT, 'project.yml');
check('project.yml exists', existsSync(projectSpecPath));
if (existsSync(projectSpecPath)) {
  const spec = read(projectSpecPath);
  check('project.yml declares the app target', spec.includes('TikTokNetDiag'));
  check('project.yml points at the local package', /path:\s*NetDiag/.test(spec));
  check('project.yml declares a scheme for CI to build',
    /schemes:/.test(spec) && /TikTokNetDiag:/.test(spec),
    'xcodebuild -scheme needs a scheme XcodeGen generates from this');
}

console.log('\n== 10. Repository hygiene ==');

// The four researched repositories were cloned locally for analysis. This
// checks that none of them were vendored into the deliverable, which would
// import someone else's licence terms into this project.
const researchDir = join(ROOT, '.research');
check('no vendored copy of a researched repo in the deliverable',
  !existsSync(researchDir),
  '.research directory found in the project root');

// Dependency directories must never be committed: they pull code and add
// licence terms that this project has not reviewed.
check('no node_modules committed', !existsSync(join(ROOT, 'node_modules')));
check('no package-lock.json committed', !existsSync(join(ROOT, 'package-lock.json')));
check('a .gitignore excludes build output',
  existsSync(join(ROOT, '.gitignore'))
  && /node_modules|\.build|DerivedData|\.ipa/.test(read(join(ROOT, '.gitignore'))),
  'missing .gitignore, or it does not cover node_modules/.build/.ipa');

// A stray .ipa or .app in the tree would be a signed artefact that should
// never be committed.
const signedArtifacts = walk(ROOT).filter(f => /\.(ipa|app|mobileprovision|p12)$/.test(f));
check('no signed build artefacts committed', signedArtifacts.length === 0,
  signedArtifacts.map(rel).join(', '));

console.log(`\n${'='.repeat(60)}`);
console.log(`passed: ${passed}   failed: ${failed}`);
console.log(`${'='.repeat(60)}\n`);

if (failed > 0) {
  console.log('FAILED CHECKS:');
  for (const f of failures) console.log(`  - ${f.name}${f.detail ? `: ${f.detail}` : ''}`);
  process.exit(1);
}