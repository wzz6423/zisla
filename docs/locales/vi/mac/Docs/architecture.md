# Thiết kế kiến trúc và hiệu năng

[English](../../../../../mac/Docs/architecture.md) | [简体中文](../../../../../mac/Docs/architecture.zh-CN.md) | **Tiếng Việt** | [Ngôn ngữ khác](../../../README.md)

## Kích hoạt ở mép trên

Trạng thái ẩn không có cửa sổ trong suốt. `PointerEdgeMonitor` cài bộ theo dõi `NSEvent` toàn cục/cục bộ cho chuột di chuyển và kéo; `ScreenLayoutEngine` dùng hình học để xác định con trỏ vào vùng 6 px ở giữa trên mỗi màn hình.

Mỗi màn có định danh ổn định ghép `NSScreenNumber` với `CGDirectDisplayID`. Bố cục neo ở `screen.frame.maxY` nên hỗ trợ tọa độ âm, màn xếp dọc và màn ngoài không khuyết.

## Cửa sổ

Đảo chính giữ một `.borderless + .nonactivatingPanel`:

- Dùng mức `.statusBar` không che màn khóa hoặc menu hệ thống.
- `.canJoinAllSpaces + .fullScreenAuxiliary` hỗ trợ Spaces và ứng dụng toàn màn hình thông thường.
- Mở khi trỏ không gọi `NSApp.activate`, không lấy tiêu điểm hiện tại.
- Ẩn dùng `orderOut`, không chiếm thanh menu bởi cửa sổ trong suốt.

Bảng thông báo trái/phải tạo khi cần và ẩn ngay khi hết hàng.

## Trạng thái và đồng thời

- AppKit, trạng thái SwiftUI, điều khiển cửa sổ ở `MainActor`.
- Tải, thời tiết và yêu cầu GitHub dùng actor.
- AI hook được theo dõi qua sự kiện hệ thống tệp thư mục. Mỗi nguồn phiên so thời gian sửa/kích thước tệp phiên hoặc hoạt động mới nhất, dùng lại bộ đệm phân tích nếu không đổi.
- Phát hiện chỉ đọc sự kiện có cấu trúc, dấu trạng thái cố định, siêu dữ liệu cần. Không đọc lời nhắc/đáp án; lỗi parser một nhà cung cấp không chặn khác.
- Hạn mức tài khoản AI được lấy riêng từ từng nhà cung cấp. Gemini và Claude/GPT của Antigravity có cửa sổ đặt lại và cảnh báo riêng. Hạn mức trò chuyện thông thường của Gemini App dùng Cookie web đã lưu của cùng tài khoản Google; Gemini CLI giữ nguồn OAuth cục bộ. Không ước tính hạn mức khi thiếu dữ liệu.
- Trễ thu gọn dùng `Task` hủy được và token thế hệ, không cho tác vụ cũ ẩn đảo đã mở lại.
- Ẩn không `TimelineView`, timer 60 Hz hoặc gửi hoạt ảnh liên tục.

## Phát hiện đa phương tiện

MediaRemote cho tiêu đề, bìa, tiến độ và điều khiển. Thuộc tính đối tượng tiến trình Core Audio 14.4+ xác nhận luồng đầu ra đang chạy và ứng dụng nguồn dự phòng khi thiếu metadata. Danh sách/trạng thái dùng lắng nghe thuộc tính cùng xác minh định kỳ có giới hạn; không thu nội dung âm thanh, không xin Screen Recording/Accessibility. Nguồn tạm dừng/dừng/tắt tiếng không giữ ở vùng media.

## Ghi và trộn ứng dụng

Ghi màn hình/trộn âm tách khỏi phát hiện metadata. Ghi xin Screen Recording và micrô/camera bật, lưu nguồn tại máy, quản lý dự án trong thư mục ghi chọn. Trộn dùng Core Audio tap macOS 14.4+ và cần System Audio Recording.

## Vật liệu

macOS 26 một lớp SwiftUI `glassEffect`, 14/15 một lớp `NSVisualEffectView`. Reduce Transparency đổi nền đục, không chồng nhiều blur/vật liệu.

## Giới hạn an toàn tải

Swift gọi `yt-dlp` qua `Process.executableURL` và mảng tham số; URL luôn là argv riêng sau `--`. Tắt cấu hình runtime/plugin/exec, rút ống đầu ra đồng thời, phân tích tiến độ qua dấu JSON.

Chỉ thành công khi exit 0, đường ra tồn tại, đường giải quyết vẫn trong thư mục được phép. Mỗi tác vụ chỉ dọn thư mục tạm tên UUID của mình.

## Kiểm tra và tải cập nhật

Kênh chọn tra quốc gia đầu ra công khai mỗi lần chạy, rồi Sparkle lấy appcast đã ký cho bản cài, tải ZIP qua HTTPS, xác minh chữ ký EdDSA của kho/feed trước giải nén, thay ứng dụng và mở lại. `CN` bắt đầu Gitee (`update-release` cho Release, `preview` cho Preview), thử feed GitHub cùng kênh một lần; khác GitHub rồi Gitee một lần. Lỗi tra vẫn Gitee trước; feed trỏ ZIP đã ký trên host của nó. Phát hành appcast mỗi kiến trúc bên cạnh `appcast.xml` chung; bản đơn yêu cầu slice mình (x86_64 phiên dịch yêu cầu `arm64`), không đổi sang universal. Universal đếm slice executable mình, giữ `appcast.xml`, cũng phục vụ bản trước khi có cập nhật kiến trúc. Đổi cài đặt tác động tự động/thủ công, reset chu kỳ Sparkle tiếp. Khóa công khai nhúng không có tài khoản; khóa riêng ở macOS Keychain người duy trì hoặc tệp riêng được bảo vệ.
