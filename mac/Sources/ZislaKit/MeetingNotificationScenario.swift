import Foundation
import ZislaCore

@MainActor
public final class MeetingNotificationScenario {
    private let queue: SideNoticeQueue
    private let now: () -> Date
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void
    private let onCalendarStateChanged: (Bool) -> Void
    private var events: [CalendarEventSnapshot] = []
    private var automaticallyDetectsMeetings = false
    private var manual = false
    private var cancelTimer: (() -> Void)?
    private var generation: UInt64 = 0

    public init(queue: SideNoticeQueue, now: @escaping () -> Date = Date.init,
                schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void = { delay, action in
                    let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                        Task { @MainActor in action() }
                    }
                    return { timer.invalidate() }
                }, onCalendarStateChanged: @escaping (Bool) -> Void) {
        self.queue = queue
        self.now = now
        self.schedule = schedule
        self.onCalendarStateChanged = onCalendarStateChanged
    }

    public func configure(settings: NotificationScenarioSettings, manual: Bool, events: [CalendarEventSnapshot]) {
        self.automaticallyDetectsMeetings = settings.enabled && settings.automaticallyDetectsMeetings
        self.manual = manual
        self.events = events
        refresh()
    }

    public func stop() {
        generation &+= 1
        cancelTimer?()
        cancelTimer = nil
        events.removeAll()
        manual = false
        automaticallyDetectsMeetings = false
        onCalendarStateChanged(false)
        queue.setNotificationScenario(.meeting, active: false)
    }

    private func refresh() {
        generation &+= 1
        cancelTimer?()
        cancelTimer = nil
        let date = now()
        let meetings = automaticallyDetectsMeetings ? MeetingWorkflow.meetings(in: events, at: date) : []
        let current = MeetingWorkflow.currentMeeting(in: meetings, at: date) != nil
        onCalendarStateChanged(current)
        queue.setNotificationScenario(.meeting, active: manual || current)
        guard !meetings.isEmpty else { return }
        let nextBoundary = meetings.flatMap { [$0.startDate, $0.endDate] }.filter { $0 > date }.min()!
        let generation = self.generation
        cancelTimer = schedule(nextBoundary.timeIntervalSince(date)) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.refresh()
        }
    }
}
