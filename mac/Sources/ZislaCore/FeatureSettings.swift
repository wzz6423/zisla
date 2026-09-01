import Foundation

/// Display duration of the side notice for persistent collapsed-state activity (playing / AI running·queued).
public enum ActivityNoticeDisplayDuration: String, Codable, CaseIterable, Sendable, Equatable {
    case threeSeconds
    case fiveSeconds
    case tenSeconds
    case thirtySeconds
    case always

    /// Expiry seconds used for enqueueing; `always` is `nil`, meaning it persists until the activity ends.
    public var expiresAfter: Double? {
        switch self {
        case .threeSeconds: 3
        case .fiveSeconds: 5
        case .tenSeconds: 10
        case .thirtySeconds: 30
        case .always: nil
        }
    }

    public var menuTitle: String {
        switch self {
        case .threeSeconds: "3 秒"
        case .fiveSeconds: "5 秒"
        case .tenSeconds: "10 秒"
        case .thirtySeconds: "30 秒"
        case .always: "始终显示"
        }
    }
}

/// Display duration of the side notice when system Focus mode changes.
public enum FocusModeNoticeDisplayDuration: String, Codable, CaseIterable, Sendable, Equatable {
    case threeSeconds
    case always

    public var expiresAfter: Double? {
        switch self {
        case .threeSeconds: 3
        case .always: nil
        }
    }

    public var menuTitle: String {
        switch self {
        case .threeSeconds: "3 秒"
        case .always: "始终显示"
        }
    }
}

/// Default time before the clipboard assistant disappears automatically.
public enum ClipboardAssistantDisplayDuration: String, Codable, CaseIterable, Sendable, Equatable {
    case threeSeconds
    case fiveSeconds
    case sevenSeconds
    case never

    public var expiresAfter: Double? {
        switch self {
        case .threeSeconds: 3
        case .fiveSeconds: 5
        case .sevenSeconds: 7
        case .never: nil
        }
    }

    public var menuTitle: String {
        switch self {
        case .threeSeconds: "3 秒"
        case .fiveSeconds: "5 秒"
        case .sevenSeconds: "7 秒"
        case .never: "永不"
        }
    }
}

/// Appearance mode for regular UI (Settings window, etc.). The Dynamic Island is always dark and unaffected by this setting.
public enum AppearanceMode: String, Codable, CaseIterable, Sendable, Equatable {
    case system
    case light
    case dark

    public var menuTitle: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

/// Target update channel for both automatic and manual checks.
public enum UpdateChannel: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case release
    case preview

    public var menuTitle: String {
        switch self {
        case .release: "Release"
        case .preview: "Preview"
        }
    }

    public var detail: String {
        switch self {
        case .release: "最新正式发布版本"
        case .preview: "最新预览构建，可能包含未稳定功能"
        }
    }
}

/// Music display style in the collapsed Dynamic Island.
public enum MediaCompactStyle: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case compact
    case detailed

    public var title: String {
        switch self {
        case .compact: "简洁模式"
        case .detailed: "详细模式"
        }
    }

    public var detail: String {
        switch self {
        case .compact: "仅在刘海两侧显示封面与音浪"
        case .detailed: "左侧封面、歌名与歌手，右侧音浪与滚动歌词"
        }
    }
}

/// macOS Accessibility Background Sounds names used by the system asset catalog.
public enum SystemBackgroundSound: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case pinkNoise = "PinkNoise"
    case brownNoise = "BrownNoise"
    case whiteNoise = "WhiteNoise"
    // Compatibility with the name saved by macOS 14 and earlier.
    case balancedNoise = "BalancedNoise"
    case brightNoise = "BrightNoise"
    case darkNoise = "DarkNoise"
    case ocean = "Ocean"
    case rain = "Rain"
    case stream = "Stream"
    case night = "Night"
    case fire = "Fire"
    case babble = "Babble"
    case steam = "Steam"
    case airplane = "Airplane"
    case boat = "Boat"
    case bus = "Bus"
    case train = "Train"
    case rainOnRoof = "RainOnRoof"
    case quietNight = "QuietNight"

    public static let allCases: [Self] = [
        .pinkNoise, .brownNoise, .whiteNoise,
        .balancedNoise, .brightNoise, .darkNoise,
        .ocean, .rain, .stream, .night, .fire, .babble, .steam,
        .airplane, .boat, .bus, .train, .rainOnRoof, .quietNight,
    ]

    public var title: String {
        switch self {
        case .pinkNoise: "粉红噪声"
        case .brownNoise: "棕色噪声"
        case .whiteNoise: "白噪声"
        case .balancedNoise: "平衡噪声"
        case .brightNoise: "亮噪声"
        case .darkNoise: "暗噪声"
        case .ocean: "海洋"
        case .rain: "雨声"
        case .stream: "溪流"
        case .night: "夜晚"
        case .fire: "火苗"
        case .babble: "嘈杂声"
        case .steam: "蒸汽"
        case .airplane: "飞机"
        case .boat: "船"
        case .bus: "公交车"
        case .train: "火车"
        case .rainOnRoof: "屋顶雨声"
        case .quietNight: "静夜"
        }
    }
}

public enum MailCompactStyle: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case compact
    case detailed

    public var title: String {
        switch self {
        case .compact: "简洁模式"
        case .detailed: "详细模式"
        }
    }

    public var detail: String {
        switch self {
        case .compact: "左侧邮件图标，右侧新邮件数量"
        case .detailed: "左侧主题，右侧发件人与新邮件数量"
        }
    }
}

/// Visual style of the Dynamic Island surface.
public enum IslandVisualStyle: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    /// Existing smoky frosted glass; preserves the historical default look.
    case frosted
    /// More translucent transmissive glass, close to macOS 27 Liquid Glass.
    case transparent

    public var title: String {
        switch self {
        case .frosted: "磨砂玻璃"
        case .transparent: "Liquid Glass"
        }
    }

    public var detail: String {
        switch self {
        case .frosted: "可视化更好"
        case .transparent: "更美观"
        }
    }
}

/// Background of the collapsed notch surface.
public enum IslandNotchBackground: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case black
    case frosted

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "liquidGlass" {
            self = .frosted
            return
        }
        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown island notch background: \(rawValue)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var title: String {
        switch self {
        case .black: "刘海"
        case .frosted: "磨砂玻璃"
        }
    }

    public var detail: String {
        switch self {
        case .black: "收起时保留刘海外观"
        case .frosted: "收起时显示磨砂玻璃背景"
        }
    }
}

/// The system Now Playing source the media module should follow; automatic mode keeps the current system target.
public enum MediaSourcePreference: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case automatic
    case appleMusic
    case spotify
    case qqMusic
    case amazonMusic
    case cider

    public var title: String {
        switch self {
        case .automatic: "自动"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .qqMusic: "QQ 音乐"
        case .amazonMusic: "Amazon Music"
        case .cider: "Cider"
        }
    }

    public var detail: String {
        switch self {
        case .automatic: "跟随系统当前正在播放的媒体"
        default: "仅显示和控制所选播放器的媒体"
        }
    }

    public var bundleIdentifiers: [String] {
        switch self {
        case .automatic: []
        case .appleMusic: ["com.apple.Music"]
        case .spotify: ["com.spotify.client"]
        case .qqMusic: ["com.tencent.QQMusicMac"]
        case .amazonMusic: ["com.amazon.music"]
        case .cider: ["sh.cider.genten.mac", "sh.cider.genten"]
        }
    }

    public var bundleIdentifier: String? { bundleIdentifiers.first }

    public func matches(bundleIdentifier: String?) -> Bool {
        guard !bundleIdentifiers.isEmpty else { return true }
        guard let bundleIdentifier else { return false }
        return bundleIdentifiers.contains(bundleIdentifier)
    }
}

/// Metrics that can be pinned individually to the menu bar and jump to the system monitor panel on click.
public enum SystemMonitorMenuBarMetric: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case cpu
    case gpu
    case memory
    case disk
    case network
    case fan

    public var menuTitle: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "内存"
        case .disk: "磁盘"
        case .network: "网络"
        case .fan: "风扇"
        }
    }

    public var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "memorychip"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .fan: "fan"
        }
    }
}

/// Display style of the menu bar monitor status items.
public enum SystemMonitorMenuBarDisplayStyle: String, Codable, CaseIterable, Sendable, Equatable {
    case detailed
    case compact

    public var menuTitle: String {
        switch self {
        case .detailed: "详细"
        case .compact: "紧凑"
        }
    }
}

public enum VoiceRecordingCleanupPolicy: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case sevenDays
    case fifteenDays
    case thirtyDays
    case never

    public var menuTitle: String {
        switch self {
        case .sevenDays: "7 天"
        case .fifteenDays: "15 天"
        case .thirtyDays: "30 天"
        case .never: "永不清理"
        }
    }

    public var daysThreshold: Int? {
        switch self {
        case .sevenDays: 7
        case .fifteenDays: 15
        case .thirtyDays: 30
        case .never: nil
        }
    }
}

public enum ScreenshotHotkeyDefaults {
    public static let capture = VoiceInputHotkeyPreset(
        keyCode: 18,
        carbonModifiers: 0x1000,
        keyDisplayName: "1"
    )
    public static let pin = VoiceInputHotkeyPreset(
        keyCode: 19,
        carbonModifiers: 0x1000,
        keyDisplayName: "2"
    )
}

public enum CompactStatusPriority: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case transient
    case updateAvailable
    case mail
    case videoDownload
    case browserDownload
    case focusCountdown
    case toolboxReminder
    case aiActivity
    case media
    case focusMode

    public static let defaultOrder: [Self] = [
        .transient,
        .videoDownload,
        .browserDownload,
        .mail,
        .updateAvailable,
        .focusCountdown,
        .focusMode,
        .aiActivity,
        .media,
        .toolboxReminder,
    ]

    public var title: String {
        switch self {
        case .transient: "临时提示"
        case .updateAvailable: "可用更新"
        case .mail: "新邮件"
        case .videoDownload: "视频下载"
        case .browserDownload: "浏览器下载"
        case .focusCountdown: "专注倒计时"
        case .toolboxReminder: "工具箱提醒"
        case .aiActivity: "AI 活动"
        case .media: "正在播放"
        case .focusMode: "专注模式"
        }
    }

    public static func normalized(_ priorities: [Self]) -> [Self] {
        var seen: Set<Self> = []
        let uniquePriorities = priorities.filter { seen.insert($0).inserted }
        return uniquePriorities + defaultOrder.filter { !seen.contains($0) }
    }
}

/// Feature module toggles default to on.
public struct FeatureSettings: Codable, Equatable, Sendable {
    public var mediaEnabled: Bool
    public var mediaSource: MediaSourcePreference
    public var fileShelfEnabled: Bool
    public var aiProgressEnabled: Bool
    public var downloaderEnabled: Bool
    public var calendarEnabled: Bool
    public var toolboxEnabled: Bool
    public var pdfToolsEnabled: Bool
    public var toolboxReminderEnabled: Bool
    /// Whether to show a countdown in the collapsed Dynamic Island during Focus sessions.
    public var focusCountdownIslandEnabled: Bool
    /// Whether to show the source icon and percentage in the collapsed Dynamic Island during browser downloads.
    public var browserDownloadIslandEnabled: Bool
    /// Whether to show the source platform logo and percentage in the collapsed Dynamic Island while the native downloader is active.
    public var videoDownloadIslandEnabled: Bool
    public var systemMonitorEnabled: Bool
    /// Whether zisla should play the selected macOS background sound locally.
    public var systemBackgroundSoundEnabled: Bool
    /// The macOS background sound selected for local playback.
    public var systemBackgroundSound: SystemBackgroundSound
    /// Whether playback stops when the Mac is locked, enters the screen saver, or sleeps.
    public var systemBackgroundSoundStopsWhenUnused: Bool
    /// Battery monitor: independent toggle for the battery detail module and status tracking.
    public var batteryMonitorEnabled: Bool
    /// When empty, no additional monitor status bar items are added.
    public var systemMonitorMenuBarMetrics: Set<SystemMonitorMenuBarMetric>
    /// Detailed mode retains the existing icon and horizontal readings; compact mode hides the icon and reduces font size.
    public var systemMonitorMenuBarDisplayStyle: SystemMonitorMenuBarDisplayStyle
    /// Whether to show Zisla's menu bar icon separately; does not affect monitor status items.
    public var menuBarAppIconEnabled: Bool
    public var weatherEnabled: Bool
    public var lockScreenInfoEnabled: Bool
    /// User-defined text shown above the native lock-screen clock; empty string means nothing is shown.
    public var lockScreenMessage: String
    /// Whether to show the lunar calendar above the native lock-screen clock; can be shown alongside the custom message.
    public var lockScreenShowsLunar: Bool
    public var quickNotesEnabled: Bool
    /// Mail integration; users can disable it in Settings if they don't want inbox metadata to be read.
    public var mailEnabled: Bool
    /// An empty set means all configured system Mail.app accounts are synced.
    public var mailAccountNames: Set<String>
    public var mailCompactStyle: MailCompactStyle
    public var updateChecksEnabled: Bool
    public var automaticDownloadEnabled: Bool
    /// Target channel for automatic and manual update checks.
    public var updateChannel: UpdateChannel
    /// Optional proxy URL used by local update, install, and network download tasks.
    public var networkProxyURL: String
    /// Whether local update, install, and network download tasks should use the configured proxy.
    public var networkProxyEnabled: Bool
    /// Whether to save clipboard text and images locally; users can disable it in Settings if concerned about sensitive content.
    public var clipboardHistoryEnabled: Bool
    /// Whether to detect downloadable links in clipboard; users can disable it in Settings.
    public var clipboardDetectionEnabled: Bool
    /// Whether copying shows the assistant toast with a recognized result and next-step action.
    public var clipboardAssistantEnabled: Bool
    /// Quick trigger hotkey firing the assistant's primary action while its toast is visible.
    /// Modifier-only presets fire on double-tap; ordinary combos fire on key-down.
    public var clipboardAssistantTriggerConfiguration: ClipboardAssistantTriggerConfiguration
    /// Mouse side button (CGEvent button number, e.g. 3 = back) firing the primary action; `nil` disables it.
    public var clipboardAssistantMouseButton: Int?
    /// Bundle identifiers of apps whose copies never trigger the assistant toast.
    public var clipboardAssistantBlacklist: Set<String>
    /// Recognized content kinds; an empty set falls back to all kinds.
    public var clipboardAssistantEnabledKinds: Set<ClipboardAssistantKind>
    /// Primary action and expanded-menu order for each recognized content kind.
    public var clipboardAssistantActionOrders: [ClipboardAssistantKind: [ClipboardAssistantActionKind]]
    /// Engine used by the assistant's "search" action for copied text.
    public var clipboardAssistantSearchEngine: ClipboardAssistantSearchEngine
    public var clipboardAssistantCustomSearchURL: String
    /// Lightweight reminder mode: compact toast without buttons; tapping it performs the primary action.
    public var clipboardAssistantLightweightMode: Bool
    /// Default time before the clipboard assistant closes automatically.
    public var clipboardAssistantDisplayDuration: ClipboardAssistantDisplayDuration
    /// Whether image saves should ask for a destination instead of using the shared download directory.
    public var clipboardAssistantPromptsForImageSaveLocation: Bool
    /// Hold left mouse button + right-click to copy the selection (simulated ⌘C); off by default.
    /// Requires input monitoring and accessibility permissions.
    public var clipboardAssistantMouseGestureEnabled: Bool
    public var sideNoticesEnabled: Bool
    public var compactStatusPriority: [CompactStatusPriority]
    /// Temporarily suppresses system notifications pushed by Zisla itself (Pomodoro, etc.); alarms are unaffected.
    public var notificationsMuted: Bool
    public var hoverActivationEnabled: Bool
    public var activityNoticeDisplayDuration: ActivityNoticeDisplayDuration
    public var focusModeNoticeDisplayDuration: FocusModeNoticeDisplayDuration
    /// An empty set means activity notices appear on all currently connected displays.
    public var activityNoticeDisplayIDs: Set<UInt32>
    public var appearanceMode: AppearanceMode
    /// Whether to keep a pet beside the Dynamic Island (compatible with Codex hatch-pet format; pets sourced from codex-pets.net and similar community libraries).
    public var petEnabled: Bool
    /// The currently selected pet id (corresponds to a built-in or imported pet in `PetLibrary`).
    public var petID: String
    /// Which side of the Dynamic Island the pet appears on.
    public var petSide: PetSide
    /// Whether the Dynamic Island shows lyrics and song info while music plays.
    public var mediaShowLyricsAndInfo: Bool
    /// Display style for the collapsed Dynamic Island when music is playing.
    public var mediaCompactStyle: MediaCompactStyle
    /// Visual style of the Dynamic Island surface.
    public var islandVisualStyle: IslandVisualStyle
    /// Background of the collapsed notch surface.
    public var islandNotchBackground: IslandNotchBackground
    /// Whether the collapsed Dynamic Island floats above other windows; when off, it is covered by other windows and menu bar icons.
    public var islandCollapsedOnTop: Bool
    public var voiceInputEnabled: Bool
    public var voiceInputMode: VoiceInputMode
    public var voiceInputHotkeyPreset: VoiceInputHotkeyPreset
    public var voiceRecordingRetentionEnabled: Bool
    public var voiceRecordingCleanupPolicy: VoiceRecordingCleanupPolicy
    /// Current model configuration for voice processing. Endpoint and credentials remain in voice settings.
    public var voiceModelConfiguration: AIModelConfigurationReference?
    /// Built-in vocabulary sets used to bias ASR and guide transcript typo correction.
    public var voiceEnabledLexicons: Set<VoiceLexicon>
    /// User-defined hotwords used alongside the enabled built-in vocabulary sets.
    public var voiceCustomHotwords: [String]
    /// Whether to format explicitly enumerated items into numbered lists during voice transcript cleanup.
    public var voiceStructuredFormattingEnabled: Bool
    /// Whether screenshot capture and its global hotkeys are enabled.
    public var screenshotEnabled: Bool
    /// Global hotkey for capturing a screenshot.
    public var screenshotHotkey: VoiceInputHotkeyPreset
    /// Global hotkey for toggling screenshot pin state.
    public var screenshotPinHotkey: VoiceInputHotkeyPreset
    /// Whether the pinned screenshot shows its bottom control bar.
    public var screenshotPinnedToolbarVisible: Bool
    /// Whether the integrated keyboard sounds are enabled.
    public var keyboardEnabled: Bool
    public var keyboardSelectedProfileID: String
    public var keyboardVolume: Double
    public var keyboardPlaysReleaseSound: Bool
    public var keyboardUsesPitchVariation: Bool
    public var keyboardTypingStatsEnabled: Bool
    /// Whether keyboard typing sound (Battuta) is enabled.
    public var battutaEnabled: Bool
    /// Selected keyboard sound profile ID.
    public var battutaSelectedProfileID: String
    /// Keyboard sound volume (0.0 - 1.0).
    public var battutaVolume: Double
    /// Whether to play key release sounds.
    public var battutaPlaysReleaseSound: Bool
    /// Whether to use pitch variation for natural sound.
    public var battutaUsesPitchVariation: Bool
    /// Whether pointer (mouse) click sound is enabled.
    public var battutaPointerSoundEnabled: Bool
    /// Selected pointer sound profile ID.
    public var battutaSelectedPointerProfileID: String
    /// Pointer sound volume (0.0 - 1.0).
    public var battutaPointerVolume: Double
    /// Whether to play pointer release sounds.
    public var battutaPlaysPointerReleaseSound: Bool

    public init(
        mediaEnabled: Bool = true,
        mediaSource: MediaSourcePreference = .automatic,
        fileShelfEnabled: Bool = true,
        aiProgressEnabled: Bool = true,
        downloaderEnabled: Bool = true,
        calendarEnabled: Bool = true,
        toolboxEnabled: Bool = true,
        pdfToolsEnabled: Bool = true,
        toolboxReminderEnabled: Bool = true,
        focusCountdownIslandEnabled: Bool = true,
        browserDownloadIslandEnabled: Bool = true,
        videoDownloadIslandEnabled: Bool = true,
        systemMonitorEnabled: Bool = true,
        systemBackgroundSoundEnabled: Bool = false,
        systemBackgroundSound: SystemBackgroundSound = .rain,
        systemBackgroundSoundStopsWhenUnused: Bool = true,
        batteryMonitorEnabled: Bool = true,
        systemMonitorMenuBarMetrics: Set<SystemMonitorMenuBarMetric> = [.cpu],
        systemMonitorMenuBarDisplayStyle: SystemMonitorMenuBarDisplayStyle = .compact,
        menuBarAppIconEnabled: Bool = false,
        weatherEnabled: Bool = true,
        lockScreenInfoEnabled: Bool = true,
        lockScreenMessage: String = "",
        lockScreenShowsLunar: Bool = true,
        quickNotesEnabled: Bool = true,
        mailEnabled: Bool = true,
        mailAccountNames: Set<String> = [],
        mailCompactStyle: MailCompactStyle = .compact,
        updateChecksEnabled: Bool = true,
        automaticDownloadEnabled: Bool = true,
        updateChannel: UpdateChannel = .release,
        networkProxyURL: String = "",
        networkProxyEnabled: Bool = false,
        clipboardHistoryEnabled: Bool = true,
        clipboardDetectionEnabled: Bool = true,
        clipboardAssistantEnabled: Bool = true,
        clipboardAssistantTriggerConfiguration: ClipboardAssistantTriggerConfiguration = .default,
        clipboardAssistantMouseButton: Int? = nil,
        clipboardAssistantBlacklist: Set<String> = [],
        clipboardAssistantEnabledKinds: Set<ClipboardAssistantKind> = Set(ClipboardAssistantKind.allCases),
        clipboardAssistantActionOrders: [ClipboardAssistantKind: [ClipboardAssistantActionKind]] = [:],
        clipboardAssistantSearchEngine: ClipboardAssistantSearchEngine = .google,
        clipboardAssistantCustomSearchURL: String = "",
        clipboardAssistantLightweightMode: Bool = false,
        clipboardAssistantDisplayDuration: ClipboardAssistantDisplayDuration = .fiveSeconds,
        clipboardAssistantPromptsForImageSaveLocation: Bool = false,
        clipboardAssistantMouseGestureEnabled: Bool = false,
        sideNoticesEnabled: Bool = true,
        compactStatusPriority: [CompactStatusPriority] = CompactStatusPriority.defaultOrder,
        notificationsMuted: Bool = false,
        hoverActivationEnabled: Bool = true,
        activityNoticeDisplayDuration: ActivityNoticeDisplayDuration = .threeSeconds,
        focusModeNoticeDisplayDuration: FocusModeNoticeDisplayDuration = .threeSeconds,
        activityNoticeDisplayIDs: Set<UInt32> = [],
        appearanceMode: AppearanceMode = .system,
        petEnabled: Bool = true,
        petID: String = "panda",
        petSide: PetSide = .left,
        mediaShowLyricsAndInfo: Bool = true,
        mediaCompactStyle: MediaCompactStyle = .compact,
        islandVisualStyle: IslandVisualStyle = .transparent,
        islandNotchBackground: IslandNotchBackground = .black,
        islandCollapsedOnTop: Bool = true,
        voiceInputEnabled: Bool = true,
        voiceInputMode: VoiceInputMode = .toggle,
        voiceInputHotkeyPreset: VoiceInputHotkeyPreset = .optionSpace,
        voiceRecordingRetentionEnabled: Bool = true,
        voiceRecordingCleanupPolicy: VoiceRecordingCleanupPolicy = .never,
        voiceModelConfiguration: AIModelConfigurationReference? = nil,
        voiceEnabledLexicons: Set<VoiceLexicon> = VoiceLexicon.defaultEnabled,
        voiceCustomHotwords: [String] = [],
        voiceStructuredFormattingEnabled: Bool = true,
        screenshotEnabled: Bool = true,
        screenshotHotkey: VoiceInputHotkeyPreset = ScreenshotHotkeyDefaults.capture,
        screenshotPinHotkey: VoiceInputHotkeyPreset = ScreenshotHotkeyDefaults.pin,
        screenshotPinnedToolbarVisible: Bool = true,
        keyboardEnabled: Bool = false,
        keyboardSelectedProfileID: String = "holypanda",
        keyboardVolume: Double = 0.75,
        keyboardPlaysReleaseSound: Bool = true,
        keyboardUsesPitchVariation: Bool = true,
        keyboardTypingStatsEnabled: Bool = false,
        battutaEnabled: Bool = false,
        battutaSelectedProfileID: String = "holypanda",
        battutaVolume: Double = 0.75,
        battutaPlaysReleaseSound: Bool = true,
        battutaUsesPitchVariation: Bool = true,
        battutaPointerSoundEnabled: Bool = false,
        battutaSelectedPointerProfileID: String = "classic",
        battutaPointerVolume: Double = 0.5,
        battutaPlaysPointerReleaseSound: Bool = true
    ) {
        self.mediaEnabled = mediaEnabled
        self.mediaSource = mediaSource
        self.fileShelfEnabled = fileShelfEnabled
        self.aiProgressEnabled = aiProgressEnabled
        self.downloaderEnabled = downloaderEnabled
        self.calendarEnabled = calendarEnabled
        self.toolboxEnabled = toolboxEnabled
        self.pdfToolsEnabled = pdfToolsEnabled
        self.toolboxReminderEnabled = toolboxReminderEnabled
        self.focusCountdownIslandEnabled = focusCountdownIslandEnabled
        self.browserDownloadIslandEnabled = browserDownloadIslandEnabled
        self.videoDownloadIslandEnabled = videoDownloadIslandEnabled
        self.systemMonitorEnabled = systemMonitorEnabled
        self.systemBackgroundSoundEnabled = systemBackgroundSoundEnabled
        self.systemBackgroundSound = systemBackgroundSound
        self.systemBackgroundSoundStopsWhenUnused = systemBackgroundSoundStopsWhenUnused
        self.batteryMonitorEnabled = batteryMonitorEnabled
        self.systemMonitorMenuBarMetrics = systemMonitorMenuBarMetrics
        self.systemMonitorMenuBarDisplayStyle = systemMonitorMenuBarDisplayStyle
        self.menuBarAppIconEnabled = menuBarAppIconEnabled
        self.weatherEnabled = weatherEnabled
        self.lockScreenInfoEnabled = lockScreenInfoEnabled
        self.lockScreenMessage = lockScreenMessage
        self.lockScreenShowsLunar = lockScreenShowsLunar
        self.quickNotesEnabled = quickNotesEnabled
        self.mailEnabled = mailEnabled
        self.mailAccountNames = mailAccountNames
        self.mailCompactStyle = mailCompactStyle
        self.updateChecksEnabled = updateChecksEnabled
        self.automaticDownloadEnabled = automaticDownloadEnabled
        self.updateChannel = updateChannel
        self.networkProxyURL = networkProxyURL
        self.networkProxyEnabled = networkProxyEnabled
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.clipboardDetectionEnabled = clipboardDetectionEnabled
        self.clipboardAssistantEnabled = clipboardAssistantEnabled
        self.clipboardAssistantTriggerConfiguration = clipboardAssistantTriggerConfiguration
        self.clipboardAssistantMouseButton = clipboardAssistantMouseButton
        self.clipboardAssistantBlacklist = clipboardAssistantBlacklist
        self.clipboardAssistantEnabledKinds =
            clipboardAssistantEnabledKinds.isEmpty
            ? Set(ClipboardAssistantKind.allCases)
            : clipboardAssistantEnabledKinds
        self.clipboardAssistantActionOrders = ClipboardAssistantActionOrder.normalized(
            clipboardAssistantActionOrders
        )
        self.clipboardAssistantSearchEngine = clipboardAssistantSearchEngine
        self.clipboardAssistantCustomSearchURL = clipboardAssistantCustomSearchURL
        self.clipboardAssistantLightweightMode = clipboardAssistantLightweightMode
        self.clipboardAssistantDisplayDuration = clipboardAssistantDisplayDuration
        self.clipboardAssistantPromptsForImageSaveLocation = clipboardAssistantPromptsForImageSaveLocation
        self.clipboardAssistantMouseGestureEnabled = clipboardAssistantMouseGestureEnabled
        self.sideNoticesEnabled = sideNoticesEnabled
        self.compactStatusPriority = CompactStatusPriority.normalized(compactStatusPriority)
        self.notificationsMuted = notificationsMuted
        self.hoverActivationEnabled = hoverActivationEnabled
        self.activityNoticeDisplayDuration = activityNoticeDisplayDuration
        self.focusModeNoticeDisplayDuration = focusModeNoticeDisplayDuration
        self.activityNoticeDisplayIDs = activityNoticeDisplayIDs
        self.appearanceMode = appearanceMode
        self.petEnabled = petEnabled
        self.petID = petID
        self.petSide = petSide
        self.mediaShowLyricsAndInfo = mediaShowLyricsAndInfo
        self.mediaCompactStyle = mediaCompactStyle
        self.islandVisualStyle = islandVisualStyle
        self.islandNotchBackground = islandNotchBackground
        self.islandCollapsedOnTop = islandCollapsedOnTop
        self.voiceInputEnabled = voiceInputEnabled
        self.voiceInputMode = voiceInputMode
        self.voiceInputHotkeyPreset = voiceInputHotkeyPreset
        self.voiceRecordingRetentionEnabled = voiceRecordingRetentionEnabled
        self.voiceRecordingCleanupPolicy = voiceRecordingCleanupPolicy
        self.voiceModelConfiguration = voiceModelConfiguration
        self.voiceEnabledLexicons = voiceEnabledLexicons
        self.voiceCustomHotwords = VoiceLexicon.normalizedCustomTerms(voiceCustomHotwords)
        self.voiceStructuredFormattingEnabled = voiceStructuredFormattingEnabled
        self.screenshotEnabled = screenshotEnabled
        self.screenshotHotkey = screenshotHotkey
        self.screenshotPinHotkey = screenshotPinHotkey
        self.screenshotPinnedToolbarVisible = screenshotPinnedToolbarVisible
        self.keyboardEnabled = keyboardEnabled
        self.keyboardSelectedProfileID = keyboardSelectedProfileID
        self.keyboardVolume = keyboardVolume
        self.keyboardPlaysReleaseSound = keyboardPlaysReleaseSound
        self.keyboardUsesPitchVariation = keyboardUsesPitchVariation
        self.keyboardTypingStatsEnabled = keyboardTypingStatsEnabled
        self.battutaEnabled = battutaEnabled
        self.battutaSelectedProfileID = battutaSelectedProfileID
        self.battutaVolume = battutaVolume
        self.battutaPlaysReleaseSound = battutaPlaysReleaseSound
        self.battutaUsesPitchVariation = battutaUsesPitchVariation
        self.battutaPointerSoundEnabled = battutaPointerSoundEnabled
        self.battutaSelectedPointerProfileID = battutaSelectedPointerProfileID
        self.battutaPointerVolume = battutaPointerVolume
        self.battutaPlaysPointerReleaseSound = battutaPlaysPointerReleaseSound
    }

    /// Falls back to all current displays when all selected displays are disconnected, so activity notices remain visible.
    public func resolvedActivityNoticeDisplayIDs(
        from connectedDisplayIDs: Set<UInt32>
    ) -> Set<UInt32> {
        let selected = activityNoticeDisplayIDs.intersection(connectedDisplayIDs)
        return selected.isEmpty ? connectedDisplayIDs : selected
    }

    /// Syncs all accounts when the user has not narrowed the scope; does not automatically add new accounts once a filter has been set.
    public func resolvedMailAccountNames(from availableAccountNames: Set<String>) -> Set<String> {
        guard !mailAccountNames.isEmpty else { return availableAccountNames }
        return mailAccountNames.intersection(availableAccountNames)
    }

    public static let `default` = FeatureSettings()

    private enum CodingKeys: String, CodingKey {
        case mediaEnabled
        case mediaSource
        case fileShelfEnabled
        case aiProgressEnabled
        case downloaderEnabled
        case calendarEnabled
        case toolboxEnabled
        case pdfToolsEnabled
        case toolboxReminderEnabled
        case focusCountdownIslandEnabled
        case browserDownloadIslandEnabled
        case videoDownloadIslandEnabled
        case systemMonitorEnabled
        case systemBackgroundSoundEnabled
        case systemBackgroundSound
        case systemBackgroundSoundStopsWhenUnused
        case batteryMonitorEnabled
        case systemMonitorMenuBarMetrics
        case systemMonitorMenuBarDisplayStyle
        case menuBarAppIconEnabled
        case weatherEnabled
        case lockScreenInfoEnabled
        case lockScreenMessage
        case lockScreenShowsLunar
        case quickNotesEnabled
        case mailEnabled
        case mailAccountNames
        case mailCompactStyle
        case updateChecksEnabled
        case automaticDownloadEnabled
        case updateChannel
        case networkProxyURL
        case networkProxyEnabled
        case clipboardHistoryEnabled
        case clipboardDetectionEnabled
        case clipboardAssistantEnabled
        case clipboardAssistantTriggerConfiguration
        case clipboardAssistantMouseButton
        case clipboardAssistantBlacklist
        case clipboardAssistantEnabledKinds
        case clipboardAssistantActionOrders
        case clipboardAssistantSearchEngine
        case clipboardAssistantCustomSearchURL
        case clipboardAssistantLightweightMode
        case clipboardAssistantDisplayDuration
        case clipboardAssistantPromptsForImageSaveLocation
        case clipboardAssistantMouseGestureEnabled
        case sideNoticesEnabled
        case compactStatusPriority
        case notificationsMuted
        case hoverActivationEnabled
        case activityNoticeDisplayDuration
        case focusModeNoticeDisplayDuration
        case activityNoticeDisplayIDs
        case appearanceMode
        case petEnabled
        case petID
        case petSide
        case mediaShowLyricsAndInfo
        case mediaCompactStyle
        case islandVisualStyle
        case islandNotchBackground
        case islandCollapsedOnTop
        case voiceInputEnabled
        case voiceInputMode
        case voiceInputHotkeyPreset
        case voiceRecordingRetentionEnabled
        case voiceRecordingCleanupPolicy
        case voiceModelConfiguration
        case voiceEnabledLexicons
        case voiceCustomHotwords
        case voiceStructuredFormattingEnabled
        case screenshotEnabled
        case screenshotHotkey
        case screenshotPinHotkey
        case screenshotPinnedToolbarVisible
        case keyboardEnabled
        case keyboardSelectedProfileID
        case keyboardVolume
        case keyboardPlaysReleaseSound
        case keyboardUsesPitchVariation
        case keyboardTypingStatsEnabled
        case battutaEnabled
        case battutaSelectedProfileID
        case battutaVolume
        case battutaPlaysReleaseSound
        case battutaUsesPitchVariation
        case battutaPointerSoundEnabled
        case battutaSelectedPointerProfileID
        case battutaPointerVolume
        case battutaPlaysPointerReleaseSound
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case automaticUpdatesEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FeatureSettings.default
        mediaEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaEnabled) ?? defaults.mediaEnabled
        mediaSource = try container.decodeIfPresent(MediaSourcePreference.self, forKey: .mediaSource) ?? defaults.mediaSource
        fileShelfEnabled = try container.decodeIfPresent(Bool.self, forKey: .fileShelfEnabled) ?? defaults.fileShelfEnabled
        aiProgressEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiProgressEnabled) ?? defaults.aiProgressEnabled
        downloaderEnabled = try container.decodeIfPresent(Bool.self, forKey: .downloaderEnabled) ?? defaults.downloaderEnabled
        calendarEnabled = try container.decodeIfPresent(Bool.self, forKey: .calendarEnabled) ?? defaults.calendarEnabled
        toolboxEnabled = try container.decodeIfPresent(Bool.self, forKey: .toolboxEnabled) ?? defaults.toolboxEnabled
        pdfToolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .pdfToolsEnabled) ?? defaults.pdfToolsEnabled
        toolboxReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .toolboxReminderEnabled) ?? defaults.toolboxReminderEnabled
        focusCountdownIslandEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .focusCountdownIslandEnabled
        ) ?? defaults.focusCountdownIslandEnabled
        browserDownloadIslandEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .browserDownloadIslandEnabled
        ) ?? defaults.browserDownloadIslandEnabled
        videoDownloadIslandEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .videoDownloadIslandEnabled
        ) ?? defaults.videoDownloadIslandEnabled
        systemMonitorEnabled = try container.decodeIfPresent(Bool.self, forKey: .systemMonitorEnabled) ?? defaults.systemMonitorEnabled
        systemBackgroundSoundEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .systemBackgroundSoundEnabled
        ) ?? defaults.systemBackgroundSoundEnabled
        systemBackgroundSound = try container.decodeIfPresent(
            SystemBackgroundSound.self,
            forKey: .systemBackgroundSound
        ) ?? defaults.systemBackgroundSound
        systemBackgroundSoundStopsWhenUnused = try container.decodeIfPresent(
            Bool.self,
            forKey: .systemBackgroundSoundStopsWhenUnused
        ) ?? defaults.systemBackgroundSoundStopsWhenUnused
        batteryMonitorEnabled = try container.decodeIfPresent(Bool.self, forKey: .batteryMonitorEnabled) ?? defaults.batteryMonitorEnabled
        systemMonitorMenuBarMetrics = try container.decodeIfPresent(
            Set<SystemMonitorMenuBarMetric>.self,
            forKey: .systemMonitorMenuBarMetrics
        ) ?? defaults.systemMonitorMenuBarMetrics
        systemMonitorMenuBarDisplayStyle = try container.decodeIfPresent(
            SystemMonitorMenuBarDisplayStyle.self,
            forKey: .systemMonitorMenuBarDisplayStyle
        ) ?? defaults.systemMonitorMenuBarDisplayStyle
        menuBarAppIconEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .menuBarAppIconEnabled
        ) ?? defaults.menuBarAppIconEnabled
        weatherEnabled = try container.decodeIfPresent(Bool.self, forKey: .weatherEnabled) ?? defaults.weatherEnabled
        lockScreenInfoEnabled = try container.decodeIfPresent(Bool.self, forKey: .lockScreenInfoEnabled) ?? defaults.lockScreenInfoEnabled
        lockScreenMessage = try container.decodeIfPresent(String.self, forKey: .lockScreenMessage) ?? defaults.lockScreenMessage
        lockScreenShowsLunar = try container.decodeIfPresent(Bool.self, forKey: .lockScreenShowsLunar) ?? defaults.lockScreenShowsLunar
        quickNotesEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickNotesEnabled) ?? defaults.quickNotesEnabled
        mailEnabled = try container.decodeIfPresent(Bool.self, forKey: .mailEnabled) ?? defaults.mailEnabled
        mailAccountNames = try container.decodeIfPresent(Set<String>.self, forKey: .mailAccountNames) ?? defaults.mailAccountNames
        mailCompactStyle = try container.decodeIfPresent(MailCompactStyle.self, forKey: .mailCompactStyle) ?? defaults.mailCompactStyle
        updateChecksEnabled = try container.decodeIfPresent(Bool.self, forKey: .updateChecksEnabled) ?? defaults.updateChecksEnabled
        if let automaticDownload = try container.decodeIfPresent(Bool.self, forKey: .automaticDownloadEnabled) {
            automaticDownloadEnabled = automaticDownload
        } else {
            let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
            automaticDownloadEnabled = try legacyContainer.decodeIfPresent(Bool.self, forKey: .automaticUpdatesEnabled) ?? defaults.automaticDownloadEnabled
        }
        updateChannel = try container.decodeIfPresent(UpdateChannel.self, forKey: .updateChannel) ?? defaults.updateChannel
        networkProxyURL = try container.decodeIfPresent(String.self, forKey: .networkProxyURL) ?? defaults.networkProxyURL
        networkProxyEnabled = try container.decodeIfPresent(Bool.self, forKey: .networkProxyEnabled)
            ?? (!networkProxyURL.isEmpty)
        clipboardHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? defaults.clipboardHistoryEnabled
        clipboardDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardDetectionEnabled) ?? defaults.clipboardDetectionEnabled
        clipboardAssistantEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .clipboardAssistantEnabled
        ) ?? defaults.clipboardAssistantEnabled
        clipboardAssistantTriggerConfiguration = try container.decodeIfPresent(
            ClipboardAssistantTriggerConfiguration.self,
            forKey: .clipboardAssistantTriggerConfiguration
        ) ?? .default
        if container.contains(.clipboardAssistantMouseButton) {
            clipboardAssistantMouseButton = try container.decodeIfPresent(
                Int.self,
                forKey: .clipboardAssistantMouseButton
            )
        } else {
            clipboardAssistantMouseButton = defaults.clipboardAssistantMouseButton
        }
        clipboardAssistantBlacklist = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .clipboardAssistantBlacklist
        ) ?? defaults.clipboardAssistantBlacklist
        clipboardAssistantEnabledKinds = try container.decodeIfPresent(
            Set<ClipboardAssistantKind>.self,
            forKey: .clipboardAssistantEnabledKinds
        ) ?? defaults.clipboardAssistantEnabledKinds
        clipboardAssistantActionOrders = ClipboardAssistantActionOrder.normalized(
            try container.decodeIfPresent(
                [ClipboardAssistantKind: [ClipboardAssistantActionKind]].self,
                forKey: .clipboardAssistantActionOrders
            ) ?? defaults.clipboardAssistantActionOrders
        )
        clipboardAssistantSearchEngine = try container.decodeIfPresent(
            ClipboardAssistantSearchEngine.self,
            forKey: .clipboardAssistantSearchEngine
        ) ?? defaults.clipboardAssistantSearchEngine
        clipboardAssistantCustomSearchURL = try container.decodeIfPresent(
            String.self,
            forKey: .clipboardAssistantCustomSearchURL
        ) ?? defaults.clipboardAssistantCustomSearchURL
        clipboardAssistantLightweightMode = try container.decodeIfPresent(
            Bool.self,
            forKey: .clipboardAssistantLightweightMode
        ) ?? defaults.clipboardAssistantLightweightMode
        clipboardAssistantDisplayDuration = try container.decodeIfPresent(
            ClipboardAssistantDisplayDuration.self,
            forKey: .clipboardAssistantDisplayDuration
        ) ?? defaults.clipboardAssistantDisplayDuration
        clipboardAssistantPromptsForImageSaveLocation = try container.decodeIfPresent(
            Bool.self,
            forKey: .clipboardAssistantPromptsForImageSaveLocation
        ) ?? defaults.clipboardAssistantPromptsForImageSaveLocation
        clipboardAssistantMouseGestureEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .clipboardAssistantMouseGestureEnabled
        ) ?? defaults.clipboardAssistantMouseGestureEnabled
        sideNoticesEnabled = try container.decodeIfPresent(Bool.self, forKey: .sideNoticesEnabled) ?? defaults.sideNoticesEnabled
        compactStatusPriority = CompactStatusPriority.normalized(
            try container.decodeIfPresent([CompactStatusPriority].self, forKey: .compactStatusPriority)
                ?? defaults.compactStatusPriority
        )
        notificationsMuted = try container.decodeIfPresent(Bool.self, forKey: .notificationsMuted) ?? defaults.notificationsMuted
        hoverActivationEnabled = try container.decodeIfPresent(Bool.self, forKey: .hoverActivationEnabled) ?? defaults.hoverActivationEnabled
        activityNoticeDisplayDuration = try container.decodeIfPresent(
            ActivityNoticeDisplayDuration.self,
            forKey: .activityNoticeDisplayDuration
        ) ?? defaults.activityNoticeDisplayDuration
        focusModeNoticeDisplayDuration = try container.decodeIfPresent(
            FocusModeNoticeDisplayDuration.self,
            forKey: .focusModeNoticeDisplayDuration
        ) ?? defaults.focusModeNoticeDisplayDuration
        activityNoticeDisplayIDs = try container.decodeIfPresent(
            Set<UInt32>.self,
            forKey: .activityNoticeDisplayIDs
        ) ?? defaults.activityNoticeDisplayIDs
        appearanceMode = try container.decodeIfPresent(
            AppearanceMode.self,
            forKey: .appearanceMode
        ) ?? defaults.appearanceMode
        petEnabled = try container.decodeIfPresent(Bool.self, forKey: .petEnabled) ?? defaults.petEnabled
        petID = try container.decodeIfPresent(String.self, forKey: .petID) ?? defaults.petID
        petSide = try container.decodeIfPresent(PetSide.self, forKey: .petSide) ?? defaults.petSide
        mediaShowLyricsAndInfo = try container.decodeIfPresent(Bool.self, forKey: .mediaShowLyricsAndInfo) ?? defaults.mediaShowLyricsAndInfo
        mediaCompactStyle = try container.decodeIfPresent(
            MediaCompactStyle.self,
            forKey: .mediaCompactStyle
        ) ?? defaults.mediaCompactStyle
        islandVisualStyle = try container.decodeIfPresent(
            IslandVisualStyle.self,
            forKey: .islandVisualStyle
        ) ?? defaults.islandVisualStyle
        islandNotchBackground = try container.decodeIfPresent(
            IslandNotchBackground.self,
            forKey: .islandNotchBackground
        ) ?? defaults.islandNotchBackground
        islandCollapsedOnTop = try container.decodeIfPresent(
            Bool.self,
            forKey: .islandCollapsedOnTop
        ) ?? defaults.islandCollapsedOnTop
        voiceInputEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceInputEnabled) ?? defaults.voiceInputEnabled
        voiceInputMode = try container.decodeIfPresent(VoiceInputMode.self, forKey: .voiceInputMode) ?? defaults.voiceInputMode
        voiceInputHotkeyPreset = try container.decodeIfPresent(VoiceInputHotkeyPreset.self, forKey: .voiceInputHotkeyPreset) ?? defaults.voiceInputHotkeyPreset
        voiceRecordingRetentionEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .voiceRecordingRetentionEnabled
        ) ?? defaults.voiceRecordingRetentionEnabled
        voiceRecordingCleanupPolicy = try container.decodeIfPresent(
            VoiceRecordingCleanupPolicy.self,
            forKey: .voiceRecordingCleanupPolicy
        ) ?? defaults.voiceRecordingCleanupPolicy
        voiceModelConfiguration = try container.decodeIfPresent(
            AIModelConfigurationReference.self,
            forKey: .voiceModelConfiguration
        )
        voiceEnabledLexicons = try container.decodeIfPresent(
            Set<VoiceLexicon>.self,
            forKey: .voiceEnabledLexicons
        ) ?? defaults.voiceEnabledLexicons
        voiceCustomHotwords = VoiceLexicon.normalizedCustomTerms(
            try container.decodeIfPresent([String].self, forKey: .voiceCustomHotwords)
                ?? defaults.voiceCustomHotwords
        )
        voiceStructuredFormattingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .voiceStructuredFormattingEnabled
        ) ?? defaults.voiceStructuredFormattingEnabled
        screenshotEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .screenshotEnabled
        ) ?? defaults.screenshotEnabled
        screenshotHotkey = try container.decodeIfPresent(
            VoiceInputHotkeyPreset.self,
            forKey: .screenshotHotkey
        ) ?? defaults.screenshotHotkey
        screenshotPinHotkey = try container.decodeIfPresent(
            VoiceInputHotkeyPreset.self,
            forKey: .screenshotPinHotkey
        ) ?? defaults.screenshotPinHotkey
        screenshotPinnedToolbarVisible = try container.decodeIfPresent(
            Bool.self,
            forKey: .screenshotPinnedToolbarVisible
        ) ?? defaults.screenshotPinnedToolbarVisible
        keyboardEnabled = try container.decodeIfPresent(Bool.self, forKey: .keyboardEnabled) ?? defaults.keyboardEnabled
        keyboardSelectedProfileID = try container.decodeIfPresent(String.self, forKey: .keyboardSelectedProfileID) ?? defaults.keyboardSelectedProfileID
        keyboardVolume = try container.decodeIfPresent(Double.self, forKey: .keyboardVolume) ?? defaults.keyboardVolume
        keyboardPlaysReleaseSound = try container.decodeIfPresent(Bool.self, forKey: .keyboardPlaysReleaseSound) ?? defaults.keyboardPlaysReleaseSound
        keyboardUsesPitchVariation = try container.decodeIfPresent(Bool.self, forKey: .keyboardUsesPitchVariation) ?? defaults.keyboardUsesPitchVariation
        keyboardTypingStatsEnabled = try container.decodeIfPresent(Bool.self, forKey: .keyboardTypingStatsEnabled) ?? defaults.keyboardTypingStatsEnabled
        battutaEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .battutaEnabled
        ) ?? defaults.battutaEnabled
        battutaSelectedProfileID = try container.decodeIfPresent(
            String.self,
            forKey: .battutaSelectedProfileID
        ) ?? defaults.battutaSelectedProfileID
        battutaVolume = try container.decodeIfPresent(
            Double.self,
            forKey: .battutaVolume
        ) ?? defaults.battutaVolume
        battutaPlaysReleaseSound = try container.decodeIfPresent(
            Bool.self,
            forKey: .battutaPlaysReleaseSound
        ) ?? defaults.battutaPlaysReleaseSound
        battutaUsesPitchVariation = try container.decodeIfPresent(
            Bool.self,
            forKey: .battutaUsesPitchVariation
        ) ?? defaults.battutaUsesPitchVariation
        battutaPointerSoundEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .battutaPointerSoundEnabled
        ) ?? defaults.battutaPointerSoundEnabled
        battutaSelectedPointerProfileID = try container.decodeIfPresent(
            String.self,
            forKey: .battutaSelectedPointerProfileID
        ) ?? defaults.battutaSelectedPointerProfileID
        battutaPointerVolume = try container.decodeIfPresent(
            Double.self,
            forKey: .battutaPointerVolume
        ) ?? defaults.battutaPointerVolume
        battutaPlaysPointerReleaseSound = try container.decodeIfPresent(
            Bool.self,
            forKey: .battutaPlaysPointerReleaseSound
        ) ?? defaults.battutaPlaysPointerReleaseSound
    }
}

/// Which side of the Dynamic Island the pet appears on.
public enum PetSide: String, Codable, Sendable {
    case left
    case right
}
