TARGET := iphone:clang:latest:15.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTLiquidGlass

YTLiquidGlass_FILES = Tweak.x Sideloading.x
YTLiquidGlass_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
YTLiquidGlass_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
