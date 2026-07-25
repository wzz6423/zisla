import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// 针对不完整支持 MediaRemote 的播放器应用的特化配置。
/// 当 MediaRemote 未暴露收藏、播放模式等能力时，
/// 通过应用公开脚本字典或 Accessibility API 补充控制手段。
struct MediaAppProfile: Sendable {
    let bundleIdentifier: String
    let supportsFavorite: Bool
    let supportsFavoriteStateRead: Bool
    let supportsPlaybackControls: Bool
    let supportsPlaybackModeSet: Bool
    let supportsPlaybackModeCycle: Bool
    let defaultPlaybackMode: NowPlayingPlaybackMode
    let favoriteControl: NowPlayingFavoriteControl
}

/// 执行针对特定播放器应用的控制命令。
@MainActor
final class MediaAppSpecialist {
    static let shared = MediaAppSpecialist()

    private let profiles: [String: MediaAppProfile] = [
        "com.apple.Music": MediaAppProfile(
            bundleIdentifier: "com.apple.Music",
            supportsFavorite: true,
            supportsFavoriteStateRead: true,
            supportsPlaybackControls: true,
            supportsPlaybackModeSet: true,
            supportsPlaybackModeCycle: false,
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

    /// Apple Music 使用公开脚本字典；QQ 音乐优先执行无障碍元素的 Press action。
    func toggleFavorite(pid: pid_t?, bundleIdentifier: String?) -> Bool {
        if bundleIdentifier == Self.appleMusicBundleIdentifier {
            return Self.runAppleScript(Self.appleMusicToggleFavoriteScript)
        }
        guard bundleIdentifier == Self.qqMusicBundleIdentifier,
              let pid,
              Self.isAccessibilityTrusted(prompt: true)
        else { return false }
        let app = AXUIElementCreateApplication(pid)
        if let button = Self.findFavoriteButton(in: app, depth: 0),
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
        guard bundleIdentifier == Self.qqMusicBundleIdentifier,
              let pid,
              Self.isAccessibilityTrusted(prompt: false)
        else { return nil }
        return Self.favoriteState(
            for: Self.accessibilityLabels(
                of: Self.findFavoriteButton(
                    in: AXUIElementCreateApplication(pid),
                    depth: 0
                )
            )
        )
    }

    /// Apple Music 与 Spotify 使用公开脚本字典；QQ 音乐使用主播放栏无障碍操作。
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
              Self.isAccessibilityTrusted(prompt: true),
              let labels = Self.playbackLabels(for: command)
        else { return nil }
        guard let button = Self.findButton(
            in: AXUIElementCreateApplication(pid),
            depth: 0,
            matching: labels
        ) else { return nil }
        return Self.performPress(on: button, pid: pid) ? true : nil
    }

    /// Apple Music 的模式属性在公开脚本字典中可写；其它播放器继续走各自的控制通道。
    func setPlaybackMode(
        _ mode: NowPlayingPlaybackMode,
        pid _: pid_t?,
        bundleIdentifier: String?
    ) -> Bool? {
        guard bundleIdentifier == Self.appleMusicBundleIdentifier else { return nil }
        return Self.runAppleScript(Self.appleMusicModeScript(for: mode)) ? true : nil
    }

    /// QQ 音乐通过 Accessibility 标签循环切换。
    func cyclePlaybackMode(
        pid: pid_t?,
        bundleIdentifier: String?,
        currentMode _: NowPlayingPlaybackMode
    ) -> Bool {
        guard bundleIdentifier == Self.qqMusicBundleIdentifier,
              let pid,
              Self.isAccessibilityTrusted(prompt: true)
        else { return false }
        let app = AXUIElementCreateApplication(pid)
        return Self.searchAndClickPlayMode(in: app, depth: 0, pid: pid)
    }

    // MARK: - CGEvent
    private static let appleMusicBundleIdentifier = "com.apple.Music"
    private static let qqMusicBundleIdentifier = "com.tencent.QQMusicMac"

    private static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static let favoriteEnabledLabels = [
        "从我喜欢删除", "取消喜欢", "取消收藏",
    ]
    private static let favoriteDisabledLabels = [
        "添加到我喜欢", "添加到喜欢", "添加收藏",
    ]

    static func favoriteState(for labels: [String]) -> Bool? {
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
        return nil
    }

    /// 纯坐标逻辑：有效 frame 时返回中心点，供单元测试与点击共用。
    static func clickPoint(position: CGPoint, size: CGSize) -> CGPoint? {
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

    /// 纯标签匹配：判断无障碍文案是否指向播放模式控件。
    static func matchesPlayModeLabels(_ labels: [String]) -> Bool {
        labels.contains { label in
            let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            return playModeKeywords.contains { keyword in
                text.localizedCaseInsensitiveContains(keyword)
            }
        }
    }

    /// 纯标签匹配：判断无障碍文案是否指向收藏控件。
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

    private static func playbackLabels(for command: NowPlayingService.Command) -> [String]? {
        switch command {
        case .play:
            ["播放", "继续播放"]
        case .pause:
            ["暂停"]
        case .togglePlayPause:
            ["播放", "暂停", "继续播放"]
        case .previous:
            ["上一首"]
        case .next:
            ["下一首"]
        case .likeTrack, .addTrackToWishList, .removeTrackFromWishList:
            nil
        }
    }

    private static func postLeftClick(at point: CGPoint, pid: pid_t) -> Bool {
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

    private static let playModeKeywords = [
        "循环", "随机", "顺序", "播放模式", "repeat", "shuffle",
    ]

    private static func findFavoriteButton(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 12 else { return nil }
        if favoriteState(for: accessibilityLabels(of: element)) != nil,
           let pressable = pressableAncestor(of: element)
        {
            return pressable
        }

        for child in children(of: element) {
            if let match = findFavoriteButton(in: child, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private static func findButton(
        in element: AXUIElement,
        depth: Int,
        matching labels: [String]
    ) -> AXUIElement? {
        guard depth < 12 else { return nil }
        if accessibilityLabels(of: element).contains(where: { labels.contains($0) }),
           let pressable = pressableAncestor(of: element)
        {
            return pressable
        }

        for child in children(of: element) {
            if let match = findButton(in: child, depth: depth + 1, matching: labels) {
                return match
            }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success else { return [] }
        return childrenRef as? [AXUIElement] ?? []
    }

    private static func pressableAncestor(of element: AXUIElement) -> AXUIElement? {
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

    private static func supportsPress(_ element: AXUIElement) -> Bool {
        var actionsRef: CFArray?
        guard AXUIElementCopyActionNames(element, &actionsRef) == .success,
              let actions = actionsRef as? [String]
        else { return false }
        return actions.contains(kAXPressAction as String)
    }

    private static func accessibilityLabels(of element: AXUIElement?) -> [String] {
        guard let element else { return [] }
        let attributes = [
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXHelpAttribute as CFString,
        ]
        return attributes.compactMap { attribute in
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attribute, &value)
            guard let text = value as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func frame(of element: AXUIElement) -> (position: CGPoint, size: CGSize)? {
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

    private static func clickCenter(of element: AXUIElement, pid: pid_t) -> Bool {
        guard let frame = frame(of: element),
              let point = clickPoint(position: frame.position, size: frame.size)
        else { return false }
        return postLeftClick(at: point, pid: pid)
    }

    private static func performPress(on element: AXUIElement, pid: pid_t) -> Bool {
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return true
        }
        return clickCenter(of: element, pid: pid)
    }

    private static func searchAndClickPlayMode(
        in element: AXUIElement,
        depth: Int,
        pid: pid_t
    ) -> Bool {
        guard depth < 12 else { return false }

        if matchesPlayModeLabels(accessibilityLabels(of: element)),
           let pressable = pressableAncestor(of: element),
           performPress(on: pressable, pid: pid)
        {
            return true
        }

        for child in children(of: element) {
            if searchAndClickPlayMode(in: child, depth: depth + 1, pid: pid) {
                return true
            }
        }
        return false
    }
}
