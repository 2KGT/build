TARGET := iphone:clang:latest:15.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = YouTube
include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
TWEAK_NAME = Liquid
Liquid_FILES = Tweak.x Sideloading.x
Liquid_FRAMEWORKS = UIKit QuartzCore CoreImage Accelerate
Liquid_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
Liquid_LIBRARIES = substrate
