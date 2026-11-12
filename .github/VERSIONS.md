<!-- TỰ ĐỘNG TẠO bởi scripts/versions.py — đừng sửa tay. Muốn đổi số: sửa dòng `version:` đầu từng file. -->
# Phiên bản hệ thống build

## Hiện tại

| File | Phiên bản | Ngày | Mô tả |
|------|-----------|------|-------|
| `scripts/build_engine.py` | _chưa đánh số_ | — | — |
| `scripts/changelog.py` | _chưa đánh số_ | — | — |
| `scripts/clean.py` | _chưa đánh số_ | — | — |
| `scripts/engine_core.py` | _chưa đánh số_ | — | — |
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
| `scripts/plan.py` | **1.1.0** | 2026-11-06 | push đổi file Logos (.x .xm .xi .xmi) trong dự án cũng kích hoạt build (để sau khi merge PR sửa hook thì tự build lại) |
| `scripts/setup_theos.py` | _chưa đánh số_ | — | — |
| `scripts/tgbot.py` | _chưa đánh số_ | — | — |
| `scripts/upstream.py` | _chưa đánh số_ | — | — |
| `scripts/versions.py` | **1.0.0** | 2026-11-06 | tự dựng VERSIONS.md từ dòng version trong file + git log; cảnh báo quên tăng số |
| `tweaks.catalog.json` | **1.1.0** | 2026-11-06 | bỏ YTLite của tác giả; chia tweak bên thứ ba thành gói video/ui/khac |
| `workflows/Package.yml` | **3.1.0** | 2026-11-06 | ô Bộ tweak liệt kê thẳng dự án của bạn (tự thành repo:Tên), bỏ YTLite của tác giả; gói preset:video/ui/khac; tweak bên thứ ba lỗi thì bỏ qua (strict=1 để dừng) \| cần package_engine.py >= 2.2.0 |

File _chưa đánh số_ sẽ được ghi số ở lần sửa tiếp theo của chính file đó.

## Lịch sử đổi phiên bản

| Ngày | File | Phiên bản | Ghi chú | Commit |
|------|------|-----------|---------|--------|
| 2026-11-12 | `workflows/Package.yml` | 3.0.2 (lần đầu) | đổi tên workflow thành "Build Multi & Ký IPA"; nội dung giữ nguyên \| cần package_engine.py >= 2.1.0 | `576c4a5` |
| 2026-11-12 | `workflows/Package.yml` | 3.1.0 | ô Bộ tweak liệt kê thẳng dự án của bạn (tự thành repo:Tên), bỏ YTLite của tác giả; gói preset:video/ui/khac; tweak bên thứ ba lỗi thì bỏ qua (strict=1 để dừng) \| cần package_engine.py >= 2.2.0 | `f44106b` |
| 2026-11-12 | `tweaks.catalog.json` | 1.1.0 (lần đầu) | bỏ YTLite của tác giả; chia tweak bên thứ ba thành gói video/ui/khac | `26efdca` |
| 2026-11-12 | `scripts/versions.py` | 1.0.0 (lần đầu) | tự dựng VERSIONS.md từ dòng version trong file + git log; cảnh báo quên tăng số | `576c4a5` |
| 2026-11-12 | `scripts/plan.py` | 1.1.0 (lần đầu) | push đổi file Logos (.x .xm .xi .xmi) trong dự án cũng kích hoạt build (để sau khi merge PR sửa hook thì tự build lại) | `576c4a5` |
| 2026-11-12 | `scripts/package_engine.py` | 2.1.0 (lần đầu) | token -tên (bớt tweak), ô OPTIONS (name= bundle= flags= ent=), NO_PRESET, release_name; tương thích 2.0.0 | `576c4a5` |
| 2026-11-12 | `scripts/package_engine.py` | 2.2.0 | ô Bộ tweak nhận tên dự án trong repo (tự thành repo:Tên); tweak bên thứ ba lỗi build thì bỏ qua và báo (strict=1 để dừng); cảnh báo dự án chưa có trong danh sách chọn | `b65ff37` |
| 2026-11-12 | `scripts/modules/yt_handler.py` | 1.1.0 (lần đầu) | thêm HEADER_DIRS (dump của người dùng) để hooks.py nối dự án YouTube với headers/YouTubeHeader | `576c4a5` |
| 2026-11-12 | `scripts/hooks.py` | 1.2.0 (lần đầu) | list-dumps/latest-dump (tự chọn thư mục), dựng fingerprint từ lịch sử git, báo tên dump sai kèm danh sách hợp lệ, check-all xuất broken/broken_dumps | `576c4a5` |

## Quy ước

- `MAJOR`: đổi ô nhập hoặc cách file nối với file khác. `MINOR`: thêm tính năng tương thích. `PATCH`: sửa lỗi.
- Chỉ file được sửa mới tăng số. Workflow cảnh báo nếu file bị sửa mà số không đổi.
- Workflow ghi rõ engine tối thiểu (`REQUIRES_ENGINE`) và dừng sớm ở bước `plan` nếu thiếu.
- Workflow chỉ dùng một đuôi: `.yml`.
