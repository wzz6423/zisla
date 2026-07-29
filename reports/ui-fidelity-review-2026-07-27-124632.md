# UI 检查记录

> 生成时间: 2026-07-27 12:46
> 评审依据: 用户截图与 SwiftUI 布局实现

**总体结果**: 已修复

## 布局

- 扩展态宠物从 `IslandSurface` 的蒙版内容移到独立侧边槽位，左、右侧各保留 8pt 与岛面的间隔。
- 宠物不再占用首页正文的顶部空间，岛面内的工具栏和运行时间保持原有可用宽度。
- 无卡片首页按工具栏实际高度收缩；有卡片时按 72pt 卡片行高和 8pt 行距计算高度。

## 响应式

- 扩展面板仅在宠物启用时增加 44pt 宽度。
- 可用宽度不足完整侧边槽位时隐藏扩展态宠物，避免将宠物重新放回岛面或发生裁剪。

## 验证

- `swift build --package-path mac --target Zisla` 通过。
- `swift test --package-path mac --filter 'IslandSurfaceTransformTests|CollapsedPetLayoutTests'` 通过，7/7 用例成功。
