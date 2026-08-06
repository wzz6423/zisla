# zisla for Windows

Windows 版本使用 C++20、C++/WinRT、WinUI 3 和 Windows App SDK。平台外壳保持 Windows 原生，业务规则与屏幕几何放在不依赖 WinRT 的 `Core` 静态库中，以便在 macOS 上先编写并验证。

## 当前阶段

- 已建立跨 Clang/MSVC 的 C++20 核心工程。
- 已实现单一 WinUI 浮层、顶部热区、通知区域悬停/点击入口以及 Acrylic/Mica 视觉骨架。
- Core 已覆盖展示状态、屏幕几何、功能目录、番茄钟状态机，以及 Codex rollout 的受限扫描、结构化活动解析和展示排序。
- AI Agent Core 已覆盖路由元数据、Credential Manager 引用和技能扫描/受管同步；Skills 后台模块和 WinUI 管理页已接线，默认以文件复制同步到用户目录下的受管目标。同步只管理 Zisla 标记的目标目录，文件复制不会跟随符号链接，也不会将同步副本重复列入扫描结果。Windows 实机仍需验证凭据、符号链接权限、MSVC/XAML 和实际同步结果。
- AI 状态使用固定版本 SQLite 3.53.4，支持任务、用量、外部通知、消息通知和跨进程 change token；Core 与 macOS 使用相同表结构和时间协议。
- `zislactl` 已实现 `update/finish/remove/clear/list/usage/notify/message/help` 的解析、退出码与持久化，并已加入 CMake、MSVC 和 solution 工程。
- Codex、AI 状态、Claude 项目目录、Gemini CLI 的 `~/.gemini/tmp`、Grok CLI 的 `~/.grok/sessions`、Harnext 的 `~/.harnext`、Kimi Code 的 `KIMI_CODE_HOME/sessions`、Qwen Code 的 `${QWEN_RUNTIME_DIR:-${QWEN_HOME:-~/.qwen}}/projects`，以及 Copilot、Qoder、豆包、OpenCode 的受限本地状态均已接线。新增四者复用一个多目录 `ReadDirectoryChangesW` 监视器，在 UI 线程通过 `AIActivityMerger` 合并后更新 Peek 摘要和任务列表；Copilot 读取 VS Code/Cursor 会话与 CLI 状态，Qoder 读取 CLI/桌面日志，豆包只在进程存活且近期本地数据变化时报告，OpenCode 优先读取 SQLite 并以受限 JSON storage 回退。所有扫描都只保留展示所需元数据，不保留 prompt 或 response；Windows 实机仍需验证目录布局、进程名和监听结果。
- 系统正在播放使用 GSMTC 后台监视器，支持多会话选择、封面、时间轴、播放/暂停、上一首、下一首与 seek；可移植选择和合并规则由 Core 测试覆盖。
- 首页活动聚合已接入专注计时、AI 任务、系统正在播放、媒体下载和浏览器下载，使用可扩展的 Core 排序模型；浏览器状态读取仍待 Windows 实机锁库与路径审计。
- 视频与音频下载已接入固定版本 `yt-dlp 2026.06.09`（x64/ARM64）、安全 argv 和 Job Object 取消；无 ffmpeg 时使用 Windows Media Foundation 原样封装 H.264/AAC，B 站视频在 yt-dlp 缺失或遇到已知 412/格式问题时走 HTTPS 备用路径。该链路必须在 Windows 实机完成 MSVC、真实媒体轨道和网络风控验证后才能发布。
- 文件中转使用独立 SQLite 仓库和后台串行队列，已接入文件/目录拖入拖出、剪贴板、Explorer 定位、复制与 Windows 系统分享界面。
- 剪贴板历史使用独立 SQLite 仓库和 `AddClipboardFormatListener`，支持文字与图片自动采集、手动常用项、搜索筛选、复制、置顶、删除和分级清空；链接检测保持默认关闭且仅做本地分类。
- 随记使用本地 Markdown 与独立 SQLite 仓库，后台串行执行增删改查，支持搜索、删除确认、复制、发送到提词器和停止输入 0.8 秒后自动保存；待 Windows 实机验证 XAML 编译、输入法、键盘和辅助功能。
- PDF 工具已将 QPDF 的信息/元数据、合并、页面导出、拆分、旋转、裁剪和加解密，以及 PDFium 的文字导出、PNG/JPEG 渲染、图片转 PDF、文字/图片水印和页码接入 WinUI 浮层；Office 转 PDF 只调用用户本机 LibreOffice。PDFium 153.0.7988.0 的 x64/ARM64 DLL、导入库、许可证、MSBuild 映射和 MSIX 内容复制已固定，统一后台队列与输出保护覆盖所有操作；仍待 Windows MSVC/XAML/MSIX、真实 Office、中文字体与实际文档验证。
- 天气使用 Windows 定位和单后台线程 WinHTTP，支持 Open-Meteo 当前天气、中国天气网与 NWS 官方预警、地区搜索、当前位置和最多 6 个保存地点；地点文件限制为 1 MiB 并使用平台原子替换，待 Windows 实机验证定位授权、网络代理和 WinUI 展示。
- 日历与待办使用独立本地 SQLite 仓库和串行后台服务，已接入本地化周视图、新建日程/待办、完成待办和删除确认；待 Windows MSBuild/XAML、时区/DST、输入控件和系统日历适配实机验证。
- 登录时启动使用 MSIX `StartupTask`，设置页直接显示系统状态，并区分用户禁用与策略管控；待 Windows 实机验证首次授权、系统启动应用设置和登录后后台启动。
- 番茄钟使用纯 C++ 截止时间状态机和消息窗口 `WM_TIMER`，支持专注/休息、自定义时长、开始、暂停、重置、首页与顶部摘要，以及完成后的侧边通知和 Windows App Notification。
- 闹钟使用独立 SQLite 仓库、动态 `WM_TIMER` 和 Windows 计划通知，支持一次性/每周重复、增删改、启停、睡眠恢复与系统时间变化重排；通知点击会直接打开闹钟编辑器，待 Windows 实机验证计划投递、声音循环和权限关闭路径。
- 保持亮屏与防空闲休眠使用公开 Power Request API；亮屏同时持有 Display/System 请求，独立防休眠请求通过引用计数互不干扰，退出时统一释放。
- 屏幕清洁使用每显示器实体黑色顶层窗口并在显示器变化时重建；键盘清洁只吞掉自身前台窗口收到的普通按键，两种模式互斥、支持鼠标退出，并在清洁期间临时保存和恢复电源请求状态。
- 提词器使用独立顶层 WinUI 工具窗口，支持剪贴板脚本、速度持久化、按经过时间自动滚动、暂停和回到开头；Windows 实机还需验证 XAML 构建、滚动平滑度与多显示器定位。
- 摄像头镜子使用 `MediaCapture` 彩色视频源和 `MediaPlayerElement` 横向镜像预览，只声明 `webcam` 能力；已覆盖准备、运行、拒绝、受限、无设备、配置失败和关闭释放状态，待 Windows 实机验证权限流程、预览兼容性和摄像头指示灯生命周期。
- 系统监控使用 `GetSystemTimes`、PDH、IP Helper、DXGI 和公开电源接口，只在系统页可见且可交互时采样；支持 CPU/GPU、内存、磁盘、网络、电池、运行时间和历史曲线，温度与风扇无可靠公开接口时明确显示不可用，待 Windows 实机验证计数器与网络代理。
- 磁盘清理只扫描限定的用户临时目录、崩溃报告和 Zisla 缓存/日志，应用保留期限、根目录保护和重解析点拒绝规则；用户逐项勾选并确认后，通过 Shell `IFileOperation` 移入回收站，失败项保留供重试。
- 内存释放只调用 Windows 公开接口回收 Zisla 自身未使用的工作集页面，界面明确标注作用范围，不伪装成系统级内存整理。
- 桌面宠物复用 16 套 Kenney CC0 内置像素素材，使用独立透明分层窗口固定在任务栏伴随锚点旁；支持开关、形象和左右位置持久化，并按 AI 运行、等待、失败和完成状态切换事件驱动动画。WIC 解码、分层窗口 Alpha、混合 DPI 和 GDI 对象生命周期仍待 Windows 实机验证。
- 侧边活动通知统一接收 AI 活动、任务终态、系统正在播放和 `zislactl` 外部通知，支持左右分组、容量限制、折叠、悬停暂停、关闭和设置开关。
- WinUI 3 外壳、天气定位与网络、三个后台监听、`zislactl.exe`、GSMTC、番茄钟/闹钟计时与通知、提词器消息定时器、Power Request、清洁窗口、摄像头预览、打包和界面数据绑定仍必须在 Windows 上编译并实际启动后才能视为通过。

Windows 计划通知只有 5 分钟投递窗口：电脑在触发时关机或休眠并错过超过 5 分钟后，系统会丢弃该次通知。Zisla 不把这种平台行为描述为可靠补发；启动、系统时间变化和自动恢复时会重建后续计划。

## 在 macOS 验证核心

构建目录必须放在仓库外，验证后删除：

```bash
cmake -S windows -B /tmp/zisla-windows-build -DCMAKE_BUILD_TYPE=Debug
cmake --build /tmp/zisla-windows-build --parallel
ctest --test-dir /tmp/zisla-windows-build --output-on-failure
```

macOS 验证只证明纯 C++ 核心可移植，不证明 WinUI、HWND、托盘、Acrylic、输入或 MSIX 行为。

## Windows 实机基线

- Windows 11
- Visual Studio，安装 C++ 桌面开发与 WinUI 应用开发工作负载
- Windows SDK 与稳定版 Windows App SDK
- Developer Mode
- 默认使用带包身份的 MSIX；发布时固定 Windows App SDK 版本并评估自包含部署

## 构建固定 QPDF

QPDF、zlib 与 libjpeg-turbo 的源码均在 `Vendor/` 中固定。Windows 开发机使用下列脚本生成当前架构的静态前缀，不会下载依赖，也不使用 vcpkg 或 NuGet：

```powershell
powershell -ExecutionPolicy Bypass -File .\Scripts\build-qpdf.ps1 -Architecture x64 -Configuration Release
```

默认输出在 `%LOCALAPPDATA%\zisla\build\qpdf\<arch>\<configuration>\prefix`，不会污染仓库。生成的 QPDF CMake 包目录可传给跨平台验证：

```powershell
cmake -S . -B "$env:TEMP\zisla-windows-build" `
  -DZISLA_ENABLE_QPDF_ADAPTER=ON `
  -DZISLA_QPDF_PACKAGE_DIR="$env:LOCALAPPDATA\zisla\build\qpdf\x64\Release\prefix\lib\cmake\qpdf"
```

`-Clean` 只删除脚本对应的 `BuildRoot`；默认构建不会删除本机生成的前缀，便于随后在 Visual Studio/MSVC 中验证。

## 依赖策略

- 核心优先使用 C++20 标准库和 Windows 公共接口。
- 必需的第三方源码或二进制放入 `windows/Vendor/<name>/<version>/`，同时保存许可证、来源 URL 和 SHA-256。
- 不跟随浮动分支、`latest` URL 或运行时自动下载开发库。
- Windows SDK、C++/WinRT 和 Windows App SDK 属于平台工具链，通过项目锁定版本；不复制系统 SDK 源码进仓库。
- 直接平台包的来源、SHA-256、许可证和传递依赖记录在 [`Dependencies.lock.json`](Dependencies.lock.json)；Windows 首次恢复后还必须提交 NuGet 生成的 `packages.lock.json`。
- 在 macOS `/tmp` 下载的验证工具和构建产物必须在本次验证结束后删除。

## Windows 视觉资源

应用图标与 macOS 共用手绘 Z 轮廓：MSIX 和可执行文件使用白底日间版，通知区域图标会随 Windows 系统主题在日间与夜间版本间切换。在 macOS 上重新生成 MSIX PNG 和多尺寸 ICO：

```bash
windows/Scripts/generate-assets.sh
```

脚本复用 `mac/Resources/AppIconSource.png` 和统一配色生成器，只使用系统 AppKit/Core Graphics，不下载资源；生成结果直接写入 `windows/App/Assets/`。

桌面宠物素材随包位于 `windows/App/Assets/Pets/`，来源与 CC0 许可保存在同目录 `CREDITS.md`；运行时不下载或导入宠物资源。

## 目录

```text
windows/
  Core/       不依赖 WinRT 的状态、几何和领域规则
  Tests/      Core 的跨平台行为测试
  Docs/       架构、视觉和功能对齐记录
  App/        Windows 实机上创建的 C++/WinRT + WinUI 3 外壳
  CLI/        与 App 共用 SQLite 状态协议的 zislactl.exe 入口
  Vendor/     经审计并固定版本的必要第三方代码
```

完整迁移范围见 [Docs/feature-parity.md](Docs/feature-parity.md)，窗口与视觉约束见 [Docs/architecture.md](Docs/architecture.md)。
