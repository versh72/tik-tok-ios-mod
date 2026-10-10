# TikTokRegion — подмена региона в TikTok для iOS

Библиотека (`.dylib`), которая меняет региональные параметры запросов
TikTok: страна, регион и оператор. Аналог HushFeed для Android.

## Что это делает

Подменяются ровно два поля — `current_region` и `residence`. Плюс
`carrier_region_v2`, но только если там ровно три цифры (MCC).

Правила сверены с HushFeed и не позволяют сломать логику TikTok:

| Поле | Обычный запрос | При входе |
|---|---|---|
| `current_region` | ✅ подменяется | ❌ не трогаем |
| `residence` | ✅ подменяется | ❌ не трогаем |
| `carrier_region_v2` | ✅ если значение — MCC | ❌ не трогаем |
| `region` | ❌ не трогаем | ❌ не трогаем |
| `sys_region` | ❌ не трогаем | ✅ возвращаем живое |
| `timezone_name` | ❌ не трогаем | ✅ возвращаем живое |

Запросы входа (`/passport/`) обрабатываются отдельно: там подмена
региона не применяется, а живые значения устройства возвращаются на
место. Иначе аккаунт мог бы выглядеть как переехавший за секунду.

## Устройство

```
Tweak/RegionLogic.h    ← вся логика подмены. Чистый C99.
Tweak/TikTokRegion.m   ← мост в Objective-C. Собственной логики подмены
                         не содержит — только вызывает rl_rewrite_params.
Tweak/Makefile         ← сборка через Theos
Tools/test-region-logic.c   ← 47 тестов, исполняют настоящий RegionLogic.h
```

Логика лежит в C, а не в Objective-C, по конкретной причине: её можно
**скомпилировать и запустить на любой машине**, без Xcode и без
устройства. ObjC-мост — тонкая обёртка.

## Как собрать dylib

Сборка iOS-библиотеки требует macOS с Xcode и iOS SDK. На Windows это
невозможно: нужен Apple ObjC-рантайм и Foundation.

**Без Mac** — через CI:

1. Открыть **Actions**
2. Выбрать **Сборка TikTokRegion.dylib (arm64)**
3. **Run workflow**
4. Через ~10 минут забрать **Artifacts** → `TikTokRegion-dylib-arm64`

Workflow сначала собирает и прогоняет C-логику с `-Werror`. Если тесты
падают, сборка не идёт дальше — в dylib не попадёт непроверенный код.

**С Mac:**

```bash
brew install theos
cd Tweak
make package ARCHS=arm64 PACKAGE_CONFIG=iphoneos/clang/arm64
```

## Почему arm64, а не arm64e

Это разные архитектуры, а не «старое и новое».

Подменяется App Store IPA, а он собран под **arm64** даже на arm64e-
устройствах (A14 и новее, включая iPhone 12 Pro). `arm64e` нужен для
джейлбрейк-пути, где библиотеку грузит TweakInject. Смешивать нельзя:
у каждой архитектуры свой package-конфиг.

## Установка

Требуется **расшифрованный** `TikTok.ipa` — из App Store файл приходит
зашифрованным, и `insert_dylib` ломает подпись несуществующего кода.

```bash
# macOS или Linux
git clone https://github.com/Tyilo/insert_dylib
cd insert_dylib && cargo build --release

insert_dylib -i TikTok.ipa -d TikTokRegion.dylib -m insert_dylib \
             --target-version 16.0 --inplace
```

Либо одной командой из PowerShell — скрипт сам проверит, что IPA
действительно расшифрован, и предупредит заранее:

```powershell
.\insert-dylib.ps1 -Ipa "TikTok.ipa" -Dylib "TikTokRegion.dylib"
```

Затем переподписать **Sideloadly** или **AltStore** (оба работают на
Windows, подпись своим Apple ID) и поставить на телефон по USB. Срок
бесплатной подписи — 7 дней, потом переподписать заново.

## Проверка

```bash
node Tools/test-region-logic.mjs    # 15 проверок + запуск C-тестов
node Tools/test-tweak.mjs           # 32 проверки структуры ObjC
node Tools/test-objc-compile.mjs    # 15 проверок компиляции через шим
node Tools/test-build-levels.mjs    # 5 проверок уровней сборки
```

Всего 67 проверок и 47 настоящих C-тестов.

Честно о границах: `Tools/Shim` — минимальное описание Foundation для
проверки синтаксиса на Windows. Он доказывает, что код разбирается и
типы сходятся. Он **не** доказывает, что настоящий Foundation ведёт себя
так же и что модуль соберётся под iOS — это проверяется в CI на
настоящем Xcode.

## Статус

| Слой | Состояние |
|---|---|
| Логика подмены | 47 C-тестов на настоящем `RegionLogic.h` |
| Компиляция C | чисто, `-Wall -Wextra -Werror` |
| Компиляция ObjC | чисто на настоящем iOS SDK |
| Сборка dylib | arm64, только системные зависимости |
| Внедрение в TikTok | нужен расшифрованный IPA |
| Работа на устройстве | не проверялось |

## Лицензия

Код оригинальный. Правила подмены сверены с открытым исходником
HushFeed (Android).
