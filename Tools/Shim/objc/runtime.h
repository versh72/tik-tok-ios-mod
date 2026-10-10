#ifndef OBJC_RUNTIME_SHIM_H
#define OBJC_RUNTIME_SHIM_H

/*
 * objc/runtime.h — шим для проверки компиляции на Windows.
 * Только объявления, которые использует TikTokRegion.m.
 */

#include <stddef.h>

typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef struct objc_object *id;
typedef struct objc_method *Method;
typedef id (*IMP)(id, SEL, ...);

extern Class objc_getClass(const char *name);
extern SEL sel_registerName(const char *name);
extern SEL NSSelectorFromString(NSString *aSelectorName);
extern Class NSClassFromString(NSString *aClassName);
extern Method *class_copyMethodList(Class cls, unsigned int *outCount);
extern SEL method_getName(Method m);
extern IMP method_getImplementation(Method m);
extern IMP method_setImplementation(Method m, IMP imp);
extern unsigned method_getNumberOfArguments(Method m);
extern Class object_getClass(id obj);
extern IMP imp_implementationWithBlock(void *block);

#endif /* OBJC_RUNTIME_SHIM_H */
