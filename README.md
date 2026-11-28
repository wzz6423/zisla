# zisla

**English** | [简体中文](README.zh-CN.md) | [Other languages](docs/locales/README.md)

**zisla is a native macOS workspace that appears when you need it, then gets out of the way.** Move the pointer to the top center of the screen to open one lightweight place for active AI work, media, handoff, downloads, and desktop utilities. Displays without a notch use the same simulated status area.

Current implementation: **macOS 14+**. Apple Silicon is the supported configuration; Intel release packages may work, but compatibility is not guaranteed.

[Watch the full feature tour — 2:40 · 1080p / 60 fps](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

[![Watch the zisla launch film](web/public/media/zisla-launch-poster.webp)](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

Music: “Funkorama” by Kevin MacLeod · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Source](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474).

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
| Handoff and sharing | Drop files, media, or links on the top trigger area to keep them in a handoff tray, reveal them in Finder, or open the macOS share menu. Compress selected files and folders to ZIP, resize or convert selected images in Image Tools and return successful outputs to the tray, or import selected images, video and audio into the recording media library while keeping its current project and timeline. |
| Clipboard and notifications | Optionally records local clipboard history, recognizes new links locally, and surfaces media, AI activity, browser downloads, timers, mail, and updates in the collapsed state. Optional Quick Actions show a small island toast after every copy with a rich preview and smart next actions (open, reveal in Finder, search, translate, calculate, save). After a browser download completes or an AirDrop file arrives, the same shortcut can open its folder. New history images are queued for on-device text recognition; search their text to find the original image, or right-click an image to recognize or copy its text. |
| Everyday workspace | Includes weather, calendar, reminders, Mail.app, Markdown notes backed by Apple Notes, lock-screen information, and optional desktop pets. Preview pets and keep one, or let zisla draw from your selection at local midnight or at a custom interval. Incomplete weather is supplemented from other sources using the most complete result; available partial data is retained when the rest cannot be fetched. |

### Make AI work visible

zisla monitors local activity from Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, Delta, Orca, TRAE, OpenCode, Harnext, WorkBuddy, WorkBuddy AI, and other supported sources. It shows tasks, status, token trends, contribution heatmaps, and side notices.

For tools without a stable local activity source, `zislactl` lets scripts, CI, and tool hooks report progress, usage, and notifications while keeping protocol state on this Mac. Settings can also detect, install, update, and remove common AI CLIs and manage local Skills. See the [CLI integration reference](mac/Docs/cli-reference.md) for providers and commands.

### Handle the useful small things

| Area | Included tools |
| --- | --- |
| Downloads and documents | Video and audio downloads through `yt-dlp`; local PDF merge, split, rotate, crop, conversion, rendering, text export, watermarks, page numbers, encryption, unlock, and metadata editing. |
| Focus and presentation | Pomodoro timer with one audible alert and a local notification when a session ends, keep-awake mode, idle-sleep prevention, screen and keyboard cleaning, teleprompter, and camera mirror. Timer names apply only to the current session and return to the default when it ends or is canceled. In the collapsed island, a sun means the display stays on and a laptop means idle sleep is blocked. |
| System and battery | CPU, GPU, memory, disk, network, fan, and battery information, plus cleanup of caches and logs that are safe to remove. |
| Voice input | Global shortcuts for recording and transcription, optional local or remote transcript organization, and local voice history. |

### Current entry points and workflows

The island has 12 modules: Home, Handoff, Clipboard, AI monitoring, Keyboard sounds, Downloads, Schedule, Mail, Notes, Application volume mixer, Utilities, and System. Battery details live under System; lock-screen presentation is separate. Open PDF, image and audio tools from Settings; open the recording studio from Settings or the menu bar.

- **Recording and creation:** Record a display, window, or region with optional system audio, microphone, and camera. Edit captions, zooms, portrait and voice effects across tracks, preview, then export video, GIF, Live Photo, or audio. Image tools offer 9 local operations; audio tools offer 27.
- **Mixing and playback:** macOS 14.4+ supports per-app volume and mute. Choose audio output in the media area and player preferences in Settings.
- **Desktop and meetings:** Dock and Command+Tab window previews, webpage/window/desktop context notes, a 10-minute meeting countdown, joining and linked notes. Shake while dragging files to reveal the shelf drop target.
- **Daily briefing:** 8 templates, preview, manual or scheduled PNG export, selected metrics, and an independent save folder.
- **AI accounts:** View supported account allowances, reset times, low-quota notices, and sampling times; export local token history as `.xlsx`. Antigravity’s Gemini and Claude/GPT pools have independent monitoring, display and alerts. Gemini App chat allowances use a web Cookie for the same Google account; Gemini CLI remains separate.
- **Quick Actions:** Popup actions use `Command+1` through `Command+0` in order. The additional default trigger for new configurations is `Command+N` for the first action. Upgrades retain saved shortcuts and cleared triggers.
- **Menu Bar Management** — Hide persistent menu bar icons while their apps keep running.

[User help](https://wzz6423.github.io/zisla/help.html?lang=en#help) provides nine step-by-step guides: clipboard, capture, shelf, meetings, AI, media tools, daily briefings, desktop notes/window previews, and playback/mixing. The [macOS guide](mac/README.md#save-locations) lists tool save folders and dependencies.

## Get started

### Install the app

Download the latest DMG from [GitHub Releases](https://github.com/wzz6423/zisla/releases) or [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), mount it, and drag `zisla.app` to `Applications`.

Homebrew is another way in:

```bash
brew install --cask wzz6423/tap/zisla
```

Homebrew fetches the build that matches your chip, so an Apple Silicon or Intel Mac downloads only its own slice. The cask comes from the third-party tap `wzz6423/tap` rather than Homebrew's own cask repository, so installing it means trusting this tap.

After launching, move the pointer to the top center of the current screen, or choose **Show Island** from the menu bar icon. Packages are not notarized, so however you installed zisla, the first launch needs **Open Anyway** in **System Settings > Privacy & Security**, or clear the quarantine attribute yourself:

```bash
xattr -d com.apple.quarantine /Applications/zisla.app
```

### Update the app

zisla updates itself through Sparkle however you installed it. A Homebrew install is the one case worth a note: `brew upgrade` replaces the app only when the installed copy really is older than the version in the tap, because Homebrew 5.1.6 and later read the version inside the app bundle — so Homebrew stays out of Sparkle's way without leaving a stale install behind. Naming the cask goes by the Homebrew install records instead, so it can put a Sparkle-updated app back on the tap version:

```bash
brew upgrade --cask zisla
```

The tap serves stable releases only; preview builds stay on Releases so `brew upgrade` never moves you onto a prerelease — and naming the cask while you are on a preview replaces it with the current stable build. Sparkle itself never downgrades, so switching back to Release leaves you on the preview build until a stable release passes it. `brew uninstall --cask zisla` removes the app, and `brew uninstall --zap --cask zisla` also trashes its local data.

### Run from source

Swift 6 / Xcode 16+ is required; Command Line Tools alone can also build the project.

```bash
cd mac
swift run zisla
```

The downloader requires `yt-dlp`; `ffmpeg` is optional. Office-to-PDF conversion requires LibreOffice or OpenOffice. Build, test, and packaging instructions are in the [macOS development guide](mac/README.md).

## Designed to stay out of the way

- Supports multiple displays, Spaces, and ordinary full-screen apps without activating or taking focus from the current app.
- When multiple displays are connected, Settings → General → Display Modes lets you choose Dynamic Island Mode (camera or custom position), Notch Mode, or Hide on This Display for each screen. With one screen, this setting is hidden and the global appearance applies; reconnecting restores each display’s saved configuration. All enabled displays show their collapsed islands on startup. Expanding the island, opening Quick Actions, recording, or showing a temporary message affects only that display. Choosing where to show notifications leaves the other islands visible.
- The hidden state has no permanent transparent hit-area window and runs no frame loop; global event monitoring and geometry checks trigger expansion.
- Uses one system material and switches to an opaque background when Reduce Transparency is enabled.
- Detects a physical notch from the system safe area; external displays without one use an overlay with the same outline.

See the [architecture and performance design](mac/Docs/architecture.md) for the implementation trade-offs.

## Privacy and permissions

zisla requests a permission only when an enabled feature first needs it. You can disable modules in Settings and revoke authorization in macOS System Settings at any time.

| Scope | Boundary |
| --- | --- |
| AI activity | Reads only structured events and local activity metadata. Prompts and answer bodies are never read. |
| Clipboard and files | Clipboard history, link detection, and Quick Actions are separate local switches; Quick Actions handles completed browser downloads and received AirDrop files independently of the browser download progress switch. Recognition runs entirely on-device, and opening links or running actions happens only after an explicit click or trigger press. Handoff uses security-scoped bookmarks and does not copy the original file. |
| Notes, Mail, and voice | Notes and Mail use AppleScript/JXA with automation authorization. Voice records only while active; transcript organization sends text only to the selected local model, remote provider, or CLI profile. |
| Browser downloads and media | Uses macOS public file-progress information, MediaRemote metadata, and Core Audio output state. It does not read browser history databases. System waveforms and application mixing process audio locally; recording saves audio only when the corresponding source is enabled. |
| Network | Weather, public-IP lookup, update mirror selection, downloads, enabled AI account-allowance checks, and dependency/CLI installation contact their services. Optional translation, voice cleanup, and recording AI edits use the selected provider or CLI. Apple speech recognition may use the network according to system and language support. |

### Permissions by feature

zisla requests the required authorization when a feature is first used. If you previously denied access, open the corresponding item in **System Settings > Privacy & Security** and allow `zisla`; item names may differ between macOS versions.

| Permission or system setting | When it is needed | Authorized scope |
| --- | --- | --- |
| Device Control and Data Access (shown as Accessibility on some versions) | Automatically inserting voice transcripts into the current app's text field | Reads and locates non-password input fields, then delivers the transcript through Accessibility APIs or `Cmd+V`. Without authorization, the transcript is still copied to the clipboard. |
| Microphone | Voice input or enabling the studio microphone | Captures the selected microphone for recording or enabled monitoring. |
| Speech Recognition | Converting recorded speech to text | Processes only actively recorded speech. Voice input requires both Microphone and Speech Recognition authorization. |
| Full Disk Access | Viewing mail while Mail.app is not running | Reads the local index in `~/Library/Mail` to show accounts, senders, subjects, summaries, timestamps, and read status. This Mail index access path requires authorization. |
| Automation | Reading, composing, replying to, marking, or deleting Mail.app messages; reading and writing Apple Notes | Allows zisla to control the corresponding system apps. Mail and Notes authorization can be revoked separately in System Settings. |
| Calendars; Reminders | Using the schedule module | Reads and manages calendar events and reminders with separate authorizations. |
| Location Services | Using current-location weather | Requests the current location once without continuous tracking. Manually added locations do not require location access. |
| Camera | Opening the mirror or enabling studio camera preview/recording | Uses the selected camera while the corresponding feature is active. |
| Input Monitoring | Keyboard sounds, typing statistics, keyboard cleaning, and modifier-only or mouse-side shortcuts | Observes events for the enabled feature; typing statistics remain local. Ordinary global shortcuts do not require this authorization. |
| Bluetooth | Viewing accessory battery levels under System → Battery | Reads only publicly available battery information for connected or paired devices. |
| Screen & System Audio Recording (shown as Screen Recording on older macOS versions) | Screenshots, window previews, recording, system-audio waveforms, and the application mixer | Reads screen images and selected audio sources. Recording saves enabled sources locally; the mixer needs macOS 14.4+. |
| Notifications | Using Pomodoro alerts | Plays one audible alert and shows a local notification when a timer ends. |
| User-selected folders (no manual authorization required) | File handoff, imports and exports, or choosing a download directory | The system file picker grants access to the selected directory. These features do not require Full Disk Access. |

Revoking a permission disables only the corresponding feature. If a feature remains unavailable after changing a setting, quit and reopen zisla, then try again.

The [macOS guide](mac/README.md#permissions-and-privacy) documents the complete permission and network behavior.

## Documentation

| Document | Purpose |
| --- | --- |
| [macOS development guide](mac/README.md) | Modules, AI integration, dependencies, build, test, permissions, and system limitations. |
| [Website guide](web/README.md) | Local development, production builds, and current download links. |
| [Launch film guide](promo/README.md) | Remotion preview, rendering, compositions, soundtracks, and asset licenses. |
| [Architecture and performance design](mac/Docs/architecture.md) | Top-edge triggering, window behavior, concurrency, media, and download safety. |
| [CLI integration reference](mac/Docs/cli-reference.md) | `zislactl` providers, commands, fields, and exit codes. |
| [Signing and release design](mac/Docs/releasing.md) | Signing, notarization, DMGs, update channels, and release acceptance. |
| [Contributing guide](CONTRIBUTING.md) | Development environment, branches, commits, and pull request requirements. |

## Contributing

Issues and pull requests are welcome. Read the [contributing guide](CONTRIBUTING.md) first. Report security issues privately through [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) rather than opening a public issue.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE.md). Noncommercial use is permitted; selling this software, or any other commercial use, is not.
