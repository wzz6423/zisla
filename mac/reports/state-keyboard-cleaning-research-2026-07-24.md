# State 键盘清洁调研（2026-07-24）

## 结论

未找到 Better365 State（`com.better365.menubar`）的公开源码，因此**不能声称已经读到**
`startCleanKeyboard` 或 `stopCleanKeyboard` 的函数体，也不能从二进制符号推断它实际使用
哪一种事件拦截路径。

不过，macOS 的公开 API 已经足以界定 Zisla 所需的行为：若键盘清洁期间要同时满足
“桌面不黑屏、鼠标可继续点击、即使焦点切到别的应用仍吞掉按键”，必须使用受辅助功能
授权约束的全局 active event tap；`NSEvent.addLocalMonitorForEvents` 只能拦截发送给
本应用的事件，透明 key window 一旦因鼠标点击失去焦点便不再有效。

## State 的可验证证据

### 公开资料与公开源码检索

| 证据 | 可确认的事实 | 不能确认的事实 |
| --- | --- | --- |
| [Better365 State 产品页](https://www.better365.cn/state.html) | 该页将 State 描述为 Mac 硬件状态监测工具，并链接到 App Store。 | 页面没有“键盘清洁”、输入接管、桌面遮罩或进入/退出流程说明。 |
| [App Store 产品页](https://apps.apple.com/cn/app/id1472818562) | 官方分发页对应 State。 | 产品描述未说明键盘清洁的实现、权限或交互。 |
| [Better365 支持页](https://www.better365.cn/support.html) | State 是可提交问题的支持产品。 | 没有键盘清洁操作指南。 |
| [Better365 隐私政策](https://www.better365.cn/Privacy.html) | 政策写明：某些功能可在用户控制下使用“辅助功能”运行脚本和系统命令。 | 该通用表述没有把辅助功能或 event tap 归因到 State 的键盘清洁。 |
| [Better365 sitemap](https://www.better365.com/sitemap.xml) 与官网 State 页 | 官网公开了产品页。 | 未发现源码发布链接。 |
| GitHub 已登录代码搜索：[`startCleanKeyboard`](https://github.com/search?q=startCleanKeyboard&type=code)、[`StopCleanKeyboardNotificationWithState`](https://github.com/search?q=StopCleanKeyboardNotificationWithState&type=code)、[`com.better365.menubar`](https://github.com/search?q=com.better365.menubar&type=code) | 2026-07-24 运行 `gh search code`，三个查询均返回空数组。 | 这不能证明私有仓库或未被索引的源码不存在。 |
| GitLab Projects API：[`better365`](https://gitlab.com/api/v4/projects?search=better365&simple=true&per_page=100)、[`com.better365.menubar`](https://gitlab.com/api/v4/projects?search=com.better365.menubar&simple=true&per_page=100)、[`CleanScreenWC`](https://gitlab.com/api/v4/projects?search=CleanScreenWC&simple=true&per_page=100) | 三个查询均没有公开项目候选。 | 该 API 是项目名检索，并非全量源码检索。 |

因此，本调研没有发现可引用的 `startCleanKeyboard` / `stopCleanKeyboard` 公开实现；不应把
反编译、猜测或网络二手说法作为结论。

### 本机 State.app 元数据、签名与符号

以下均由本机已安装的 `/Applications/State.app` 直接读取，未执行应用，也未反编译函数体。

| 证据路径或命令 | 可确认的事实 | 结论边界 |
| --- | --- | --- |
| [`Info.plist`](/Applications/State.app/Contents/Info.plist) | Bundle id 为 `com.better365.menubar`，版本 `2.1.8`，`LSUIElement=true`，是菜单栏应用。 | 不包含键盘清洁的工作方式。 |
| `codesign -d --entitlements :- /Applications/State.app` | 签名为 Mac App Store 签名；有 app sandbox、application group、Bluetooth/USB、用户选择文件读写及网络 client entitlement。 | 辅助功能信任是 TCC 授权，不是这里可据此判定的“已授权 entitlement”。 |
| [`State` 可执行文件](/Applications/State.app/Contents/MacOS/State) 的可读 Objective-C 字符串 | 包含 `startCleanKeyboard`、`stopCleanKeyboard`、`openPrivacyAccessibilitySetting`、`LCKeyboardEvents`、`HUD_enabled_clean_keyboard`、`HUD_disabled_clean_keyboard`、`Stop Clean`、`CleanScreenWC`。 | 这些名称证明发行包包含相关 selector、类名或资源 key，**不证明**它们的调用关系、视觉布局或函数体。 |
| 同一可执行文件的动态导入（`nm -arch arm64 -u`） | 导入 `CGEventTapCreate`、`CGEventTapEnable`、`AXIsProcessTrusted`、`AXIsProcessTrustedWithOptions` 与 `kAXTrustedCheckOptionPrompt`。 | State 是多功能应用；导入符号不能单独归因到键盘清洁。 |

符号与 HUD 资源使“State 可能有一个独立的键盘锁定状态和一个可点击的停止入口”成为合理的
产品线索，但仍不是它“保留桌面可见”或“采用 event tap”的代码证据。

## Apple 公开 API 与权限关系

1. [`NSEvent.addLocalMonitorForEvents(matching:handler:)`](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforeventsmatching)
   在事件派发给**本应用**前监视；handler 返回 `nil` 能阻止该事件在本应用中继续派发。Apple
   同时说明只有经 `NSApplication.sendEvent(_:)` 分发的事件会进入该 monitor。
2. Apple 的[事件监视指南](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)
   明确区分：local monitor 只看本应用的事件；global monitor 看其他应用但不能修改或阻止事件。
   [`addGlobalMonitorForEvents(matching:handler:)`](https://developer.apple.com/documentation/appkit/nsevent/1535472-addglobalmonitorforevents)
   也明确它只能收到事件副本，不能改动或阻止原始派发。
3. [`CGEvent.tapCreate`](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))
   可以创建 passive listener 或 active filter；active filter 可以修改或丢弃事件。文档明确：要接收
   key down/key up，进程需以 root 运行或获得辅助功能访问。
   [`CGEventTapOptions`](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions) 与
   [`CGEventTapCallBack`](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback) 进一步说明：
   active filter 的回调返回 `NULL` 可删除事件，passive listener 则不能改变事件流。
4. 本机 macOS SDK 的 Apple 头文件
   [`CGEvent.h`](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreGraphics.framework/Headers/CGEvent.h:263)
   说明 active filter 可以 discard event，并在 269-279 行说明 key event 的辅助功能条件；
   [`AXUIElement.h`](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Headers/AXUIElement.h:55)
   说明 `AXIsProcessTrustedWithOptions` 检查进程是否为受信任辅助功能客户端，
   `kAXTrustedCheckOptionPrompt` 可在未受信任时异步提示用户。
5. Apple 的[输入监控设置说明](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)
   说明当前 macOS 可逐应用允许或撤销跨应用键盘、鼠标和触控板监控。Apple 的 event-tap API 文档
   明确的是辅助功能条件；在目标 macOS 版本上，Zisla 应实际验证 active tap 还会触发或依赖哪些
   TCC 项（例如输入监控），而不把两种授权混为一谈。

## 对 Zisla 的实现建议

任何以 [ScreenCleaningController.swift](/Users/wzz/个人/code/zisla/mac/Sources/ZislaKit/ScreenCleaningController.swift)
中的 `NSEvent.addLocalMonitorForEvents` 加输入窗口为核心的键盘路径，都只在 Zisla 保持前台时有效；
即使输入窗口透明，用户点击 Finder、浏览器或桌面后，后续 key event 将派发到新的前台应用，local
monitor 不再能拦截。

为准确实现用户所要的“只接管键盘输入”：

1. 键盘清洁不创建黑色遮罩、不激活透明 key window，也不接管鼠标；桌面与现有窗口保持可见。
2. 开启前调用 `AXIsProcessTrustedWithOptions`。未获授权时不要伪装为已开始；提示用户授予
   “辅助功能”权限，并在授权后重试。
3. 获授权后以 `CGEventTapCreate` 建立仅覆盖 `keyDown`、`keyUp`、`flagsChanged` 的 **active**
   event tap，callback 对这些事件返回 `nil`；鼠标事件不在 mask 中，仍照常派发。
4. 通过菜单栏或岛上的鼠标可点击“结束清洁”入口停止并释放 tap。键盘事件本身已被吞掉，不能
   只依赖键盘快捷键退出。
5. 若选择继续保留无需辅助功能的 local-monitor 版本，应把能力说明限制为“Zisla 位于前台时
   暂停键盘输入”；这与全局键盘清洁不是同一语义。

## 未决项

- 未有公开源码、官方帮助文档或本次未执行的可复现 UI 观察来证明 State 实际是否始终保留桌面、
  使用何种 event tap、如何进入或退出键盘清洁。
- State 发行包中存在 Accessibility/event-tap 相关符号，但该应用还有硬件监测、热键和其他功能；
  不可将符号存在当作键盘清洁函数的实现证据。
