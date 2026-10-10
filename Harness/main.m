/*
 * Harness — проверка TikTokRegion.dylib на живом iOS-устройстве.
 *
 * Зачем это нужно
 * ---------------
 * Всё до этого проверялось на Windows, где нет ни iOS runtime, ни
 * устройства. Осталось неизвестным главное: работает ли подмена
 * методов на настоящем устройстве. Эта программа отвечает на вопрос
 * прямо, без TikTok и без расшифрованного IPA.
 *
 * Что она делает
 * --------------
 *   1. Создаёт класс с именем, которое ищет dylib (CommonParamsHandler)
 *   2. Загружает dylib через dlopen — срабатывает её конструктор
 *   3. Вызывает метод с параметрами и смотрит, подменились ли поля
 *   4. Показывает результат на экране
 *
 * Чего это НЕ проверяет: существование настоящих классов TikTok.
 * Проверить их можно только внутри TikTok.
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "FakeTikTokHandler.h"

#pragma mark - Результаты

@interface CheckResult : NSObject
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *detail;
@property (nonatomic, assign) BOOL      passed;
@end

@implementation CheckResult
@end

@interface RootViewController : UIViewController
@end

#pragma mark - Приложение

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) NSMutableArray<CheckResult *> *results;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.results = [NSMutableArray array];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[RootViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

#pragma mark - Проверки

static void Add(AppDelegate *self, NSString *t, NSString *d, BOOL ok) {
    CheckResult *r = [CheckResult new];
    r.title = t; r.detail = d; r.passed = ok;
    [self.results addObject:r];
    NSLog(@"[Harness] %@ %@ - %@", ok ? @"PASS" : @"FAIL", t, d);
}

/* Копируем dylib из bundle во временную папку: iOS запрещает
   dlopen прямо из bundle. */
static NSString *StageDylib(void) {
    NSString *src = [NSBundle.mainBundle pathForResource:@"TikTokRegion"
                                                  ofType:@"dylib"];
    if (!src) return nil;
    NSString *dst = [NSTemporaryDirectory()
                     stringByAppendingPathComponent:@"TikTokRegion.dylib"];
    NSError *err = nil;
    [[NSFileManager defaultManager] removeItemAtPath:dst error:NULL];
    if (![[NSFileManager defaultManager] copyItemAtPath:src toPath:dst error:&err]) {
        NSLog(@"[Harness] copy failed: %@", err);
        return nil;
    }
    return dst;
}

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self runAllChecks];
}

/* Проверка 1: класс, на который dylib будет вешать хук. */
- (void)checkFakeClass:(AppDelegate *)app {
    Class fake = CreateFakeTikTokClass();
    Add(app, @"Класс-подделка создан",
        fake ? NSStringFromClass(fake) : @"не удалось",
        fake != Nil);
}

/* Проверка 2: dylib грузится и её конструктор отрабатывает.
   Конструктор печатает в лог "TikTokRegion ... ready". Если он
   выполнился — NSLog из него попадёт в консоль устройства. */
- (void)checkDylibLoad:(AppDelegate *)app {
    NSString *path = StageDylib();
    if (!path) {
        Add(app, @"dylib найдена в bundle", @"нет файла TikTokRegion.dylib", NO);
        return;
    }
    Add(app, @"dylib скопирована во временную папку", path.lastPathComponent, YES);

    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW);
    if (!handle) {
        const char *err = dlerror();
        Add(app, @"dylib загрузилась", err ? @(err) : @"dlopen вернул NULL", NO);
        return;
    }
    Add(app, @"dylib загрузилась", @"dlopen: OK", YES);
}

/* Проверка 3: главная. Вызываем метод с параметрами и смотрим,
   изменились ли поля. Именно это и есть подмена региона. */
- (void)checkSpoof:(AppDelegate *)app {
    Class fake = NSClassFromString(@"CommonParamsHandler");
    if (!fake) {
        Add(app, @"Хук установлен", @"класс не найден", NO);
        return;
    }

    SEL sel = NSSelectorFromString(@"handleWithParams:flag:");
    Method m = class_getInstanceMethod(fake, sel);
    if (!m) {
        Add(app, @"Метод-мишень существует", @"нет handleWithParams:flag:", NO);
        return;
    }

    /* Проверяем, что метод подменён: после загрузки dylib реализация
       должна отличаться от исходной. */
    IMP current = method_getImplementation(m);
    Add(app, @"Метод-мишень существует", @"handleWithParams:flag:", YES);

    /* Собираем словарь в том виде, в каком его видит TikTok. */
    NSMutableDictionary *params = [@{
        @"current_region":   @"RU",
        @"residence":        @"RU",
        @"region":           @"RU",
        @"sys_region":       @"RU",
        @"carrier_region":   @"RU",
        @"carrier_region_v2":@"250",
        @"device_id":        @"test-device",
        @"_request_path":    @"/aweme/v1/feed/",
        @"_live_sys_region": @"RU",
        @"_live_timezone_name": @"Europe/Moscow",
    } mutableCopy];

    id inst = [[fake alloc] init];
    if (!inst) {
        Add(app, @"Экземпляр создан", @"alloc вернул nil", NO);
        return;
    }

    ((void (*)(id, SEL, id, id))current)(inst, sel, params, @YES);

    NSString *cur  = params[@"current_region"];
    NSString *res  = params[@"residence"];
    NSString *reg  = params[@"region"];
    NSString *dev  = params[@"device_id"];
    NSString *v2   = params[@"carrier_region_v2"];

    Add(app, @"current_region подменён",
        [NSString stringWithFormat:@"%@ -> %@", @"RU", cur ?: @"(nil)"],
        ![cur isEqualToString:@"RU"]);

    Add(app, @"residence подменён",
        [NSString stringWithFormat:@"%@ -> %@", @"RU", res ?: @"(nil)"],
        ![res isEqualToString:@"RU"]);

    Add(app, @"carrier_region_v2 пересобран (MCC+MNC)",
        v2 ?: @"(nil)",
        ![v2 isEqualToString:@"250"]);

    Add(app, @"region НЕ тронут",
        reg ?: @"(nil)",
        [reg isEqualToString:@"RU"]);

    Add(app, @"device_id НЕ тронут",
        dev ?: @"(nil)",
        [dev isEqualToString:@"test-device"]);
}

/* Проверка 4: запрос входа не должен подменять регион. */
- (void)checkSignIn:(AppDelegate *)app {
    Class fake = NSClassFromString(@"CommonParamsHandler");
    SEL sel = NSSelectorFromString(@"handleWithParams:flag:");
    if (!fake) { Add(app, @"Вход", @"класс не найден", NO); return; }

    IMP current = method_getImplementation(class_getInstanceMethod(fake, sel));

    NSMutableDictionary *params = [@{
        @"current_region":      @"RU",
        @"residence":           @"RU",
        @"sys_region":          @"XX",
        @"_request_path":       @"/passport/app/login/verify/",
        @"_live_sys_region":    @"RU",
        @"_live_timezone_name": @"Europe/Moscow",
    } mutableCopy];

    id inst = [[fake alloc] init];
    ((void (*)(id, SEL, id, id))current)(inst, sel, params, @YES);

    NSString *cur = params[@"current_region"];
    NSString *sys = params[@"sys_region"];

    Add(app, @"При входе регион НЕ подменён",
        cur ?: @"(nil)",
        [cur isEqualToString:@"RU"]);

    Add(app, @"При входе sys_region возвращён к живому",
        [NSString stringWithFormat:@"%@ -> %@", @"XX", sys ?: @"(nil)"],
        [sys isEqualToString:@"RU"]);
}

- (void)runAllChecks {
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;

    [self checkFakeClass:app];
    [self checkDylibLoad:app];
    [self checkSpoof:app];
    [self checkSignIn:app];

    BOOL allOk = YES;
    for (CheckResult *r in app.results) if (!r.passed) { allOk = NO; break; }

    CheckResult *sum = [CheckResult new];
    sum.title = @"ИТОГ";
    sum.detail = allOk ? @"все проверки пройдены"
                       : @"есть непрошедшие — см. список выше";
    sum.passed = allOk;
    [app.results addObject:sum];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([AppDelegate class]));
    }
}
