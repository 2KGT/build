ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoAC

# Upstream_*.x / Upstream_*.xm do build_engine.py tự đồng bộ (YouTube X...) mỗi lần build
AutoAC_FILES = Tweak.x $(wildcard Upstream_*.x Upstream_*.xm)
AutoAC_CFLAGS = -fobjc-arc -Wno-error -Wno-deprecated-declarations
AutoAC_FRAMEWORKS = UIKit Foundation AVFoundation AVKit MediaPlayer CoreMedia Photos Security

include $(THEOS_MAKE_PATH)/tweak.mk

# Gói ngôn ngữ: thư mục AutoAC.bundle (en.lproj, vi.lproj/Localizable.strings) nằm cạnh Makefile.
# Sao chép vào gói .deb tại /Library/Application Support/AutoAC.bundle (tự thành /var/jb/... với rootless).
# Tệp .strings rỗng hoặc sai cú pháp sẽ bị bỏ khỏi gói (nếu không, bước đóng gói của Theos báo
# "Cannot parse a NULL or zero-length data" và hỏng cả bản build). Thiếu thư mục này tweak vẫn chạy
# bằng bảng dịch có sẵn trong Tweak.x.
after-stage::
	@if [ -d AutoAC.bundle ]; then \
		DEST="$(THEOS_STAGING_DIR)/Library/Application Support/AutoAC.bundle"; \
		mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support"; \
		rm -rf "$$DEST"; \
		cp -R AutoAC.bundle "$$DEST"; \
		find "$$DEST" -name '*.strings' | while read -r f; do \
			if [ ! -s "$$f" ]; then \
				echo "[AutoAC] bo qua tep rong: $$f"; rm -f "$$f"; \
			elif command -v plutil >/dev/null 2>&1 && ! plutil -lint "$$f" >/dev/null 2>&1; then \
				echo "[AutoAC] bo qua tep loi cu phap: $$f"; rm -f "$$f"; \
			fi; \
		done; \
		find "$$DEST" -type d -empty -delete 2>/dev/null || true; \
	fi
