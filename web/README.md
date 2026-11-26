# zisla website

**English** | [简体中文](README.zh-CN.md)

This directory contains the repository's TypeScript website, built with Vite. The homepage keeps concise feature introductions, downloads and the full feature tour; detailed instructions and limits are in Help. Copy supports 17 languages; download links and the changelog match v0.1.25 (2026-11-24).

## User help

The header and footer Help links open `help.html`. Its nine guides cover clipboard, capture, shelf, meetings, AI, media tools, daily briefings, desktop notes/previews, and playback/mixing. Each includes steps, shortcuts, permissions and save locations. Three video excerpts reuse the existing tour with demonstration data and English captions.

Links use `help.html?lang=<siteLocale>#guide-<id>`. Language switching retains the selected guide; old homepage `#help`, `#guide-*` and `#workflow-*` links forward to the help page. Developer links select complete documents in the chosen language. English and Simplified Chinese keep their original paths; the other 15 locales share `docs/locales/<siteLocale>/`. The [language index](../docs/locales/README.md) lists all six documents.

## Run locally

```bash
cd web
npm install
npm run dev
```

Production build:

```bash
npm run build
```

Links currently used by the website:

- Source: https://github.com/wzz6423/zisla
- Release v0.1.25: https://github.com/wzz6423/zisla/releases/tag/v0.1.25
- Apple Silicon DMG: https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-arm64.dmg
- Apple Silicon ZIP: https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-arm64.zip
- Universal DMG: https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-universal.dmg
- Universal ZIP: https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-universal.zip
- Intel DMG: https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-x86_64.dmg
- Intel ZIP: https://github.com/wzz6423/zisla/releases/download/v0.1.25/zisla-v0.1.25-macOS-x86_64.zip
