/*
 * RegionLogic — чистая логика подмены региона, без зависимости от iOS runtime.
 *
 * Авторское право: (c) 2026 владельцы репозитория tik-tok-ios-mod.
 * Лицензия: GNU GPL v3.0 или позже. Полный текст — в файле LICENSE
 * в корне репозитория.
 *
 * ПРОИСХОЖДЕНИЕ. Правила подмены выведены из чтения исходного кода
 * HushFeed (SysAdminDoc/HushFeed), распространяемого под GPL-3.0:
 *   extensions/tiktok/src/main/java/app/morphe/extension/tiktok/spoof/region/RegionSpoof.java
 * GPL требует, чтобы производная работа оставалась под той же лицензией,
 * поэтому этот проект — GPL-3.0, а не MIT. Замена лицензии без
 * разрешения правообладателя была бы нарушением условий.
 *
 * Все функции работают с простыми типами (char*, int) и не используют
 * Foundation, Objective-C runtime или системные вызовы. Это позволяет
 * компилировать и тестировать их на любой платформе, включая Windows,
 * без iOS SDK и без Xcode.
 *
 * Логика сверена с HushFeed (SysAdminDoc), RegionSpoof.java:
 *   - пишутся только current_region и residence
 *   - carrier_region, sys_region, region читаются, но не пишутся
 *     (их уже меняют хуки геттеров)
 *   - carrier_region_v2 пишется только если текущее значение — ровно 3 цифры
 *   - при входе в аккаунт (/passport/) регион НЕ подменяется,
 *     а sys_region и timezone_name возвращаются к живым значениям
 *
 * Формат вызова: параллельные массивы ключей и значений, как это делает
 * Objective-C при перечислении NSDictionary через -allKeys.
 */

#ifndef REGION_LOGIC_H
#define REGION_LOGIC_H

#include <stddef.h>
#include <string.h>

/* Поля, которые записываются в карту параметров.
 * Только эти два — остальные обрабатываются хуками геттеров. */
#define RL_FIELD_CURRENT_REGION "current_region"
#define RL_FIELD_RESIDENCE      "residence"

/* Поля, которые только читаются — их уже меняют хуки геттеров. */
#define RL_FIELD_REGION          "region"
#define RL_FIELD_SYS_REGION      "sys_region"
#define RL_FIELD_CARRIER_REGION  "carrier_region"

/* Поле с кодом сети. */
#define RL_FIELD_NETWORK_COUNTRY "carrier_region_v2"

/* Поле часового пояса. */
#define RL_FIELD_TIMEZONE_NAME   "timezone_name"

/* Путь, по которому определяется запрос входа в аккаунт. */
#define RL_SIGN_IN_PATH "passport/"

/* Максимальная длина результата склейки MCC+MNC. */
#define RL_MCCMNC_MAX 16

/* Результат одного вызова rl_rewrite_params. */
typedef struct {
    int changed_count;                 /* сколько полей изменено */
    int removed_count;                 /* сколько полей удалено (пустое живое значение) */
    int sign_in_skipped;               /* 1 если это был запрос входа */
    char mccmnc[RL_MCCMNC_MAX];        /* результат склейки, пусто если не менялось */
} rl_result_t;

/*
 * Проверяет, является ли значение MCC-кодом.
 * Ровно 3 цифры — не 3-4 символа.
 */
static int rl_is_mcc(const char *value) {
    if (value == NULL) return 0;
    if (strlen(value) != 3) return 0;
    for (int i = 0; i < 3; i++) {
        if (value[i] < '0' || value[i] > '9') return 0;
    }
    return 1;
}

/*
 * Проверяет, начинается ли путь с /passport/.
 * Ведущие слэши пропускаются.
 */
static int rl_is_sign_in(const char *path) {
    if (path == NULL) return 0;
    while (*path == '/') path++;
    return strncmp(path, RL_SIGN_IN_PATH, strlen(RL_SIGN_IN_PATH)) == 0;
}

/*
 * Переписывает региональные поля в карте параметров.
 *
 * Аргументы:
 *   keys, values  — параллельные массивы; values[i] может быть изменён,
 *                   а также установлен в NULL (удаление поля)
 *   count         — количество пар
 *   is_sign_in    — 1 если это запрос входа в аккаунт
 *   country_iso   — код страны в нижнем регистре ("jp", "us")
 *   mcc, mnc      — коды оператора
 *   sys_region    — живое значение sys_region (для восстановления при входе)
 *   timezone_name — живое значение timezone_name (для восстановления при входе)
 *   mccmnc_scratch — буфер вызывающего кода не короче RL_MCCMNC_MAX.
 *     Обязателен: values[] может указывать на этот буфер, поэтому он должен
 *     жить дольше вызова. Нельзя писать в out.mccmnc — тот живёт на стеке
 *     этой функции и умирает вместе с ней.
 *   mccmnc_scratch_len — размер буфера
 *
 * Возвращает rl_result_t с описанием изменений.
 *
 * Правила (сверены с HushFeed):
 *   Обычный запрос:
 *     - current_region и residence заменяются на country_iso
 *     - carrier_region_v2 заменяется на mcc+mnc, но только если текущее
 *       значение — ровно 3 цифры (MCC)
 *     - region, sys_region, carrier_region НЕ трогаются
 *     - остальные поля не трогаются
 *
 *   Запрос входа (is_sign_in):
 *     - current_region и residence НЕ трогаются
 *     - sys_region возвращается к живому значению; если оно пустое — удаляется
 *     - timezone_name возвращается к живому значению
 */
static rl_result_t rl_rewrite_params(
    char **keys, char **values, size_t count,
    int is_sign_in,
    const char *country_iso,
    const char *mcc, const char *mnc,
    const char *sys_region, const char *timezone_name,
    char *mccmnc_scratch, size_t mccmnc_scratch_len
) {
    rl_result_t out;
    out.changed_count = 0;
    out.removed_count = 0;
    out.sign_in_skipped = 0;
    out.mccmnc[0] = '\0';

    for (size_t i = 0; i < count; i++) {
        const char *key = keys[i];
        if (key == NULL) continue;

        if (is_sign_in) {
            /* При входе: восстанавливаем живые значения, ничего не подменяем. */
            if (strcmp(key, RL_FIELD_SYS_REGION) == 0) {
                if (sys_region != NULL && sys_region[0] != '\0') {
                    values[i] = (char *)sys_region;
                } else {
                    values[i] = NULL;   /* пустое живое — поле удаляется */
                    out.removed_count++;
                    continue;
                }
                out.changed_count++;
                continue;
            }
            if (strcmp(key, RL_FIELD_TIMEZONE_NAME) == 0) {
                if (timezone_name != NULL && timezone_name[0] != '\0') {
                    values[i] = (char *)timezone_name;
                } else {
                    values[i] = NULL;
                    out.removed_count++;
                    continue;
                }
                out.changed_count++;
                continue;
            }
            continue;   /* остальные поля при входе не трогаем */
        }

        /* Обычный запрос: подменяем только current_region и residence. */
        if (strcmp(key, RL_FIELD_CURRENT_REGION) == 0
            || strcmp(key, RL_FIELD_RESIDENCE) == 0) {
            if (values[i] != NULL) {
                values[i] = (char *)country_iso;
                out.changed_count++;
            }
            continue;
        }

        /* carrier_region_v2 — только если текущее значение ровно 3 цифры. */
        if (strcmp(key, RL_FIELD_NETWORK_COUNTRY) == 0) {
            /* Буфер принадлежит вызывающему коду: если писать в out.mccmnc,
               values[i] указывал бы на стек этой функции и умер после return.
               ObjC-мост читает значение позже — там был бы мусор. */
            if (values[i] != NULL && rl_is_mcc(values[i]) &&
                mccmnc_scratch != NULL && mccmnc_scratch_len > 0) {
                size_t n = 0, cap = mccmnc_scratch_len;
                if (cap > RL_MCCMNC_MAX) cap = RL_MCCMNC_MAX;
                while (*mcc && n < cap - 1) mccmnc_scratch[n++] = *mcc++;
                while (*mnc && n < cap - 1) mccmnc_scratch[n++] = *mnc++;
                mccmnc_scratch[n] = '\0';
                values[i] = mccmnc_scratch;
                /* Копия в структуре — для отчётности, не для values[i]. */
                size_t k = 0;
                while (mccmnc_scratch[k] && k < RL_MCCMNC_MAX - 1) {
                    out.mccmnc[k] = mccmnc_scratch[k];
                    k++;
                }
                out.mccmnc[k] = '\0';
                out.changed_count++;
            }
            continue;
        }
    }

    if (is_sign_in) out.sign_in_skipped = 1;
    return out;
}

#endif /* REGION_LOGIC_H */