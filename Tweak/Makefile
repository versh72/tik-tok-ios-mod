# theos makefile — сборка TikTokRegion.dylib
#
# Собирается на macOS (нужен Xcode и iOS SDK) — вручную или через CI,
# см. .github/workflows/build-tweak.yml

# arm64 — потому что подменяется App Store IPA, а он arm64 даже на
# arm64e-устройствах (A14 и новее). Для джейлбрейк-пути нужен arm64e,
# но эти две архитектуры нельзя смешивать: у каждой свой package-конфиг,
# и make package падает, если он задан только для одной.
ARCHS = arm64
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = TikTok

TWEAK_NAME = TikTokRegion
TikTokRegion_FILES = TikTokRegion.m
TikTokRegion_CFLAGS  = -fobjc-arc -Wno-deprecated-declarations
TikTokRegion_FRAMEWORKS = Foundation Security
TikTokRegion_LIBRARIES  = objc

# THEOS_MAKE_PATH обязателен: без него include превращается в путь
# "/tweak.mk" и сборка падает с "No such file or directory".
# Значение по умолчанию — на случай, если переменная не экспортирована.
THEOS_MAKE_PATH ?= $(THEOS)/makefiles

include $(THEOS_MAKE_PATH)/tweak.mk