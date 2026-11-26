import AppKit
import AVFoundation
import Combine
import Foundation
import ZislaCore
@preconcurrency import UserNotifications

public enum PomodoroMode: String, Equatable, Sendable {
    case focus
    case rest

    public var title: String {
        switch self {
        case .focus: "专注"
        case .rest: "休息"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .focus: 25 * 60
        case .rest: 5 * 60
        }
    }

    public var next: PomodoroMode {
        switch self {
        case .focus: .rest
        case .rest: .focus
        }
    }
}

public enum PomodoroPhase: Equatable, Sendable {
    case idle
    case running
    case paused
}

enum PomodoroCompletionSound {
    static let resourceName = "pomodoro-complete"
    static let resourceExtension = "m4a"
    static let resourceDirectory = "Pomodoro"

    static func resourceURL() -> URL? {
        Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: resourceDirectory
        )
    }
}

@MainActor
private final class PomodoroCompletionSoundPlayer {
    static let shared = PomodoroCompletionSoundPlayer()

    private var player: AVAudioPlayer?

    func play() {
        guard let url = PomodoroCompletionSound.resourceURL(),
              let player = try? AVAudioPlayer(contentsOf: url)
        else {
            return
        }
        self.player = player
        player.play()
    }
}

/// Pure state/time calculation: derives remaining time from a deadline; freezes remaining when paused.
public struct PomodoroEngine: Equatable, Sendable {
    static let maximumDuration: TimeInterval = TimeInterval(Int.max / 2)

    public var mode: PomodoroMode
    public var phase: PomodoroPhase
    /// Running: end time; paused/idle: unused.
    public var deadline: Date?
    /// Remaining seconds frozen at pause; equals the current mode's duration when idle.
    public var remainingWhenPaused: TimeInterval
    /// Configurable focus duration in seconds; default 25 minutes.
    public var focusDuration: TimeInterval
    /// Configurable rest duration in seconds; default 5 minutes.
    public var restDuration: TimeInterval

    public init(
        mode: PomodoroMode = .focus,
        phase: PomodoroPhase = .idle,
        deadline: Date? = nil,
        remainingWhenPaused: TimeInterval? = nil,
        focusDuration: TimeInterval = PomodoroMode.focus.duration,
        restDuration: TimeInterval = PomodoroMode.rest.duration
    ) {
        let normalizedFocusDuration = Self.normalizedDuration(
            focusDuration,
            fallback: PomodoroMode.focus.duration
        )
        let normalizedRestDuration = Self.normalizedDuration(
            restDuration,
            fallback: PomodoroMode.rest.duration
        )
        self.mode = mode
        self.phase = phase
        self.deadline = deadline
        self.focusDuration = normalizedFocusDuration
        self.restDuration = normalizedRestDuration
        self.remainingWhenPaused = Self.boundedRemaining(
            remainingWhenPaused ?? (mode == .focus ? normalizedFocusDuration : normalizedRestDuration)
        )
    }

    /// Returns the configured duration for the given mode.
    public func duration(for mode: PomodoroMode) -> TimeInterval {
        switch mode {
        case .focus:
            Self.normalizedDuration(focusDuration, fallback: PomodoroMode.focus.duration)
        case .rest:
            Self.normalizedDuration(restDuration, fallback: PomodoroMode.rest.duration)
        }
    }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        switch phase {
        case .idle:
            return duration(for: mode)
        case .paused:
            return Self.boundedRemaining(remainingWhenPaused)
        case .running:
            guard let deadline else { return 0 }
            return Self.boundedRemaining(deadline.timeIntervalSince(now))
        }
    }

    public func progress(at now: Date) -> Double {
        max(0, 1 - remaining(at: now) / duration(for: mode))
    }

    public func displayTime(at now: Date = Date()) -> (minutes: Int, seconds: Int) {
        let total = Int(ceil(remaining(at: now) - 1e-9))
        let clamped = max(0, total)
        return (clamped / 60, clamped % 60)
    }

    public static func formatMMSS(at now: Date = Date(), engine: PomodoroEngine) -> String {
        let t = engine.displayTime(at: now)
        let hours = t.minutes / 60
        if hours > 0 {
            return String(
                format: "%02lld:%02lld:%02lld",
                Int64(hours),
                Int64(t.minutes % 60),
                Int64(t.seconds)
            )
        }
        return String(format: "%02lld:%02lld", Int64(t.minutes), Int64(t.seconds))
    }

    /// Always zero-padded `HH:MM:SS` (e.g. 29 minutes 28 seconds → `00:29:28`).
    public static func formatHHMMSS(at now: Date = Date(), engine: PomodoroEngine) -> String {
        let t = engine.displayTime(at: now)
        return String(
            format: "%02lld:%02lld:%02lld",
            Int64(t.minutes / 60),
            Int64(t.minutes % 60),
            Int64(t.seconds)
        )
    }

    public mutating func start(at now: Date = Date()) {
        switch phase {
        case .idle:
            remainingWhenPaused = duration(for: mode)
            deadline = now.addingTimeInterval(remainingWhenPaused)
            phase = .running
        case .paused:
            deadline = now.addingTimeInterval(Self.boundedRemaining(remainingWhenPaused))
            phase = .running
        case .running:
            break
        }
    }

    public mutating func pause(at now: Date = Date()) {
        guard phase == .running else { return }
        remainingWhenPaused = remaining(at: now)
        deadline = nil
        phase = .paused
    }

    public mutating func reset() {
        phase = .idle
        deadline = nil
        remainingWhenPaused = duration(for: mode)
    }

    /// If running and the deadline has been reached or passed, switches to the next mode and returns to idle; returns whether a transition occurred.
    @discardableResult
    public mutating func completeIfNeeded(at now: Date = Date()) -> Bool {
        guard phase == .running else { return false }
        guard remaining(at: now) <= 0 else { return false }
        let completed = mode
        mode = completed.next
        phase = .idle
        deadline = nil
        remainingWhenPaused = duration(for: mode)
        return true
    }

    /// Test helper: force-enters the running state with the specified remaining time.
    public mutating func startWithRemaining(_ remaining: TimeInterval, at now: Date = Date()) {
        remainingWhenPaused = Self.boundedRemaining(remaining)
        deadline = now.addingTimeInterval(remainingWhenPaused)
        phase = .running
    }

    static func normalizedDuration(_ duration: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return fallback }
        return min(duration, maximumDuration)
    }

    private static func boundedRemaining(_ remaining: TimeInterval) -> TimeInterval {
        guard remaining.isFinite else { return 0 }
        return min(max(0, remaining), maximumDuration)
    }
}

public struct CountdownTimer: Identifiable, Equatable, Sendable {
    public let id: UUID
    public fileprivate(set) var name: String
    public fileprivate(set) var engine: PomodoroEngine
    public fileprivate(set) var displayClock: String

    public init(id: UUID = UUID(), name: String = "", duration: TimeInterval = PomodoroMode.focus.duration) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        engine = PomodoroEngine(focusDuration: duration)
        displayClock = PomodoroEngine.formatMMSS(engine: engine)
    }
}

@MainActor
public final class PomodoroService: ObservableObject {
    @Published public private(set) var engine = PomodoroEngine()
    @Published public private(set) var displayClock = "25:00"
    @Published public private(set) var focusCountdownRunID = UUID()
    @Published public private(set) var name = ""
    @Published public private(set) var countdowns: [CountdownTimer] = []
    /// When "mute notifications" is on, Pomodoro completion signals are suppressed; synced by `AppModel` from settings.
    public var notificationsMuted = false
    public var onDailyBriefingActivity: DailyBriefingActivityHandler?
    public var userCareEnabled = false
    public var onUserCareReminder: ((UserCareReminder) -> Void)?

    public static let focusCountdownNoticeIDPrefix = "focus-countdown-"

    private var timer: Timer?
    private var notificationCenter: UNUserNotificationCenter?
    private let notificationRequestHandler: ((UNNotificationRequest) -> Void)?
    private let completionSoundHandler: (() -> Void)?
    private let now: () -> Date
    private let language: () -> AppLanguage
    private let defaults: UserDefaults
    private let focusDurationKey = "zisla.pomodoro.focusDuration"
    private let restDurationKey = "zisla.pomodoro.restDuration"
    private let nameKey = "zisla.pomodoro.name"
    private var authorizationPromptHost: NSWindow?

    public init(
        notificationCenter: UNUserNotificationCenter? = nil,
        notificationRequestHandler: ((UNNotificationRequest) -> Void)? = nil,
        defaults: UserDefaults = .standard,
        completionSoundHandler: (() -> Void)? = nil,
        language: @escaping () -> AppLanguage = { AppLocalization.currentLanguage },
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.notificationRequestHandler = notificationRequestHandler
        self.completionSoundHandler = completionSoundHandler
        self.now = now
        self.language = language
        let savedFocus = defaults.object(forKey: focusDurationKey) as? TimeInterval
        let savedRest = defaults.object(forKey: restDurationKey) as? TimeInterval
        let focusDuration = PomodoroEngine.normalizedDuration(
            savedFocus ?? PomodoroMode.focus.duration,
            fallback: PomodoroMode.focus.duration
        )
        let restDuration = PomodoroEngine.normalizedDuration(
            savedRest ?? PomodoroMode.rest.duration,
            fallback: PomodoroMode.rest.duration
        )
        if let savedFocus, savedFocus != focusDuration {
            defaults.set(focusDuration, forKey: focusDurationKey)
        }
        if let savedRest, savedRest != restDuration {
            defaults.set(restDuration, forKey: restDurationKey)
        }
        engine = PomodoroEngine(focusDuration: focusDuration, restDuration: restDuration)
        name = defaults.string(forKey: nameKey) ?? ""
        refreshDisplay()
    }

    isolated deinit {
        timer?.invalidate()
    }

    public var mode: PomodoroMode { engine.mode }
    public var phase: PomodoroPhase { engine.phase }
    public var focusDuration: TimeInterval { engine.focusDuration }
    public var restDuration: TimeInterval { engine.restDuration }
    public var displayClockWithHours: String { PomodoroEngine.formatHHMMSS(at: now(), engine: engine) }

    public func focusCountdownNoticeID(for side: NoticeSide) -> String {
        "\(Self.focusCountdownNoticeIDPrefix)\(focusCountdownRunID.uuidString)-\(side.rawValue)"
    }

    public var hasActiveCountdowns: Bool {
        engine.phase != .idle || countdowns.contains { $0.engine.phase != .idle }
    }

    public func setName(_ name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(self.name, forKey: nameKey)
    }

    @discardableResult
    public func addCountdown(name: String = "", duration: TimeInterval = PomodoroMode.focus.duration) -> UUID {
        let countdown = CountdownTimer(name: name, duration: duration)
        countdowns.append(countdown)
        return countdown.id
    }

    public func renameCountdown(id: UUID, name: String) {
        guard let index = countdowns.firstIndex(where: { $0.id == id }) else { return }
        countdowns[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func setCountdownDuration(id: UUID, duration: TimeInterval) {
        guard let index = countdowns.firstIndex(where: { $0.id == id }),
              countdowns[index].engine.phase == .idle else { return }
        countdowns[index].engine = PomodoroEngine(focusDuration: duration)
        refreshDisplay()
    }

    public func toggleCountdown(id: UUID) {
        let date = now()
        tick(at: date)
        guard let index = countdowns.firstIndex(where: { $0.id == id }) else { return }
        if countdowns[index].engine.phase == .running {
            countdowns[index].engine.pause(at: date)
        } else {
            requestNotificationAuthorizationIfNeeded()
            countdowns[index].engine.start(at: date)
        }
        synchronizeTimer()
        refreshDisplay()
    }

    public func cancelCountdown(id: UUID) {
        countdowns.removeAll { $0.id == id }
        synchronizeTimer()
    }

    public func toggleCountdownGroup(_ members: [String]) {
        let date = now()
        tick(at: date)
        let includesPomodoro = members.contains("pomodoro") && engine.phase != .idle
        let indices = countdowns.indices.filter { members.contains(countdowns[$0].id.uuidString) }
        let pauses = includesPomodoro ? engine.phase == .running
            : indices.first.map { countdowns[$0].engine.phase == .running } ?? false
        if !pauses { requestNotificationAuthorizationIfNeeded() }
        if includesPomodoro {
            if pauses { engine.pause(at: date) }
            else { engine.start(at: date) }
        }
        for index in indices {
            if pauses { countdowns[index].engine.pause(at: date) }
            else { countdowns[index].engine.start(at: date) }
        }
        synchronizeTimer()
        refreshDisplay(at: date)
    }

    public func cancelCountdownGroup(_ members: [String]) {
        if members.contains("pomodoro") { engine.reset() }
        countdowns.removeAll { members.contains($0.id.uuidString) }
        synchronizeTimer()
        refreshDisplay()
    }

    public func focusCountdownNotice(for side: NoticeSide) -> IslandNotice {
        countdownNotice(nil, for: side, at: now(), order: 0)
    }

    public func countdownNotices(for side: NoticeSide, limit: Int = 1) -> [IslandNotice] {
        let date = now()
        let candidates: [CountdownTimer?] = (engine.phase == .idle ? [] : [nil])
            + countdowns.filter { $0.engine.phase != .idle }.map { Optional($0) }
        let ordered = candidates.enumerated().sorted { lhs, rhs in
            let left = lhs.element?.engine ?? engine
            let right = rhs.element?.engine ?? engine
            if (left.phase == .running) != (right.phase == .running) {
                return left.phase == .running
            }
            let leftRemaining = left.remaining(at: date)
            let rightRemaining = right.remaining(at: date)
            return leftRemaining == rightRemaining ? lhs.offset < rhs.offset : leftRemaining < rightRemaining
        }
        var groups: [IslandNotice] = []
        for candidate in ordered {
            let notice = countdownNotice(candidate.element, for: side, at: date, order: 0)
            if let index = groups.firstIndex(where: {
                $0.detail == notice.detail && $0.metadata?["timerPhase"] == notice.metadata?["timerPhase"]
            }) {
                groups[index].title += " & " + notice.title
                let names = [groups[index].metadata?["timerName"] ?? "", notice.metadata?["timerName"] ?? ""]
                groups[index].metadata?["timerName"] = names.filter { !$0.isEmpty }.joined(separator: " & ")
                let existing = groups[index].metadata?["timerIDs"]
                    ?? groups[index].metadata?["timerID"] ?? "pomodoro"
                groups[index].metadata?["timerIDs"] = existing + "," + (notice.metadata?["timerID"] ?? "pomodoro")
            } else {
                groups.append(notice)
            }
        }
        return groups.prefix(max(0, limit)).enumerated().map { index, notice in
            var notice = notice
            notice.metadata?["timerOrder"] = String(index)
            return notice
        }
    }

    private func countdownNotice(_ countdown: CountdownTimer?, for side: NoticeSide, at date: Date, order: Int) -> IslandNotice {
        let engine = countdown?.engine ?? self.engine
        let name = countdown?.name ?? self.name
        var metadata = [
            "timerKey": (countdown?.id ?? focusCountdownRunID).uuidString,
            "timerName": name,
            "timerPhase": engine.phase == .running ? "running" : "paused",
            "timerOrder": String(order),
        ]
        if let countdown { metadata["timerID"] = countdown.id.uuidString }
        return IslandNotice(
            id: countdown.map { "\(Self.focusCountdownNoticeIDPrefix)timer-\($0.id.uuidString)-\(side.rawValue)" }
                ?? focusCountdownNoticeID(for: side),
            title: name.isEmpty ? AppLocalization.string(countdown == nil ? engine.mode.title : "计时器", language: language()) : name,
            detail: PomodoroEngine.formatHHMMSS(at: date, engine: engine),
            side: side,
            createdAt: date,
            progress: engine.progress(at: date),
            metadata: metadata
        )
    }

    public func setFocusDuration(_ duration: TimeInterval) {
        let normalized = PomodoroEngine.normalizedDuration(
            duration,
            fallback: PomodoroMode.focus.duration
        )
        engine.focusDuration = normalized
        defaults.set(normalized, forKey: focusDurationKey)
        if engine.mode == .focus {
            engine.reset()
            synchronizeTimer()
        }
        refreshDisplay()
    }

    public func setRestDuration(_ duration: TimeInterval) {
        let normalized = PomodoroEngine.normalizedDuration(
            duration,
            fallback: PomodoroMode.rest.duration
        )
        engine.restDuration = normalized
        defaults.set(normalized, forKey: restDurationKey)
        if engine.mode == .rest {
            engine.reset()
            synchronizeTimer()
        }
        refreshDisplay()
    }

    public func start() {
        let startsFocus = engine.mode == .focus && engine.phase == .idle
        let startsRun = engine.phase != .running
        let date = now()
        requestNotificationAuthorizationIfNeeded()
        engine.start(at: date)
        if startsFocus { onDailyBriefingActivity?(.pomodoroStarted, 1, 0, date) }
        if startsRun {
            focusCountdownRunID = UUID()
        }
        synchronizeTimer()
        refreshDisplay()
    }

    public func pause() {
        let date = now()
        tick(at: date)
        engine.pause(at: date)
        synchronizeTimer()
        refreshDisplay()
    }

    public func toggleStartPause() {
        switch engine.phase {
        case .running:
            pause()
        case .idle, .paused:
            start()
        }
    }

    public func reset() {
        engine.reset()
        synchronizeTimer()
        refreshDisplay()
    }

    public func stop() {
        engine.reset()
        countdowns.removeAll()
        stopTimer()
        refreshDisplay()
    }

    private func synchronizeTimer() {
        if engine.phase == .running || countdowns.contains(where: { $0.engine.phase == .running }) {
            ensureTimer()
        } else {
            stopTimer()
        }
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func resolvedNotificationCenter() -> UNUserNotificationCenter {
        if let notificationCenter { return notificationCenter }
        let center = UNUserNotificationCenter.current()
        notificationCenter = center
        return center
    }

    func tick(at date: Date? = nil) {
        let completedMode = engine.mode
        let completedDuration = engine.duration(for: completedMode)
        let date = date ?? now()
        if engine.completeIfNeeded(at: date) {
            if completedMode == .focus {
                onDailyBriefingActivity?(.pomodoroCompleted, 1, completedDuration, date)
            }
            notifyCompletion(of: completedMode)
        }
        let completed = countdowns.filter { $0.engine.phase == .running && $0.engine.remaining(at: date) <= 0 }
        for countdown in completed {
            countdowns.removeAll { $0.id == countdown.id }
            notifyCountdownCompletion(countdown)
        }
        synchronizeTimer()
        refreshDisplay(at: date)
    }

    func refreshDisplay(at date: Date? = nil) {
        let date = date ?? now()
        let clock = PomodoroEngine.formatMMSS(at: date, engine: engine)
        if displayClock != clock { displayClock = clock }
        for index in countdowns.indices {
            let clock = PomodoroEngine.formatMMSS(at: date, engine: countdowns[index].engine)
            if countdowns[index].displayClock != clock { countdowns[index].displayClock = clock }
        }
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard notificationRequestHandler == nil else { return }
        resolvedNotificationCenter().getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dismissAuthorizationPromptHost()
                self.authorizationPromptHost = WindowPlacement.authorizationPromptHost()
                _ = try? await self.resolvedNotificationCenter().requestAuthorization(options: [.alert, .sound])
                self.dismissAuthorizationPromptHost()
            }
        }
    }

    private func dismissAuthorizationPromptHost() {
        authorizationPromptHost?.orderOut(nil)
        authorizationPromptHost?.close()
        authorizationPromptHost = nil
    }

    private func notifyCompletion(of mode: PomodoroMode) {
        guard !notificationsMuted else { return }
        playCompletionSound()
        if userCareEnabled {
            onUserCareReminder?(mode == .focus ? .focusCompleted : .restCompleted)
            return
        }
        let content = UNMutableNotificationContent()
        let language = self.language()
        switch mode {
        case .focus:
            content.title = AppLocalization.string("专注结束", language: language)
            let restMinutes = max(1, Int(engine.restDuration / 60))
            content.body = AppLocalization.format("休息 %ld 分钟吧", locale: language.locale, [restMinutes])
        case .rest:
            content.title = AppLocalization.string("休息结束", language: language)
            content.body = AppLocalization.string("开始下一段专注", language: language)
        }
        sendCompletionNotification(content, identifier: "zisla.pomodoro.\(UUID().uuidString)")
    }

    private func notifyCountdownCompletion(_ countdown: CountdownTimer) {
        guard !notificationsMuted else { return }
        playCompletionSound()
        let content = UNMutableNotificationContent()
        content.title = countdown.name.isEmpty ? AppLocalization.string("计时器", language: language()) : countdown.name
        content.body = AppLocalization.string("计时结束", language: language())
        sendCompletionNotification(content, identifier: "zisla.countdown.\(countdown.id.uuidString)")
    }

    private func playCompletionSound() {
        if let completionSoundHandler {
            completionSoundHandler()
        } else {
            PomodoroCompletionSoundPlayer.shared.play()
        }
    }

    private func sendCompletionNotification(_ content: UNNotificationContent, identifier: String) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        if let notificationRequestHandler {
            notificationRequestHandler(request)
        } else {
            resolvedNotificationCenter().add(request, withCompletionHandler: nil)
        }
    }
}
