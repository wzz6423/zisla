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
    public nonisolated static let noticeID = "user-care-reminder"
    static let pollingInterval: TimeInterval = 30

    private enum Interruption: Hashable, Sendable {
        case sleep
        case displaySleep
        case inactiveSession
        case lock
    }

    private let queue: SideNoticeQueue
    private let uptime: () -> TimeInterval
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let language: () -> AppLanguage
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
    private var petEnabled = false

    public convenience init(queue: SideNoticeQueue, presentationAllowed: @escaping () -> Bool) {
        self.init(
            queue: queue,
            uptime: { ProcessInfo.processInfo.systemUptime },
            now: Date.init,
            calendar: { .autoupdatingCurrent },
            language: { AppLocalization.currentLanguage },
            activity: Self.currentActivity,
            presentationAllowed: presentationAllowed,
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            distributedCenter: DistributedNotificationCenter.default()
        )
    }

    init(
        queue: SideNoticeQueue,
        uptime: @escaping () -> TimeInterval,
        now: @escaping () -> Date,
        calendar: @escaping () -> Calendar,
        language: @escaping () -> AppLanguage,
        activity: @escaping () -> UserCareActivity?,
        presentationAllowed: @escaping () -> Bool,
        workspaceCenter: NotificationCenter,
        distributedCenter: NotificationCenter,
        timerFactory: @escaping (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer = {
            Timer(timeInterval: $0, repeats: true, block: $1)
        }
    ) {
        self.queue = queue
        self.uptime = uptime
        self.now = now
        self.calendar = calendar
        self.language = language
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
        petEnabled = settings.petEnabled
        guard settings.userCareEnabled && settings.sideNoticesEnabled else {
            stop()
            return
        }
        guard observationID == nil else { return }
        let observationID = UUID()
        self.observationID = observationID
        observe(workspaceCenter, name: NSWorkspace.willSleepNotification, interruption: .sleep, began: true)
        observe(workspaceCenter, name: NSWorkspace.didWakeNotification, interruption: .sleep, began: false)
        observe(workspaceCenter, name: NSWorkspace.screensDidSleepNotification, interruption: .displaySleep, began: true)
        observe(workspaceCenter, name: NSWorkspace.screensDidWakeNotification, interruption: .displaySleep, began: false)
        observe(workspaceCenter, name: NSWorkspace.sessionDidResignActiveNotification, interruption: .inactiveSession, began: true)
        observe(workspaceCenter, name: NSWorkspace.sessionDidBecomeActiveNotification, interruption: .inactiveSession, began: false)
        observe(distributedCenter, name: Notification.Name("com.apple.screenIsLocked"), interruption: .lock, began: true)
        observe(distributedCenter, name: Notification.Name("com.apple.screenIsUnlocked"), interruption: .lock, began: false)

        let timer = timerFactory(Self.pollingInterval) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.observationID == observationID else { return }
                self.refresh()
            }
        }
        timer.tolerance = 5
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh()
    }

    public func stop() {
        observationID = nil
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        interruptions.removeAll()
        schedule.reset()
        clearNotice()
    }

    func refresh() {
        guard observationID != nil else { return }
        guard let activity = activity() else {
            schedule.reset()
            clearNotice()
            return
        }
        let date = now()
        let active = activity.allowsTiming && interruptions.isEmpty
        let reminder = schedule.update(
            at: uptime(),
            isActive: active,
            idleSeconds: activity.idleSeconds,
            localHour: calendar().component(.hour, from: date)
        )
        guard schedule.isWorking, presentationAllowed() else {
            clearNotice()
            return
        }
        guard let reminder else { return }
        queue.enqueue(
            IslandNotice(
                id: Self.noticeID,
                title: AppLocalization.string(reminder.localizationKey(petEnabled: petEnabled), language: language()),
                createdAt: date,
                style: .message
            ),
            expiresAfter: 6
        )
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
                self.clearNotice()
                self.refresh()
            }
        }
        observers.append((center, observer))
    }

    private func clearNotice() {
        if queue.left.contains(where: { $0.id == Self.noticeID })
            || queue.right.contains(where: { $0.id == Self.noticeID }) {
            queue.remove(id: Self.noticeID)
        }
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
