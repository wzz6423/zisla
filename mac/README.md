# zisla for macOS

**English** | [简体中文](README.zh-CN.md) | [Other languages](../docs/locales/README.md)

This directory contains zisla's macOS implementation. Move the pointer to the top center of the screen to expand the island; move it away to hide it. The app uses AppKit `NSPanel`, SwiftUI, and event-driven services without a permanent transparent hit-area window or a frame loop while hidden.

Swift targets, the bundle ID, local data directory, and `zislactl` all use the zisla identifier. Upgrades migrate local data and preferences from earlier versions automatically.

macOS 14 and later are supported. macOS 26 uses Liquid Glass; macOS 14/15 fall back to the native system material.

## Features

### 12 island modules

| Module | Implemented capabilities |
| --- | --- |
| Home | Summarizes the current Pomodoro timer, first active AI task, native downloads, and multiple browser download progresses on demand. |
| Keyboard sounds and stats | 20 built-in keyboard voices; independently switch local typing statistics, trends, application timeline, and per-key heatmap. |
| Handoff | Drag files, media, or links to the top trigger area to keep them in the handoff tray, reveal them in Finder, or open the system share menu. Stashed screenshots have blue, double-width cards and their own category, with image copy, PNG export, and deletion. Compress selected files and folders to ZIP, resize or convert selected images in Image Tools and return successful outputs to the tray, or import selected images, video and audio into the recording media library while keeping its current project and timeline. |
| Clipboard | Stores a searchable local history, filters by image, URL, and file, and marks favorites; history and link detection are independent switches. New history images are queued for on-device text recognition; search their text to find the original image, or right-click an image to recognize or copy its text. Running recognition can be cancelled; background recognition does not copy text automatically. |
| AI monitoring | Aggregates activity tasks, status, token trends, contribution heatmaps, and side notices from supported CLIs, desktop apps, and IDEs. |
| Downloads | Uses `yt-dlp` for video and audio; without `ffmpeg`, AVFoundation wraps compatible tracks and a read-only Bilibili fallback is available. |
| Schedule | Shows weather for the current location and up to six saved locations; view, create, and delete calendar events and reminders and mark reminders complete. The weather list shows its update time to the left of the refresh button in the header. |
| Mail | Reads selected Mail.app accounts to view inboxes, mark messages read, reply, compose, and move messages to the trash. |
| Notes | Uses Apple Notes as the sole data source for viewing, editing, creating, and deleting Markdown notes with live preview and automatic write-back. |
| Application volume mixer | On macOS 14.4+, adjust and mute each playing application and remember its volume; requires System Audio Recording permission. |
| Utilities | Provides a Pomodoro timer that plays one audible alert and shows a local notification when a session ends, keep-awake mode, idle-sleep prevention, screen and keyboard cleaning, teleprompter, camera mirror, and confirmed trash emptying. Timer names apply only to the current session and return to the default when it ends or is canceled. |
| System | Shows CPU, GPU, memory, disk, network, temperature, and fan status; releases memory and scans caches, logs, and temporary data that are safe to remove; also includes battery health and accessory levels. |

### Cross-module capabilities

- **Now Playing:** MediaRemote shows artwork, title, progress, scrolling lyrics, and controls; Core Audio identifies the actual audio source as a fallback. Paused, stopped, and muted sources are hidden.
- **Browser downloads:** Shows download source and progress for Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera, and Arc in the home view, collapsed state, and side notices.
- **Voice input:** Supports toggle or push-to-talk shortcuts, custom global shortcuts, system speech recognition, local or remote transcript organization, and local recording history.
- **Quick Actions:** After every copy, a small island-style toast shows a rich preview and smart next actions — open links, reveal files in Finder, search (engine selectable), translate, calculate, create calendar events from recognized dates, and save long text or images. After a browser download completes or an AirDrop file is received, the same shortcut can open the containing folder; this is controlled by Quick Actions independently of browser download progress. Recognizes URLs, file paths, emails, phone numbers, CSS colors with live swatches, arithmetic, dates and times, text in a non-system language, code snippets, plain text with counts, images with thumbnails, and file references. Triggers: action buttons, the additional default Command+N shortcut, or a configured modifier-key/mouse-side trigger. Also offers a hold-left + right-click quick-copy mouse gesture (off by default), an app blacklist, per-type recognition switches, and a lightweight reminder mode.
- **CLI and Skills management:** Detects, installs, updates, and removes common AI CLIs and manages local Skills from Settings.
- **Desktop pets:** Select a built-in or imported pet and place it on either side of the island. When you expand the island on one display, pets on the other displays stay in place.
- **Updates:** The selected Release or Preview channel resolves the public egress country code once per app run. `CN` checks its signed Gitee appcast first and retries GitHub once; other country codes check GitHub first and retry Gitee once. An unavailable lookup preserves the Gitee-first order. Sparkle then downloads, verifies, installs, and relaunches updates. Changing the channel applies to both automatic and manual checks.
- **Appearance and interaction:** Settings can follow the system, light, or dark appearance. The island supports transparent or frosted surfaces, pinned expansion, multiple displays, Spaces, and external displays without a notch.
- **Defaults:** New installations enable feature modules by default. Each feature, collapsed-state indicator, side notice, menu-bar metric, and update behavior can be adjusted independently; existing installations keep their current configuration.

### Standalone tools and workflows

- **Recording studio:** Open it from the menu bar or Settings. Record a display, window, or region with optional system audio, microphone, and camera. Edit video, audio, images, and text across tracks, including captions, zooms, animations, portrait and voice effects; preview before exporting video, GIF, Live Photo, or audio. Some formats require FFmpeg; HDR recording depends on device support. Import images, video and audio from the shelf into the media library while keeping the current project and timeline.
- **Image, audio, and PDF tools:** Open the standalone tools from Settings. Images have 9 local operations and batch/ZIP export. Audio has 27 operations including mixing, LUFS normalization, and noise processing, and requires FFmpeg and ffprobe. PDF has 14 operations; Office conversion requires LibreOffice or OpenOffice.
- **Daily briefing:** Choose among 8 templates and select metrics in Settings, preview, then export PNG manually or at a daily time. Unavailable metrics are not presented as measured zero.
- **Window previews:** Hover the Dock or switch with Command+Tab, then click a preview to activate its window. Manage the feature and permissions in Settings.
- **Context notes and meetings:** Hold the configured note shortcut and shake the pointer to attach a note to a webpage, window, or desktop. Calendar events with meeting links show a countdown 10 minutes before starting; join, create a note, or link an existing note. Manage context notes on the shelf.
- **Shake to drop:** Shake the pointer while dragging files to reveal the drop target; switch this gesture independently in Settings.
- **Audio output and player preferences:** Choose an output device in the media area. Settings select an automatic source or preferred player, compact media layout, and ambient-sound stop conditions.
- **AI allowances and resets:** AI monitoring and Settings show supported account allowances, sampling times, reset times, and low-quota notices, including available 5h/7d windows and Cursor USD budgets. These are separate from locally recorded token history. Antigravity’s Gemini and Claude/GPT pools have independent monitoring, display and alerts. Gemini App chat allowances use a web Cookie for the same Google account; Gemini CLI remains separate.

### Quick Actions keyboard order

The Quick Actions popup assigns `Command+1` through `Command+9`, then `Command+0`, in the current action order. The additional default trigger for new configurations is `Command+N`, which runs the first action; `Command+Delete` dismisses the popup. Configure the trigger, mouse side button, and action order in Settings. Upgrades retain every explicitly saved combination, including the old `Command+1`, custom shortcuts, and cleared triggers; only new configurations or an absent trigger field adopt `Command+N`.

### Save locations

Settings → Save Location selects separate folders for downloads, screenshots, image tools, recordings, PDF, Quick Actions, and daily briefings. New configurations default to `~/Downloads` subfolders: `picture` for screenshots/images, `video` for recordings, `pdf`, `quick`, and `daily`. Audio tools use an export dialog to select a file or folder. Shelf files retain references to the originals; stashed screenshots and context-note state are managed locally under `~/Library/Application Support/zisla`, while recording projects use the recording folder. Quick Notes text lives in Apple Notes.

[User help and step-by-step guides](https://wzz6423.github.io/zisla/help.html?lang=en#help) cover nine topics: clipboard, capture, shelf, meetings, AI, media tools, daily briefings, desktop notes/window previews, and playback/mixing, with short film excerpts.

### Screenshot shortcuts and stashing

The screenshot toolbar's **Stash** action sits between **Pin** and **Copy**. It stores the final edited image, including annotations and completed scrolling captures, in the handoff tray without copying it to the clipboard. The PNG and capture metadata, including the original application and capture time, are stored locally in SQLite and survive app restarts. The **Stashed screenshots** category shows only these cards.

**Highlighter** follows **Brush** and draws a translucent highlight; end lines and circular markers are kept by default and can be disabled in its menu. **Extract** follows **Blur** and supports macOS subject or background extraction, plus freehand selection of arbitrary areas. Multiple loops retain their combined areas, with Select All and Clear controls; unselected pixels become transparent and extraction can be undone. Screenshot corners default to a radius of 0. Drag the radius handle above the selection or use the **Corner radius** slider; the size badge shows `r`. PNG exports have transparent corners, and resetting the radius to 0 restores the original corner pixels.

| Context | Action | Default shortcut |
| --- | --- | --- |
| Global | Screenshot | `Control+1` |
| Global | Scrolling screenshot | `Control+2` |
| Screenshot editor | Pin | `Control+1` |
| Screenshot editor | Stash | `Control+2` |
| Screenshot editor | Rectangle | `Control+3` |
| Screenshot editor | Ellipse | `Control+4` |
| Screenshot editor | Brush | `Control+5` |
| Screenshot editor | Highlighter | `Control+6` |
| Screenshot editor | Arrow | `Control+7` |
| Screenshot editor | Number | `Control+8` |
| Screenshot editor | Text | `Control+9` |
| Screenshot editor | Blur | `Control+0` |
| Screenshot editor | Extraction | `Control+A` |
| Screenshot editor | Scrolling capture | `Control+B` |
| Screenshot editor | Copy | `Enter` |
| Screenshot editor | Save | `Command+S` |
| Screenshot editor | Undo | `Command+Z` |
| Screenshot editor | Redo | `Command+Shift+Z` |

Screenshot settings show and record the global and editor shortcuts. Copy, Save, Undo, and Redo are displayed but cannot be re-recorded. User-recorded shortcuts are retained when upgrading; Pin is an editor action rather than a separate global shortcut, while its menu entry remains available.

Default editor shortcuts follow toolbar order: `Control+1` through `Control+9`, then `Control+0`, `Control+A`, `Control+B`, and subsequent letters. Default allocation skips `Q`, `M`, `N`, and `W`: pressing Command by mistake could quit the app, minimize a window, open a new window, or close a window. User-recorded combinations are still allowed.

On upgrade, untouched legacy layouts, including the previous Pin/Stash layout, move to the defaults above once. If any screenshot shortcut was customized, the existing layout is kept; new actions choose an unused Control combination in the same safe order when their default conflicts. These initial combinations can also be re-recorded.

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
| GitHub / Google / xAI | GitHub Copilot CLI and VS Code, Gemini CLI and Desktop, and Grok CLI |
| Independent and regional tools | Pi, Kimi Code, Qwen Code, Qoder, ZCode Desktop and CLI, TRAE, OpenCode, Harnext/Harness, and WorkBuddy |

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

Canonical providers include `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `zcode`, `trae`, `opencode`, `pi`, `harness`, and `doubao`; common aliases are normalized automatically. Call it from any tool hook, shell wrapper, or task script.

The AI run list and collapsed state use each tool's official logo to identify its source.

See the [CLI integration reference](Docs/cli-reference.md) for the protocol.

## Browser download progress

zisla listens to macOS public file-progress information in the Downloads directory and combines temporary-file extensions, download-source extended attributes, and running browser information to identify the source. It does not read browser history databases or make network requests to identify progress; the progress completion mark remains visible for about three seconds. Quick Actions uses the same event source and offers Open Folder after a successful transfer reaches its final location. Its prompt duration follows the Quick Actions setting, and the latest copy or transfer prompt replaces the previous one.

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
- **Quick Actions:** Runs locally on each `changeCount` when enabled and also handles completed browser downloads and received AirDrop files. The quick trigger may use Input Monitoring for modifier-only keys and mouse side buttons; the optional quick-copy gesture also posts a synthetic ⌘C and therefore requires Accessibility. Recognition never connects to the network; opening links, searching, translating, and saving happen only after an explicit click or trigger press. The app blacklist and per-type switches control copied-content prompts; the Quick Actions switch also controls completed-transfer prompts.
- **AI state:** Automatic detection reads only structured events and local activity metadata needed to determine task state.
- **Voice:** Microphone and speech recognition are accessed only after an explicit user action. Recordings, raw transcripts, and organized text are managed locally; organized text is sent only to the selected local model, remote provider, or CLI profile, and remote credentials are kept in a private database.
- **Bluetooth and devices:** Accessory and trusted Apple mobile-device battery levels are read only when the battery view under System is open.
- **Camera and Input Monitoring:** The mirror and recording-studio camera preview/recording request camera access. Keyboard sounds, typing statistics, keyboard cleaning, and modifier-only/mouse-side triggers use Input Monitoring; statistics stay local and the switches are independent.
- **Screen and system audio:** Screenshots, recording, and window previews read screen content with Screen Recording permission. Recording saves selected sources locally; optional microphone/camera access is requested only for enabled sources. The application volume mixer requires macOS 14.4+ and System Audio Recording permission, and uses local Core Audio taps.
- **Browser downloads:** Only public system file progress and download temporary files are inspected; browser history and page content are not read.
- **Media:** MediaRemote supplies metadata and Core Audio process output state confirms playback. MediaRemote is a private framework, so the current build is not suitable for direct Mac App Store submission; missing metadata falls back to the active audio source app.
- **Network:** Weather uses Open-Meteo and public China weather alerts where applicable, with WeatherKit preferred elsewhere. The selected update channel resolves the public egress country code once per app run through `ipinfo.io/country`: `CN` uses Gitee then GitHub, other country codes use GitHub then Gitee, and an unavailable lookup preserves Gitee first. The Bilibili fallback uses read-only video information, playback URLs, and its media CDN; recognizing clipboard links does not connect to the network. Enabled account-allowance checks contact the selected providers; optional translation, AI recording edits, and transcript cleanup contact the selected model or CLI. Speech recognition may use Apple services depending on system/language support. Installing or updating dependency components and CLIs, public-IP lookup, and network actions explicitly selected by the user also make requests.
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
- [Vendored dependencies](Vendor/README.md)
- [Third-party notices](Resources/ThirdPartyLicenses/README.md)

## System limitations

- macOS has no public Dynamic Island API; a physical notch is inferred from `safeAreaInsets` and the top auxiliary area, while displays without a notch use the same custom overlay simulation.
- DRM video, login windows, the lock screen, and some exclusive full-screen apps may not expose Now Playing data or allow an overlay.
- Apps that do not integrate with the system media center may still expose their audio source but cannot guarantee title, artwork, or progress; paused, stopped, and muted video is intentionally hidden.
- A browser must publish macOS file progress or use recognizable temporary files in Downloads for zisla to show a percentage.
- Battery health, temperature, live power, and accessory levels depend on hardware, connection method, and data exposed by macOS; missing fields are shown as unavailable.
- Office-to-PDF conversion requires LibreOffice or OpenOffice; other PDF operations run locally.
- Packages are not notarized and may require **Open Anyway** on first launch. Stable releases use one self-signed certificate so macOS permission grants survive later updates; Sparkle separately verifies every update with the embedded EdDSA public key before extracting, replacing, and relaunching the app.

## License

[PolyForm Noncommercial License 1.0.0](../LICENSE.md). Noncommercial use is permitted; selling this software, or any other commercial use, is not.
