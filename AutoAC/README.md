# AutoAC

<p align="center"><sub>Chạm 🇻🇳 hoặc 🇬🇧 để mở / thu gọn ngôn ngữ · Tap 🇻🇳 or 🇬🇧 to expand / collapse</sub></p>

<details open>
<summary><b>🇻🇳 Tiếng Việt</b></summary>

Tweak tùy chỉnh **YouTube** cho iOS (bản sideload hoặc jailbreak), viết bằng Theos/Logos. Gom mọi thứ vào một menu: tải video/âm thanh, bỏ qua đoạn tài trợ, tùy chỉnh thanh tab (kể cả Liquid Glass), ẩn bớt nội dung, nút tiện ích trong trình phát. Giao diện tiếng Việt và tiếng Anh.

## Mở menu
**Nhấn giữ logo YouTube** ở thanh trên (~0,5 giây). Menu chia nhóm: Bộ nhớ, Giao diện, Phát lại, Quảng cáo, Shorts, Tải xuống. Trang **(i)** cho biết số bản, nhật ký sự cố, dung lượng, chẩn đoán và nút thoát chế độ an toàn.

## Tính năng

**Tải xuống**
- Tải video (MP4, chọn chất lượng), âm thanh (M4A), ảnh bìa; cả video thường lẫn Short; có hàng chờ tải và tự tiếp tục khi mở lại app
- Lưu vào Ảnh hoặc chia sẻ (Tệp, app khác)
- Mở bảng tải từ: **Nút tải xuống** (thay nút Tải xuống gốc dưới video), mục **Tải xuống** trong menu **…** của video, và **Icon tải** trong Overlay
- Lấy phụ đề (dịch, mốc thời gian, lưu `.txt`), sao chép liên kết / tiêu đề / mô tả, lưu ảnh bài đăng cộng đồng, nhấn giữ bình luận để sao chép hoặc dịch

**Danh sách chờ cục bộ** (không cần Premium)
- Dùng nút **…** ở video: *Phát tiếp theo / Phát cuối cùng trong danh sách chờ* vào danh sách cục bộ; mục *Danh sách chờ* để xem, phát ngay hoặc xoá
- Hết video đang xem thì tự phát video kế (chỉ khi app đang mở)

**Phát lại**
- Nút trong trình phát: tốc độ (0,25x–3x), PiP, hẹn giờ ngủ (có mức *End*), phát ngoài (hệ thống / Infuse / VLC), chất lượng video, lặp video
- Tự thử lại khi video báo lỗi; tắt tự động phát; bật lặp / tắt tự cuộn Short
- **Tuỳ chỉnh Overlay:** kéo thả để xếp nút vào hàng trên, hàng dưới hoặc tắt

**Giao diện**
- **Tuỳ chỉnh tab:** kéo thả thứ tự, ẩn / hiện, đổi tên, thêm tab (Nhạc, Trực tiếp, Trò chơi, Tin tức, Lịch sử…), tab khi mở app, màu tab được chọn, nhãn tab
- **Thanh tab:** kiểu Mặc định hoặc Kính lỏng; thu gọn / tự ẩn khi cuộn ở mọi tab; ở tab Short theo giao diện sáng / tối của app
- **Kính lỏng** (iOS 26): thanh trên, bảng chọn, trình phát, nút Overlay
- Logo Premium, ẩn hiệu ứng logo lúc mở app

**Ẩn nội dung**
- Hàng video Short (chỉ ở Trang chủ, tìm kiếm, trang xem; **không** đụng tới Đã đăng ký, Thư viện, Lịch sử), bài đăng cộng đồng, Mix, game, thẻ mời Premium, nhãn quảng cáo trả phí, thẻ sản phẩm
- Shorts: ẩn từng nút ở cột phải, đĩa nhạc, thẻ tạm dừng; chụm hai ngón để làm sạch màn hình

**Quảng cáo và SponsorBlock**
- Bỏ qua đoạn tài trợ, tự quảng bá, nhắc like / đăng ký, mở đầu, kết… (chọn loại đoạn)
- Chặn popup Premium; chặn quảng cáo và phát nền khi build có YouTube X

**Bộ nhớ và hệ thống**
- Dọn cache (tay hoặc khi thoát app), sao lưu / khôi phục / đặt lại cài đặt, xem dung lượng từng thư mục
- Bỏ xác minh tuổi và giới hạn phát, tắt PiP Short, chế độ an toàn khi app thoát bất ngờ

## Cài đặt và build
Gói rootless (`arm64`, `arm64e`, iOS 14+). Tiêm `.deb` / `.dylib` vào IPA YouTube rồi sideload, hoặc cài qua Sileo / Cydia nếu có jailbreak. Cần [Theos](https://theos.dev) và iOS SDK:

```sh
make clean package FINALPACKAGE=1
```

| Tệp | Vai trò |
|---|---|
| `Tweak.x` | Toàn bộ mã AutoAC (Objective‑C, ARC) |
| `Sideloading.x` | Sửa đăng nhập cho YouTube sideload (từ YTLite) |
| `AutoAC.bundle/` | Chuỗi giao diện `en` / `vi`; thiếu thì dùng bảng dịch trong `Tweak.x` |
| `Upstream_*.x` | CI tự đồng bộ mỗi lần build (YouTube X, NoYTPremium…), không sửa tay |

## Lưu ý
- Hook gắn qua runtime và tự bỏ qua nếu YouTube đổi tên lớp / phương thức, nên bản YouTube mới có thể làm vài tính năng ngừng tác dụng. Khi báo lỗi hãy gửi báo cáo ở trang (i).
- Bộ lọc nội dung chỉ chạy ở đúng tab đã định, tab khác giữ nguyên để không để lại khoảng trống.

## Ghi công
**YouTube X**, **NoYTPremium**, **ytkace**, **YTLite** (kể cả `Sideloading.x`, dựa trên **IAmYouTube** của PoomSmart), dữ liệu **SponsorBlock** ([sponsor.ajay.app](https://sponsor.ajay.app)).

</details>

<details>
<summary><b>🇬🇧 English</b></summary>

A customization tweak for **YouTube** on iOS (sideloaded or jailbroken), written with Theos/Logos. Everything lives in one menu: download video/audio, skip sponsored segments, customize the tab bar (including Liquid Glass), hide clutter, and player utility buttons. Available in Vietnamese and English.

## Opening the menu
**Long-press the YouTube logo** in the top bar (~0.5 s). Groups: Storage, Appearance, Playback, Ads, Shorts, Downloads. The **(i)** page shows the build number, crash log, storage, diagnostics, and the safe-mode exit button.

## Features

**Downloads**
- Download video (MP4, choose quality), audio (M4A), cover image; regular videos and Shorts; a download queue that resumes when the app reopens
- Save to Photos or share (Files, other apps)
- Open the download sheet from: the **Download button** (replaces YouTube's Download button under the video), the **Download** item in a video's **…** menu, and the **Download icon** in the overlay
- Get subtitles (translated, timestamps, saved as `.txt`), copy link / title / description, save community-post images, long-press a comment to copy or translate

**Local queue** (no Premium needed)
- Use a video's **…** button: *Play next / Play last in queue* go into the local list; the *Queue* item lets you view, play now, or clear
- When the current video ends, the next one plays (only while the app is open)

**Playback**
- Player buttons: speed (0.25x–3x), PiP, sleep timer (with an *End* option), external player (system / Infuse / VLC), video quality, loop video
- Auto-retry on playback errors; disable autoplay; enable Short loop / disable Short auto-scroll
- **Customize overlay:** drag and drop buttons into the top row, bottom row, or off

**Appearance**
- **Customize tabs:** drag to reorder, show / hide, rename, add tabs (Music, Live, Gaming, News, History…), startup tab, selected-tab color, tab labels
- **Tab bar:** Default or Liquid Glass; collapses / auto-hides on scroll in every tab; on the Shorts tab it follows the app's light / dark appearance
- **Liquid Glass** (iOS 26): top bar, sheets, player, overlay buttons
- Premium logo, hide the launch logo animation

**Hide content**
- Shorts shelves (only on Home, search and the watch page; Subscriptions, Library and History are **left alone**), community posts, Mixes, games, Premium upsell cards, paid-promotion label, shop tags
- Shorts: hide each right-column button, the music disc, the pause card; pinch to clean the screen

**Ads and SponsorBlock**
- Skip sponsor, self-promo, like/subscribe reminders, intro, outro… (choose categories)
- Block Premium popups; ad blocking and background play when the build includes YouTube X

**Storage and system**
- Clear cache (manually or on exit), back up / restore / reset settings, per-folder storage usage
- Skip age verification and play limit, disable Shorts PiP, safe mode after unexpected exits

## Install and build
Rootless package (`arm64`, `arm64e`, iOS 14+). Inject the `.deb` / `.dylib` into a YouTube IPA and sideload, or install through Sileo / Cydia on a jailbroken device. Requires [Theos](https://theos.dev) and an iOS SDK:

```sh
make clean package FINALPACKAGE=1
```

| File | Role |
|---|---|
| `Tweak.x` | All AutoAC code (Objective‑C, ARC) |
| `Sideloading.x` | Sign-in fix for sideloaded YouTube (from YTLite) |
| `AutoAC.bundle/` | `en` / `vi` UI strings; if missing, the built-in table in `Tweak.x` is used |
| `Upstream_*.x` | Synced by CI on every build (YouTube X, NoYTPremium…), do not edit by hand |

## Notes
- Hooks attach at runtime and skip themselves if YouTube renames a class or method, so a new YouTube version may disable a few features. When reporting a bug, attach the report from the (i) page.
- Content filters run only in the tabs they are meant for; other tabs are left untouched so no blank space is left behind.

## Credits
**YouTube X**, **NoYTPremium**, **ytkace**, **YTLite** (including `Sideloading.x`, based on PoomSmart's **IAmYouTube**), **SponsorBlock** data ([sponsor.ajay.app](https://sponsor.ajay.app)).

</details>
