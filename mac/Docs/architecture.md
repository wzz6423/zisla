# Architecture and performance design

**English** | [简体中文](architecture.zh-CN.md)

## Top-edge triggering

The hidden state has no transparent window. `PointerEdgeMonitor` installs global and local `NSEvent` monitors for mouse movement and drag events; `ScreenLayoutEngine` uses geometry alone to determine whether the pointer enters the top-center 6 px area of each display.

Each display has a stable identity by pairing `NSScreenNumber` with its `CGDirectDisplayID`. Layout is anchored to `screen.frame.maxY`, so negative coordinates, vertically stacked displays, and external displays without a notch are supported.

## Window

The main island keeps one `.borderless + .nonactivatingPanel`:

- It uses the `.statusBar` level and does not cover the system lock screen or system menu.
- `.canJoinAllSpaces + .fullScreenAuxiliary` supports Spaces and ordinary full-screen apps.
- Hover expansion never calls `NSApp.activate`, so it does not take focus from the current app.
- Hidden state uses `orderOut`, so the menu bar area is not consumed by a transparent window.

Left and right notification panels are created on demand and are hidden as soon as their queues are empty.

## State and concurrency

- AppKit, SwiftUI state, and window control stay on `MainActor`.
- Downloads, weather, and GitHub requests use actors.
- AI state written by hooks is monitored through directory filesystem events. Each AI session source compares the latest local session or activity file by mtime and size and reuses the parse cache when nothing changed.
- Automatic detection reads only structured events, fixed status markers, and activity metadata needed to determine task state. It does not read prompt or answer bodies, and a provider parser failure does not block other providers.
- Collapse delays use cancellable `Task`s and a generation token so an old task cannot hide an island that has already reopened.
- The hidden state has no `TimelineView`, 60 Hz timer, or continuous animation submission.

## Media detection

MediaRemote provides the title, artwork, progress, and controls. Process-object properties from Core Audio 14.4+ confirm whether an app has an active output stream and provide a fallback source app when metadata is missing. Process lists and output state are driven by property listeners rather than polling; audio content is never captured, and Screen Recording or Accessibility permission is not requested. Paused, stopped, and muted sources are not kept in the media area.

## Materials

macOS 26 uses a single-layer SwiftUI `glassEffect`; macOS 14/15 use a single-layer `NSVisualEffectView`. Reduce Transparency switches to an opaque background. The island does not stack multiple blur or material layers.

## Download safety boundary

Swift starts `yt-dlp` with `Process.executableURL` and an argument array; the URL is always a separate argv value after `--`. Runtime configuration, plugins, and exec are disabled, output pipes are drained concurrently, and progress is parsed through a JSON sentinel.

A task succeeds only when the exit code is 0, the output path exists, and the resolved path remains inside the authorized directory. Each task cleans only its own UUID-named temporary directory.

## Update checks and downloads

The selected update channel uses Sparkle to retrieve the signed appcast for the installed build, download the referenced ZIP over HTTPS, verify the EdDSA archive and feed signatures before extraction, replace the app, and relaunch it. Every automatic and manual check starts with Gitee (`update-release` for Release, `preview` for Preview) and retries the matching GitHub feed once when the Gitee appcast cannot load or its update package fails to download; each feed points to a signed ZIP on its own host. A release publishes one appcast per architecture next to the shared `appcast.xml`, and a single-architecture install asks for the one matching its own slice (a translated x86_64 slice asks for `arm64`), so it is never replaced by the universal build; a universal install counts the slices in its own executable and stays on `appcast.xml`, which also serves apps released before per-architecture updates. Switching the setting affects automatic and manual checks and resets Sparkle's next update cycle. The embedded public key contains no account information; the private signing key stays in the release maintainer's macOS Keychain or separately secured private key file.
