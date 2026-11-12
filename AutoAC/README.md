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
- Tốc độ và hẹn giờ ngủ dùng chung kiểu bánh xe cuộn: cuộn để chọn, thả tay là áp dụng. Hẹn giờ có hàng Tắt, các mức 5 đến 120 `min` (`min` là phút, ghi tắt để cả tiếng Anh lẫn tiếng Việt đều đọc được) và hàng **End** ở cuối cùng (dừng đúng lúc video hiện tại hết, không tự phát video kế, giống hẹn giờ gốc của YouTube); nút đổi màu khi đang hẹn giờ
- Phát ngoài: mở video bằng trình phát hệ thống, Infuse hoặc VLC (Infuse và VLC cần cài sẵn). Trình phát hệ thống và Infuse bắt đầu từ thời điểm đang xem, VLC bắt đầu từ đầu; luồng thường chỉ 360p hoặc 720p
- Tự thử lại khi video báo lỗi "Đã xảy ra lỗi"
- Tắt tự động phát, **Bật lặp Short** (bật = Short lặp lại; tắt = không lặp, mặc định), **Tắt tự cuộn Short**, **Bật sửa lỗi phát** (tự thử lại khi video báo lỗi)

### Giao diện
- **Tuỳ chỉnh tab:** phía trên là các thiết lập: **Bật thu gọn** (khi cuộn, thanh tab co thành vòng tròn chứa icon tab đang chọn, chạm vòng tròn để mở lại; cần mở lại app. Ở mọi tab ngoài Trang chủ, kể cả Shorts, cuộn lên (sang video kế) thì thanh tab thu gọn hoặc ẩn, cuộn xuống thì hiện lại, giống Trang chủ. Khi tắt thu gọn, thanh tab ẩn bằng hàm ẩn/hiện thanh tab của chính YouTube), **Bật kính lỏng** (một công tắc cho thanh trên, bảng chọn, trình phát và nút Overlay; cần iOS 26), **Nhãn tab**, **Kiểu màu tab**, **Kiểu thanh tab** (Mặc định hoặc Kính lỏng có sẵn của YouTube; ở kiểu Kính lỏng: chế độ tối thanh tab có nền kính tối, icon và nhãn trắng; chế độ sáng nền kính trong suốt, icon và nhãn đen; ở tab Shorts thanh cũng được ép theo giao diện của app nên không còn đen khi app sáng) và **Tab khi mở app**. Bên dưới là bảng kéo thả cùng kiểu với Tuỳ chỉnh Overlay, tông trung tính: hai dải icon ngang **TAB ĐANG HIỆN** và **TAB ĐANG ẨN** (ít nhất 6 icon mỗi hàng, nhiều tab thì tự xuống hàng); nhấn giữ một tab rồi kéo để đổi thứ tự hoặc chuyển dải. Chạm một tab để chọn, thẻ chi tiết có một hàng hai nút kính cùng cỡ: Hiện/Ẩn và Đổi tên tab…. Thêm tab (Nhạc, Trực tiếp, Trò chơi, Tin tức, Thể thao, Học tập, Thời trang, Playlist, Lịch sử…) bằng cách kéo vào dải đang hiện. Ẩn/hiện, thứ tự, đổi tên, kiểu thanh tab và tab khi mở app áp dụng khi mở lại app (app nhắc "Mở lại app để áp dụng"); nút tròn kính lỏng ở góc phải trên để khôi phục tab mặc định của YouTube (chạm hai lần)
- Thanh tab kiểu Liquid Glass, thu nhỏ khi cuộn, đổi màu tab được chọn
- Ẩn khỏi trang chủ: hàng video Short (làm theo YTLite: gỡ phần tử và ô Short khỏi danh sách), bài đăng cộng đồng, thẻ gợi ý Mix, mục Chơi game
- Ẩn hiệu ứng logo lúc mở app

### Shorts
Ẩn từng nút ở cột phải (Thích, Bình luận, Chia sẻ, Lưu, Remix), đĩa nhạc, thẻ hiện ra khi chạm dừng, thẻ sản phẩm.

**Làm sạch short:** chụm hai ngón lại để làm sạch màn hình (ẩn nút, tiêu đề, thanh tab), kéo giãn hai ngón ra để hiện lại. Không còn chức năng thu phóng video.

**Thanh tab ở tab Shorts khi app sáng:** nền trắng, icon và nhãn đen cho mọi tab, kể cả Trang chủ, Kênh đăng ký, Xem sau, Bài đăng (YouTube vốn đặt thanh tối riêng ở Short).

### Quảng cáo
- **SponsorBlock:** tự bỏ qua đoạn tài trợ, tự quảng bá, nhắc like/đăng ký, mở đầu, kết… (chọn loại đoạn), có thông báo nhỏ khi bỏ qua. Dữ liệu từ sponsor.ajay.app
- Chặn popup mời dùng thử hoặc mua Premium **và** thẻ mời dùng thử/mua YouTube Music Premium trong bảng tin (gộp vào một công tắc **No premium**, không để lại khoảng trống); khi bản build tích hợp **NoYTPremium** thì cùng công tắc này chặn thêm khảo sát và mục dùng thử trong cài đặt
- Ẩn nhãn "Có quảng cáo trả phí" trên trình phát (mã tự viết)
- **Tuỳ chỉnh Overlay:** một bảng gộp để chọn và sắp xếp các nút (tải xuống, tốc độ, PiP, hẹn giờ, phát ngoài, **chất lượng video** và **lặp video**; hai nút mới mặc định nằm ở dải ĐANG TẮT, kéo lên để dùng). Mỗi nút nằm ở **hàng trên** (dưới nút bánh răng), **hàng dưới** (cùng hàng, bên trái nút xem toàn màn hình, theo cách của YTVideoOverlay) hoặc **đang tắt**. Bảng hiện ba dải icon ngang (HÀNG TRÊN, HÀNG DƯỚI, ĐANG TẮT, tông trung tính, ít nhất 6 icon mỗi dải): nhấn giữ một icon rồi kéo thả ngang để đổi thứ tự hoặc sang dải khác. Chạm một icon để chọn, rồi đặt **Vị trí Overlay** bằng nút kính lỏng [Tất cả, Dưới, Trên, Không hiện] (Tất cả = cả hàng trên và hàng dưới). Nút **Chất lượng** mở bánh xe chọn độ phân giải của video đang xem, xếp từ thấp đến cao: 144p Lowest, 240p Low, 360p SDL, 480p SDH, 720p HDL, 1080p HDH, 1440p 2K/QHD, 2160p 4K/UHD, 4320p 8K/FUHD (áp dụng cho video đó, video sau về tự động). Nút **Lặp video** bật/tắt lặp lại video đang xem (chuyển sang video khác thì tự tắt). Các icon Tải xuống, Phát ngoài và Lặp video dùng khung tròn, cùng cỡ với icon Hẹn giờ; vòng kính quanh icon là hình tròn thật (bo tròn chuẩn, kính trong), nhỏ hơn nút 4 điểm để viền kính quanh icon mỏng (icon giữ nguyên cỡ), giống nút toàn màn hình và thời gian video. Công tắc **Kính lỏng** cũng thêm vòng kính tròn cho các nút gốc của YouTube ở hàng trên trình phát (chiếu màn hình, phụ đề CC, cài đặt, thu gọn, và nút tự động phát nếu có). Nút khôi phục tròn ở góc phải trên đưa mọi thứ về mặc định (chạm hai lần)
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
- Speed and the sleep timer share the same scroll wheel: scroll to choose, release to apply. The timer offers an Off row, 5 to 120 `min` (abbreviated so that both English and Vietnamese readers understand it) and an **End** row last (stops exactly when the current video ends and does not autoplay the next one, like YouTube's own timer); the button changes color while a timer is running
- External player: open the video in the system player, Infuse, or VLC (Infuse and VLC must be installed). The system player and Infuse start from the current time; VLC starts from the beginning. The stream is usually only 360p or 720p
- Automatically retry when a video reports "An error occurred"
- Disable autoplay, **Enable Short loop** (on = Shorts loop; off = no loop, default), **Disable Short auto-scroll**, **Fix playback errors** (auto-retry when a video reports an error)

### Appearance
- **Customize tabs:** the settings at the top are: **Enable minimize** (on scroll the tab bar shrinks to a circle holding the selected tab's icon; tap the circle to expand; needs a relaunch. On every tab except Home, Shorts included, scrolling up (to the next video) minimizes or hides the tab bar and scrolling down brings it back, like Home. With minimize off, the bar is hidden through YouTube's own hide/show tab bar calls), **Enable liquid glass** (one switch for the top bar, sheets, player and Overlay buttons; iOS 26 required), **Tab labels**, **Tab color style**, **Tab bar style** (Default or YouTube's built-in Liquid Glass; in the Liquid Glass style: in dark mode the tab bar has a dark glass background with white icons and labels; in light mode the glass is clear with black icons and labels; on the Shorts tab the bar is also forced to follow the app's appearance, so it no longer stays black when the app is light) and **Tab at launch**. Below it is a drag-and-drop board in the same style as Customize Overlay, in neutral tones: two horizontal icon strips, **VISIBLE TABS** and **HIDDEN TABS** (at least 6 icons per row, wrapping to more rows when there are many tabs); press and hold a tab and drag it to reorder or move it between strips. Tap a tab to select it; the detail card has one row with two equal-size glass pills: Show/Hide and Rename…. Add tabs (Music, Live, Gaming, News, Sports, Learning, Fashion, Playlists, History…) by dragging them into the visible strip. Show/hide, order, renaming, the tab bar style and the launch tab apply after a relaunch (the app shows "Restart the app to apply"); the round glass button at the top right restores YouTube's default tabs (tap twice)
- Liquid Glass tab bar, minimize on scroll, selected-tab color
- Hide from the home feed: Short shelves (done the YTLite way: Short elements and cells are removed from the list), community posts, Mix suggestion cards, the Games section
- Hide the logo animation at launch

### Shorts
Hide individual buttons in the right column (Like, Comment, Share, Save, Remix), the music disc, the card shown when you tap to pause, and product tags.

**Clean Short:** pinch two fingers together to clean the screen (hides buttons, titles and the tab bar), spread them apart to bring it back. Video zoom has been removed.

**Tab bar on the Shorts tab when the app is light:** white background, black icons and labels on every tab, including Home, Subscriptions, Watch later and Posts (YouTube normally makes the bar dark on Shorts).

### Ads
- **SponsorBlock:** automatically skip sponsors, self-promotion, like/subscribe reminders, intros, outros, and more (choose the segment types), with a small notice when a segment is skipped. Data from sponsor.ajay.app
- Block popups that offer a Premium trial or purchase **and** the cards that offer YouTube Music Premium in the feed (merged into the single **No premium** switch, leaving no gap); when the build includes **NoYTPremium**, the same switch also blocks surveys and the trial entry in settings
- Hide the "Includes paid promotion" label on the player (own code)
- **Customize overlay:** one panel to choose and arrange the buttons (download, speed, PiP, sleep timer, external player, **video quality** and **loop video**; the two new buttons start in the OFF strip, drag them up to use them). Each button lives in the **top row** (under the gear button), the **bottom row** (same row, to the left of the fullscreen button, the way YTVideoOverlay does it) or is **off**. The panel shows three horizontal icon strips (TOP ROW, BOTTOM ROW, OFF, neutral tones, at least 6 icons per strip): long-press an icon and drag it sideways to reorder or move it to another strip. Tap an icon to select it, then set the **Overlay position** with the liquid-glass pill [All, Bottom, Top, Hidden] (All = both top and bottom rows). The **Quality** button opens a wheel with the resolutions available for the current video, ordered low to high: 144p Lowest, 240p Low, 360p SDL, 480p SDH, 720p HDL, 1080p HDH, 1440p 2K/QHD, 2160p 4K/UHD, 4320p 8K/FUHD (applies to that video; the next video goes back to automatic). The **Loop video** button turns repeat on or off for the current video (it turns itself off when another video starts). The Download, External player and Loop icons use a round frame at the same size as the Sleep timer icon; the glass around each icon is a true circle (standard round corners, clear glass), 4 points smaller than the button so the glass rim around the icon is thin (icon size unchanged), like the fullscreen button and the video time. The **Liquid Glass** switch also adds a round glass ring behind YouTube's own buttons in the top row of the player (cast, captions CC, settings, minimize, and the autoplay toggle if present). The round restore button at the top right resets everything to default (tap twice)
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

---
**2.1.77 (VI):** Số phiên bản AutoAC và phiên bản YouTube đang dùng hiện cạnh nhau ở đầu menu (v… - (YouTube …)) và trong trang (i). Mọi ngôn ngữ (Anh và ngôn ngữ thêm sau này) đều xếp chức năng theo thứ tự tiếng Việt, không xếp a-z theo bản dịch. Sửa lớp mờ hình vuông dưới vòng kính tròn của nút Overlay và nút gốc.

**2.1.77 (EN):** The AutoAC version and the YouTube version in use are shown side by side at the top of the menu (v… - (YouTube …)) and on the (i) page. Every language (English and any added later) orders features in Vietnamese order, not alphabetically by translation. Fixed the square dim layer under the round glass of the Overlay and native buttons.

---
**2.1.78 (VI):** Sửa lỗi thoát app khi chụm hai ngón trong Short (lỗi đệ quy vô hạn trong hàm làm sạch màn hình). Đổi tên: Làm sạch short, Bật sửa lỗi phát, Tắt tự cuộn Short. "Tắt lặp Short" đổi thành **Bật lặp Short** với logic đảo ngược (bật = Short lặp lại; mặc định tắt = không lặp như trước). Thanh dock ẩn bằng hàm của YouTube trên màn hình gốc trước, như YTLite.
**2.1.78 (EN):** Fixed the crash when pinching in Shorts (infinite recursion in the clean-screen code). Renamed: Clean Short, Fix playback errors, Disable Short auto-scroll. "Disable Short loop" became **Enable Short loop** with inverted logic (on = Shorts loop; default off = no loop, as before). The tab bar is hidden through YouTube's own call on the root controller first, like YTLite.

---
**2.1.80 (VI):** Sửa khung "Chẩn đoán hệ thống" bị chèn lên nút gạt (công tắc thu nhỏ nay được bọc trong khung đúng cỡ nhìn thấy). Bảng báo cáo hoạt động thấp hơn 50% (230 → 115 điểm). Thêm bản dịch tiếng Anh cho "Báo cáo hoạt động" và "Sao chép chẩn đoán".
**2.1.80 (EN):** Fixed the "System diagnostics" box overlapping the toggle (the scaled switch is now wrapped in a view of its visible size). The activity-report box is 50% shorter (230 → 115 pt). Added English strings for "Báo cáo hoạt động" and "Sao chép chẩn đoán".

---
**2.1.81 (VI):** Trang (i): mục **CHỨC NĂNG CHÍNH** có nút thu gọn / mở rộng (mặc định thu gọn); sửa lỗi nội dung bị nén lại khi bật Chẩn đoán (khung cuộn nay không còn ép nhãn). Dock ở tab **Short**: chế độ tối = nền tối trong suốt (gỡ nền đen đặc, lớp tối nhẹ 0,30), chế độ sáng = nền trắng trong suốt (0,34), icon đen.
**2.1.81 (EN):** (i) page: the **MAIN FEATURES** section can be collapsed / expanded (collapsed by default); fixed content being squashed when Diagnostics is on (the scroll view no longer compresses labels). Tab bar on the **Shorts** tab: dark mode = transparent dark background (solid black removed, light 0.30 tint), light mode = transparent white background (0.34), black icons.

---
**2.1.82 (VI):** Sửa nút **Tải xuống** (thay nút Tải xuống gốc) không chạy ngay từ đầu dù đang bật, phải tắt/bật lại: nút phủ nay được ghim bốn cạnh vào nút gốc bằng ràng buộc (trước đây đặt theo khung lúc gắn, khi đó nút gốc có thể chưa có kích thước), nhận cả nhãn đặt sau, nhận nút trong trang xem video khi YouTube đổi tên lớp, quét lại định kỳ khi trình phát hiện và ngay khi bật công tắc. Nút này và **Nút icon tải** (nút nổi trong Overlay) là hai công tắc độc lập: bật/tắt/ẩn nút nổi không ảnh hưởng nút Tải xuống và ngược lại; cả hai có thể chạy cùng lúc.
**2.1.82 (EN):** Fixed the **Download button** (replaces YouTube's native Download button) not working from the start even though it was on, needing an off/on toggle: the overlay is now pinned to the native button with Auto Layout constraints (before, it was framed at attach time when the native button could still be 0×0), also catches labels set later, finds the button on the watch page when YouTube renames classes, and rescans periodically while the player is shown and immediately when the switch is turned on. This button and the **Download icon button** (the floating one in the Overlay) are independent switches: toggling or hiding the floating button does not affect the Download button and vice versa; both can run at the same time.

---
**2.1.83 (VI):** Trang (i): bỏ mũi tên ^ cạnh tiêu đề CHỨC NĂNG CHÍNH, chỉ còn chữ Thu gọn / Mở rộng ở mép phải. Thanh tab: đổi giao diện sáng ↔ tối khi app đang chạy nay làm mới ngay nền kính và màu icon / nhãn (trước đây thanh bị ép giao diện nên trait không đổi, icon giữ màu cũ tới khi bố cục lại). Đã đối chiếu thanh tab Liquid Glass của YTKACE: màu icon gốc của nó theo trait, tab phụ theo độ sáng nền hoặc màu chữ theo trait; AutoAC cho kết quả màu tương đương ở mọi trạng thái đã kiểm tra trên giấy.
**2.1.83 (EN):** (i) page: removed the ^ arrow next to the MAIN FEATURES title; only the Collapse / Expand text on the right edge remains. Tab bar: switching light ↔ dark while the app is running now immediately refreshes the glass fill and icon / label colours (before, the bar's forced interface style meant no trait change fired and icons kept the old colour until the next layout). Compared with YTKACE's Liquid Glass tab bar: its native icons follow traits and its extra tabs follow background luminance or the trait-resolved label colour; AutoAC gives equivalent colours in every state checked on paper.

---
**2.1.85 (VI):** Rà lại các chức năng thêm ở 2.1.84 (Bỏ xác minh tuổi, Bỏ giới hạn phát, Phụ đề theo ngôn ngữ thiết bị, Tắt PiP Short, Danh sách chờ cục bộ, Logo Premium) và đối chiếu với YTKACE. **Phụ đề ngôn ngữ**: cách cũ đoán tên hàm nên nhiều khả năng không chọn được phụ đề; nay theo YTKACE: bắt `MLInnerTubeCaptionController`, khi danh sách phụ đề được đặt thì chọn bản đúng ngôn ngữ thiết bị (ưu tiên bản người làm, rồi bản tự tạo) qua `setSelectedCaptionTrack:selectionReason:`. **Logo Premium**: thêm đường thứ hai như YTKACE (thay ảnh `youtube_logo*` bằng `youtube_premium_logo*` lúc nạp ảnh) bên cạnh đường renderer cũ. **Bỏ xác minh tuổi**: thêm cờ `isAgeRestricted`, `requiresAgeVerification`, `shouldShowAgeGate`, `ageGateRequired`, `isAgeVerified`, `isAgeAllowed`. **Bỏ giới hạn phát**: thêm `isMiniplayerRendererPlaybackModePauseOnly` → NO, `isPlayableInMiniPlayer` → YES và hỗ trợ `playbackMode` kiểu NSInteger. Các hook tự bỏ qua nếu YouTube bản đang dùng không có hàm tương ứng.
**2.1.85 (EN):** Reviewed the 2.1.84 features (Skip age verification, Remove play limit, Device-language subtitles, Disable Shorts PiP, Local queue, Premium logo) against YTKACE. **Device-language subtitles**: the old code guessed method names and most likely never selected a track; it now follows YTKACE: it tracks `MLInnerTubeCaptionController`, and when the track list is set it selects the device-language track (human-made first, then auto-generated) via `setSelectedCaptionTrack:selectionReason:`. **Premium logo**: added a second path like YTKACE (swap `youtube_logo*` for `youtube_premium_logo*` at image load) next to the renderer path. **Age verification**: added the `isAgeRestricted`, `requiresAgeVerification`, `shouldShowAgeGate`, `ageGateRequired`, `isAgeVerified`, `isAgeAllowed` flags. **Play limit**: added `isMiniplayerRendererPlaybackModePauseOnly` → NO, `isPlayableInMiniPlayer` → YES and NSInteger-typed `playbackMode`. Hooks skip themselves when the installed YouTube lacks the method.

---
**2.1.86 (VI):** **Tự ẩn dock ở mọi trang**: khi lướt lên, dock tự ẩn ở mọi trang (cả Trang chủ và các trang không có tab trên dock như Kênh đăng ký trong hàng tab của Trang chủ), không còn phụ thuộc mã tab đang chọn. **Short**: gỡ dải đen dưới thanh tab ở chân video (mọi view đặc màu tối đè lên vùng thanh tab hoặc dính đáy màn hình, ở bất kỳ nhánh nào của cửa sổ; trả lại màu gốc khi rời Short), áp dụng cả kiểu thanh tab Mặc định.
**2.1.86 (EN):** **Auto-hide dock everywhere**: the dock now hides when scrolling up on every page (Home too, and pages that have no tab on the dock, such as Subscriptions inside Home's tab row), no longer depending on the selected tab id. **Shorts**: removes the black strip under the tab bar at the foot of the video (any solid dark view covering the tab-bar area or sticking to the screen bottom, in any branch of the window; original colours restored when leaving Shorts), also with the Default tab-bar style.

---
**2.1.87 (VI):** Trang (i) gọn hơn: bỏ dòng trống thừa ở cuối mỗi khối chữ (mỗi đoạn kết thúc bằng xuống dòng nên để lại một dòng trống), giảm khoảng cách giữa tiêu đề và nội dung, giữa các mục (TÁC GIẢ, MÃ NGUỒN THAM KHẢO, CHỨC NĂNG CHÍNH, CHẾ ĐỘ AN TOÀN, CHẨN ĐOÁN HỆ THỐNG), lề trên / dưới trang và hàng công tắc chẩn đoán.
**2.1.87 (EN):** Tidier (i) page: removed the stray blank line at the end of each text block (each paragraph ended with a newline, leaving an empty line), and reduced the spacing between titles and content, between sections (AUTHOR, REFERENCE SOURCES, MAIN FEATURES, SAFE MODE, SYSTEM DIAGNOSTICS), the page's top / bottom margins and the diagnostics switch row.

---
**2.1.88 (VI):** **Tải xuống trong menu …**: mục **Tải xuống** gốc trong menu … ở góc dưới bên phải video nay mở bảng tải của AutoAC cho đúng video đó (theo công tắc *Nút tải xuống*). Hai lớp: thay hành động của mục trong menu (nhận mã video từ cây renderer), và bắt thẳng lệnh tải của YouTube (`YTOfflineVideoEndpointCommandHandler…`) phòng khi lớp đầu không nhận ra. **Danh sách chờ**: đã xoá *Phát tiếp theo / Phát cuối cùng / Danh sách chờ* khỏi toàn bộ menu tải. Danh sách chờ chỉ chạy qua menu …: mục *Phát tiếp theo / Phát cuối cùng trong danh sách chờ* của YouTube vào danh sách cục bộ không cần Premium (theo YTKACE: với tài khoản không Premium, mục bị YouTube đặt thành quảng cáo nâng cấp nay được chép lệnh thật sang, rồi lệnh được bắt ở các lớp xử lý lệnh và router). Mục *Danh sách chờ* (xem / phát / xoá) vẫn xuất hiện ngay dưới hai mục đó trong menu …; không còn tự chèn 3 mục vào menu khi YouTube không có mục hàng chờ.
**2.1.88 (EN):** **Download in the … menu**: YouTube's own **Download** item in the … menu at the bottom right of a video now opens the AutoAC download sheet for that exact video (governed by the *Download button* switch). Two layers: replacing the menu item's action (video id read from the renderer tree), and catching YouTube's download command itself (`YTOfflineVideoEndpointCommandHandler…`) in case the first layer does not recognise the item. **Queue**: *Play next / Play last / Queue* were removed from every download menu. The queue now works only through the … menu: YouTube's *Play next / Play last in queue* items go into the local list without Premium (like YTKACE: for non-Premium accounts the item YouTube turns into an upgrade ad gets the real command copied in, and the command is caught in the command handlers and the router). The *Queue* item (view / play / clear) still appears right below those two in the … menu; it no longer inserts 3 items when YouTube provides no queue items.

---
**2.1.89 (VI):** **Mặc định theo bản sao lưu của bạn**: bật sẵn Kính lỏng (thanh trên, bảng, trình phát), Danh sách chờ, Bỏ xác minh tuổi / giới hạn phát, Tắt PiP Short, Phụ đề theo ngôn ngữ thiết bị, Logo Premium, Sửa lỗi phát, Ẩn video Short / thẻ sản phẩm / thẻ tạm dừng Short, SponsorBlock với đủ 7 loại (tắt thông báo bỏ qua), nút lặp và chọn chất lượng; Overlay hàng dưới = Tải, Lặp, PiP, hàng trên = Ngoài, Chất lượng, Hẹn giờ, Tốc độ; Tuỳ chỉnh tab: Trang chủ, Short, Kênh đăng ký, Xem sau, Bạn (ẩn Tạo), nhấn tab đang chọn màu #FF3A30. Chỉ áp cho mục bạn chưa chỉnh. **Dock tab Short (chế độ sáng)**: phía sau dock là vùng đen của trình phát Short nên kính trắng trong suốt trông xám tối, và icon / nhãn đen (đúng cho kính trắng) lại khó đọc. Nay có dải trắng đặt ngay sau kính (con của thanh nên ẩn / trượt cùng thanh khi tự ẩn dock) từ mép trên thanh tới đáy màn hình, nên dock Short trông giống dock Trang chủ sáng; icon / nhãn của các ô gốc (Trang chủ, Short…) cũng được ép giao diện sáng nên đen như tab phụ. Chế độ tối giữ nguyên.
**2.1.89 (EN):** **Defaults from your settings backup**: Liquid Glass (top bar, sheets, player), Local queue, Skip age verification / play limit, Disable Shorts PiP, Device-language subtitles, Premium logo, Fix playback errors, Hide Shorts shelf / shop tag / Shorts pause card, SponsorBlock with all 7 categories (skip alerts off), loop and quality buttons are on by default; Overlay bottom row = Download, Loop, PiP, top row = External, Quality, Sleep, Speed; Tab customisation: Home, Shorts, Subscriptions, Watch Later, You (Create hidden), selected-tab tint #FF3A30. Applies only to settings you have not changed. **Shorts dock (light mode)**: behind the dock is the black area of the Shorts player, so the translucent white glass looked dark grey and the black icons / labels (correct for white glass) were hard to read. A white strip now sits right behind the glass (a child of the bar, so it hides / slides with it when the dock auto-hides) from the bar's top edge to the bottom of the screen, so the Shorts dock looks like the light-mode Home dock; the native tabs' icons / labels (Home, Shorts…) are also forced to light appearance so they are black like the extra tabs. Dark mode is unchanged.

---
**2.1.90 (VI):** Dock tab Short (chế độ sáng): **bỏ hẳn dải trắng** sau kính (thêm ở 2.1.89), không để dải màu nào. Thay vào đó gỡ chính nền đen của trình phát Short nằm sau dock: ở chế độ sáng, bước gỡ nền đen ở chân Short nay xử lý cả view đặc màu tối phủ toàn màn hình và cả khung cuộn (trước đây bỏ qua view cao hơn 60% màn hình và mọi khung cuộn), nên sau kính là nền trong suốt. Báo cáo (i) ghi tên lớp và kích thước các view đã gỡ nền. Giữ phần ép icon / nhãn các ô gốc sang giao diện sáng. Chế độ tối giữ nguyên.
**2.1.90 (EN):** Shorts dock (light mode): **removed the white strip** behind the glass (added in 2.1.89), leaving no colour band at all. Instead, the black background of the Shorts player behind the dock is cleared: in light mode the foot-black removal now also handles full-screen solid dark views and scroll views (before, views taller than 60% of the screen and all scroll views were skipped), so what sits behind the glass is transparent. The (i) report logs the class names and sizes of the views whose background was cleared. The forcing of the native tabs' icons / labels to light appearance stays. Dark mode is unchanged.
