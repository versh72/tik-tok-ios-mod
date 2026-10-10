# TikTokRegion — патч региона для TikTok на iOS

Внедряемая динамическая библиотека для TikTok iOS. Подменяет регион,
притворяется оригинальной сборкой App Store, снимает проверки целостности.

**Это тот же механизм, что у Android-модов** (например у `HushFeed`): патч
байткода + переподпись. На Android разрешается перепаковка APK, на iOS —
внедрение dylib в расшифрованный IPA.

---

## Что готово

| Файл | Назначение |
|---|---|
| `TikTokRegion.m` | исходник dylib — четыре этапа подмены |
| `Makefile` | сборка через theos (arm64 + arm64e) |
| `build.sh` | полный пайплайн: сборка → внедрение → подпись → IPA |

```
node Tools/test-tweak.mjs   →  34 проверки, все проходят
```

---

## Чего не хватает

**Расшифрованный TikTok.ipa.**

FairPlay-ключ лежит в защищённом хранилище устройства и легально не
извлекается. `build.sh` это проверяет и **откажется работать** с зашифрованным
IPA, а не соберёт битый файл:

```
IPA зашифрован (cryptid=1). Нужен РАСШИФРОВАННЫЙ IPA.
```

Где взять:

| Путь | Надёжность |
|---|---|
| Выгрузка с джейлбрейкнутого устройства | Высокая, но устройства нет |
| Сторонние сайты с готовыми IPA | **Недоверенный источник.** Ставьте на телефон с аккаунтом, который не жалко |

Второй вариант — это то, чем торгуют коммерческие проекты вроде
`TikTok-iOS-SSL-Pinning-Bypass`. Мы их не рекомендуем и не распространяем.
Но риск остаётся на вас: в чужом IPA может быть что угодно.

---

## Сборка

Зависимости (Linux или WSL2 на Windows, macOS не нужен):

```bash
bash bootstrap && bash scripts/get_theos.sh   # theos
sudo apt install ldid zip unzip
# insert_dylib:
git clone https://github.com/opa334/insert_dylib && make
```

Сборка:

```bash
./Tweak/build.sh путь-к-расшифрованному-TikTok.ipa
```

Скрипт на каждом шаге проверяет результат и падает с внятной ошибкой, если
что-то не сработало. Установка — через **Sideloadly** (бесплатно, Windows).

---

## Что именно делает dylib

**1. Снимает проверку сертификата.**
`TTHttpTask -setSkipSSLCertificateError:` и `TTNetworkManagerChromium`.
Без этого подменённый поток не принимается.

**2. Подменяет регион.**

Параметры — по набору из `HushFeed`, наиболее полной Android-реализации:
`region`, `sys_region`, `carrier_region`, `current_region`, `residence`,
`carrier_region_v2`.

Два решения, которые важны:

- перезаписываются **только те поля, что приложение уже заполнило**
  (`if ([existing isKindOfClass:[NSString class]])`). Добавление параметра,
  которого телефон такого региона не отправляет, само по себе аномалия
- `carrier_region_v2` меняется **только если текущее значение похоже на MCC**,
  иначе в поле кладут мусор

**3. Притворяется сборкой из App Store.**
`sgm_installChannel`, `signInfo`, `isFromAppStore`,
`pathForResource:@"mobileprovision"` → `nil`.

**4. Отключает root/jailbreak-проверки.**

Все селекторы и классы ищутся **в момент выполнения** через `NSClassFromString`
и `NSSelectorFromString`, а не жёстко. R8 переименовывает внутренние классы
при каждом релизе — жёсткие имена ломаются мгновенно.

---

## Настройка

Регион задаётся константой `kDefaultCountry` в начале `TikTokRegion.m`
или ключом в `Info.plist` самого TikTok:

```xml
<key>TikTokRegionCountry</key>  <string>JP</string>
<key>TikTokRegionMCC</key>      <string>440</string>
<key>TikTokRegionMNC</key>      <string>10</string>
```

---

## Честно об ограничениях

**Не проверено на устройстве.** Ни один из этих файлов не компилировался и не
запускался — на машине разработки нет clang для iOS и theos. `test-tweak.mjs`
проверяет структуру и наличие хуков, а не типы.

**Стабильность привязана к версии TikTok.** Имена внутренних классов меняются
с каждым релизом. Список кандидатов повышает живучесть, но не гарантирует
работу на будущих версиях. `tiktokkk` формулирует это так:

> *«Only TikTok 46.0.3 is supported. Detection relies on TikTok's hardcoded
> (obfuscated) resource-ids and model symbols, which change on every TikTok
> update.»*

**Риск аккаунта.** Подмена региона при российском IP создаёт
противоречивые сигналы — регион JP, IP RU. `HushFeed` специально не подменяет
регион при входе в аккаунт и глушит событие `ttac_sim_change_detect`, то есть
автор считает это реальным риском. Здесь то же сделано частично.

**Нарушение ToS.** Патч лицензионного приложения и обход его защиты —
правовая зона, которую вы решаете сами.

---

## Проверка после установки

**Настройки → Основные → Обслуживание → Журналы** → найдите TikTok → ищите
`[TikTokRegion]`.

Успех выглядит так:

```
[TikTokRegion] loading, target JP
[TikTokRegion] TLS bypass enabled on TTHttpTask / TTNetworkManagerChromium
[TikTokRegion] hooked param builder ... on com.ss.ugc.aweme.net.partner.CommonParamsTTNetHandler
[TikTokRegion] region spoof -> JP
[TikTokRegion] integrity spoof enabled
[TikTokRegion] ready
```

Если строки нет — dylib не загрузилась. Если есть `region spoof`, но нет
`hooked param builder` — класс сборщика параметров переименован, и подмены
параметров не произошло.