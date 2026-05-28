FINALPACKAGE = 1
# Hỗ trợ cả arm64 và arm64e
ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouMod
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FILES = $(wildcard Files/*.x)

include $(THEOS_MAKE_PATH)/tweak.mk

# Thêm bước sau khi build để copy dylib ra output
# ... (giữ nguyên các phần trên của bạn)

include $(THEOS_MAKE_PATH)/tweak.mk

# Dùng cú pháp này để copy an toàn hơn
after-package::
	@mkdir -p output
	@echo "Đang copy file sang thư mục output..."
	@find . -name "*.dylib" -exec cp -f {} output/ \;
	@find packages -name "*.deb" -exec cp -f {} output/ \;
	@echo "Hoàn tất copy!"
