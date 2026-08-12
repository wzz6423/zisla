# zisla for macOS

这是 zisla 的 macOS 实现：鼠标移到屏幕顶部中央时展开，移开后隐藏。它使用 AppKit `NSPanel`、SwiftUI 和事件驱动服务实现，不创建常驻透明热区窗口，隐藏时不运行帧循环。

Swift target、Bundle ID、本地数据目录和 `zislactl` 均使用 zisla 标识。升级时会自动迁移此前版本的本地数据和偏好设置。

支持 macOS 14 及更高版本。macOS 26 使用 Liquid Glass，macOS 14/15 自动回退到系统原生材质。

## 功能

- 系统正在播放：MediaRemote 展示封面、标题、进度和播放控制；Core Audio 兜底识别所有当前实际输出音频的应用，暂停、停止和静音来源不显示。
- 文件中转与共享：拖动文件、音视频或链接到菜单栏下方的专用触发带时自动展开左右肩部提示，无需进入 macOS 顶边窗口切换热区；可放入中转站或调用 macOS 共享菜单，并支持 Finder 定位。
- AI 状态：兼容 Claude、Codex、ChatGPT、Gemini、Grok、Qoder、千问等 CLI/桌面工具，展示完整运行任务列表、实时 token 趋势、按日的贡献日历热力图和侧边通知；折叠态会叠放不同 AI 的官方 Logo。
- 下载器：粘贴视频或音频链接，通过 `yt-dlp` 下载到默认“下载”目录或自选目录；无 ffmpeg 时使用 AVFoundation 原生封装分离的视频轨和音频轨，B 站风控或格式不可用时使用只读接口备用路径。
- 剪贴板检测：默认关闭；开启后只在本地识别新链接并提示，不会自动联网、下载、清空或写回剪贴板。
- 信息聚合：同时展示当前位置和最多 6 个自选地区的天气，可搜索添加或删除地点；日历事件与提醒事项支持新增、删除及标记提醒完成。
- 随记：以系统「备忘录」为数据源——左侧列出备忘录中已有的笔记，可查看、编辑、删除、新建；右侧编辑/预览切换，标题、列表、引用、代码块等 Markdown 实时渲染。草稿停止输入后自动写回备忘录。首次使用需授权自动化。
- 检查和下载更新：检查 GitHub/Gitee Release 后，可将最新 DMG 下载到默认下载目录或临时指定目录。下载包不会自动打开或安装；安装前必须退出 zisla，再将 DMG 中的应用拖入 Applications。
- 独立开关：媒体、中转、AI、下载、日历、天气、随记、侧边通知、hover、剪贴板和更新均可配置。
- 外观：固定使用当前深色视觉；顶部保持纯黑，下半部使用高透明度的系统模糊材质。
- 折叠状态：使用贴住屏幕顶边的单个连续中央状态条，高度与物理刘海严格一致；轮廓顶部较窄、左右底侧向外展开并由连续弧线过渡，无刘海外接屏使用相同轮廓的模拟条。

## 快速开始

### 环境

- macOS 14+
- Swift 6 / Xcode 16+（仅 Command Line Tools 也可构建）
- 可选：`yt-dlp`、`ffmpeg`

本机已安装 Homebrew 时：

```bash
brew install yt-dlp ffmpeg
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

zisla 会自动读取各工具公开或稳定的本地会话状态，只解析事件类型、状态、时间、模型和会话 ID，不读取提示词或回答正文：

| 工具 | CLI | Desktop / IDE | VS Code 插件 | 自动检测源 |
| --- | --- | --- | --- | --- |
| Codex / GPT | Codex CLI | Codex Desktop | OpenAI Codex | `~/.codex/sessions/**/*.jsonl` |
| Claude | Claude Code | 使用 Claude Code 会话的宿主 | Claude Code | `~/.claude/projects/**/*.jsonl` |
| Gemini | Gemini CLI | - | - | `~/.gemini/tmp/**/chats/session-*` |
| Grok | Grok CLI | - | - | `~/.grok/sessions/**/events.jsonl` |
| 千问 | Qwen Code | - | Qwen Code Companion | `${QWEN_RUNTIME_DIR:-${QWEN_HOME:-~/.qwen}}/projects/**` |
| Qoder | Qoder CLI | Qoder、QoderWork、QoderWake、JetBrains 等名称含 Qoder 的宿主 | Code、Cursor、VSCodium、Windsurf | `~/.qoder*/logs/sessions/**` 与宿主的 `qoder-agent-sdk.log` |

检测到等待审批或等待用户回答时显示黄色，工具或命令报错时显示红色，正常运行时显示绿色；同一时刻按红色、黄色、绿色的顺序聚合。Qwen runtime sidecar 只有在 PID 仍存活时才生效，避免退出后长期误报。

普通聊天型 Desktop 应用如果不落盘结构化活动事件，系统无法可靠区分“应用已打开但空闲”和“模型正在生成”。这类工具应使用下面的 `zislactl` hook 接入；zisla 不会用常驻进程冒充运行状态。

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

Codex、ChatGPT、Gemini、Grok、Qoder、Qwen 只需替换 `--provider`。ChatGPT 继续使用兼容参数 `--provider gpt`，Qoder 使用 `--provider coder` 或 `--provider qoder`。可在任意工具的 hook、shell wrapper 或任务脚本中调用。

AI 运行列表和折叠状态使用各工具的官方 Logo 标识任务来源。

接入协议见 [CLI 接入设计](Docs/cli-reference.md)。

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
- 剪贴板：默认关闭；开启时只在 `changeCount` 变化后读取一次文本，最多处理一个链接，不保存 query 参数日志，也不调用清空、声明类型或写入 API，因此不会替换 Mac、iPhone、iPad 之间的通用剪贴板内容。
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
python3 -m http.server 4173
```

打开 `http://localhost:4173`。

## 文档

- [架构与性能设计](Docs/architecture.md)
- [CLI 接入设计](Docs/cli-reference.md)
- [签名与发布设计](Docs/releasing.md)

## 系统限制

- macOS 没有公开的“灵动岛”API；物理刘海通过 `safeAreaInsets` 和顶部辅助区域推断，无刘海屏幕使用同样的自有覆盖层模拟。
- DRM 视频、登录窗口、锁屏和部分独占全屏应用不保证提供 Now Playing 数据或允许覆盖层显示。
- 未接入系统媒体中心的应用仍可识别正在输出音频的来源，但无法保证提供曲名、封面或进度；暂停、停止和静音视频按设计不显示。
- 免费 ad-hoc 签名包未经公证，首次打开可能需要在系统设置中选择“仍要打开”。无论签名方式，应用内都只检查和下载更新包，不会自动替换当前应用。

## License

MIT
