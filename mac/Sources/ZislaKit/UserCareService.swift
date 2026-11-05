import AppKit
import CoreGraphics
import Foundation
import ZislaCore

struct UserCareActivity {
    var isScreenAwake: Bool
    var isSessionActive: Bool
    var isScreenLocked: Bool
    var idleSeconds: TimeInterval?

    var allowsTiming: Bool {
        isScreenAwake && isSessionActive && !isScreenLocked
    }
}

@MainActor
public final class UserCareService {
    static let pollingInterval: TimeInterval = 30

    private enum Interruption: Hashable, Sendable {
        case sleep
        case displaySleep
        case inactiveSession
        case lock
    }

    private let onReminder: (UserCareReminder) -> Void
    private let onClear: (_ routineOnly: Bool) -> Void
    private let chooseIndex: (Range<Int>) -> Int
    private let uptime: () -> TimeInterval
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let activity: () -> UserCareActivity?
    private let presentationAllowed: () -> Bool
    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private let timerFactory: (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var interruptions: Set<Interruption> = []
    private var observationID: UUID?
    private var schedule = UserCareSchedule()

    public convenience init(
        presentationAllowed: @escaping () -> Bool,
        onReminder: @escaping (UserCareReminder) -> Void,
        onClear: @escaping (_ routineOnly: Bool) -> Void
    ) {
        self.init(
            onReminder: onReminder,
            onClear: onClear,
            uptime: { ProcessInfo.processInfo.systemUptime },
            now: Date.init,
            calendar: { .autoupdatingCurrent },
            activity: Self.currentActivity,
            presentationAllowed: presentationAllowed,
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            distributedCenter: DistributedNotificationCenter.default()
        )
    }

    init(
        onReminder: @escaping (UserCareReminder) -> Void,
        onClear: @escaping (_ routineOnly: Bool) -> Void,
        uptime: @escaping () -> TimeInterval,
        now: @escaping () -> Date,
        calendar: @escaping () -> Calendar,
        activity: @escaping () -> UserCareActivity?,
        presentationAllowed: @escaping () -> Bool,
        workspaceCenter: NotificationCenter,
        distributedCenter: NotificationCenter,
        chooseIndex: @escaping (Range<Int>) -> Int = { Int.random(in: $0) },
        timerFactory: @escaping (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer = {
            Timer(timeInterval: $0, repeats: true, block: $1)
        }
    ) {
        self.onReminder = onReminder
        self.onClear = onClear
        self.chooseIndex = chooseIndex
        self.uptime = uptime
        self.now = now
        self.calendar = calendar
        self.activity = activity
        self.presentationAllowed = presentationAllowed
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
        self.timerFactory = timerFactory
    }

    isolated deinit {
        stop()
    }

    public func apply(settings: FeatureSettings) {
        guard settings.userCareEnabled else {
            stop()
            return
        }
        if schedule.interval != settings.userCareReminderInterval {
            schedule.setInterval(settings.userCareReminderInterval)
            timer?.invalidate()
            timer = nil
            onClear(true)
        }
        if observationID == nil {
            observationID = UUID()
            observe(workspaceCenter, name: NSWorkspace.willSleepNotification, interruption: .sleep, began: true)
            observe(workspaceCenter, name: NSWorkspace.didWakeNotification, interruption: .sleep, began: false)
            observe(workspaceCenter, name: NSWorkspace.screensDidSleepNotification, interruption: .displaySleep, began: true)
            observe(workspaceCenter, name: NSWorkspace.screensDidWakeNotification, interruption: .displaySleep, began: false)
            observe(workspaceCenter, name: NSWorkspace.sessionDidResignActiveNotification, interruption: .inactiveSession, began: true)
            observe(workspaceCenter, name: NSWorkspace.sessionDidBecomeActiveNotification, interruption: .inactiveSession, began: false)
            observe(distributedCenter, name: Notification.Name("com.apple.screenIsLocked"), interruption: .lock, began: true)
            observe(distributedCenter, name: Notification.Name("com.apple.screenIsUnlocked"), interruption: .lock, began: false)
        }

        guard timer == nil else { return }
        refresh()
        let timer = timerFactory(min(Self.pollingInterval, schedule.interval)) { [weak self] timer in
            let timerID = ObjectIdentifier(timer)
            MainActor.assumeIsolated {
                guard let self, let activeTimer = self.timer,
                      ObjectIdentifier(activeTimer) == timerID else { return }
                self.refresh()
            }
        }
        self.timer = timer
        scheduleNextTick()
        RunLoop.main.add(timer, forMode: .common)
    }

    public func stop() {
        observationID = nil
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        interruptions.removeAll()
        schedule.reset()
        onClear(false)
    }

    func refresh() {
        guard observationID != nil else { return }
        defer { scheduleNextTick() }
        guard let activity = activity() else {
            schedule.reset()
            onClear(true)
            return
        }
        let date = now()
        let active = activity.allowsTiming && interruptions.isEmpty
        let reminder = schedule.update(
            at: uptime(),
            isActive: active,
            idleSeconds: activity.idleSeconds,
            localHour: calendar().component(.hour, from: date),
            chooseIndex: chooseIndex
        )
        let allowed = presentationAllowed()
        guard schedule.isWorking, allowed else {
            onClear(active && allowed)
            return
        }
        guard let reminder else { return }
        onReminder(reminder)
    }

    private func scheduleNextTick() {
        guard let timer else { return }
        let remaining = schedule.timeUntilReminder(at: uptime())
        let delay = min(Self.pollingInterval, remaining)
        timer.fireDate = Date(timeIntervalSinceNow: delay)
        timer.tolerance = min(5, remaining - delay)
    }

    private func observe(
        _ center: NotificationCenter,
        name: Notification.Name,
        interruption: Interruption,
        began: Bool
    ) {
        let observationID = observationID
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.observationID == observationID else { return }
                if began {
                    self.interruptions.insert(interruption)
                } else {
                    self.interruptions.remove(interruption)
                }
                self.schedule.reset()
                self.onClear(false)
                self.refresh()
            }
        }
        observers.append((center, observer))
    }

    private static func currentActivity() -> UserCareActivity? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        let screens = NSScreen.screens.compactMap(ScreenSnapshot.init(screen:))
        return UserCareActivity(
            isScreenAwake: screens.contains { CGDisplayIsAsleep($0.displayID) == 0 },
            isSessionActive: session[kCGSessionOnConsoleKey as String] as? Bool == true,
            isScreenLocked: session["CGSSessionScreenIsLocked"] as? Bool ?? false,
            idleSeconds: CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: CGEventType(rawValue: UInt32.max)!
            )
        )
    }
}
