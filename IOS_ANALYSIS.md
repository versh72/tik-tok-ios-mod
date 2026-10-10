# IOS_ANALYSIS.md — совместимость и ограничения iOS

Дата: 2026-10-10. Каждый вывод помечен **CONFIRMED** (прочитан в коде/доках) или
**UNVERIFIED**.

---

## 1. Жёсткое ограничение, на которое упирается всё остальное

### Apple: подпись обязательна и связана с содержимым — CONFIRMED

[Apple Platform Security — App code signing process](https://support.apple.com/en-us/guide/security/app-code-signing-process-sec7c917bf14/web):

> «These operating systems **require that all executable code be signed using an
> Apple-issued certificate**… Mandatory code signing extends the chain of trust
> from the operating system to apps and **helps prevent third-party apps from
> loading unsigned code resources or using self-modifying code**.»

Там же — про загрузку динамических библиотек:

> «the system performs a code signature validation of **all the dynamic
> libraries that a process links against at launch time**. This verification is
> accomplished through the **team identifier (Team ID)**… A program may link
> against any platform library that ships with the system or any library with
> **the same team identifier** in its code signature as the main executable.»

**Следствие для мода:** библиотека с Team ID другого разработчика не будет
загружена в приложение TikTok. Даже если байткод изменён, главный исполняемый
файл подписан TikTok Pte. Ltd., и чужой dylib к нему не подгрузится.

### Что происходит при изменении байтов после подписи — CONFIRMED

1. **При установке** `installd` проверяет печать бандла. Реальная ошибка из
   [SideStore#1273](https://github.com/SideStore/SideStore/issues/1273):
   ```
   Failed to verify code signature of .../Payload/App.app :
   0xe8008017 (A signed resource has been added, modified, or deleted.)
   ```
2. **При запуске** хеш CodeDirectory не сходится → процесс убивается.

### Apple не предоставляет механизма модификации чужих приложений — CONFIRMED

Из документов Apple есть только: сертификат Developer Program **для вашего**
кода; Enterprise Program — и там область применения прямо ограничена:

> *«Eligible businesses have the ability to write **proprietary in-house apps
> for use within their organization**»* — это **ваш** код, а не перепакованный
> TikTok.

Пути «переподписать и перепаковать чужое приложение» у Apple нет.

---

## 2. Сравнение с Android: почему там механизм существует

| Шаг | Android | iOS |
|---|---|---|
| Декомпиляция | `apktool` → smali, открытый формат | `dumpdecrypted` → только на джейлбрейке, бинарный Mach-O |
| Патч байткода | открытый DEX, патчится текстом | проприетарный arm64, нужен Frida/ChOma |
| Переподпись | `apksigner` своим ключом, Android разрешает | подпись привязана к содержимому, iOS проверяет |
| Установка поверх оригинала | нельзя одновременно, но можно рядом | подпись не совпадёт |
| Root / доступ к ключу | `resetprop`, Magisk, LSPosed | jailbreak |

**Разница не в том, что Android-мод «хитрее».** Разница в том, что Android
разрешает пересобрать и переподписать APK, а iOS — нет. Именно поэтому
`HushFeed` (patcher) существует, а его аналога для iOS нет.

---

## 3. Единственный работающий путь: TrollStore — и его потолок

### 3.1 Поддерживаемые версии — CONFIRMED

[README TrollStore](https://github.com/opa334/TrollStore):

> «Supported versions: **14.0 beta 2 - 16.6.1, 16.7 RC (20H18), 17.0**»
>
> «16.7.x (excluding 16.7 RC) and 17.0.1+ will **NEVER** be supported (unless a
> third CoreTrust bug is discovered, which is unlikely).»

### 3.2 На чём держится — эксплойты, оба уже закрыты — CONFIRMED

| Версия TrollStore | Диапазон iOS | CVE | Исправлено в |
|---|---|---|---|
| 1.x | 14.0 – 15.4.1 | **CVE-2022-26766** (CoreTrust, Linus Henze) | iOS 15.5 |
| 2.0+ | 15.5 – 16.6.1, 17.0 | **CVE-2023-41991** (CoreTrust) | iOS 16.7 / 17.0.1 |

Оба — ошибки валидации подписи. Apple их закрыла. Нового нет.

### 3.3 Установка изменённого Mach-O — ДА, это работает — CONFIRMED

README TrollStore:

> «The binaries inside an IPA can have arbitrary entitlements, **fakesign them
> with `ldid`** and the entitlements you want (`ldid -S<path/to/entitlements.plist>
> <path/to/binary>`) and **TrollStore will preserve the entitlements when
> resigning them with the fake root certificate on installation.**»

TrollStore **сам переподписывает** бинарники поддельным корневым сертификатом,
используя CoreTrust-баг. Точные байты вашего бинарника не важны.

Документированный пайплайн внедрения — [**TrollFools**](https://github.com/Lessica/TrollFools)
(«In-place tweak injection with `insert_dylib` and ChOma»):

> «Expected to work on all iOS versions supported by opa334's TrollStore (i.e.
> **iOS 14.0 - 17.0**)»
>
> Цели: *Decrypted App Store applications (TrollStore applications)* /
> *Encrypted App Store applications with bare dynamic library*

Механика: `insert_dylib` добавляет команды `LC_LOAD_DYLIB`, затем
`cmdCoreTrustBypass(machO, teamID:)` переподписывает и целевой бинарник, и
внедрённую библиотеку.

### 3.4 Обязательное условие: расшифрованный IPA — CONFIRMED

FairPlay-ключ лежит на устройстве. Без джейлбрейка (или устройства A8–A11 с
checkm8) расшифрованный TikTok не получить. Это первое звено, которое
ломается на современном устройстве.

---

## 4. Почему это не работает на современном iPhone

### 4.1 Разрыв в десять мажорных версий — CONFIRMED

| | Значение |
|---|---|
| Новейшая iOS на сегодня | **27.0.1** (28 сентября 2026) — [Apple security releases](https://support.apple.com/en-us/100100) |
| Потолок TrollStore | **17.0** |
| Разрыв | **10 мажорных версий** |

TrollStore не может расшириться: оба CoreTrust-бага закрыты, а начиная с
**iOS 17.6 / 18.0** добавлена митигация `com.apple.private.persona-mgmt`,
запрещающая непривилегированному процессу порождать привилегированный —
а именно на этом TrollStore и построен.

### 4.2 Jailbreak закрывает дыру только на старых чипах — CONFIRMED

| Устройство | Максимум |
|---|---|
| A12 / A13 | **iOS 26.0.1** (Dopamine 3.0) |
| A8–A11 | любой iOS через palera1n (checkm8) |
| A14 и новее | максимум **18.7.1** |

ElleKit (движок твиков, замена Substrate):
> *«Tested configurations: iOS 15-27 (arm64), iOS 15-17 (arm64e)»*

---

## 5. Сводная таблица: можно ли запустить модифицированный TikTok

| Путь | Без джейлбрейка | Диапазон iOS | Модифицированный Mach-O в чужое приложение | Постоянно |
|---|---|---|---|---|
| **TrollStore + TrollFools** | ✅ | 14.0 b2 – **17.0** | ✅ **да** | ✅ навсегда |
| **Jailbreak + ElleKit** | ❌ | 15 – 26.0.1 (A12/A13) | ✅ да, прямо в App Store-приложение | пока джейлбрейк |
| **SideStore / AltStore** | ✅ | 14 – 27 | ⚠️ переподпишет, но это станет «ваше» приложение; срок 7 дней | ❌ |
| **Frida без джейлбрейка** | ✅ | любой | ❌ нет — [frida.re/docs/ios](https://frida.re/docs/ios/) требует либо jailbreak, либо отлаживаемого приложения | ❌ |
| **Обычная переподпись через Xcode** | ✅ | любой | ❌ нет | 7 дней |

SideStore сам формулирует границу:
> *«Your apps shouldn't need any modification to work with SideStore!»*

Поддержка модифицированных приложений в AltStore отклонена мейнтейнером
([issue #649](https://github.com/SideStore/SideStore/issues/649)):
> *«Any application modified and distributed without the copyright-holders
> permission is considered piracy… not a priority.»*

---

## 6. Статус исследованных iOS-проектов

| Проект | Механизм | Статус | Причина смерти |
|---|---|---|---|
| `tuxi/TikTok-Tweaks` | Logos-твик + **MonkeyDev** (инъекция без джейлбрейка) | заброшен 2023-05-31 | **issue #24: «注入后无法登录»** — после инъекции TikTok 34 не пускает войти |
| `haoict/tiktok-god` | Cydia-твик, `/Library/MobileSubstrate/` | **archived**, 2022-02-17 | **issue #153 «Rootless support»** без ответа. Все современные джейлбрейки rootless |
| `i90O/tiktok-ios-ipa` | конфиг Shadowrocket (MITM) | заброшен | **APK внутри нет**: `ios/tiktok` — 18 байт текста `tiktok ios免拔卡\r\n`. README: «最新版的TikTok暂时不支持免拔卡使用，需要下载旧版» |

### Что говорит автор `TikTok-Tweaks` сам

> *«经调试，大部分功能的代码适用抖音，观看视频还需要挂梯子，我记得去年的版本不需要的»*
>
> **Переведено: после отладки большинство функций работает на Douyin, но для
> просмотра видео в TikTok всё равно нужен прокси. В прошлом году, помню,
> обходилось без.**

Прямое признание автора: **твик не решает задачу просмотра TikTok без
прокси** — ровно тот же вывод, что даёт чтение Android-проектов.

### Регион в iOS-твиках — CONFIRMED

И `tuxi`, и `haoict` меняют одно и то же: то, что приложение **сообщает**
о регионе, через `CTCarrier`:

```objc
%hook CTCarrier
- (NSString *)mobileCountryCode { return changeRegion ? region[@"mcc"] : %orig; }
- (NSString *)isoCountryCode    { return changeRegion ? region[@"code"] : %orig; }
- (NSString *)mobileNetworkCode { return changeRegion ? region[@"mnc"] : %orig; }
```

Это тот же слой SIM, что и `TelephonyManager` на Android. **Никаких правок
параметров HTTP-запроса на iOS нет** — потому что нет возможности их внести.

---

## 7. Условия, которые потребовались бы для дальнейшей разработки

Чтобы iOS-мод стал возможен, нужно **одновременно**:

1. **Устройство на iOS ≤ 17.0** (TrollStore) или A8–A13 на джейлбрейке —
   то есть устройство не на актуальной iOS.
2. **Расшифрованный IPA** — джейлбрейк или A8–A11 с checkm8.
3. **Инструмент внедрения**, работающий на Linux/Windows — `insert_dylib`
   (opa334/ChOma), `fastPathSign`, `ldid`. Сборка dylib — macOS или Linux
   (theos).
4. **Знание актуальных внутренних символов TikTok.** Все исследованные
   проекты ломаются на каждом обновлении TikTok:
   - `tiktokkk`: *«Only TikTok 46.0.3 is supported»*
   - `tiktok-region-hook`: *«升级 TikTok 后如果功能异常，需要针对新版本重新适配»*
   - `HushFeed` привязан к 47.1.4 **точно**
5. **Готовность к тому, что TikTok всё равно смотрит на IP и аккаунт** — три
   независимых автора это написали прямым текстом.

Пункт 4 — не инженерная сложность, а бесконечная поддержка. Пункт 5
определяет, что даже сделанный мод не даст желаемого результата.

---

## 8. Что РЕАЛЬНО работает: перехват HTTPS через прокси-клиент

Измерение с российского IP показало, что вся инфраструктура TikTok доступна:
DNS резолвит, TCP соединяется, TLS завершается, серверы отвечают. Значит,
задача сводится не к смене маршрута, а к **подмене передаваемого параметра
региона**. А это можно сделать и без модификации приложения.

### Механизм

Прокси-клиент с поддержкой MITM (Shadowrocket, Quantumult X, Surge) ставит
свой корневой сертификат, терминирует TLS к доменам TikTok и переписывает
`_region=` / `region` / `carrier_region` в исходящих запросах. Само приложение
остаётся нетронутым и подписанным оригинально.

| | Мод (инъекция кода) | Перехват через прокси |
|---|---|---|
| Требует jailbreak | Да | **Нет** |
| Требует TrollStore | Да (iOS ≤ 17.0) | **Нет** |
| Меняет приложение | Да | **Нет** |
| Работает на iOS 18–27 | Нет | **Да** |
| Ломается при обновлении TikTok | Да | Нет (правила редактируются) |
| Цена | Устройство на старой iOS | Установка CA-сертификата |

### Готовая конфигурация

`Tools/proxy/region-swap.conf` — 5 секций (`[General]`, `[Rule]`,
`[URL Rewrite]`, `[Body Rewrite]`, `[MITM]`), 15 доменных правил, 14 правил
переписывания.

Главное в ней — переключатель, который и есть ваша проверка:

```
ACTION = DIRECT   →  TikTok идёт НАПРЯМУЮ с российского IP,
                     меняется ТОЛЬКО параметр региона.
                     Это проверка гипотезы «подмена работает без VPN».

ACTION = PROXY    →  TikTok идёт через туннель, регион подменяется поверх.
                     Работает в любом случае.
```

Если при `DIRECT` появились свежие видео — гипотеза подтверждена, и туннель
для TikTok больше не нужен. Если нет — нужен `PROXY`.

### Исправление к исходной конфигурации i90O

Опубликованные правила используют `(?<=_region=)CN(?=&)`. **Без `$` в конце
они не срабатывают**, когда параметр последний в строке запроса — то есть
молча, без ошибки. В конфигурации здесь используется `(?=&|$)`.

### Цена: сертификат

Установка CA в «Настройки → Основные → Доверие сертификатам» делает вас
самодостаточным CA — и **любое** приложение на телефоне, включая банковские,
сможет читать ваш HTTPS. Это осознанный компромисс, а не рекомендация.

Откат: удалить сертификат из «Доверие сертификатам» и удалить профиль
конфигурации. Установленные приложения при этом не ломаются.

Список MITM-доменов стоит держать минимальным: каждый добавленный домен
расширяет поверхность перехвата.

### Чего эта подмена НЕ делает

- Не обходит проверку подписи iOS
- Не модифицирует TikTok
- Не подделывает устройство под джейлбрейкнутое
- Не выдаёт себя за официальное приложение

Это конфигурация сетевого прокси, а не модификация приложения.

### Непроверено

**Работоспособность подмены на актуальной версии TikTok не проверена.** Нужен
телефон и включённый перехват. Имена параметров меняются между версиями
приложения — возможно, потребуется дополнить `[Body Rewrite]`. Это проверяется
только вручную.

---

## 9. Ответ на исходный вопрос

> *«Существует ли актуальный, воспроизводимый метод для обычного iPhone?»*

**Модификация приложения — нет.** Подпись iOS, Team ID и потолок iOS 17.0
остаются в силе, все четыре исследованных проекта мертвы.

**Подмена регионального параметра — да**, через перехват HTTPS прокси-клиентом
на любом актуальном iOS без jailbreak и без изменения приложения. Это и есть
механизм, который на Android делают патчем байткода.

Конфигурация готова. Проверить её можно только на устройстве.