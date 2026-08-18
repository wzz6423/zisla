# zisla for macOS

**English** | [简体中文](README.zh-CN.md)

This directory contains zisla's macOS implementation. Move the pointer to the top center of the screen to expand the island; move it away to hide it. The app uses AppKit `NSPanel`, SwiftUI, and event-driven services without a permanent transparent hit-area window or a frame loop while hidden.

Swift targets, the bundle ID, local data directory, and `zislactl` all use the zisla identifier. Upgrades migrate local data and preferences from earlier versions automatically.

macOS 14 and later are supported. macOS 26 uses Liquid Glass; macOS 14/15 fall back to the native system material.

## Features

### 13 modules

| Module | Implemented capabilities |
| --- | --- |
| Home | Summarizes the current Pomodoro timer, first active AI task, native downloads, and multiple browser download progresses on demand. |
| Handoff | Drag files, media, or links to the top trigger area to keep them in the handoff tray, reveal them in Finder, or open the system share menu. |
| Clipboard | Stores a searchable local history, filters by image, URL, and file, and marks favorites; history and link detection are independent switches. |
| AI monitoring | Aggregates activity tasks, status, token trends, contribution heatmaps, and side notices from supported CLIs, desktop apps, and IDEs. |
| Downloads | Uses `yt-dlp` for video and audio; without `ffmpeg`, AVFoundation wraps compatible tracks and a read-only Bilibili fallback is available. |
| Schedule | Shows weather for the current location and up to six saved locations; view, create, and delete calendar events and reminders and mark reminders complete. |
| Mail | Reads selected Mail.app accounts to view inboxes, mark messages read, reply, compose, and move messages to the trash. |
| Notes | Uses Apple Notes as the sole data source for viewing, editing, creating, and deleting Markdown notes with live preview and automatic write-back. |
| PDF | Performs local merge, split, rotate, image/Office conversion, image rendering, text export, two watermark types, page numbering, crop, encryption, unlock, and metadata editing. |
| Utilities | Provides a Pomodoro timer, alarm, keep-awake mode, idle-sleep prevention, screen and keyboard cleaning, teleprompter, camera mirror, and confirmed trash emptying. |
| System | Shows CPU, GPU, memory, disk, network, temperature, and fan status; releases memory and scans caches, logs, and temporary data that are safe to remove. |
| Battery | Shows charge flow, health, cycles, temperature, capacity, current, voltage, charger information, and battery levels for Bluetooth accessories and trusted Apple mobile devices. |
| Lock screen | Displays custom text, lunar dates, media, and related status information on the system lock screen. |

### Cross-module capabilities

- **Now Playing:** MediaRemote shows artwork, title, progress, scrolling lyrics, and controls; Core Audio identifies the actual audio source as a fallback. Paused, stopped, and muted sources are hidden.
- **Browser downloads:** Shows download source and progress for Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera, and Arc in the home view, collapsed state, and side notices.
- **Voice input:** Supports toggle or push-to-talk shortcuts, custom global shortcuts, system speech recognition, local or remote transcript organization, and local recording history.
- **CLI and Skills management:** Detects, installs, updates, and removes common AI CLIs and manages local Skills from Settings.
- **Desktop pets:** Select a built-in or imported pet and place it on either side of the island.
- **Updates:** Checks GitHub/Gitee Releases and can manually or automatically download the current channel's DMG; the app never mounts or replaces itself.
- **Appearance and interaction:** Settings can follow the system, light, or dark appearance. The island supports transparent or frosted surfaces, pinned expansion, multiple displays, Spaces, and external displays without a notch.
- **Defaults:** New installations enable feature modules by default. Each feature, collapsed-state indicator, side notice, menu-bar metric, and update behavior can be adjusted independently; existing installations keep their current configuration.

## Quick start

### Environment

- macOS 14+
- Swift 6 / Xcode 16+ (Command Line Tools alone can also build)
- Optional: `yt-dlp` and `ffmpeg`; Office-to-PDF conversion also requires LibreOffice or OpenOffice

With Homebrew:

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### Run from source

```bash
swift run zisla
```

The app starts as a menu-bar accessory. Move the pointer into the 6 px area at the top center of the current display to expand it, or choose “Show Island” from the menu bar icon.

### Build an `.app`

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

To package the official `yt-dlp` helper:

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh` downloads a pinned official macOS standalone file and verifies it against the official `SHA2-256SUMS` before installing it at `Tools/yt-dlp`.

## AI tool integration

### Automatic detection

zisla reads public or stable local session state from supported tools and extracts only structured events and local activity metadata needed to determine task state. It does not read prompts or answer bodies.

| Environment | Automatic detection |
| --- | --- |
| OpenAI / Anthropic | Codex CLI and Desktop, Claude Code, and their host environments |
| GitHub / Google / xAI | GitHub Copilot CLI and VS Code, Gemini CLI, and Grok CLI |
| Independent and regional tools | Kimi Code, Qwen Code, Qoder, TRAE, OpenCode, Harnext/Harness, WorkBuddy, and Doubao |

Waiting for approval or a user answer is yellow, tool or command errors are red, and normal execution is green; simultaneous sources are grouped in red, yellow, green order. The Qwen runtime sidecar is considered active only while its PID is alive, avoiding stale reports after exit.

If a chat-oriented desktop app does not persist structured activity events, the system cannot reliably distinguish an idle open app from an actively generating model. Such tools, including ChatGPT, should use the `zislactl` hook below; zisla does not fake activity with a resident process.

### Local `zislactl` protocol

`zislactl` writes task state and usage history to SQLite:

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

Usage history survives app restarts, replacement updates, and task clearing. It is lost only when the user deletes the application data manually.

Example:

```bash
swift run zislactl update \
  --id build-42 \
  --provider claude \
  --title "Refactor index" \
  --progress 68 \
  --detail "17/25"

swift run zislactl usage \
  --provider claude \
  --input-tokens 12400 \
  --output-tokens 2100 \
  --model claude-opus-4-8

swift run zislactl finish --id build-42 --detail "Complete"
```

Canonical providers include `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `trae`, `opencode`, `harness`, and `doubao`; common aliases are normalized automatically. Call it from any tool hook, shell wrapper, or task script.

The AI run list and collapsed state use each tool's official logo to identify its source.

See the [CLI integration reference](Docs/cli-reference.md) for the protocol.

## Browser download progress

zisla listens to macOS public file-progress information in the Downloads directory and combines temporary-file extensions, download-source extended attributes, and running browser information to identify the source. It does not read browser history databases or make network requests to identify progress; a completed download remains visible for about three seconds.

## Downloader

Executables are resolved in this order:

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

The URL is passed to `Process` as a separate argv value rather than through a shell. Runtime configuration and plugins are ignored, `--exec` is disabled, single-item limits are enforced, and the final file is verified to remain inside the authorized directory.

Without `ffmpeg`:

- Video prefers AVC/MP4 video and M4A audio tracks, then wraps them into MP4 with AVFoundation; a single-file format is kept as-is.
- Audio prefers M4A and otherwise keeps the original audio format.
- If yt-dlp receives HTTP 412, cannot find a format, or is unavailable locally, Bilibili uses its read-only API to obtain DASH tracks and follows the same native wrapping path without installing another tool.

## Notes

Markdown notes inside the island use Apple Notes as their only data source. You can create, view, edit, and delete existing notes rather than only adding new ones.

- **List:** On entry, JXA (`osascript -l JavaScript`) reads titles and modification dates for non-deleted notes and sorts by latest modification. Returning from Notes refreshes the list; notes in Recently Deleted are hidden. Select a note to edit it, refresh, create a note, or delete it from the context menu.
- **View and edit:** AppleScript reads the selected note's `plaintext` (the Markdown source) into the editor. Native `TextEditor` writes changes back after about 0.8 seconds of inactivity to avoid an AppleScript call for every keystroke. New notes are created in Apple Notes and selected.
- **Preview:** The built-in block parser renders headings, unordered/ordered/task lists, quotes, fenced code, rules, bold, italic, inline code, strikethrough, and links as `AttributedString`.
- **Storage:** The Markdown source is stored as ordinary text in the note's `body` with HTML escaping and blank lines preserved. Reading `plaintext` restores the source; Apple Notes displays plain text rather than rendering Markdown.
- **Permissions:** The first read or write triggers macOS automation authorization for Apple Notes; a denial returns a failure notice from the list or editor.

The Notes module does not keep a second local copy; Apple Notes is the storage backend.

## Permissions and privacy

- **Calendar:** Calendar and Reminders permissions are requested separately on first entry; events and reminders refresh after creation, deletion, or completion.
- **Location:** Weather uses a one-time current-location request and does not track continuously; other locations can be searched, saved, and removed in Settings.
- **Files and Downloads:** User-selected directories use security-scoped bookmarks; file handoff does not copy the original.
- **Clipboard:** New installations enable history and link detection by default, with independent switches. On each `changeCount`, at most one link is recognized locally; query parameters are not logged and no clear, declare-type, or write API is called, so the universal clipboard is not replaced.
- **AI state:** Automatic detection reads only structured events and local activity metadata needed to determine task state.
- **Voice:** Microphone and speech recognition are accessed only after an explicit user action. Recordings, raw transcripts, and organized text are managed locally; organized text is sent only to the selected local model, remote provider, or CLI profile, and remote credentials are kept in a private database.
- **Bluetooth and devices:** Accessory and trusted Apple mobile-device battery levels are read only when the battery module is open.
- **Camera and Input Monitoring:** The camera is used only for the mirror; custom modifier-key shortcuts and keyboard cleaning may require Input Monitoring.
- **Browser downloads:** Only public system file progress and download temporary files are inspected; browser history and page content are not read.
- **Media:** MediaRemote supplies metadata and Core Audio process output state confirms playback. MediaRemote is a private framework, so the current build is not suitable for direct Mac App Store submission; missing metadata falls back to the active audio source app.
- **Network:** Weather uses Open-Meteo and public China weather alerts where applicable, with WeatherKit preferred elsewhere. Update checks try Gitee before GitHub, and download confirmation contacts the selected Release DMG. The Bilibili fallback uses read-only video information, playback URLs, and its media CDN; recognizing clipboard links does not connect to the network.
- **Automation:** Notes uses AppleScript/JXA to list, view, edit, create, and delete Apple Notes. It requires automation authorization, does not use the network, and keeps data in Apple Notes.

## Tests

With a complete Xcode installation:

```bash
swift test
```

With Command Line Tools only:

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Documentation

- [Architecture and performance design](Docs/architecture.md)
- [CLI integration reference](Docs/cli-reference.md)
- [Signing and release design](Docs/releasing.md)

## System limitations

- macOS has no public Dynamic Island API; a physical notch is inferred from `safeAreaInsets` and the top auxiliary area, while displays without a notch use the same custom overlay simulation.
- DRM video, login windows, the lock screen, and some exclusive full-screen apps may not expose Now Playing data or allow an overlay.
- Apps that do not integrate with the system media center may still expose their audio source but cannot guarantee title, artwork, or progress; paused, stopped, and muted video is intentionally hidden.
- A browser must publish macOS file progress or use recognizable temporary files in Downloads for zisla to show a percentage.
- Battery health, temperature, live power, and accessory levels depend on hardware, connection method, and data exposed by macOS; missing fields are shown as unavailable.
- Office-to-PDF conversion requires LibreOffice or OpenOffice; other PDF operations run locally.
- Free ad-hoc packages are not notarized and may require **Open Anyway** on first launch. Regardless of signing, the app only checks and downloads updates and never replaces itself automatically.

## License

MIT
