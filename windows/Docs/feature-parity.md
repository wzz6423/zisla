# Windows 功能对齐清单

本清单定义 Windows 版本的完整范围。`计划` 不代表已完成；只有代码、测试和 Windows 实机证据齐全后才能改为 `完成`。

| 能力 | Windows 实现方向 | 当前状态 |
| --- | --- | --- |
| 顶部中央悬停 | 启用时低频光标采样 + 每显示器物理像素几何 + 单一无边框浮层 | 已实现，待 Windows 实机验证 |
| 托盘入口 | `Shell_NotifyIcon` + `Shell_NotifyIconGetRect`，悬停展示 Peek、点击提升为同一交互浮层 | 已实现，待 Windows 实机验证 |
| 天气按钮槽位 | 无公开第三方占位接口；不得注入或遮盖 Explorer | 平台不支持；任务栏伴随入口用 Zisla 自己的托盘图标矩形锚定在通知区域一侧的任务栏外侧，不读取私有布局注册表，无法安全放置时隐藏 |
| 白色 Acrylic 浮层 | WinUI 3 Desktop Acrylic，8 px 圆角、单层材质、实体回退 | 已实现，待 Windows 实机验证 |
| Mica 设置窗口 | WinUI 3 Mica + `NavigationView` 设置壳 | 已实现，待 Windows 实机验证 |
| 主页聚合 | 各功能快照汇总，共用紧凑卡片布局 | Core 排序模型与专注计时、AI、系统正在播放、媒体下载、浏览器下载聚合已接线，待 Windows 实机验证 |
| 系统正在播放 | Global System Media Transport Controls，多会话选择、封面、进度与公开播放控制 | Core 行为与 WinUI/GSMTC 接线已实现，待 Windows 编译、播放器兼容性和实机交互验证 |
| 文件中转与分享 | OLE 拖放、文件系统、Explorer 定位、Windows 分享界面 | Core 仓库、后台队列和 WinUI 操作已接线，待 Windows MSBuild/XAML、Explorer/应用拖放兼容性及 Share Sheet 生命周期实机验证 |
| 剪贴板历史与链接检测 | `AddClipboardFormatListener`、本地 SQLite、默认关闭 | Core、Win32 采集、WinUI 管理与链接提示已接线，待 Windows MSBuild/XAML、剪贴板格式兼容性及实机交互验证 |
| AI 活动监控 | `ReadDirectoryChangesW`、有界 JSONL/JSON 解析、SQLite 用量历史 | Codex、Claude、Gemini、Grok CLI、Harnext、Kimi Code、Qwen Code、Copilot、Qoder、豆包与 OpenCode 的扫描、SQLite 持久化、目录监听、任务合并与浮层展示已接线。新增 Provider 复用多目录监视器：Copilot 读取 VS Code/Cursor 会话和 CLI 状态，Qoder 读取 CLI/桌面日志，豆包仅在进程存活且近期本地数据变化时报告，OpenCode 优先只读 SQLite 并以受限 JSON storage 回退。所有扫描只保留显示所需元数据，不保留 prompt/response；Qwen runtime sidecar 仅在 PID 存活时生效。跨平台 Core UT 已覆盖新增四个扫描器的正常、错误和边界路径；均待 Windows 实机验证目录布局、进程名、SQLite WAL 与监听结果 |
| AI Agent | WinHTTP/本地 CLI、Windows Credential Manager、工作区与技能同步 | OpenAI-compatible、Anthropic Messages、Gemini generateContent 三种协议，账户、CLI 配置引用、端点分组、优先级/余额/冷却筛选、模型目录和稳定轮转的 C++20 Core 已实现；`ai-agent-routing.sqlite` 以事务保存元数据、探测和模型目录，绝不保存 API Key 或 CLI 内容。工作区的 `/plan`、`/goal`、`/skill` 输入解析、SQLite 持久化、后台串行服务、WinUI 会话页以及新建/删除会话和本地消息保存已接线。路由规划会从会话历史、计划/目标模式生成非流式请求；WinHTTP 适配器会限制为 HTTPS 或本机 loopback HTTP、30 秒超时、4 MiB 请求/响应上限、禁用重定向且不记录密钥或请求正文。会话页已提供渠道名、协议、Base URL、模型、模型目录、余额探测和 `PasswordBox` 密钥配置；密钥只写入 Windows Credential Manager，渠道元数据写入 SQLite，成功请求会追加 assistant 消息，失败会记录路由失败并保留用户消息。Claude、Codex、Gemini、Grok 和 OpenCode 官方 CLI 已支持固定 argv、标准输入转发、最近 32 条/4 MiB 上下文限制、4 MiB 输出限制和 Job Object 子进程树取消；UI 可按会话选择 API 或本机 CLI。Core UT 已覆盖协议序列化/解析、余额和模型目录响应、CLI 参数、线程隔离、上下文限额和输出边界；新增 WinHTTP、Credential Manager、CLI、WinUI/XAML、MSIX 与真实渠道回复均待 Windows 实机验证 |
| 视频与音频下载 | 固定版本 `yt-dlp`、安全 argv、Media Foundation 封装、B 站备用路径 | 固定 `2026.06.09` x64/ARM64 资产、安全进程组取消、流式临时文件、H.264/AAC 原生 MP4 封装和 B 站 HTTPS 备用路径已接线；待 Windows MSBuild、真实媒体轨道和网络风控场景实机验证 |
| 天气与预警 | Windows 定位、Open-Meteo、中国天气网与 NWS 官方预警、多地点 | Core 解析与地点仓库、WinHTTP 后台服务、定位、设置开关、首页/Peek/日程展示、搜索刷新和删除已接线；待 Windows MSBuild/XAML、定位权限、系统代理、真实网络与浅色/深色/高对比度实机验证 |
| 日历与待办 | 本地 SQLite 提供稳定基础能力；Windows Appointment/UserDataTasks 或可选 Microsoft Graph 用于系统数据适配 | 本地周视图、新建日程/待办、完成待办和删除已接线；待 Windows MSBuild/XAML、时区/DST 和系统日历能力实机定界 |
| 邮件 | Microsoft Graph Device Code Flow；不假设可读取任意系统邮件客户端 | Core 请求/响应与 OAuth 解析、WinHTTP 后台服务、Credential Manager 令牌存储、设置页显式租户/Client ID 配置，以及浮层中的收件箱、发送、回复、已读、垃圾邮件和删除操作已接线；待 Windows MSBuild/XAML、Microsoft Entra 配置、授权取消/超时、网络失败、真实收发和 Credential Manager 生命周期实机验证 |
| 随记 | 本地 Markdown + SQLite；可选 OneNote/Graph，不能复用 Apple Notes 自动化 | Core 仓库、后台队列和 WinUI 列表/搜索/编辑/新建/删除/复制/提词器联动已接线，支持 0.8 秒自动保存和一次性欢迎随记；待 Windows MSBuild/XAML、输入法、键盘、Narrator、高对比度及退出冲刷实机验证。Apple Notes 富文本、锁定笔记和附件属于平台专属能力，不伪造兼容 |
| PDF 工具 | 固定版本、许可证兼容的 PDF 引擎，覆盖合并、拆分、旋转、水印、页码、裁剪、加解密、元数据与文本提取 | QPDF 负责结构/加密，PDFium 153.0.7988.0 负责渲染/文字/页面绘制，LibreOffice 只调用用户本机安装；x64/ARM64 PDFium DLL、导入库、许可证、归档校验和 MSBuild/MSIX 打包接线已固定。WinUI 支持 PDF、图片和 Office 的输入选择、文字导出、PNG/JPEG 渲染、图片转 PDF、文字/图片水印、页码和 Office 转 PDF；C++ UT 覆盖适配器与服务分派。仍待 Windows MSVC/XAML/MSIX、中文字体、真实 Office、加密/损坏/非 ASCII 文档和输出目录实机验证，详见 `Docs/pdf-engine-audit.md` |
| 番茄钟与闹钟 | `std::chrono`/系统计时器 + Windows 通知 | 番茄钟 Core、动态 `WM_TIMER`、时长持久化、小工具/首页/顶部摘要、侧边通知和 App Notification 已接线；闹钟 Core、SQLite、WinUI CRUD、一次性/重复排程、时间变化/睡眠恢复重排及通知动作分流已接线，待 Windows MSBuild/XAML、5 分钟投递窗口、DST、声音循环和实机通知验证 |
| 保持亮屏与防休眠 | Power Request 公共接口 | Core 引用与失败回滚、`PowerCreateRequest` 后端及小工具双开关已接线，待 Windows MSBuild、Modern Standby/传统睡眠、电池供电、合盖与用户主动睡眠边界实机验证 |
| 屏幕/键盘清洁 | 全屏清洁界面；只在自身窗口内安全吞键，不做系统级永久输入阻断 | Core 互斥状态机、每显示器屏幕清洁窗口、前台键盘清洁窗口、鼠标退出、显示器变化重建及清洁期间电源状态保存/恢复已接线，待 Windows MSBuild/XAML、多显示器、任务栏覆盖、焦点与按键边界实机验证 |
| 提词器与摄像头镜子 | 独立 WinUI 工具窗口 + MediaCapture | 提词器 Core 状态机、脚本与速度持久化、WinUI 阅读面和自动滚动已接线；镜子异步状态机、`webcam` 能力、MediaCapture/MediaPlayerElement 横向镜像预览、权限与失败界面、停止释放已接线；待 Windows MSBuild/XAML、权限、预览、指示灯生命周期和多显示器实机验证 |
| 回收站与桌面整理 | Shell 文件操作，危险操作必须确认并报告恢复边界 | 回收站统计与确认清空、Explorer 自动排列及 Store 更新入口已接线；待 Windows MSBuild、Explorer 版本兼容性和实机验证 |
| 系统监控 | PDH、IP Helper、DXGI、存储与公开传感器；无公开风扇数据时显示不可用 | CPU/GPU、内存、磁盘容量与吞吐、网络速率与地址、电池、运行时间、历史曲线和显式不可用状态已接线；磁盘清理支持受限目录、保留期限、逐项勾选和移入回收站，并拒绝重解析点；内存操作只通过公开 API 释放 Zisla 自身工作集，不声称整理全系统内存；待 Windows MSBuild、PDH、Shell 长路径和实机读数验证 |
| 锁屏信息覆盖 | Windows 不允许普通桌面应用在安全锁屏上任意覆盖 | 平台不支持 |
| 桌宠 | 透明工具窗口、精灵图、事件驱动行为 | Core 状态优先级、点击反馈、资源清单校验、任务栏伴随定位、16 套内置素材、设置持久化和透明分层窗口已接线；待 Windows MSVC/WIC、Alpha 命中测试、混合 DPI、动画偏好和 GDI 生命周期实机验证 |
| 侧边活动通知 | 左右 Acrylic 浮层队列；用户明确设置的闹钟和番茄钟使用 Windows App Notifications | Core 队列、SQLite 原子消费、WinUI 双侧窗和设置接线已实现；AI 活动、任务终态、媒体、下载和外部 `zislactl` 消息均走侧边浮层，闹钟与番茄钟已接入 App Notifications。当前实现与 macOS 的通知边界一致；待 Windows MSBuild/XAML、通知权限和实机投递验证 |
| 浏览器下载状态 | 只读受支持 Chromium 浏览器本地 History 的下载状态，不读取网页内容、不联网 | Windows 路径发现、只读 SQLite 轮询、进行中聚合、完成状态转移通知和设置开关已接线；待 Windows 实机确认浏览器锁库、Opera/Arc 路径、Schema 兼容性和浅色/深色展示 |
| 语音输入 | Windows SpeechRecognizer 听写、麦克风权限、可选全局快捷键与 AI 后处理 | Core 状态机、连续识别适配器、实时文本、3 秒最终化、剪贴板交付、设置 opt-in、`microphone` capability、RegisterHotKey + MOD_NOREPEAT、Raw Input key-up、toggle/push-to-talk 双模式、Ctrl+Alt+V/Space/R 预设、注册状态反馈和设置持久化已接线；按住说话会在启动前松键时取消，Raw Input 注册失败会撤销热键；待 Windows MSVC/XAML、语言包、授权、设备切换和真实转写质量实机验证 |
| 快捷键与开机启动 | `RegisterHotKey` + MSIX StartupTask | MSIX StartupTask Manifest、状态查询、设置开关、用户禁用/策略禁用提示和系统设置入口已接线；全局快捷键默认 `Ctrl+Alt+V`，可选 `Ctrl+Alt+Space`、`Ctrl+Alt+R`，待 Windows 部署、快捷键冲突、输入法及登录启动实机验证 |
| `zislactl` | C++ 命令行程序，共用 AI 状态数据库协议 | 命令、退出码、SQLite 协议与 MSVC target 已实现，待 Windows UTF-8 控制台、打包和实机验证 |
| 自动更新 | 签名 MSIX/App Installer 或 Microsoft Store，Release/Preview 分通道 | Core Release/Preview 选择、Gitee 优先/GitHub 回退解析、Windows 后台检查服务和设置页通道/检查/打开更新入口已接线；发现更新后只打开 `.appinstaller` 资产或发布页，不在应用内下载或安装未验证包。待签名、发布源、MSIX/App Installer、商店策略和 Windows 实机更新回归验证 |
| 桌面与全屏兼容 | 多显示器、每显示器 DPI、虚拟桌面、普通全屏；独占全屏不承诺覆盖 | 多显示器物理坐标、负坐标、任务栏方向、DPI 缩放、显示器热插拔和普通/跨屏全屏抑制已接线；待 Windows 实机验证虚拟桌面归属、自动隐藏任务栏、独占全屏和混合 DPI |

## 完成证据

每一行改为 `完成` 前至少需要：

1. 对应实现文件和公开接口测试。
2. Windows 11 上实际构建并启动。
3. 该功能的正常、拒绝权限、无数据和失败路径验证。
4. 隐私、权限、依赖许可证及打包检查。
5. 测试生成的 binary、构建目录和临时下载已清理。
