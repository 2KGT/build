TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SampleTweak
SampleTweak_FILES = Tweak.x
SampleTweak_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/tweak.mk
