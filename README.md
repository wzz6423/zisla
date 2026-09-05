# zisla

**English** | [简体中文](README.zh-CN.md)

**zisla is a native macOS workspace that appears when you need it, then gets out of the way.** Move the pointer to the top center of the screen to open one lightweight place for active AI work, media, handoff, downloads, and desktop utilities. Displays without a notch use the same simulated status area.

Current implementation: **macOS 14+**. Apple Silicon is the supported configuration; Intel release packages may work, but compatibility is not guaranteed.

## Why it belongs at the top of your screen

- **On demand, without stealing focus.** Expand it from the top edge, pin it when needed, and keep working in the current app.
- **One place for active work.** See now playing, AI tasks, downloads, timers, mail, system status, and battery details without opening a full dashboard.
- **AI activity without conversation access.** zisla reads only structured events and local activity metadata needed to determine task state. It never reads prompts or answer bodies.
- **Controls remain local.** Modules, clipboard history, and link detection are independent switches; permissions are requested only when a feature is first used.

## What it can do

### Keep desktop work moving

| Capability | What it does |
| --- | --- |
| Now Playing | Shows artwork, title, progress, lyrics, and playback controls; Core Audio can identify the app actually outputting audio when metadata is unavailable. |
| Handoff and sharing | Drop files, media, or links on the top trigger area to keep them in a handoff tray, reveal them in Finder, or open the macOS share menu. |
| Clipboard and notifications | Optionally records local clipboard history, recognizes new links locally, and surfaces media, AI activity, browser downloads, timers, mail, and updates in the collapsed state. An optional copy assistant shows a small island toast after every copy with a rich preview and smart next actions (open, reveal in Finder, search, translate, calculate, save). |
| Everyday workspace | Includes weather, calendar, reminders, Mail.app, Markdown notes backed by Apple Notes, lock-screen information, and optional desktop pets. |

### Make AI work visible

zisla monitors local activity from Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, TRAE, OpenCode, Harnext, WorkBuddy, Doubao, and other supported sources. It shows tasks, status, token trends, contribution heatmaps, and side notices.

For tools without a stable local activity source, `zislactl` lets scripts, CI, and tool hooks report progress, usage, and notifications while keeping protocol state on this Mac. Settings can also detect, install, update, and remove common AI CLIs and manage local Skills. See the [CLI integration reference](mac/Docs/cli-reference.md) for providers and commands.

### Handle the useful small things

| Area | Included tools |
| --- | --- |
| Downloads and documents | Video and audio downloads through `yt-dlp`; local PDF merge, split, rotate, crop, conversion, rendering, text export, watermarks, page numbers, encryption, unlock, and metadata editing. |
| Focus and presentation | Pomodoro timer, alarm, keep-awake mode, idle-sleep prevention, screen and keyboard cleaning, teleprompter, and camera mirror. |
| System and battery | CPU, GPU, memory, disk, network, fan, and battery information, plus cleanup of caches and logs that are safe to remove. |
| Voice input | Global shortcuts for recording and transcription, optional local or remote transcript organization, and local voice history. |

## Get started

### Install the app

Install with Homebrew:

```bash
brew install --cask wzz6423/tap/zisla
```

Or download the latest DMG from [GitHub Releases](https://github.com/wzz6423/zisla/releases) or [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), mount it, and drag `zisla.app` to `Applications`.

After launching, move the pointer to the top center of the current screen, or choose **Show Island** from the menu bar icon. An unsigned preview package may require **Open Anyway** in **System Settings > Privacy & Security** on first launch.

### Update the app

zisla updates itself through Sparkle, so a plain `brew upgrade` leaves the installed app alone. Name the cask when you want Homebrew to do the replacement instead:

```bash
brew upgrade --cask zisla
```

The tap serves stable releases only; preview builds stay on Releases so `brew upgrade` never moves you onto a prerelease. `brew uninstall --cask zisla` removes the app, and `brew uninstall --zap --cask zisla` also trashes its local data.

### Run from source

Swift 6 / Xcode 16+ is required; Command Line Tools alone can also build the project.

```bash
cd mac
swift run zisla
```

The downloader requires `yt-dlp`; `ffmpeg` is optional. Office-to-PDF conversion requires LibreOffice or OpenOffice. Build, test, and packaging instructions are in the [macOS development guide](mac/README.md).

## Designed to stay out of the way

- Supports multiple displays, Spaces, and ordinary full-screen apps without activating or taking focus from the current app.
- The hidden state has no permanent transparent hit-area window and runs no frame loop; global event monitoring and geometry checks trigger expansion.
- Uses one system material and switches to an opaque background when Reduce Transparency is enabled.
- Detects a physical notch from the system safe area; external displays without one use an overlay with the same outline.

See the [architecture and performance design](mac/Docs/architecture.md) for the implementation trade-offs.

## Privacy and permissions

zisla requests a permission only when an enabled feature first needs it. You can disable modules in Settings and revoke authorization in macOS System Settings at any time.

| Scope | Boundary |
| --- | --- |
| AI activity | Reads only structured events and local activity metadata. Prompts and answer bodies are never read. |
| Clipboard and files | Clipboard history, link detection, and the copy assistant are separate local switches; recognition runs entirely on-device, and opening links or running actions happens only after an explicit click or trigger press. Handoff uses security-scoped bookmarks and does not copy the original file. |
| Notes, Mail, and voice | Notes and Mail use AppleScript/JXA with automation authorization. Voice records only while active; transcript organization sends text only to the selected local model, remote provider, or CLI profile. |
| Browser downloads and media | Uses macOS public file-progress information, MediaRemote metadata, and Core Audio output state. It does not read browser history databases or capture audio content. |
| Network | Weather, release checks, downloader requests, and optional remote voice organization access the network only for their respective enabled actions. |

The [macOS guide](mac/README.md#permissions-and-privacy) documents the complete permission and network behavior.

## Documentation

| Document | Purpose |
| --- | --- |
| [macOS development guide](mac/README.md) | Modules, AI integration, dependencies, build, test, permissions, and system limitations. |
| [Architecture and performance design](mac/Docs/architecture.md) | Top-edge triggering, window behavior, concurrency, media, and download safety. |
| [CLI integration reference](mac/Docs/cli-reference.md) | `zislactl` providers, commands, fields, and exit codes. |
| [Signing and release design](mac/Docs/releasing.md) | Signing, notarization, DMGs, update channels, and release acceptance. |
| [Contributing guide](CONTRIBUTING.md) | Development environment, branches, commits, and pull request requirements. |

## Contributing

Issues and pull requests are welcome. Read the [contributing guide](CONTRIBUTING.md) first. Report security issues privately through [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) rather than opening a public issue.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE.md). Noncommercial use is permitted; selling this software, or any other commercial use, is not.
