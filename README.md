# zisla

**English** | [简体中文](README.zh-CN.md)

zisla is a native macOS dynamic workspace that turns the limited space at the top of the screen into a lightweight, on-demand workbench. It surfaces information and actions when needed, then stays out of the way.

It is useful for Mac users who want to make better use of the notch area, work with several AI tools, or keep common desktop actions in one place. Displays without a notch are supported through a simulated status area with the same outline.

> The current implementation targets macOS. The repository is organized by platform so future platforms can share the product direction while using native interaction patterns and technology stacks.

## Why zisla

- **Information when it matters:** Move the pointer to the top center of the screen to expand the island; move it away to collapse it without taking focus from the current app.
- **A desktop-top workflow:** Access media controls, file handoff, browser and native download progress, calendar, mail, system status, battery details, and focus timers in one place.
- **Visible AI activity:** Aggregate tasks, progress, and usage trends from supported AI CLIs and desktop tools without reading conversation content.
- **Your controls stay yours:** Modules can be toggled independently; clipboard history and link detection can be disabled separately; permissions are requested only when a feature is first used.

## Features

### Top-of-screen workflows

| Capability | Description |
| --- | --- |
| Now Playing | Shows artwork, title, progress, and playback controls; when metadata is missing, it can identify the app that is actually outputting audio. |
| File handoff and sharing | Drop files, media, or links on the top trigger area to put them in the handoff tray, reveal them in Finder, or open the macOS share menu. |
| Clipboard | Optionally records clipboard history and filters it by image, URL, or file; link detection is independent and only recognizes new links locally. |
| Status and notifications | Shows media, AI activity, browser and native downloads, focus timers, new mail, and updates in the collapsed state, with configurable priority, display, and duration. |
| Desktop pets | Optionally displays a pet in the island and configures its position independently. |

### AI workflows

| Capability | Description |
| --- | --- |
| AI activity monitoring | Detects local activity from Codex, Claude Code, GitHub Copilot, Kimi Code, Gemini, Grok, Qwen Code, Qoder, TRAE, OpenCode, Harnext, WorkBuddy, Doubao, and other supported sources, then shows task lists, status, token trends, contribution heatmaps, and side notices. |
| Local status protocol | Ships `zislactl` so scripts, CI, and other tools can report progress, usage, and notifications. The protocol and state stay on this Mac. |
| CLI and Skills management | Detects, installs, updates, and removes common AI CLIs and manages local Skills from Settings. |
| Voice input | Records and transcribes through a global shortcut, optionally organizes the transcript with a local or remote model, and manages local voice history in Settings. |

AI monitoring reads only structured events and local activity metadata needed to determine task state. **It never reads prompts or answer bodies.** Tools without a stable local activity source can report through `zislactl`; supported providers, integration methods, and commands are documented in the [CLI integration reference](mac/Docs/cli-reference.md).

### Everyday information and communication

| Capability | Description |
| --- | --- |
| Weather, calendar, and reminders | Shows weather for the current location and up to six saved locations; view, create, and delete calendar events and reminders, and mark reminders complete. |
| Mail | Reads enabled Mail.app accounts to view inboxes, mark messages read, reply, compose, and move messages to the trash. |
| Markdown notes | Uses Apple Notes as the data source for viewing, editing, creating, and deleting notes with live Markdown preview; drafts are written back automatically. |
| Lock-screen information | Configures lock-screen text, lunar dates, and related status information. |

### Utilities

| Capability | Description |
| --- | --- |
| Video and audio downloads | Paste a link and use `yt-dlp` to download to the default or a chosen directory; without `ffmpeg`, AVFoundation can wrap compatible media tracks natively. |
| PDF tools | Merge, split, rotate, crop, convert images and Office files, render pages, export text, add text and image watermarks or page numbers, encrypt, unlock, and edit metadata locally. |
| Toolbox | Provides a Pomodoro timer, alarm, keep-awake mode, idle-sleep prevention, screen and keyboard cleaning, teleprompter, camera mirror, and a confirmed trash-emptying action. |
| System status and cleanup | Shows CPU, GPU, memory, disk, network, and fan status and cleans caches and logs that are safe to remove. |
| Battery center | Shows charge flow, health, cycles, temperature, capacity, current, voltage, charger information, and readable battery levels for Bluetooth accessories and trusted Apple mobile devices. |

## Interaction and performance

- Supports multiple displays, Spaces, and ordinary full-screen apps without activating or taking focus from the current app when expanded.
- The expanded panel can be pinned to the top of the screen; pinned panels remain passive while controls can still receive keyboard focus.
- The collapsed state creates no permanent transparent hit-area window and runs no frame loop; global event monitoring and geometry checks trigger expansion.
- Uses a single system material and switches to an opaque background when Reduce Transparency is enabled.
- Infers a physical notch from the system safe area; external displays without a notch use an overlay that simulates the status area.

See the [architecture and performance design](mac/Docs/architecture.md) for the trade-offs behind these choices.

## Quick start

### Requirements

- macOS 14 or later
- Apple Silicon is the supported configuration

Intel Macs may have usable release packages, but compatibility is not guaranteed. macOS versions before 14 are unsupported.

### Install the app

Download the latest DMG from [GitHub Releases](https://github.com/wzz6423/zisla/releases) or [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), mount it, and drag `zisla.app` to `Applications`.

After the first launch, move the pointer to the top center of the current screen to expand the island, or choose “Show Island” from the menu bar icon. An unsigned preview package may require **Open Anyway** in **System Settings > Privacy & Security** the first time it opens.

### Run from source

The development environment requires Swift 6 / Xcode 16+; Command Line Tools alone can also build the project.

```bash
cd mac
swift run zisla
```

The downloader requires `yt-dlp`; `ffmpeg` is optional. Office-to-PDF conversion requires LibreOffice or OpenOffice. Installation, build, test, and packaging commands are in the [macOS development guide](mac/README.md).

## Permissions, data, and network

zisla requests a system permission only when an enabled feature is first used. Modules can be disabled in Settings and authorization can be revoked in macOS System Settings at any time.

| Scope | Use |
| --- | --- |
| Calendar and Reminders | Reads and manages events and reminders you authorize. |
| Location | Uses a one-time location request for default weather and does not track continuously; additional locations can be saved manually. |
| Notes and Mail | Uses AppleScript/JXA to interact with Notes and Mail.app; automation authorization is required, and reading the local Mail index may require Full Disk Access. |
| Microphone, speech recognition, and organizer models | Records and transcribes only while voice input is actively used; an organizer sends transcript text only to the local model, remote provider, or CLI profile selected by the user. Credentials stay in a private database. |
| Bluetooth and Apple mobile devices | Reads accessory battery data exposed by macOS and trusted device battery levels only when the battery page is open. |
| Camera and input monitoring | Uses the camera only for the mirror; custom voice shortcuts and keyboard cleaning may require Input Monitoring. |
| Files and Downloads | Uses security-scoped bookmarks for user-selected directories; file handoff does not copy the original. |
| Clipboard | Clipboard history and link detection are independent switches; links are recognized locally and are never automatically uploaded, downloaded, cleared, or written back. |
| Browser downloads | Uses macOS public file-progress information and does not read browser history databases or make network requests to identify progress. |
| Network | Weather uses Open-Meteo, WeatherKit, and relevant public alert services; update checks use GitHub/Gitee Release APIs; the downloader contacts a site only after you start a download; voice organization contacts a remote provider only when enabled. |

The media module gets metadata through MediaRemote and checks actual audio output with Core Audio; it does not capture audio content. See the [permissions and privacy section of the macOS guide](mac/README.md#permissions-and-privacy) for more boundaries and limitations.

## Documentation and development

| Document | Purpose |
| --- | --- |
| [macOS development guide](mac/README.md) | Modules, AI integration, dependencies, build, test, permissions, and system limitations. |
| [Architecture and performance design](mac/Docs/architecture.md) | Top-edge triggering, window behavior, concurrency, media, and download safety. |
| [CLI integration reference](mac/Docs/cli-reference.md) | `zislactl` providers, commands, fields, and exit codes. |
| [Signing and release design](mac/Docs/releasing.md) | Signing, notarization, DMGs, update channels, and release acceptance. |
| [Contributing guide](CONTRIBUTING.md) | Development environment, branches, commits, and pull request requirements. |

The repository is currently organized as:

```text
mac/      Current macOS implementation using Swift, AppKit, and SwiftUI
skills/   Release and repository-maintenance skills
```

## Contributing

Issues and pull requests are welcome. Read the [contributing guide](CONTRIBUTING.md) first. Report security issues privately through [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) rather than opening a public issue.

## License

MIT
