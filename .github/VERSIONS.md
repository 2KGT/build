<!-- TỰ ĐỘNG TẠO bởi scripts/versions.py — đừng sửa tay. Muốn đổi số: sửa dòng `version:` đầu từng file. -->
# Phiên bản hệ thống build

## Hiện tại

| File | Phiên bản | Ngày | Mô tả |
|------|-----------|------|-------|
| `scripts/build_engine.py` | **2.1.0** | 2026-11-13 | build nhiều hệ sinh thái (INPUT_ECO), tự soạn mô tả/ghi chú (INPUT_NOTES → control tạm thời + RELEASE_NOTES.md), xuất has_dylib/ecosystems/release_title |
| `scripts/changelog.py` | _chưa đánh số_ | — | — |
| `scripts/clean.py` | _chưa đánh số_ | — | — |
| `scripts/deb_desc.py` | **1.0.0** | 2026-11-13 | soạn mô tả + ghi chú phiên bản tự động (sửa lỗi / tính năng / chú ý / hỗ trợ tốt nhất) cho .deb, Release, Sileo, Telegram |
| `scripts/engine_core.py` | **2.1.0** | 2026-11-13 | build nhiều hệ sinh thái (Rootless/Rootful/Dylib), tự soạn mô tả vào control tạm thời, thu .dylib; không đổi cách gọi cũ |
| `scripts/header_tools.py` | _chưa đánh số_ | — | — |
| `scripts/hooks.py` | **1.2.0** | 2026-11-06 | list-dumps/latest-dump (tự chọn thư mục), dựng fingerprint từ lịch sử git, báo tên dump sai kèm danh sách hợp lệ, check-all xuất broken/broken_dumps |
| `scripts/modules/bilibili_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/fb_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/instagram_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/spotify_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/tiktok_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/twitter_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/yt_handler.py` | **1.1.0** | 2026-11-06 | thêm HEADER_DIRS (dump của người dùng) để hooks.py nối dự án YouTube với headers/YouTubeHeader |
| `scripts/package_engine.py` | **2.2.0** | 2026-11-06 | ô Bộ tweak nhận tên dự án trong repo (tự thành repo:Tên); tweak bên thứ ba lỗi build thì bỏ qua và báo (strict=1 để dừng); cảnh báo dự án chưa có trong danh sách chọn |
| `scripts/plan.py` | **1.1.1** | 2026-11-13 | khôi phục: chỉ đổi <Dự án>/control mới kích hoạt build khi push (sửa file Logos/xoá file KHÔNG tự build) |
| `scripts/publish.py` | **1.0.0** | 2026-11-13 | phát hành .deb/.dylib: (1) GitHub Release trong repo Sileo, (2) đẩy file thẳng vào repo/debs + repo/dylibs; cùng ghi chú |
| `scripts/setup_theos.py` | _chưa đánh số_ | — | — |
| `scripts/tgbot.py` | **1.1.0** | 2026-11-13 | gửi cả .deb và .dylib; nội dung tin lấy từ RELEASE_NOTES.md; hiện liên kết Release / trạng thái đẩy lên repo Sileo |
| `scripts/upstream.py` | _chưa đánh số_ | — | — |
| `scripts/versions.py` | **1.0.0** | 2026-11-06 | tự dựng VERSIONS.md từ dòng version trong file + git log; cảnh báo quên tăng số |
| `tweaks.catalog.json` | **1.1.0** | 2026-11-06 | bỏ YTLite của tác giả; chia tweak bên thứ ba thành gói video/ui/khac |

File _chưa đánh số_ sẽ được ghi số ở lần sửa tiếp theo của chính file đó.

## Lịch sử đổi phiên bản

| Ngày | File | Phiên bản | Ghi chú | Commit |
|------|------|-----------|---------|--------|
| 2026-11-16 | `tweaks.catalog.json` | 1.1.0 (lần đầu) | bỏ YTLite của tác giả; chia tweak bên thứ ba thành gói video/ui/khac | `dcfd0e4` |
| 2026-11-16 | `scripts/versions.py` | 1.0.0 (lần đầu) | tự dựng VERSIONS.md từ dòng version trong file + git log; cảnh báo quên tăng số | `dcfd0e4` |
| 2026-11-16 | `scripts/tgbot.py` | 1.1.0 (lần đầu) | gửi cả .deb và .dylib; nội dung tin lấy từ RELEASE_NOTES.md; hiện liên kết Release / trạng thái đẩy lên repo Sileo | `dcfd0e4` |
| 2026-11-16 | `scripts/publish.py` | 1.0.0 (lần đầu) | phát hành .deb/.dylib: (1) GitHub Release trong repo Sileo, (2) đẩy file thẳng vào repo/debs + repo/dylibs; cùng ghi chú | `dcfd0e4` |
| 2026-11-16 | `scripts/plan.py` | 1.1.1 (lần đầu) | khôi phục: chỉ đổi <Dự án>/control mới kích hoạt build khi push (sửa file Logos/xoá file KHÔNG tự build) | `dcfd0e4` |
| 2026-11-16 | `scripts/package_engine.py` | 2.2.0 (lần đầu) | ô Bộ tweak nhận tên dự án trong repo (tự thành repo:Tên); tweak bên thứ ba lỗi build thì bỏ qua và báo (strict=1 để dừng); cảnh báo dự án chưa có trong danh sách chọn | `dcfd0e4` |
| 2026-11-16 | `scripts/modules/yt_handler.py` | 1.1.0 (lần đầu) | thêm HEADER_DIRS (dump của người dùng) để hooks.py nối dự án YouTube với headers/YouTubeHeader | `dcfd0e4` |
| 2026-11-16 | `scripts/hooks.py` | 1.2.0 (lần đầu) | list-dumps/latest-dump (tự chọn thư mục), dựng fingerprint từ lịch sử git, báo tên dump sai kèm danh sách hợp lệ, check-all xuất broken/broken_dumps | `dcfd0e4` |
| 2026-11-16 | `scripts/engine_core.py` | 2.1.0 (lần đầu) | build nhiều hệ sinh thái (Rootless/Rootful/Dylib), tự soạn mô tả vào control tạm thời, thu .dylib; không đổi cách gọi cũ | `dcfd0e4` |
| 2026-11-16 | `scripts/deb_desc.py` | 1.0.0 (lần đầu) | soạn mô tả + ghi chú phiên bản tự động (sửa lỗi / tính năng / chú ý / hỗ trợ tốt nhất) cho .deb, Release, Sileo, Telegram | `dcfd0e4` |
| 2026-11-16 | `scripts/build_engine.py` | 2.1.0 (lần đầu) | build nhiều hệ sinh thái (INPUT_ECO), tự soạn mô tả/ghi chú (INPUT_NOTES → control tạm thời + RELEASE_NOTES.md), xuất has_dylib/ecosystems/release_title | `dcfd0e4` |

## Quy ước

- `MAJOR`: đổi ô nhập hoặc cách file nối với file khác. `MINOR`: thêm tính năng tương thích. `PATCH`: sửa lỗi.
- Chỉ file được sửa mới tăng số. Workflow cảnh báo nếu file bị sửa mà số không đổi.
- Workflow ghi rõ engine tối thiểu (`REQUIRES_ENGINE`) và dừng sớm ở bước `plan` nếu thiếu.
- Workflow chỉ dùng một đuôi: `.yml`.
