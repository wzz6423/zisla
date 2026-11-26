# zisla website

**English** | [简体中文](README.zh-CN.md)

This directory contains the repository's TypeScript website, built with Vite. Download links and the changelog match the current macOS Release. Page copy also documents the upcoming image-text search and shelf tool/media-library workflows from PRs [#372](https://github.com/wzz6423/zisla/pull/372) and [#373](https://github.com/wzz6423/zisla/pull/373); deploy this documentation and help after both features merge. The site presents 12 island modules and 19 standalone capabilities, including nine image tools, 27 audio operations, PDF tools, AI quota rings and model usage history, meeting countdowns and linked notes, shelf batch actions, automatic power modes, compact Pomodoro controls, HDR and scrolling screenshots, application-opening repair, and daily briefings. It also covers recording portrait and voice effects, independent save folders, scheduled cleanup, reorganized settings, daily dependency updates, actual browser download filenames, and the Zshell recommendation. Recent additions cover clipboard grouping by source application, background cleanup with island feedback, duplicate installation and update-leftover detection, HDR recordings, Command-arrow note navigation, independent AI quota regions, permission status refresh, persistent application volumes, and restoring all save folders to their defaults. The 0.1.25 update adds the Utilities junk-cleanup shortcut and fixes pinned screenshot scaling, duplicate weather labels, typing-statistics scrolling, audio-tool viewport layout, and idle application-volume sources. A 160-second feature tour plays on request. Copy covers all 17 languages, and the changelog matches v0.1.25 (2026-11-24). System history is retained until manually cleared by default.

## User help

The homepage’s Help entry links to nine guides: clipboard, screenshots/recordings, shelf, meetings, AI integration/allowances, media tools, daily briefings, desktop notes/previews, and playback/mixing. Each guide includes its entry point, steps, shortcuts, permissions, and output location in all 17 site languages. Stable links use `?lang=<siteLocale>#guide-<id>`; language switching keeps the selected guide. Three embedded excerpts reuse the existing tour with demonstration data and explicitly label its English video captions. Developer resource links select complete documents in the chosen site language across all 17 locales, with the actual document language visible. English and Simplified Chinese keep their original paths; the other 15 locales mirror the root README, macOS guide, architecture, CLI reference, release guide, and contributing guide under `docs/locales/<siteLocale>/`. The [language index](../docs/locales/README.md) links to all six documents.

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
