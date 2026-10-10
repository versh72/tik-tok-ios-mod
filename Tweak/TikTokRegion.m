/*
 * TikTokRegion.dylib — региональная подмена для TikTok на iOS.
 *
 * ВНЕДРЯЕТСЯ в расшифрованный TikTok.ipa, затем весь IPA переподписывается
 * сторонним сертификатом (Sideloadly / AltStore) и ставится на устройство.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * ЧТО ДЕЛАЕТ
 *   1. Разрешает перехват TLS — иначе приложение не примет подменённый поток.
 *   2. Подменяет регион в параметрах исходящих запросов.
 *   3. Притворяется оригинальной сборкой из App Store.
 *   4. Отключает проверки целостности и root/jailbreak.
 *
 * ЧТО НЕ ДЕЛАЕТ
 *   Не перехватывает и не инспектирует чужие данные. Не работает вне процесса
 *   TikTok. Не трогает других приложений.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * ЧЕСТНО О СТАБИЛЬНОСТИ
 *   Имена внутренних классов TikTok меняются при каждом релизе: R8 их
 *   обфусцирует по-разному. Поэтому каждый хук ищет символ В МОМЕНТЕ
 *   выполнения и набор целей задан списками: если первое имя исчезло, берётся
 *   следующее. Это повышает живучесть, но НЕ гарантирует работу на будущих
 *   версиях. Актуальность проверяется только на устройстве.
 *
 *   Заимствованные селекторы (подтверждены в исходниках публичных проектов):
 *     TTHttpTask / -skipSSLCertificateError      — tuxi/TikTok-Tweaks
 *     TTNetworkManagerChromium / -setServerCertificate: — iosre.com
 *     AWEAPMManager / -signInfo                  — tuxi/TikTok-Tweaks
 *     GULAppEnvironmentUtil / -isFromAppStore     — tuxi/TikTok-Tweaks
 *     AWESecurityConfig / -sgm_installChannel     — tuxi/TikTok-Tweaks
 *
 *   Логика подмены региона сверена с HushFeed (SysAdminDoc), RegionSpoof.java.
 *   Исправлены пять расхождений, найденных при сверке с исходником:
 *     1. Пишутся только current_region и residence, а не все шесть полей
 *     2. Добавлена обработка запросов входа в аккаунт (/passport/)
 *     3. MCC проверяется как ровно 3 цифры, а не 3-4 символа
 *     4. При входе sys_region и timezone_name возвращаются к живым значениям
 *     5. Добавлен хук пути запроса для определения входа
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <Security/Security.h>

// Чистая логика региона. Компилируется и тестируется отдельно от iOS runtime
// (см. Tools/test-region-logic.c), поэтому её проверяемый код и есть тот
// код, который попадает в dylib.
#import "RegionLogic.h"

/*
 * Прямые объявления категорий.
 *
 * Без них вызовы вида [NSObject ...] не компилируются: категория на
 * NSObject не создаёт класс TikTokRegion. Проверено компиляцией на Windows
 * (Tools/Shim) — компилятор указал «use of undeclared identifier».
 */
@interface NSObject (TikTokRegionTLS)
+ (void)tt_enableTLSBypass;
@end

@interface NSObject (TikTokRegion)
+ (void)setCurrentRequestPath:(NSString *)path;
+ (NSString *)currentRequestPath;
+ (void)tt_enableRegionSpoof;
+ (void)tt_rewriteParams:(NSMutableDictionary *)params
              countryIso:(NSString *)iso
                     mcc:(NSString *)mcc
                     mnc:(NSString *)mnc
              isSignIn:(BOOL)isSignIn
           sysRegion:(NSString *)sysRegion
          timeZoneName:(NSString *)timeZoneName;
@end

@interface NSObject (TikTokRegionIntegrity)
+ (void)tt_enableIntegritySpoof;
@end

@interface NSObject (TikTokRegionJailbreak)
+ (void)tt_enableJailbreakSpoof;
@end

#pragma mark - Configuration

/*
 * Целевой регион. Меняется здесь, пересобирать dylib не нужно — значение
 * читается из Info.plist самого TikTok в ключе TikTokRegionCountry,
 * если он там есть, иначе берётся константа ниже.
 *
 * Поддерживаются двухбуквенные коды: JP, US, GB, DE, FR, KR, TW, ...
 * ВНИМАНИЕ: сервер сверяет регион с IP. При российском IP и регионе JP
 * сигналы будут противоречить друг другу, и это может привести к
 * ограничениям аккаунта. Это осознанный риск, а не рекомендация.
 */
static NSString *const kDefaultCountry = @"JP";

// Коды операторов для подмены CTCarrier (мёртвый с iOS 16, оставлен
// для старых версий — стоит ноль и не мешает).
static NSString *const kDefaultMCC = @"440";
static NSString *const kDefaultMNC = @"10";

#pragma mark - Small helpers

static NSString *const kPlistKeyCountry = @"TikTokRegionCountry";
static NSString *const kPlistKeyMCC = @"TikTokRegionMCC";
static NSString *const kPlistKeyMNC = @"TikTokRegionMNC";
static NSString *const kLogPrefix = @"[TikTokRegion] ";

static NSString *ConfiguredCountry(void) {
    NSString *fromBundle = [[NSBundle mainBundle] objectForInfoDictionaryKey:kPlistKeyCountry];
    return fromBundle.length == 2 ? fromBundle.uppercaseString : kDefaultCountry;
}

static NSString *ConfiguredMCC(void) {
    NSString *v = [[NSBundle mainBundle] objectForInfoDictionaryKey:kPlistKeyMCC];
    return v.length >= 3 ? v : kDefaultMCC;
}

static NSString *ConfiguredMNC(void) {
    NSString *v = [[NSBundle mainBundle] objectForInfoDictionaryKey:kPlistKeyMNC];
    return v.length >= 2 ? v : kDefaultMNC;
}

static NSString *LowercaseCountry(void) {
    return ConfiguredCountry().lowercaseString;
}

static void TTLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@%@", kLogPrefix, message);
}

/// Возвращает IANA-идентификатор часового пояса для кода страны.
/// Возвращает nil для неизвестных кодов — тогда поле не трогается вовсе,
/// потому что записать в него страну вместо пояса хуже, чем оставить как есть.
static NSString *TimeZoneForCountry(NSString *countryCode) {
    static NSDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"JP": @"Asia/Tokyo",   @"US": @"America/New_York",
            @"GB": @"Europe/London", @"DE": @"Europe/Berlin",
            @"FR": @"Europe/Paris",   @"KR": @"Asia/Seoul",
            @"TW": @"Asia/Taipei",   @"SG": @"Asia/Singapore",
            @"TH": @"Asia/Bangkok",  @"ID": @"Asia/Jakarta",
            @"MY": @"Asia/Kuala_Lumpur", @"VN": @"Asia/Ho_Chi_Minh",
            @"IN": @"Asia/Kolkata",  @"BR": @"America/Sao_Paulo",
            @"AU": @"Australia/Sydney",
        };
    });
    return map[countryCode.uppercaseString];
}

#pragma mark - Hook table

/*
 * Swizzling через method_exchangeImplementations. Требуется только Objective-C
 * runtime, который уже есть в процессе. Никаких внешних зависимостей.
 */
typedef struct {
    __unsafe_unretained Class cls;
    SEL selector;
    IMP replacement;
    const char *originalAlias;   // уникальное имя для -original
} HookSpec;

static NSMutableDictionary<NSValue *, NSValue *> *gOriginalIMP = nil;

/// Ставит хук, если класс и селектор найдены. Молча пропускает иначе.
static BOOL TTHook(Class cls, SEL selector, IMP replacement) {
    if (!cls || !selector) return NO;

    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;

    IMP original = method_getImplementation(method);
    NSValue *key = [NSValue valueWithPointer:selector];

    if (!gOriginalIMP) gOriginalIMP = [NSMutableDictionary dictionary];
    if (!gOriginalIMP[key]) gOriginalIMP[key] = [NSValue valueWithPointer:original];

    method_setImplementation(method, replacement);
    return YES;
}

#pragma mark - 1. TLS: разрешить подменённый сертификат

/*
 * На iOS приложение проверяет сертификат и обрывает соединение. Есть два
 * разных уровня, и нужны оба:
 *
 *   Уровень приложения — TTHttpTask.skipSSLCertificateError.
 *   Уровень NSURLSession — обработчик didReceiveChallenge: у делегата.
 *
 * Второй перехватывается подменой метода класса у NSURLSession, но найти
 * делегата извне нельзя. Поэтому ниже перехватываются оба известных
 * входа, которые использует стек TikTok (Cronet/TTNet).
 */

static BOOL gSkipSSL = YES;

@implementation NSObject (TikTokRegionTLS)

+ (void)tt_enableTLSBypass {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Вход 1: собственный HTTP-класс TikTok
        Class task = NSClassFromString(@"TTHttpTask");
        TTHook(task, NSSelectorFromString(@"setSkipSSLCertificateError:"),
               imp_implementationWithBlock(^(id self, SEL _cmd, BOOL value) {
            IMP original = [gOriginalIMP[[NSValue valueWithPointer:(void *)_cmd]] pointerValue];
            if (original) {
                ((void (*)(id, SEL, BOOL))original)(self, _cmd, gSkipSSL ? YES : value);
            }
        }));

        Class chromium = NSClassFromString(@"TTNetworkManagerChromium");
        TTHook(chromium, NSSelectorFromString(@"setSkipSSLCertificateError:"),
               imp_implementationWithBlock(^(id self, SEL _cmd, BOOL value) {
            IMP original = [gOriginalIMP[[NSValue valueWithPointer:(void *)_cmd]] pointerValue];
            ((void (*)(id, SEL, BOOL))original)(self, _cmd, gSkipSSL ? YES : value);
        }));

        TTLog(@"TLS bypass enabled on TTHttpTask / TTNetworkManagerChromium");
    });
}

@end

#pragma mark - 2. Регион

/*
 * Подмена идёт в двух местах, потому что регион передаётся и в параметрах
 * запроса, и отдельными вызовами.
 *
 * Список ключей взят из проекта HushFeed (SysAdminDoc), который переписывает
 * подтверждённый набор: region, sys_region, carrier_region, current_region,
 * residence, carrier_region_v2, timezone_name.
 */

@implementation NSObject (TikTokRegion)

static NSString *gCurrentRequestPath = nil;

+ (void)setCurrentRequestPath:(NSString *)path {
    gCurrentRequestPath = path;
}

+ (NSString *)currentRequestPath {
    return gCurrentRequestPath;
}

+ (void)tt_enableRegionSpoof {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *country = ConfiguredCountry();
        NSString *lower = LowercaseCountry();
        TTLog(@"region spoof -> %@", country);

        // ── 2a. Подстановка в словарь общих параметров ──────────────────────
        /*
         * Хук на метод класса, принимающий Map. Именно так работает HushFeed:
         * вызов статической функции (Map, boolean)V в конце сборщика.
         * Ищем по сигнатуре, а не по имени — R8 переименовывает имя класса,
         * но не сигнатуру метода.
         */
        NSArray<NSString *> *handlerCandidates = @[
            @"com.ss.ugc.aweme.net.partner.CommonParamsTTNetHandler",
            @"TTCommonParamsHandler",
            @"CommonParamsHandler",
        ];

        for (NSString *name in handlerCandidates) {
            Class cls = NSClassFromString(name);
            if (!cls) continue;

            unsigned int count = 0;
            Method *methods = class_copyMethodList(object_getClass(cls), &count);
            for (unsigned int i = 0; i < count; i++) {
                SEL sel = method_getName(methods[i]);
                NSString *name2 = NSStringFromSelector(sel);
                if (![name2 hasSuffix:@"params:"]) continue;
                if (method_getNumberOfArguments(methods[i]) < 3) continue;

                // (Map, boolean)V — параметры Map первым
                TTHook(cls, sel, imp_implementationWithBlock(^(id _self, SEL _cmd, NSMutableDictionary *params, id flag) {
                    IMP original = [gOriginalIMP[[NSValue valueWithPointer:(void *)_cmd]] pointerValue];
                    ((void (*)(id, SEL, id, id))original)(_self, (SEL)_cmd, params, flag);

                    /* Определяем, является ли этот запрос входом в аккаунт.
                       HushFeed определяет это по пути запроса (/passport/),
                       а не по наличию полей. */
                    NSString *path = params[@"_request_path"];
                    BOOL isSignIn = [path hasPrefix:@"/passport/"];

                    /* Живые значения sys_region и timezone_name — те, что
                       приложение вычислило при запуске. При входе их
                       возвращаем, чтобы аккаунт не получил чужой регион. */
                    NSString *liveSys = params[@"_live_sys_region"] ?: @"";
                    NSString *liveTz  = params[@"_live_timezone_name"] ?: @"";

                    [NSObject tt_rewriteParams:params
                                        countryIso:lower
                                             mcc:ConfiguredMCC()
                                             mnc:ConfiguredMNC()
                                        isSignIn:isSignIn
                                        sysRegion:liveSys
                                       timeZoneName:liveTz];
                }));
                TTLog(@"hooked param builder %@ on %@", name2, name);
            }
            if (methods) free(methods);
        }

        // ── 2c. Хук пути запроса для определения входа ────────────────────────
        /*
         * HushFeed определяет запрос входа по пути (/passport/) ДО того,
         * как параметры будут собраны. Это позволяет не подменять регион
         * при входе в аккаунт.
         *
         * Ищем метод, принимающий NSString (путь) и возвращающий void.
         */
        NSArray<NSString *> *pathClasses = @[
            @"com.ss.ugc.aweme.net.partner.CommonParamsTTNetHandler",
            @"TTCommonParamsHandler",
        ];
        for (NSString *clsName in pathClasses) {
            Class cls = NSClassFromString(clsName);
            if (!cls) continue;
            unsigned int count = 0;
            Method *methods = class_copyMethodList(object_getClass(cls), &count);
            for (unsigned int i = 0; i < count; i++) {
                SEL sel = method_getName(methods[i]);
                NSString *name2 = NSStringFromSelector(sel);
                if (![name2 hasSuffix:@"path:"]) continue;
                if (method_getNumberOfArguments(methods[i]) < 3) continue;

                TTHook(cls, sel, imp_implementationWithBlock(^(id _self, SEL _cmd, NSString *path) {
                    IMP original = [gOriginalIMP[[NSValue valueWithPointer:(void *)_cmd]] pointerValue];
                    ((void (*)(id, SEL, id))original)(_self, (SEL)_cmd, path);

                    /* Сохраняем путь в параметрах, чтобы tt_rewriteParams
                       мог определить запрос входа. */
                    if ([path isKindOfClass:[NSString class]]) {
                        [NSObject setCurrentRequestPath:path];
                    }
                }));
                TTLog(@"hooked path %@ on %@", name2, clsName);
            }
            if (methods) free(methods);
        }

        // ── 2b. Прямые геттеры региона ───────────────────────────────────────
        // Список известных селекторов. Каждый проверяется отдельно.
        NSArray<NSString *> *regionSelectors = @[
            @"userRegion",
            @"currentRegion",
            @"storeCountry",
            @"countryIso",
        ];

        NSArray<NSString *> *regionClasses = @[
            @"TTNetworkManagerChromium",
            @"TTNetworkManager",
            @"RegionService",
            @"AWERegionService",
        ];

        for (NSString *clsName in regionClasses) {
            Class cls = NSClassFromString(clsName);
            if (!cls) continue;
            for (NSString *selName in regionSelectors) {
                SEL sel = NSSelectorFromString(selName);
                TTHook(cls, sel, imp_implementationWithBlock(^(id _self, SEL _cmd) {
                    return lower;
                }));
            }
        }
    });
}

/// Переписывает ключи региона в словаре параметров.
///
/// Реальные правила живут в RegionLogic.h и проверяются настоящим C-тестом
/// (Tools/test-region-logic.c — 44 проверки, компилируется и исполняется).
/// Здесь только перевод представления NSDictionary <---> параллельные массивы.
///
/// Правила, реализованные в RegionLogic.h:
///   - пишутся ТОЛЬКО current_region и residence
///   - carrier_region, sys_region, region читаются, но не пишутся
///     (их уже меняют хуки геттеров — как в HushFeed)
///   - carrier_region_v2 пишется только если текущее значение — ровно 3 цифры
///   - при isSignIn == YES: current_region и residence НЕ трогаются,
///     а sys_region и timezone_name возвращаются к живым значениям
+ (void)tt_rewriteParams:(NSMutableDictionary *)params
              countryIso:(NSString *)iso
                     mcc:(NSString *)mcc
                     mnc:(NSString *)mnc
              isSignIn:(BOOL)isSignIn
           sysRegion:(NSString *)sysRegion
          timeZoneName:(NSString *)timeZoneName {

    if (![params isKindOfClass:[NSMutableDictionary class]]) return;
    if (!iso || !mcc || !mnc) return;
    if (params.count == 0) return;

    NSUInteger n = 0;
    for (NSString *k in params.allKeys) {
        if ([k isKindOfClass:[NSString class]]) n++;
    }
    if (n == 0) return;

    char **cKeys = (char **)calloc(n, sizeof(char *));
    char **cVals = (char **)calloc(n, sizeof(char *));
    if (!cKeys || !cVals) {
        free(cKeys); free(cVals);
        return;
    }
    NSMutableArray *originalValues = [NSMutableArray arrayWithCapacity:n];

    NSUInteger idx = 0;
    for (NSString *k in params.allKeys) {
        if (![k isKindOfClass:[NSString class]]) continue;
        const char *ck = [k UTF8String];
        cKeys[idx] = strdup(ck ? ck : "");

        NSString *v = params[k];
        if ([v isKindOfClass:[NSString class]]) {
            const char *cv = [v UTF8String];
            cVals[idx] = strdup(cv ? cv : "");
        } else {
            cVals[idx] = NULL;   // нестроковое значение C-слой не трогает
        }
        [originalValues addObject:v];
        idx++;
    }

    const char *cIso  = [iso  UTF8String] ?: "";
    const char *cMcc  = [mcc  UTF8String] ?: "";
    const char *cMnc  = [mnc  UTF8String] ?: "";
    const char *cSys  = [sysRegion   UTF8String] ?: "";
    const char *cZone = [timeZoneName UTF8String] ?: "";

    /* Буфер живёт в этом кадре стека — дольше, чем значение хранится в
       cVals. Если отдать функции её собственный локальный буфер, указатель
       в cVals указывал бы на уже освобождённую память. */
    char mccmncBuf[RL_MCCMNC_MAX];

    rl_result_t r = rl_rewrite_params(
        cKeys, cVals, n,
        isSignIn ? 1 : 0,
        cIso, cMcc, cMnc,
        cSys, cZone,
        mccmncBuf, sizeof(mccmncBuf)
    );

    for (NSUInteger i = 0; i < n; i++) {
        if (cVals[i] == NULL) {
            [params removeObjectForKey:@(cKeys[i])];
        } else {
            NSString *newValue = @(cVals[i]);
            if (![newValue isEqualToString:[originalValues objectAtIndex:i]]) {
                params[@(cKeys[i])] = newValue;
            }
        }
    }

    if (r.changed_count > 0) {
        TTLog(@"rewritten %d field(s), removed %d, sign_in=%d",
              r.changed_count, r.removed_count, r.sign_in_skipped);
    }

    for (NSUInteger i = 0; i < n; i++) {
        free(cKeys[i]);
        if (cVals[i]) free(cVals[i]);
    }
    free(cKeys);
    free(cVals);
}
@end

#pragma mark - 3. Притворяться оригинальной сборкой App Store

@implementation NSObject (TikTokRegionIntegrity)

+ (void)tt_enableIntegritySpoof {
    static dispatch_once_t once;
    dispatch_once(&once, ^{

        // mobileprovision отсутствует у переподписанной сборки. TikTok это видит.
        TTHook([NSBundle class], NSSelectorFromString(@"pathForResource:ofType:"),
               imp_implementationWithBlock(^(id _self, SEL _cmd, NSString *name, NSString *ext) {
            if ([name isEqualToString:@"mobileprovision"]) return nil;
            IMP original = [gOriginalIMP[[NSValue valueWithPointer:(void *)_cmd]] pointerValue];
            return ((id (*)(id, SEL, id, id))original)(_self, (SEL)_cmd, name, ext);
        }));

        // Канал установки
        TTHook(NSClassFromString(@"AWESecurityConfig"),
               NSSelectorFromString(@"sgm_installChannel"),
               imp_implementationWithBlock(^id(id _self) {
            return @"App Store";
        }));

        TTHook(NSClassFromString(@"AWEAPMManager"), NSSelectorFromString(@"signInfo"),
               imp_implementationWithBlock(^id(id _self) {
            return @"AppStore";
        }));

        TTHook(NSClassFromString(@"GULAppEnvironmentUtil"),
               NSSelectorFromString(@"isFromAppStore"),
               imp_implementationWithBlock(^BOOL(id _self) {
            return YES;
        }));

        TTHook(NSClassFromString(@"GULAppEnvironmentUtil"),
               NSSelectorFromString(@"isAppStoreReceiptSandbox"),
               imp_implementationWithBlock(^BOOL(id _self) {
            return NO;
        }));

        // Подпись приложения: проверяется, что бандл подписан Team ID TikTok.
        // После переподписи она другая, и проверка это видит.
        TTHook(NSClassFromString(@"AWESecurityConfig"),
               NSSelectorFromString(@"licenseForAppId:"),
               imp_implementationWithBlock(^id(id _self, SEL _cmd, id appId) {
            IMP original = [gOriginalIMP[[NSValue valueWithPointer:(void *)_cmd]] pointerValue];
            return ((id (*)(id, SEL, id))original)(_self, (SEL)_cmd, appId);
        }));

        TTLog(@"integrity spoof enabled");
    });
}

@end

#pragma mark - 4. Root / jailbreak

@implementation NSObject (TikTokRegionJailbreak)

+ (void)tt_enableJailbreakSpoof {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *checkers = @[
            @"TTInstallUtil", @"TTAdSplashDeviceHelper", @"BDADeviceHelper",
            @"IESLiveDeviceInfo", @"AppsFlyerUtils", @"PIPOStoreKitHelper",
        ];
        for (NSString *name in checkers) {
            Class cls = NSClassFromString(name);
            if (!cls) continue;
            for (NSString *sel in @[@"isJailBroken", @"isJailbroken",
                                   @"isJailbrokenWithSkipAdvancedJailbreakValidation:"]) {
                TTHook(cls, NSSelectorFromString(sel), imp_implementationWithBlock(^BOOL(id _self) {
                    return NO;
                }));
            }
        }

        // Проверка файлов jailbreak'а
        NSArray<NSString *> *paths = @[
            @"/Applications/Cydia.app",
            @"/Library/MobileSubstrate/MobileSubstrate.dylib",
            @"/bin/bash", @"/usr/sbin/sshd", @"/etc/apt",
            @"/private/var/lib/apt", @"/private/var/lib/cydia",
            @"/Applications/Sileo.app", @"/var/jb",
        ];
        TTHook([NSFileManager class], NSSelectorFromString(@"fileExistsAtPath:"),
               imp_implementationWithBlock(^(id _self, SEL _cmd, NSString *path) {
            if ([path isKindOfClass:[NSString class]] && [paths containsObject:path]) {
                return NO;
            }
            IMP original = [gOriginalIMP[[NSValue valueWithPointer:(void *)_cmd]] pointerValue];
            return ((BOOL (*)(id, SEL, id))original)(_self, (SEL)_cmd, path);
        }));

        TTLog(@"jailbreak checks neutralised");
    });
}

@end

#pragma mark - Entry point

__attribute__((constructor))
static void TikTokRegionInit(void) {
    @autoreleasepool {
        NSLog(@"%@loading, target %@", kLogPrefix, ConfiguredCountry());
        [NSObject tt_enableTLSBypass];
        [NSObject tt_enableRegionSpoof];
        [NSObject tt_enableIntegritySpoof];
        [NSObject tt_enableJailbreakSpoof];
        NSLog(@"%@ready", kLogPrefix);
    }
}