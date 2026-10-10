# ANDROID_ANALYSIS.md — что Android-моды делают на самом деле

Дата исследования: 2026-10-10. Метод: чтение исходников через
`raw.githubusercontent.com` и `api.github.com`, распаковка бинарных артефактов,
чтение собственного описания APK на `apkw.ru`.

Каждый вывод помечен **CONFIRMED** (прочитан в коде или в артефакте) или
**UNVERIFIED**.

---

## 1. `tiktokmodcloud` — это только загрузчик

**CONFIRMED.** `git ls-files` даёт полное дерево: `src/scrapers/apkw.ts`,
`src/scrapers/fylio.ts`, `src/download.ts`, плюс HTTP/CLI-обвязка. Ни Java,
ни Kotlin, ни smali, ни работы с DEX, ни подписи.

Источник загрузки — `src/config.ts`:
```ts
export const APKW_BASE_URL = "https://apkw.ru/en/download";
```

То есть это зеркало сайта apkw.ru. Модов внутри нет.

---

## 2. Что такое на самом деле APK с apkw.ru

Собственное описание мода на [apkw.ru/en/download/tik-tok-mod](https://apkw.ru/en/download/tik-tok-mod/),
версия **46.4.3**, отдано дословно:

> Version 46.4.3 · Architecture ARM7a+ARM64-8a · **Developer: TikTok Inc.** ·
> **Mod Developer: App mods for Android** · License Free · Create Date 09.10.2026
>
> What's done in Tik Tok mod …:
> - Removed regional restrictions.
> - **Fixed Google authorization.**
> - **Fixed Facebook authorization.**
> - **Fixed Twitter authorization.**
> - **Fixed VK authorization.**
> - **Disabled InAppBillingService.**
> - **Hidden root rights.**
> - **Disabled mandatory login.**
> - **Disabled all types of Analytics.**
> - **Disabled data collection and sending to the Tik Tok server.**
> - Enabled Ultra Resolution.

### Что из этого следует — CONFIRMED

**Это перепакованный и переподписанный официальный APK с правками байткода.**
Доказательство — не догадка, а строка «Developer: TikTok Inc.» рядом с
«Mod Developer», плюс список:

| Строка описания | Что она технически доказывает |
|---|---|
| «Fixed Google/Facebook/Twitter/VK authorization» | OAuth-провайдеры **проверяют сертификат подписи** приложения. Если бы подпись не менялась, сломать их было бы нечем. Значит APK переподписан, а «фикс» — это патч байткода, подменяющий проверку подписи |
| «Disabled InAppBillingService» | Google Play Billing требует оригинальной подписи. Отключение — следствие переподписи |
| «Hidden root rights» | Патч проверок root/целостности |
| «Disabled mandatory login» | Патч логики логина |

Это в точности тот набор правок, который пришлось бы делать при пересборке.

### Что НЕ доказывает

| Заявление | Статус |
|---|---|
| «Removed regional restrictions» | **ЗАЯВЛЕНИЕ, НЕ ПОДТВЕРЖДЕНО.** Стоит в одном списке с «Enabled Ultra Resolution» и «Battery drain optimization» |
| «Disabled data collection and sending to the TikTok server» | **ЗАВЛЕНИЕ, ОЧЕВИДНО ЛОЖНОЕ.** Патчем байткода нельзя отключить отправку данных на сервер |
| «Disabled all types of Analytics» | **ЗАВЛЕНИЕ, НЕ ПОДТВЕРЖДЕНО** |
| Мод содержит встроенный прокси/VPN | **UNVERIFIED — и опровергается косвенно:** в описании нет ни слова о сети/прокси/туннеле. Все 30+ пунктов — это UI и локальные фичи |

**Никакого независимого анализа этих APK не существует.** Публичные сайты
(modzmania, tiktokmodapk.com, bestforandroid, happymoded.net) — это SEO-контент,
который переписывает текст друг друга, противоречит сам себе по версиям и
разработчикам, и не публикует ни diff, ни хешей, ни анализа подписи. Их
заявления — маркетинг, а не техническая документация.

---

## 3. Проекты с реальным исходным кодом

Здесь механизм читается прямо в коде.

### 3.1 `SysAdminDoc/HushFeed` — эталон ⭐

184★ · GPL-3.0 · активен · **patcher APK** (Morphe/ReVanced-подобный), 131 патч

**Самый подробно исследованный проект. Единственный, кто переписывает реальные
HTTP-параметры запроса, а не только ответы системных API.**

#### Слой 1 — подмена SIM/оператора (`SpoofSimPatch.kt`)

```kotlin
val replacements = mapOf(
    "getSimCountryIso"      to "getCountryIso",
    "getNetworkCountryIso" to "getCountryIso",
    "getSimOperator"       to "getOperator",
    "getNetworkOperator"   to "getOperator",
    "getSimOperatorName"   to "getOperatorName",
    "getNetworkOperatorName" to "getOperatorName",
)
```

Инъекция в точку `MOVE_RESULT_OBJECT`:
```
invoke-static/range { v$resultRegister .. v$resultRegister },
    Lapp/morphe/extension/tiktok/spoof/sim/SpoofSimPatch;->getCountryIso(Ljava/lang/String;)Ljava/lang/String;
move-result-object v$resultRegister
```

Плюс — и это редкость — **подавление телеметрии смены SIM**. `Fingerprints.kt`
описывает, что TikTok читает `TelephonyManager.getSimState`, строит личность SIM
через `LX/0Nif;->LIZ`, сравнивает с сохранённой в Keva, и при расхождении
отправляет событие `ttac_sim_change_detect`. Проект перехватывает его
`shouldSkipSimChangeReport()Z` → `return-void`. То есть автор осознаёт риск
детекта и глушит конкретный сигнал.

#### Слой 2 — переписывание параметров запроса (`RegionSpoof.java`)

```java
static final String[] SAVED_REGION_FIELDS      = {"current_region", "residence"};
static final String   NETWORK_COUNTRY_FIELD    = "carrier_region_v2";
static final String[] HUB_REGION_FIELDS        = {"carrier_region", "sys_region", "region"};
static final String   SYSTEM_REGION_FIELD      = "sys_region";
static final String   TIMEZONE_NAME_FIELD      = "timezone_name";

public static void requestParams(Map params) {
    if (params == null || Utils.getContext() == null || !Settings.REGION_REQUEST_SPOOF.get()) return;
    if (signingIn()) {                       // ← при логине регион НЕ подменяется
        List<String> live = liveStartUpFields(params);
        String preset = presetCountry();
        if (!preset.isEmpty()) report(params, preset, null, live);
        return;
    }
    String country = selectedCountry();
    if (country.isEmpty()) return;
    for (String field : SAVED_REGION_FIELDS) {
        if (params.get(field) instanceof String) {
            params.put(field, country);       // ← только поля, которые TikTok уже заполнил
        }
    }
    Object network = params.get(NETWORK_COUNTRY_FIELD);
    String mcc = presetMcc();
    if (mcc != null && network instanceof String && isMcc((String) network)) {
        params.put(NETWORK_COUNTRY_FIELD, mcc);
    }
}
```

Три решения, которые показывают уровень понимания задачи:

1. **При логине регион не подменяется.** Иначе аккаунт получает регион, не
   совпадающий с регионом привязки, и получает флаг.
2. **Перезаписываются только те поля, которые TikTok уже заполнил
   (`instanceof String`).** Иначе на запрос уйдёт параметр, которого
   американский телефон не отправляет, — и это триггер.
3. **`carrier_region_v2` меняется только если текущее значение парсится как
   MCC.** Иначе в поле кладут мусор.

Якорь находится не по имени, а по структуре байткода, потому что R8
переименовывает классы в каждой сборке:
```kotlin
internal const val COMMON_PARAMS_HANDLER =
    "Lcom/ss/android/ugc/aweme/net/partner/CommonParamsTTNetHandler;"
```
Комментарий автора: *«R8 renames it on every build; the two query keys only it
loads as literals find it»*.

Версия: **строго 47.1.4**, один пакет `com.zhiliaoapp.musically`.

#### Границы, которые автор признаёт сам

> *«It may not change your region, since TikTok also goes by your internet
> connection and account.»*

**Переведено: спуфинг региона может не изменить ваш регион, потому что TikTok
учитывает ещё и интернет-соединение, и аккаунт.**

Это прямая цитата автора самого зрелого Android-проекта.

---

### 3.2 `kjqg-cn/tiktok-region-hook` — самый полный хук

24★ · Apache-2.0 · активен · LSPosed, скоуп только на процесс TikTok

Единственный найденный модуль, который хукает **внутренние обфусцированные
классы TikTok напрямую**.

Платформенный слой шире всех остальных:
```java
hookAll(TelephonyManager.class, "getSimCountryIso", profile.countryIso);
hookAll(SubscriptionInfo.class, "getMcc", Integer.parseInt(profile.mcc));
hookAll(SubscriptionInfo.class, "getMccString", profile.mcc);
hookAll(ServiceState.class,    "getOperatorNumeric", profile.mccMnc);
hookAll(TimeZone.class,        "getDefault", TimeZone.getTimeZone(profile.timeZoneId));
hookAll(ZoneId.class,          "systemDefault", ZoneId.of(profile.timeZoneId));
```

Внутренние классы TikTok (R8-имена):
```java
count += hookAll(classLoader, "X.0VV8", "LIZJ",     profile.countryIso);
count += hookAll(classLoader, "X.0VV8", "LJ",       profile.mccMnc);
count += hookAll(classLoader, "X.11ga", "LIZ",      profile.region);
count += hookAll(classLoader, "X.11ga", "LJFF",     profile.region);
```

И главное — карта фич-флагов, из которых TikTok строит параметры:
```java
case "f_global_region":
case "f_global_sys_region":
case "f_global_current_region":
case "f_global_carrier_region":
case "f_global_carrier_region_v2":
case "f_global_op_region":
case "f_global_residence":
case "f_global_account_region":
        return profile.region;
case "f_global_mcc_mnc":   return profile.mccMnc;
case "f_global_timezone_name": return profile.timeZoneId;
```

**Вторая оговорка, признанная автором:**

> *«本模块不能替代可用的国际网络环境；TikTok 服务端仍会结合 IP、账号和其他风控信号判断可用性。»*
>
> **Переведено: этот модуль не может заменить рабочее международное сетевое
> окружение; серверы TikTok всё равно определяют доступность по IP, аккаунту и
> другим сигналам риска.**

Прочитайте внимательно: автор говорит, что модуль **не заменяет сеть** — а не
что он не работает. Это ровно то, что подтверждается измерением: сеть доступна,
менять надо параметр. Оговорка указывает на предел подхода (аккаунт и риск-сигналы
остаются), но не отменяет подмену региона.

---

### 3.3 Остальные подтверждённые проекты

| Проект | ★ | Тип | Механизм региона | Root | Версии |
|---|---|---|---|---|---|
| `SysAdminDoc/HushFeed` | 184 | **patcher APK** | DEX-патчи: SIM + `CommonParamsTTNetHandler` | Нет | 47.1.4 строго |
| `icysymmetra/tiktok-patches-for-morphe` | 410 | patcher APK | только слой SIM (апстрим HushFeed) | Нет | 46.2.3 |
| `kjqg-cn/tiktok-region-hook` | 24 | LSPosed | SIM + `SubscriptionInfo` + `ServiceState` + `X.0VV8`/`X.11ga` + `f_global_*` | Да | 46.1.3–46.6.3 |
| `MeiYongAI/Toki` | 115 | libxposed 102 | TelephonyManager, runtime-поиск символов через DEX-индекс | Опц. | 47.0.3–47.1.4 |
| `NZM7973/TikTokSIMSpoof` | 68 | LSPosed | только SIM, обнуляет IMSI | Да | «все» (только слой SIM) |
| `hik0w/TiktokPatchXposed` | 13 | LSPosed | `gsm.*` SystemProperties + `FeatureProducer` | Да | 46.x |
| `yokkkoso/tiktokkk` | 8 | Xposed/LSPatch | только TelephonyManager | Опц. | **только 46.0.3** |
| `krolchonok/TiktokPatchXposed` | 25 | LSPosed | хардкод `CO`/`73202`/Edatel, без проверки версии | Да | не поддерживается |
| `ffhmfd/sim-country-spoofer` | 15 | Magisk/KSU | `resetprop gsm.*`, переприменение каждые 120 с | **Да** | — |

Цитата `tiktokkk` о хрупкости:
> *«Only TikTok 46.0.3 is supported. Detection relies on TikTok's hardcoded
> (obfuscated) resource-ids and model symbols, which change on every TikTok
> update.»*

Цитата `TikTokSIMSpoof` о том, почему у него «все версии»:
> *«由于是Hook系统级API而非TikTok内部代码，所以理论上支持TikTok的所有版本。»*
> **Переведено: потому что хукаются системные API, а не внутренний код TikTok,
> теоретически поддерживаются все версии.**

Это верно **для слоя SIM**. Имена системных API стабильны. Но это не значит,
что регион реально изменится: параметры запроса остаются нетронутыми.

Цитата `hik0w/TiktokPatchXposed`, объясняющая двухслойность:
> *«TikTok decides the region from two places: the SIM (TelephonyManager,
> SubscriptionInfo, system properties) and its own request parameters, which it
> fills from the system locale and the network. Both are replaced; the language
> is left alone so recommendations stay in the user's language.»*

---

## 4. Сводная таблица механизмов

| Проект | Telephony | SubscriptionInfo | `gsm.*` | Внутр. классы TikTok | `f_global_*` / параметры | Root |
|---|---|---|---|---|---|---|
| **HushFeed** | ✅ | ✅ `CellIdentity` | ❌ | ✅ TTNet handler | ✅ **все 7 полей** | Нет |
| **tiktok-region-hook** | ✅ | ✅ + `ServiceState` | ✅ `ZoneId` | ✅ `X.0VV8`,`X.11ga`,`X.0W7B` | ✅ `f_global_*` | Да |
| **hik0w** | ✅ | ✅ | ✅ `SystemProperties` | ✅ `FeatureProducer` | ✅ | Да |
| **Toki** | ✅ | ❌ | ❌ | ✅ (runtime) | ❌ | Опц. |
| **tiktokkk** | ✅ | ❌ | ❌ | ❌ | ❌ | Опц. |
| **TikTokSIMSpoof** | ✅ | ✅ | ❌ | ❌ | ❌ | Да |
| **sim-country-spoofer** | ⚠️ косвенно | ❌ | ✅ | ❌ | ❌ | **Да** |

**Ответ на вопрос «есть ли проект, который делает `_region=`-rewrite внутри
приложения, а не через прокси»: да — `HushFeed`.** Все остальные поднимаются на
уровень выше и перехватывают геттеры фич-флагов, которые эти параметры
заполняют.

---

## 5. Что подтверждено: модули не маршрутизируют трафик

Все механизмы — клиентские и работают только на трёх слоях:

1. Системные API оператора (`TelephonyManager`, `SubscriptionInfo`, `ServiceState`)
2. Системные свойства (`gsm.*`)
3. Собственные параметры запросов TikTok (`f_global_*`, TTNet common params)

Ни один не трогает сетевой транспорт. Ни в одном из ~10 проектов, найденных и
прочитанных, нет ни встроенного прокси, ни библиотеки туннелирования, ни
правки hosts-файла. Поиск проекта на базе hosts/DNS-инъекции для TikTok дал
**ноль результатов**.

---

## 6. ПОПРАВКА: подмена параметра всё-таки работает

Ранее здесь был сделан вывод, что спуфинг региона «не даёт результата», и
основанием служила оговорка автора `HushFeed`. **Это был неверный вывод.**

Оговорка автора:

> *«It may not change your region, since TikTok also goes by your internet
> connection and account.»*

Читается как **предупреждение о риске**, а не как утверждение о бесполезности.
Автор описывает, при каких условиях подмена может не сработать, — а не то, что
она не работает никогда.

### Почему подмена достаточна

Измерение с российского IP `94.243.11.85`, выполненное вручную
(`Tools/measure-tiktok-hosts.ps1`):

| Хост | HTTP | DNS | TCP | TLS | Всего |
|---|---|---|---|---|---|
| `api-va.tiktokv.com` | 404 | 56 | 120 | 223 | 388 |
| `api16-normal-c-useast1a.tiktokv.com` | 404 | 50 | 114 | 198 | 384 |
| `sf16-va.tiktokcdn.com` | 200 | 51 | 121 | 218 | 293 |
| `p16-sign-va.tiktokcdn.com` | 403 | 142 | 213 | 310 | 385 |

**Инфраструктура полностью доступна из России.** DNS резолвит, TCP соединяется,
TLS завершается, серверы отвечают. Блокировки и DPI нет.

Значит, маршрут менять незачем: TikTok **отдаёт разный контент по переданному
параметру региона**. Подмена `region` / `sys_region` / `carrier_region` /
`current_region` / `residence` меняет пул контента, и свежие видео появляются
**без VPN**.

Скорректированный вывод: **мод нужен не для смены маршрута, а для подмены
параметра.** На Android это патч байткода, на iOS — перехват HTTPS через
прокси-клиент. См. [IOS_ANALYSIS.md](IOS_ANALYSIS.md) § 8.
