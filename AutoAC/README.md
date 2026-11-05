# AutoAC

<p align="center"><sub>Chạm vào 🇻🇳 hoặc 🇬🇧 bên dưới để mở hoặc thu gọn ngôn ngữ · Tap 🇻🇳 or 🇬🇧 below to expand or collapse a language</sub></p>

<details open>
<summary><b>🇻🇳 Tiếng Việt</b></summary>

Tweak tùy chỉnh **YouTube** cho iOS (YouTube bản sideload), viết bằng Theos/Logos. Gom vào một menu duy nhất: tải video và âm thanh, bỏ qua đoạn tài trợ, tùy chỉnh thanh tab (kể cả kiểu Liquid Glass), ẩn bớt nội dung ở trang chủ và Shorts, và nhiều tiện ích khác. Giao diện có tiếng Việt và tiếng Anh.

## Mở menu

**Nhấn giữ vào logo YouTube** ở thanh trên cùng (khoảng nửa giây). Menu AutoAC hiện ra, chia theo nhóm: Bộ nhớ, Giao diện, Phát lại, Quảng cáo, Shorts, Tải xuống.

Trang **(i)** trong menu cho biết số bản (dòng `bản X.Y.Z`), nhật ký sự cố, dung lượng, chẩn đoán lọc danh sách và nút thoát chế độ an toàn.

## Tính năng

### Tải xuống
- Tải video (MP4, chọn chất lượng trước khi tải), tải âm thanh (M4A), lưu ảnh bìa
- Tải cả video thường lẫn Short; có hàng chờ tải, hiện trong trang (i), và tự tiếp tục khi mở lại app
- Lưu vào Ảnh hoặc mở bảng chia sẻ (Tệp, app khác)
- Hai nút tải trong trình phát, mặc định bật cả hai và bật/tắt độc lập: **Nút tải xuống** (thay nút Tải xuống gốc dưới video) và **Icon tải** (icon nhỏ trong cụm nút Overlay, xếp trong Tuỳ chỉnh Overlay)
- Lưu ảnh trong bài đăng cộng đồng
- Nhấn giữ bình luận để sao chép hoặc dịch sang ngôn ngữ của máy
- Sao chép liên kết, tiêu đề, mô tả; lấy phụ đề (có dịch, có mốc thời gian, lưu `.txt`)

### Phát lại
- Hàng nút ngay trong trình phát, mỗi nút một công tắc: tốc độ (0.25x đến 3x, nhấn giữ để về tốc độ gốc), Picture in Picture, icon tải, **hẹn giờ ngủ** và **phát ngoài**
- Tốc độ và hẹn giờ ngủ dùng chung kiểu bánh xe cuộn: cuộn để chọn, thả tay là áp dụng. Hẹn giờ có hàng Tắt, hàng **Cuối video** (dừng đúng lúc video hiện tại hết, không tự phát video kế, giống hẹn giờ gốc của YouTube) và các mức 5 đến 120 `min` (`min` là phút, ghi tắt để cả tiếng Anh lẫn tiếng Việt đều đọc được); nút đổi màu khi đang hẹn giờ
- Phát ngoài: mở video bằng trình phát hệ thống, Infuse hoặc VLC (Infuse và VLC cần cài sẵn). Trình phát hệ thống và Infuse bắt đầu từ thời điểm đang xem, VLC bắt đầu từ đầu; luồng thường chỉ 360p hoặc 720p
- Tự thử lại khi video báo lỗi "Đã xảy ra lỗi"
- Tắt tự động phát, tắt lặp Short, tắt tự cuộn sang Short kế

### Giao diện
- **Tuỳ chỉnh tab:** đổi thứ tự, ẩn hoặc hiện tab (kể cả Shorts), thêm tab (Nhạc, Trực tiếp, Trò chơi, Tin tức, Thể thao, Học tập, Thời trang, Playlist, Lịch sử…), đổi tên, chọn tab mở đầu; nút tròn kính lỏng ở góc phải trên để khôi phục tab mặc định của YouTube (chạm hai lần); ở tab Shorts AutoAC không còn ép nền dock và chân video thành đen, thanh tab đồng bộ với các tab khác (lúc này nếu còn tối là do chính YouTube, báo dòng `[Dock Short]` trong Chẩn đoán)
- Thanh tab kiểu Liquid Glass, thu nhỏ khi cuộn, đổi màu tab được chọn
- Ẩn khỏi trang chủ: hàng video Short, bài đăng cộng đồng, thẻ gợi ý Mix, mục Chơi game
- Ẩn hiệu ứng logo lúc mở app

### Shorts
Ẩn từng nút ở cột phải (Thích, Bình luận, Chia sẻ, Lưu, Remix), đĩa nhạc, thẻ hiện ra khi chạm dừng, thẻ sản phẩm.

### Quảng cáo
- **SponsorBlock:** tự bỏ qua đoạn tài trợ, tự quảng bá, nhắc like/đăng ký, mở đầu, kết… (chọn loại đoạn), có thông báo nhỏ khi bỏ qua. Dữ liệu từ sponsor.ajay.app
- Chặn popup mời dùng thử hoặc mua Premium; khi bản build tích hợp **NoYTPremium** thì cùng công tắc này chặn thêm khảo sát và mục dùng thử trong cài đặt
- **Chặn Music Premium:** gỡ thẻ mời dùng thử hoặc mua YouTube Music Premium (và thẻ mời nâng cấp tương tự) khỏi bảng tin, không để lại khoảng trống
- Ẩn nhãn "Có quảng cáo trả phí" trên trình phát (mã tự viết)
- **Tuỳ chỉnh Overlay:** một bảng gộp để chọn và sắp xếp các nút (tải xuống, tốc độ, PiP, hẹn giờ, phát ngoài). Mỗi nút nằm ở **hàng trên** (dưới nút bánh răng), **hàng dưới** (cùng hàng, bên trái nút xem toàn màn hình, theo cách của YTVideoOverlay) hoặc **đang tắt**. Bảng hiện ba dải icon ngang (HÀNG TRÊN, HÀNG DƯỚI, ĐANG TẮT, mỗi dải một màu): nhấn giữ một icon rồi kéo thả ngang để đổi thứ tự hoặc sang dải khác. Chạm một icon để chọn, rồi đặt **Vị trí Overlay** bằng nút kính lỏng [Tất cả, Dưới, Trên, Không hiện] (Tất cả = cả hàng trên và hàng dưới). Hai hàng dùng cùng khoảng cách giữa các icon. Nút khôi phục tròn ở góc phải trên đưa mọi thứ về mặc định (chạm hai lần)
- PiP: khi thoát PiP, trình phát YouTube tua tới đúng giây vừa xem trong PiP rồi phát tiếp
- Chặn quảng cáo và phát nền: chỉ có khi bản build tích hợp **YouTube X** (xem phần Cấu trúc)

### Bộ nhớ và hệ thống
- Dọn cache ngay, hoặc tự dọn khi thoát app (không đụng tới video đã tải hay cài đặt)
- Sao lưu và khôi phục cài đặt ra tệp, đặt lại về mặc định
- **Dung lượng ứng dụng:** mục riêng trong nhóm Bộ nhớ, mở bảng cho biết app và từng thư mục (cache, video đã tải, dữ liệu…) đang chiếm bao nhiêu, có nút Tính lại
- **Chế độ an toàn:** nếu app thoát bất ngờ, lần mở sau AutoAC tự tắt dần các nhóm hook rủi ro. Thoát chế độ này ở trang (i)

## Cài đặt

AutoAC là tweak chạy trong app YouTube. Bản build đóng gói rootless (`arm64`, `arm64e`, iOS 14 trở lên). Cách dùng thông thường là tiêm tệp `.deb`/`.dylib` vào IPA YouTube rồi sideload, hoặc cài qua trình quản lý gói nếu máy có jailbreak.

Gói ngôn ngữ `AutoAC.bundle` được cài vào `/Library/Application Support/AutoAC.bundle` (theo tiền tố rootless). Thiếu thư mục này tweak vẫn chạy, dùng bảng dịch có sẵn trong `Tweak.x`.

## Build

Cần [Theos](https://theos.dev) và iOS SDK.

```sh
make clean package FINALPACKAGE=1
```

Repo có thể build bằng GitHub Actions: CI chạy `build_engine.py`, script này ghi `BuildInfo.h` (số bản, danh sách mã nguồn tích hợp) và đồng bộ các tệp `Upstream_*` trước khi gọi Theos.

## Cấu trúc

| Tệp | Vai trò |
|---|---|
| `Tweak.x` | Toàn bộ mã của AutoAC (Objective‑C, ARC; hook qua Logos và runtime) |
| `Sideloading.x` | Sửa đăng nhập cho YouTube sideload (Keychain, App Group, giả bundle ID). Mã lấy từ YTLite; chỉ chạy khi app không có biên lai App Store, nên không cần tiêm thêm dylib sửa Keychain |
| `Makefile` | Cấu hình Theos, sao chép `AutoAC.bundle` vào gói; nhớ liệt kê `Sideloading.x` trong `AutoAC_FILES` |
| `AutoAC.bundle/` | Chuỗi giao diện: `en.lproj`, `vi.lproj` (`Localizable.strings`) |
| `Upstream_*.x`, `Upstream_*.xm` | Tự sinh/đồng bộ mỗi lần build (ví dụ YouTube X, NoYTPremium), không sửa tay |
| `upstream.json` | Danh sách tweak mã nguồn mở của riêng dự án này (đặt trong thư mục dự án, CI đọc trước file chung `.github/scripts/upstream.json`). Chỉ nhúng repo có giấy phép MIT/Apache/BSD |
| `BuildInfo.h` | Tự sinh bởi CI; không có thì tweak vẫn build, chỉ không hiện số bản |
| `README.md` | Tài liệu tiếng Việt và tiếng Anh trong một tệp: chạm tiêu đề ngôn ngữ để mở hoặc thu gọn |

Phần lớn hook gắn qua runtime và **tự bỏ qua** nếu YouTube đổi tên lớp hoặc phương thức, nên một bản YouTube mới có thể làm một vài tính năng ngừng tác dụng mà không gây lỗi build.

## Lưu ý

- Mỗi lần YouTube cập nhật, giao diện nội bộ có thể đổi. Hãy xem số bản ở trang (i) khi báo lỗi.
- Tab Đăng ký đôi khi có khoảng trắng lớn khi cuộn. Nguyên nhân chưa xác định; trang (i) có mục "[Lọc danh sách]" ghi tab hiện tại để đối chiếu.
- Tính năng ẩn nội dung ở trang chủ chỉ lọc ở tab Trang chủ.
- Còn trong mã nhưng chưa có lối vào ở menu: tốc độ khi mở video, tua khi chạm đúp.
- Hàng nút trình phát có tối đa năm nút (hẹn giờ, phát ngoài, PiP, icon tải, tốc độ); trên màn hình hẹp chúng có thể chạm vào icon gốc của YouTube.

## Ghi công

AutoAC tham khảo và tích hợp ý tưởng, mã từ: **YouTube X**, **NoYTPremium**, **ytkace**, **YTLite** (kể cả `Sideloading.x`, phần giả danh YouTube dựa trên **IAmYouTube** của PoomSmart), và dữ liệu cộng đồng **SponsorBlock** ([sponsor.ajay.app](https://sponsor.ajay.app)). Cảm ơn các tác giả của những dự án này.

</details>

<details>
<summary><b>🇬🇧 English</b></summary>

A customization tweak for **YouTube** on iOS (sideloaded YouTube builds), written with Theos/Logos. Everything lives in one menu: download videos and audio, skip sponsored segments, customize the tab bar (including the Liquid Glass style), hide clutter on the home feed and in Shorts, and more. The interface is available in Vietnamese and English.

## Opening the menu

**Long-press the YouTube logo** in the top bar (about half a second). The AutoAC menu opens, grouped as: Storage, Appearance, Playback, Ads, Shorts, Downloads.

The **(i)** page in the menu shows the build number (the `bản X.Y.Z` line), the crash log, storage usage, list-filter diagnostics, and the button to leave safe mode.

## Features

### Downloads
- Download video (MP4, with a quality choice before downloading), download audio (M4A), save the cover image
- Works for regular videos and Shorts; a download queue is shown on the (i) page and resumes when the app is reopened
- Save to Photos or open the share sheet (Files, other apps)
- Two download buttons in the player, both on by default and switched on or off independently: the **Download button** (replaces YouTube's own Download button under the video) and the **Download icon** (a small icon among the overlay buttons, arranged in Customize overlay)
- Save images from community posts
- Long-press a comment to copy it or translate it into the device language
- Copy the link, title, or description; get subtitles (translated, with timestamps, saved as `.txt`)

### Playback
- A row of buttons right in the player, each with its own switch: speed (0.25x to 3x, long-press to return to normal speed), Picture in Picture, download icon, **sleep timer**, and **external player**
- Speed and the sleep timer share the same scroll wheel: scroll to choose, release to apply. The timer offers an Off row, an **End of video** row (stops exactly when the current video ends and does not autoplay the next one, like YouTube's own timer) and 5 to 120 `min` (abbreviated so that both English and Vietnamese readers understand it); the button changes color while a timer is running
- External player: open the video in the system player, Infuse, or VLC (Infuse and VLC must be installed). The system player and Infuse start from the current time; VLC starts from the beginning. The stream is usually only 360p or 720p
- Automatically retry when a video reports "An error occurred"
- Disable autoplay, disable Short looping, disable auto-scroll to the next Short

### Appearance
- **Customize tabs:** reorder, hide or show tabs (including Shorts), add tabs (Music, Live, Gaming, News, Sports, Learning, Fashion, Playlists, History…), rename them, choose the launch tab; the round glass button at the top right restores YouTube's default tabs (tap twice); on the Shorts tab AutoAC no longer forces the dock and the video footer to black, so the tab bar matches the other tabs (if it is still dark, that comes from YouTube itself; report the `[Dock Short]` line from Diagnostics)
- Liquid Glass tab bar, minimize on scroll, selected-tab color
- Hide from the home feed: Short shelves, community posts, Mix suggestion cards, the Games section
- Hide the logo animation at launch

### Shorts
Hide individual buttons in the right column (Like, Comment, Share, Save, Remix), the music disc, the card shown when you tap to pause, and product tags.

### Ads
- **SponsorBlock:** automatically skip sponsors, self-promotion, like/subscribe reminders, intros, outros, and more (choose the segment types), with a small notice when a segment is skipped. Data from sponsor.ajay.app
- Block popups that offer a Premium trial or purchase; when the build includes **NoYTPremium**, the same switch also blocks surveys and the trial entry in settings
- **Block Music Premium:** removes cards that invite you to try or buy YouTube Music Premium (and similar upgrade cards) from the feed, leaving no gap
- Hide the "Includes paid promotion" label on the player (own code)
- **Customize overlay:** one panel to choose and arrange the buttons (download, speed, PiP, sleep timer, external player). Each button lives in the **top row** (under the gear button), the **bottom row** (same row, to the left of the fullscreen button, the way YTVideoOverlay does it) or is **off**. The panel shows three horizontal icon strips (TOP ROW, BOTTOM ROW, OFF, each with its own color): long-press an icon and drag it sideways to reorder or move it to another strip. Tap an icon to select it, then set the **Overlay position** with the liquid-glass pill [All, Bottom, Top, Hidden] (All = both top and bottom rows). Both rows use the same icon spacing. The round restore button at the top right resets everything to default (tap twice)
- PiP: when you leave PiP, the YouTube player seeks to the second you reached in PiP and keeps playing
- Ad blocking and background play: only available when the build includes **YouTube X** (see Structure)

### Storage and system
- Clean the cache now, or automatically when leaving the app (downloaded videos and settings are never touched)
- Back up and restore settings to a file, and reset to defaults
- **App storage:** a dedicated row in the Storage group that opens a panel showing how much space the app and each folder (cache, downloaded videos, data…) take up, with a Recalculate button
- **Safe mode:** if the app exits unexpectedly, AutoAC progressively turns off risky hook groups on the next launch. Leave safe mode from the (i) page

## Installation

AutoAC is a tweak that runs inside the YouTube app. Builds are packaged rootless (`arm64`, `arm64e`, iOS 14 or later). The usual way is to inject the `.deb`/`.dylib` into a YouTube IPA and sideload it, or to install it through a package manager on a jailbroken device.

The `AutoAC.bundle` language pack is installed to `/Library/Application Support/AutoAC.bundle` (with the rootless prefix). Without this folder the tweak still works, using the translation table built into `Tweak.x`.

## Building

Requires [Theos](https://theos.dev) and an iOS SDK.

```sh
make clean package FINALPACKAGE=1
```

The repo can be built with GitHub Actions: CI runs `build_engine.py`, which writes `BuildInfo.h` (the build number and the list of integrated sources) and syncs the `Upstream_*` files before calling Theos.

## Structure

| File | Role |
|---|---|
| `Tweak.x` | All of AutoAC's code (Objective‑C, ARC; hooks through Logos and the runtime) |
| `Sideloading.x` | Login fixes for sideloaded YouTube (Keychain, App Group, bundle ID spoofing). Code taken from YTLite; it only runs when the app has no App Store receipt, so no separate Keychain-fix dylib needs to be injected |
| `Makefile` | Theos configuration, copies `AutoAC.bundle` into the package; remember to list `Sideloading.x` in `AutoAC_FILES` |
| `AutoAC.bundle/` | Interface strings: `en.lproj`, `vi.lproj` (`Localizable.strings`) |
| `Upstream_*.x`, `Upstream_*.xm` | Generated/synced on every build (for example YouTube X, NoYTPremium); do not edit by hand |
| `upstream.json` | This project's own list of open-source tweaks (lives in the project folder; CI reads it before the shared `.github/scripts/upstream.json`). Only repos with an MIT/Apache/BSD licence are embedded |
| `BuildInfo.h` | Generated by CI; without it the tweak still builds, it just doesn't show the build number |
| `README.md` | Documentation in Vietnamese and English in a single file: tap a language heading to expand or collapse it |

Most hooks are attached through the runtime and are **skipped automatically** if YouTube renames a class or method, so a new YouTube version may disable a few features without causing a build error.

## Notes

- Internal YouTube UI can change with every update. Include the build number from the (i) page when reporting a problem.
- The Subscriptions tab sometimes shows a large blank gap while scrolling. The cause is not yet identified; the (i) page has a "[Lọc danh sách]" (list filter) section that shows the current tab for comparison.
- Hiding content on the home feed only filters the Home tab.
- Present in the code but with no entry in the menu: speed on video open, double-tap skip.
- The player button row holds at most five buttons (sleep timer, external player, PiP, download icon, speed); on narrow screens they may overlap YouTube's own icons.

## Credits

AutoAC draws on ideas and code from: **YouTube X**, **NoYTPremium**, **ytkace**, **YTLite** (including `Sideloading.x`, whose app-spoofing part is based on PoomSmart's **IAmYouTube**), and the community data of **SponsorBlock** ([sponsor.ajay.app](https://sponsor.ajay.app)). Thanks to the authors of these projects.

</details>
