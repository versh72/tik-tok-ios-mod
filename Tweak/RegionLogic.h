/*
 * RegionLogic — чистая логика подмены региона, без зависимости от iOS runtime.
 *
 * Все функции работают с простыми типами (char*, int) и не используют
 * Foundation, Objective-C runtime или системные вызовы. Это позволяет
 * тестировать их на любой платформе без сборки под iOS.
 *
 * Логика сверена с HushFeed (SysAdminDoc), RegionSpoof.java:
 *   - пишутся только current_region и residence
 *   - carrier_region, sys_region, region читаются, но не пишутся
 *     (их уже меняют хуки геттеров)
 *   - carrier_region_v2 пишется только если текущее значение — ровно 3 цифры
 *   - при входе в аккаунт (/passport/) регион НЕ подменяется,
 *     а sys_region и timezone_name возвращаются к живым значениям
 */

#ifndef REGION_LOGIC_H
#define REGION_LOGIC_H

#include <stddef.h>

/* Поля, которые записываются в карту параметров.
 * Только current_region и residence — остальные обрабатываются хуками геттеров. */
static const char *const RL_SAVED_REGION_FIELDS[] = {
    "current_region", "residence"
};

/* Поля, которые только читаются — их уже меняют хуки геттеров. */
static const char *const RL_HUB_REGION_FIELDS[] = {
    "carrier_region", "sys_region", "region"
};

/* Поле с кодом сети. */
static const char *const RL_NETWORK_COUNTRY_FIELD = "carrier_region_v2";

/* Поля, которые восстанавливаются к живым значениям при входе. */
static const char *const RL_SYSTEM_REGION_FIELD  = "sys_region";
static const char *const RL_TIMEZONE_NAME_FIELD  = "timezone_name";

/* Путь, по которому определяется запрос входа в аккаунт. */
static const char *const RL_SIGN_IN_PATH = "passport/";

/*
 * Проверяет, является ли значение MCC-кодом.
 * Ровно 3 цифры — не 3-4 символа, как было в прежней версии.
 */
static int rl_is_mcc(const char *value) {
    if (!value) return 0;
    if (value[0] == '\0' || value[1] == '\0' || value[2] == '\0') return 0;
    if (value[3] != '\0') return 0;
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
    if (!path) return 0;
    while (*path == '/') path++;
    const char *p = RL_SIGN_IN_PATH;
    while (*p) {
        if (*path != *p) return 0;
        path++; p++;
    }
    return 1;
}

/*
 * Переписывает региональные поля в карте параметров.
 *
 * Аргументы:
 *   params        — массив пар {ключ, значение}, NULL-терминированный
 *   country_iso   — код страны в нижнем регистре ("jp", "us")
 *   mcc, mnc      — коды оператора
 *   is_sign_in    — 1 если это запрос входа в аккаунт
 *   sys_region    — живое значение sys_region (для восстановления при входе)
 *   timezone_name — живое значение timezone_name (для восстановления при входе)
 *
 * Возвращает количество изменённых полей.
 *
 * При is_sign_in == 1:
 *   - current_region и residence НЕ трогаются
 *   - sys_region и timezone_name возвращаются к живым значениям
 *   - если живое значение пустое, поле удаляется
 */
static int rl_rewrite_params(
    const char **keys, const char **values, size_t count,
    const char *country_iso, const char *mcc, const char *mnc,
    int is_sign_in,
    const char *sys_region, const char *timezone_name
) {
    int changed = 0;

    for (size_t i = 0; i < count; i++) {
        const char *key = keys[i];
        const char *value = values[i];
        if (!key || !value) continue;

        if (is_sign_in) {
            /* При входе: восстанавливаем живые значения, ничего не подменяем. */
            if (key == RL_SYSTEM_REGION_FIELD || key == RL_TIMEZONE_NAME_FIELD) {
                /* Сравнение по строковому содержимому, не по указателю. */
                int match = 1;
                const char *a = key, *b = (key == RL_SYSTEM_REGION_FIELD)
                    ? RL_SYSTEM_REGION_FIELD : RL_TIMEZONE_NAME_FIELD;
                while (*a && *b) { if (*a != *b) { match = 0; break; } a++; b++; }
                if (match && *a == *b) {
                    /* Поле найдено — восстанавливаем живое значение. */
                    const char *live = (key == RL_SYSTEM_REGION_FIELD)
                        ? sys_region : timezone_name;
                    if (live && live[0] != '\0') {
                        values[i] = live;
                    } else {
                        values[i] = NULL;   /* пустое — удаляем поле */
                    }
                    changed++;
                }
            }
            continue;
        }

        /* Обычный запрос: подменяем только SAVED_REGION_FIELDS. */
        for (size_t f = 0; f < sizeof(RL_SAVED_REGION_FIELDS) / sizeof(RL_SAVED_REGION_FIELDS[0]); f++) {
            const char *field = RL_SAVED_REGION_FIELDS[f];
            int match = 1;
            const char *a = key, *b = field;
            while (*a && *b) { if (*a != *b) { match = 0; break; } a++; b++; }
            if (match && *a == *b) {
                values[i] = country_iso;
                changed++;
                break;
            }
        }

        /* carrier_region_v2 — только если текущее значение — MCC. */
        {
            int match = 1;
            const char *a = key, *b = RL_NETWORK_COUNTRY_FIELD;
            while (*a && *b) { if (*a != *b) { match = 0; break; } a++; b++; }
            if (match && *a == *b) {
                if (rl_is_mcc(value)) {
                    /* Склеиваем MCC + MNC. */
                    static char combined[16];
                    int n = 0;
                    for (const char *p = mcc; *p && n < 15; p++) combined[n++] = *p;
                    for (const char *p = mnc; *p && n < 15; p++) combined[n++] = *p;
                    combined[n] = '\0';
                    values[i] = combined;
                    changed++;
                }
            }
        }
    }

    return changed;
}

#endif /* REGION_LOGIC_H */