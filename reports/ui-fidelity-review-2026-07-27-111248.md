# 设计还原度报告

> 生成时间: 2026-07-27 11:12
> 评审工具: ui-checker
> 设计工具: 用户提供截图

**总体得分**: 不适用（未取得运行后截图）

## 颜色 (不变)

未调整颜色、渐变或材质 token。

## 间距 (已修复)

首页无卡片时，原高度仅覆盖顶部内容，黑色到磨砂玻璃的过渡会在底部圆角前结束。空态现在至少保留 228pt 的展开高度。

## 字体 (不变)

未调整字体、字号或行高。

## 尺寸 (已修复)

小工具的展开高度由 360pt 提高到 460pt；PDF 的展开高度由 520pt 提高到 600pt，面板宽度统一为 860pt，使顶栏工具栏保持完整展示。

## 圆角/阴影 (已修复)

空首页已为 132pt 顶部黑色区、60pt 过渡区及底部圆角保留足够空间，不再在过渡中截断。

## 响应式 (已修复)

PDF 使用与首页一致的 860pt 面板宽度，避免宽度不足时顶栏模块入口收起。

## 验证

- `swift build --package-path mac --target Zisla --scratch-path /tmp/zisla-build-empty-toolbar -q`：通过。
- `swift test --package-path mac --filter IslandSurfaceTransformTests --scratch-path /tmp/zisla-test-surface-empty-toolbar -q`：5/5 通过。
- `swift test --package-path mac --filter ScreenLayoutTests --scratch-path /tmp/zisla-test-layout-empty-toolbar -q`：18/18 通过。

三个 scratch 目录均已执行 `swift package reset` 清理。
