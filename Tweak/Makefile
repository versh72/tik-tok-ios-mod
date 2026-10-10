# theos makefile — сборка TikTokRegion.dylib
#
# theos работает на Linux и macOS. На Windows — через WSL2.
# Установка: bash bootstrap && bash scripts/get_theos.sh

ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = TikTok

TWEAK_NAME = TikTokRegion
TikTokRegion_FILES = TikTokRegion.m
TikTokRegion_CFLAGS  = -fobjc-arc -Wno-deprecated-declarations
TikTokRegion_FRAMEWORKS = Foundation Security
TikTokRegion_LIBRARIES  = objc

include $(THEOS_MAKE_PATH)/tweak.mk

# dylib, а не bundle: внедряется напрямую в Payload/TikTok.app
internal-stage::
	@echo "→ $(THEOS_OBJ_DIR)/$(TWEAK_NAME).dylib"