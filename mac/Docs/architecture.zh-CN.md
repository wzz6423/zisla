# 架构与性能设计

[English](architecture.md) | **简体中文** | [其他语言](../../docs/locales/README.md)

## 顶部触发

隐藏态没有透明窗口。`PointerEdgeMonitor` 安装一组全局和本地 `NSEvent` monitor，只处理 `mouseMoved` 与拖拽事件；`ScreenLayoutEngine` 用纯几何判断指针是否进入每块屏幕顶部中央 6 px 区域。

每块屏幕通过 `NSScreenNumber` 对应的 `CGDirectDisplayID` 建立稳定身份。布局始终以 `screen.frame.maxY` 为顶部锚点，支持负坐标、上下排列和无刘海外接屏。

连接多显示器时，在「设置 → 通用 → 显示器模式」分别选择灵动岛模式（摄像头或自定义位置）、刘海模式，或在该屏幕不显示。单屏时隐藏此设置，使用原有全局样式；重新连接后恢复各屏幕的配置。启用灵动岛的屏幕会同时显示收起的岛。在一块屏幕上展开灵动岛、打开快捷操作、录音或显示临时提示时，其他屏幕的岛保持可见。选择通知显示器只决定哪块屏幕显示通知。

## 窗口

主岛只保留一个 `.borderless + .nonactivatingPanel`：

- `.statusBar` 层级，不覆盖系统锁屏和系统菜单。
- `.canJoinAllSpaces + .fullScreenAuxiliary` 支持 Space 与普通全屏。
- hover 展开不调用 `NSApp.activate`，不会抢走当前应用焦点。
- 隐藏使用 `orderOut`，菜单栏区域不被透明窗口吞掉。

左右通知面板按需创建，队列为空立即隐藏。

## 状态与并发

- AppKit、SwiftUI 状态和窗口控制限制在 `MainActor`。
- 开启菜单栏管理后，zisla 创建两个 `NSStatusItem` 控件。图标列表打开时，zisla 读取 `AXExtrasMenuBar`，并在移动后核对所选图标的位置。
- 下载、天气和 GitHub 请求使用 actor。
- hook 写入的 AI 状态使用目录文件系统事件监听；各 AI 会话源定期比较最近本地会话或活动文件的 mtime/size，未变化时复用解析缓存。
- 自动检测只读取判断任务状态所需的结构化事件、固定状态 marker 或活动元数据，不读取 prompt/answer 正文；任一 Provider 解析失败不会阻断其他 Provider。
- AI 账户额度来自供应商独立采样。Antigravity 的 Gemini 与 Claude/GPT 额度保留各自的重置窗口和低额度提醒。Gemini App 普通对话额度使用同一 Google 账号保存的网站 Cookie 查询；Gemini CLI 保留本地 OAuth 来源。缺失额度不得估算。
- 折叠延迟使用可取消 `Task` 和 generation token，旧任务不能隐藏重新展开的岛。
- 隐藏态没有 `TimelineView`、60 Hz Timer 或持续动画提交。

## 媒体检测

MediaRemote 提供曲名、封面、进度和控制；Core Audio 14.4+ 的进程对象属性负责确认应用是否存在活动输出流，并在元数据缺失时提供来源应用兜底。进程列表和输出状态使用属性监听器并配合定期复核，不采集音频内容，也不请求屏幕录制或辅助功能权限。暂停、停止和静音来源不会保留在媒体区域。

## 录屏与应用混音

录屏和应用混音与媒体元数据检测是独立路径。录屏请求屏幕录制以及启用的麦克风/摄像头权限，在本机保存所选媒体，并在录屏目录管理工程。应用混音在 macOS 14.4+ 使用 Core Audio tap，需要系统音频录制权限。

## 材质

macOS 26 使用单层 SwiftUI `glassEffect`；macOS 14/15 使用单层 `NSVisualEffectView`。系统开启“降低透明度”后改用实体背景。岛面不会叠加多层 blur/material。

## 下载安全边界

Swift 使用 `Process.executableURL` 和参数数组启动 `yt-dlp`，URL 永远位于 `--` 后的独立 argv。运行时禁用配置、插件和 exec，并发排空输出管道，通过 JSON sentinel 解析进度。

只有退出码为 0、完成路径存在、解析符号链接后仍位于授权目录内时任务才成功。每个任务只清理自己的 UUID 临时目录。

## 检查和下载更新

当前选择的更新通道会在本次运行中解析一次公网出口国家码，再由 Sparkle 读取该安装包对应的已签名 appcast，经 HTTPS 下载其中引用的 ZIP，并在解压前验证 EdDSA 归档与 feed 签名，随后替换并重启应用。`CN` 先读取 Gitee（Release 为 `update-release`，Preview 为 `preview`），再回退一次对应 GitHub feed；其他国家码先读取 GitHub，再回退一次 Gitee。无法获取国家码时保留 Gitee 优先；两份 appcast 分别只引用本站已签名的 ZIP。每次发布在共享的 `appcast.xml` 旁再发布每个架构各自的 appcast，单架构安装只请求自己 slice 对应的那份（Rosetta 下的 x86_64 slice 按 `arm64` 请求），因此不会被 Universal 包替换；Universal 安装按自身可执行文件里的 slice 数判定，继续请求 `appcast.xml`，这一份同时服务于按架构更新之前发布的版本。切换设置同时影响自动和手动检查，并重置 Sparkle 的下一次检查周期。内置公钥不含账户信息；私钥仅保存在维护者的 macOS 钥匙串或受保护的私钥文件中。
