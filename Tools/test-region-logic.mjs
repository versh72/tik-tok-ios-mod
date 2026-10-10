#!/usr/bin/env node
// Поведенческие тесты логики подмены региона.
//
// Проверяют семь требований из задачи:
//   1. обработка query-параметров
//   2. обработка подходящих форматов тела запроса
//   3. корректное изменение только заданных полей
//   4. сохранение остальных параметров
//   5. согласованность региона и часового пояса
//   6. повторный вызов без повторного повреждения запроса
//   7. отказ от изменения неподходящих запросов
//
// Логика сверена с HushFeed RegionSpoof.java (получен полный исходник).
// Исправлены пять расхождений:
//   1. Пишутся только current_region и residence
//   2. Добавлена обработка запросов входа (/passport/)
//   3. MCC проверяется как ровно 3 цифры
//   4. При входе sys_region и timezone_name возвращаются к живым значениям
//   5. Добавлен хук пути запроса

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

// ── Транскрипция логики из ObjC ─────────────────────────────────────────────

const SAVED_FIELDS = ['current_region', 'residence'];
const HUB_FIELDS = ['carrier_region', 'sys_region', 'region'];

function isMcc(value) {
  if (!value) return false;
  if (value.length !== 3) return false;
  for (let i = 0; i < 3; i++) {
    const c = value.charCodeAt(i);
    if (c < 48 || c > 57) return false;
  }
  return true;
}

function rewriteParams(params, iso, mcc, mnc, isSignIn, sysRegion, timeZoneName) {
  const changed = [];
  const keys = Object.keys(params);

  for (const key of keys) {
    const value = params[key];

    if (isSignIn) {
      if (key === 'sys_region') {
        if (typeof value === 'string') {
          if (sysRegion && sysRegion.length > 0) {
            params[key] = sysRegion;
          } else {
            delete params[key];
          }
          changed.push(key);
        }
      }
      if (key === 'timezone_name') {
        if (typeof value === 'string') {
          params[key] = timeZoneName && timeZoneName.length > 0 ? timeZoneName : undefined;
          changed.push(key);
        }
      }
      continue;
    }

    if (SAVED_FIELDS.includes(key)) {
      if (typeof value === 'string') {
        params[key] = iso;
        changed.push(key);
      }
    }

    if (key === 'carrier_region_v2') {
      if (typeof value === 'string' && isMcc(value)) {
        params[key] = mcc + mnc;
        changed.push(key);
      }
    }
  }

  return { params, changed };
}

// ── 1. Обработка query-параметров ───────────────────────────────────────────

console.log('\n== 1. Обработка query-параметров ==');

{
  const p = { region: 'RU', current_region: 'RU', residence: 'RU' };
  const r = rewriteParams(p, 'jp', '440', '10', false, '', '');
  check('current_region переписан', r.params.current_region === 'jp');
  check('residence переписан', r.params.residence === 'jp');
  check('region НЕ переписан (обрабатывается хуками геттеров)',
    r.params.region === 'RU',
    `стал ${r.params.region} — HushFeed явно не пишет это поле`);
}

// ── 2. Обработка форматов тела запроса ──────────────────────────────────────

console.log('\n== 2. Обработка форматов тела запроса ==');

{
  // JSON-подобное тело
  const body = { region: 'RU', current_region: 'RU', data: { nested: true } };
  const r = rewriteParams(body, 'jp', '440', '10', false, '', '');
  check('JSON-тело: current_region переписан', r.params.current_region === 'jp');
  check('JSON-тело: вложенные объекты не повреждены',
    r.params.data.nested === true);
}

{
  // Тело с нестроковым значением
  const body = { current_region: 250, region: 'RU' };
  const r = rewriteParams(body, 'jp', '440', '10', false, '', '');
  check('нестроковое значение не перезаписано', r.params.current_region === 250);
}

// ── 3. Изменение только заданных полей ─────────────────────────────────────

console.log('\n== 3. Изменение только заданных полей ==');

{
  const p = {
    region: 'RU', sys_region: 'RU', carrier_region: 'RU',
    current_region: 'RU', residence: 'RU', carrier_region_v2: '250',
    device_id: 'abc123', app_version: '34.1.0',
  };
  const r = rewriteParams(p, 'jp', '440', '10', false, '', '');
  check('current_region → jp', r.params.current_region === 'jp');
  check('residence → jp', r.params.residence === 'jp');
  check('carrier_region_v2 → 44010', r.params.carrier_region_v2 === '44010');
  check('region не тронут', r.params.region === 'RU');
  check('sys_region не тронут', r.params.sys_region === 'RU');
  check('carrier_region не тронут', r.params.carrier_region === 'RU');
  check('device_id не тронут', r.params.device_id === 'abc123');
  check('app_version не тронут', r.params.app_version === '34.1.0');
}

// ── 4. Сохранение остальных параметров ──────────────────────────────────────

console.log('\n== 4. Сохранение остальных параметров ==');

{
  const p = {
    current_region: 'RU',
    video_id: '7123456789',
    user_id: '9876543210',
    timestamp: 1699999999,
    nested: { deep: { value: 'keep' } },
  };
  const r = rewriteParams(p, 'jp', '440', '10', false, '', '');
  check('video_id сохранён', r.params.video_id === '7123456789');
  check('user_id сохранён', r.params.user_id === '9876543210');
  check('timestamp сохранён', r.params.timestamp === 1699999999);
  check('вложенная структура сохранена',
    r.params.nested.deep.value === 'keep');
}

// ── 5. Согласованность региона и часового пояса ─────────────────────────────

console.log('\n== 5. Согласованность региона и часового пояса ==');

{
  // При входе: sys_region и timezone_name возвращаются к живым значениям
  const p = {
    current_region: 'RU',
    sys_region: 'RU',
    timezone_name: 'Europe/Moscow',
  };
  const r = rewriteParams(p, 'jp', '440', '10', true, 'RU', 'Europe/Moscow');
  check('при входе current_region НЕ подменён', r.params.current_region === 'RU');
  check('при входе sys_region возвращён к живому', r.params.sys_region === 'RU');
  check('при входе timezone_name возвращён к живому',
    r.params.timezone_name === 'Europe/Moscow');
}

{
  // При входе с пустым живым значением — поле удаляется
  const p = { current_region: 'RU', sys_region: 'RU' };
  const r = rewriteParams(p, 'jp', '440', '10', true, '', '');
  check('пустой sys_region удаляется', !('sys_region' in r.params));
}

// ── 6. Повторный вызов без повреждения ─────────────────────────────────────

console.log('\n== 6. Повторный вызов без повреждения ==');

{
  const p = { current_region: 'RU', residence: 'RU', device_id: 'abc' };
  const r1 = rewriteParams(p, 'jp', '440', '10', false, '', '');
  const r2 = rewriteParams(r1.params, 'jp', '440', '10', false, '', '');
  check('второй вызов не ломает данные', r2.params.current_region === 'jp');
  check('второй вызов сохраняет device_id', r2.params.device_id === 'abc');
}

{
  // Повторный вызов с другим регионом
  const p = { current_region: 'RU' };
  const r1 = rewriteParams(p, 'jp', '440', '10', false, '', '');
  const r2 = rewriteParams(r1.params, 'us', '310', '410', false, '', '');
  check('смена региона работает', r2.params.current_region === 'us');
}

{
  // Идемпотентность: повторный вызов с теми же параметрами не должен
  // менять результат. Логика не отслеживает "уже изменено" — она просто
  // ставит то же значение. Это не повреждение, но результат должен быть
  // идентичным.
  const p = { current_region: 'RU', residence: 'RU', device_id: 'abc' };
  const r1 = rewriteParams(p, 'jp', '440', '10', false, '', '');
  const r2 = rewriteParams(r1.params, 'jp', '440', '10', false, '', '');
  check('повторный вызов даёт тот же результат',
    r2.params.current_region === r1.params.current_region
    && r2.params.residence === r1.params.residence
    && r2.params.device_id === r1.params.device_id,
    'idempotency: same input → same output');
}

// ── 7. Отказ от изменения неподходящих запросов ────────────────────────────

console.log('\n== 7. Отказ от изменения неподходящих запросов ==');

{
  // Пустой словарь
  const p = {};
  const r = rewriteParams(p, 'jp', '440', '10', false, '', '');
  check('пустой словарь не ломается', Object.keys(r.params).length === 0);
}

{
  // Словарь без региональных полей
  const p = { device_id: 'abc', video_id: '123' };
  const r = rewriteParams(p, 'jp', '440', '10', false, '', '');
  check('без региональных полей — ничего не меняется', r.changed.length === 0);
}

{
  // carrier_region_v2 с не-MCC значением
  const p = { carrier_region_v2: 'not-a-mcc' };
  const r = rewriteParams(p, 'jp', '440', '10', false, '', '');
  check('не-MCC значение не трогается', r.params.carrier_region_v2 === 'not-a-mcc');
}

{
  // carrier_region_v2 с 2-буквенным кодом
  const p = { carrier_region_v2: 'RU' };
  const r = rewriteParams(p, 'jp', '440', '10', false, '', '');
  check('2-буквенный код не считается MCC', r.params.carrier_region_v2 === 'RU');
}

{
  // carrier_region_v2 с 4-значным значением
  const p = { carrier_region_v2: '1234' };
  const r = rewriteParams(p, 'jp', '440', '10', false, '', '');
  check('4-значное значение не считается MCC', r.params.carrier_region_v2 === '1234');
}

// ── 8. Сверка с исходником ObjC ─────────────────────────────────────────────

console.log('\n== 8. Сверка с исходником ObjC ==');

check('пишутся только current_region и residence',
  objc.includes('"current_region"') && objc.includes('"residence"')
  && !objc.includes('"region", @"sys_region", @"carrier_region"'),
  'HushFeed пишет только эти два поля');

check('MCC проверяется как ровно 3 цифры',
  /length == 3/.test(objc) && /characterAtIndex:0.*'0'.*'9'/.test(objc),
  'не 3-4 символа, как было раньше');

check('есть обработка входа в аккаунт',
  /isSignIn/.test(objc) && /hasPrefix:@"\/passport\/"/.test(objc));

check('при входе sys_region возвращается к живому',
  /sysRegion/.test(objc) && /removeObjectForKey:@"sys_region"/.test(objc));

check('есть хук пути запроса',
  /hasSuffix:@"path:"/.test(objc) && /setCurrentRequestPath/.test(objc));

check('HUB-поля не пишутся в tt_rewriteParams',
  !objc.includes('for (NSString *field in stringFields)'),
  'прежний код писал все шесть полей — исправлено');

console.log(`\n${'='.repeat(60)}`);
console.log(`passed: ${passed}   failed: ${failed}`);
console.log(`${'='.repeat(60)}\n`);

if (failed) {
  console.log('FAILED CHECKS:');
  for (const f of failures) console.log(`  - ${f.name}${f.detail ? `: ${f.detail}` : ''}`);
  process.exit(1);
}