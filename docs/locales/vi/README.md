# zisla

[English](../../../README.md) | [简体中文](../../../README.zh-CN.md) | **Tiếng Việt** | [Ngôn ngữ khác](../README.md)

**zisla là không gian làm việc macOS gốc, xuất hiện khi bạn cần rồi nhường chỗ cho công việc.** Đưa con trỏ đến giữa mép trên màn hình để mở một khu vực gọn nhẹ cho tác vụ AI đang chạy, nội dung đa phương tiện, chuyển tệp, tải xuống và tiện ích máy tính. Màn hình không có phần khuyết dùng vùng trạng thái mô phỏng cùng hình dạng.

Bản triển khai hiện tại: **macOS 14+**. Apple Silicon là cấu hình được hỗ trợ; gói phát hành Intel có thể hoạt động nhưng không được bảo đảm tương thích.

[Xem toàn bộ hướng dẫn tính năng — 2:40 · 1080p / 60 fps](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

[![Xem phim giới thiệu zisla](../../../web/public/media/zisla-launch-poster.webp)](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

Nhạc: “Funkorama” của Kevin MacLeod · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Nguồn](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474).

## Vì sao phù hợp với mép trên màn hình

- **Mở khi cần, không chiếm tiêu điểm.** Mở rộng từ mép trên, ghim khi cần và tiếp tục làm việc trong ứng dụng hiện tại.
- **Một nơi cho công việc đang diễn ra.** Xem nội dung đang phát, tác vụ AI, tải xuống, bộ hẹn giờ, thư, trạng thái hệ thống và pin mà không mở bảng điều khiển đầy đủ.
- **Hoạt động AI không cần truy cập hội thoại.** zisla chỉ đọc sự kiện có cấu trúc và siêu dữ liệu hoạt động cục bộ cần để xác định trạng thái tác vụ. Không đọc lời nhắc hay nội dung câu trả lời.
- **Quyền điều khiển ở máy của bạn.** Mô-đun, lịch sử bảng nhớ tạm và phát hiện liên kết có công tắc riêng; quyền được yêu cầu khi dùng tính năng lần đầu.

## Có thể làm gì

### Giúp công việc trên máy tính tiếp tục

| Khả năng | Chức năng |
| --- | --- |
| Đang phát | Hiện ảnh bìa, tiêu đề, tiến độ, lời bài hát và điều khiển phát; khi thiếu siêu dữ liệu, Core Audio có thể xác định ứng dụng thực sự phát âm thanh. |
| Chuyển và chia sẻ | Thả tệp, nội dung đa phương tiện hoặc liên kết vào vùng kích hoạt trên cùng để giữ trong khay, hiện trong Finder hoặc mở menu chia sẻ macOS. Nén tệp và thư mục đã chọn thành ZIP, đổi kích thước hoặc định dạng ảnh bằng Công cụ Ảnh rồi đưa kết quả thành công về khay, hoặc nhập ảnh, video và âm thanh vào thư viện ghi hình mà giữ nguyên dự án và dòng thời gian hiện tại. |
| Bảng nhớ tạm và thông báo | Tùy chọn lưu lịch sử cục bộ, nhận diện liên kết mới trên máy, và hiện nội dung đa phương tiện, AI, tải trình duyệt, bộ hẹn giờ, thư, cập nhật ở trạng thái thu gọn. Thao tác Nhanh tùy chọn hiện thông báo đảo nhỏ sau mỗi lần sao chép với bản xem trước phong phú và hành động phù hợp: mở, hiện trong Finder, tìm, dịch, tính, lưu. Khi trình duyệt tải xong hoặc nhận tệp AirDrop, cùng phím tắt có thể mở thư mục. Ảnh mới trong lịch sử được xếp hàng nhận diện chữ trên thiết bị; tìm chữ để tìm ảnh gốc, hoặc nhấp phải ảnh để nhận diện hay sao chép chữ. |
| Không gian hằng ngày | Thời tiết, lịch, lời nhắc, Mail.app, ghi chú Markdown lưu trong Apple Notes, thông tin màn hình khóa và thú cưng máy tính tùy chọn. |

### Hiển thị công việc AI

zisla theo dõi hoạt động cục bộ của Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, Delta, Orca, TRAE, OpenCode, Harnext, WorkBuddy, WorkBuddy AI và các nguồn khác được hỗ trợ. Ứng dụng hiện tác vụ, trạng thái, xu hướng token, bản đồ nhiệt đóng góp và thông báo bên.

Với công cụ không có nguồn hoạt động cục bộ ổn định, `zislactl` cho phép tập lệnh, CI và hook công cụ báo tiến độ, mức sử dụng, thông báo, trong khi trạng thái giao thức vẫn ở Mac này. Cài đặt cũng phát hiện, cài, cập nhật, gỡ CLI AI phổ biến và quản lý Skills cục bộ. Xem nhà cung cấp và lệnh trong [tham chiếu tích hợp CLI](mac/Docs/cli-reference.md).

### Những công cụ nhỏ hữu ích

| Nhóm | Công cụ có sẵn |
| --- | --- |
| Tải xuống và tài liệu | Tải video, âm thanh qua `yt-dlp`; gộp, tách, xoay, cắt, chuyển đổi, kết xuất, xuất chữ, thêm hình mờ/số trang, mã hóa, mở khóa và sửa siêu dữ liệu PDF tại máy. |
| Tập trung và trình bày | Pomodoro phát một âm báo và thông báo cục bộ khi hết phiên, giữ máy thức, ngăn ngủ khi nhàn rỗi, vệ sinh màn hình/bàn phím, máy nhắc chữ và gương camera. Tên bộ hẹn giờ chỉ áp dụng cho phiên hiện tại và trở về tên mặc định khi phiên kết thúc hoặc bị hủy. |
| Hệ thống và pin | CPU, GPU, bộ nhớ, đĩa, mạng, quạt, pin và dọn bộ đệm/nhật ký có thể xóa an toàn. |
| Nhập giọng nói | Phím tắt toàn hệ thống để ghi và chuyển giọng nói thành chữ, tùy chọn xử lý bản chép cục bộ/từ xa và lịch sử giọng nói tại máy. |

### Lối vào và quy trình hiện tại

Đảo có 12 mô-đun: Trang chủ, Chuyển tệp, Bảng nhớ tạm, Theo dõi AI, Âm bàn phím, Tải xuống, Lịch trình, Thư, Ghi chú, Bộ trộn âm lượng ứng dụng, Tiện ích và Hệ thống. Pin ở trong Hệ thống; hiển thị màn hình khóa riêng. Mở PDF, ảnh và âm thanh từ Cài đặt; mở studio ghi hình từ Cài đặt hoặc thanh menu.

- **Ghi và tạo:** Ghi màn hình, cửa sổ hoặc vùng với âm hệ thống, micrô, camera tùy chọn. Sửa phụ đề, thu phóng, hiệu ứng chân dung/giọng nói trên các rãnh, xem trước rồi xuất video, GIF, Live Photo hoặc âm thanh. Công cụ ảnh có 9 thao tác cục bộ; âm thanh có 27.
- **Trộn và phát:** macOS 14.4+ hỗ trợ âm lượng và tắt tiếng theo ứng dụng. Chọn đầu ra ở vùng đa phương tiện, tùy chọn trình phát trong Cài đặt.
- **Máy tính và họp:** Xem trước cửa sổ Dock/Command+Tab, ghi chú theo trang/cửa sổ/màn hình, đếm ngược họp 10 phút, tham gia và liên kết ghi chú. Lắc con trỏ khi kéo tệp để hiện đích thả trên kệ.
- **Bản tin hằng ngày:** 8 mẫu, xem trước, xuất PNG thủ công hoặc theo lịch, chỉ số được chọn và thư mục riêng.
- **Tài khoản AI:** Xem hạn mức hỗ trợ, giờ đặt lại, cảnh báo sắp hết và giờ lấy mẫu; xuất lịch sử token tại máy sang `.xlsx`.
- **Thao tác Nhanh:** Hành động trong cửa sổ dùng `Command+1` đến `Command+0` theo thứ tự. Phím kích hoạt mặc định bổ sung cho cấu hình mới là `Command+N` để thực hiện hành động đầu tiên. Nâng cấp giữ phím đã lưu và trạng thái xóa phím kích hoạt.

[Trợ giúp người dùng](https://wzz6423.github.io/zisla/help.html?lang=vi#help) có chín hướng dẫn từng bước: bảng nhớ tạm, chụp/ghi, kệ, họp, AI, công cụ đa phương tiện, bản tin hằng ngày, ghi chú máy tính/xem trước cửa sổ và phát/trộn âm. [Hướng dẫn macOS](mac/README.md) liệt kê thư mục lưu và phụ thuộc công cụ.

## Bắt đầu

### Cài ứng dụng

Tải DMG mới nhất từ [GitHub Releases](https://github.com/wzz6423/zisla/releases) hoặc [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), gắn ảnh đĩa rồi kéo `zisla.app` vào `Applications`.

Có thể dùng Homebrew:

```bash
brew install --cask wzz6423/tap/zisla
```

Homebrew tải bản đúng chip, nên Mac Apple Silicon/Intel chỉ lấy kiến trúc của mình. Cask từ tap bên thứ ba `wzz6423/tap`, không phải kho cask của Homebrew; cài nghĩa là tin cậy tap này.

Sau khi mở, đưa con trỏ lên giữa mép trên màn hình hiện tại hoặc chọn **Show Island** ở biểu tượng thanh menu. Gói chưa được Apple công chứng; lần mở đầu, bất kể cách cài, cần **Open Anyway** trong **System Settings > Privacy & Security** hoặc tự bỏ thuộc tính cách ly:

```bash
xattr -d com.apple.quarantine /Applications/zisla.app
```

### Cập nhật ứng dụng

zisla tự cập nhật qua Sparkle bất kể cách cài. Với Homebrew, `brew upgrade` chỉ thay ứng dụng khi bản hiện có thực sự cũ hơn tap vì Homebrew 5.1.6 trở lên đọc phiên bản trong gói ứng dụng. Homebrew do đó không cản Sparkle hoặc bỏ lại bản cũ. Chỉ định cask theo tên lại dựa trên hồ sơ cài Homebrew, có thể đưa bản Sparkle đã cập nhật về phiên bản tap:

```bash
brew upgrade --cask zisla
```

Tap chỉ có bản ổn định; bản xem trước ở Releases nên `brew upgrade` không chuyển sang tiền phát hành. Chỉ định cask khi đang dùng xem trước sẽ thay bằng bản ổn định hiện tại. Sparkle không hạ phiên bản, nên chuyển về Release vẫn giữ bản xem trước đến khi ổn định vượt qua. `brew uninstall --cask zisla` xóa ứng dụng; `brew uninstall --zap --cask zisla` còn xóa dữ liệu cục bộ.

### Chạy từ mã nguồn

Cần Swift 6 / Xcode 16+; chỉ Command Line Tools cũng xây dựng được.

```bash
cd mac
swift run zisla
```

Trình tải cần `yt-dlp`; `ffmpeg` tùy chọn. Office sang PDF cần LibreOffice hoặc OpenOffice. Hướng dẫn xây dựng, kiểm thử và đóng gói trong [hướng dẫn phát triển macOS](mac/README.md).

## Thiết kế không gây cản trở

- Hỗ trợ nhiều màn hình, Spaces và ứng dụng toàn màn hình thông thường mà không kích hoạt hay lấy tiêu điểm.
- Khi ẩn không có cửa sổ trong suốt thường trực bắt chuột hoặc vòng khung hình; theo dõi sự kiện toàn cục và kiểm tra hình học kích hoạt mở.
- Dùng một vật liệu hệ thống; chuyển nền đục khi Reduce Transparency bật.
- Phát hiện phần khuyết thật từ vùng an toàn hệ thống; màn hình ngoài không có dùng lớp phủ cùng đường viền.

Xem [thiết kế kiến trúc và hiệu năng](mac/Docs/architecture.md) về lựa chọn triển khai.

## Quyền riêng tư và quyền truy cập

zisla xin quyền khi tính năng đã bật cần lần đầu. Bạn có thể tắt mô-đun trong Cài đặt và thu hồi quyền trong cài đặt macOS bất cứ lúc nào.

| Phạm vi | Giới hạn |
| --- | --- |
| AI | Chỉ sự kiện có cấu trúc và siêu dữ liệu cục bộ; không đọc lời nhắc/câu trả lời. |
| Bảng nhớ tạm và tệp | Lịch sử, phát hiện liên kết, Thao tác Nhanh có công tắc riêng. Thao tác Nhanh xử lý tải trình duyệt xong/AirDrop độc lập với công tắc tiến độ tải. Nhận diện hoàn toàn trên thiết bị; mở liên kết/hành động chỉ sau nhấp hoặc phím kích hoạt rõ ràng. Chuyển tệp dùng bookmark giới hạn quyền, không sao chép gốc. |
| Ghi chú, thư, giọng nói | AppleScript/JXA với quyền tự động hóa. Chỉ ghi giọng nói khi hoạt động; xử lý bản chép gửi chữ chỉ đến mô hình cục bộ, nhà cung cấp từ xa hoặc hồ sơ CLI đã chọn. |
| Tải trình duyệt và đa phương tiện | Tiến độ tệp công khai macOS, siêu dữ liệu MediaRemote và trạng thái đầu ra Core Audio; không đọc lịch sử trình duyệt. Dạng sóng/trộn xử lý tại máy; ghi chỉ lưu âm thanh của nguồn bật. |
| Mạng | Thời tiết, IP công khai, chọn gương cập nhật, tải xuống, kiểm tra hạn mức AI bật, cài phụ thuộc/CLI liên hệ dịch vụ. Dịch, làm sạch giọng và sửa ghi hình AI dùng nhà cung cấp/CLI được chọn. Apple nhận dạng giọng nói có thể dùng mạng tùy hệ thống/ngôn ngữ. |

### Quyền theo tính năng

Xin quyền lần dùng đầu. Nếu đã từ chối, mở mục tương ứng trong **System Settings > Privacy & Security** và cho `zisla` phép; tên có thể khác theo phiên bản.

| Quyền hoặc cài đặt | Khi cần | Truy cập được cấp |
| --- | --- | --- |
| Điều khiển thiết bị và truy cập dữ liệu (Accessibility ở một số bản) | Tự chèn bản chép vào ô chữ ứng dụng hiện tại | Đọc/tìm ô không phải mật khẩu, gửi qua Accessibility hoặc `Cmd+V`. Không quyền vẫn sao chép vào bảng nhớ tạm. |
| Micrô | Nhập giọng nói hoặc bật micrô studio | Thu micrô được chọn để ghi hoặc theo dõi đã bật. |
| Nhận dạng giọng nói | Đổi ghi âm thành chữ | Chỉ xử lý giọng nói được ghi khi hoạt động; nhập cần cả Micrô và Nhận dạng giọng nói. |
| Truy cập toàn bộ đĩa | Xem thư khi Mail.app không chạy | Đọc chỉ mục `~/Library/Mail` để hiện tài khoản, người gửi, chủ đề, tóm tắt, giờ và trạng thái đọc; đường chỉ mục này cần quyền. |
| Tự động hóa | Đọc, soạn, trả lời, đánh dấu, xóa Mail.app; đọc/ghi Apple Notes | Điều khiển ứng dụng tương ứng; có thể thu hồi Mail/Notes riêng. |
| Lịch; Lời nhắc | Mô-đun lịch trình | Đọc/quản lý sự kiện và lời nhắc với quyền riêng. |
| Dịch vụ vị trí | Thời tiết nơi hiện tại | Xin vị trí một lần, không theo dõi liên tục; nơi thêm thủ công không cần. |
| Camera | Gương hoặc xem trước/ghi camera studio | Dùng camera được chọn khi tính năng hoạt động. |
| Theo dõi đầu vào | Âm, thống kê, vệ sinh bàn phím, phím chỉ bổ trợ/nút chuột bên | Quan sát sự kiện tính năng bật, thống kê tại máy; phím tắt toàn cục thông thường không cần. |
| Bluetooth | Pin phụ kiện trong Hệ thống → Pin | Chỉ thông tin công khai của thiết bị nối/ghép đôi. |
| Ghi màn hình và âm hệ thống (Screen Recording ở bản cũ) | Ảnh, xem cửa sổ, ghi, dạng sóng, trộn ứng dụng | Đọc hình và nguồn âm đã chọn; lưu nguồn bật tại máy; trộn cần macOS 14.4+. |
| Thông báo | Pomodoro | Một âm và thông báo tại máy khi hết giờ. |
| Thư mục người dùng chọn (không cấp thủ công) | Chuyển, nhập/xuất, chọn thư mục tải | Bộ chọn tệp hệ thống cấp thư mục; không cần truy cập toàn bộ đĩa. |

Thu hồi quyền chỉ tắt tính năng tương ứng. Nếu chưa dùng được sau thay đổi, thoát và mở lại zisla rồi thử.

[Hướng dẫn macOS](mac/README.md) mô tả đầy đủ quyền và mạng.

## Tài liệu

| Tài liệu | Mục đích |
| --- | --- |
| [Phát triển macOS](mac/README.md) | Mô-đun, AI, phụ thuộc, xây dựng, kiểm thử, quyền, giới hạn. |
| [Hướng dẫn website — tiếng Anh](../../../web/README.md) | Phát triển tại máy, bản sản xuất, liên kết tải hiện tại. |
| [Hướng dẫn phim — tiếng Anh](../../../promo/README.md) | Remotion, xem trước, kết xuất, bố cục, nhạc, giấy phép. |
| [Kiến trúc và hiệu năng](mac/Docs/architecture.md) | Mép trên, cửa sổ, đồng thời, đa phương tiện, an toàn tải. |
| [Tham chiếu CLI](mac/Docs/cli-reference.md) | Nhà cung cấp, lệnh, trường, mã thoát `zislactl`. |
| [Ký và phát hành](mac/Docs/releasing.md) | Ký, công chứng, DMG, kênh cập nhật, nghiệm thu. |
| [Đóng góp](CONTRIBUTING.md) | Môi trường, nhánh, commit, yêu cầu PR. |

## Đóng góp

Hoan nghênh issue và pull request. Đọc [hướng dẫn đóng góp](CONTRIBUTING.md) trước. Báo bảo mật riêng qua [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), không mở issue công khai.

## Giấy phép

[PolyForm Noncommercial License 1.0.0](../../../LICENSE.md). Cho phép phi thương mại; không cho phép bán phần mềm hoặc mục đích thương mại khác.
