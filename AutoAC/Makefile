ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoAC

AutoAC_FILES = Tweak.x
AutoAC_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk