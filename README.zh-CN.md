# zisla

[English](README.md) | **简体中文**

**zisla 是一个在需要时出现、平时保持收起的原生 macOS 动态工作空间。** 将鼠标移到屏幕顶部中央，即可在轻量工作台中查看 AI 任务、媒体、文件中转、下载和常用桌面工具；无刘海显示器也会使用同样轮廓的模拟状态条。

当前实现支持 **macOS 14+**。Apple 芯片 Mac 为受支持配置；Intel 机型可能存在可用的发布包，但不保证兼容性。

## 为什么它适合放在屏幕顶部

- **按需出现，不抢焦点。** 从屏幕顶边展开，必要时固定面板，同时继续在当前应用中工作。
- **把正在进行的事放在一起。** 无需打开完整仪表盘，即可查看正在播放、AI 任务、下载、计时器、邮件、系统状态和电池信息。
- **看见 AI 工作，不读取对话。** zisla 仅读取判断任务状态所需的结构化事件和本地活动元数据，绝不读取提示词或回答正文。
- **控制权留在本机。** 功能模块、剪贴板历史和链接检测均可独立开关；权限只在功能首次实际需要时请求。

## 能做什么

### 保持桌面工作流顺畅

| 能力 | 说明 |
| --- | --- |
| 正在播放 | 显示封面、标题、进度、滚动歌词和播放控制；没有媒体元数据时，Core Audio 可识别实际输出音频的应用。 |
| 文件中转与共享 | 将文件、音视频或链接拖到屏幕顶部触发带，放入中转站、在 Finder 中定位，或调用 macOS 系统共享菜单。 |
| 剪贴板与通知 | 可选记录本机剪贴板历史、仅在本机识别新链接，并在收起状态显示媒体、AI 活动、浏览器下载、计时器、邮件和更新。 |
| 日常工作区 | 提供天气、日历、提醒事项、Mail.app、以系统「备忘录」为数据源的 Markdown 笔记、锁屏信息和可选桌面宠物。 |

### 让 AI 工作状态可见

zisla 可监控 Codex、Claude Code、GitHub Copilot、Gemini、Grok、Kimi Code、Qwen Code、Qoder、ZCode、TRAE、OpenCode、Harnext、WorkBuddy、豆包等本地活动源，展示任务、状态、token 趋势、贡献热力图和侧边通知。

对于没有稳定本地活动源的工具，可通过 `zislactl` 让脚本、CI 和工具 hook 上报进度、用量与通知，协议状态始终保存在这台 Mac 上。设置中还可检测、安装、更新和卸载常用 AI CLI，并管理本机 Skills。Provider 与命令见 [CLI 接入设计](mac/Docs/cli-reference.zh-CN.md)。

### 处理桌面上的细碎工作

| 范围 | 已包含工具 |
| --- | --- |
| 下载与文档 | 通过 `yt-dlp` 下载视频与音频；在本机完成 PDF 合并、拆分、旋转、裁剪、转换、渲染、文本导出、水印、页码、加密、解除密码和元数据编辑。 |
| 专注与展示 | 番茄钟、闹钟、保持亮屏、防止空闲休眠、屏幕与键盘清洁、提词器和摄像头镜子。 |
| 系统与电池 | CPU、GPU、内存、磁盘、网络、风扇和电池信息，以及安全可删除的缓存和日志清理。 |
| 语音输入 | 全局快捷键录音与转写、可选本地或远端转写整理，以及本机语音记录。 |

## 快速开始

### 安装应用

从 [GitHub Releases](https://github.com/wzz6423/zisla/releases) 或 [Gitee Releases](https://gitee.com/wzz6423/zisla/releases) 下载最新 DMG，挂载后将 `zisla.app` 拖入 `Applications`。

启动后，将鼠标移到当前屏幕顶部中央即可展开；也可从菜单栏图标选择“显示灵动岛”。非公证的预览包首次打开时，可能需要在“系统设置 > 隐私与安全性”中选择“仍要打开”。

### 从源码运行

开发环境需要 Swift 6 / Xcode 16+；仅安装 Command Line Tools 也可构建。

```bash
cd mac
swift run zisla
```

下载器需要 `yt-dlp`，`ffmpeg` 为可选依赖；Office 转 PDF 需要 LibreOffice 或 OpenOffice。构建、测试和打包命令见 [macOS 开发指南](mac/README.zh-CN.md)。

## 设计为不打扰工作

- 支持多显示器、Spaces 和普通全屏应用；展开时不会激活或抢走当前应用焦点。
- 隐藏状态不创建常驻透明热区窗口，也不运行帧循环；通过全局事件监听与几何判断触发展开。
- 使用单层系统材质；系统开启“降低透明度”后自动使用实体背景。
- 物理刘海通过系统安全区域推断；无刘海的外接显示器使用同样轮廓的覆盖层。

具体实现取舍见 [架构与性能设计](mac/Docs/architecture.zh-CN.md)。

## 隐私与权限

zisla 仅在启用的功能首次实际需要时请求系统权限。你可以随时在设置中关闭模块，或在 macOS 系统设置中撤销授权。

| 范围 | 边界 |
| --- | --- |
| AI 活动 | 仅读取结构化事件和本地活动元数据，绝不读取提示词或回答正文。 |
| 剪贴板与文件 | 剪贴板历史和链接检测是独立的本地开关；文件中转使用安全书签，不复制原始文件。 |
| 备忘录、邮件与语音 | 备忘录和邮件通过 AppleScript/JXA 访问，并要求自动化授权。语音仅在主动使用时录音；整理功能只向选定的本地模型、远端 Provider 或 CLI 档案发送转写文本。 |
| 浏览器下载与媒体 | 使用 macOS 公共文件进度、MediaRemote 元数据和 Core Audio 输出状态；不会读取浏览器历史数据库，也不会采集音频内容。 |
| 网络 | 天气、更新检查、下载器请求和可选的远端语音整理，只会为各自已启用的操作联网。 |

完整的权限与网络行为见 [macOS 开发指南](mac/README.zh-CN.md#权限和隐私)。

## 文档

| 文档 | 用途 |
| --- | --- |
| [macOS 开发指南](mac/README.zh-CN.md) | 模块、AI 接入、依赖、构建、测试、权限与系统限制。 |
| [架构与性能设计](mac/Docs/architecture.zh-CN.md) | 顶部触发、窗口行为、并发、媒体与下载安全设计。 |
| [CLI 接入设计](mac/Docs/cli-reference.zh-CN.md) | `zislactl` 的 Provider、命令、字段与退出码。 |
| [签名与发布设计](mac/Docs/releasing.zh-CN.md) | 签名、公证、DMG、更新通道与发布验收。 |
| [贡献指南](CONTRIBUTING.zh-CN.md) | 开发环境、分支、提交和 Pull Request 要求。 |

## 贡献

欢迎提交 Issue 和 Pull Request。开始前请阅读 [贡献指南](CONTRIBUTING.zh-CN.md)；安全问题请通过 [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) 私下报告，不要公开提交 Issue。

## License

MIT
