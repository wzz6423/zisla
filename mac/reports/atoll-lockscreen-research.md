# Atoll 锁屏信息实现调研

调研日期：2026-07-23。本文只记录一手源码与官方资料，不复制 Atoll 的 GPL 代码。

## 结论

Atoll 的“Lock Screen Widgets”不是修改 macOS 原生 `loginwindow`、密码输入框或认证逻辑。它在系统报告锁定时，创建多个由自身持有的透明、无边框 `NSWindow`，把播放器、天气等 SwiftUI 视图装入这些窗口；解锁后仅 `orderOut` 自己的窗口。

让这些第三方窗口出现在锁屏空间的关键并非普通 AppKit 窗口，而是 `SkyLightWindow` 对私有 `SkyLight.framework` 的调用。它有系统兼容性、分发和审核风险，不能算作公开支持的 macOS 锁屏扩展 API。原生密码框仍由系统绘制，Zisla 不应查询、移动、替换或遮挡其控件。

## 官方来源与许可

- 官方仓库：[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)，仓库主页字段指向 [getatoll.app](https://getatoll.app)，默认开发分支为 `dev`。
- 官方 README 将产品定位为 macOS Dynamic Island，并列出“锁屏媒体、计时器、充电、蓝牙设备、天气组件”： [ReadMe.md:39-60](https://github.com/Ebullioscopic/Atoll/blob/dev/ReadMe.md#L39-L60)。
- README 明确声明 GPL v3：[ReadMe.md:99-100](https://github.com/Ebullioscopic/Atoll/blob/dev/ReadMe.md#L99-L100)；许可证正文标识为 GNU GPL v3：[LICENSE:1-2](https://github.com/Ebullioscopic/Atoll/blob/dev/LICENSE#L1-L2)。因此 Zisla 不能复制、改写后保留实质结构，或直接引入 Atoll 的 Swift 源码；如形成 GPL 衍生作品会承担 GPL 的分发义务。
- Atoll 自己注明锁屏窗口渲染使用 [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)：[ReadMe.md:112-115](https://github.com/Ebullioscopic/Atoll/blob/dev/ReadMe.md#L112-L115)。该依赖为 MIT，但使用的是私有系统框架，MIT 许可不消除私有 API 风险。

## Atoll 的实际机制

| 阶段 | 实现证据 | 含义 |
| --- | --- | --- |
| 监测锁定状态 | [LockScreenManager.swift:79-104](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/LockScreenManager.swift#L79-L104) 订阅 `com.apple.screenIsLocked` 与 `com.apple.screenIsUnlocked`；[236-241](https://github.com/Ebullioscopic/Atoll/blob/503606ca34aece08d30d3c86bce50eb5e07a3139/DynamicIsland/managers/LockScreenManager.swift#L236-L241) 还用 `CGSessionCopyCurrentDictionary()` 读取 `"CGSSessionScreenIsLocked"`，按 `Bool` 解析。 | Atoll 以通知为主、session dictionary 轮询为兜底，只切换自己的状态。 |
| 锁定时展示 | [LockScreenManager.swift:142-147](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/LockScreenManager.swift#L142-L147) 分别调用媒体面板、刘海活动、天气与计时器管理器。 | 多个组件是独立的自有窗口，不是原生锁屏视图树的子视图。 |
| 解锁时清理 | [LockScreenManager.swift:204-210](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/LockScreenManager.swift#L204-L210) 隐藏上述窗口。 | 没有修改或恢复密码框的代码路径。 |
| 音乐面板窗口 | [LockScreenPanelManager.swift:127-174](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/LockScreenPanelManager.swift#L127-L174) 新建 `.borderless`、`.nonactivatingPanel` 的 `NSWindow`，设透明背景、`CGShieldingWindowLevel()`、跨空间行为，托管 `LockScreenMusicPanel`，最后 `delegateWindow` 并 `orderFrontRegardless()`。 | 播放器是独立叠加窗，不接触原生登录窗口。 |
| 音乐面板位置 | [LockScreenPanelManager.swift:357-376](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/LockScreenPanelManager.swift#L357-L376) 用 `screenFrame.midX`、屏幕高度和用户偏移计算 frame。 | 其“密码框上方”的视觉位置来自屏幕几何估算，不读取密码框 frame。 |
| 音乐面板内容 | [LockScreenMusicPanel.swift:30-35](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/components/LockScreen/LockScreenMusicPanel.swift#L30-L35) 给出 420×180 默认收起尺寸；[271-277](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/components/LockScreen/LockScreenMusicPanel.swift#L271-L277) 组合歌曲信息、进度条和播放控制。 | 可借鉴信息层级与交互目标，但需独立写 Zisla 视图。 |
| 天气窗口 | [LockScreenWeatherPanelManager.swift:93-116](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/LockScreenWeatherPanelManager.swift#L93-L116) 同样新建透明 `NSWindow`，设置 `ignoresMouseEvents = true`、窗口层级与 `delegateWindow`。 | 天气/电量等信息也是第二个自有叠加层，未触及认证界面。 |

## 为什么它能盖在锁屏之上

Atoll 的项目文件把 `SkyLightWindow` 作为 Swift Package 依赖：[project.pbxproj:792-798](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland.xcodeproj/project.pbxproj#L792-L798)。该包的 SwiftPM 产品和 target 均名为 `SkyLightWindow`：[Package.swift:6-16](https://github.com/Lakr233/SkyLightWindow/blob/main/Package.swift#L6-L16)。关键行为在该依赖的一手源码：

1. [SkyLightOperator.swift:53-58](https://github.com/Lakr233/SkyLightWindow/blob/main/Sources/SkyLightWindow/SkyLightOperator.swift#L53-L58) 使用 `dlopen` 和 `dlsym` 加载 `/System/Library/PrivateFrameworks/SkyLight.framework` 的 `SLS*` 符号。
2. [SkyLightOperator.swift:60-67](https://github.com/Lakr233/SkyLightWindow/blob/main/Sources/SkyLightWindow/SkyLightOperator.swift#L60-L67) 创建 space，并设为 `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`。
3. [SkyLightOperator.swift:70-76](https://github.com/Lakr233/SkyLightWindow/blob/main/Sources/SkyLightWindow/SkyLightOperator.swift#L70-L76) 的公开调用签名为 `public func delegateWindow(_ window: NSWindow)`；实现将独立 `NSWindow.windowNumber` 加入这个 space。

该库 README 也直接称它使用 private SkyLight APIs，并警告系统更新可能改变行为：[README:115-135](https://github.com/Lakr233/SkyLightWindow/blob/main/README.md#L115-L135)。Apple 的审核规则要求 App 使用公开 API：[App Store Review Guidelines 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)。所以这不是 App Store 或长期兼容的公开方案。

## 对 Zisla 的约束与建议

1. **保留系统认证界面。** 不搜索 `loginwindow`、`SecurityAgent`、Accessibility 密码控件，也不修改密码框；只管理 Zisla 自己创建的窗口。
2. **按功能分层，而非照抄 Atoll。** 独立重写锁定状态协调器、信息视图和媒体面板：时间上方放用户自定义短句/农历，时间下方放电量与天气，播放器作为用户自有窗口放在系统认证区域上方。数据层优先复用 Zisla 的现有电量、天气、农历与播放器服务。
3. **把私有路径做成明确的可选风险项。** 仅用 AppKit 可构建普通前台叠加窗，却不能保证锁屏可见；若要求与 Atoll 一样出现在真正锁屏页，必须采用等价的私有 SkyLight 技术或引入该 MIT 依赖，并接受 OS 更新、签名和审核风险。不要把这种行为描述为公开受支持功能。
4. **避免版权污染。** 可以根据上述“锁定事件 -> 自有窗口 -> 解锁隐藏”的事实独立设计；不得复用 Atoll 的类型、布局常量、源码、资源或其 GPL 依赖。
