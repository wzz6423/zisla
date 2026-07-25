# macOS 语音输入：全局热键与权限调研

调研日期：2026-07-24。目标是回答：普通全局快捷键、单键录音、左右 `Option` / `Command` / `Shift` 精确识别分别需要什么权限，以及“千问等没有要求输入监控”是否能作为 Zisla 取消该权限的依据。

结论优先采用 Apple 一手 API/系统文档。千问、Wispr Flow、Superwhisper、MacWhisper 的公开材料用于核实产品能力；除 Wispr Flow 明确说明的按住说话、辅助功能和剪贴板降级外，未发现其余产品公开 macOS 键盘事件 API、左右修饰键语义或 TCC 授权策略的可核验说明。因此**不将“没有看到授权弹窗”写成“该产品绕过输入监控”的事实**。

## 结论

1. **普通全局快捷键可以不申请输入监控。** Apple 的 `RegisterEventHotKey` 是系统注册的全局热键，按“虚拟键码 + 修饰键”注册，并分别提供按下与松开通知；它不是应用自己读取全局原始键盘流。该 API 的修饰键参数可为 `0`，所以对普通、非修饰键的单键预设（例如 `F5`）没有“必须组合键”的 API 限制。[Apple Carbon Event Manager](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/Carbon_Event_Manager/Tasks/CarbonEventsTasks.html)；[本机 macOS SDK：`RegisterEventHotKey` 声明与说明](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/CarbonEvents.h#L15428)。
2. **“后台精确区分左右修饰键 + 单独按住/松开开始结束录音”不能承诺免输入监控。** Apple 的 Carbon 修饰位中，右 `Shift`、右 `Option`、右 `Control` 明确标为 macOS 不支持；普通修饰位只有合并后的 `Command`、`Shift`、`Option` 等。可靠地观察单独修饰键的硬件侧按下/松开，需要监听原始 `.flagsChanged` / `.keyDown` / `.keyUp` 事件；Apple 为事件监听提供 `CGPreflightListenEventAccess` 与 `CGRequestListenEventAccess`，对应输入监控访问。[本机 macOS SDK：左右修饰位限制](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/Events.h#L107)；[Apple：`CGPreflightListenEventAccess`](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteventaccess())；[Apple：`CGRequestListenEventAccess`](https://developer.apple.com/documentation/coregraphics/cgrequestlisteventaccess())。
3. 上述结论并不声称“物理上不存在任何其他实现”。`Events.h` 同时定义了左右修饰键的**虚拟键码**；但 Apple 未公开承诺 `RegisterEventHotKey` 能可靠地把“左/右修饰键单键”作为跨应用、可按住可松开的热键注册。公开 API 对右侧**修饰位掩码**的限制，加上单独修饰键会产生 `.flagsChanged` 而非普通字符键事件，意味着这不是可作为产品承诺的免授权方案。应将“不需要输入监控”的承诺限定为常规全局热键/普通单键，而不能扩展到左右 `Option`、`Command`、`Shift`。
4. **录音本身只需要麦克风授权。** `AVCaptureDevice.requestAccess(for: .audio)` 请求的是音频硬件访问，与键盘监听无关；语音识别还可能另行需要语音识别授权。[Apple：请求媒体采集授权](https://developer.apple.com/documentation/avfoundation/requesting_authorization_for_media_capture)；[Apple：`AVCaptureDevice.requestAccess(for:completionHandler:)`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/1624584-requestaccess)。

## 权限边界

| 权限/机制 | 解决的问题 | 不能替代什么 | 对语音输入的含义 |
| --- | --- | --- | --- |
| 麦克风（`AVCaptureDevice`） | 读取音频设备，供录音与识别使用。 | 不接收全局快捷键，不读取键盘，也不向其他 app 输入文本。 | 每种录音模式都需要；它与输入监控无关。 |
| 输入监控（事件监听访问） | 在 app 不处于前台时，观察全局键盘/鼠标原始事件；`CGEvent` 的事件监听访问 API 用来预检/请求它。 | 不授予麦克风、识别或跨 app 控制权限。 | 只有需要原始全局事件时申请，例如左右侧修饰键、单独修饰键的按住/松开。 |
| 辅助功能（Accessibility） | 使进程成为受信任的辅助功能客户端，可读取/操作其他应用的 UI；Apple 的 `AXIsProcessTrustedWithOptions` 可检查并提示。 | 不提供麦克风，不等价于输入监控，也不替代系统热键注册。 | 仅当 Zisla 要把转写结果主动写入其他 app（例如定位控件、模拟粘贴/键入）时才可能需要。先复制到剪贴板、让用户自行粘贴不需要它。 |
| `RegisterEventHotKey` | 让系统分发已注册的全局热键按下/松开通知。 | 不提供全局原始按键流，也不保证区分左右修饰位。 | 用于普通组合键和普通单键的无输入监控路径。 |

系统级说明也把“Input Monitoring”与“Accessibility”和“Microphone”列为不同的隐私项目：[输入监控](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)、[辅助功能](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)、[硬件功能（含麦克风）](https://support.apple.com/guide/mac-help/control-access-to-hardware-features-mchlf6d108da/mac)。辅助功能 API 的“受信任客户端”定义见 [Apple：`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459163-axisprocesstrustedwithoptions)；事件 tap 接收键盘上下键的访问前提见 [本机 macOS SDK：`CGEventTapCreate` 注释](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGEvent.h#L269)。

## 竞品与千问：已证实与未披露

| 产品/类别 | 官方一手材料 | 已证实 | 官方未披露，不能推断 |
| --- | --- | --- | --- |
| macOS 系统听写 | [Apple：在 Mac 上使用听写](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac) | 听写是系统功能，由 macOS 提供入口。 | 不能将系统自身的权限模型套用到第三方 app；它不证明第三方能监听左右修饰键而无需输入监控。 |
| 千问 / Qwen Web | [Qwen 官方 Web 入口](https://chat.qwen.ai/) | 该链接是千问的官方 Web 入口。若用户是在浏览器页面点击麦克风，授权主体通常是浏览器的麦克风权限，而非网页获得 macOS 输入监控。 | 未找到千问官方材料说明 macOS 原生端的全局热键实现、是否支持按住说话、是否区分左右修饰键或是否申请输入监控。因此不能以实际未弹窗现象证明它实现了同等的全局快捷键能力。 |
| Wispr Flow | [官方：支持的键盘热键](https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts)；[官方：修复文字未粘贴](https://docs.wisprflow.ai/articles/7971211038-fix-text-not-pasting-after-dictation) | Mac 端支持配置按住说话键；它将转写临时写入本地剪贴板，跨应用自动粘贴失败时要求辅助功能授权，并允许用户手动粘贴。 | 官方没有披露热键的底层 API、输入监控授权状态，或是否区分左右修饰键；不能据此声称它免输入监控或能区分左右键。 |
| Superwhisper | [Superwhisper 官方产品页](https://superwhisper.com/) | 官方产品页将其定位为语音转文字产品。 | 同样未获取到公开的、可核验的全局热键实现和左右修饰键说明；不能用其 UX 推定权限实现。 |
| MacWhisper | [MacWhisper 官方产品页](https://macwhisper.com/)；[官方帮助中心](https://macwhisper.helpscoutdocs.com/) | 官方提供 macOS 语音转写产品与帮助入口。 | 本轮未获得其关于全局按住说话、输入监控或左右修饰键的官方技术说明；不应把它作为“免输入监控的精确左右键”证据。 |

这里的关键区别是：网页或系统级听写可以通过**页面按钮/系统入口**开始录音，只需由浏览器或系统请求麦克风；一个独立 macOS app 若要在任何应用上方感知“左 Option 单独被按住然后松开”，则是在解决另一件事，即读取全局原始输入。

## 对 Zisla 的产品方案

建议保留两个清晰模式，而不是为了消除一个授权而牺牲用户要求的精确能力：

1. **无需输入监控：普通热键与普通单键。** 默认提供 `F5` 等非修饰键单键，以及常规组合键；使用 `RegisterEventHotKey` 接收按下/松开，允许按住说话。此路径仅在用户真正开始录音时请求麦克风；不把输入监控按钮展示为必经步骤。
2. **需要输入监控：左右修饰键与单独修饰键。** 当用户录制或选择 `左/右 Option`、`左/右 Command`、`左/右 Shift`，或要求精确区分这些键时，解释原因并跳转系统“输入监控”设置；授权后再注册只读 event tap。这样既满足精确需求，也不会把它伪装成普通热键。
3. **避免混淆辅助功能。** 语音识别结束先将文本放到 Zisla 自己的界面或剪贴板；只有“自动写入当前其他应用”这项独立功能才询问辅助功能。不要用辅助功能授权去替代输入监控，或以输入监控解释麦克风失败。
4. **录制时机。** 无论哪种热键路径，先确保麦克风/语音识别授权完成，再开始音频引擎；热键按下期间异步授权的竞态必须以一次录制请求的标识取消，防止已松键后仍开始录音。

## 验证建议

以下应在实际签名的 `Zisla.app` 中分别测试，而不是从竞品界面猜测：

1. 拒绝输入监控，只保留麦克风授权：`F5` 与普通组合键在另一应用前台时能收到按下、松开并正确开始/结束录音。
2. 拒绝输入监控：选择左右 `Option` / `Command` / `Shift` 时明确显示“需要输入监控”，且不得偷偷降级成合并后的任一侧。
3. 授予输入监控：六个左右修饰键都分别做按住、松开、连续触发和切换前台应用测试。
4. 拒绝麦克风：热键可以触发界面反馈，但绝不启动音频引擎；再次授权后能够重新注册并开始录音。
5. 拒绝辅助功能：语音文本仍能显示/复制；仅“自动输入到其他 app”被禁用并说明原因。

## 资料索引

- [Apple Carbon Event Manager](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/Carbon_Event_Manager/Tasks/CarbonEventsTasks.html)：系统注册全局热键及按下/松开通知。
- [Apple Core Graphics：事件监听访问](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteventaccess())、[请求事件监听访问](https://developer.apple.com/documentation/coregraphics/cgrequestlisteventaccess())：输入监控预检与请求 API。
- [Apple AVFoundation：媒体采集授权](https://developer.apple.com/documentation/avfoundation/requesting_authorization_for_media_capture)：麦克风访问边界。
- [Apple Accessibility：受信任进程检查](https://developer.apple.com/documentation/applicationservices/1459163-axisprocesstrustedwithoptions)：辅助功能访问边界。
- [Apple：输入监控隐私项目](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)：用户侧系统设置入口。
- [本机 macOS SDK `Events.h`](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/Events.h)：左右修饰位限制与左右虚拟键码定义。
