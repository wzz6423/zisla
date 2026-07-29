# 收起状态背景 UI 核查

> 生成时间: 2026-07-27 15:10
> 评审工具: ui-checker
> 设计依据: 用户截图与收起状态背景设置

**总体得分**: 100/100

## 颜色 (25/25)

✅ `Liquid Glass` 由外层状态条的材质负责；内层 AI、媒体、下载和状态翼不再覆盖黑色填充。

## 间距 (25/25)

✅ 未改动布局、内边距或状态条尺寸。

## 字体 (20/20)

✅ 未改动文字和图标样式。

## 尺寸 (15/15)

✅ 未改动宽度、高度或中心避让空间。

## 圆角/阴影 (10/10)

✅ 未改动 `SimulatedIslandShape`、`CompactAIWingShape` 或其圆角参数。

## 响应式 (5/5)

✅ `刘海` 仍使用原有黑色内层填充；`Liquid Glass` 仅改变收起状态的背景可见性。

## 验证

- `swift test --package-path mac --filter 'FeatureSettingsCompatibilityTests|FeatureSettingsStoreTests|SideNoticeLayoutTests'`：59/59 通过
