import AppKit
import Combine
import ZislaCore
import ZislaKit

@MainActor
final class MeetingCountdownController {
    private let calendar: CalendarService
    private let queue: SideNoticeQueue
    private let settings: FeatureSettingsStore
    private let language: AppLanguageStore
    private let now: () -> Date
    private let makeTimer: (TimeInterval, @escaping @Sendable () -> Void) -> Timer
    private var timer: Timer?
    private var generation: UInt64 = 0
    private var isEnabled = false
    private var subscriptions: Set<AnyCancellable> = []

    init(calendar: CalendarService, queue: SideNoticeQueue, settings: FeatureSettingsStore,
         language: AppLanguageStore, now: @escaping () -> Date = Date.init,
         makeTimer: @escaping (TimeInterval, @escaping @Sendable () -> Void) -> Timer = { interval, action in
             Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in action() }
         }) {
        self.calendar = calendar
        self.queue = queue
        self.settings = settings
        self.language = language
        self.now = now
        self.makeTimer = makeTimer
        calendar.$meetingEvents.dropFirst().sink { [weak self] events in self?.update(events: events) }
            .store(in: &subscriptions)
        language.$language.dropFirst().sink { [weak self] value in self?.update(language: value) }
            .store(in: &subscriptions)
    }

    isolated deinit { timer?.invalidate() }

    func configure() {
        isEnabled = settings.settings.calendarEnabled && settings.settings.sideNoticesEnabled
        if isEnabled {
            update()
        } else {
            stop()
        }
    }

    func stop() {
        isEnabled = false
        generation &+= 1
        timer?.invalidate()
        timer = nil
        queue.removeAll(withIDPrefix: MeetingCountdown.noticePrefix)
    }

    func update(events: [CalendarEventSnapshot]? = nil, language: AppLanguage? = nil) {
        generation &+= 1
        timer?.invalidate()
        timer = nil
        let date = now()
        guard isEnabled, let next = MeetingWorkflow.nextMeeting(in: events ?? calendar.meetingEvents, at: date) else {
            queue.removeAll(withIDPrefix: MeetingCountdown.noticePrefix)
            return
        }
        let remaining = next.startDate.timeIntervalSince(date)
        let delay: TimeInterval
        if remaining > MeetingCountdown.leadTime {
            queue.removeAll(withIDPrefix: MeetingCountdown.noticePrefix)
            delay = remaining - MeetingCountdown.leadTime
        } else {
            let notices = MeetingCountdown.notices(for: next, at: date, locale: (language ?? self.language.language).locale)
            queue.removeAll(withIDPrefix: MeetingCountdown.noticePrefix, except: Set(notices.map(\.id)))
            for notice in notices {
                let old = (notice.side == .left ? queue.left : queue.right).first { $0.id == notice.id }
                if old != notice, !queue.updateIfPresent(notice) { queue.enqueue(notice, expiresAfter: nil) }
            }
            delay = remaining > 0 ? min(1, remaining) : next.endDate.timeIntervalSince(date)
        }
        let expectedGeneration = generation
        timer = makeTimer(delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == expectedGeneration else { return }
                self.update()
            }
        }
        timer?.tolerance = min(1, delay * 0.1)
    }
}
