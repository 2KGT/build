TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = BilibiliHD

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BilibiliHD
BilibiliHDTweak_FILES = Tweak.x
BilibiliHDTweak_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)

include $(THEOS_MAKE_PATH)/tweak.mk