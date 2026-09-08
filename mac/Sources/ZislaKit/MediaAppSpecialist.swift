import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Specialized configuration for player apps with incomplete MediaRemote support.
/// When MediaRemote does not expose capabilities such as favorites or playback modes,
/// this provides supplemental controls via the app's public scripting dictionary or Accessibility API.
struct MediaAppProfile: Sendable {
    let bundleIdentifier: String
    let supportsFavorite: Bool
    let supportsFavoriteStateRead: Bool
    let supportsPlaybackControls: Bool
    let supportsPlaybackModeSet: Bool
    let supportsPlaybackModeCycle: Bool
    let prefersAccessibilityControls: Bool
    let defaultPlaybackMode: NowPlayingPlaybackMode
    let favoriteControl: NowPlayingFavoriteControl
}

struct PlaybackModeCycleResult: Sendable, Equatable {
    let observedMode: NowPlayingPlaybackMode?
    let targetMode: NowPlayingPlaybackMode
}

struct PlaybackModeControlResolution: Sendable, Equatable {
    let mode: NowPlayingPlaybackMode
    let usesCoordinateClick: Bool
}

/// Executes control commands targeting a specific player app.
@MainActor
final class MediaAppSpecialist {
    static let shared = MediaAppSpecialist()
    private var hasRequestedQQMusicAccessibilityAccess = false

    private let profiles: [String: MediaAppProfile] = [
        "com.apple.Music": MediaAppProfile(
            bundleIdentifier: "com.apple.Music",
            supportsFavorite: true,
            supportsFavoriteStateRead: true,
            supportsPlaybackControls: true,
            supportsPlaybackModeSet: true,
            supportsPlaybackModeCycle: false,
            prefersAccessibilityControls: false,
            defaultPlaybackMode: .sequential,
            favoriteControl: .like
        ),
        "com.spotify.client": MediaAppProfile(
            bundleIdentifier: "com.spotify.client",
            supportsFavorite: false,
            supportsFavoriteStateRead: false,
            supportsPlaybackControls: true,
            supportsPlaybackModeSet: false,
            supportsPlaybackModeCycle: false,
            prefersAccessibilityControls: false,
            defaultPlaybackMode: .sequential,
            favoriteControl: .like
        ),
        "com.tencent.QQMusicMac": MediaAppProfile(
            bundleIdentifier: "com.tencent.QQMusicMac",
            supportsFavorite: true,
            supportsFavoriteStateRead: true,
            supportsPlaybackControls: true,
            supportsPlaybackModeSet: false,
            supportsPlaybackModeCycle: true,
            prefersAccessibilityControls: true,
            defaultPlaybackMode: .sequential,
            favoriteControl: .like
        ),
    ]

    private init() {}

    func profile(for bundleIdentifier: String?) -> MediaAppProfile? {
        guard let id = bundleIdentifier else { return nil }
        if let exact = profiles[id] { return exact }
        return profiles.first { id.hasPrefix($0.key) }?.value
    }

    /// Apple Music uses its public scripting dictionary; QQ Music prefers its pressable menu items.
    func toggleFavorite(pid: pid_t?, bundleIdentifier: String?) -> Bool {
        if bundleIdentifier == Self.appleMusicBundleIdentifier {
            return Self.runAppleScript(Self.appleMusicToggleFavoriteScript)
        }
        guard bundleIdentifier == Self.qqMusicBundleIdentifier,
              let pid,
              hasQQMusicAccessibilityAccess()
        else { return false }
        if let item = Self.qqMusicFavoriteMenuItem(pid: pid),
           Self.performPress(on: item, pid: pid)
        {
            return true
        }
        if let button = Self.qqMusicControlRoots(pid: pid).lazy.compactMap({
            Self.findFavoriteButton(in: $0, depth: 0)
        }).first,
           Self.performPress(on: button, pid: pid)
        {
            return true
        }
        return false
    }

    func favoriteState(pid: pid_t?, bundleIdentifier: String?) -> Bool? {
        if bundleIdentifier == Self.appleMusicBundleIdentifier {
            return Self.appleMusicFavoriteState()
        }
        return Self.qqMusicFavoriteState(pid: pid, bundleIdentifier: bundleIdentifier)
    }

    nonisolated static func qqMusicFavoriteState(
        pid: pid_t?,
        bundleIdentifier: String?
    ) -> Bool? {
        guard bundleIdentifier == Self.qqMusicBundleIdentifier,
              let pid,
              AXIsProcessTrusted()
        else { return nil }
        if let item = Self.qqMusicFavoriteMenuItem(pid: pid),
           let state = Self.favoriteState(for: Self.accessibilityLabels(of: item))
        {
            return state
        }
        return Self.qqMusicControlRoots(pid: pid).lazy.compactMap {
            Self.favoriteState(
                for: Self.accessibilityLabels(of: Self.findFavoriteButton(in: $0, depth: 0))
            )
        }.first
    }

    func playbackMode(pid: pid_t?, bundleIdentifier: String?) -> NowPlayingPlaybackMode? {
        Self.qqMusicPlaybackMode(pid: pid, bundleIdentifier: bundleIdentifier)
    }

    nonisolated static func qqMusicPlaybackMode(
        pid: pid_t?,
        bundleIdentifier: String?
    ) -> NowPlayingPlaybackMode? {
        guard bundleIdentifier == Self.qqMusicBundleIdentifier,
              let pid,
              AXIsProcessTrusted()
        else { return nil }
        return Self.qqMusicPlaybackModeControl(pid: pid)?.mode
    }

    /// Apple Music and Spotify use their public scripting dictionaries; QQ Music prioritises pressable menu items.
    func sendPlaybackCommand(
        _ command: NowPlayingService.Command,
        pid: pid_t?,
        bundleIdentifier: String?
    ) -> Bool? {
        if let script = Self.playbackScript(for: command, bundleIdentifier: bundleIdentifier) {
            return Self.runAppleScript(script) ? true : nil
        }
        guard bundleIdentifier == Self.qqMusicBundleIdentifier,
              let pid,
              hasQQMusicAccessibilityAccess(),
              let labels = Self.qqMusicMenuLabels(for: command)
        else { return nil }
        if Self.performQQMusicMenuCommand(pid: pid, matching: labels) {
            return true
        }
        guard let button = Self.qqMusicControlRoots(pid: pid).lazy.compactMap({
            Self.findButton(in: $0, depth: 0, matching: labels)
        }).first else { return nil }
        return Self.performPress(on: button, pid: pid) ? true : nil
    }

    /// Apple Music's mode property is writable in its public scripting dictionary; other players continue through their own control channels.
    func setPlaybackMode(
        _ mode: NowPlayingPlaybackMode,
        pid _: pid_t?,
        bundleIdentifier: String?
    ) -> Bool? {
        guard bundleIdentifier == Self.appleMusicBundleIdentifier else { return nil }
        return Self.runAppleScript(Self.appleMusicModeScript(for: mode)) ? true : nil
    }

    func prepareQQMusicPlaybackModeCycle(
        pid: pid_t?,
        bundleIdentifier: String?
    ) -> Bool {
        guard bundleIdentifier == Self.qqMusicBundleIdentifier, pid != nil else { return false }
        return hasQQMusicAccessibilityAccess()
    }

    nonisolated static func qqMusicPlaybackModeCycle(
        pid: pid_t?,
        bundleIdentifier: String?,
        currentMode: NowPlayingPlaybackMode?
    ) -> PlaybackModeCycleResult? {
        guard bundleIdentifier == Self.qqMusicBundleIdentifier,
              let pid,
              AXIsProcessTrusted()
        else { return nil }

        guard let match = qqMusicPlaybackModeControl(pid: pid) else { return nil }
        let sourceMode = match.mode
        guard let targetMode = cycleTargetMode(observedMode: sourceMode, fallback: currentMode) else {
            return nil
        }

        guard performPlaybackModeToggle(
            on: match.element,
            pid: pid,
            usesCoordinateClick: match.usesCoordinateClick
        ) else { return nil }
        return PlaybackModeCycleResult(observedMode: sourceMode, targetMode: targetMode)
    }

    nonisolated static func cycleTargetMode(
        observedMode: NowPlayingPlaybackMode?,
        fallback: NowPlayingPlaybackMode?
    ) -> NowPlayingPlaybackMode? {
        guard let sourceMode = observedMode ?? fallback else { return nil }
        switch sourceMode {
        case .sequential:
            return .repeatOne
        case .repeatOne:
            return .random
        case .random:
            return .sequential
        }
    }

    nonisolated static func playbackModeControlResolution(
        for labels: [String],
        hasPressableTarget: Bool
    ) -> PlaybackModeControlResolution? {
        guard let mode = playbackMode(for: labels) else { return nil }
        return PlaybackModeControlResolution(
            mode: mode,
            usesCoordinateClick: !hasPressableTarget
        )
    }

    // MARK: - CGEvent
    nonisolated private static let appleMusicBundleIdentifier = "com.apple.Music"
    nonisolated private static let qqMusicBundleIdentifier = "com.tencent.QQMusicMac"

    private func hasQQMusicAccessibilityAccess() -> Bool {
        let trusted = AXIsProcessTrusted()
        guard Self.shouldRequestAccessibilityPrompt(
            isTrusted: trusted,
            hasRequestedInCurrentLaunch: hasRequestedQQMusicAccessibilityAccess
        ) else {
            return trusted
        }
        hasRequestedQQMusicAccessibilityAccess = true
        guard let host = WindowPlacement.authorizationPromptHost() else {
            return trusted
        }
        defer {
            host.orderOut(nil)
            host.close()
        }
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func shouldRequestAccessibilityPrompt(
        isTrusted: Bool,
        hasRequestedInCurrentLaunch: Bool
    ) -> Bool {
        !isTrusted && !hasRequestedInCurrentLaunch
    }

    nonisolated private static let favoriteEnabledLabels = [
        "从我喜欢删除", "取消喜欢", "取消收藏", "移除收藏",
    ]
    nonisolated private static let favoriteDisabledLabels = [
        "添加到我喜欢", "添加到喜欢", "添加收藏",
    ]
    nonisolated private static let favoriteGenericDisabledLabels = [
        "收藏", "喜欢歌曲", "喜欢",
    ]
    static let qqMusicFavoriteMenuLabels = [
        "喜欢歌曲", "取消喜欢", "添加到我喜欢", "从我喜欢删除", "喜欢",
    ]

    nonisolated static func favoriteState(for labels: [String]) -> Bool? {
        let normalized = labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if normalized.contains(where: {
            favoriteEnabledLabels.contains($0)
                || ($0.contains("取消") && ($0.contains("喜欢") || $0.contains("收藏")))
        }) {
            return true
        }
        if normalized.contains(where: {
            favoriteDisabledLabels.contains($0)
                || ($0.contains("添加") && ($0.contains("喜欢") || $0.contains("收藏")))
        }) {
            return false
        }
        if normalized.contains(where: { favoriteGenericDisabledLabels.contains($0) }) {
            return false
        }
        return nil
    }

    nonisolated static func playbackMode(for labels: [String]) -> NowPlayingPlaybackMode? {
        labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .compactMap { label -> (NowPlayingPlaybackMode, Int)? in
                if label.contains("单曲循环") || label.contains("single repeat") || label.contains("repeat one") {
                    return (.repeatOne, label.contains("播放模式") ? 3 : 2)
                }
                if label.contains("随机") || label.contains("shuffle") || label.contains("random") {
                    return (.random, label.contains("播放模式") ? 3 : 2)
                }
                if label.contains("顺序") || label.contains("列表循环") || label.contains("sequential") || label.contains("order") {
                    return (.sequential, label.contains("播放模式") ? 3 : 2)
                }
                return nil
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    /// Pure coordinate logic: returns the center point of a valid frame; shared by unit tests and click handling.
    nonisolated static func clickPoint(position: CGPoint, size: CGSize) -> CGPoint? {
        guard size.width > 0, size.height > 0,
              position.x.isFinite, position.y.isFinite,
              size.width.isFinite, size.height.isFinite
        else { return nil }
        let point = CGPoint(
            x: position.x + size.width / 2,
            y: position.y + size.height / 2
        )
        return point.x.isFinite && point.y.isFinite ? point : nil
    }

    /// Pure label matching: determines whether accessibility labels point to the playback mode control.
    nonisolated static func matchesPlayModeLabels(_ labels: [String]) -> Bool {
        labels.contains { label in
            let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            return playModeKeywords.contains { keyword in
                text.localizedCaseInsensitiveContains(keyword)
            }
        }
    }

    /// Pure label matching: determines whether accessibility labels point to the favorite control.
    static func matchesFavoriteLabels(_ labels: [String]) -> Bool {
        favoriteState(for: labels) != nil
    }

    static func appleMusicModeScript(for mode: NowPlayingPlaybackMode) -> String {
        let commands: String
        switch mode {
        case .sequential:
            commands = """
            set shuffle enabled to false
            set song repeat to off
            """
        case .repeatOne:
            commands = """
            set shuffle enabled to false
            set song repeat to one
            """
        case .random:
            commands = """
            set shuffle enabled to true
            set song repeat to off
            """
        }
        return """
        if application id "com.apple.Music" is running then
            tell application id "com.apple.Music"
                \(commands)
                return true
            end tell
        end if
        return false
        """
    }

    private static let appleMusicToggleFavoriteScript = """
    if application id "com.apple.Music" is running then
        tell application id "com.apple.Music"
            if not (exists current track) then return false
            set favorited of current track to not (favorited of current track)
            return true
        end tell
    end if
    return false
    """

    private static let appleMusicFavoriteStateScript = """
    if application id "com.apple.Music" is running then
        tell application id "com.apple.Music"
            if not (exists current track) then return ""
            return favorited of current track as text
        end tell
    end if
    return ""
    """

    private static func appleMusicFavoriteState() -> Bool? {
        guard let result = runAppleScriptResult(appleMusicFavoriteStateScript)?.lowercased() else {
            return nil
        }
        switch result.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func playbackScript(
        for command: NowPlayingService.Command,
        bundleIdentifier: String?
    ) -> String? {
        let commandText: String
        switch command {
        case .play: commandText = "play"
        case .pause: commandText = "pause"
        case .togglePlayPause: commandText = "playpause"
        case .previous: commandText = "previous track"
        case .next: commandText = "next track"
        case .likeTrack, .addTrackToWishList, .removeTrackFromWishList: return nil
        }
        let applicationIdentifier: String
        switch bundleIdentifier {
        case appleMusicBundleIdentifier: applicationIdentifier = appleMusicBundleIdentifier
        case "com.spotify.client": applicationIdentifier = "com.spotify.client"
        default: return nil
        }
        return """
        if application id "\(applicationIdentifier)" is running then
            tell application id "\(applicationIdentifier)" to \(commandText)
            return true
        end if
        return false
        """
    }

    private static func runAppleScript(_ source: String) -> Bool {
        runAppleScriptResult(source)?.lowercased() == "true"
    }

    private static func runAppleScriptResult(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue
    }

    static func qqMusicMenuLabels(for command: NowPlayingService.Command) -> [String]? {
        switch command {
        case .play:
            ["播放", "继续播放"]
        case .pause:
            ["暂停"]
        case .togglePlayPause:
            ["播放", "暂停", "继续播放"]
        case .previous:
            ["上一首", "上一曲", "上一首歌", "上一个"]
        case .next:
            ["下一首", "下一曲", "下一首歌", "下一个"]
        case .likeTrack, .addTrackToWishList, .removeTrackFromWishList:
            nil
        }
    }

    nonisolated static func qqMusicPlaybackModeMenuLabels(after mode: NowPlayingPlaybackMode) -> [String] {
        switch mode {
        case .sequential:
            ["单曲循环"]
        case .repeatOne:
            ["随机播放"]
        case .random:
            ["顺序播放"]
        }
    }

    nonisolated private static func postLeftClick(at point: CGPoint, pid: pid_t) -> Bool {
        let source = CGEventSource(stateID: .privateState)
        guard
            let down = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ),
            let up = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
        else { return false }
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    // MARK: - Accessibility

    nonisolated private static let playModeKeywords = [
        "循环", "随机", "顺序", "播放模式", "repeat", "shuffle",
    ]
    nonisolated private static let maximumAccessibilityDepth = 20
    nonisolated private static let accessibilityTimeout: Float = 0.15

    nonisolated private static func findFavoriteButton(in element: AXUIElement, depth: Int) -> AXUIElement? {
        findFavoriteButtonMatch(in: element, depth: depth)?.element
    }

    nonisolated private static func findFavoriteButtonMatch(
        in element: AXUIElement,
        depth: Int
    ) -> (element: AXUIElement, rank: Int)? {
        guard depth < maximumAccessibilityDepth else { return nil }
        let labels = accessibilityLabels(of: element)
        let currentRank = favoriteLabelRank(labels)
        var best = currentRank > 0 ? (pressableAncestor(of: element) ?? element, currentRank) : nil
        for child in children(of: element) {
            if let match = findFavoriteButtonMatch(in: child, depth: depth + 1) {
                if best == nil || match.rank > best!.1 {
                    best = match
                }
            }
        }
        return best
    }

    nonisolated private static func findPlaybackMode(
        in element: AXUIElement,
        depth: Int,
        maximumDepth: Int = maximumAccessibilityDepth
    ) -> (element: AXUIElement, mode: NowPlayingPlaybackMode, rank: Int, usesCoordinateClick: Bool)? {
        guard depth < maximumDepth else { return nil }
        let labels = accessibilityLabels(of: element)
        var best: (element: AXUIElement, mode: NowPlayingPlaybackMode, rank: Int, usesCoordinateClick: Bool)?
        if playbackMode(for: labels) != nil {
            let pressableTarget = pressableAncestor(of: element)
            if let resolution = playbackModeControlResolution(
                for: labels,
                hasPressableTarget: pressableTarget != nil
            ) {
                best = (
                    pressableTarget ?? element,
                    resolution.mode,
                    playbackModeLabelRank(labels),
                    resolution.usesCoordinateClick
                )
                if best?.rank == 3 { return best }
            }
        }
        for child in children(of: element) {
            if let candidate = findPlaybackMode(
                in: child,
                depth: depth + 1,
                maximumDepth: maximumDepth
            ) {
                if best == nil || candidate.rank > best!.rank {
                    best = candidate
                }
                if best?.rank == 3 { break }
            }
        }
        return best
    }

    nonisolated private static func qqMusicPlaybackModeControl(
        pid: pid_t
    ) -> (element: AXUIElement, mode: NowPlayingPlaybackMode, rank: Int, usesCoordinateClick: Bool)? {
        qqMusicControlRoots(pid: pid)
            .compactMap { findPlaybackMode(in: $0, depth: 0, maximumDepth: 4) }
            .max(by: { $0.rank < $1.rank })
    }

    nonisolated private static func findButton(
        in element: AXUIElement,
        depth: Int,
        matching labels: [String]
    ) -> AXUIElement? {
        guard depth < maximumAccessibilityDepth else { return nil }
        if matchesControlLabels(accessibilityLabels(of: element), expected: labels) {
            return pressableAncestor(of: element) ?? element
        }

        for child in children(of: element) {
            if let match = findButton(in: child, depth: depth + 1, matching: labels) {
                return match
            }
        }
        return nil
    }

    nonisolated private static func children(of element: AXUIElement) -> [AXUIElement] {
        configureAccessibilityTimeout(for: element)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success else { return [] }
        return childrenRef as? [AXUIElement] ?? []
    }

    nonisolated private static func pressableAncestor(of element: AXUIElement) -> AXUIElement? {
        var candidate = element
        for _ in 0..<4 {
            if supportsPress(candidate) { return candidate }

            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                candidate,
                kAXParentAttribute as CFString,
                &parentRef
            ) == .success,
                let parentRef
            else { return nil }
            candidate = unsafeDowncast(parentRef, to: AXUIElement.self)
        }
        return nil
    }

    nonisolated private static func supportsPress(_ element: AXUIElement) -> Bool {
        configureAccessibilityTimeout(for: element)
        var actionsRef: CFArray?
        guard AXUIElementCopyActionNames(element, &actionsRef) == .success,
              let actions = actionsRef as? [String]
        else { return false }
        return actions.contains(kAXPressAction as String)
    }

    nonisolated private static func findQQMusicMenuItem(
        in element: AXUIElement,
        depth: Int,
        matching labels: [String]
    ) -> AXUIElement? {
        guard depth < maximumAccessibilityDepth else { return nil }
        if role(of: element) == kAXMenuItemRole as String,
           supportsPress(element),
           matchesControlLabels(accessibilityLabels(of: element), expected: labels)
        {
            return element
        }
        for child in children(of: element) {
            if let match = findQQMusicMenuItem(in: child, depth: depth + 1, matching: labels) {
                return match
            }
        }
        return nil
    }

    nonisolated private static func findQQMusicFavoriteMenuItem(
        in element: AXUIElement,
        depth: Int
    ) -> (element: AXUIElement, rank: Int)? {
        guard depth < maximumAccessibilityDepth else { return nil }
        var best: (element: AXUIElement, rank: Int)?
        if role(of: element) == kAXMenuItemRole as String,
           supportsPress(element) {
            let rank = favoriteLabelRank(accessibilityLabels(of: element))
            if rank > 0 {
                best = (element, rank)
            }
        }
        for child in children(of: element) {
            if let match = findQQMusicFavoriteMenuItem(in: child, depth: depth + 1),
               best == nil || match.rank > best!.rank
            {
                best = match
            }
        }
        return best
    }

    nonisolated private static func performQQMusicMenuCommand(pid: pid_t, matching labels: [String]) -> Bool {
        guard let item = qqMusicMenuItem(pid: pid, matching: labels) else { return false }
        return performPress(on: item, pid: pid)
    }

    nonisolated private static func qqMusicFavoriteMenuItem(pid: pid_t) -> AXUIElement? {
        guard let menuBar = elementAttribute(
            kAXMenuBarAttribute,
            of: AXUIElementCreateApplication(pid)
        ) else { return nil }
        return findQQMusicFavoriteMenuItem(in: menuBar, depth: 0)?.element
    }

    nonisolated private static func favoriteLabelRank(_ labels: [String]) -> Int {
        let normalized = labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if normalized.contains(where: {
            favoriteEnabledLabels.contains($0)
                || ($0.contains("取消") && ($0.contains("喜欢") || $0.contains("收藏")))
        }) {
            return 3
        }
        if normalized.contains(where: {
            favoriteDisabledLabels.contains($0)
                || ($0.contains("添加") && ($0.contains("喜欢") || $0.contains("收藏")))
        }) {
            return 2
        }
        return normalized.contains(where: { favoriteGenericDisabledLabels.contains($0) }) ? 1 : 0
    }

    nonisolated private static func playbackModeLabelRank(_ labels: [String]) -> Int {
        let normalized = labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard playbackMode(for: labels) != nil else { return 0 }
        if normalized.contains(where: { $0.contains("播放模式") && $0 != "播放模式" }) {
            return 3
        }
        if normalized.contains(where: { $0.contains("播放模式") }) {
            return 1
        }
        return 2
    }

    /// The menu bar is not among the application element's AX children; it is only reachable via kAXMenuBarAttribute.
    nonisolated private static func qqMusicMenuItem(pid: pid_t, matching labels: [String]) -> AXUIElement? {
        guard let menuBar = elementAttribute(
            kAXMenuBarAttribute,
            of: AXUIElementCreateApplication(pid)
        ) else { return nil }
        return findQQMusicMenuItem(in: menuBar, depth: 0, matching: labels)
    }

    nonisolated private static func role(of element: AXUIElement) -> String? {
        configureAccessibilityTimeout(for: element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    nonisolated private static func accessibilityLabels(of element: AXUIElement?) -> [String] {
        guard let element else { return [] }
        configureAccessibilityTimeout(for: element)
        let attributes: [CFString] = [
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXHelpAttribute as CFString,
            kAXValueAttribute as CFString,
            kAXIdentifierAttribute as CFString,
        ]
        var valuesRef: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            [],
            &valuesRef
        ) == .success,
            let values = valuesRef as? [Any]
        else { return [] }
        return values.compactMap { value in
            guard let text = value as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    nonisolated private static func frame(of element: AXUIElement) -> (position: CGPoint, size: CGSize)? {
        configureAccessibilityTimeout(for: element)
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXPositionAttribute as CFString,
                &positionRef
            ) == .success,
            AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeRef
            ) == .success,
            let positionValue = positionRef,
            let sizeValue = sizeRef,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        let axPosition = unsafeDowncast(positionValue, to: AXValue.self)
        let axSize = unsafeDowncast(sizeValue, to: AXValue.self)
        guard AXValueGetValue(axPosition, .cgPoint, &position),
              AXValueGetValue(axSize, .cgSize, &size)
        else { return nil }
        return (position, size)
    }

    nonisolated private static func clickCenter(of element: AXUIElement, pid: pid_t) -> Bool {
        guard let frame = frame(of: element),
              let point = clickPoint(position: frame.position, size: frame.size)
        else { return false }
        return postLeftClick(at: point, pid: pid)
    }

    nonisolated private static func performPress(on element: AXUIElement, pid: pid_t) -> Bool {
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return true
        }
        return clickCenter(of: element, pid: pid)
    }

    nonisolated private static func performPlaybackModeToggle(
        on element: AXUIElement,
        pid: pid_t,
        usesCoordinateClick: Bool
    ) -> Bool {
        if usesCoordinateClick {
            return clickCenter(of: element, pid: pid)
        }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
            || clickCenter(of: element, pid: pid)
    }

    nonisolated private static func matchesControlLabels(
        _ labels: [String],
        expected: [String]
    ) -> Bool {
        labels.contains { label in
            expected.contains { target in
                label.localizedCaseInsensitiveContains(target)
            }
        }
    }

    nonisolated private static let qqMusicControlBarLabel = "播放控制栏"

    /// The window content area exposes links sharing the player controls' labels, which depth-first search reaches earlier;
    /// only the playback-controls container is a safe search root.
    nonisolated private static func qqMusicControlRoots(pid: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(pid)
        var windows: [AXUIElement] = []
        for attribute in [
            kAXFocusedWindowAttribute,
            kAXMainWindowAttribute,
        ] {
            if let window = elementAttribute(attribute, of: application) {
                windows.append(window)
            }
        }
        windows.append(contentsOf: self.windows(of: application))
        return windows.reduce(into: [AXUIElement]()) { roots, window in
            guard !roots.contains(where: { CFEqual($0, window) }) else { return }
            if let controlBar = findControlBar(in: window, depth: 0) {
                roots.append(controlBar)
            }
        }
    }

    nonisolated private static func findControlBar(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 6 else { return nil }
        if accessibilityLabels(of: element).contains(where: {
            $0.contains(qqMusicControlBarLabel)
        }) {
            return element
        }
        for child in children(of: element) {
            if let bar = findControlBar(in: child, depth: depth + 1) {
                return bar
            }
        }
        return nil
    }

    nonisolated private static func windows(of element: AXUIElement) -> [AXUIElement] {
        configureAccessibilityTimeout(for: element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    nonisolated private static func elementAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> AXUIElement? {
        configureAccessibilityTimeout(for: element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
        let value else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    nonisolated private static func configureAccessibilityTimeout(for element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, accessibilityTimeout)
    }
}
