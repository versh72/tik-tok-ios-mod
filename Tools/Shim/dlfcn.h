/*
 * Минимальный шим dlfcn.h — только для проверки синтаксиса на Windows.
 * На iOS настоящий dlfcn.h есть в SDK. Здесь объявлены ровно те
 * функции, которые использует Harness.
 */

#ifndef SHIM_DLFCN_H
#define SHIM_DLFCN_H

#include <stddef.h>

/*
 * На настоящем iOS RTLD_NOW — это ((void *) 0x2), макрос, а не
 * переменная. Здесь объявлен так же макросом: иначе вызов
 * dlopen(path, RTLD_NOW) не проходит проверку синтаксиса.
 */
#define RTLD_LAZY  0x00001
#define RTLD_NOW   0x00002
#define RTLD_GLOBAL 0x00100
#define RTLD_LOCAL  0x00000
#define RTLD_DEFAULT ((void *) -2)

extern void *dlopen(const char *path, int mode);
extern int   dlclose(void *handle);
extern void *dlsym(void *handle, const char *symbol);
extern char *dlerror(void);

#endif /* SHIM_DLFCN_H */
