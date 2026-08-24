# 新 macOS 工具机会复调研

日期：2026-08-22

## 结论先行

这轮复调研不再考虑以下三项：

1. **PDF 工具**：zisla 已经覆盖合并、拆分、旋转、裁剪、转换、渲染、文本导出、水印、页码、加密、解除密码和元数据编辑，继续拆成独立 App 的新增价值不足。
2. **AI 任务回执**：用户已经明确不需要。zisla 的 AI 模块目前展示活动任务、状态和会话入口即可，不应再增加一套“完成后生成回执”的流程。
3. **工作上下文胶囊**：此前设想的是保存项目分支、打开文件、网页、终端和 AI 会话入口，稍后一次性恢复。它更像跨应用自动化的包装，用户需要先维护上下文，隐私和恢复失败的边界也很复杂；本轮将其淘汰，不作为产品方向。

首选方向是 **Mac UI Regression Lab（暂名 Framecheck）**：面向原生 macOS App 的窗口、状态和视觉回归检查。它不是普通截图工具，也不是 AI 任务记录器，而是把“同一 App 在不同窗口尺寸、显示缩放和外观下是否仍然正确”变成可重复的本地检查。

第二选择是 **Release Evidence & Artifact Diff**：比较两版 `.app/.pkg/.dmg` 的语义变化，并保存签名、公证、架构和嵌套组件的可交接证据。它与 zisla 自己的发布流程高度相关，但使用频率和竞品压力都低于首选。

## 调研边界与方法

- 本地边界以 `README.zh-CN.md`、`mac/Package.swift`、AI/PDF 模块和发布文档为准。
- 外部事实优先采用 Apple、项目官方文档、官方仓库和官方产品页；代理只负责发散和交叉检查，主线程重新核对关键结论。
- 使用了 `agent-reach` 的 doctor、Exa、网页和 GitHub 路由，并在结束时运行 `agent-reach check-update`。当前版本为 v1.5.0，已是最新。
- 使用多个并行 subagents 分别调研开发者工具、会议/展示工具和 QA/UI 工具；Claude Opus 5 做了独立的 adversarial review。代理报告只作为线索，以下结论以列出的来源和本地代码为准。
- Twitter、Reddit、小红书和 V2EX 在本次环境没有可用后端；Exa 在后续查询触发免费额度限制，GitHub API 也出现限流。因此不能把本报告写成完整的社区需求或付费意愿验证。这里的“空位”和“痛点”是产品假设，不是销售数据。

## zisla 已覆盖的范围

`README.zh-CN.md` 描述 zisla 是一个顶部动态工作空间，已经包含媒体、文件中转、下载、剪贴板、语音、AI 活动、系统监控、日程、邮件、笔记和 PDF 等模块（[README.zh-CN.md](/Users/wzz/个人/code/zisla/README.zh-CN.md:5)、[README.zh-CN.md](/Users/wzz/个人/code/zisla/README.zh-CN.md:22)）。

实现层面，`Package.swift` 已链接 `PDFKit`、`ScreenCaptureKit`、`AVFoundation` 等框架（[Package.swift](/Users/wzz/个人/code/zisla/mac/Package.swift:34)），所以“再做一个 PDF 小工具”或“再做一个系统监视小组件”很容易变成复制已有代码，而不是独立产品。

目前发布流程还需要手动处理构建、签名、公证、DMG、校验和多架构验收（[releasing.zh-CN.md](/Users/wzz/个人/code/zisla/mac/Docs/releasing.zh-CN.md:48)）。这说明发布证据差分有真实 dogfood 场景，但不等于它天然有足够的外部市场。

## 候选一：Mac UI Regression Lab（首选）

### 用户任务

开发者把一个正在运行的 macOS App 选为目标，定义几个可复现的界面状态，例如“首页”“PDF 工具页”“录音中”“窄窗口”“深色模式”。工具在指定窗口尺寸和显示缩放下截取窗口，保存基线；下一次运行时重新截取并给出像素差异、叠加图和结构变化。

第一版不需要理解业务语义，也不承诺替代 XCUITest。它只承诺：**同一个本地 App 的同一个检查点，变化能被稳定地看见并导出。**

### 官方能力与边界（事实）

- Apple 的 `SCScreenshotManager` 支持从 ScreenCaptureKit 流中捕获单帧，`SCContentFilter` 可将目标限定到窗口或 App；相关 API 文档见 [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager) 和 [Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)。
- 读取和操作辅助功能树可使用 `AXUIElement`，监听变化可使用 `AXObserver`；是否允许访问目标进程由 `AXIsProcessTrustedWithOptions` 决定。该能力需要用户授予辅助功能权限。
- Apple 的 [Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector) 已能人工查看、查询和审计裁切文本、未标记元素、文字大小与对比度，但它是 Xcode Developer Tool，官方描述的流程是逐屏人工检查。
- `NSScreen` 能提供屏幕 frame、backing scale 和可见区域，足以把窗口截图按显示器/Retina 条件分组；它不代表工具可以可靠地替用户切换所有显示器分辨率。
- Playwright 的 [Visual comparisons](https://playwright.dev/docs/test-snapshots) 和 [Trace viewer](https://playwright.dev/docs/trace-viewer) 已把截图基线、diff 和失败追踪做好，但目标主要是浏览器/Web 测试；[Accessibility testing](https://playwright.dev/docs/accessibility-testing) 也明确自动审计只能发现部分问题。
- [guiport](https://guiport.dev/) 已提供跨平台桌面 App 的 AX 树、截图、选择器控制和 YAML 回放；[peek](https://github.com/alexmx/peek) 和 [Loupe](https://github.com/heoblitz/Loupe) 也覆盖了桌面树/截图/运行时观察。它们解决的是“看见和操作任意 App”，不是“维护多条件视觉基线并审阅回归”。

### 可形成的差异

产品边界必须写得很窄：

- **做**：窗口级基线、尺寸矩阵、浅色/深色基线、Retina 归一化、像素 diff、人工接受/拒绝、AX 树摘要 diff、HTML/JSON 报告。
- **不做**：通用录屏、AI 视觉评审、自动修复 UI、保证所有 App 都能被无权限控制、替代 Xcode 的单元/UI 测试。
- 对动态区域提供“遮罩/忽略区”和阈值，而不是用 AI 猜测“这应该没问题”。
- 对无法访问 AX 树的 Electron/Canvas App，只提供截图基线，并明确标注“无结构化树证据”。

### 两周 MVP

1. 选择运行中的 App/窗口，显示权限状态和可捕获区域。
2. 手动输入或读取当前窗口尺寸，保存一个检查点和 PNG 基线。
3. 再次捕获时做 Retina 归一化、像素 diff、叠加图和差异面积统计。
4. 追加 3 个固定尺寸 preset；窗口不能稳定调整时，允许用户手动调整后再采集，不假装有完整自动化。
5. 可选保存 AX 树中 role、label、frame 的摘要，提供结构变化提示。
6. 导出一个脱离 App 也能阅读的 HTML 报告和机器可读 JSON。

### 关键风险与杀死指标

- Screen Recording + Accessibility 两项授权会增加首次使用摩擦；guiport 的官方安装说明也要求这两项权限，且 [issue #4](https://github.com/edihasaj/guiport/issues/4) 记录了权限身份/升级稳定性问题。
- 原生 UI 的动画、时间、网络数据、字体渲染和系统外观会制造误报。目标不是“零差异”，而是让差异可解释。
- **两周止损条件**：用 5 个真实 macOS App，每个至少连续跑 3 次；在固定 fixture 下 false positive 超过 10%，或超过 1 分钟仍无法从报告定位变化，停止做“任意 App”承诺，缩窄为“自家 SwiftUI/AppKit App + CLI hook”。

### 为什么值得做成独立 App

它需要一个持续可见的检查列表、基线浏览器、差异审阅器和导出流程；把它塞入 zisla 顶部岛会失去对比空间和状态历史。它也能直接用于 zisla 自己的窗口、PDF 模块和 Liquid Glass 状态，是可立即 dogfood 的方向。

## 候选二：Release Evidence & Artifact Diff

### 用户任务

拖入旧版与候选版 `.app`，或拖入 `.pkg/.dmg`，工具生成一份“这次发布到底变了什么”的报告：Bundle tree、版本/构建号、架构 slice、最低系统版本、Team ID、签名、Hardened Runtime、entitlements、嵌套 helper/framework、资源哈希和公证/staple 状态。签名时间、压缩噪声等不会导致运行时变化的差异应与高风险差异分开。

### 事实与竞品

- Apple 提供 `SecStaticCodeCheckValidity`（可检查所有架构）和 `SecCodeCopySigningInformation` 读取签名信息；公证常见失败项包括嵌套代码、Developer ID、secure timestamp、Hardened Runtime、entitlements 和 stapling，见 [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues) 和 [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
- [Apparency](https://www.mothersruin.com/software/Apparency/) 已覆盖单个 App 的 Gatekeeper、签名、公证、sandbox、entitlements 和组件检查；[Suspicious Package](https://www.mothersruin.com/software/SuspiciousPackage/) 已覆盖 PKG 的 payload、脚本、receipts、签名和公证信息。
- [Signaro](https://github.com/hov172/Signaro) 已覆盖签名、公证、staple、entitlement diff 和分发流程；[diffoscope](https://diffoscope.org/) 能递归比较目录和归档；因此“把 `codesign` 做成 GUI”或“再做一个 PKG 浏览器”没有足够差异。

### 仍可能存在的窄空位

跨 `.app/.pkg/.dmg` 的**版本间语义差分 + 不可变发布证据包**仍可作为一个小而明确的产品假设，但目前没有销售验证。它的卖点不能写成“市场上没有签名工具”，只能写成“把两次发布验收结果放在同一张可审阅、可交接的时间线上”。

### 两周 MVP 与止损条件

- 第 1 周：拖入 old/new `.app`，输出 bundle tree、Mach-O 架构、Info.plist、entitlements、签名和文件大小 diff。
- 第 2 周：加入 `.pkg/.dmg` 外层元数据、`spctl`/`stapler`/`pkgutil` 结果收集和 CI JSON/HTML 导出。
- **止损条件**：10 对真实发布产物中，报告无法发现 `diffoscope` 加 Apple CLI 已经能发现不了的 actionable 差异；或目标用户每月复用少于 2 次，则转为 CLI/CI 插件，不做独立窗口 App。

## 候选三与淘汰项

### 原生窗口尺寸矩阵（作为候选一的附加能力）

`NSScreen` 和辅助功能窗口 frame 能支持预设尺寸采集。它是 macOS 原生 App 的真实痛点，但单独做成 App 市场太窄；应作为 UI Regression Lab 的“尺寸矩阵”功能，而不是独立品牌。

### 崩溃证据库（不作为首发）

Apple 的 [build debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)、[missing debug symbol file](https://developer.apple.com/documentation/xcode/locating-a-missing-debug-symbol-file) 和 [identifiable symbol names](https://developer.apple.com/documentation/xcode/adding-identifiable-symbol-names-to-a-crash-report) 文档要求保留对应 build 的 archive/dSYM，并以 UUID 匹配符号；但现有工具已经覆盖“拖入报告并符号化”：[Xsymbolicate](https://furnacecreek.org/xsymbolicate/) 可自动从 Xcode Archives 查找符号，[MacSymbolicator](https://github.com/inket/MacSymbolicator) 支持 `.crash/.ips`、sample、spindump 和 hang，[SYM](https://github.com/zqqf16/SYM) 也支持从本地/Xcode Archives 找 dSYM。若以后做，只能做“发布证据库与缺失 dSYM 预警”，不能做普通 symbolicator。

### 会议设备体检（暂不做）

Zoom 和 Teams 各自提供麦克风、扬声器和摄像头测试；SoundSource 已做按 App 音频路由。跨会议软件统一保存“耳机会议/桌面演示”配置有一定价值，但使用频率低、蓝牙重连后的状态也难以保证，先不作为首发。

### 其他明确淘汰

- 泛发布预检/签名查看器：Apparency、Signaro、Apple CLI 已覆盖基础能力。
- Sparkle 专用验证器：Sparkle 官方已有 `generate_appcast`、签名和 feed 校验。
- Xcode 环境 Doctor：适合 CLI，不足以支撑独立窗口 App 的高频使用。
- 全局麦克风/摄像头急停、演示者叠层：macOS 或 MutexCam 等已有方案覆盖。
- 安装后副作用监控：需要 Endpoint Security/完全磁盘访问或隔离 VM，权限和实现风险不适合两周 MVP。

## 推荐决策

建议先做 **Mac UI Regression Lab / Framecheck** 的可验证原型，而不是立刻承诺完整产品：

1. 先只支持“选择一个窗口 → 采集一个基线 → 再采集一次 → 给出可解释 diff”。
2. 用 zisla 自己的 PDF、AI 监控和录音界面做 fixture，覆盖窗口尺寸、深色模式和动态区域遮罩。
3. 通过 5 个真实 App 的三轮重复测试验证误报率，再决定是否加入 AX 树和 CLI/CI 接入。
4. 若权限或误报使止损指标失败，就把范围缩窄到“SwiftUI/AppKit 开发者的本地回归审阅器”，不要继续扩张成任意桌面自动化平台。

## 证据限制

本报告能证明 Apple API 的能力、竞品公开宣称的功能和本地 zisla 的现有边界，不能证明付费意愿、市场规模或竞品真实活跃用户数。后续若进入实现，第一步应是用上述 MVP 做可运行 demo，再找 5 名原生 macOS 开发者实际跑 fixture，而不是继续堆更多功能。
