# zisla 发布宣传片

60 秒、60 fps 的 zisla 产品宣传片，用 [Remotion](https://www.remotion.dev/) 逐帧渲染：React + TypeScript + Tailwind CSS，同一套时间轴输出 1080p 与 4K 两个合成，配乐采用 Scott Buckley 的《Origami》连续首分钟（CC BY 4.0）。岛的高度、颜色、弹簧参数都取自应用源码（`mac/Sources/Zisla/DesignSystem.swift`、`MotionDesign.swift`），不是另起一套设计。

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
- `out/` 已忽略，成片不入库。
- 逐帧渲染，任何一帧都能单独渲染；单帧 PNG 可逐字节复现，整片 mp4 因编码器不保证逐字节一致。
- 工程不分发字体，字体栈是系统字体，因此在 macOS 上渲染才是 SF Pro。

## 合成与时间轴

| 合成 id | 尺寸 | 帧数 | 内容 |
| --- | --- | --- | --- |
| `ZislaLaunchFilm` | 1920×1080 | 3600 | 全片，60 fps，60 秒，带配乐 |
| `ZislaLaunchFilm4K` | 3840×2160 | 3600 | 同一部影片，画布放大到 3 倍 |
| `Scene1Awakening` | 1920×1080 | 480 | 0–8s，顶部触发区展开顶栏 |
| `Scene2AICenter` | 1920×1080 | 720 | 8–20s，AI 指挥中心、按模型用量、网关余额与隐私护盾 |
| `Scene3Flow` | 1920×1080 | 780 | 20–33s，媒体、Handoff 托盘、下载快捷操作 |
| `SceneMail` | 1920×1080 | 600 | 33–43s，查看邮件、撰写、发送与完成反馈 |
| `Scene4Bento` | 1920×1080 | 600 | 43–53s，日常模块、截图录屏、文件工具与系统监控 |
| `Scene5Outro` | 1920×1080 | 420 | 53–60s，品牌、安装命令与音乐署名 |

相邻两幕有 16 帧叠化：后一幕提前 16 帧在仍不透明的前一幕之上淡入，到名义起点时刚好完全显现。跨幕连续的读数（歌曲进度、番茄钟）按全片帧号算，用 `filmFrame()` 换算。分幕合成用于单独预览：除第一幕外，它的第 0 帧是全片中该幕"名义起点 − 16 帧"（叠化起点），画面长度是名义时长，不带音频。

## 配乐

使用 [Scott Buckley《Origami》](https://www.scottbuckley.com.au/library/origami/) 的连续首分钟，保留原曲的旋律、节奏与编曲变化，不循环、不拼接、不叠加逐幕提示音。成片音频为 60 秒、44.1 kHz 立体声、320 kbps MP3，约 2.4 MB；整体降低 2 dB，开头淡入 0.4 秒，55.8–59.6 秒淡出。配乐只挂在两个全片合成上。

原曲由作者以 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 发布。音乐文件保留作者、曲名、来源、许可和编辑说明，片尾也有署名；发布影片时将下面这行放进视频介绍：

```text
'Origami' by Scott Buckley - released under CC-BY 4.0. www.scottbuckley.com.au
```

编辑说明：截取连续首分钟、整体降低 2 dB、开头与结尾淡入淡出。

重新生成时先从作者的曲目页取得原曲，再运行（需要 ffmpeg）：

```bash
node tools/make-soundtrack.mjs /absolute/path/Origami.mp3
```

可选第二个参数指定输出 MP3 路径。时间长度取自 `src/timeline.ts`，曲目和许可信息统一保存在 `src/soundtrack.ts`。

## 结构

```
promo/
├── public/audio/        # 配乐
├── src/
│   ├── timeline.ts      # FPS、六幕起止、叠化帧数、filmFrame()
│   ├── soundtrack.ts    # 曲目、作者、来源与许可
│   ├── theme.ts         # 尺寸/颜色/字号，数值取自应用源码
│   ├── motion.ts        # ZislaMotion（岛内，与应用一致）+ FilmMotion（影片层）
│   ├── content.ts       # 全部样例数据与字幕文案（虚构原创）
│   ├── LaunchFilm.tsx   # 六幕编排 + 叠化 + 配乐
│   ├── Root.tsx         # 八个合成注册
│   ├── components/      # 岛外壳、玻璃、光标、桌面、终端、浮层等通用件
│   ├── modules/         # 岛内模块及 AI 统计、邮件、文件工具、系统监控
│   └── scenes/          # 六幕
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
- 配乐《Origami》由 Scott Buckley 创作，遵循 CC BY 4.0；它的许可证与仓库代码许可证独立。
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
