/*
 * Минимальный шим UIKit — только для проверки синтаксиса Harness
 * на Windows. Настоящий UIKit есть в iOS SDK, этот файл его
 * не заменяет ни на сборке, ни на устройстве.
 *
 * Что он НЕ проверяет: поведение интерфейса, реальные типы
 * контроллеров, раскладку. Только то, что файл разбирается
 * и имена написаны правильно.
 */

#import <Foundation/Foundation.h>

typedef struct CGPoint { double x, y; } CGPoint;
typedef struct CGSize  { double width, height; } CGSize;
typedef struct CGRect  { CGPoint origin; CGSize size; } CGRect;
typedef double CGFloat;

/* Перечисления UIKit используют NS_OPTIONS, а он живёт в Foundation.
   Объявляем здесь, чтобы шим не зависел от версии Foundation. */
#define TT_OPTIONS(type, name) enum name : type name; enum name : type

typedef TT_OPTIONS(NSUInteger, UIControlEvents) {
    UIControlEventTouchUpInside = 1 << 6,
};

@class UIColor, UIImage, UIFont, UIView, UIWindow;

@interface UIResponder : NSObject
@end

/* NSObject как протокол нужен для NSObject<UIApplicationDelegate>;
   в Foundation-шиме он объявлен только как класс. */
@protocol NSObjectShim <NSObject>
@end

@interface UIColor : NSObject
@property (class, readonly) UIColor *systemBackgroundColor;
@property (class, readonly) UIColor *systemRedColor;
@property (class, readonly) UIColor *labelColor;
@property (class, readonly) UIColor *secondaryLabelColor;
@property (class, readonly) UIColor *systemGreenColor;
+ (UIColor *)greenColor;
@end

@interface UIScreen : NSObject
@property (class, readonly) UIScreen *mainScreen;
@property (nonatomic, readonly) CGRect bounds;
@end

@interface UIScreen (Main)
@end

@interface UIView : UIResponder
@property (nonatomic, strong) UIColor *backgroundColor;
@property (nonatomic) BOOL hidden;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)setNeedsLayout;
@end

@interface UILabel : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic) NSInteger numberOfLines;
@end

@interface UIScrollView : UIView
@property (nonatomic) CGSize contentSize;
@end

@interface UIStackView : UIView
@property (nonatomic) NSInteger axis;
@property (nonatomic) CGFloat spacing;
- (void)addArrangedSubview:(UIView *)view;
@end

@interface UIViewController : UIResponder
@property (nonatomic, strong) UIView *view;
- (void)viewDidLoad;
- (void)viewDidAppear:(BOOL)animated;
@end

@interface UIWindow : UIView
@property (nonatomic, strong) UIViewController *rootViewController;
- (void)makeKeyAndVisible;
@end

@interface UIApplication : UIResponder
@property (class, readonly) UIApplication *sharedApplication;
@property (nonatomic, weak) id delegate;
@property (nonatomic, readonly) UIWindow *keyWindow;
@end

@protocol UIApplicationDelegate <NSObject>
@optional
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
@end

/* Свойства и методы NSString, которые использует Harness, но которых
   нет в Foundation-шиме. Дублировать объявления нельзя — поэтому здесь
   только то, чего в Foundation-шиме действительно нет. */
@interface NSString (HarnessExtras)
@property (readonly) NSString *lastPathComponent;
@property (readonly) NSString *fileSystemRepresentation;
@end

extern int UIApplicationMain(int argc, char *argv[],
                             NSString *principalClassName,
                             NSString *delegateClassName);
