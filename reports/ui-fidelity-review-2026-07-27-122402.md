# 设计还原度报告

> 生成时间: 2026-07-27 12:24
> 评审工具: ui-checker
> 设计工具: 用户提供截图

**总体得分**: 不适用（未取得修复后的运行时截图）

## 颜色 (不变)

未调整颜色、材质或阴影。

## 间距 (已修复)

首页无卡片时仍会渲染宠物预留、顶部间距、工具栏和模块底部内边距。空态下限从 228pt 改为标准首页的 340pt，避免这些固定 chrome 挤占可视内容区。

## 字体 (不变)

未调整字体、字号或行高。

## 尺寸 (已修复)

仅空首页的高度下限恢复为 340pt；有活动卡片时仍按卡片行数计算高度。

## 圆角/阴影 (不变)

未调整圆角或阴影；增加的空态高度让底部过渡和圆角落在完整面板内。

## 响应式 (已修复)

空首页与标准首页共用高度基准，避免模块切换到无内容首页时被缩短。

## 验证

- `swift build --package-path mac --target Zisla --scratch-path /tmp/zisla-home-empty-build -q`：通过。
- `swift test --package-path mac --filter IslandSurfaceTransformTests --scratch-path /tmp/zisla-home-empty-test -q`：5/5 通过。
- 两个 scratch 构建目录已通过 `swift package reset` 清理。
