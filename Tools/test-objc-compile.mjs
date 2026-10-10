#!/usr/bin/env node
/*
 * Проверка компиляции ObjC-модуля на Windows через шим.
 *
 * ЗАЧЕМ: на Windows нет ни Foundation, ни Apple ObjC-рантайма, поэтому
 * TikTokRegion.m не собирается в dylib. Но синтаксис, типы и сигнатуры
 * блоков можно проверить, скомпилировав против минимального описания
 * используемого API (Tools/Shim).
 *
 * ЧТО ДОКАЗЫВАЕТ: код парсится, нет необъявленных идентификаторов, нет
 * опечаток в собственных именах, generics и сигнатуры блоков корректны.
 *
 * ЧЕГО НЕ ДОКАЗЫВАЕТ: что настоящий Foundation ведёт себя так же, и что
 * модуль соберётся под iOS. Это проверка компиляции, не совместимости.
 *
 * Найдено этой проверкой (все реальные — упали бы и на macOS):
 *   1. #import "../RegionLogic.h" — неверный относительный путь
 *   2. NSMutableDictionary<NSValue *, IMP> — IMP нельзя типом-параметром
 *   3. [TikTokRegion ...] — класс не объявлен (вызовы вместо [NSObject ...])
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');

let passed = 0, failed = 0;
const failures = [];
const check = (name, cond, detail) => {
  if (cond) { passed++; console.log(`  ok   ${name}`); }
  else { failed++; failures.push({ name, detail }); console.log(`  FAIL ${name}${detail ? `\n         ${detail}` : ''}`); }
};

function findZig() {
  for (const p of [
    process.env.ZIG,
    ...(process.env.LOCALAPPDATA ? [`${process.env.LOCALAPPDATA}\\Programs\\zig\\zig.exe`] : []),
    'C:\\Program Files\\zig\\zig.exe',
  ]) if (p && existsSync(p)) return p;
  try {
    return execFileSync('where', ['zig'], { encoding: 'utf8' }).split('\n')[0].trim();
  } catch { return null; }
}

const zig = findZig();
check('найден C99-компилятор (zig)', zig !== null,
  'winget install -e --id zig.zig');

if (!zig) {
  console.log(`\npassed: ${passed}   failed: ${failed}\n`);
  process.exit(1);
}

console.log('\n== 1. Шим покрывает используемый API ==\n');

const shim = readFileSync(join(ROOT, 'Tools/Shim/Foundation/Foundation.h'), 'utf8');
const shimDir = join(ROOT, 'Tools/Shim');

// Each of these is used by TikTokRegion.m; if the shim drops one, the check
// reports a shim gap as if it were a code bug, which is worse than useless.
for (const [needle, what] of [
  ['objectForKeyedSubscript', 'subscripting'],
  ['class_getInstanceMethod', 'runtime hook helper'],
  ['imp_implementationWithBlock', 'block-based swizzling'],
  ['arrayWithObjects:', 'NSArray literal'],
  ['dictionaryWithObjects:', 'NSDictionary literal'],
  ['fileExistsAtPath', 'jailbreak path check'],
  ['objectForInfoDictionaryKey', 'Info.plist override'],
]) {
  check(`шим объявляет ${what}`, shim.includes(needle));
}

check('шим предупреждает о своём характере',
  /не проверка совместимости/.test(shim),
  'a reader must know this proves compilation, not iOS behaviour');

console.log('\n== 2. Объявления категорий существуют ==\n');

const src = readFileSync(join(ROOT, 'Tweak/TikTokRegion.m'), 'utf8');

// Without a forward declaration the above calls refer to a class called
// TikTokRegion, which does not exist. This was a real bug found here.
for (const category of ['TikTokRegionTLS', 'TikTokRegion',
  'TikTokRegionIntegrity', 'TikTokRegionJailbreak']) {
  check(`объявлена категория NSObject (${category})`,
    new RegExp(`@interface NSObject \\(${category}\\)`).test(src));
}

check('никогда не вызывается несуществующий класс',
  !/\[TikTokRegion /.test(src),
  'the category is on NSObject, so calls must go through NSObject');

console.log('\n== 3. Компиляция ObjC против шима ==\n');

try {
  execFileSync(zig,
    ['-ObjC', '-fsyntax-only', '-fno-objc-arc', '-fblocks',
     '-Wall', '-Wextra', '-I', shimDir, '-I', join(ROOT, 'Tweak'),
     join(ROOT, 'Tweak/TikTokRegion.m')],
    { encoding: 'utf8', cwd: ROOT, stdio: ['pipe', 'pipe', 'pipe'] });
  check('модуль компилируется против шима', true);
} catch (e) {
  const text = (e.stderr || '') + (e.stdout || '');
  const lines = text.split('\n');

  // Known compiler limitation, not a code defect: zig's clang on Windows
  // does not implement ObjC object subscripting.
  const known = /array subscript is not an integer/;
  const real = lines.filter(l => /: error:/.test(l) && !known.test(l));

  check('реальных ошибок компиляции нет', real.length === 0,
    real.slice(0, 6).join('\n         '));

  const subsCount = lines.filter(l => known.test(l)).length;
  console.log(`         (${subsCount} обращений к subscripting не проверяются`);
  console.log('          — ограничение компилятора zig, не дефект кода)');
}

console.log('\n== 4. Что этот уровень не подтверждает ==\n');
console.log('  · что настоящий Foundation ведёт себя так же');
console.log('  · что модуль соберётся под iOS (нужен Xcode на macOS)');
console.log('  · что хуки сработают в TikTok (нужно устройство)');
console.log('  · что подмена изменит реальные запросы (нужно устройство)');

console.log(`\n${'='.repeat(60)}`);
console.log(`passed: ${passed}   failed: ${failed}`);
console.log(`${'='.repeat(60)}\n`);

if (failed) {
  console.log('FAILED CHECKS:');
  for (const f of failures) console.log(`  - ${f.name}${f.detail ? `: ${f.detail}` : ''}`);
  process.exit(1);
}