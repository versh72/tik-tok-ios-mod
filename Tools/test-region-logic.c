/*
 * Настоящий C-тест логики RegionLogic.h.
 *
 * Компилируется и выполняется:
 *   zig cc -std=c99 -Wall -Wextra -O2 test.c -o test.exe && test.exe
 *
 * Это уровень фактического исполнения настоящего кода, а не его копии
 * на другом языке. Прежний test-region-logic.mjs был зеркалом на JS и
 * мог расходиться с исходником; здесь исполняется RegionLogic.h сам.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>

#include "../Tweak/RegionLogic.h"

static int passed = 0, failed = 0;

static void check(const char *name, int cond, const char *detail) {
    if (cond) { passed++; printf("  ok   %s\n", name); }
    else { failed++; printf("  FAIL %s%s%s\n", name, detail ? " — " : "", detail ? detail : ""); }
}

/* Строит карту пар из списка "ключ=значение", NULL-терминированного. */
struct map {
    char *keys[32];
    char *vals[32];
    size_t count;
};

static struct map mk(const char *first, ...) {
    struct map m;
    m.count = 0;
    va_list ap;
    va_start(ap, first);
    const char *s = first;
    while (s != NULL && m.count < 32) {
        const char *eq = strchr(s, '=');
        if (eq != NULL) {
            size_t klen = (size_t)(eq - s);
            m.keys[m.count] = (char *)malloc(klen + 1);
            memcpy(m.keys[m.count], s, klen);
            m.keys[m.count][klen] = '\0';
            m.vals[m.count] = (char *)(eq + 1);
            m.count++;
        }
        s = va_arg(ap, const char *);
    }
    va_end(ap);
    return m;
}

/* Значение по ключу; NULL если поля нет или оно удалено. */
static const char *get(struct map *m, const char *key) {
    for (size_t i = 0; i < m->count; i++) {
        if (strcmp(m->keys[i], key) == 0) return m->vals[i];
    }
    return NULL;
}

int main(void) {
    printf("\n== 1. Обычный запрос: подменяются только два поля ==\n");
    {
        struct map m = mk("region=RU", "sys_region=RU", "carrier_region=RU",
                         "current_region=RU", "residence=RU", "device_id=abc", NULL);
        rl_result_t r = rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10",
                                          "", "");

        check("current_region -> jp", strcmp(get(&m, "current_region"), "jp") == 0, get(&m, "current_region"));
        check("residence -> jp", strcmp(get(&m, "residence"), "jp") == 0, get(&m, "residence"));
        check("region НЕ тронут", strcmp(get(&m, "region"), "RU") == 0, get(&m, "region"));
        check("sys_region НЕ тронут", strcmp(get(&m, "sys_region"), "RU") == 0, get(&m, "sys_region"));
        check("carrier_region НЕ тронут", strcmp(get(&m, "carrier_region"), "RU") == 0, get(&m, "carrier_region"));
        check("device_id НЕ тронут", strcmp(get(&m, "device_id"), "abc") == 0, get(&m, "device_id"));
        check("изменено ровно 2 поля", r.changed_count == 2, NULL);
    }

    printf("\n== 2. carrier_region_v2 только при MCC ==\n");
    {
        struct map m = mk("carrier_region_v2=250", "current_region=RU", NULL);
        rl_result_t r = rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10", "", "");
        check("3 цифры - MCC, заменено на 44010",
              strcmp(get(&m, "carrier_region_v2"), "44010") == 0, get(&m, "carrier_region_v2"));
        check("mccmnc склеен", r.mccmnc[0] != '\0', r.mccmnc);
    }
    {
        struct map m = mk("carrier_region_v2=RU", NULL);
        rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10", "", "");
        check("2-буквенный код НЕ считается MCC",
              strcmp(get(&m, "carrier_region_v2"), "RU") == 0, get(&m, "carrier_region_v2"));
    }
    {
        struct map m = mk("carrier_region_v2=1234", NULL);
        rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10", "", "");
        check("4 знака НЕ считаются MCC",
              strcmp(get(&m, "carrier_region_v2"), "1234") == 0, get(&m, "carrier_region_v2"));
    }
    {
        struct map m = mk("carrier_region_v2=12a", NULL);
        rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10", "", "");
        check("цифра+буква НЕ считается MCC",
              strcmp(get(&m, "carrier_region_v2"), "12a") == 0, get(&m, "carrier_region_v2"));
    }
    {
        struct map m = mk("carrier_region_v2=not-mcc", NULL);
        rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10", "", "");
        check("произвольная строка НЕ трогается",
              strcmp(get(&m, "carrier_region_v2"), "not-mcc") == 0, get(&m, "carrier_region_v2"));
    }

    printf("\n== 3. Запрос входа: регион не подменяется ==\n");
    {
        struct map m = mk("current_region=RU", "residence=RU",
                          "sys_region=RU", "timezone_name=Europe/Moscow", NULL);
        rl_result_t r = rl_rewrite_params(m.keys, m.vals, m.count, 1, "jp", "440", "10",
                                          "RU", "Europe/Moscow");

        check("current_region НЕ подменён", strcmp(get(&m, "current_region"), "RU") == 0, get(&m, "current_region"));
        check("residence НЕ подменён", strcmp(get(&m, "residence"), "RU") == 0, get(&m, "residence"));
        check("sys_region возвращён к живому", strcmp(get(&m, "sys_region"), "RU") == 0, get(&m, "sys_region"));
        check("timezone_name возвращён к живому",
              strcmp(get(&m, "timezone_name"), "Europe/Moscow") == 0, get(&m, "timezone_name"));
        check("флаг sign_in установлен", r.sign_in_skipped == 1, NULL);
    }
    {
        /* Живое значение пустое — поле удаляется, как в HushFeed. */
        struct map m = mk("current_region=RU", "sys_region=RU", NULL);
        rl_result_t r = rl_rewrite_params(m.keys, m.vals, m.count, 1, "jp", "440", "10",
                                          "", "Asia/Tokyo");
        check("пустой живой sys_region удаляется",
              get(&m, "sys_region") == NULL && r.removed_count == 1, NULL);
    }
    {
        /* Живой часовой пояс отличается — подменяется на живой, не на preset. */
        struct map m = mk("timezone_name=Asia/Tokyo", NULL);
        rl_rewrite_params(m.keys, m.vals, m.count, 1, "us", "310", "410",
                          "RU", "Europe/Moscow");
        check("timezone_name берёт живой пояс, не preset",
              strcmp(get(&m, "timezone_name"), "Europe/Moscow") == 0, get(&m, "timezone_name"));
    }

    printf("\n== 4. Определение пути входа ==\n");
    check("/passport/... is sign-in", rl_is_sign_in("/passport/account/login/") == 1, NULL);
    check("//passport/ (двойной слеш) is sign-in", rl_is_sign_in("//passport/x") == 1, NULL);
    check("passport/ без слеша is sign-in", rl_is_sign_in("passport/x") == 1, NULL);
    check("/aweme/... not sign-in", rl_is_sign_in("/aweme/v1/feed/") == 0, NULL);
    check("/passportslike/... not sign-in",
          rl_is_sign_in("/passportslike/x") == 0, "startsWith без границы");
    check("NULL not sign-in", rl_is_sign_in(NULL) == 0, NULL);

    printf("\n== 5. Отсутствие региональных полей ==\n");
    {
        struct map m = mk("device_id=abc", "video_id=123", "timestamp=1699999999", NULL);
        rl_result_t r = rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10", "", "");
        check("ничего не изменено", r.changed_count == 0, NULL);
        check("device_id сохранён", strcmp(get(&m, "device_id"), "abc") == 0, NULL);
        check("video_id сохранён", strcmp(get(&m, "video_id"), "123") == 0, NULL);
        check("timestamp сохранён", strcmp(get(&m, "timestamp"), "1699999999") == 0, NULL);
    }
    {
        struct map m = mk(NULL);
        rl_result_t r = rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10", "", "");
        check("пустая карта не ломается", r.changed_count == 0 && r.removed_count == 0, NULL);
    }

    printf("\n== 6. Идемпотентность ==\n");
    {
        struct map m = mk("current_region=RU", "residence=RU", "device_id=abc", NULL);
        rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10", "", "");
        char *after_first = strdup(get(&m, "current_region"));
        rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10", "", "");
        check("повторный вызов даёт тот же результат",
              strcmp(get(&m, "current_region"), after_first) == 0, get(&m, "current_region"));
        check("device_id не повреждён", strcmp(get(&m, "device_id"), "abc") == 0, NULL);
        free(after_first);
    }

    printf("\n== 7. Реальная структура запроса TikTok ==\n");
    {
        /* Поля из HushFeed, плюс типичные параметры запроса. */
        struct map m = mk(
            "region=RU",
            "sys_region=RU",
            "carrier_region=RU",
            "current_region=RU",
            "residence=RU",
            "carrier_region_v2=250",
            "timezone_name=Europe/Moscow",
            "timezone_offset=10800",
            "device_id=7123456789",
            "iid=9876543210",
            "app_name=musical_ly",
            "channel=App%20Store",
            "device_type=iPhone15,2",
            "os_version=18.0",
            NULL);
        rl_result_t r = rl_rewrite_params(m.keys, m.vals, m.count, 0, "jp", "440", "10", "", "");

        check("current_region -> jp", strcmp(get(&m, "current_region"), "jp") == 0, NULL);
        check("residence -> jp", strcmp(get(&m, "residence"), "jp") == 0, NULL);
        check("carrier_region_v2 -> 44010",
              strcmp(get(&m, "carrier_region_v2"), "44010") == 0, NULL);
        check("изменено ровно 3 поля", r.changed_count == 3, NULL);
        check("device_id сохранён", strcmp(get(&m, "device_id"), "7123456789") == 0, NULL);
        check("iid сохранён", strcmp(get(&m, "iid"), "9876543210") == 0, NULL);
        check("app_name сохранён", strcmp(get(&m, "app_name"), "musical_ly") == 0, NULL);
        check("os_version сохранён", strcmp(get(&m, "os_version"), "18.0") == 0, NULL);
        check("timezone_name НЕ тронут в обычном запросе",
              strcmp(get(&m, "timezone_name"), "Europe/Moscow") == 0, NULL);
    }

    printf("\n== 8. Второй регион (не хардкод JP) ==\n");
    {
        struct map m = mk("current_region=RU", "carrier_region_v2=250", NULL);
        rl_rewrite_params(m.keys, m.vals, m.count, 0, "us", "310", "410", "", "");
        check("current_region -> us", strcmp(get(&m, "current_region"), "us") == 0, NULL);
        check("carrier_region_v2 -> 310410",
              strcmp(get(&m, "carrier_region_v2"), "310410") == 0, NULL);
    }

    printf("\n%s\n", "============================================================");
    printf("passed: %d   failed: %d\n", passed, failed);
    printf("%s\n\n", "============================================================");
    return failed == 0 ? 0 : 1;
}