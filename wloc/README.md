<p align="center">
  <img src="wloc.jpg" width="144" />
</p>

# Apple WLOC - Sửa vị trí định vị

Sửa toạ độ trả về từ dịch vụ định vị mạng của Apple (WiFi/trạm phát sóng), giúp giả lập vị trí định vị mạng trên iOS. Chỉ cần mở trang chọn điểm trực tuyến và chọn vị trí là có hiệu lực ngay, không cần tự nhập kinh độ/vĩ độ.

---

## Địa chỉ đăng ký (Subscribe)

**Surge:**
https://raw.githubusercontent.com/2KGT/build/refs/heads/main/wloc/modules/wloc.sgmodule

**Quantumult X:**
https://raw.githubusercontent.com/2KGT/build/refs/heads/main/wloc/modules/wloc.conf

**Loon:**
https://raw.githubusercontent.com/2KGT/build/refs/heads/main/wloc/modules/wloc.lpx

**Stash:**
https://raw.githubusercontent.com/2KGT/build/refs/heads/main/wloc/modules/wloc.stoverride

**Shadowrocket (Tiểu Hoả Tiễn):**
https://raw.githubusercontent.com/2KGT/build/refs/heads/main/wloc/modules/wloc.module

> Egern có thể dùng trực tiếp module của Surge
> Stash vui lòng đăng ký trực tiếp file `.stoverride` ở trên, không cần chuyển đổi qua Script Hub

---

## Shortcuts (Phím tắt) - khuyên dùng, tiện nhất

Dùng Shortcuts để chuyển đổi / xoá vị trí trực tiếp, không cần mở trang chọn điểm:

- **Đặt vị trí WLOC**: https://www.icloud.com/shortcuts/a69bb22ad8724e4fb279ab4bb4119e0d
- **Khôi phục WLOC**: https://www.icloud.com/shortcuts/38f9c92948564e89b56f39c4f7ca52ea

**Cách dùng**

- **Đặt vị trí:** Trong app Bản đồ, chọn vị trí (nhấn giữ trên bản đồ) → Chia sẻ → chọn "Đặt vị trí WLOC" để chuyển đổi.
  - Apple Maps: chọn điểm → Chia sẻ → "Đặt vị trí WLOC"
  - Bản đồ Cao Đức (Amap): chọn điểm → Chia sẻ → **Thêm** → "Đặt vị trí WLOC"
- **Xoá vị trí:** Nhấn "Khôi phục WLOC" để khôi phục định vị thật.

Hỗ trợ Apple Maps, Cao Đức (bao gồm link rút gọn, tự động theo redirect + chuyển đổi toạ độ GCJ-02→WGS84).

> Điều kiện: đã bật proxy + đã bật module + đã tin cậy chứng chỉ `gs-loc.apple.com`. Phương án trang chọn điểm (Worker / Pages) vẫn được giữ lại, xem bên dưới.

---

### Về việc phân tích link bản đồ (worker)

Để Apple Maps và Cao Đức dùng chung một luồng xử lý, link được gửi thống nhất tới `wloc-spoofer.wloc.workers.dev/api/parse` để phân tích:

- **Cao Đức (Amap)**: link chia sẻ ra là link rút gọn, toạ độ thật chỉ nằm trong header `Location` của redirect 302, và là toạ độ lệch kiểu GCJ-02. Shortcuts vừa không đọc được header redirect, vừa khó tự chuyển đổi toạ độ, nên worker sẽ theo redirect → lấy toạ độ → chuyển GCJ-02→WGS84 → trả về kinh độ/vĩ độ.
- **Apple Maps**: link mang sẵn `coordinate=vĩ độ,kinh độ`, nhưng **ở Trung Quốc đại lục cũng là toạ độ lệch GCJ-02**, nên cũng được worker chuyển đổi GCJ-02→WGS84 giống như Cao Đức trước khi trả về; toạ độ ở nước ngoài sẽ tự động bỏ qua bước chuyển đổi (kiểm tra `out_of_china`) và trả về nguyên bản. Ngoài việc thống nhất hệ toạ độ, dùng chung 1 API cũng giúp xử lý đồng bộ link rút gọn, link kèm trong văn bản, giải mã tên địa điểm, v.v.

**Về quyền riêng tư:** `/api/parse` chỉ đơn thuần chuyển tiếp và phân tích — nhận link → theo redirect → phân tích toạ độ → trả JSON, toàn bộ quá trình không ghi vào bất kỳ nơi lưu trữ nào, không ghi log, không cache, xử lý xong là xoá ngay.

**Nếu không yên tâm, có thể tự triển khai:** mã nguồn worker hoàn toàn mã nguồn mở, bạn có thể tự triển khai một bản để thay thế địa chỉ trên:

- Logic phân tích: [`worker/src/parse.js`](worker/src/parse.js), route: [`worker/src/index.js`](worker/src/index.js)
- Sau khi triển khai xong, chỉ cần đổi `wloc-spoofer.wloc.workers.dev` trong Shortcuts thành domain worker của riêng bạn.

---

<details>
<summary><b>Cách sử dụng</b></summary>

1. Đăng ký module và bật MITM
2. Mở trang chọn điểm trực tuyến (Worker công cộng, nên thêm vào màn hình chính)
3. Chọn vị trí trên bản đồ / tìm tên địa danh / dán link bản đồ
4. Nhấn "Lưu vào thiết bị"
5. Lần định vị Apple tiếp theo sẽ tự động có hiệu lực

Hỗ trợ phân tích link Apple Maps / Google Maps / Cao Đức / Baidu / văn bản toạ độ.

> **Lưu ý với iOS 26/27 trở lên:** Từ iOS 26, Apple đã tăng cường đáng kể cơ chế cache định vị của `locationd`. Hệ thống sẽ lưu kết quả định vị thật đã lấy được vào bộ nhớ và tái sử dụng trong thời gian dài. Nghĩa là sau khi cài module hoặc đổi toạ độ mục tiêu, dù script đã sửa thành công response WLOC (log hiển thị "đã sửa"), hệ thống vẫn có thể tiếp tục dùng toạ độ cũ trong cache, khiến định vị trông như chưa đổi.
>
> **Cách khắc phục: khởi động lại thiết bị.** Khởi động lại sẽ xoá cache bộ nhớ của `locationd`, khi hệ thống gửi lại request WLOC sẽ nhận được toạ độ đã sửa. Trên iOS 26+, bật chế độ máy bay hay tắt dịch vụ định vị **không** xoá được cache này, bắt buộc phải khởi động lại máy. iOS 15~18 thường không cần khởi động lại vẫn có hiệu lực.

**Quy trình khuyên dùng cho các bản hệ điều hành mới (tỷ lệ thành công cao nhất):**

Cách 1:
1. Vào trang chọn điểm, chọn vị trí cần đổi và lưu vào thiết bị trước
2. Bật chế độ máy bay → tắt Dịch vụ định vị → khởi động lại thiết bị
3. Tắt chế độ máy bay (tắt cả WiFi) → kết nối proxy (xác nhận icon VPN xuất hiện) → bật lại Dịch vụ định vị
4. Mở Bản đồ để kiểm tra

Cách 2:
1. Tắt Dịch vụ định vị
2. Vào trang chọn điểm, chọn vị trí và lưu vào thiết bị
3. Bật Dịch vụ định vị → khi hiện hộp thoại "Cho phép truy cập vị trí", chọn **"Lần tới hoặc khi tôi chia sẻ"**
4. Mở Bản đồ để kiểm tra

</details>

<details>
<summary><b>Nguyên lý hoạt động</b></summary>

```
Trang chọn điểm → gửi request gs-loc.apple.com/wloc-settings/save?lon=x&lat=y
              → module proxy chặn request → wloc-settings.js ghi vào $persistentStore
              → lần WLOC tiếp theo → wloc.js đọc toạ độ → patch vào response protobuf
```

Module gồm 2 quy tắc:
- `wloc.js` — chặn response `/clls/wloc`, phân tích protobuf và thay toạ độ
- `wloc-settings.js` — chặn request `/wloc-settings/save`, ghi vào bộ nhớ lưu trữ cố định (persistent storage)

</details>

<details>
<summary><b>Cấu hình tham số</b></summary>

| Tham số | Mô tả | Giá trị mặc định |
|------|------|--------|
| longitude | Kinh độ mục tiêu (ưu tiên vị trí chọn online) | null (truyền qua, không đổi) |
| latitude | Vĩ độ mục tiêu (ưu tiên vị trí chọn online) | null (truyền qua, không đổi) |
| accuracy | Độ chính xác (mét) | 25 |
| logLevel | Cấp độ log | info |

Thứ tự ưu tiên: vị trí đã lưu qua trang chọn điểm online > tham số module > giá trị mặc định

</details>

<details>
<summary><b>Huỷ giả lập vị trí / Khôi phục định vị thật</b></summary>

**Cách 1: Tắt hoặc xoá module** (khuyên dùng)

Sau khi tắt module, script không còn chặn request WLOC nữa, hệ thống tự động khôi phục định vị thật. iOS 26+ cần khởi động lại thiết bị để xoá cache định vị.

**Cách 2: Xoá dữ liệu đã lưu (chế độ truyền qua - passthrough)**

Sau khi xoá toạ độ đã lưu, script sẽ vào **chế độ truyền qua** — không sửa response WLOC nữa, cho dữ liệu gốc đi qua nguyên vẹn, hệ thống tự động khôi phục định vị GPS thật.

**Điều kiện kích hoạt chế độ truyền qua:** Khi dữ liệu lưu trữ rỗng (null) và tham số module vẫn là giá trị mặc định (113.94114, 22.544577), script sẽ xác định người dùng chưa tự đặt toạ độ và tự động bỏ qua việc sửa đổi. Không cần đổi tham số mặc định của module, chỉ cần xoá dữ liệu đã lưu là đủ để kích hoạt chế độ truyền qua.

Xoá dữ liệu lưu trữ trong công cụ proxy, tên field là `wloc_settings`:

- **Surge** — chạy trong trình soạn script: `$persistentStore.write(null, "wloc_settings")`
- **Quantumult X** — chạy: `$prefs.removeValueForKey("wloc_settings")`
- **Loon** — chạy: `$persistentStore.write(null, "wloc_settings")`

Xoá xong khởi động lại thiết bị là khôi phục định vị thật. Không cần tắt module, script sẽ tự phát hiện không có toạ độ tự đặt và bỏ qua việc sửa đổi.

> **Lưu ý:** Nếu người dùng đã tự sửa kinh/vĩ độ trong tham số module (khác với mặc định 113.94114, 22.544577), thì dù có xoá dữ liệu đã lưu, script vẫn sẽ dùng toạ độ trong tham số module để sửa đổi. Chỉ khi giữ nguyên tham số mặc định thì xoá dữ liệu lưu trữ mới kích hoạt được chế độ truyền qua.

</details>

<details>
<summary><b>Tính năng lưu vị trí yêu thích</b></summary>

Trang chọn điểm trực tuyến hỗ trợ lưu nhiều vị trí yêu thích để tiện chuyển đổi qua lại:

- **Thêm mục yêu thích**: chọn vị trí xong nhấn "Lưu vị trí yêu thích" → nhập tên ghi chú (hỗ trợ tiếng Trung/Anh/số, tối đa 30 ký tự) → lưu
- **Chuyển đổi nhanh**: nhấn vào vị trí trong danh sách yêu thích → bản đồ tự động nhảy tới → nhấn "Lưu vào thiết bị" là chuyển xong
- **Đánh dấu đang hiệu lực**: mục yêu thích trùng với toạ độ đã lưu trên thiết bị sẽ hiển thị "✓ Đang hiệu lực"
- **Quản lý xoá**: xoá từng mục (nút ×) hoặc xoá toàn bộ
- **Toạ độ đang hiệu lực**: trang hiển thị dữ liệu đã lưu trên thiết bị (wloc_settings), hỗ trợ làm mới và xoá

**Về việc lưu trữ dữ liệu:**
- **Danh sách yêu thích** → lưu trong `localStorage` của trình duyệt (chỉ phục vụ thao tác UI tiện lợi trên trang chọn điểm)
- **Toạ độ đang hiệu lực** → lưu trong bộ nhớ cố định `$persistentStore` của công cụ proxy (dữ liệu script thực sự đọc khi chạy)

Hai loại này lưu trữ độc lập nhau. Danh sách yêu thích là dữ liệu phụ trợ phía trình duyệt, xoá cache trình duyệt hoặc đổi trình duyệt thì phải lưu lại từ đầu, nhưng không ảnh hưởng đến toạ độ đang hiệu lực đã lưu trên thiết bị.

</details>

<details>
<summary><b>Tự triển khai Worker (khuyên dùng)</b></summary>

Trang chọn điểm công cộng có giới hạn số lượng request, khuyên bạn nên tự triển khai một bản riêng:

- **Địa chỉ đang dùng (Pages, deploy qua Git integration)**: `https://build-4sl.pages.dev/`

> Lưu ý: bản đang chạy thực tế được deploy qua Cloudflare Pages (Connect to Git), không dùng nút 1-click Workers dưới đây. Giữ hướng dẫn dưới cho ai muốn triển khai theo cách Workers CLI thay thế.

**Triển khai nhanh 1 cú nhấp (Workers):**

[![Deploy to Cloudflare Workers](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/2KGT/build/tree/main/wloc/worker)

> Triển khai 1 cú nhấp chỉ hỗ trợ chế độ Workers, nhấn nút rồi làm theo hướng dẫn cấp quyền là xong.

**Triển khai thủ công (Workers):**

```bash
# 1. Clone repo
git clone https://github.com/2KGT/build.git
cd build/wloc/worker

# 2. Cài dependency
npm install

# 3. Đăng nhập Cloudflare (lần đầu cần làm)
npx wrangler login

# 4. Triển khai
npm run deploy
```

Triển khai thành công sẽ có địa chỉ Worker của riêng bạn (ví dụ `https://wloc-spoofer.<subdomain-của-bạn>.workers.dev`), dùng địa chỉ này để chọn điểm.

> Tài khoản miễn phí cho phép 100.000 request/ngày, dùng cá nhân là quá đủ.

<details>
<summary>Nâng cao: Triển khai Pages</summary>

Triển khai Pages không hỗ trợ nút 1 cú nhấp, cần chạy tay:

```bash
git clone https://github.com/2KGT/build.git
cd build/wloc/worker
npm install
npx wrangler pages deploy dist --project-name <tên-project-tuỳ-chỉnh>
```

Khi triển khai sẽ được hỏi thiết lập production branch, nhập `main` là được. Triển khai xong sẽ có địa chỉ `https://<tên-project>.pages.dev`.

Pages và Workers có chức năng hoàn toàn giống nhau, chọn cái nào tuỳ ý.

</details>

</details>

<details>
<summary><b>Lưu ý</b></summary>

- Cần tin cậy chứng chỉ MITM cho `gs-loc.apple.com` và `gs-loc-cn.apple.com`
- Chỉ sửa định vị mạng (WiFi/trạm phát sóng), không ảnh hưởng đến định vị phần cứng GPS
- Khi tín hiệu GPS mạnh, iOS có thể bỏ qua kết quả định vị mạng
- Hiệu quả tốt nhất ở các tình huống trong nhà, chủ yếu dùng định vị WiFi
- Trang chọn điểm cần dùng trong chế độ có proxy (Safari phải đi qua proxy mới chặn được request lưu)

</details>

---

## Lời cảm ơn

- [proxypin-wloc-spoofer](https://github.com/FFF686868/proxypin-wloc-spoofer) - Ý tưởng gốc về sửa định vị WLOC, bởi FFF686868
- [NSNanoCat/Util](https://github.com/NSNanoCat/util) - Framework công cụ script đa nền tảng
