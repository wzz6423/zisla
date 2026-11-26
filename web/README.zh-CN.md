# zisla 官网

[English](README.md) | **简体中文**

这是仓库的 TypeScript 官网，使用 Vite 构建，下载入口和更新日志与当前 macOS Release 保持一致。页面文案也包含 [#372](https://github.com/wzz6423/zisla/pull/372) 的图片文字搜索与 [#373](https://github.com/wzz6423/zisla/pull/373) 的中转工具/素材库工作流；两项功能合并后再部署这批文档和帮助。官网展示 12 个灵动岛模块与 19 项独立能力，包括 9 项图片工具、27 项音频操作、PDF 工具、AI 额度环与模型用量历史、会议倒计时与关联便签、中转站批量操作、自动电源模式、紧凑番茄钟、HDR 与自动滚动截图、应用打开修复和每日简报；同时涵盖录屏人像与美声效果、独立保存目录、定时清理、设置重组、依赖组件每日更新、浏览器真实下载文件名和 Zshell 推荐。近期新增剪贴板来源应用分组、后台清理与岛内反馈、重复安装与更新残留检测、HDR 录屏、Command 方向键便笺导航、AI 额度独立地区、权限状态刷新、应用音量记忆，以及全部保存目录恢复默认。0.1.25 新增工具箱垃圾清理入口，并修复贴图缩放、天气重复标注、打字统计滚动、音频工具可视区域布局和应用音量空闲来源。160 秒功能导览由用户点击后播放。文案覆盖全部 17 种语言，更新日志与 v0.1.25（2026-11-24）一致，系统历史默认保留至手动清空。

## 用户帮助

首页「帮助」连接剪贴板、截图/录屏、中转、会议、AI 接入/额度、媒体工具、每日简报、桌面便签/窗口预览和播放/混音九个指南。每个指南包含入口、步骤、快捷键、权限和保存位置，覆盖全部 17 种官网语言。稳定链接使用 `?lang=<siteLocale>#guide-<id>`；语言切换保留当前指南。三个嵌入片段复用已有导览和演示数据，明确标注片内英文字幕。开发资料在全部 17 种语言下跳转所选语言的完整文档，并显示实际文档语言。英文与简体中文保留原路径，其余 15 种语言的根 README、macOS 指南、架构、CLI 参考、发布指南和贡献指南集中放在 `docs/locales/<siteLocale>/`。[语言索引](../docs/locales/README.md)连接六份文档。

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
