/*
 * Минимальный шим Foundation/ObjC-runtime для проверки компиляции на Windows.
 *
 * ЗАЧЕМ: на Windows нет ни Foundation, ни Apple ObjC-рантайма, поэтому
 * TikTokRegion.m не собирается. Но синтаксис, типы и сигнатуры блоков можно
 * проверить, скомпилировав против минимального описания используемого API.
 *
 * ЧТО ЭТО ДОКАЗЫВАЕТ:
 *   код парсится; блоки и указатели на функции имеют совпадающие сигнатуры;
 *   нет опечаток в собственных именах; нет необъявленных переменных.
 *
 * ЧЕГО ЭТО НЕ ДОКАЗЫВАЕТ:
 *   что реальный Foundation ведёт себя так же. Некоторые методы здесь
 * объявлены с запасом по сигнатуре. Поведение на iOS не проверяется.
 *
 * Это проверка компиляции, а не проверка совместимости.
 */

#ifndef FOUNDATION_SHIM_H
#define FOUNDATION_SHIM_H

#include <stddef.h>
#include <stdarg.h>
#include <stdbool.h>
#include <string.h>

typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double NSTimeInterval;
typedef signed char BOOL8;

#ifndef YES
#define YES ((BOOL8)1)
#define NO  ((BOOL8)0)
#endif

typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef struct objc_object *id;
typedef id (*IMP)(id, SEL, ...);
typedef void *dispatch_once_t;
typedef long dispatch_once_predicate_t;

/* ── ObjC runtime ──────────────────────────────────────────────────────── */

extern id objc_getClass(const char *name);
extern SEL sel_registerName(const char *name);
extern const char *sel_getName(SEL sel);
extern BOOL8 class_respondsToSelector(Class cls, SEL sel);
extern Method *class_copyMethodList(Class cls, unsigned int *outCount);
extern SEL method_getName(Method m);
extern IMP method_getImplementation(Method m);
extern IMP method_setImplementation(Method m, IMP imp);
extern unsigned method_getNumberOfArguments(Method m);
extern Class object_getClass(id obj);

/* Объявления типов-заглушек для Method и va_arg */
#define _shim_VA_LIST_DEFINED

/* ── NSString ──────────────────────────────────────────────────────────── */

@interface NSString : NSObject
+ (instancetype)stringWithUTF8String:(const char *)bytes;
- (BOOL8)isEqualToString:(NSString *)other;
- (const char *)UTF8String;
- (NSUInteger)length;
- (BOOL8)hasPrefix:(NSString *)prefix;
- (BOOL8)hasSuffix:(NSString *)suffix;
- (NSString *)lowercaseString;
- (NSString *)uppercaseString;
- (unichar)characterAtIndex;
- (instancetype)initWithFormat:(NSString *)fmt, ...;
- (NSString *)stringByAppendingString:(NSString *)other;
@end

/* ── NSDictionary ──────────────────────────────────────────────────────── */

@interface NSDictionary : NSObject
- (id)objectForKey:(id)key;
- (id)objectForInfoDictionaryKey;        /* shim: no-arg */
- (NSUInteger)count;
- (NSArray *)allKeys;
@end

@interface NSMutableDictionary : NSDictionary
- (void)setObject:(id)obj forKey:(id)key;
- (void)removeObjectForKey:(id)key;
@end

@interface NSArray : NSObject
- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)index;
- (BOOL8)containsObject:(id)obj;
@end

@interface NSMutableArray : NSArray
- (void)addObject:(id)obj;
@end

@interface NSValue : NSObject
+ (NSValue *)valueWithPointer:(const void *)ptr;
@end

@interface NSBundle : NSObject
+ (NSBundle *)mainBundle;
- (id)objectForInfoDictionaryKey:(NSString *)key;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext;
@end

extern NSString *const NSLocalizedDescriptionKey;

/* ── Блочные преобразования ────────────────────────────────────────────── */

extern IMP imp_implementationWithBlock(void *block);
extern void *imp_getBlock(IMP imp);
extern BOOL8 imp_removeBlock(IMP imp);

/* ── NSLog / dispatch ──────────────────────────────────────────────────── */

extern void NSLog(NSString *fmt, ...);
extern void dispatch_once(dispatch_once_t *predicate, void (^block)(void));

/* ── Shims для Security (используется только в TLS-файле, здесь не нужен) ── */

#endif /* FOUNDATION_SHIM_H */