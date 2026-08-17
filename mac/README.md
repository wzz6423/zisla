# zisla for macOS

这是 zisla 的 macOS 实现：鼠标移到屏幕顶部中央时展开，移开后隐藏。它使用 AppKit `NSPanel`、SwiftUI 和事件驱动服务实现，不创建常驻透明热区窗口，隐藏时不运行帧循环。

Swift target、Bundle ID、本地数据目录和 `zislactl` 均使用 zisla 标识。升级时会自动迁移此前版本的本地数据和偏好设置。

支持 macOS 14 及更高版本。macOS 26 使用 Liquid Glass，macOS 14/15 自动回退到系统原生材质。

## 功能

### 13 个功能模块

| 模块 | 已实现能力 |
| --- | --- |
| 首页 | 按需汇总当前番茄钟、首个活动 AI 任务、原生下载与多个浏览器下载进度。 |
| 中转 | 将文件、音视频或链接拖到顶部触发带，暂存到中转站、在 Finder 中定位或调用系统共享菜单。 |
| 剪贴板 | 在本机保存可搜索历史，按图片、URL 与文件筛选并标记常用项；历史记录与链接检测可独立开关。 |
| AI 监控 | 聚合受支持 CLI、桌面端与 IDE 的活动任务、状态、token 趋势、贡献热力图和侧翼通知。 |
| 下载 | 通过 `yt-dlp` 下载视频或音频；无 `ffmpeg` 时用 AVFoundation 封装兼容轨道，并为 B 站提供只读接口备用路径。 |
| 日程 | 同时展示当前位置与最多 6 个自选地点的天气；查看、新增和删除日历事件及提醒事项，并标记提醒完成。 |
| 邮件 | 读取选定 Mail.app 账户，在岛内查看收件箱、标记已读、回复、撰写邮件和移入废纸篓。 |
| 随记 | 以系统「备忘录」为唯一数据源，查看、编辑、新建和删除 Markdown 笔记，并提供实时预览和自动写回。 |
| PDF | 在本机完成合并、拆分、旋转、图片/Office 转换、转图片、导出文字、两类水印、页码、裁剪、加密、解锁和元数据编辑等 14 项操作。 |
| 小工具 | 提供番茄钟、闹钟、保持亮屏、防止空闲休眠、屏幕与键盘清洁、提词器、摄像头镜子和经确认后清空废纸篓。 |
| 系统 | 查看 CPU、GPU、内存、磁盘、网络、温度和风扇状态，释放内存并扫描可安全清理的缓存、日志与临时数据。 |
| 电池 | 展示本机充放电功率流、健康度、循环次数、温度、容量、电流、电压、充电器，以及蓝牙配件和已信任 Apple 移动设备电量。 |
| 锁屏 | 在系统锁屏页展示自定义文字、农历日期、媒体与相关状态信息。 |

### 跨模块能力

- 系统正在播放：MediaRemote 展示封面、标题、进度、滚动歌词和播放控制；Core Audio 兜底识别实际输出音频的应用，暂停、停止和静音来源不显示。
- 浏览器下载：在首页、收起态和侧翼通知中显示 Safari、Chrome、Edge、Firefox、Brave、Vivaldi、Opera 与 Arc 的下载来源和进度。
- 语音输入：支持按键切换或按住说话、自定义全局快捷键、系统语音识别、本地或远端模型整理，以及本机录音历史。
- CLI 与 Skills 管理：在设置中检测、安装、更新和卸载常用 AI CLI，并管理本机 Skills。
- 桌面宠物：可选择内置或导入宠物，并配置显示在灵动岛左侧或右侧。
- 更新：检查 GitHub/Gitee Release，可手动或自动下载当前通道的 DMG；应用不会自动挂载或替换自身。
- 外观与交互：设置窗口可跟随系统、浅色或深色；灵动岛支持透明或磨砂表面、固定展开、多显示器、Spaces 和无刘海外接屏。
- 新安装默认启用功能模块；每项功能、收起态状态、侧翼通知、菜单栏指标和更新行为都可在设置中单独调整，已有安装保留用户当前配置。

## 快速开始

### 环境

- macOS 14+
- Swift 6 / Xcode 16+（仅 Command Line Tools 也可构建）
- 可选：`yt-dlp`、`ffmpeg`；Office 转 PDF 另需 LibreOffice 或 OpenOffice

本机已安装 Homebrew 时：

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### 运行源码

```bash
swift run zisla
```

应用以菜单栏附件模式启动。鼠标移到当前屏幕顶部中央 6 px 区域即可展开；也可从菜单栏图标选择“显示灵动岛”。

### 构建 `.app`

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

打包自带的官方 `yt-dlp` Helper：

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh` 固定版本下载官方 macOS standalone 文件，并用官方 `SHA2-256SUMS` 校验后安装到 `Tools/yt-dlp`。

## AI 工具接入

### 自动检测

zisla 会读取各工具公开或稳定的本地会话状态，只提取判断任务状态所需的结构化事件和本地活动元数据，不读取提示词或回答正文：

| 环境 | 自动检测范围 |
| --- | --- |
| OpenAI / Anthropic | Codex CLI 与 Desktop、Claude Code 及其宿主环境 |
| GitHub / Google / xAI | GitHub Copilot CLI 与 VS Code、Gemini CLI、Grok CLI |
| 国内与独立工具 | Kimi Code、Qwen Code、Qoder、TRAE、OpenCode、Harnext/Harness、WorkBuddy、豆包 |

检测到等待审批或等待用户回答时显示黄色，工具或命令报错时显示红色，正常运行时显示绿色；同一时刻按红色、黄色、绿色的顺序聚合。Qwen runtime sidecar 只有在 PID 仍存活时才生效，避免退出后长期误报。

普通聊天型 Desktop 应用如果不落盘结构化活动事件，系统无法可靠区分“应用已打开但空闲”和“模型正在生成”。这类工具（包括 ChatGPT 等）应使用下面的 `zislactl` hook 接入；zisla 不会用常驻进程冒充运行状态。

### `zislactl` 本地协议

`zislactl` 将任务状态和历史用量写入 SQLite：

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

用量历史不会因应用重启、覆盖更新或清空任务而删除；下次启动会从此数据库回读。只有用户手动删除应用数据时，历史才会丢失。

示例：

```bash
swift run zislactl update \
  --id build-42 \
  --provider claude \
  --title "重构索引" \
  --progress 68 \
  --detail "17/25"

swift run zislactl usage \
  --provider claude \
  --input-tokens 12400 \
  --output-tokens 2100 \
  --model claude-opus-4-8

swift run zislactl finish --id build-42 --detail "完成"
```

Provider 规范值包括 `claude`、`codex`、`gemini`、`grok`、`gpt`、`copilot`、`kimi`、`qwen`、`coder`、`trae`、`opencode`、`harness` 和 `doubao`；常见别名会自动归一化。可在任意工具的 hook、shell wrapper 或任务脚本中调用。

AI 运行列表和折叠状态使用各工具的官方 Logo 标识任务来源。

接入协议见 [CLI 接入设计](Docs/cli-reference.md)。

## 浏览器下载进度

zisla 使用 macOS 公共文件进度机制监听“下载”目录，并结合临时文件扩展名、下载来源扩展属性和正在运行的浏览器解析来源。它不会读取浏览器历史数据库，也不会为识别进度发起网络请求；下载成功后完成状态保留约 3 秒。

## 下载器

可执行文件按以下顺序解析：

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

URL 作为独立 argv 传给 `Process`，不经过 shell。运行时强制忽略用户配置和插件、禁用 `--exec`、限制单个条目，并验证最终文件仍位于授权目录内。

没有 ffmpeg 时：

- 视频优先下载 AVC/MP4 视频轨和 M4A 音频轨，再通过系统 AVFoundation 原样封装为 MP4；若站点只提供单文件则直接保存。
- 音频优先已有 M4A，否则保留原始音频格式。
- B 站视频在 yt-dlp 遇到 HTTP 412、格式不可用或本机没有 yt-dlp 时，改用 B 站只读接口获取 DASH 轨并走同一原生封装流程，不安装额外工具。

## 随记

灵动岛内的 Markdown 随记，以系统「备忘录」App 作为唯一数据源——既能新建，也能查看、编辑、删除备忘录里已有的笔记，而不仅限于新增。

- 列表：进入模块时通过 JXA（`osascript -l JavaScript`）读取备忘录中未删除笔记的标题与修改时间，按最近修改排序；从备忘录返回时会同步列表，已移入「最近删除」的笔记不显示。点选切换当前编辑的笔记，可刷新、新建、右键删除。
- 查看/编辑：选中笔记后用 AppleScript 读取其 `plaintext`（即 Markdown 原文）载入编辑器；编辑态使用原生 `TextEditor`，停止输入约 0.8 秒后自动写回备忘录（防抖，避免每次按键触发 AppleScript）。新建则在备忘录中创建一条新笔记并选中。
- 预览：内置块级解析器把 Markdown 渲染为 `AttributedString`，支持标题、无序/有序/任务列表、引用、围栏代码块、分隔线，以及粗体、斜体、行内代码、删除线和链接等行内格式。
- 存储格式：笔记正文按 Markdown 原文存入备忘录 `body` 的普通文本段落（HTML 转义并保留空行），读取 `plaintext` 时还原 Markdown 源文本，由随记模块负责渲染。备忘录 App 内显示的是普通文本（不渲染），这是用备忘录做 Markdown 存储后端的取舍。
- 权限：首次读取/写入时 macOS 弹出自动化授权弹窗，允许 zisla 控制「备忘录」；被拒绝后列表与编辑会返回失败提示。

随记不在本地另存一份——备忘录即存储后端，避免双份数据与同步问题。

## 权限和隐私

- 日程：首次打开日程模块时分别请求日历和提醒事项权限；新增事件/提醒、删除或标记提醒完成后自动刷新。
- 定位：天气默认使用一次性当前位置请求，不持续跟踪；也可在设置中搜索、保存和删除其他地区，同时查看多个地点。
- 文件和下载目录：使用用户选择目录的安全书签；文件中转不复制原文件。
- 剪贴板：新安装默认开启历史与链接检测；两项可独立关闭。开启后只在 `changeCount` 变化时读取一次，最多处理一个链接，不保存 query 参数日志，也不调用清空、声明类型或写入 API，因此不会替换 Mac、iPhone、iPad 之间的通用剪贴板内容。
- AI 状态：自动检测只读取判断任务状态所需的结构化事件和本地活动元数据。
- 语音：仅在用户主动触发时访问麦克风和系统语音识别；录音、原始转写和 AI 整理文本由用户在本机管理。启用模型整理后，转写文本只发送给用户选定的本地模型、远端 Provider 或 CLI 档案；远端 Provider 与 CLI 凭据存入私有数据库，不写入普通设置。
- 蓝牙与设备：仅在打开电池模块时读取 macOS 可提供的配件电量和已与本机建立信任关系的 Apple 移动设备电量。
- 摄像头与输入监控：摄像头仅在打开镜子时使用；自定义物理修饰键快捷键和键盘清洁可能需要输入监控授权。
- 浏览器下载：只订阅系统公开的文件进度并检查下载临时文件，不读取浏览历史或页面内容。
- 媒体：通过 MediaRemote 获取系统元数据，并用 Core Audio 的进程输出状态确认是否正在播放。MediaRemote 是非公开框架，因此当前构建不适合直接提交 Mac App Store；无元数据时降级显示实际出声的来源应用。
- 网络：天气访问 Open-Meteo；中国大陆地点的官方预警访问中国天气网公开数据，其他地点优先使用 WeatherKit；更新检查先访问 Gitee API，未发现新版本或 Gitee 不可用时再访问 GitHub API，确认下载时访问对应 Release 的 DMG；B 站备用下载访问其只读视频信息、播放地址和媒体 CDN；识别剪贴板链接本身不联网。
- 自动化：随记通过 AppleScript/JXA 读写系统「备忘录」App 中的笔记（列出、查看、编辑、新建、删除），首次使用需在弹窗中授权 zisla 控制「备忘录」；随记不联网，笔记数据存在备忘录中。

## 测试

完整 Xcode 环境：

```bash
swift test
```

仅安装 Command Line Tools 时：

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

产品介绍页：

```bash
cd ../Web
npm ci
npm run dev
```

打开 Vite 在终端输出的本地地址。生产构建使用 `npm run build`。

## 文档

- [架构与性能设计](Docs/architecture.md)
- [CLI 接入设计](Docs/cli-reference.md)
- [签名与发布设计](Docs/releasing.md)

## 系统限制

- macOS 没有公开的“灵动岛”API；物理刘海通过 `safeAreaInsets` 和顶部辅助区域推断，无刘海屏幕使用同样的自有覆盖层模拟。
- DRM 视频、登录窗口、锁屏和部分独占全屏应用不保证提供 Now Playing 数据或允许覆盖层显示。
- 未接入系统媒体中心的应用仍可识别正在输出音频的来源，但无法保证提供曲名、封面或进度；暂停、停止和静音视频按设计不显示。
- 浏览器必须向 macOS 发布文件进度，或在“下载”目录使用可识别的临时文件，zisla 才能显示下载百分比。
- 电池健康、温度、实时功率和配件电量取决于硬件、连接方式及 macOS 实际暴露的数据；缺失字段会显示为不可用。
- Office 转 PDF 依赖本机 LibreOffice 或 OpenOffice，其余 PDF 操作在本机直接完成。
- 免费 ad-hoc 签名包未经公证，首次打开可能需要在系统设置中选择“仍要打开”。无论签名方式，应用内都只检查和下载更新包，不会自动替换当前应用。

## License

MIT
