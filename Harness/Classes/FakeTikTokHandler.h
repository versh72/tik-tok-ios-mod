/*
 * Подставной класс для проверки dylib на живом устройстве.
 *
 * Зачем он нужен
 * --------------
 * Настоящие классы TikTok (CommonParamsHandler и подобные) живут внутри
 * приложения TikTok. В обычном приложении их нет, поэтому хук в dylib
 * не на что навесить и проверить его нечем.
 *
 * Здесь создаётся класс с ТЕМ ЖИ ИМЕНЕМ, который dylib ищет через
 * NSClassFromString, и с теми же сигнатурами методов: метод, чьё имя
 * оканчивается на "params:", принимающий словарь. Если хук встанет на
 * него — значит вся цепочка работает: поиск класса, подмена метода,
 * вызов оригинала, разбор словаря и подмена полей.
 *
 * Это проверка механики, а не TikTok. Наличие настоящих классов TikTok
 * проверяется только внутри TikTok.
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/*
 * Метод с суффиксом "params:" и тремя аргументами (self, _cmd, params) —
 * ровно та форма, которую ищет хук в dylib:
 *     hasSuffix:@"params:"  и  method_getNumberOfArguments >= 3
 *
 * Сигнатура повторяет ожидаемую: (Map, boolean)V
 */
@interface FakeTikTokHandler : NSObject
- (void)handleWithParams:(NSMutableDictionary *)params flag:(id)flag;
- (void)handleWithPath:(NSString *)path;
@end

@implementation FakeTikTokHandler

/* Хук вызывает оригинал первым, потом правит словарь. Здесь ничего
   не делаем: важно только, что метод существует и принимает словарь. */
- (void)handleWithParams:(NSMutableDictionary *)params flag:(id)flag {
    (void)params;
    (void)flag;
}

/* Метод с суффиксом "path:" — под него dylib вешает второй хук,
   отвечающий за определение запроса входа. */
- (void)handleWithPath:(NSString *)path {
    (void)path;
}

@end

/*
 * dylib ищет класс по имени "CommonParamsHandler" — без префикса
 * Objective-C. Чтобы NSClassFromString его нашёл, нужен ровно такой
 *runtime-класс. Поэтому создаём его через objc_allocateClassPair, а не
 * через @interface (тот бы дал имя TestHarness.FakeTikTokHandler).
 */
#import <objc/runtime.h>

Class CreateFakeTikTokClass(void) {
    NSArray<NSString *> *names = @[
        @"com.ss.ugc.aweme.net.partner.CommonParamsTTNetHandler",
        @"TTCommonParamsHandler",
        @"CommonParamsHandler",
    ];

    for (NSString *name in names) {
        if (NSClassFromString(name) != Nil) continue;

        Class fake = objc_allocateClassPair([NSObject class], name.UTF8String, 0);
        if (!fake) return Nil;
        objc_registerClassPair(fake);

        /* Методы добавляются именно на созданный класс: у пары нет
           собственного списка методов, class_addMethod обязателен.

           IMP берём из класса-реализации через class_getMethodImplementation:
           это метод экземпляра, обращаться к нему как [Class method:] нельзя. */
        SEL paramsSel = NSSelectorFromString(@"handleWithParams:flag:");
        IMP paramsIMP = class_getMethodImplementation([FakeTikTokHandler class],
                                                     paramsSel);
        class_addMethod(fake, paramsSel, paramsIMP, "v@:@@");

        SEL pathSel = NSSelectorFromString(@"handleWithPath:");
        IMP pathIMP = class_getMethodImplementation([FakeTikTokHandler class],
                                                   pathSel);
        class_addMethod(fake, pathSel, pathIMP, "@@:@");

        return fake;
    }
    return Nil;
}
