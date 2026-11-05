# 🏛 Core System Changelog

Tệp này ghi lại các thay đổi quan trọng về cấu trúc hệ thống, quy trình Build và các tính năng cốt lõi của Repository.

---

## [1.2.0] - 2026-04-22
### 🚀 Cải tiến quy trình Build (Major Update)
- **Auto-Automation:** Hệ thống hiện đã tự động hoàn toàn quy trình: *Tăng Version -> Quét Changelog -> Build -> Clean Code -> Release*.
- **Smart Metadata:** Tự động trích xuất tính năng mới từ comment `// NEW:` và `// FIX:` trực tiếp trong mã nguồn `.xm`.
- **Auto-Cleanup:** Cơ chế tự động xóa comment sau build giúp giữ mã nguồn sạch sẽ và tránh lặp nội dung Release.
- **Isolate Build:** Tách biệt hoàn toàn môi trường build cho từng dự án trong `src/`, loại bỏ vấn đề lẫn lộn file `.deb`.

### 🛠 Cơ sở hạ tầng
- Tối ưu hóa GitHub Actions với quyền `contents: write` để tự động push ngược lại hệ thống.
- Chuẩn hóa cấu trúc thư mục `debs/` tập trung để làm nguồn cho các dự án tiếp theo.

---

## [1.1.0] - 2026-04-15
### 🏗 Tái cấu trúc Repository
- Chuyển đổi sang mô hình **Multi-Tweak Storage**: Toàn bộ dự án nằm trong thư mục `src/`.
- Tích hợp **Theos Action v1** giúp build trực tiếp trên máy ảo macOS của GitHub.

---

## [1.0.0] - 2026-04-01
### 🌱 Khởi tạo
- Thiết lập Repository và cấu trúc thư mục cơ bản.
- Cấu hình file workflow `.yml` sơ khai.

---

## 🛠 Lộ trình phát triển (Upcoming)
- [ ] **IPA Injector:** Phát triển script tự động tiêm (inject) các file `.deb` từ thư mục `debs/` vào file IPA mục tiêu.
- [ ] **External Source Support:** Hỗ trợ tải và tiêm các thư viện (.dylib, .deb) từ các nguồn GitHub hoặc URL bên ngoài.
- [ ] **Auto-Update Repo:** Tự động cập nhật file `Packages` và `Release` cho Cydia/Sileo Repo sau mỗi bản build thành công.

---

### ⚠️ Lưu ý hệ thống
- Mọi thay đổi về logic build cần được kiểm tra kỹ trên nhánh phát triển trước khi gộp vào `main`.
- Các file `CHANGELOG.md` trong từng dự án con chỉ phục vụ cho nội dung Release của dự án đó.
