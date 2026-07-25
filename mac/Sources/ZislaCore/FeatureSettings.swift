import Foundation

/// 折叠态持续活动（播放中 / AI running·queued）的侧翼展示时长。
public enum ActivityNoticeDisplayDuration: String, Codable, CaseIterable, Sendable, Equatable {
    case threeSeconds
    case fiveSeconds
    case tenSeconds
    case thirtySeconds
    case always

    /// 入队用的过期秒数；`always` 为 `nil` 表示常驻直至活动结束。
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

/// 系统专注模式切换时的侧翼展示时长。
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

/// 常规界面（设置窗口等）的外观模式。灵动岛固定深色，不受此设置影响。
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

/// 媒体模块要跟随的系统 Now Playing 来源；自动模式保留系统当前目标。
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

/// 可单独常驻菜单栏，并在点击时直达系统监控面板的指标。
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

/// 菜单栏监控状态项的展示方式。
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

/// 各功能模块的开关。隐私敏感项（剪贴板检测）默认关闭，核心模块默认开启。
public struct FeatureSettings: Codable, Equatable, Sendable {
    public var mediaEnabled: Bool
    public var mediaSource: MediaSourcePreference
    public var fileShelfEnabled: Bool
    public var aiProgressEnabled: Bool
    public var downloaderEnabled: Bool
    public var calendarEnabled: Bool
    public var toolboxEnabled: Bool
    public var toolboxReminderEnabled: Bool
    /// 专注进行时是否在收起态灵动岛显示倒计时。
    public var focusCountdownIslandEnabled: Bool
    public var systemMonitorEnabled: Bool
    /// 为空时不新增监控状态栏项。
    public var systemMonitorMenuBarMetrics: Set<SystemMonitorMenuBarMetric>
    /// 详细模式保留原有图标与横向读数，紧凑模式隐藏图标并减小字号。
    public var systemMonitorMenuBarDisplayStyle: SystemMonitorMenuBarDisplayStyle
    /// 是否单独显示 Zisla 的菜单栏图标，不影响监控状态项。
    public var menuBarAppIconEnabled: Bool
    public var weatherEnabled: Bool
    public var lockScreenInfoEnabled: Bool
    /// 锁屏原生时间上方显示的用户自定义文字；空字符串表示不显示。
    public var lockScreenMessage: String
    /// 是否在锁屏原生时间上方显示农历，可与自定义文字同时显示。
    public var lockScreenShowsLunar: Bool
    public var quickNotesEnabled: Bool
    /// 邮件集成默认关闭，避免未确认授权前读取用户的收件箱元数据。
    public var mailEnabled: Bool
    /// 空集合表示同步所有已配置的系统 Mail.app 账户。
    public var mailAccountNames: Set<String>
    public var updateChecksEnabled: Bool
    public var automaticUpdatesEnabled: Bool
    /// 是否在本机保存剪贴板文本与图片；默认关闭以避免无意记录敏感内容。
    public var clipboardHistoryEnabled: Bool
    public var clipboardDetectionEnabled: Bool
    public var sideNoticesEnabled: Bool
    public var hoverActivationEnabled: Bool
    public var activityNoticeDisplayDuration: ActivityNoticeDisplayDuration
    public var focusModeNoticeDisplayDuration: FocusModeNoticeDisplayDuration
    /// 空集合表示活动通知显示在所有当前连接的显示器上。
    public var activityNoticeDisplayIDs: Set<UInt32>
    public var appearanceMode: AppearanceMode
    /// 是否在灵动岛旁养一只宠物（兼容 Codex hatch-pet 格式，宠物来自 codex-pets.net 等社区库）。
    public var petEnabled: Bool
    /// 当前选中的宠物 id（对应 `PetLibrary` 的某个内置或导入宠物）。
    public var petID: String
    /// 宠物出现在灵动岛的哪一侧。
    public var petSide: PetSide
    /// 播放音乐时灵动岛是否展示歌词及歌曲信息。
    public var mediaShowLyricsAndInfo: Bool
    public var voiceInputEnabled: Bool
    public var voiceInputMode: VoiceInputMode
    public var voiceInputHotkeyPreset: VoiceInputHotkeyPreset
    /// 当前语音模型连接指向本机服务还是远端 OpenAI 兼容服务。
    public var voiceModelEndpointMode: VoiceModelEndpointMode
    /// 本地模型端点类型（LM Studio / Ollama）。
    public var voiceModelEndpointKind: AIEndpointKind
    /// 本地模型服务的基础 URL，如 http://127.0.0.1:1234/v1。
    public var voiceModelBaseURL: String
    /// 每组远端服务独立保存 URL、模型名、API Key 和启用状态。
    public var voiceModelRemoteEndpoints: [VoiceModelRemoteEndpoint]
    /// 负载均衡关闭时使用的远端端点。
    public var voiceModelSelectedRemoteEndpointID: UUID?
    /// 开启后在已启用的远端端点间轮询。
    public var voiceModelRemoteLoadBalancingEnabled: Bool
    /// 本地模型名称；远端模型名称保存在各自端点组内。
    public var voiceModelName: String

    public init(
        mediaEnabled: Bool = true,
        mediaSource: MediaSourcePreference = .automatic,
        fileShelfEnabled: Bool = true,
        aiProgressEnabled: Bool = true,
        downloaderEnabled: Bool = true,
        calendarEnabled: Bool = true,
        toolboxEnabled: Bool = true,
        toolboxReminderEnabled: Bool = false,
        focusCountdownIslandEnabled: Bool = true,
        systemMonitorEnabled: Bool = true,
        systemMonitorMenuBarMetrics: Set<SystemMonitorMenuBarMetric> = [.cpu],
        systemMonitorMenuBarDisplayStyle: SystemMonitorMenuBarDisplayStyle = .detailed,
        menuBarAppIconEnabled: Bool = false,
        weatherEnabled: Bool = true,
        lockScreenInfoEnabled: Bool = true,
        lockScreenMessage: String = "",
        lockScreenShowsLunar: Bool = true,
        quickNotesEnabled: Bool = true,
        mailEnabled: Bool = false,
        mailAccountNames: Set<String> = [],
        updateChecksEnabled: Bool = true,
        automaticUpdatesEnabled: Bool = true,
        clipboardHistoryEnabled: Bool = false,
        clipboardDetectionEnabled: Bool = false,
        sideNoticesEnabled: Bool = true,
        hoverActivationEnabled: Bool = true,
        activityNoticeDisplayDuration: ActivityNoticeDisplayDuration = .threeSeconds,
        focusModeNoticeDisplayDuration: FocusModeNoticeDisplayDuration = .threeSeconds,
        activityNoticeDisplayIDs: Set<UInt32> = [],
        appearanceMode: AppearanceMode = .system,
        petEnabled: Bool = true,
        petID: String = "dog",
        petSide: PetSide = .right,
        mediaShowLyricsAndInfo: Bool = true,
        voiceInputEnabled: Bool = false,
        voiceInputMode: VoiceInputMode = .toggle,
        voiceInputHotkeyPreset: VoiceInputHotkeyPreset = .optionSpace,
        voiceModelEndpointMode: VoiceModelEndpointMode = .local,
        voiceModelEndpointKind: AIEndpointKind = .openAICompatible,
        voiceModelBaseURL: String = AIEndpointKind.openAICompatible.defaultBaseURL,
        voiceModelRemoteEndpoints: [VoiceModelRemoteEndpoint] = [],
        voiceModelSelectedRemoteEndpointID: UUID? = nil,
        voiceModelRemoteLoadBalancingEnabled: Bool = false,
        voiceModelName: String = ""
    ) {
        self.mediaEnabled = mediaEnabled
        self.mediaSource = mediaSource
        self.fileShelfEnabled = fileShelfEnabled
        self.aiProgressEnabled = aiProgressEnabled
        self.downloaderEnabled = downloaderEnabled
        self.calendarEnabled = calendarEnabled
        self.toolboxEnabled = toolboxEnabled
        self.toolboxReminderEnabled = toolboxReminderEnabled
        self.focusCountdownIslandEnabled = focusCountdownIslandEnabled
        self.systemMonitorEnabled = systemMonitorEnabled
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
        self.updateChecksEnabled = updateChecksEnabled
        self.automaticUpdatesEnabled = automaticUpdatesEnabled
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.clipboardDetectionEnabled = clipboardDetectionEnabled
        self.sideNoticesEnabled = sideNoticesEnabled
        self.hoverActivationEnabled = hoverActivationEnabled
        self.activityNoticeDisplayDuration = activityNoticeDisplayDuration
        self.focusModeNoticeDisplayDuration = focusModeNoticeDisplayDuration
        self.activityNoticeDisplayIDs = activityNoticeDisplayIDs
        self.appearanceMode = appearanceMode
        self.petEnabled = petEnabled
        self.petID = petID
        self.petSide = petSide
        self.mediaShowLyricsAndInfo = mediaShowLyricsAndInfo
        self.voiceInputEnabled = voiceInputEnabled
        self.voiceInputMode = voiceInputMode
        self.voiceInputHotkeyPreset = voiceInputHotkeyPreset
        self.voiceModelEndpointMode = voiceModelEndpointMode
        self.voiceModelEndpointKind = voiceModelEndpointKind
        self.voiceModelBaseURL = voiceModelBaseURL
        self.voiceModelRemoteEndpoints = voiceModelRemoteEndpoints
        self.voiceModelSelectedRemoteEndpointID = voiceModelSelectedRemoteEndpointID
        self.voiceModelRemoteLoadBalancingEnabled = voiceModelRemoteLoadBalancingEnabled
        self.voiceModelName = voiceModelName
    }

    /// 已选显示器均断开时回退到当前全部显示器，避免活动通知完全不可见。
    public func resolvedActivityNoticeDisplayIDs(
        from connectedDisplayIDs: Set<UInt32>
    ) -> Set<UInt32> {
        let selected = activityNoticeDisplayIDs.intersection(connectedDisplayIDs)
        return selected.isEmpty ? connectedDisplayIDs : selected
    }

    /// 用户没有缩小范围时同步所有账户；已做过筛选时不自动把新账户加入同步范围。
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
        case toolboxReminderEnabled
        case focusCountdownIslandEnabled
        case systemMonitorEnabled
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
        case updateChecksEnabled
        case automaticUpdatesEnabled
        case clipboardHistoryEnabled
        case clipboardDetectionEnabled
        case sideNoticesEnabled
        case hoverActivationEnabled
        case activityNoticeDisplayDuration
        case focusModeNoticeDisplayDuration
        case activityNoticeDisplayIDs
        case appearanceMode
        case petEnabled
        case petID
        case petSide
        case mediaShowLyricsAndInfo
        case voiceInputEnabled
        case voiceInputMode
        case voiceInputHotkeyPreset
        case voiceModelEndpointMode
        case voiceModelEndpointKind
        case voiceModelBaseURL
        case voiceModelRemoteEndpoints
        case voiceModelSelectedRemoteEndpointID
        case voiceModelRemoteLoadBalancingEnabled
        case voiceModelName
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case voiceModelRemoteBaseURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let defaults = FeatureSettings.default
        mediaEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaEnabled) ?? defaults.mediaEnabled
        mediaSource = try container.decodeIfPresent(MediaSourcePreference.self, forKey: .mediaSource) ?? defaults.mediaSource
        fileShelfEnabled = try container.decodeIfPresent(Bool.self, forKey: .fileShelfEnabled) ?? defaults.fileShelfEnabled
        aiProgressEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiProgressEnabled) ?? defaults.aiProgressEnabled
        downloaderEnabled = try container.decodeIfPresent(Bool.self, forKey: .downloaderEnabled) ?? defaults.downloaderEnabled
        calendarEnabled = try container.decodeIfPresent(Bool.self, forKey: .calendarEnabled) ?? defaults.calendarEnabled
        toolboxEnabled = try container.decodeIfPresent(Bool.self, forKey: .toolboxEnabled) ?? defaults.toolboxEnabled
        toolboxReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .toolboxReminderEnabled) ?? defaults.toolboxReminderEnabled
        focusCountdownIslandEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .focusCountdownIslandEnabled
        ) ?? defaults.focusCountdownIslandEnabled
        systemMonitorEnabled = try container.decodeIfPresent(Bool.self, forKey: .systemMonitorEnabled) ?? defaults.systemMonitorEnabled
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
        updateChecksEnabled = try container.decodeIfPresent(Bool.self, forKey: .updateChecksEnabled) ?? defaults.updateChecksEnabled
        automaticUpdatesEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdatesEnabled) ?? defaults.automaticUpdatesEnabled
        clipboardHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? defaults.clipboardHistoryEnabled
        clipboardDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardDetectionEnabled) ?? defaults.clipboardDetectionEnabled
        sideNoticesEnabled = try container.decodeIfPresent(Bool.self, forKey: .sideNoticesEnabled) ?? defaults.sideNoticesEnabled
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
        voiceInputEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceInputEnabled) ?? defaults.voiceInputEnabled
        voiceInputMode = try container.decodeIfPresent(VoiceInputMode.self, forKey: .voiceInputMode) ?? defaults.voiceInputMode
        voiceInputHotkeyPreset = try container.decodeIfPresent(VoiceInputHotkeyPreset.self, forKey: .voiceInputHotkeyPreset) ?? defaults.voiceInputHotkeyPreset
        voiceModelEndpointMode = try container.decodeIfPresent(VoiceModelEndpointMode.self, forKey: .voiceModelEndpointMode) ?? defaults.voiceModelEndpointMode
        voiceModelEndpointKind = try container.decodeIfPresent(AIEndpointKind.self, forKey: .voiceModelEndpointKind) ?? defaults.voiceModelEndpointKind
        voiceModelBaseURL = try container.decodeIfPresent(String.self, forKey: .voiceModelBaseURL) ?? defaults.voiceModelBaseURL
        voiceModelName = try container.decodeIfPresent(String.self, forKey: .voiceModelName) ?? defaults.voiceModelName
        let legacyRemoteBaseURL = try legacyContainer.decodeIfPresent(
            String.self,
            forKey: .voiceModelRemoteBaseURL
        ) ?? ""
        if let endpoints = try container.decodeIfPresent([VoiceModelRemoteEndpoint].self, forKey: .voiceModelRemoteEndpoints) {
            voiceModelRemoteEndpoints = endpoints
        } else if !legacyRemoteBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            voiceModelRemoteEndpoints = [
                VoiceModelRemoteEndpoint(
                    name: "远端端点 1",
                    baseURL: legacyRemoteBaseURL,
                    modelName: voiceModelName
                )
            ]
        } else {
            voiceModelRemoteEndpoints = defaults.voiceModelRemoteEndpoints
        }
        voiceModelSelectedRemoteEndpointID = try container.decodeIfPresent(
            UUID.self,
            forKey: .voiceModelSelectedRemoteEndpointID
        ) ?? voiceModelRemoteEndpoints.first?.id
        voiceModelRemoteLoadBalancingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .voiceModelRemoteLoadBalancingEnabled
        ) ?? defaults.voiceModelRemoteLoadBalancingEnabled
    }
}

/// 宠物在灵动岛的哪一侧出现。
public enum PetSide: String, Codable, Sendable {
    case left
    case right
}
