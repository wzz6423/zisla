# Zisla UI 设计系统优化 · 2026-07-23

> 执行者：UI Designer（像素君）
> 范围：`mac/Sources/Zisla/` 视图层（SwiftUI 灵动岛 + 设置窗口）

## 概述

按前一轮 UI 评审的建议，落地了一轮以「设计系统优先」为指导的优化，核心是建立**单一令牌来源**，
再以此为基准统一各模块的配色、字号、组件与状态语义。新增文件 `Sources/Zisla/DesignSystem.swift`。

## 1. 设计令牌与基础组件（新增 `DesignSystem.swift`）

| 令牌/组件 | 作用 | 替代了 |
| --- | --- | --- |
| `ProviderBrand.color(for:)` | AI 厂商品牌色**唯一来源** | `AIProgressModuleView.providerColor` 与 `AIMascotIdentity.tint` 两处不一致的硬编码 |
| `Color.fillCard / fillControl / strokeCard / dividerSubtle / accentTint` | 表面/描边/分隔/激活底 | 各处 `Color.primary.opacity(0.06/0.08/0.09…)` 散值 |
| `Color.zislaError/Warning/Success/Info` | 语义色 | 各处混用的 `.red/.orange/.green/.cyan` |
| `Font.islandMicro`（9pt 下限） | 可阅读微文案字号 | 7 / 7.5 / 8pt 过小字号 |
| `Hairline` | 细分隔线 | `Divider().overlay(Color.primary.opacity(0.06))` 重复 |
| `IconButton` / `IconButtonLabel`（`.compact`/`.regular`） | 统一圆形图标按钮 | `IconButton`、`CompactMediaButton`、`CompactMediaControlLabel`、`ModuleSelector` 四套实现 |
| `EmptyState` | 统一空状态 | 各模块自绘空态 / `ContentUnavailableView` |

## 2. 具体改动

### 配色一致性
- **厂商品牌色合并**：Claude/Codex/Gemini/GPT/Qwen/Coder 此前在进度条与图标两处数值不同
  （如 GPT `0.27,0.78,0.55` vs `0.42,0.82,0.72`），现统一引用 `ProviderBrand`。
- **语义色统一**：Download 失败 `orange → red`（`zislaError`）；Settings 更新状态、
  Agenda 天气/授权、SystemMonitor 结果等改用 `zisla*` 语义令牌。
- **拖放高亮统一**：Shelf 容器与中转肩部 targeted 态统一为 `accent 0.12` 填充 + `accent` 描边。

### 组件统一
- 媒体控制按钮（播放/上下首/收藏/播放模式）→ `IconButton(size: .compact)`，
  播放模式菜单标签 → `IconButtonLabel(size: .compact)`。
- 模块选择器 → `IconButtonLabel(dimmedWhenInactive: true)`；选中态由「白底+主色图标」
  改为「强调色底+强调色图标」，与固定按钮的激活态一致。
- 移除 `IslandSurface.swift` 中旧的 `IconButton`（迁移至 `DesignSystem.swift`）。

### 字号下限
- 将 7 / 7.5 / 8pt 的可阅读微文案统一到 9pt（`islandMicro`）：Token 趋势图轴标、
  图例、热力图图例、厂商徽标、运行时长、进度时间、星期标签、中转提示副标题、SystemMonitor 详情。
- 同步放宽受限 frame 高度（如进度行 `10→12`、状态行 `11→12`），避免裁切。
- 进度时间文字 `.tertiary → .secondary`，改善玻璃面板上的可读对比。

### 空状态统一
- Shelf（中转站为空）、AI 运行任务（暂无活动任务）、AI 用量（暂无 Token 用量）、
  Agenda（当天暂无事项）均改用 `EmptyState`，图标尺度/字号/配色一致。

### 数据可视化
- **热力图相对归一**：强度按当前 24 周窗口内的最大单日 token 分四档（≤25%/50%/75%/100%），
  取代原先绝对阈值 50M/100M/150M/200M——后者对多数用户恒为最浅档，几乎不传递信息。
  图例改为「少 ▢▢▢▢ 多 · {实际最大值}」。Core 层 `ContributionIntensity.classify`
  与阈值及其测试保持不变，仅视图层改动。

### 评估后保持现状（注明）
- **ShareLink**：`ShelfModuleView` 的 `ShareLink` 已用自定义 Image 标签 + `.plain` 样式，
  与同级 folder 按钮一致，未强行替换为 `NSSharingServicePicker`（避免无谓风险）。
- **命中区**：在 240pt 宽、30pt 高工具条的紧约束下，28/24pt 命中区对 macOS 指针可接受，
  未强行放大（放大需级联调整工具条高度，易裁切）。
- **玻璃 scrim**：未对玻璃体加暗化层（视觉改动大）；改以提升关键微文案对比的方式处理。
  如后续需进一步保证 WCAG AA，可在 `IslandSurface` 玻璃层加一层可控暗化 scrim。

## 3. 变更文件清单

新增：
- `Sources/Zisla/DesignSystem.swift`

修改（视图层）：
- `Sources/Zisla/AIProgressModuleView.swift`
- `Sources/Zisla/AgendaModuleView.swift`
- `Sources/Zisla/DownloadModuleView.swift`
- `Sources/Zisla/IslandRootView.swift`
- `Sources/Zisla/IslandSurface.swift`
- `Sources/Zisla/NowPlayingHeader.swift`
- `Sources/Zisla/SettingsView.swift`
- `Sources/Zisla/ShelfModuleView.swift`
- `Sources/Zisla/SystemMonitorView.swift`
- `Sources/Zisla/AIMascotView.swift`

未改动：`ZislaCore` / `ZislaKit`（热力图归一纯视图层；`classify` 与阈值、测试保持不变）。

## 4. 构建验证说明

本机构建环境为 beta CommandLineTools（macosx27.0，无 Xcode），存在两个与本次改动无关的
环境性阻塞：
1. 显式模块模式下 `SwiftUIMacros` 插件缺失 → `@State`/`@StateObject` 无法展开（全项目性，
   报错点 `SystemMonitorView` 的 `@State` 为既有代码，非本次触碰）。
2. 非显式模式下，工作区既有未提交改动（如 `ZislaCore/Weather.swift` 的插值写法）报解析错。

核查结论：显式模块构建中除上述环境性宏插件错误外，**未报告任何本次改动文件的类型错误**；
已确认无对已移除符号（`CompactMediaButton` / `CompactMediaControlLabel` / `legendLabel`）
的悬挂引用。建议在正常 Xcode / 稳定工具链环境构建确认。
