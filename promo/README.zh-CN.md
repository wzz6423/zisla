# zisla 发布宣传片

[English](README.md) | **简体中文**

160 秒、60 fps 的 zisla 产品宣传片，用 [Remotion](https://www.remotion.dev/) 逐帧渲染：React + TypeScript + Tailwind CSS，覆盖官网列出的 12 个模块和 19 项扩展功能。同一条画面时间轴提供放克与电影配乐两个版本，各支持 1080p 和 4K。布局、尺寸和弹簧参数取自原生应用源码，演示数据为虚构样例。

## 本地运行

```bash
cd promo
npm install
npm run studio
```

`npm run studio` 打开 Remotion Studio，可以逐帧拖动、单独预览每一幕。已在 macOS 27、Node 26、npm 11 上验证。

## 渲染

```bash
npm run render
```

```bash
npm run render:4k
```

抽单帧：

```bash
npm run still -- out/frame.png --frame=300
```

```bash
npx remotion still Scene3Flow out/scene3.png --frame=200
```

类型检查与自动化测试：

```bash
npm run typecheck
npm test
```

- 首次渲染时 Remotion 会自行取得 Chrome Headless Shell，放进 `node_modules/.remotion/`。
- `out/` 已忽略，4K 交付文件不入库。官网使用的 1080p 成片与海报保存在 `web/public/media/`。
- 逐帧渲染，任何一帧都能单独渲染；单帧 PNG 可逐字节复现，整片 mp4 因编码器不保证逐字节一致。
- 工程不分发字体，字体栈是系统字体，因此在 macOS 上渲染才是 SF Pro。

## 合成与时间轴

| 合成 id | 尺寸 | 帧数 | 内容 |
| --- | --- | --- | --- |
| `ZislaLaunchFilm` | 1920×1080 | 9600 | 2 分 40 秒，Funkorama 配乐 |
| `ZislaLaunchFilm4K` | 3840×2160 | 9600 | 同画面放克版，4K |
| `ZislaLaunchFilmCinematic` | 1920×1080 | 9600 | 同画面，The Miracle of Flight 配乐 |
| `ZislaLaunchFilmCinematic4K` | 3840×2160 | 9600 | 同画面电影配乐版，4K |
| `Scene1Awakening` | 1920×1080 | 300 | 0–5s，顶部触发和按应用汇总 |
| `SceneLayouts` | 1920×1080 | 960 | 5–21s，刘海、摄像头、四边定位和宠物 |
| `Scene2AICenter` | 1920×1080 | 840 | 21–35s，任务、按日模型统计、历史和双窗口额度 |
| `Scene3Flow` | 1920×1080 | 900 | 35–50s，媒体、中转站多选和视频／音频下载 |
| `SceneMail` | 1920×1080 | 480 | 50–58s，阅读、撰写、发送和全部已读 |
| `SceneEveryday` | 1920×1080 | 1440 | 58–82s，随记、剪贴板、会议、位置便签、简报和语音 |
| `SceneCreativeTools` | 1920×1080 | 1920 | 82–114s，截图、录屏、图片、音频和 PDF |
| `SceneDesktopTools` | 1920×1080 | 1460 | 114–138.3s，混音、键盘、专注、清洁、系统历史和电池 |
| `SceneSettings` | 1920×1080 | 1140 | 138.3–157.3s，窗口、快捷动作、权限、CLI／Skills、Zshell 和整屏合盖 |
| `Scene4Bento` | 1920×1080 | 600 | 独立工具快览预览 |
| `Scene5Outro` | 1920×1080 | 160 | 157.3–160s，品牌、完整安装命令和对应音乐署名 |

相邻两幕有 16 帧叠化：后一幕提前 16 帧在仍不透明的前一幕之上淡入，到名义起点时完全显现。歌曲进度和番茄钟用 `filmFrame()` 换算成全片帧号。分幕合成按名义长度注册，用于无声预览；全片中的布局与工具导览按含叠化的幕长缩放，并保留各幕末态。

## 配乐

两个版本均使用一首完整作品的连续前 160 秒，保留原曲编排，只在首尾淡入淡出。MP3 为 44.1 kHz 立体声、320 kbps，整体降低 2 dB，开头淡入 0.4 秒，155.8–159.6 秒淡出。

- 放克版：[Kevin MacLeod《Funkorama》](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474)。官网播放器采用此版。
- 电影配乐版：[Scott Buckley《The Miracle of Flight》](https://www.scottbuckley.com.au/library/the-miracle-of-flight/)。

两首作品均以 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 发布。片尾、音频元数据与官网保留作者和来源；再分发影片时使用对应署名：

```text
Funkorama by Kevin MacLeod (incompetech.com), licensed under Creative Commons Attribution 4.0.
'The Miracle of Flight' by Scott Buckley - released under CC-BY 4.0. www.scottbuckley.com.au
```

从作者曲目页取得原曲后重新生成（需要 ffmpeg）：

```bash
node tools/make-soundtrack.mjs /absolute/path/Funkorama.mp3 public/audio/zisla-launch.mp3 funk
node tools/make-soundtrack.mjs /absolute/path/The-Miracle-of-Flight.mp3 public/audio/zisla-launch-cinematic.mp3 cinematic
npx remotion render ZislaLaunchFilmCinematic out/zisla-launch-cinematic-1080p60.mp4
npx remotion render ZislaLaunchFilmCinematic4K out/zisla-launch-cinematic-2160p60.mp4
```

时长取自 `src/timeline.ts`，曲目和许可统一保存在 `src/soundtrack.ts`。

## 结构

```
promo/
├── public/audio/        # 配乐
├── src/
│   ├── timeline.ts      # FPS、十幕起止、叠化帧数、filmFrame()
│   ├── soundtrack.ts    # 曲目、作者、来源与许可
│   ├── theme.ts         # 尺寸/颜色/字号，数值取自应用源码
│   ├── motion.ts        # ZislaMotion（岛内，与应用一致）+ FilmMotion（影片层）
│   ├── content.ts       # 全部样例数据与字幕文案（虚构原创）
│   ├── LaunchFilm.tsx   # 十幕编排 + 叠化 + 配乐
│   ├── Root.tsx         # 全片与分幕合成注册
│   ├── components/      # 岛外壳、玻璃、光标、桌面、终端、浮层等通用件
│   ├── modules/         # 岛内模块及 AI 统计、邮件、文件工具、系统监控
│   └── scenes/          # 十幕
└── tools/               # 配乐处理脚本与帧驱动测试
```

## 约定

- 时间只写在 `src/timeline.ts`；跨幕读数用 `filmFrame()` 换算成全片帧。
- 舞台是 1280×720 的逻辑画布，`Stage` 按输出尺寸等比放大（1080p 1.5×、4K 3×）。
- 全部帧驱动：没有 `Math.random`、`Date.now`、CSS transition 或 `@keyframes`，任何一帧单独渲染结果一致。
- 岛内动效用 `ZislaMotion`（参数与应用一致），影片层强调动效用 `FilmMotion`。
- 玻璃质感统一为 `backdrop-filter: blur(24px) saturate(180%)` 加 1px 内描边；`backdrop-filter` 要求祖先不带 opacity 或 filter。
- 样例数据与字幕集中在 `src/content.ts`；只在某一幕出现的演示字符串留在该幕文件里。

## 素材与数据

- 全部虚构原创：任务、文件名、歌曲《Paper Lanterns》及其歌词、城市、日程、笔记、路径，都不来自本机真实数据，也不含受版权保护的歌词。
- 品牌图标直接引用仓库内应用自带资源（lobehub/lobe-icons，MIT）：`mac/Resources/BrandIcons/`；zisla 图标引用 `web/public/assets/zisla-icon.png`，promo 里不存副本。
- 宠物小熊与小鸡直接引用 `mac/Resources/Pets/` 的 Kenney Animal Pack Redux 素材，CC0 1.0；单帧素材使用应用相同的 1.4 秒呼吸动画。
- 两首配乐遵循 CC BY 4.0，作品许可证与仓库代码许可证独立。
- 仓库不提交 Apple 字体。

## 忠于真实界面

尺寸、颜色、弹簧参数都对着应用源码写。以下五处与分镜草稿的描述不同，以真实界面为准：

1. Token 趋势图是最近 7 天、每天一个点（应用里 `AIProgressModuleView` 调 `dailyUsageSeries` 时传的是 `days: 7`），不是 12 小时；`mac/Docs/cli-reference.md` 里的 "12-hour chart" 与当前实现不一致。
2. 专辑封面在岛内是静止的，旋转唱片只出现在岛外的影片特写层。
3. Handoff 托盘的 Finder/Share 入口是标题行的 `Share`、`Show` 按钮加右键菜单，没有悬停操作条。
4. 下载完成后的快捷操作是从顶部落下的岛形横条，不是从右侧滑出的卡片。
5. 随记是左列表 + 右所见即所得编辑器，没有独立的 Markdown 预览区。

## 许可

- Remotion 不是 MIT：它的免费许可只覆盖个人使用、不超过 3 名员工的营利组织、非营利组织等情形，详见 https://www.remotion.dev/docs/license 。
- 本目录其余内容随 zisla 仓库，PolyForm Noncommercial 1.0.0。
