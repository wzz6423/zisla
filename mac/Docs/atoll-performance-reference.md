# Atoll 展开动画与性能实现参考

调研日期：2026-07-24。本文仅记录公开一手源码中可核验的事实，并给出 zisla 的独立实现建议；**没有复制 Atoll 的 GPL 代码、类型或布局常量**。

## 结论先行

Atoll 的主岛不是通过 `NSPanel` 从屏幕上方位移到目标位置来呈现展开效果。它把窗口的顶边固定在屏幕顶边，窗口尺寸变化时以非 AppKit 动画的 `setFrame` 更新；可见的动效留在 SwiftUI 内容层，通过顶部对齐、裁剪形状、圆角插值和围绕状态值的弹簧动画完成。因此视觉上是“胶囊/刘海面本身展开”，不是“整块窗口从上往下掉下来”。

公开源码本身不是性能基准，不能据此证明 Atoll 在所有机器上都更快。不过它确实实现了几项可减少无效布局、重复状态切换和后台采样的机制，适合独立借鉴到 zisla。

## 核验范围与边界

- 本文以 [Atoll-Labs/Atoll `main` 的 `a971e2c`](https://github.com/Atoll-Labs/Atoll/tree/a971e2c5d36366d6cc66874334660fc34e2c57e6) 为主要快照；同时核验了 [Ebullioscopic/Atoll `dev` 的 `503606c`](https://github.com/Ebullioscopic/Atoll/tree/503606ca34aece08d30d3c86bce50eb5e07a3139)。前者的 `main` 较新，两个仓库的公开源码并不逐文件相同。
- Atoll README 将其描述为按需展开、使用原生 SwiftUI 动画的刘海交互面；这是产品自述，不是帧率或功耗证明：[ReadMe.md:42-61](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/ReadMe.md#L42-L61)。
- Atoll 使用 GPLv3：[LICENSE:1-17](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/LICENSE#L1-L17)。zisla 应只采用下面的通用工程原则并独立实现，不能移植或改写后保留其实质实现。

## 展开为何不是下落动画

| Atoll 中的可核验证据 | 实现含义 | 对 zisla 的最小借鉴 |
| --- | --- | --- |
| 主面板是透明、无边框 `NSPanel`，并禁用 AppKit 自带阴影；窗口本身只承担承载与命中职责：[DynamicIslandWindow.swift:25-58](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/components/Notch/DynamicIslandWindow.swift#L25-L58)。创建窗口时又设置 `animationBehavior = .none`：[DynamicIslandApp.swift:357-392](https://github.com/Ebullioscopic/Atoll/blob/503606ca34aece08d30d3c86bce50eb5e07a3139/DynamicIsland/DynamicIslandApp.swift#L357-L392)。 | 避免系统窗口动画和 SwiftUI 动画同时驱动同一个几何变化。 | `IslandPanel` 不应对展开/收起使用 `animator().setFrame`、`setFrame(..., animate: true)`，也不应叠加 SwiftUI 的位移动画。窗口仅按需要扩容并立即提交，或维持可容纳展开态的稳定 frame。 |
| 重设窗口 frame 时，`newY` 始终按 `screenFrame` 顶边减去当前高度计算，随后调用普通 `setFrame`；同一尺寸不会重复设置：[DynamicIslandApp.swift:535-558](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/DynamicIslandApp.swift#L535-L558)。 | 窗口的顶缘保持锚定；尺寸变化不会转变为整窗向下平移的 AppKit 动画。 | zisla 计算展开 frame 时固定 `maxY`，只改变 width/height；更重要的是在 frame 完全相等时直接返回。 |
| 根视图和外层 frame 都使用 `.top` 对齐：[ContentView.swift:719-728](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/ContentView.swift#L719-L728)。 | 真正被用户看到的表面从顶部锚点生长，而不是作为整体被 `offset(y:)` 推入。 | `IslandRootView`/`IslandSurface` 保留顶部锚点；删除展开收起路径上的 `.move(edge: .top)`、整面 `offset` 或不必要的插入/移除 transition。 |
| 内容面用 `clipShape`、一个 `compositingGroup` 和按状态计算的阴影；`isHovering` 与 `notchState` 分别绑定有限个弹簧/平滑动画：[ContentView.swift:524-566](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/ContentView.swift#L524-L566)。其形状通过 `animatableData` 插值两个圆角：[NotchShape.swift:37-48](https://github.com/Ebullioscopic/Atoll/blob/503606ca34aece08d30d3c86bce50eb5e07a3139/DynamicIsland/components/Notch/NotchShape.swift#L37-L48)。 | 可见动效发生在一个有裁剪边界的面内，状态来源明确，不需要对整个面板做下落。 | zisla 为 surface 建立一个 `isExpanded` 驱动的尺寸、圆角、opacity/轻微 scale 动画。使用单一、临界阻尼附近的 spring；不要将同一 `isExpanded` 同时绑定多个 `.animation`，不要额外 blur/阴影层叠加。 |

### 应采用的 zisla 动效模型

```text
NSPanel：顶边固定，frame 只在状态真正切换时立即更新
    └─ IslandSurface（top anchor）
         └─ clip/mask 形状：紧凑胶囊 <-> 展开面
              ├─ width / height
              ├─ corner radius
              └─ opacity（内容延后极短时间出现）
```

这意味着“展开”是表面变形和内容淡入，不是窗口或内容从 `y < 0` 移动下来。要避免双重动画：AppKit frame 更新不能带动画，SwiftUI 只保留这一条表面状态动画。

## 响应速度与资源控制

### 1. 悬停只切换状态，延迟任务可取消

- 正常命中路径是 SwiftUI `.onHover`；处理函数首先取消旧任务，再根据进入/离开事件创建一个任务：[ContentView.swift:546-580](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/ContentView.swift#L546-L580)、[ContentView.swift:2062-2134](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/ContentView.swift#L2062-L2134)。
- 打开前等待用户配置的最短悬停时间，关闭前等待 100 ms；两个路径在执行前再次检查取消状态、当前展开状态和鼠标状态：[ContentView.swift:2091-2133](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/ContentView.swift#L2091-L2133)。
- 这不是“永不轮询”：在完全藏到屏幕边缘、普通 hover 命中失效时，Atoll 仅为这个回退场景创建 50 ms 轮询任务，并在 teardown 时取消：[ContentView.swift:1918-1974](https://github.com/Ebullioscopic/Atoll/blob/503606ca34aece08d30d3c86bce50eb5e07a3139/DynamicIsland/ContentView.swift#L1918-L1974)。

**zisla 建议：** 普通鼠标移动事件只做纯几何命中与状态去重，绝不读取剪贴板、拉取服务数据、构建 SwiftUI 视图或写磁盘。将展开/收起改为一个可取消的 `Task`（或 generation token）；输入事件新旧状态相同则立即返回。仅当 zisla 确实完全隐藏导致 hit-test 不可用时才增加低频回退检测，并确保窗口销毁时取消。

### 2. 合并尺寸更新，避免无效重绘

- Atoll 对多个设置变化共用一个 150 ms、可取消的 `DispatchWorkItem`，连续变化只留下最后一次：[DynamicIslandApp.swift:138-150](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/DynamicIslandApp.swift#L138-L150)、[DynamicIslandApp.swift:676-712](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/DynamicIslandApp.swift#L676-L712)。
- 真正 resize 前会比较目标与现有 `window.frame.size`，无变化不提交 frame：[DynamicIslandApp.swift:539-558](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/DynamicIslandApp.swift#L539-L558)。

**zisla 建议：** 让 `OverlayCoordinator` 产出一个 `Equatable` 的 presentation snapshot（展开态、tab、内容尺寸、target screen）。只有 snapshot 改变才调用 `IslandPanel`；把配置连发、服务批量通知和连续布局测量收敛为同一个可取消的短 debounce。鼠标事件不参与此 debounce，而是走状态去重后的即时路径。

### 3. 仅在可见且需要时采样

- Atoll 的系统统计采样仅在“刘海已展开且当前 tab 是 stats”时启动；离开 tab 或关闭后延迟停止：[StatsManager.swift:513-548](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/managers/StatsManager.swift#L513-L548)。
- 停止采样时，它会失效计时器，并释放/清空历史缓存、进程统计和 Mach CPU 信息：[StatsManager.swift:579-609](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/managers/StatsManager.swift#L579-L609)。
- 音乐进度 `TimelineView` 在暂停、直播或零播放速率时进入 paused，避免无意义时钟刷新：[NotchHomeView.swift:374-400](https://github.com/Atoll-Labs/Atoll/blob/a971e2c5d36366d6cc66874334660fc34e2c57e6/DynamicIsland/components/Notch/NotchHomeView.swift#L374-L400)。

**zisla 建议：** 为媒体波形、系统监控、时钟、AI 状态刷新建立“模块可见性 + 数据实际变化”门控。收起或离开对应模块即停 timer/display link/订阅，重新可见才恢复；进度时间线在暂停时停止。不要让所有服务变化都广播到岛根视图或每一个列表行。

## 可直接排入 zisla 的最小实现顺序

1. **先消除双重几何动画。** 统一 `IslandPanel` 的顶边锚定和 frame 去重；`IslandSurface` 改为 `isExpanded` 的内部形变，移除向下 move/offset transition。
2. **再收敛事件。** `PointerEdgeMonitor` 只计算命中；`OverlayCoordinator` 为进入、离开和自动收起维护单一可取消任务，所有状态写入做 `guard old != new`。
3. **最后做后台门控。** 逐项停掉收起态不可见模块的定时器、波形、系统采样和昂贵图片/Markdown 渲染；为每个模块保留最后一个轻量 snapshot，重新打开时先显示缓存再异步刷新。
4. **用 Instruments 验证，而不是凭观感判断。** 对“进入热区 -> 完成展开”和“离开 -> 完成收起”分别采样 Core Animation FPS、主线程 CPU、GPU Renderer Utilization、wakeups 及峰值常驻内存；再对折叠态静置 60 秒测基线。只有这些基线下降，才能称为低耗优化完成。

## 不应照搬的部分

- Atoll 的隐藏边缘回退存在 50 ms 轮询，适用于它自己的“完全藏在屏幕外”模式，不应无条件复制到 zisla：[ContentView.swift:1952-1974](https://github.com/Ebullioscopic/Atoll/blob/503606ca34aece08d30d3c86bce50eb5e07a3139/DynamicIsland/ContentView.swift#L1952-L1974)。
- Atoll 自己曾以 [c53034ca `BugFix: Top sliding down`](https://github.com/Ebullioscopic/Atoll/commit/c53034ca9c0d51b4c117a0dbde8bda993a5c2239) 修复过顶部下滑。这个历史证据支持“稳定顶边 + 内容形变”的原则，但不意味着应复刻其当前根容器尺寸补偿。
- Atoll 也曾因 borderless panel 关闭时未清理 20 Hz hover 轮询任务，导致长期运行主线程饱和；修复提交明确记录了该原因：[4d4ca2fd `Atoll: Notch Freeze Fix`](https://github.com/Ebullioscopic/Atoll/commit/4d4ca2fd41db5edd46111d35b70ab0aa2f819532)。当前实现把 hover task、事件 monitor 和回退轮询统一放入确定性 teardown：[ContentView.swift:1937-1974](https://github.com/Ebullioscopic/Atoll/blob/503606ca34aece08d30d3c86bce50eb5e07a3139/DynamicIsland/ContentView.swift#L1937-L1974)。zisla 的每一个 monitor、timer 和 animation completion 也必须有等价的销毁路径。
- Atoll 的主视图仍观察多个全局对象：[ContentView.swift:37-57](https://github.com/Ebullioscopic/Atoll/blob/503606ca34aece08d30d3c86bce50eb5e07a3139/DynamicIsland/ContentView.swift#L37-L57)。因此只能借鉴其开合几何与可见性门控，不能把它当作已验证的全局刷新架构。
- Atoll 的实现同时有许多可选功能和定时源；它的公开源码不构成 zisla 现有卡顿的因果证明。必须先用 zisla 的 Instruments trace 验证主线程热点、layer 数与 wakeups，再做最小改动。
