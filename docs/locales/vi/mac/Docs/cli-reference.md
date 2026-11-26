# Tham chiếu tích hợp `zislactl`

[English](../../../../../mac/Docs/cli-reference.md) | [简体中文](../../../../../mac/Docs/cli-reference.zh-CN.md) | **Tiếng Việt** | [Ngôn ngữ khác](../../../README.md)

`zislactl` là giao thức trạng thái cục bộ dùng chung cho công cụ AI, tập lệnh và tác vụ CI tích hợp với zisla. Giao thức ghi trạng thái tác vụ, mức sử dụng và thông báo dưới dạng dữ liệu có cấu trúc, lưu trong giao dịch SQLite để tránh trạng thái ghi dở. Tài liệu này quy định nhà cung cấp, lệnh và giới hạn trường ổn định.

## Nguyên tắc thiết kế

- Trạng thái được ghi cục bộ; không tải lên lời nhắc, nội dung câu trả lời hoặc thông tin đăng nhập.
- Cập nhật cùng ID tác vụ có tính lũy đẳng; trình đọc thấy trạng thái cơ sở dữ liệu đã commit đầy đủ.
- Tên nhà cung cấp chấp nhận bí danh tương thích nhưng được lưu bằng giá trị chuẩn.

## Lưu trữ cục bộ và phạm vi JSON

Tác vụ, mức sử dụng và thông báo nằm trong `~/Library/Application Support/zisla/ai-state.sqlite`. Việc ghi dùng giao dịch SQLite; giao thức hiện tại không ghi `ai-state.json`. Xóa tác vụ vẫn giữ lịch sử sử dụng.

`zislactl` nhận tùy chọn dòng lệnh được mô tả, còn `list` in văn bản theo dòng. Tích hợp và cấu hình vẫn dùng JSON có cấu trúc, gồm đầu vào phiên JSON/JSONL của công cụ bên ngoài và mã hóa/giải mã cài đặt theo quy tắc phân tích riêng. Bản thân CLI dùng tham số dòng lệnh, đầu ra văn bản và lưu trữ SQLite.

## Nhà cung cấp

| Giá trị | Bí danh |
| --- | --- |
| `claude` | `claude-code`, `claude-cli`, `claude-desktop` |
| `codex` | `openai-codex`, `codex-cli`, `codex-desktop` |
| `gemini` | `google-gemini`, `gemini-cli`, `gemini-code-assist` |
| `grok` | `grok-cli`, `xai` |
| `gpt` | `openai`, `chatgpt`, `openai-gpt` |
| `copilot` | `github-copilot`, `copilot-cli`, `copilot-chat` |
| `kimi` | `kimi-code`, `kimi-code-cli`, `kimi-vscode` |
| `qwen` | `tongyi`, `qwen-code`, `qwen-code-cli`, `qwen-vscode` |
| `coder` | `qoder`, `qoder-cli`, `qoderwork`, `qoderwork-cn`, `qoderwake`, `qwen-coder` |
| `zcode` | `z-code`, `zcode-cli`, `zcode-desktop`, `glm`, `glm-coding`, `z-ai`, `z.ai` |
| `trae` | `trae-work`, `traework`, `trae-solo`, `trae-cn` |
| `opencode` | `open-code`, `open_code` |
| `pi` | `pi-coding`, `pi-coding-agent`, `pi-cli`, `pi-agent` |
| `harness` | `harnext`, `harnext-cli`, `harness-cli` |
| `doubao` | `豆包` |
| `delta` | `delta-app`, `delta-desktop`, `zed-delta` |
| `orca` | `orca-desktop`, `orca-ide` |
| `workbuddy` | `workbuddy-desktop` |
| `workbuddy-ai` | `workbuddyai`, `workbuddy ai` |

WorkBuddy và WorkBuddy AI là hai sản phẩm cho thị trường nội địa/quốc tế, không phải bản cũ/mới của một ứng dụng. Nhà cung cấp chuẩn, kho dữ liệu, biểu tượng và liên kết sâu phải riêng biệt. Bản ghi WorkBuddy cũ dùng `harness` vẫn đọc được; nhà cung cấp này không được đổi tên hay chuyển toàn cục. ID thông báo WorkBuddy có ranh giới nhà cung cấp/tác vụ rõ ràng (`ai-active-workbuddy:<id>` hoặc `ai-active-workbuddy-ai:<id>`), nên tác vụ WorkBuddy thủ công có ID bắt đầu `ai-` không bị nhầm thành WorkBuddy AI.

### Phát hiện tự động Delta, Orca, WorkBuddy và WorkBuddy AI

- Delta đọc siêu dữ liệu luồng hội thoại đã lập chỉ mục từ `Library/Application Support/Delta/user_*/data.sqlite` và cơ sở gốc cũ. Luồng lưu trữ, nhàn rỗi hoặc lỗi thời bị loại. Số sử dụng đến từ sổ `app_model_usage_daily` của Delta, gồm đọc và ghi bộ đệm. Phiên bản không có sổ này không báo sử dụng tự động, không đoán số từ hội thoại.
- Orca đọc ảnh chụp trạng thái `agent-hooks/last-status.json` và trạng thái lượt hội thoại có cấu trúc hiện tại từ `agent-session-journal.db`, gồm thư mục hồ sơ và bản ghi lượt v1/v2/v3. Dùng phiên bản sửa cao nhất và thứ tự lượt ban đầu. Loại phiên hoàn thành, hết hạn, từ xa và chỉ có định danh. Đường dẫn bản chép đáng tin cậy và thư mục tài khoản Claude/Codex được ghim cũng đóng góp token. Mẫu giữ nhà cung cấp CLI gốc và ID sự kiện, nên trình phát hiện CLI thông thường không đếm lại. Bộ đệm sử dụng toàn máy của Orca chủ động không được nhập thêm.
- WorkBuddy đọc `~/.workbuddy/workbuddy.db` của riêng nó, dùng nhà cung cấp `workbuddy`, biểu tượng WorkBuddy và `workbuddy://chat/<id>`. Không kiểm tra kho WorkBuddy AI.
- WorkBuddy AI đọc trạng thái, tiêu đề, mô hình và thời gian phiên từ `~/.workbuddy-ai/workbuddy.db`, độc lập với `~/.workbuddy/workbuddy.db`. Loại phiên xong, xóa và cũ; giá trị mới hơn giữa `updated_at` và `last_activity_at` giữ phiên chạy lâu hiển thị. Tác vụ dùng `workbuddy-ai`, biểu tượng WorkBuddy AI và `workbuddy-ai://chat/<id>`. Tích hợp chỉ phát hiện phiên: `session_usage.used` là mức chiếm ngữ cảnh, tín dụng không phải USD/token, nên không nhập hai loại này như token tính phí. Có thể báo số thủ công bằng `zislactl usage`.
- Mọi tích hợp chỉ đọc và thực hiện trong khả năng dữ liệu cho phép; kho thiếu/không tương thích trả về không có dữ liệu. Không truy vấn nội dung luồng Delta được sao chép hoặc nội dung thông điệp trong nhật ký Orca. Dùng `zislactl usage` cho công cụ/phiên bản không công bố số sử dụng đã ghi.

## Cú pháp tùy chọn

- Viết `--key value` hoặc `--key=value`. Mỗi tùy chọn chỉ xuất hiện một lần trong lệnh; lặp là lỗi sử dụng với mã thoát 64.
- Giá trị có thể bắt đầu `--`, như `--detail --verbose`. Ngoại lệ là cờ của cùng lệnh: `--failed` với `finish`, `--queued` với `update` không bị nhận làm giá trị. Vì vậy biến trống không có dấu nháy trong `--detail $DETAIL --failed` vẫn đánh dấu thất bại. Truyền giá trị ký tự đó bằng `--detail=--failed`.
- `--failed` và `--queued` là cờ. Đứng riêng nghĩa là true; `--failed=false` hoặc `--failed false` và dạng tương ứng queued tắt cờ. Giá trị khác gây lỗi sử dụng.

## `update`

Tạo hoặc thay tác vụ có cùng `id`.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- Bỏ `--progress` thì giao diện hiện tiến độ không xác định.
- `--pid` tùy chọn, chỉ truyền khi biết tiến trình của tác vụ.
- `--status` báo rõ đang chạy, xếp hàng, chờ hành động người dùng hoặc lỗi khi chạy.
- `--queued` là bí danh `--status queued`; không chỉ định trạng thái thì tác vụ đang chạy. `--status` rõ ràng ưu tiên hơn `--queued`.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

Tác vụ thành công được đặt 100%; thất bại giữ tiến độ cuối.

## `remove`

```text
zislactl remove --id <id>
```

Thoát với mã 65 khi không có tác vụ.

## `clear`

```text
zislactl clear
```

Xóa tác vụ nhưng giữ lịch sử sử dụng và thông báo.

## `list`

```text
zislactl list
```

In trạng thái, nhà cung cấp, tiêu đề và phần trăm hiện tại, mỗi tác vụ một dòng.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

Mức sử dụng cung cấp dữ liệu biểu đồ 12 giờ và bản đồ nhiệt 7x24.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

Thông báo xuất hiện từ bên được chọn và tạm ngừng tự đóng khi con trỏ ở trên.

## `message`

Gửi một thông báo đến hai bên đảo: trái hiện biểu tượng ứng dụng và người gửi, phải cuộn nội dung.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

Ví dụ:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender`, `--content` bắt buộc; `--app-bundle-id` tùy chọn để xác định biểu tượng ứng dụng cài.
- Xuống dòng và khoảng trắng thừa được gộp; nội dung cắt khoảng 48 ký tự rồi thêm dấu ba chấm.
- Một giao dịch SQLite lưu cả hai `IslandNotice`, không thay hành vi `notify`.

## Mã thoát

| Mã | Ý nghĩa |
| --- | --- |
| `0` | Thành công |
| `64` | Tham số hoặc lệnh con không hợp lệ |
| `65` | Lỗi dữ liệu, tác vụ thiếu hoặc cơ sở dữ liệu hỏng |
| `70` | Lỗi hệ thống tệp hoặc lỗi thực thi khác |
