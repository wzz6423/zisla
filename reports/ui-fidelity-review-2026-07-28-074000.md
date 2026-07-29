# UI 问题排查报告

生成时间：2026-07-28 07:40（Asia/Shanghai）

## 结论

宠物使用的 `IslandPanel` 同时声明跨 Space、全屏辅助和跨应用能力，但错误地使用了 `.stationary` 窗口集合行为。AppKit 将该行为定义为“像桌面窗口一样保持可见且固定”，所以面板不会按预期随应用/Space 切换显示。

## 修复

- 将 `IslandPanel` 的窗口集合行为切换为 `.transient`。
- 保留 `.canJoinAllSpaces`、`.canJoinAllApplications` 与 `.fullScreenAuxiliary`，让宠物在普通应用、不同 Space 和全屏应用中仍可显示。

## 验证

- 新增回归断言，确保宠物面板使用 `.transient` 且不再包含 `.stationary`。
- 完整 SwiftPM 测试被并行开发中的 `ScreenSelectionOverlay`、`AppModel` 接口不匹配阻断；该错误不在本次修改范围内。
