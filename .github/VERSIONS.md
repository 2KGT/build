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
| `scripts/package engine.py` | **2.0.0** | 2026-11-06 | ký giả/chứng chỉ, tự biên dịch repo:, token none, form gọn |
| `scripts/plan.py` | _chưa đánh số_ | — | — |
| `scripts/setup_theos.py` | _chưa đánh số_ | — | — |
| `scripts/tgbot.py` | _chưa đánh số_ | — | — |
| `scripts/upstream.py` | _chưa đánh số_ | — | — |
| `scripts/versions.py` | **1.0.0** | 2026-11-06 | tự dựng VERSIONS.md từ dòng version trong file + git log; cảnh báo quên tăng số |
| `tweaks.catalog.json` | _chưa đánh số_ | — | — |
| `workflows/tweaks.yml` | _chưa đánh số_ | — | — |

File _chưa đánh số_ sẽ được ghi số ở lần sửa tiếp theo của chính file đó.

## Lịch sử đổi phiên bản

| Ngày | File | Phiên bản | Ghi chú | Commit |
|------|------|-----------|---------|--------|
| 2026-11-06 | `scripts/versions.py` | 1.0.0 (lần đầu) | tự dựng VERSIONS.md từ dòng version trong file + git log; cảnh báo quên tăng số | `08fbb67` |
| 2026-11-06 | `scripts/package engine.py` | 2.0.0 (lần đầu) | ký giả/chứng chỉ, tự biên dịch repo:, token none, form gọn | `08fbb67` |

## Quy ước

- `MAJOR`: đổi ô nhập hoặc cách file nối với file khác. `MINOR`: thêm tính năng tương thích. `PATCH`: sửa lỗi.
- Chỉ file được sửa mới tăng số. Workflow cảnh báo nếu file bị sửa mà số không đổi.
- Workflow ghi rõ engine tối thiểu (`REQUIRES_ENGINE`) và dừng sớm ở bước `plan` nếu thiếu.
- Workflow chỉ dùng một đuôi: `.yml`.
