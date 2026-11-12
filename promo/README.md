# zisla 发布宣传片

50 秒、60 fps 的 zisla 产品宣传片，用 [Remotion](https://www.remotion.dev/) 逐帧渲染：React + TypeScript + Tailwind CSS，同一套时间轴输出 1080p 与 4K 两个合成，带一段原创合成的配乐。岛的高度、颜色、弹簧参数都取自应用源码（`mac/Sources/Zisla/DesignSystem.swift`、`MotionDesign.swift`），不是另起一套设计。

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

类型检查：

```bash
npm run typecheck
```

- 首次渲染时 Remotion 会自行取得 Chrome Headless Shell，放进 `node_modules/.remotion/`。
- `out/` 已忽略，成片不入库。
- 逐帧渲染，任何一帧都能单独渲染；单帧 PNG 可逐字节复现，整片 mp4 因编码器不保证逐字节一致。
- 工程不分发字体，字体栈是系统字体，因此在 macOS 上渲染才是 SF Pro。

## 合成与时间轴

| 合成 id | 尺寸 | 帧数 | 内容 |
| --- | --- | --- | --- |
| `ZislaLaunchFilm` | 1920×1080 | 3000 | 全片，60 fps，50 秒，带配乐 |
| `ZislaLaunchFilm4K` | 3840×2160 | 3000 | 同一部影片，画布放大到 3 倍 |
| `Scene1Awakening` | 1920×1080 | 480 | 0–8s，顶部触发区展开顶栏 |
| `Scene2AICenter` | 1920×1080 | 720 | 8–20s，AI 指挥中心与隐私护盾 |
| `Scene3Flow` | 1920×1080 | 780 | 20–33s，媒体、Handoff 托盘、下载快捷操作 |
| `Scene4Bento` | 1920×1080 | 600 | 33–43s，Bento Grid 与性能指标 |
| `Scene5Outro` | 1920×1080 | 420 | 43–50s，品牌与安装命令 |

相邻两幕有 16 帧叠化：后一幕提前 16 帧在仍不透明的前一幕之上淡入，到名义起点时刚好完全显现。跨幕连续的读数（歌曲进度、番茄钟）按全片帧号算，用 `filmFrame()` 换算。分幕合成用于单独预览：除第一幕外，它的第 0 帧是全片中该幕"名义起点 − 16 帧"（叠化起点），画面长度是名义时长，不带音频。

## 配乐

配乐是脚本合成的原创音频，不含任何第三方素材：`tools/make-soundtrack.mjs`（固定随机种子，结果可复现）用正弦叠加与噪声写出 `public/audio/zisla-launch.mp3`（50 秒、44.1 kHz 立体声、192 kbps，约 1.2 MB）。96 BPM、A 小调，和声 Am9–Fmaj7–C–G 走两遍、再收在 Dm–Am；第二幕起低频脉冲、第三幕起碎拍、第四幕起拨弦，8/20/33/43 秒（各幕落点）各有一声铃与一记气声，末尾 2.1 秒淡出。配乐只挂在 `ZislaLaunchFilm` / `ZislaLaunchFilm4K` 上。

重新生成：

```bash
node tools/make-soundtrack.mjs public/audio/zisla-launch.wav
```

```bash
ffmpeg -i public/audio/zisla-launch.wav -c:a libmp3lame -b:a 192k public/audio/zisla-launch.mp3
```

编曲参数（和弦表、各层增益、提示音时间点）都在脚本顶部的常量里，改完重新生成即可。和弦表每个和弦占 5 秒，时间点与 `src/timeline.ts` 的幕起点对齐。

## 结构

```
promo/
├── public/audio/        # 配乐
├── src/
│   ├── timeline.ts      # FPS、五幕起止、叠化帧数、filmFrame()
│   ├── theme.ts         # 尺寸/颜色/字号，数值取自应用源码
│   ├── motion.ts        # ZislaMotion（岛内，与应用一致）+ FilmMotion（影片层）
│   ├── content.ts       # 全部样例数据与字幕文案（虚构原创）
│   ├── LaunchFilm.tsx   # 五幕编排 + 叠化 + 配乐
│   ├── Root.tsx         # 七个合成注册
│   ├── components/      # 岛外壳、玻璃、光标、桌面、终端、浮层等通用件
│   ├── modules/         # 六个岛内模块：Home / AI / Agenda / Shelf / Clipboard / Notes
│   └── scenes/          # 五幕
└── tools/               # 配乐生成脚本
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
- 配乐由 `tools/make-soundtrack.mjs` 合成，不含任何第三方音乐或采样。
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
