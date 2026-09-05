import AppKit
import Combine
import Foundation
import SwiftUI
import ZislaCore

/// Public integration surface used by Zisla. The complete keyboard sound implementation remains
/// inside this target; Zisla only synchronizes feature settings and presents its own UI.
public struct KeyboardSoundProfileOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let family: String
    public let tone: String

    public init(id: String, name: String, family: String, tone: String) {
        self.id = id
        self.name = name
        self.family = family
        self.tone = tone
    }
}

public struct KeyboardTypingStatsApplicationSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let characterCount: Int64
    public let activeMinuteBuckets: Int64
    public let peakCharactersPerSecond: Int64

    public init(
        id: String,
        name: String,
        characterCount: Int64,
        activeMinuteBuckets: Int64,
        peakCharactersPerSecond: Int64
    ) {
        self.id = id
        self.name = name
        self.characterCount = characterCount
        self.activeMinuteBuckets = activeMinuteBuckets
        self.peakCharactersPerSecond = peakCharactersPerSecond
    }
}

public struct KeyboardTypingStatsDaySummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let characterCount: Int64
    public let peakCharactersPerSecond: Int64
    public let activeMinuteBuckets: Int64

    public init(
        id: String,
        date: Date,
        characterCount: Int64,
        peakCharactersPerSecond: Int64,
        activeMinuteBuckets: Int64
    ) {
        self.id = id
        self.date = date
        self.characterCount = characterCount
        self.peakCharactersPerSecond = peakCharactersPerSecond
        self.activeMinuteBuckets = activeMinuteBuckets
    }
}

public struct KeyboardTypingStatsTrendPoint: Identifiable, Equatable, Sendable {
    public let id: Int
    public let start: Date
    public let characterCount: Int64

    public init(id: Int, start: Date, characterCount: Int64) {
        self.id = id
        self.start = start
        self.characterCount = characterCount
    }
}

public struct KeyboardTypingStatsApplicationTimeline: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let buckets: [KeyboardTypingStatsTrendPoint]

    public init(id: String, name: String, buckets: [KeyboardTypingStatsTrendPoint]) {
        self.id = id
        self.name = name
        self.buckets = buckets
    }
}

public struct KeyboardTypingStatsSummary: Equatable, Sendable {
    public let generatedAt: Date
    public let lastInputAt: Date?
    public let todayCharacterCount: Int64
    public let todayPeakCharactersPerSecond: Int64
    public let todayActiveSeconds: Int64
    public let todayActiveMinuteBuckets: Int64
    public let todayTopApplication: String?
    public let todayKeyPressCount: Int64
    public let allTimeKeyPressCount: Int64
    public let applications: [KeyboardTypingStatsApplicationSummary]
    public let history: [KeyboardTypingStatsDaySummary]
    public let timelineRange: String
    public let recentBuckets: [KeyboardTypingStatsTrendPoint]
    public let applicationTimelines: [KeyboardTypingStatsApplicationTimeline]
    public let todayKeyCounts: [UInt16: Int64]
    public let allTimeKeyCounts: [UInt16: Int64]

    public init(
        generatedAt: Date,
        lastInputAt: Date?,
        todayCharacterCount: Int64,
        todayPeakCharactersPerSecond: Int64,
        todayActiveSeconds: Int64,
        todayActiveMinuteBuckets: Int64,
        todayTopApplication: String?,
        todayKeyPressCount: Int64,
        allTimeKeyPressCount: Int64,
        applications: [KeyboardTypingStatsApplicationSummary],
        history: [KeyboardTypingStatsDaySummary],
        timelineRange: String,
        recentBuckets: [KeyboardTypingStatsTrendPoint],
        applicationTimelines: [KeyboardTypingStatsApplicationTimeline],
        todayKeyCounts: [UInt16: Int64],
        allTimeKeyCounts: [UInt16: Int64]
    ) {
        self.generatedAt = generatedAt
        self.lastInputAt = lastInputAt
        self.todayCharacterCount = todayCharacterCount
        self.todayPeakCharactersPerSecond = todayPeakCharactersPerSecond
        self.todayActiveSeconds = todayActiveSeconds
        self.todayActiveMinuteBuckets = todayActiveMinuteBuckets
        self.todayTopApplication = todayTopApplication
        self.todayKeyPressCount = todayKeyPressCount
        self.allTimeKeyPressCount = allTimeKeyPressCount
        self.applications = applications
        self.history = history
        self.timelineRange = timelineRange
        self.recentBuckets = recentBuckets
        self.applicationTimelines = applicationTimelines
        self.todayKeyCounts = todayKeyCounts
        self.allTimeKeyCounts = allTimeKeyCounts
    }
}

@MainActor
public final class KeyboardSoundController: ObservableObject {
    @Published public private(set) var isInputMonitoringGranted = false
    @Published public private(set) var monitoringStateText = AppLocalization.text("未启动")
    @Published public private(set) var audioError: String?
    @Published public private(set) var typingStatsSummary: KeyboardTypingStatsSummary?

    private let model: KeyboardAppModel
    private var cancellables: Set<AnyCancellable> = []

    public let keyboardProfiles: [KeyboardSoundProfileOption]
    public init() {
        let model = KeyboardAppModel(startsServices: false)
        self.model = model
        keyboardProfiles = SwitchProfile.allCases.map {
            KeyboardSoundProfileOption(
                id: $0.rawValue,
                name: $0.displayName,
                family: $0.family,
                tone: $0.tone
            )
        }
        refreshPublishedState()
        model.objectWillChange
            .sink { [weak self] in
                Task { @MainActor [weak self] in self?.refreshPublishedState() }
            }
            .store(in: &cancellables)
        model.typingStats.objectWillChange
            .sink { [weak self] in
                Task { @MainActor [weak self] in self?.refreshPublishedState() }
            }
            .store(in: &cancellables)
    }

    public var selectedKeyboardProfileID: String { model.settings.selectedProfileID }

    public func apply(
        enabled: Bool,
        keyboardProfileID: String,
        keyboardVolume: Double,
        playsReleaseSound: Bool,
        usesPitchVariation: Bool,
        typingStatsEnabled: Bool
    ) {
        model.settings.isEnabled = enabled
        model.settings.selectedProfileID = keyboardProfileID
        model.settings.volume = keyboardVolume
        model.settings.playsReleaseSound = playsReleaseSound
        model.settings.usesPitchVariation = usesPitchVariation
        model.settings.isTypingStatsEnabled = typingStatsEnabled
        if enabled || typingStatsEnabled {
            model.startServicesIfNeeded()
            requestInputMonitoringIfNeeded()
        } else {
            model.stop()
        }
    }

    public func requestInputMonitoring() {
        model.requestInputMonitoring()
    }

    /// Mirrors the clipboard, screenshot and voice authorization rows: ask first, because the system
    /// dialog grants in a single click, and fall back to System Settings once the prompt is spent —
    /// from then on it is the only way left to grant.
    public func openInputMonitoringSettings() {
        requestInputMonitoringIfNeeded()
        guard !model.permission.isGranted else { return }
        model.openInputMonitoringSettings()
    }

    static func shouldRequestInputMonitoring(
        hasAccess: Bool,
        hasRequestedBefore: Bool
    ) -> Bool {
        !hasAccess && !hasRequestedBefore
    }

    /// Keyboard sound and typing stats are passive global listeners: no user action marks the moment
    /// the permission is needed, and both default to on, so a fresh install has to be asked while
    /// the listener is starting up.
    private func requestInputMonitoringIfNeeded() {
        guard Self.shouldRequestInputMonitoring(
            hasAccess: model.permission.refresh(),
            hasRequestedBefore: model.permission.hasRequestedOnce
        ) else { return }
        model.requestInputMonitoring()
    }

    public func retryInputMonitoring() {
        model.retryKeyboardMonitor()
    }

    public func refreshTypingStats() async {
        await model.typingStats.refresh(
            for: .overview,
            publishesUnchangedSnapshot: true
        )
        refreshPublishedState()
    }

    public func stop() {
        model.stop()
    }

    /// Host apps must route `applicationShouldTerminate` here. `stop()` alone can only fire the
    /// final flush off into a detached task, which the terminating process rarely lets finish.
    public func applicationShouldTerminate(
        _ application: NSApplication
    ) -> NSApplication.TerminateReply {
        model.applicationShouldTerminate(application)
    }

    public func preview() {
        model.preview()
    }

    private func refreshPublishedState() {
        isInputMonitoringGranted = model.permission.isGranted
        monitoringStateText = switch model.monitoringState {
        case .stopped: "已停止"
        case .waitingForPermission: "等待输入监控授权"
        case .running: "输入监控正在运行"
        case let .failed(message): message
        }
        audioError = model.audioError ?? model.pointerSoundError
        guard let snapshot = model.typingStats.snapshot else {
            typingStatsSummary = nil
            return
        }
        typingStatsSummary = KeyboardTypingStatsSummary(
            generatedAt: snapshot.generatedAt,
            lastInputAt: snapshot.lastInputAt,
            todayCharacterCount: snapshot.today.characterCount,
            todayPeakCharactersPerSecond: snapshot.today.peakCPS,
            todayActiveSeconds: snapshot.today.activeSeconds,
            todayActiveMinuteBuckets: snapshot.today.activeMinuteBuckets,
            todayTopApplication: snapshot.today.topAppName,
            todayKeyPressCount: snapshot.todayKeyCounts.values.reduce(0, +),
            allTimeKeyPressCount: snapshot.allTimeKeyCounts.values.reduce(0, +),
            applications: snapshot.apps.map {
                KeyboardTypingStatsApplicationSummary(
                    id: $0.id,
                    name: $0.displayName,
                    characterCount: $0.characterCount,
                    activeMinuteBuckets: $0.activeMinuteBuckets,
                    peakCharactersPerSecond: $0.peakCPS
                )
            },
            history: snapshot.history.map {
                KeyboardTypingStatsDaySummary(
                    id: $0.id,
                    date: $0.date,
                    characterCount: $0.characterCount,
                    peakCharactersPerSecond: $0.peakCPS,
                    activeMinuteBuckets: $0.activeMinuteBuckets
                )
            },
            timelineRange: snapshot.timelineRange.rawValue,
            recentBuckets: snapshot.recentBuckets.map {
                KeyboardTypingStatsTrendPoint(
                    id: $0.id,
                    start: $0.start,
                    characterCount: $0.characterCount
                )
            },
            applicationTimelines: snapshot.recentAppTimelines.map {
                KeyboardTypingStatsApplicationTimeline(
                    id: $0.id,
                    name: $0.application.displayName,
                    buckets: $0.buckets.map {
                        KeyboardTypingStatsTrendPoint(
                            id: $0.id,
                            start: $0.start,
                            characterCount: $0.characterCount
                        )
                    }
                )
            },
            todayKeyCounts: snapshot.todayKeyCounts,
            allTimeKeyCounts: snapshot.allTimeKeyCounts
        )
    }
}
