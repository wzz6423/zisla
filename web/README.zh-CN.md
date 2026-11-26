# zisla 官网

[English](README.md) | **简体中文**

这是仓库的 TypeScript 官网，使用 Vite 构建。首页保留简洁的功能介绍、下载和完整功能导览；详细步骤与使用限制在帮助页查看。文案覆盖 17 种语言，下载入口与更新日志对应 v0.1.25（2026-11-24）。

## 用户帮助

首页「帮助」打开独立的 `help.html`，提供剪贴板、截图/录屏、中转、会议、AI、媒体工具、每日简报、桌面便签/窗口预览和播放/混音九组指南。每组包含步骤、快捷键、权限和保存位置。三个视频片段复用原导览，使用演示数据和英文字幕。

链接格式为 `help.html?lang=<siteLocale>#guide-<id>`。切换语言保留当前指南；旧首页的 `#help`、`#guide-*` 和 `#workflow-*` 链接转入帮助页。开发资料按所选语言打开完整文档。英文与简体中文保留原路径，其余 15 种语言集中在 `docs/locales/<siteLocale>/`。[语言索引](../docs/locales/README.md)列出六份文档。

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
- Release v0.1.25：https://github.com/wzz6423/zisla/releases/tag/v0.1.25
- Apple 芯片 DMG：https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-arm64.dmg
- Apple 芯片 ZIP：https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-arm64.zip
- Universal DMG：https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-universal.dmg
- Universal ZIP：https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-universal.zip
- Intel DMG：https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-x86_64.dmg
- Intel ZIP：https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-x86_64.zip
