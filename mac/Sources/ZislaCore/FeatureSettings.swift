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

/// Update channel selectable when checking for updates manually.
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
        .toolboxReminder,
        .mail,
        .updateAvailable,
        .focusCountdown,
        .aiActivity,
        .media,
        .focusMode,
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
    public var aiAgentEnabled: Bool
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
    /// Target channel for manual update checks.
    public var updateChannel: UpdateChannel
    /// Whether to save clipboard text and images locally; users can disable it in Settings if concerned about sensitive content.
    public var clipboardHistoryEnabled: Bool
    /// Whether to detect downloadable links in clipboard; users can disable it in Settings.
    public var clipboardDetectionEnabled: Bool
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
    /// Current model configuration for voice processing. The endpoint and credentials remain in AI Agent settings.
    public var voiceModelConfiguration: AIModelConfigurationReference?

    public init(
        mediaEnabled: Bool = true,
        mediaSource: MediaSourcePreference = .automatic,
        fileShelfEnabled: Bool = true,
        aiProgressEnabled: Bool = true,
        aiAgentEnabled: Bool = true,
        downloaderEnabled: Bool = true,
        calendarEnabled: Bool = true,
        toolboxEnabled: Bool = true,
        pdfToolsEnabled: Bool = true,
        toolboxReminderEnabled: Bool = true,
        focusCountdownIslandEnabled: Bool = true,
        browserDownloadIslandEnabled: Bool = true,
        videoDownloadIslandEnabled: Bool = true,
        systemMonitorEnabled: Bool = true,
        batteryMonitorEnabled: Bool = true,
        systemMonitorMenuBarMetrics: Set<SystemMonitorMenuBarMetric> = Set(SystemMonitorMenuBarMetric.allCases),
        systemMonitorMenuBarDisplayStyle: SystemMonitorMenuBarDisplayStyle = .detailed,
        menuBarAppIconEnabled: Bool = true,
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
        clipboardHistoryEnabled: Bool = true,
        clipboardDetectionEnabled: Bool = true,
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
        voiceModelConfiguration: AIModelConfigurationReference? = nil
    ) {
        self.mediaEnabled = mediaEnabled
        self.mediaSource = mediaSource
        self.fileShelfEnabled = fileShelfEnabled
        self.aiProgressEnabled = aiProgressEnabled
        self.aiAgentEnabled = aiAgentEnabled
        self.downloaderEnabled = downloaderEnabled
        self.calendarEnabled = calendarEnabled
        self.toolboxEnabled = toolboxEnabled
        self.pdfToolsEnabled = pdfToolsEnabled
        self.toolboxReminderEnabled = toolboxReminderEnabled
        self.focusCountdownIslandEnabled = focusCountdownIslandEnabled
        self.browserDownloadIslandEnabled = browserDownloadIslandEnabled
        self.videoDownloadIslandEnabled = videoDownloadIslandEnabled
        self.systemMonitorEnabled = systemMonitorEnabled
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
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.clipboardDetectionEnabled = clipboardDetectionEnabled
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
        self.voiceModelConfiguration = voiceModelConfiguration
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
        case aiAgentEnabled
        case downloaderEnabled
        case calendarEnabled
        case toolboxEnabled
        case pdfToolsEnabled
        case toolboxReminderEnabled
        case focusCountdownIslandEnabled
        case browserDownloadIslandEnabled
        case videoDownloadIslandEnabled
        case systemMonitorEnabled
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
        case clipboardHistoryEnabled
        case clipboardDetectionEnabled
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
        case voiceModelConfiguration
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
        aiAgentEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiAgentEnabled) ?? defaults.aiAgentEnabled
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
        clipboardHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? defaults.clipboardHistoryEnabled
        clipboardDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardDetectionEnabled) ?? defaults.clipboardDetectionEnabled
        sideNoticesEnabled = try container.decodeIfPresent(Bool.self, forKey: .sideNoticesEnabled) ?? defaults.sideNoticesEnabled
        compactStatusPriority = CompactStatusPriority.normalized(
            try container.decodeIfPresent([CompactStatusPriority].self, forKey: .compactStatusPriority)
                ?? defaults.compactStatusPriority
        )
        notificationsMuted = try container.decodeIfPresent(Bool.self, forKey: .notificationsMuted) ?? defaults.notificationsMuted
        hoverActivationEnabled = try container.decodeIfPresent(Bool.self, forKey: .hoverActivationEnabled) ?? defaults.hoverActivationEnabled
        activityNoticeDisplayDuration = try container.decode(
            ActivityNoticeDisplayDuration.self,
            forKey: .activityNoticeDisplayDuration
        )
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
        voiceModelConfiguration = try container.decodeIfPresent(
            AIModelConfigurationReference.self,
            forKey: .voiceModelConfiguration
        )
    }
}

/// Which side of the Dynamic Island the pet appears on.
public enum PetSide: String, Codable, Sendable {
    case left
    case right
}
