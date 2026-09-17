import Combine
import Foundation
import AppKit
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

@MainActor
public final class PomodoroService: ObservableObject {
    @Published public private(set) var engine = PomodoroEngine()
    @Published public private(set) var displayClock = "25:00"
    /// When "mute notifications" is on, Pomodoro completion notifications are suppressed; synced by `AppModel` from settings.
    public var notificationsMuted = false

    private var timer: Timer?
    private var notificationCenter: UNUserNotificationCenter?
    private let notificationRequestHandler: ((UNNotificationRequest) -> Void)?
    private let defaults: UserDefaults
    private let focusDurationKey = "zisla.pomodoro.focusDuration"
    private let restDurationKey = "zisla.pomodoro.restDuration"
    private var authorizationPromptHost: NSWindow?

    public init(
        notificationCenter: UNUserNotificationCenter? = nil,
        notificationRequestHandler: ((UNNotificationRequest) -> Void)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.notificationRequestHandler = notificationRequestHandler
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
        refreshDisplay()
    }

    isolated deinit {
        timer?.invalidate()
    }

    public var mode: PomodoroMode { engine.mode }
    public var phase: PomodoroPhase { engine.phase }
    public var focusDuration: TimeInterval { engine.focusDuration }
    public var restDuration: TimeInterval { engine.restDuration }
    public var displayClockWithHours: String { PomodoroEngine.formatHHMMSS(engine: engine) }

    public func setFocusDuration(_ duration: TimeInterval) {
        let normalized = PomodoroEngine.normalizedDuration(
            duration,
            fallback: PomodoroMode.focus.duration
        )
        engine.focusDuration = normalized
        defaults.set(normalized, forKey: focusDurationKey)
        if engine.mode == .focus {
            engine.reset()
            stopTimer()
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
            stopTimer()
        }
        refreshDisplay()
    }

    public func start() {
        requestNotificationAuthorizationIfNeeded()
        engine.start()
        ensureTimer()
        refreshDisplay()
    }

    public func pause() {
        engine.pause()
        stopTimer()
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
        stopTimer()
        refreshDisplay()
    }

    public func stop() {
        engine.reset()
        stopTimer()
        refreshDisplay()
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

    private func tick() {
        let completedMode = engine.mode
        if engine.completeIfNeeded() {
            stopTimer()
            notifyCompletion(of: completedMode)
            refreshDisplay()
            return
        }
        refreshDisplay()
    }

    func refreshDisplay() {
        let clock = PomodoroEngine.formatMMSS(engine: engine)
        guard displayClock != clock else { return }
        displayClock = clock
    }

    private func requestNotificationAuthorizationIfNeeded() {
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
        let content = UNMutableNotificationContent()
        switch mode {
        case .focus:
            content.title = AppLocalization.text("专注结束")
            let restMinutes = max(1, Int(engine.restDuration / 60))
            content.body = AppLocalization.text("休息 %ld 分钟吧", restMinutes)
        case .rest:
            content.title = AppLocalization.text("休息结束")
            content.body = AppLocalization.text("开始下一段专注")
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "zisla.pomodoro.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        if let notificationRequestHandler {
            notificationRequestHandler(request)
        } else {
            resolvedNotificationCenter().add(request, withCompletionHandler: nil)
        }
    }
}
