# WLOC Giả lập định vị - Hướng dẫn sử dụng

## Nguyên lý hoạt động

```
Người dùng mở trang chọn điểm bằng Safari trên điện thoại
  → Chọn vị trí trên bản đồ / Tìm tên địa danh / Dán link bản đồ
  → Nhấn "Lưu vào thiết bị"
  → Trang gửi request https://gs-loc.apple.com/wloc-settings/save?lon=x&lat=y
  → Module proxy chặn request → wloc-settings.js ghi vào $persistentStore
  → Lần định vị Apple tiếp theo → wloc.js đọc toạ độ → sửa response định vị
```

Nếu module chưa được bật → request sẽ không bị chặn → trang sẽ báo kiểm tra cấu hình MITM/module.

---

## Cách sử dụng

### 1. Cài module (chỉ 1 lần)
Đăng ký module tương ứng với nền tảng đang dùng và bật MITM.

### 2. Mở trang chọn điểm
Mở trang chọn điểm công cộng trong Safari (nên thêm vào màn hình chính):
```
https://domain-worker-của-bạn/
```

> Worker là trang tĩnh thuần, không lưu trữ bất kỳ dữ liệu nào. Toạ độ được ghi trực tiếp vào thiết bị của bạn.

### 3. Chọn vị trí
- **Nhấn vào bản đồ** — chọn trực tiếp
- **Tìm tên địa danh** — nhập ví dụ "Bến Thượng Hải" v.v.
- **Dán link** — copy link chia sẻ từ Apple Maps / Google Maps / Cao Đức / Baidu
- **Vị trí hiện tại** — dùng định vị của trình duyệt

### 4. Lưu vào thiết bị
Nhấn "Lưu vào thiết bị" → hiện dấu ✓ là thành công.

---

## Triển khai trang chọn điểm công cộng

Worker là dịch vụ trang tĩnh thuần, không cần bind bất kỳ tài nguyên nào:

```bash
cd worker
npx wrangler deploy
```

Hoặc vào CF Dashboard → Workers → Tạo Worker mới → dán nội dung `wloc-worker.js` → Deploy.

Không cần KV, không cần database, không cần biến môi trường.

---

## Cấu hình module

Module gồm 2 quy tắc script (đã tự động cấu hình sẵn, người dùng không cần thao tác gì):

| Quy tắc | Loại | Đường dẫn | Chức năng |
|------|------|------|------|
| Apple WLOC | http-response | `/clls/wloc` | Sửa response định vị |
| WLOC Settings | http-request | `/wloc-settings/save` | Nhận dữ liệu ghi từ trang chọn điểm |

Hostname MITM: `gs-loc.apple.com, gs-loc-cn.apple.com` (đã có sẵn trong module)

---

## Xử lý sự cố khi lưu thất bại

Khi trang hiện cảnh báo màu đỏ, hãy kiểm tra:
1. **Module đã bật** — xác nhận công tắc module WLOC đang bật trong công cụ proxy
2. **Chứng chỉ MITM** — đã cài và tin cậy chứng chỉ CA
3. **Hostname MITM** — có chứa `gs-loc.apple.com`
4. **Kết nối proxy** — mạng hiện tại đang đi qua proxy (request của Safari phải đi qua proxy)

---

## Phương án khác: chỉnh tay (BoxJS)

Nếu không dùng trang chọn điểm, có thể chỉnh trực tiếp `wloc_settings` trong BoxJS:
```json
{"longitude":121.4737,"latitude":31.2304,"accuracy":25}
```

Thứ tự ưu tiên: toạ độ đã lưu > tham số module > giá trị mặc định
