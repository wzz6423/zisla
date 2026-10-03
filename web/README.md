# zisla 官网

这是仓库根目录下的 TypeScript 官网，使用 Vite 构建，页面文案和下载入口与仓库当前 macOS Release 保持一致。官网会同步已发布的 Zed Agent 监控、截图标注导出、键盘音效、全局键盘监听和本地输入统计等能力。

## 本地运行

```bash
cd web
npm install
npm run dev
```

生产构建：

```bash
npm run build
```

当前官网使用的链接：

- 源码：https://github.com/wzz6423/zisla
- Release v0.1.14：https://github.com/wzz6423/zisla/releases/tag/v0.1.14
- Apple 芯片 DMG：https://github.com/wzz6423/zisla/releases/download/v0.1.14/zisla-v0.1.14-macOS-arm64.dmg
- Apple 芯片 ZIP：https://github.com/wzz6423/zisla/releases/download/v0.1.14/zisla-v0.1.14-macOS-arm64.zip
- Universal 与 Intel 安装包：https://github.com/wzz6423/zisla/releases/tag/v0.1.14

## 项目介绍动画

`showcase.html` 是第二个构建入口，输出为 `/showcase.html`。它用 three.js 渲染一段约 54 秒的分章动画，作为官网的动态版本；营销首页不加载 three.js，动画代码按需分包。

```bash
npm run dev     # http://localhost:5173/showcase.html
npm run build
npm run verify:showcase   # 无头浏览器冒烟测试（需先 npm run build）
```

验证与调试脚本（均使用系统 Chrome，无需下载 Playwright 浏览器）：

```bash
node scripts/capture-showcase.mjs     # 每章一张 PNG，输出到 web/showcase-frames/
node scripts/capture-responsive.mjs   # 五种窗口尺寸，输出到 web/showcase-responsive/
node scripts/probe-showcase.mjs 33    # 打印某一时刻的场景状态
node scripts/probe-chapters.mjs 33    # 打印章节按钮的高亮与文案
```

`verify:showcase` 会遍历整条时间轴、校验五个章节都真的有可见物体、拖动进度条、
验证播放/暂停/重播与数字键跳章，并在 1920×1080 到 360×640 之间检查画布尺寸；
任何控制台报错、页面异常或请求失败都会让它退出码非零。

### 章节结构

| # | id | 时长 | 内容 |
| --- | --- | --- | --- |
| 1 | `opening` | 7.4s | 字标与岛屿从粒子场中浮现 |
| 2 | `context` | 9.2s | 六块虚构来源面板散落，随后汇聚 |
| 3 | `features` | 14.4s | 托盘展开，六个模块卡片依次亮起 |
| 4 | `highlights` | 14.4s | 四条技术主张，附「展开不抢焦点」实证 |
| 5 | `outro` | 8.6s | 收起为常态胶囊，显示结束卡片 |

### 实现要点

- **单一时间源**：所有动画都是时间轴位置的纯函数，不累加帧增量。因此拖动进度条与正常播放的画面完全一致。
- **章节交叉淡化**：相邻章节重叠 0.9s，切点不会出现空帧；权重降到 0 的章节会整组卸载，不再产生绘制开销。
- **相机轨道**：13 个关键帧，Catmull-Rom 插值保证过关键帧时速度连续。
- **文案**：`script.ts` 以 `en` 为完整基底，其余语言为深度部分覆盖，未翻译的句子回退英文而不是留空。语言选择复用官网的 `resolvePreferredLocale`。
- **无障碍**：`prefers-reduced-motion` 下不自动播放、不做相机呼吸位移，并显示提示；快捷键支持空格、方向键、数字键跳转章节、`F` 全屏。
- **文案真实性**：按 `PRODUCT.md` 的要求，动画不使用本机真实数据、路径或标识，只用中性虚构内容，也不堆叠 SaaS 式卡片墙。

### 目录

```
src/showcase/
  main.ts       入口：语言解析、装配、生命周期
  player.ts     渲染循环、场景挂载与逐帧姿态
  transport.ts  播放时钟（播放/暂停/拖动/跳转）
  chapters.ts   章节定义与权重采样
  director.ts   相机关键帧轨道
  stage.ts      渲染器、灯光、后处理
  island.ts     灵动岛几何与材质（跨章节复用）
  motes.ts      共享粒子场
  textures.ts   Canvas 生成的文字与光晕贴图
  overlay.ts    DOM 标题层与控制条
  math.ts       缓动与工具函数
  scenes/       五个章节各自独立的场景模块
```