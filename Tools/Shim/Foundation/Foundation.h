#ifndef FOUNDATION_SHIM_H
#define FOUNDATION_SHIM_H

/*
 * Foundation/Foundation.h — шим для проверки компиляции на Windows.
 *
 * ЗАЧЕМ: на Windows нет ни Foundation, ни Apple ObjC-рантайма, поэтому
 * TikTokRegion.m не собирается. Синтаксис, типы и сигнатуры блоков можно
 * проверить, скомпилировав против минимального описания используемого API.
 *
 * ЧТО ДОКАЗЫВАЕТ:
 *   код парсится; блоки и указатели на функции имеют совпадающие сигнатуры;
 *   нет опечаток в собственных именах; нет необъявленных идентификаторов.
 *
 * ЧЕГО НЕ ДОКАЗЫВАЕТ:
 *   что настоящий Foundation ведёт себя так же. Это проверка компиляции,
 *   а не проверка совместимости.
 *
 * ИЗВЕСТНЫЕ ОГРАНИЧЕНИЯ КОМПИЛЯТОРА:
 *   ObjC-subscripting (obj[key]) не поддерживается компилятором zig на
 *   Windows. Проверено минимальным примером. Поэтому эти места не
 *   проверяются данным способом.
 */

#include <stddef.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double NSTimeInterval;
typedef unsigned short unichar;

/* ObjC-типы: на arm64 BOOL это bool. */
typedef bool BOOL;
#ifndef YES
#define YES ((BOOL)1)
#define NO  ((BOOL)0)
#endif
#ifndef nil
#define nil ((id)0)
#define Nil ((Class)0)
#endif

typedef void (^dispatch_block_t)(void);
typedef void *dispatch_once_t;

/* Прямые объявления: NSDictionary ссылается на NSArray до его определения. */
@class NSString;
@class NSArray;
@class NSMutableArray;
@class NSValue;
@class NSBundle;

/* ── Корневой класс ────────────────────────────────────────────────────── */

/* Протокол NSObject нужен для NSObject<UIApplicationDelegate> и других
   конструкций вида Class<Proto>. Настоящий Foundation объявляет и
   класс, и протокол с таким же именем. */
@protocol NSObject
@end

@interface NSObject <NSObject>
+ (instancetype)alloc;
+ (instancetype)dictionary;
- (instancetype)init;
@end

/* ── NSString ──────────────────────────────────────────────────────────── */

@interface NSString : NSObject
+ (instancetype)stringWithUTF8String:(const char *)bytes;
- (BOOL)isEqualToString:(NSString *)other;
- (const char *)UTF8String;
- (NSUInteger)length;
- (BOOL)hasPrefix:(NSString *)prefix;
- (BOOL)hasSuffix:(NSString *)suffix;
- (NSString *)lowercaseString;
- (NSString *)uppercaseString;
- (unichar)characterAtIndex:(NSUInteger)index;
- (instancetype)initWithFormat:(NSString *)fmt, ...;
- (instancetype)initWithFormat:(NSString *)fmt arguments:(va_list)args;
- (NSString *)stringByAppendingString:(NSString *)other;
@end

extern NSString *NSStringFromClass(Class aClass);
extern NSString *NSStringFromSelector(SEL aSelector);

/* ── NSDictionary / NSArray ───────────────────────────────────────────── */

@interface NSArray<ObjectType> : NSObject
+ (instancetype)array;
+ (instancetype)arrayWithObjects:(const id [])objects count:(NSUInteger)count;
- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)index;
- (BOOL)containsObject:(id)obj;
- (id)objectAtIndexedSubscript:(NSUInteger)index;
@end

@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
- (void)addObject:(id)obj;
@end

@interface NSDictionary<__covariant KeyType, __covariant ObjectType> : NSObject
- (id)objectForKey:(id)key;
- (id)objectForKeyedSubscript:(id)key;
+ (instancetype)dictionaryWithObjects:(const id [])objects
                              forKeys:(const id [])keys
                                count:(NSUInteger)count;
- (NSUInteger)count;
- (NSArray *)allKeys;
@end

@interface NSMutableDictionary<KeyType, ObjectType>
    : NSDictionary<KeyType, ObjectType>
- (void)setObject:(id)obj forKey:(id)key;
- (void)setObject:(id)obj forKeyedSubscript:(id)key;
- (void)removeObjectForKey:(id)key;
+ (instancetype)dictionary;
@end

@interface NSValue : NSObject
+ (NSValue *)valueWithPointer:(const void *)ptr;
- (void *)pointerValue;
@end

@interface NSBundle : NSObject
+ (NSBundle *)mainBundle;
- (id)objectForInfoDictionaryKey:(NSString *)key;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext;
@end

@interface NSError : NSObject
@property (readonly) NSInteger code;
@property (readonly, copy) NSString *domain;
@property (readonly, copy) NSString *localizedDescription;
@end

/* NSNumber нужен для boxed-литералов (@YES, @1). */
@interface NSNumber : NSObject
+ (NSNumber *)numberWithBool:(BOOL)value;
+ (NSNumber *)numberWithInt:(int)value;
+ (NSNumber *)numberWithInteger:(NSInteger)value;
@end

@interface NSFileManager : NSObject
+ (NSFileManager *)defaultManager;
- (BOOL)fileExistsAtPath:(NSString *)path;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error;
@end

extern NSString *NSTemporaryDirectory(void);
extern NSString *NSHomeDirectory(void);

/* ── ObjC runtime ──────────────────────────────────────────────────────── */

typedef struct objc_method *Method;
typedef id (*IMP)(id, SEL, ...);

extern Class objc_getClass(const char *name);
extern SEL sel_registerName(const char *name);
extern SEL NSSelectorFromString(NSString *aSelectorName);
extern Class NSClassFromString(NSString *aClassName);
extern Method class_getInstanceMethod(Class cls, SEL name);
extern Method *class_copyMethodList(Class cls, unsigned int *outCount);
extern SEL method_getName(Method m);
extern IMP method_getImplementation(Method m);
extern IMP method_setImplementation(Method m, IMP imp);
extern unsigned method_getNumberOfArguments(Method m);
extern Class object_getClass(id obj);
extern IMP imp_implementationWithBlock(void *block);
extern void dispatch_once(dispatch_once_t *predicate, dispatch_block_t block);

/* ── Логирование ──────────────────────────────────────────────────────── */

extern void NSLog(NSString *fmt, ...);

#endif /* FOUNDATION_SHIM_H */
