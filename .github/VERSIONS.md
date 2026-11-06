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
| `scripts/modules/bilibili_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/fb_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/instagram_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/spotify_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/tiktok_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/twitter_handler.py` | _chưa đánh số_ | — | — |
| `scripts/modules/yt_handler.py` | _chưa đánh số_ | — | — |
| `scripts/package_engine.py` | **2.0.0** | 2026-11-06 | ký giả/chứng chỉ, tự biên dịch repo:, token none, form gọn |
| `scripts/plan.py` | _chưa đánh số_ | — | — |
| `scripts/setup_theos.py` | _chưa đánh số_ | — | — |
| `scripts/tgbot.py` | _chưa đánh số_ | — | — |
| `scripts/upstream.py` | _chưa đánh số_ | — | — |
| `scripts/versions.py` | **1.0.0** | 2026-11-06 | tự dựng VERSIONS.md từ dòng version trong file + git log; cảnh báo quên tăng số |
| `tweaks.catalog.json` | _chưa đánh số_ | — | — |
| `workflows/Dump-Unified.yml` | **2.0.0** | 2026-11-06 | danh sách chọn thư mục header, Bridge.h + ClassList.txt, Selectors.txt tuỳ chọn; đuôi .yml |
| `workflows/Package.yml` | **2.0.0** | 2026-11-06 | form gọn 11 ô, ký giả/chứng chỉ, repo: tự biên dịch, token none \| cần package_engine.py >= 2.0.0 |
| `workflows/Versions.yml` | **1.0.0** | 2026-11-06 | tự dựng .github/VERSIONS.md khi push, cảnh báo quên tăng version |
| `workflows/tweaks.yml` | _chưa đánh số_ | — | — |

File _chưa đánh số_ sẽ được ghi số ở lần sửa tiếp theo của chính file đó.

## Lịch sử đổi phiên bản

_Chưa có lịch sử git cho các file đã đánh số (sẽ xuất hiện sau commit đầu tiên chứa dòng `version:`)._

## Quy ước

- `MAJOR`: đổi ô nhập hoặc cách file nối với file khác. `MINOR`: thêm tính năng tương thích. `PATCH`: sửa lỗi.
- Chỉ file được sửa mới tăng số. Workflow cảnh báo nếu file bị sửa mà số không đổi.
- Workflow ghi rõ engine tối thiểu (`REQUIRES_ENGINE`) và dừng sớm ở bước `plan` nếu thiếu.
- Workflow chỉ dùng một đuôi: `.yml`.
