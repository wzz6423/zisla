import Combine
import Foundation
import AppKit
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

/// 纯状态/时间计算：用 deadline 推剩余时间，暂停时冻结 remaining。
public struct PomodoroEngine: Equatable, Sendable {
    public var mode: PomodoroMode
    public var phase: PomodoroPhase
    /// 运行中：结束时刻；暂停/空闲：未使用。
    public var deadline: Date?
    /// 暂停时冻结的剩余秒数；idle 时等于当前模式时长。
    public var remainingWhenPaused: TimeInterval
    /// 可配置的专注时长（秒），默认 25 分钟。
    public var focusDuration: TimeInterval
    /// 可配置的休息时长（秒），默认 5 分钟。
    public var restDuration: TimeInterval

    public init(
        mode: PomodoroMode = .focus,
        phase: PomodoroPhase = .idle,
        deadline: Date? = nil,
        remainingWhenPaused: TimeInterval? = nil,
        focusDuration: TimeInterval = PomodoroMode.focus.duration,
        restDuration: TimeInterval = PomodoroMode.rest.duration
    ) {
        self.mode = mode
        self.phase = phase
        self.deadline = deadline
        self.focusDuration = focusDuration
        self.restDuration = restDuration
        self.remainingWhenPaused = remainingWhenPaused ?? (mode == .focus ? focusDuration : restDuration)
    }

    /// 返回指定模式的当前配置时长。
    public func duration(for mode: PomodoroMode) -> TimeInterval {
        switch mode {
        case .focus: focusDuration
        case .rest: restDuration
        }
    }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        switch phase {
        case .idle:
            return duration(for: mode)
        case .paused:
            return max(0, remainingWhenPaused)
        case .running:
            guard let deadline else { return 0 }
            return max(0, deadline.timeIntervalSince(now))
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
            return String(format: "%02d:%02d:%02d", hours, t.minutes % 60, t.seconds)
        }
        return String(format: "%02d:%02d", t.minutes, t.seconds)
    }

    /// 始终零补齐的 `HH:MM:SS`（例如 29 分 28 秒 → `00:29:28`）。
    public static func formatHHMMSS(at now: Date = Date(), engine: PomodoroEngine) -> String {
        let t = engine.displayTime(at: now)
        return String(format: "%02d:%02d:%02d", t.minutes / 60, t.minutes % 60, t.seconds)
    }

    public mutating func start(at now: Date = Date()) {
        switch phase {
        case .idle:
            remainingWhenPaused = duration(for: mode)
            deadline = now.addingTimeInterval(remainingWhenPaused)
            phase = .running
        case .paused:
            deadline = now.addingTimeInterval(max(0, remainingWhenPaused))
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

    /// 若运行中且已到/超过 deadline，切换到下一模式并回到 idle；返回是否发生切换。
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

    /// 测试辅助：强制以指定剩余时间进入 running。
    public mutating func startWithRemaining(_ remaining: TimeInterval, at now: Date = Date()) {
        remainingWhenPaused = max(0, remaining)
        deadline = now.addingTimeInterval(remainingWhenPaused)
        phase = .running
    }
}

@MainActor
public final class PomodoroService: ObservableObject {
    @Published public private(set) var engine = PomodoroEngine()
    @Published public private(set) var displayClock = "25:00"

    private var timer: Timer?
    private let notificationCenter: UNUserNotificationCenter
    private let notificationRequestHandler: (UNNotificationRequest) -> Void
    private let defaults: UserDefaults
    private let focusDurationKey = "zisla.pomodoro.focusDuration"
    private let restDurationKey = "zisla.pomodoro.restDuration"
    private var authorizationPromptHost: NSWindow?

    public init(
        notificationCenter: UNUserNotificationCenter = .current(),
        notificationRequestHandler: ((UNNotificationRequest) -> Void)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.notificationRequestHandler = notificationRequestHandler ?? { [notificationCenter] request in
            notificationCenter.add(request, withCompletionHandler: nil)
        }
        let savedFocus = defaults.object(forKey: focusDurationKey) as? TimeInterval ?? PomodoroMode.focus.duration
        let savedRest = defaults.object(forKey: restDurationKey) as? TimeInterval ?? PomodoroMode.rest.duration
        engine = PomodoroEngine(focusDuration: savedFocus, restDuration: savedRest)
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
        engine.focusDuration = duration
        defaults.set(duration, forKey: focusDurationKey)
        if engine.mode == .focus {
            engine.reset()
            stopTimer()
        }
        refreshDisplay()
    }

    public func setRestDuration(_ duration: TimeInterval) {
        engine.restDuration = duration
        defaults.set(duration, forKey: restDurationKey)
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

    private func refreshDisplay() {
        displayClock = PomodoroEngine.formatMMSS(engine: engine)
    }

    private func requestNotificationAuthorizationIfNeeded() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dismissAuthorizationPromptHost()
                self.authorizationPromptHost = WindowPlacement.authorizationPromptHost()
                _ = try? await self.notificationCenter.requestAuthorization(options: [.alert, .sound])
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
        let content = UNMutableNotificationContent()
        switch mode {
        case .focus:
            content.title = "专注结束"
            let restMinutes = max(1, Int(engine.restDuration / 60))
            content.body = "休息 \(restMinutes) 分钟吧"
        case .rest:
            content.title = "休息结束"
            content.body = "开始下一段专注"
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "zisla.pomodoro.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationRequestHandler(request)
    }
}
