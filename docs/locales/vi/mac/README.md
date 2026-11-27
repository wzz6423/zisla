# zisla cho macOS

[English](../../../../mac/README.md) | [简体中文](../../../../mac/README.zh-CN.md) | **Tiếng Việt** | [Ngôn ngữ khác](../../README.md)

Thư mục này chứa bản macOS của zisla. Đưa con trỏ đến giữa mép trên để mở đảo, đưa ra để ẩn. Ứng dụng dùng AppKit `NSPanel`, SwiftUI và dịch vụ theo sự kiện, không có cửa sổ trong suốt thường trực bắt chuột hoặc vòng khung hình khi ẩn.

Swift target, ID gói, thư mục dữ liệu và `zislactl` đều dùng tên zisla. Nâng cấp tự chuyển dữ liệu và tùy chọn từ phiên bản trước.

Hỗ trợ macOS 14 trở lên. macOS 26 dùng Liquid Glass; 14/15 dùng vật liệu hệ thống gốc.

## Tính năng

### 12 mô-đun đảo

| Mô-đun | Khả năng triển khai |
| --- | --- |
| Trang chủ | Tổng hợp khi cần bộ hẹn giờ Pomodoro hiện tại, tác vụ AI đang chạy đầu tiên, các lượt tải gốc và tiến độ nhiều lượt tải trình duyệt. |
| Âm và thống kê bàn phím | 20 âm có sẵn; bật thống kê tại máy độc lập, xem xu hướng, dòng thời gian ứng dụng và bản đồ nhiệt từng phím. |
| Chuyển tệp | Kéo tệp, nội dung hoặc liên kết lên vùng trên để giữ khay, hiện Finder hoặc chia sẻ. Ảnh lưu có thẻ xanh rộng gấp đôi và nhóm riêng, sao chép ảnh/xuất PNG/xóa. Nén tệp và thư mục thành ZIP, đổi kích thước/định dạng ảnh và trả kết quả thành công về khay, hoặc nhập ảnh, video, âm thanh vào thư viện ghi hình, giữ dự án/dòng thời gian hiện tại. |
| Bảng nhớ tạm | Lịch sử tại máy có tìm kiếm, lọc ảnh/URL/tệp và yêu thích; lịch sử/liên kết độc lập. Ảnh mới xếp hàng nhận chữ tại máy, tìm chữ tìm ảnh gốc hoặc nhấp phải nhận/sao chép. Có thể hủy nhận diện đang chạy; nền không tự sao chép chữ. |
| Theo dõi AI | Tổng hợp tác vụ, trạng thái, xu hướng token, bản đồ đóng góp và thông báo từ CLI, ứng dụng, IDE hỗ trợ. |
| Tải xuống | `yt-dlp` cho video/âm thanh; thiếu `ffmpeg` dùng AVFoundation đóng gói rãnh tương thích và Bilibili chỉ đọc dự phòng. |
| Lịch trình | Thời tiết hiện tại và tối đa sáu nơi lưu; xem/tạo/xóa sự kiện và lời nhắc, đánh dấu hoàn thành. |
| Thư | Đọc các tài khoản Mail.app được chọn để xem hộp thư đến, đánh dấu đã đọc, trả lời, soạn thư và chuyển thư vào thùng rác. |
| Ghi chú | Dùng Apple Notes làm nguồn dữ liệu duy nhất để xem, sửa, tạo và xóa ghi chú Markdown, với bản xem trước trực tiếp và tự động ghi thay đổi trở lại. |
| Trộn âm lượng ứng dụng | Trên macOS 14.4+, chỉnh âm lượng hoặc tắt tiếng từng ứng dụng đang phát và ghi nhớ mức âm lượng; cần quyền ghi âm thanh hệ thống. |
| Tiện ích | Pomodoro một âm và thông báo khi hết phiên, giữ thức, ngăn ngủ nhàn rỗi, vệ sinh màn hình/bàn phím, nhắc chữ, gương camera, dọn thùng rác có xác nhận. |
| Hệ thống | CPU, GPU, bộ nhớ, đĩa, mạng, nhiệt độ, quạt; giải phóng bộ nhớ, quét bộ đệm/nhật ký/tạm an toàn; sức khỏe pin và phụ kiện. |

### Khả năng liên mô-đun

- **Đang phát:** MediaRemote hiện ảnh bìa, tiêu đề, tiến độ, lời cuộn và điều khiển; Core Audio dự phòng xác định nguồn thật. Tạm dừng, dừng, tắt tiếng bị ẩn.
- **Tải trình duyệt:** Nguồn/tiến độ Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera, Arc ở Trang chủ, thu gọn và thông báo bên.
- **Nhập giọng nói:** Phím bật/tắt hoặc giữ để nói, phím toàn cục tự chọn, nhận dạng hệ thống, xử lý bản chép tại máy/từ xa, lịch sử ghi tại máy.
- **Thao tác Nhanh:** Sau mỗi sao chép hiện đảo nhỏ với bản xem trước, mở liên kết, Finder, tìm với máy tìm kiếm chọn, dịch, tính, tạo sự kiện từ ngày và lưu chữ dài/ảnh. Tải xong/AirDrop dùng cùng phím mở thư mục, độc lập với tiến độ trình duyệt. Nhận URL, đường dẫn, email, điện thoại, màu CSS xem mẫu, tính, ngày giờ, ngôn ngữ khác hệ thống, mã, chữ có đếm, ảnh thu nhỏ, tham chiếu tệp. Kích hoạt bằng nút, Command+N bổ sung mặc định hoặc phím bổ trợ/nút chuột bên. Có cử chỉ “giữ trái + nhấp phải” sao chép nhanh tắt mặc định, danh sách chặn, công tắc loại, chế độ nhắc nhẹ.
- **CLI và Skills:** Phát hiện/cài/cập nhật/gỡ CLI AI phổ biến, quản lý Skills tại Cài đặt.
- **Thú cưng máy tính:** Chọn thú cưng có sẵn hoặc được nhập và đặt ở bên trái hoặc bên phải đảo.
- **Cập nhật:** Kênh Release hoặc Preview được chọn tra mã quốc gia của kết nối Internet công khai một lần mỗi lần mở ứng dụng. `CN` kiểm tra appcast Gitee đã ký trước rồi thử GitHub một lần; quốc gia khác kiểm tra GitHub trước rồi Gitee một lần. Nếu không tra được, vẫn ưu tiên Gitee. Sau đó Sparkle tải, xác minh, cài đặt và khởi động lại ứng dụng. Đổi kênh áp dụng cho cả kiểm tra tự động và thủ công.
- **Giao diện và tương tác:** Cài đặt có thể theo giao diện hệ thống, sáng hoặc tối. Đảo hỗ trợ bề mặt trong suốt hoặc mờ, ghim trạng thái mở, nhiều màn hình, Spaces và màn hình ngoài không có phần khuyết.
- **Mặc định:** Cài mới bật mô-đun; tính năng, chỉ báo thu gọn, thông báo bên, số liệu thanh menu, cập nhật điều chỉnh độc lập; cài cũ giữ cấu hình.
- Khi kết nối nhiều màn hình, Cài đặt → Chung → Chế độ màn hình cho phép chọn chế độ Dynamic Island (vị trí camera hoặc tùy chỉnh), chế độ phần khuyết hoặc ẩn riêng từng màn hình. Với một màn hình, mục này được ẩn và dùng giao diện chung; kết nối lại sẽ khôi phục cấu hình đã lưu của từng màn hình. Tất cả màn hình đang bật hiển thị đảo đều giữ đảo thu gọn cùng lúc. Việc mở rộng, thao tác nhanh, ghi âm và thông báo tạm thời chỉ thay thế đảo trên màn hình tương ứng; chọn màn hình thông báo chỉ lọc nội dung, không ẩn đảo đang chờ.

### Công cụ độc lập và quy trình

- **Studio ghi:** Mở thanh menu/Cài đặt. Ghi màn hình, cửa sổ, vùng, âm hệ thống/micrô/camera tùy chọn. Sửa video, âm, ảnh, chữ trên rãnh, gồm phụ đề, thu phóng, chuyển động, chân dung/giọng; xem trước xuất video/GIF/Live Photo/âm. Một số định dạng cần FFmpeg, HDR theo thiết bị. Nhập ảnh/video/âm từ kệ vào thư viện giữ dự án/dòng thời gian.
- **Ảnh, âm và PDF:** Từ Cài đặt. Ảnh 9 thao tác cục bộ và xuất lô/ZIP; âm 27 gồm trộn, chuẩn LUFS, xử lý nhiễu, cần FFmpeg/ffprobe; PDF 14, Office cần LibreOffice/OpenOffice.
- **Bản tin hằng ngày:** Chọn một trong 8 mẫu và các chỉ số trong Cài đặt, xem trước rồi xuất PNG thủ công hoặc vào giờ hằng ngày. Chỉ số không có dữ liệu không được hiển thị như số 0 đã đo.
- **Xem trước cửa sổ:** Đưa con trỏ lên Dock hoặc chuyển bằng Command+Tab, rồi nhấp bản xem trước để kích hoạt cửa sổ tương ứng. Quản lý tính năng và quyền trong Cài đặt.
- **Ghi chú theo ngữ cảnh/họp:** Giữ phím ghi chú và lắc để gắn trang/cửa sổ/màn hình. Sự kiện có liên kết đếm 10 phút trước; tham gia, tạo hoặc nối ghi chú. Quản lý ở kệ.
- **Lắc để thả:** Lắc con trỏ khi kéo tệp để hiện vùng thả; cử chỉ này có công tắc riêng trong Cài đặt.
- **Đầu ra âm thanh và tùy chọn trình phát:** Chọn thiết bị đầu ra trong vùng đa phương tiện. Cài đặt cho phép chọn nguồn tự động hoặc trình phát ưu tiên, bố cục gọn và điều kiện dừng âm thanh môi trường.
- **Hạn mức và đặt lại AI:** Theo dõi AI và Cài đặt hiển thị hạn mức tài khoản được hỗ trợ, thời gian lấy mẫu, thời gian đặt lại và cảnh báo sắp hết, gồm các cửa sổ 5h/7d có sẵn và ngân sách Cursor bằng USD. Dữ liệu này tách biệt với lịch sử token được ghi tại máy.

### Thứ tự phím Thao tác Nhanh

Cửa sổ Thao tác Nhanh gán `Command+1` đến `Command+9`, rồi `Command+0`, theo thứ tự hành động hiện tại. Phím kích hoạt mặc định bổ sung của cấu hình mới là `Command+N`, chạy hành động đầu tiên; `Command+Delete` đóng cửa sổ. Thiết lập phím kích hoạt, nút chuột bên và thứ tự hành động trong Cài đặt. Nâng cấp giữ mọi tổ hợp đã lưu rõ ràng, gồm `Command+1` cũ, phím tự đặt và trạng thái xóa phím kích hoạt; chỉ cấu hình mới hoặc thiếu trường kích hoạt mới dùng `Command+N`.

### Nơi lưu

Cài đặt → Nơi lưu cho phép chọn thư mục riêng cho tải xuống, ảnh chụp màn hình, công cụ ảnh, ghi hình, PDF, Thao tác Nhanh và bản tin hằng ngày. Cấu hình mới mặc định dùng thư mục con của `~/Downloads`: `picture` cho ảnh chụp/ảnh, `video` cho ghi hình, `pdf`, `quick` và `daily`. Công cụ âm thanh dùng hộp thoại xuất để chọn tệp hoặc thư mục. Tệp trên kệ giữ tham chiếu đến bản gốc; ảnh cất và trạng thái ghi chú theo ngữ cảnh được quản lý cục bộ trong `~/Library/Application Support/zisla`, còn dự án ghi dùng thư mục ghi hình. Nội dung ghi chú nhanh nằm trong Apple Notes.

[Trợ giúp và từng bước](https://wzz6423.github.io/zisla/help.html?lang=vi#help) gồm chín nhóm bảng nhớ, chụp/ghi, kệ, họp, AI, đa phương tiện, bản tin, ghi chú/xem cửa sổ và phát/trộn với đoạn phim ngắn.

### Phím tắt và cất ảnh màn hình

**Stash** giữa **Pin** và **Copy** lưu ảnh cuối đã sửa, gồm chú thích/chụp cuộn hoàn tất, vào khay không sao chép bảng nhớ. PNG và metadata ứng dụng gốc/thời gian lưu SQLite tại máy, còn sau khởi động lại. **Stashed screenshots** chỉ hiện các thẻ đó.

**Highlighter** sau **Brush** tô bán trong suốt; đường đầu và dấu tròn mặc định giữ, tắt ở menu. **Extract** sau **Blur** trích chủ thể/nền macOS hoặc vùng vẽ tay. Nhiều vòng gộp vùng, có Select All/Clear; pixel không chọn trong suốt, có hoàn tác. Góc mặc định bán kính 0; kéo nút trên vùng hoặc **Corner radius**, nhãn kích thước `r`. PNG góc trong suốt; về 0 khôi phục pixel gốc.

| Ngữ cảnh | Thao tác | Phím mặc định |
| --- | --- | --- |
| Toàn cục | Chụp màn hình | `Control+1` |
| Toàn cục | Chụp cuộn | `Control+2` |
| Trình sửa ảnh | Ghim | `Control+1` |
| Trình sửa ảnh | Cất khay | `Control+2` |
| Trình sửa ảnh | Chữ nhật | `Control+3` |
| Trình sửa ảnh | Elip | `Control+4` |
| Trình sửa ảnh | Cọ | `Control+5` |
| Trình sửa ảnh | Tô sáng | `Control+6` |
| Trình sửa ảnh | Mũi tên | `Control+7` |
| Trình sửa ảnh | Số | `Control+8` |
| Trình sửa ảnh | Chữ | `Control+9` |
| Trình sửa ảnh | Làm mờ | `Control+0` |
| Trình sửa ảnh | Trích xuất | `Control+A` |
| Trình sửa ảnh | Chụp cuộn | `Control+B` |
| Trình sửa ảnh | Sao chép | `Enter` |
| Trình sửa ảnh | Lưu | `Command+S` |
| Trình sửa ảnh | Hoàn tác | `Command+Z` |
| Trình sửa ảnh | Làm lại | `Command+Shift+Z` |

Cài đặt ảnh chụp hiển thị và ghi lại phím toàn cục cùng phím của trình sửa. Sao chép, Lưu, Hoàn tác và Làm lại được hiển thị nhưng không thể ghi lại. Phím do người dùng ghi được giữ khi nâng cấp; Pin là thao tác trong trình sửa, không phải phím toàn cục riêng, nhưng mục menu vẫn có.

Phím mặc định của trình sửa theo thứ tự thanh công cụ: `Control+1` đến `Control+9`, rồi `Control+0`, `Control+A`, `Control+B` và các chữ tiếp theo. Việc phân bổ bỏ `Q`, `M`, `N` và `W`: nhấn nhầm Command có thể thoát ứng dụng, thu nhỏ, mở hoặc đóng cửa sổ. Người dùng vẫn có thể ghi các tổ hợp này.

Khi nâng cấp, bố cục cũ chưa chỉnh, gồm bố cục Pin/Stash trước đây, chuyển một lần sang mặc định trên. Nếu bất kỳ phím chụp nào đã được tùy chỉnh, bố cục hiện tại được giữ. Khi phím mặc định của thao tác mới xung đột, nó chọn tổ hợp Control còn trống theo cùng thứ tự an toàn. Các tổ hợp ban đầu này cũng có thể ghi lại.

## Bắt đầu nhanh

### Môi trường

- macOS 14+
- Swift 6 / Xcode 16+ (chỉ Command Line Tools cũng xây dựng được)
- Tùy chọn `yt-dlp` và `ffmpeg`; Office sang PDF cần LibreOffice/OpenOffice

Homebrew:

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### Chạy mã nguồn

```bash
swift run zisla
```

Ứng dụng khởi động như tiện ích thanh menu. Đưa con trỏ vào vùng 6 px ở giữa mép trên của màn hình hiện tại để mở đảo, hoặc chọn “Show Island” từ biểu tượng thanh menu.

### Xây `.app`

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

Đóng gói helper `yt-dlp` chính thức:

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh` tải tệp macOS độc lập chính thức với phiên bản được cố định, đối chiếu với `SHA2-256SUMS` chính thức rồi mới cài vào `Tools/yt-dlp`.

## Tích hợp AI

### Phát hiện tự động

zisla đọc trạng thái phiên cục bộ công khai hoặc ổn định của công cụ được hỗ trợ, chỉ trích sự kiện có cấu trúc và siêu dữ liệu cần để xác định trạng thái tác vụ. Không đọc lời nhắc hay nội dung câu trả lời.

| Môi trường | Phát hiện |
| --- | --- |
| OpenAI / Anthropic | Codex CLI/Desktop, Claude Code và môi trường chứa |
| GitHub / Google / xAI | GitHub Copilot CLI/VS Code, Gemini CLI/Desktop, Grok CLI |
| Độc lập/khu vực | Pi, Kimi Code, Qwen Code, Qoder, ZCode Desktop/CLI, TRAE, OpenCode, Harnext/Harness, WorkBuddy |

Chờ phê duyệt hoặc câu trả lời được hiển thị màu vàng, lỗi công cụ/lệnh màu đỏ, chạy bình thường màu xanh; các nguồn đồng thời được nhóm theo thứ tự đỏ, vàng, xanh. Tiến trình phụ Qwen chỉ được coi là hoạt động khi PID còn sống, tránh báo trạng thái cũ sau khi thoát.

Ứng dụng chat không lưu sự kiện không thể phân biệt mở nhàn rỗi và tạo đáp án. Dùng hook `zislactl` bên dưới cho những ứng dụng như ChatGPT; zisla không giả hoạt động từ tiến trình thường trú.

### Giao thức cục bộ `zislactl`

`zislactl` ghi trạng thái tác vụ và lịch sử sử dụng vào SQLite:

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

Lịch sử sử dụng vẫn còn sau khởi động lại, cập nhật thay ứng dụng và xóa tác vụ. Chỉ việc người dùng xóa dữ liệu ứng dụng thủ công mới làm mất lịch sử.

Ví dụ:

```bash
swift run zislactl update \
  --id build-42 \
  --provider claude \
  --title "Refactor index" \
  --progress 68 \
  --detail "17/25"

swift run zislactl usage \
  --provider claude \
  --input-tokens 12400 \
  --output-tokens 2100 \
  --model claude-opus-4-8

swift run zislactl finish --id build-42 --detail "Complete"
```

Nhà cung cấp chuẩn gồm `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `zcode`, `trae`, `opencode`, `pi`, `harness` và `doubao`; bí danh phổ biến được chuẩn hóa tự động. Có thể gọi từ hook công cụ, trình bao shell hoặc tập lệnh tác vụ.

Danh sách tác vụ AI và trạng thái thu gọn dùng logo chính thức của từng công cụ để nhận diện nguồn.

Xem [tham chiếu CLI](Docs/cli-reference.md).

## Tiến độ tải trình duyệt

zisla theo dõi thông tin tiến độ tệp công khai của macOS trong Downloads và kết hợp đuôi tệp tạm, thuộc tính mở rộng của nguồn tải cùng trình duyệt đang chạy để nhận diện nguồn. Không đọc cơ sở dữ liệu lịch sử hoặc gửi yêu cầu mạng để xác định tiến độ; dấu hoàn thành còn khoảng ba giây. Thao tác Nhanh dùng cùng nguồn sự kiện, cung cấp Open Folder khi chuyển thành công đến vị trí cuối. Thời gian thông báo theo cài đặt Thao tác Nhanh; thông báo sao chép hoặc chuyển mới nhất thay thông báo trước.

## Trình tải

Tệp thực thi được tìm theo thứ tự:

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

URL được truyền vào `Process` bằng giá trị argv riêng, không qua shell. Cấu hình lúc chạy và plugin bị bỏ qua, `--exec` bị tắt, giới hạn một mục được áp dụng, và tệp cuối được kiểm tra nằm trong thư mục được cấp quyền.

Thiếu `ffmpeg`:

- Video ưu tiên AVC/MP4 và M4A rồi AVFoundation gói MP4; tệp đơn giữ nguyên.
- Âm ưu tiên M4A hoặc giữ gốc.
- Khi yt-dlp nhận HTTP 412, không tìm thấy định dạng hoặc không có tại máy, Bilibili dùng API chỉ đọc để lấy rãnh DASH và cùng quy trình đóng gói gốc, không cài công cụ khác.

## Ghi chú

Ghi chú Markdown trong đảo dùng Apple Notes làm nguồn dữ liệu duy nhất. Bạn có thể tạo, xem, sửa và xóa ghi chú có sẵn, thay vì chỉ thêm ghi chú mới.

- **Danh sách:** Khi mở, JXA (`osascript -l JavaScript`) đọc tiêu đề và ngày sửa các ghi chú chưa xóa, sắp xếp theo lần sửa mới nhất. Quay lại từ Notes làm mới danh sách; ghi chú trong Recently Deleted bị ẩn. Chọn ghi chú để sửa, làm mới, tạo ghi chú hoặc xóa từ menu ngữ cảnh.
- **Xem và sửa:** AppleScript đọc `plaintext` của ghi chú đã chọn, tức mã nguồn Markdown, vào trình sửa. `TextEditor` gốc ghi thay đổi trở lại sau khoảng 0,8 giây ngừng nhập để tránh gọi AppleScript mỗi lần nhấn phím. Ghi chú mới được tạo trong Apple Notes và chọn tự động.
- **Xem trước:** Bộ phân tích khối có sẵn kết xuất tiêu đề, danh sách không thứ tự/có thứ tự/tác vụ, trích dẫn, khối mã có hàng rào, đường phân cách, chữ đậm, nghiêng, mã nội dòng, gạch bỏ và liên kết thành `AttributedString`.
- **Lưu trữ:** Mã nguồn Markdown được lưu bằng văn bản thuần trong `body`, với ký tự HTML được xử lý thoát và dòng trống được giữ. Đọc `plaintext` khôi phục mã nguồn; Apple Notes hiển thị văn bản thuần, không kết xuất Markdown.
- **Quyền:** Lần đọc hoặc ghi đầu tiên kích hoạt yêu cầu tự động hóa macOS cho Apple Notes; từ chối sẽ trả thông báo lỗi trong danh sách hoặc trình sửa.

Mô-đun Ghi chú không giữ bản sao cục bộ thứ hai; Apple Notes là hệ thống lưu trữ.

## Quyền và riêng tư

- **Lịch:** Quyền Lịch và Lời nhắc được yêu cầu riêng khi mở lần đầu; sự kiện và lời nhắc được làm mới sau tạo, xóa hoặc hoàn thành.
- **Vị trí:** Xin một lần không theo dõi; tìm/lưu/xóa nơi khác Cài đặt.
- **Tệp:** Bookmark giới hạn quyền; chuyển không chép gốc.
- **Bảng nhớ:** Mới bật lịch sử/liên kết riêng. Mỗi `changeCount` tối đa một liên kết tại máy; không log query, không clear/declare/write, không thay bảng nhớ liên thiết bị.
- **Thao tác Nhanh:** Cục bộ mỗi `changeCount` và tải/AirDrop xong; modifier/chuột bên có thể cần theo dõi đầu vào. Cử chỉ sao chép còn gửi ⌘C tổng hợp cần Accessibility. Nhận không mạng, mở/tìm/dịch/lưu chỉ nhấp/phím. Danh sách chặn/loại cho sao chép, công tắc chung cả chuyển.
- **Trạng thái AI:** Phát hiện tự động chỉ đọc sự kiện có cấu trúc và siêu dữ liệu hoạt động cục bộ cần để xác định trạng thái tác vụ.
- **Giọng nói:** Chỉ truy cập micrô và nhận dạng sau hành động rõ ràng của người dùng. Ghi âm, bản chép gốc và văn bản đã xử lý được quản lý tại máy; văn bản chỉ gửi đến mô hình cục bộ, nhà cung cấp từ xa hoặc hồ sơ CLI đã chọn, còn thông tin đăng nhập từ xa được giữ trong cơ sở dữ liệu riêng.
- **Bluetooth và thiết bị:** Chỉ đọc mức pin phụ kiện và thiết bị di động Apple tin cậy khi phần Pin trong Hệ thống đang mở.
- **Camera/đầu vào:** Gương và studio xin camera; âm/thống kê/vệ sinh/modifier-nút bên dùng theo dõi, thống kê tại máy và công tắc riêng.
- **Màn hình/âm:** Ảnh/ghi/xem cần Screen Recording; nguồn chọn lưu tại máy, micrô/camera chỉ khi bật. Trộn macOS 14.4+ System Audio Recording và Core Audio tap.
- **Trình duyệt:** Chỉ tiến độ/tạm công khai, không lịch sử/nội dung.
- **Đa phương tiện:** MediaRemote cung cấp siêu dữ liệu và trạng thái đầu ra tiến trình Core Audio xác nhận việc phát. MediaRemote là framework riêng, nên bản hiện tại không phù hợp gửi trực tiếp lên Mac App Store; khi thiếu siêu dữ liệu, ứng dụng dùng nguồn âm thanh đang hoạt động.
- **Mạng:** Open-Meteo/cảnh báo Trung Quốc công khai khi phù hợp, ưu tiên WeatherKit khác. `ipinfo.io/country` một lần: `CN` Gitee→GitHub, khác ngược, lỗi Gitee. Bilibili thông tin/URL/CDN chỉ đọc; nhận liên kết không mạng. Hạn mức bật đến nhà cung cấp; dịch/sửa AI/clean transcript đến mô hình/CLI. Speech Apple theo hệ thống/ngôn ngữ. Cài/cập nhật phụ thuộc/CLI, IP và thao tác mạng chọn cũng yêu cầu.
- **Tự động hóa:** AppleScript/JXA liệt kê, xem, sửa, tạo và xóa Apple Notes. Cần quyền tự động hóa, không dùng mạng và giữ dữ liệu trong Apple Notes.

## Kiểm thử

Xcode đầy đủ:

```bash
swift test
```

Chỉ Command Line Tools:

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Tài liệu

- [Kiến trúc/hiệu năng](Docs/architecture.md)
- [Tham chiếu CLI](Docs/cli-reference.md)
- [Ký/phát hành](Docs/releasing.md)
- [Phụ thuộc kèm — tiếng Anh](../../../../mac/Vendor/README.md)
- [Thông báo bên thứ ba — tiếng Anh](../../../../mac/Resources/ThirdPartyLicenses/README.md)

## Giới hạn hệ thống

- macOS không có API Dynamic Island công khai; phần khuyết thật được suy ra từ `safeAreaInsets` và vùng phụ phía trên, còn màn hình không khuyết dùng cùng lớp phủ mô phỏng.
- Video DRM, cửa sổ đăng nhập, màn hình khóa và một số ứng dụng toàn màn hình độc quyền có thể không cung cấp dữ liệu Đang phát hoặc không cho phép lớp phủ.
- Không tích hợp media center có thể chỉ nguồn, không bảo đảm tiêu đề/bìa/tiến độ; dừng/tạm dừng/tắt âm cố ý ẩn.
- Trình duyệt phải công bố tiến độ tệp macOS hoặc dùng tệp tạm có thể nhận diện trong Downloads để zisla hiện phần trăm.
- Sức khỏe pin, nhiệt độ, công suất hiện tại và mức pin phụ kiện phụ thuộc phần cứng, cách kết nối và dữ liệu macOS cung cấp; trường thiếu hiển thị là không có dữ liệu.
- Office PDF cần LibreOffice/OpenOffice, PDF khác tại máy.
- Gói chưa được công chứng và có thể cần **Open Anyway** lần đầu. Bản ổn định dùng một chứng chỉ tự ký để giữ quyền macOS qua cập nhật; Sparkle xác minh riêng mọi cập nhật bằng khóa công khai EdDSA nhúng trước giải nén, thay và khởi động lại ứng dụng.

## Giấy phép

[PolyForm Noncommercial License 1.0.0](../../../../LICENSE.md). Phi thương mại được phép; bán và thương mại khác không.
