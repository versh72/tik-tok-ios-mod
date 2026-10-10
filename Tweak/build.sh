#!/usr/bin/env bash
# Сборка TikTokRegion.dylib и внедрение в расшифрованный TikTok.ipa.
#
# Работает на Windows (через WSL или Git Bash) и на Linux. Mac не нужен.
#
# ВАЖНО: нужен РАСШИФРОВАННЫЙ IPA. Обычный App Store IPA зашифрован
# FairPlay и не поддаётся внедрению — патчатся только зашифрованные байты.
#
# ── Использование ─────────────────────────────────────────────────────────────
#   ./build.sh <путь-к-расшифрованному-TikTok.ipa> [выходной.ipa]
#
# ── Зависимости ───────────────────────────────────────────────────────────────
#   theos      — сборка dylib
#   ldid       — подпись dylib и всего бандла перед переподписью в Sideloadly
#   insert_dylib (opa334/ChOma) — внедрение LC_LOAD_DYLIB в главный бинарник
#   unzip / zip
#
#   На Windows проще всего: WSL2 + apt install theos ldid zip unzip

set -euo pipefail

DYLIB_NAME="TikTokRegion"
BUNDLE_ID="com.zhiliaoapp.musically"
MARKER=".ttregion"

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'
die()  { echo "${RED}ОШИБКА:${RST} $*" >&2; exit 1; }
info() { echo "${GRN}==>${RST} $*"; }
warn() { echo "${YLW}ВНИМАНИЕ:${RST} $*"; }

[ $# -ge 1 ] || die "укажите путь к расшифрованному IPA: ./build.sh TikTok-decrypted.ipa"

SRC_IPA="${1:?}"
OUT_IPA="${2:-TikTok-region-patched.ipa}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$SRC_IPA" ] || die "файл не найден: $SRC_IPA"

# ── 0. Проверка инструментов ──────────────────────────────────────────────────
for tool in theos ldid insert_dylib zip unzip; do
  command -v "$tool" >/dev/null 2>&1 || die "нет $tool — см. зависимости в шапке скрипта"
done

# ── 1. Сборка dylib ───────────────────────────────────────────────────────────
info "Сборка $DYLIB_NAME.dylib"
( cd "$ROOT/Tweak" && make clean >/dev/null 2>&1 || true && make )

DYLIB="$ROOT/Tweak/.theos/obj/$DYLIB_NAME.dylib"
[ -f "$DYLIB" ] || DYLIB="$ROOT/Tweak/.theos/obj/debug/$DYLIB_NAME.dylib"
[ -f "$DYLIB" ] || die "dylib не собрался — смотрите вывод theos"
info "Собрано: $(basename "$DYLIB") ($(stat -c%s "$DYLIB" 2>/dev/null || wc -c < "$DYLIB") байт)"

# ── 2. Распаковка ─────────────────────────────────────────────────────────────
info "Распаковка $SRC_IPA"
unzip -q "$SRC_IPA" -d "$WORK"
APP="$WORK/Payload/$BUNDLE_ID.app"
[ -d "$APP" ] || die "внутри нет Payload/$BUNDLE_ID.app — это не TikTok.ipa"

MAIN="$APP/$BUNDLE_ID"
[ -f "$MAIN" ] || die "нет главного бинарника $BUNDLE_ID"

# Расшифрован ли IPA: у зашифрованного в заголовке Mach-O cryptid != 0.
CRYPTID="$(lipo -info "$MAIN" >/dev/null 2>&1; otool -l "$MAIN" 2>/dev/null \
           | awk '/LC_ENCRYPTION_INFO/{f=1} f&&/cryptid/{print $2; exit}')"
if [ "${CRYPTID:-1}" != "0" ]; then
  die "IPA зашифрован (cryptid=$CRYPTID). Нужен РАСШИФРОВАННЫЙ IPA.
      FairPlay-ключ лежит на устройстве и легально не извлекается."
fi
info "IPA расшифрован (cryptid=0)"

# ── 3. Проверка: не патчен ли уже ──────────────────────────────────────────────
if otool -l "$MAIN" 2>/dev/null | grep -q "$DYLIB_NAME"; then
  warn "IPA уже содержит $DYLIB_NAME — продолжаю, но внедрение будет двойным"
fi

# ── 4. Копирование и подпись dylib ────────────────────────────────────────────
info "Подготовка dylib"
cp "$DYLIB" "$APP/$DYLIB_NAME.dylib"
chmod 755 "$APP/$DYLIB_NAME.dylib"

# ldid ставит ad-hoc подпись. Без неё iOS не загрузит библиотеку даже после
# переподписи всего бандла сторонним сертификатом.
ldid -S"$APP/$DYLIB_NAME.dylib"

# ── 5. Внедрение в главный бинарник ───────────────────────────────────────────
# insert_dylib добавляет LC_LOAD_DYLIB с @executable_path, чтобы iOS нашёл
# библиотеку рядом с бинарником.
info "Внедрение в главный бинарник"
insert_dylib \
  --inplace \
  --all-yes \
  --strip-codesig \
  --add "@executable_path/$DYLIB_NAME.dylib" \
  "$MAIN" 2>/dev/null \
  || insert_dylib \
       --inplace \
       --all-yes \
       --strip-codesig \
       --add "@executable_path/$DYLIB_NAME.dylib" \
       "$MAIN"

if ! otool -l "$MAIN" 2>/dev/null | grep -q "$DYLIB_NAME"; then
  die "внедрение не удалось: LC_LOAD_DYLIB не найден в $MAIN"
fi
info "Внедрение подтверждено: LC_LOAD_DYLIB присутствует"

# ── 6. Подпись всего бандла ───────────────────────────────────────────────────
# Это ad-hoc подпись, чтобы iOS принял структуру. Окончательную подпись
# (с вашим сертификатом) сделает Sideloadly при установке.
info "Подпись бандла"
find "$APP" -name "*.framework" -type d -exec sh -c 'ldid -S "$1" 2>/dev/null || true' _ {} \;
ldid -S"$APP"

# ── 7. Упаковка ───────────────────────────────────────────────────────────────
info "Упаковка $OUT_IPA"
( cd "$WORK" && zip -qry "$ROOT/$OUT_IPA" Payload )
[ -f "$ROOT/$OUT_IPA" ] || die "не удалось собрать $OUT_IPA"

echo
echo "${GRN}Готово:${RST} $ROOT/$OUT_IPA"
echo "Установка:"
echo "  1. Sideloadly (бесплатно, Windows) — выбрать этот файл"
echo "  2. Указать свой Apple ID"
echo "  3. На iPhone: Настройки → Основные → Доверие сертификатам → включить"
echo "  4. iOS 16+: Настройки → Конфиденциальность → Режим разработчика"
echo
echo "${YLW}Ограничение:${RST} бесплатный профиль истекает через 7 дней —"
echo "переподписывать и ставить заново примерно раз в неделю."
echo
echo "Проверить, что dylib загрузилась: смотрите логи устройства"
echo "(Настройки → Основные → Обслуживание → Журналы → найдите TikTok)."