# Windows 架构与产品约束

## 技术基线

- C++20
- C++/WinRT + WinUI 3 + Windows App SDK
- Windows 11
- 带包身份的 MSIX
- UI 线程只负责窗口、输入、布局和渲染；文件、网络、解析和媒体处理在后台执行

## 选型结论

“占用最小、性能最高、界面最美观”不是同一个框架可以同时达到的三个极值。本项目采用 **Win32 外壳 + WinUI 3 内容 + C++20 Core**，理由如下：

| 方案 | 优点 | 主要代价 | 结论 |
| --- | --- | --- | --- |
| 纯 Win32 + Direct2D/DirectComposition | 常驻开销和渲染链路最可控 | 控件、无障碍、主题、文本输入和设置页需要自行维护 | 只作为后续性能兜底，不作为首版 UI |
| WPF/.NET | 开发效率高、控件成熟 | 运行时和内存基线更重，Windows 11 材质与原生窗口互操作不如 WinUI 直接 | 不选 |
| Qt/Avalonia/Flutter/Electron | 跨平台或生态完整 | 额外渲染/运行时层，托盘、DPI、系统媒体和 MSIX 细节仍需平台适配 | 不选 |
| **WinUI 3 + C++/WinRT** | Windows 11 原生控件、Acrylic/Mica、输入和辅助功能完整；C++ 可复用 Core | Windows App SDK 带来固定运行时依赖，部分 HWND 互操作仍需 Win32 | **首版采用** |

Win32 负责消息窗口、托盘、顶部鼠标触发、窗口样式和系统 API；WinUI 3 只负责可见内容与交互。这样隐藏态可以真正隐藏窗口、不保留透明热区，也能在需要时使用原生 Acrylic/Mica。只有 Windows 实机性能数据证明 XAML 合成成为瓶颈时，才把局部绘制替换为 DirectComposition；不在首版提前引入第二套渲染树。

Windows App SDK 发布先采用带包身份的框架依赖 MSIX，以降低应用自身包体；离线分发或目标机没有运行时时，再评估自包含 MSIX 的体积、内存和更新成本。

## 产品形态

- **正式入口**：通知区域图标及其相邻弹出卡片；悬停显示不激活的 Peek，点击进入可交互状态。Windows 没有公开 API 允许第三方占据天气/Widgets 槽位或插入系统按钮之间，因此不注入 Explorer，也不靠坐标遮盖系统控件。
- **顶部入口**：屏幕顶部中央约 6 px 的无窗口感应区，鼠标悬停后从工作区内向下展开；按下鼠标拖动经过时忽略，避免干扰 Snap Layout。
- **卡片**：peek 使用约 `420 × 96 DIP` 的白色或浅灰白单层 Acrylic 卡片，8 px 圆角和 1 px 半透明描边；点击后进入约 `480 × 420 DIP` 的 interactive 状态。托盘触发按任务栏方向向上或向侧面展开。
- **材质**：Windows 的 Desktop Acrylic/Mica 是可用的系统材质，但不等同于 Apple Liquid Glass。透明度关闭、旧 GPU 或高对比度模式下回退到实体主题色，并保持相同几何和信息层级。

## 模块

`zisla_windows_core` 是深模块，其公开接口只表达展示动作、效果和物理像素几何，不暴露 HWND、XAML、COM 或 Windows 类型。可移植实现不包含 Windows 头文件；Windows 文件原子替换收敛在私有平台适配器中，Clang 与 MSVC 复用同一套公开接口和行为测试。

首页通过 `DashboardPresentation` 统一活动顺序，平台适配器只提交可用快照；专注计时、AI、原生下载和浏览器下载沿用 macOS 顺序，Windows 的系统正在播放作为附加活动排在其后。

Windows 外壳负责以下适配器：

- `TopEdgeTrigger`：仅在用户开启时由主消息窗口每 100 ms 采样光标位置，按每显示器物理像素几何判断顶部触发区；不安装全局鼠标 Hook，也不拦截输入。
- `TrayTrigger`：`Shell_NotifyIcon`、`Shell_NotifyIconGetRect`、悬停进入/离开事件和重启 Explorer 后的图标恢复。
- `OverlayHost`：WinUI 内容、`AppWindow` 与必要的 HWND 样式互操作。
- `DisplayTopology`：每显示器 DPI、工作区、负坐标和显示器热插拔。
- `AIStateMonitor`：监听不受包重定向影响的 `%LOCALAPPDATA%\zisla` SQLite/WAL 变化，只在 change token 改变时后台加载，并与本地探测任务合并后投递 UI 消息。
- `MediaSessionMonitor`：在 MTA 后台线程订阅 GSMTC 会话，读取元数据和封面、执行播放控制，并以不可变 Core 快照投递 UI 消息。
- `BrowserDownloadService`：只读枚举受支持 Chromium 浏览器的 History SQLite，按 profile 与下载 id 追踪进行中到完成的状态转移，以不可变快照投递 UI 消息；不联网、不读取网页内容，数据库锁定时保留上一次可用状态。
- `FileShelfService`：在串行后台线程维护独立 SQLite 文件中转仓库，完成路径检查后以不可变快照投递 UI 消息。
- `QuickNotesService`：在串行后台线程维护本地 Markdown/SQLite 随记，限制单条内容为 1 MiB，并以不可变快照驱动列表、选择和保存状态；UI 线程只负责 0.8 秒防抖与编辑控件。
- `MailService`：单后台线程执行显式配置的 Microsoft Graph Device Code Flow、令牌刷新和收件箱/邮件命令；租户、Client ID 与显示名可保存在应用设置中，访问令牌和刷新令牌只保存在 Windows Credential Manager，绝不写入 `LocalSettings`、日志或 UI 快照。
- `UpdateService`：单后台线程按 Release/Preview 通道检查固定的 Gitee 首选、GitHub 回退发布端点；它只发布不可变检查结果。安装入口由外壳交给 `.appinstaller` 或发布页，应用不在进程内下载、替换或执行更新包。
- `SideNoticeHost`：两个不激活的 Acrylic 工具窗口承载左右活动通知，按通知到达时指针所在显示器定位。
- `CleaningHost`：屏幕清洁为每显示器实体黑色顶层窗口；键盘清洁只处理自身前台 WinUI 窗口收到的按键，并始终保留鼠标退出路径。
- `TeleprompterHost`：独立顶层 WinUI 工具窗口承载阅读面与控制栏，滚动状态由纯 C++ 时间状态机驱动，脚本和速度保存在应用本地目录。
- `CameraMirrorHost`：独立顶层 WinUI 工具窗口通过 `MediaCapture` 选择彩色视频源，由 `MediaPlayerElement` 显示横向镜像预览；异步代次阻止关闭后的旧初始化结果重新占用摄像头。
- `WeatherService`：单后台线程串行执行 WinHTTP 请求，合并待处理命令并用代次拒绝旧结果；定位只在需要当前位置时从 UI STA 请求，地点文件通过平台适配器原子替换。
- `SystemMonitorService`：只在系统页可见且可交互时，以 1.5 秒间隔采集 CPU、GPU、内存、磁盘、网络、电池和运行时间；读取失败保持显式不可用状态，温度与风扇不伪造数据。
- `DiskCleanupService`：串行扫描限定的用户临时目录、崩溃报告和 Zisla 缓存/日志；候选必须超过保留期限并由用户逐项确认，只通过 `IFileOperation` 移入回收站，重解析点和根目录永不进入清理操作。
- `DesktopToolsService`：串行执行 Explorer 自动排列、回收站统计/清空、Store 更新入口和 Zisla 自身工作集回收；不调用或宣传不存在的“全系统内存整理”接口。
- `StartupTask`：只以 MSIX Manifest 声明和系统状态为准；设置页不复制一份本地开关，并在用户或策略禁用时禁止伪造启用状态。
- `PetHost`：独立的透明分层工具窗口按任务栏伴随锚点定位，WIC 只加载随包资源，最终 PBGRA 画布同时用于显示和 Alpha 命中测试；AI 活动只通过 Core 的宠物状态接口驱动行为。
- `FeatureAdapters`：媒体、剪贴板、文件、AI、天气等 Windows 能力。

所有触发源复用一个浮层窗口和一棵 WinUI 视觉树。隐藏时窗口真正隐藏，不保留覆盖屏幕边缘的透明热区，也不运行帧循环。

顶部触发只接受没有按下鼠标按钮的移动事件。拖动窗口进入屏幕顶边时按离开热区处理，避免与 Windows Snap Layout 争抢交互。

## 展示状态

```text
hidden -> peek -> interactive
                 ^        |
                 +-- pin -+
```

- `peek` 使用不激活的工具窗口，不抢走当前应用焦点。
- 用户明确点击后进入 `interactive`，允许键盘、Narrator 和输入控件工作。
- 指针离开后延迟隐藏；固定、拖拽或临时交互期间拒绝过期的隐藏请求。
- 托盘悬停时卡片从通知图标向工作区展开，离开后延迟隐藏；点击后在同一锚点提升为可交互状态。顶部热区触发时向下展开。

侧边通知每侧最多保留 3 条普通通知，默认显示 6 秒；悬停期间暂停计时，离开后保留 3 秒。折叠状态不占普通通知容量，持久通知只接受显式关闭。主浮层或设置窗口可见、前台窗口覆盖整块显示器，或系统不接受自定义通知时，侧边窗口隐藏但队列状态保留。

## 计时与系统通知

番茄钟只在运行期间使用消息窗口定时器，暂停和空闲时不轮询。完成后发送普通 App Notification；设置中的通知静音会同时屏蔽番茄钟系统通知与侧边通知。

闹钟先原子替换 SQLite 数据，再更新内存和 Windows 计划通知。一次性闹钟保存绝对触发时间；重复闹钟按本地星期和时间生成后续 32 次投递，64 条闹钟最坏为 2048 条，低于 Windows 每应用 4096 条计划通知上限。应用启动、系统时间变化和睡眠自动恢复时重新计算，通知点击按参数进入闹钟或番茄钟界面。闹钟不受普通通知静音开关影响。

Windows 对计划通知只提供 5 分钟投递窗口。设备错过触发超过 5 分钟时系统会丢弃该次通知；Zisla 在窗口结束后停用一次性闹钟，不承诺超过平台窗口的补发。DST、时区切换、声音循环和批量重排成本必须在 Windows 实机验证。

## 视觉系统

- 短暂浮层只使用一层 Desktop Acrylic。
- 设置窗口使用 Mica。
- 卡片使用 8 px 圆角、1 px 主题感知半透明描边和克制阴影。
- 默认表面为白色或浅灰白；同时支持深色、高对比度和系统关闭透明度的实体背景回退，并在 Windows 设置、主题或 DWM 合成变化时重新应用材质。
- 不复制黑色灵动岛，不使用多层 Blur/Acrylic，不把 Acrylic 称为 Liquid Glass。
- 颜色、描边和回退色集中在 WinUI ResourceDictionary，避免散落硬编码。

## 任务栏边界

受支持的正式入口是通知区域图标与其相邻弹窗。系统允许应用添加图标、接收鼠标事件并读取图标矩形，但图标是否常显及其顺序由用户和 Shell 决定。

Windows 没有公开接口让第三方应用占据天气按钮槽位，或精确插入天气、快速设置、时钟等系统按钮之间。实机阶段可以只读探索公开的 Widget 和 Shell 能力；正式实现不得注入 `explorer.exe`、覆写系统按钮、使用未文档化任务栏子窗口、读取私有布局注册表，或通过坐标遮盖系统控件。任务栏伴随入口因此只作为通知区域一侧、任务栏外侧的独立顶层浮窗：优先用 `Shell_NotifyIconGetRect` 读取 Zisla 自己的托盘图标，再把入口锚定在该图标左侧的工作区内；读取失败时退回工作区末端。多显示器时以图标所在显示器为准：主任务栏继续使用公开的 `SHAppBarMessage` 矩形，无法取得对应矩形的屏幕仅按图标边缘和 `MONITORINFO.rcWork` 推断锚点，绝不探测私有 Shell 窗口。底部任务栏向上展开，顶部或侧边任务栏向工作区一侧展开；无法放下完整入口时直接隐藏，托盘入口仍可用。

## 清洁模式边界

屏幕清洁覆盖当前枚举到的全部显示器物理边界，显示器拓扑变化时整体重建窗口集合。任何清洁窗口都提供鼠标点击退出，避免只能依赖正在被清洁的键盘。

键盘清洁不安装全局低级键盘 Hook，也不试图绕过 Windows 安全输入路径。它只能吞掉自身清洁窗口拥有前台焦点时收到的普通按键；`Ctrl+Alt+Delete`、Windows 保留快捷键、切换到其他应用后的输入和外接设备策略不在承诺范围内。

## 摄像头镜子边界

镜子只声明 `webcam` 能力，不请求麦克风。初始化从 UI STA 发起，优先使用彩色 `VideoPreview` 流并回退到 `VideoRecord` 流；拒绝、系统限制、无设备和配置失败分别呈现。关闭或重试时先从 XAML 脱离播放器，再关闭 `MediaPlayer` 和 `MediaCapture`，避免摄像头继续被占用。

## 依赖与发布

- 第三方依赖必须固定版本、来源、许可证和校验值，优先仓库内 Vendor。
- 不使用浮动 Git 分支或启动时下载库。
- Windows App SDK 项目固定稳定版本；发布前验证框架依赖与自包含 MSIX 的磁盘、内存和更新取舍。
- 应用更新与开发库更新分离：应用可通过签名 MSIX/App Installer 或商店更新，但不能借此改变未审计的第三方库版本。

## 验证分层

1. macOS：Clang 严格警告下验证纯 C++20 核心。
2. Windows：MSVC 严格警告、C++/WinRT 编译、打包和单元测试。
3. Windows 运行态：真实顶层窗口、托盘点击、顶部悬停、多屏 DPI、Explorer 重启、全屏、浅色、深色、高对比度和关闭透明度。
4. 性能：隐藏态 CPU、私有工作集、冷启动、悬停到首帧、掉帧和 GPU 合成，全部以实测报告为准。
