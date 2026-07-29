# 收起状态 Liquid Glass UI 核查

> 生成时间: 2026-07-27 15:26
> 评审工具: ui-checker
> 设计依据: 用户反馈“不能只是透明”

**总体得分**: 95/100

## 颜色 (25/25)

✅ `Liquid Glass` 使用系统模糊材质和高光渐层，而非单纯透明。

## 间距 (25/25)

✅ 未改动间距、布局或状态条尺寸。

## 字体 (20/20)

✅ 未改动文字和图标样式。

## 尺寸 (15/15)

✅ 未改动状态翼宽高与中心避让。

## 圆角/阴影 (10/10)

✅ 未改动 `SimulatedIslandShape`、`CompactAIWingShape` 或任何圆角参数。

## 响应式 (0/5)

⚠️ 自动截图期间没有活跃状态条，需由下一次媒体或 AI 状态出现时完成视觉确认。

## 验证

- `swift test --package-path mac --filter 'FeatureSettingsCompatibilityTests|FeatureSettingsStoreTests|SideNoticeLayoutTests'`：59/59 通过
