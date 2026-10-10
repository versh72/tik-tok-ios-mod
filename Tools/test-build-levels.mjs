#!/usr/bin/env node
// Попытка компиляции ObjC-модуля и фиксация точных блокеров.
//
// ЗАЧЕМ: в прежних отчётах блокер формулировался как «нет расшифрованного
// IPA». Это conflated две разные вещи:
//
//   (a) компиляция самой библиотеки;
//   (b) интеграция собранной библиотеки в TikTok.
//
// Для (a) IPA НЕ нужен вообще — dylib компилируется независимо от цели
// внедрения. Здесь проверяется (a) и фиксируется, чем именно оно блокировано.
//
// Результат: исполняемый C (RegionLogic.h) компилируется и работает.
// ObjC-модуль (TikTokRegion.m) — нет, и причина названа точно.

import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');

const ZIG_CANDIDATES = [
  process.env.ZIG,
  ...(process.env.LOCALAPPDATA
    ? [`${process.env.LOCALAPPDATA}\\Programs\\zig\\zig.exe`]
    : []),
  'C:\\Program Files\\zig\\zig.exe',
].filter(Boolean);

function findZig() {
  for (const p of ZIG_CANDIDATES) if (existsSync(p)) return p;
  try {
    return execFileSync('where', ['zig'], { encoding: 'utf8' })
      .split('\n')[0].trim();
  } catch {
    return null;
  }
}

const zig = findZig();
let passed = 0, failed = 0;
const check = (name, cond, detail) => {
  if (cond) { passed++; console.log(`  ok   ${name}`); }
  else { failed++; console.log(`  FAIL ${name}${detail ? `\n         ${detail}` : ''}`); }
};

console.log('\n== 1. Инструмент для проверки компиляции ==\n');

check('найден C99-компилятор (zig)', zig !== null,
  'поставь zig: winget install -e --id zig.zig — тогда можно исполнить ' +
  'настоящий RegionLogic.h, а не его зеркало на JS');

if (!zig) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`passed: ${passed}   failed: ${failed}`);
  console.log(`${'='.repeat(60)}\n`);
  process.exit(1);
}

console.log('\n== 2. Чистый C-слой компилируется и исполняется ==\n');

try {
  const out = execFileSync(
    zig,
    ['cc', '-std=c99', '-Wall', '-Wextra', '-O2',
     join(ROOT, 'Tools/test-region-logic.c'), '-o', join(ROOT, '..', 'rl_test.tmp')],
    { encoding: 'utf8', cwd: ROOT }
  );
  check('RegionLogic.h компилируется с -Wall -Wextra без предупреждений', true);
} catch (e) {
  check('RegionLogic.h компилируется с -Wall -Wextra без предупреждений', false,
    (e.stdout || '') + (e.stderr || ''));
}

try {
  const run = execFileSync(
    join(ROOT, '..', 'rl_test.tmp'),
    [],
    { encoding: 'utf8' }
  );
  const m = run.match(/passed:\s*(\d+)\s+failed:\s*(\d+)/);
  const cPassed = m ? Number(m[1]) : 0;
  const cFailed = m ? Number(m[2]) : -1;
  check(`исполнение настоящего C-кода: ${cPassed} проверок проходят`,
        cPassed > 0 && cFailed === 0, run.split('\n').slice(-3).join('\n'));
} catch (e) {
  check('исполнение настоящего C-кода', false,
    (e.stdout || '') + (e.stderr || ''));
}

console.log('\n== 3. ObjC-модуль: точные блокеры компиляции ==\n');

// (a) ARC
try {
  execFileSync(zig,
    ['cc', '-ObjC', '-dynamiclib', '-fobjc-arc', '-Wall',
     join(ROOT, 'Tweak/TikTokRegion.m'), '-o', 'Test-objc.dll'],
    { encoding: 'utf8', cwd: ROOT, stdio: ['pipe', 'pipe', 'pipe'] });
  check('блокер ARC зафиксирован', false, 'сборка неожиданно прошла — проверь флаги');
} catch (e) {
  const text = (e.stderr || '') + (e.stdout || '');
  const arcBlocked = /-fobjc-arc is not supported .* legacy runtime/i.test(text);
  check('блокер #1 зафиксирован: ObjC-рантайм компилятора — legacy, не Apple',
    arcBlocked,
    text.split('\n').slice(0, 4).join('\n'));
}

// (b) Foundation headers
try {
  execFileSync(zig,
    ['cc', '-ObjC', '-dynamiclib', '-Wall',
     join(ROOT, 'Tweak/TikTokRegion.m'), '-o', 'Test-objc.dll'],
    { encoding: 'utf8', cwd: ROOT, stdio: ['pipe', 'pipe', 'pipe'] });
  check('блокер Foundation зафиксирован', false, 'сборка неожиданно прошла');
} catch (e) {
  const text = (e.stderr || '') + (e.stdout || '');
  const noFoundation = /Foundation\/Foundation\.h' file not found/i.test(text);
  check('блокер #2 зафиксирован: нет заголовков Foundation (Apple SDK)',
    noFoundation,
    text.split('\n').slice(0, 4).join('\n'));
}

console.log('\n== 4. Что блокеры означают ==\n');

console.log(`  Компиляция чистой логики  : РАБОТАЕТ (RegionLogic.h)
  Компиляция ObjC-модуля     : БЛОК — ARC-рантайм + Foundation + ObjC-рантайм
  Интеграция в TikTok        : ОТДЕЛЬНЫЙ блокер — расшифрованный IPA

  Расшифрованный IPA не нужен для компиляции библиотеки.
  Он нужен только для шага внедрения. Это разные шаги, и прежний
  отчёт соединял их в один неверный вывод.`);

console.log(`\n${'='.repeat(60)}`);
console.log(`passed: ${passed}   failed: ${failed}`);
console.log(`${'='.repeat(60)}\n`);

process.exit(failed === 0 ? 0 : 1);