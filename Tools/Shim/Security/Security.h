#ifndef SECURITY_SHIM_H
#define SECURITY_SHIM_H

/*
 * Security/Security.h — шим для проверки компиляции на Windows.
 *
 * Объявлен только SecTrustEvaluateWithError, который использует TLS-файл.
 * Проверка компиляции, не проверка поведения.
 */

#include <stdbool.h>

typedef struct __SecTrust *SecTrustRef;
typedef struct __SecCertificate *SecCertificateRef;
typedef struct __CFError *CFErrorRef;

extern bool SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error);

#endif /* SECURITY_SHIM_H */
