#!/usr/bin/env node
// Мост между NSDictionary и C-слоем.
//
// Этот файл ПРЕЖДЕ содержал копию логики подмены на JS. Копия могла
// расходиться с исходником — и расходилась. Поведенческие тесты переехали
// в Tools/test-region-logic.c, где исполняется настоящий RegionLogic.h.
//
// Здесь остаётся только то, что нельзя проверить в C: корректность перевода
// представления NSDictionary <---> параллельные массивы.
//
// Запуск настоящих тестов:
//   powershell -ExecutionPolicy Bypass -File Tools\test-region-logic-c.ps1

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');

let passed = 0, failed = 0;
const failures = [];
const check = (name, cond, detail) => {
  if (cond) { passed++; console.log(`  ok   ${name}`); }
  else { failed++; failures.push({ name, detail }); console.log(`  FAIL ${name}${detail ? `\n         ${detail}` : ''}`); }
};

const src = readFileSync(join(ROOT, 'Tweak/TikTokRegion.m'), 'utf8');
const logic = readFileSync(join(ROOT, 'Tweak/RegionLogic.h'), 'utf8');

console.log('\n== 1. Мост NSDictionary -> C ==\n');

check('tt_rewriteParams делегирует в rl_rewrite_params',
  /rl_rewrite_params\s*\(/.test(src),
  'иначе dylib несёт собственную копию правил, которая может разойтись');
check('ObjC включает RegionLogic.h',
  src.includes('../RegionLogic.h'));

// Keys are collected as UTF-8 strings. A key that is not a string must be
// skipped, or strdup(NULL) is undefined behaviour.
check('нестроковые ключи пропускаются',
  /isKindOfClass:\[NSString class\]\].*continue/s.test(src)
  && /calloc\(n, sizeof\(char \*\)\)/.test(src),
  'a non-string key would reach strdup(NULL)');

// Values: a non-string is passed as NULL so the C layer leaves it alone.
check('нестроковые значения передаются как NULL',
  /cVals\[idx\] = NULL/.test(src),
  'otherwise the C layer would see a valid pointer it must not overwrite');

// A NULL value on the way back means "delete the field" (empty live region).
check('NULL-результат трактуруется как удаление поля',
  /if \(cVals\[i\] == NULL\)[\s\S]{0,80}removeObjectForKey/.test(src),
  'HushFeed removes the field when the live value is empty');

// Memory: every strdup must be freed, and the arrays must be freed too.
{
  const strdups = (src.match(/strdup\(/g) || []).length;
  const frees = (src.match(/free\(/g) || []).length;
  check('все strdup освобождаются', frees >= strdups + 2,
    `${strdups} strdup vs ${frees} free — the arrays must be freed too`);
}

console.log('\n== 2. Настоящий C-тест исполняется ==\n');

// The behavioural tests are in C and must actually run here, otherwise
// "44 tests pass" becomes an unverified claim again.
const zigCandidates = [
  process.env.ZIG,
  ...(process.env.LOCALAPPDATA ? [`${process.env.LOCALAPPDATA}\\Programs\\zig\\zig.exe`] : []),
  'C:\\Program Files\\zig\\zig.exe',
];
const foundZig = zigCandidates.find(p => p && existsSync(p)) ?? null;

check('найден C99-компилятор (zig)', foundZig !== null,
  'winget install -e --id zig.zig — без него настоящий RegionLogic.h не исполняется');

if (foundZig) {
  const tmp = join(ROOT, 'rl_test.tmp');
  try {
    execFileSync(foundZig,
      ['cc', '-std=c99', '-Wall', '-Wextra', '-O2',
       join(ROOT, 'Tools/test-region-logic.c'), '-o', tmp],
      { encoding: 'utf8', cwd: ROOT, stdio: ['pipe', 'pipe', 'pipe'] });
    check('RegionLogic.h компилируется чисто (-Wall -Wextra)', true);
  } catch (e) {
    check('RegionLogic.h компилируется чисто (-Wall -Wextra)', false,
      (e.stdout || '') + (e.stderr || ''));
  }

  try {
    const out = execFileSync(tmp, [], { encoding: 'utf8', cwd: ROOT });
    const m = out.match(/passed:\s*(\d+)\s+failed:\s*(\d+)/);
    const n = m ? Number(m[1]) : 0;
    const f = m ? Number(m[2]) : -1;
    check(`настоящий C-тест: ${n} проверок проходят`, n >= 40 && f === 0);
  } catch (e) {
    check('настоящий C-тест исполняется', false,
      (e.stdout || '') + (e.stderr || ''));
  }
}

console.log('\n== 3. Правила в C совпадают с HushFeed ==\n');

check('пишутся только current_region и residence',
  logic.includes('#define RL_FIELD_CURRENT_REGION "current_region"')
  && logic.includes('#define RL_FIELD_RESIDENCE      "residence"'));
check('hub-поля объявлены, но НЕ пишутся циклом',
  logic.includes('#define RL_FIELD_REGION')
  && !logic.includes('RL_FIELD_REGION") == 0'));
check('MCC — ровно 3 цифры', /strlen\(value\) != 3/.test(logic));
check('вход определяется по пути', /RL_SIGN_IN_PATH "passport\/"/.test(logic));
check('при входе восстанавливаются живые sys_region и timezone_name',
  logic.includes('RL_FIELD_SYS_REGION') && logic.includes('RL_FIELD_TIMEZONE_NAME'));
check('пустое живое значение удаляет поле',
  /values\[i\] = NULL;\s*\/\* пустое живое/.test(logic)
  || /removed_count\+\+/.test(logic));

console.log(`\n${'='.repeat(60)}`);
console.log(`passed: ${passed}   failed: ${failed}`);
console.log(`${'='.repeat(60)}\n`);

if (failed) {
  console.log('FAILED CHECKS:');
  for (const f of failures) console.log(`  - ${f.name}${f.detail ? `: ${f.detail}` : ''}`);
  process.exit(1);
}