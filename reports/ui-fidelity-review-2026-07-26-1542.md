# 灵动岛透明玻璃 UI 验收

生成时间：2026-07-26 15:42

## 已修复

- 顶部为实黑 crown，之后以 64pt 渐变过渡到整块下半区 Liquid Glass。
- 下半区保留 P2 的 `NSVisualEffectView(.hudWindow, .behindWindow)` 透射层，`alphaValue` 固定为 `0.62`，可透出墙纸色彩而不会泛成白色。
- 其上叠加 macOS 原生 `NSGlassEffectView(.clear)`，仅由系统渲染折射和高光，不再使用会在岛面窗口中雾化的 `.regular` 材质，也移除了手绘白色描边。
- 透明玻璃壳接收收起态，在首次展开时立即刷新，并在 0.24 秒遮罩动画结束后再次刷新；不再依赖功能页切换触发 `updateNSView` 才参与合成。
- 展示卡片、笔记编辑框、AI 消息框和 AI 输入框在透明样式下使用统一深色玻璃表面。
- 透射视图保持挂载，展开或收起仅改变遮罩，避免重建时闪现。

## 验证

- `swift build --package-path mac --scratch-path /tmp/zisla-liquid-shell-build --product zisla` 通过。
- `swift test --package-path mac --scratch-path /tmp/zisla-liquid-shell-test-build --filter 'FeatureSettingsCompatibilityTests|IslandSurfaceTransformTests'` 通过，36 个测试成功。
- `make run` 已在 macOS 27 实际桌面合成环境中启动最新构建并截图检查。
- 固定首次展开态且不切换功能页时，玻璃壳已直接显示。
- `git diff --check` 通过。

## 残余风险

实际桌面中壁纸和其下窗口内容不同会改变折射色彩；最终视觉验收以透明玻璃样式下的展开态为准。
