# Build with THEOS set (e.g. export THEOS=~/theos).
# Produces libRXStickerGifCompanion.dylib — inject into TikTok.app/Frameworks
# alongside ___RXTikTok.dylib (load after RX so this runs on top of it).
#
# Sideload: use insert_dylib / your IPA tool; keep bundle id filter matching app.

ARCHS = arm64
TARGET = iphone:clang:latest:14.0

INSTALL_TARGET_PROCESSES = TikTok

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RXStickerGifCompanion

RXStickerGifCompanion_FILES = Tweak.x
RXStickerGifCompanion_CFLAGS = -fobjc-arc -Wno-module-import-in-extern-c
RXStickerGifCompanion_FRAMEWORKS = Foundation

include $(THEOS)/makefiles/tweak.mk
