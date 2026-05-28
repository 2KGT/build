# Cấu hình thiết bị và Root
ifeq ($(ROOTLESS),1)
    THEOS_PACKAGE_SCHEME=rootless
else ifeq ($(ROOTHIDE),1)
    THEOS_PACKAGE_SCHEME=roothide
endif

FINALPACKAGE = 1
ARCHS = arm64
TARGET := iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouMod
# Định nghĩa các file nguồn rõ ràng
YouMod_FILES = $(wildcard Files/*.x)

# Thêm các framework cần thiết
YouMod_FRAMEWORKS = UIKit Foundation Security MediaPlayer

# Các Flag cực kỳ quan trọng để bỏ qua lỗi biên dịch "nghiêm khắc"
# -Wno-unused-variable: Bỏ qua lỗi khai báo biến không dùng
# -Wno-unused-function: Bỏ qua lỗi hàm không dùng
# -Wno-objc-multiple-method-names: Bỏ qua lỗi trùng tên method
# -undefined dynamic_lookup: Cần thiết để link các hàm private của YouTube
YouMod_CFLAGS = -fobjc-arc -IFiles -Wno-unused-variable -Wno-unused-function -Wno-objc-multiple-method-names
YouMod_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
