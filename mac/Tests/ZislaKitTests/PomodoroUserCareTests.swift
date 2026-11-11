import Foundation
import Testing
import UserNotifications
import ZislaCore

@testable import ZislaKit

@MainActor
struct PomodoroUserCareTests {
    @Test(arguments: [false, true])
    func realCompletionUsesOneSoundAndCareEventsReplaceSystemBanners(careEnabled: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        #expect(!service.userCareEnabled)
        service.userCareEnabled = careEnabled
        for index in 0..<2 {
            let completedMode = service.mode
            service.start()
            fixture.now += completedMode == .focus ? service.focusDuration : service.restDuration
            service.tick()
            #expect(service.phase == .idle && service.mode == completedMode.next)
            #expect(fixture.sounds == index + 1)
            #expect(fixture.requests.count == (careEnabled ? 0 : index + 1))
            if !careEnabled {
                let request = fixture.requests[index]
                #expect(request.content.title == AppLocalization.string(
                    completedMode == .focus ? "专注结束" : "休息结束", language: .english))
                #expect(request.content.body == (completedMode == .focus
                    ? AppLocalization.format("休息 %ld 分钟吧", locale: AppLanguage.english.locale, [7])
                    : AppLocalization.string("开始下一段专注", language: .english)))
                #expect(request.content.sound == nil, "The custom melody must not be doubled by a notification sound")
            }
            service.tick()
            #expect(fixture.sounds == index + 1)
            #expect(fixture.requests.count == (careEnabled ? 0 : index + 1))
        }
        #expect(fixture.reminders == (careEnabled ? [.focusCompleted, .restCompleted] : []))
    }

    @Test(arguments: [false, true])
    func mutedCompletionsSuppressSoundSystemNotificationsAndCareEvents(careEnabled: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = careEnabled
        service.notificationsMuted = true
        for _ in 0..<2 {
            service.start()
            fixture.now += service.mode == .focus ? service.focusDuration : service.restDuration
            service.tick()
            #expect(service.phase == .idle)
        }
        #expect(fixture.requests.isEmpty && fixture.reminders.isEmpty && fixture.sounds == 0)
    }

    @Test(arguments: ["pause", "reset", "stop"])
    func interruptionNeverFabricatesACompletion(action: String) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = true
        service.start()
        switch action {
        case "pause": service.pause()
        case "reset": service.reset()
        default: service.stop()
        }
        fixture.now += 10_000
        service.tick()
        #expect(fixture.requests.isEmpty && fixture.reminders.isEmpty && fixture.sounds == 0)
        #expect(service.mode == .focus)
    }

    @Test(arguments: [0.0, 0.125, 10_000.0], [false, true])
    func deadlinePauseCompletesEachModeOnceWithoutWaitingForTheNextTick(
        delay: TimeInterval, careEnabled: Bool
    ) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = careEnabled
        for (index, mode) in [PomodoroMode.focus, .rest].enumerated() {
            service.start()
            fixture.now += service.engine.duration(for: mode) + delay

            service.pause()

            #expect(service.phase == .idle && service.mode == mode.next,
                "Pausing an expired countdown must complete it rather than freeze at zero")
            #expect(service.engine.deadline == nil)
            #expect(service.displayClock == (mode == .focus ? "07:00" : "00:01"))
            #expect(service.focusCountdownNotice(for: .left).progress == 0)
            #expect(fixture.sounds == index + 1)
            #expect(fixture.requests.count == (careEnabled ? 0 : index + 1))
            #expect(fixture.reminders == (careEnabled
                ? Array([UserCareReminder.focusCompleted, .restCompleted].prefix(index + 1)) : []))
            #expect(fixture.activity.count(for: .pomodoroCompleted) == 1)
            #expect(fixture.activity.completedFocusSeconds == 1)

            service.pause()
            service.tick()
            #expect(service.phase == .idle && service.mode == mode.next)
            #expect(fixture.sounds == index + 1)
            #expect(fixture.requests.count == (careEnabled ? 0 : index + 1))
            #expect(fixture.activity.count(for: .pomodoroCompleted) == 1)
        }
        service.start()
        service.tick()
        #expect(service.phase == .running && service.mode == .focus)
        #expect(service.engine.remaining(at: fixture.now) == 1)
        #expect(fixture.sounds == 2)
    }

    @Test(arguments: [0.5, 0.001])
    func preDeadlinePauseFreezesAndResumeUsesTheSavedRemaining(remaining: TimeInterval) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = true
        for (index, mode) in [PomodoroMode.focus, .rest].enumerated() {
            service.start()
            fixture.now += service.engine.duration(for: mode) - remaining
            service.pause()
            let frozenClock = service.displayClock
            #expect(service.phase == .paused && service.mode == mode)
            #expect(abs(service.engine.remaining(at: fixture.now) - remaining) < 0.000_001)
            fixture.now += 10_000
            service.pause()
            service.tick()
            #expect(service.phase == .paused && service.displayClock == frozenClock)
            #expect(abs(service.engine.remaining(at: fixture.now) - remaining) < 0.000_001)
            #expect(fixture.sounds == index && fixture.reminders.count == index && fixture.requests.isEmpty)

            service.start()
            #expect(service.phase == .running && service.mode == mode)
            fixture.now += remaining + 0.125
            service.tick()
            #expect(service.phase == .idle && service.mode == mode.next)
            #expect(fixture.sounds == index + 1 && fixture.reminders.count == index + 1)
        }
        #expect(fixture.activity.count(for: .pomodoroStarted) == 1,
            "Resuming must not count as a new focus session")
        #expect(fixture.activity.count(for: .pomodoroCompleted) == 1)
        #expect(fixture.activity.completedFocusSeconds == 1)
    }

    @Test(arguments: [false, true])
    func mutedDeadlinePauseCompletesWithoutSoundBannerOrCare(careEnabled: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = careEnabled
        service.notificationsMuted = true
        for mode in [PomodoroMode.focus, .rest] {
            service.start()
            fixture.now += service.engine.duration(for: mode) + 0.125
            service.pause()
            #expect(service.phase == .idle && service.mode == mode.next)
            service.tick()
            #expect(fixture.requests.isEmpty && fixture.reminders.isEmpty && fixture.sounds == 0)
        }
        #expect(fixture.activity.count(for: .pomodoroCompleted) == 1)
        #expect(fixture.activity.completedFocusSeconds == 1)
    }

    @Test
    func idlePauseAndExpiredPauseWithoutCareHandlerKeepConsistentState() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = true
        service.onUserCareReminder = nil
        let idle = service.engine
        service.pause()
        #expect(service.engine == idle)
        #expect(fixture.requests.isEmpty && fixture.reminders.isEmpty && fixture.sounds == 0)
        service.start()
        fixture.now += service.focusDuration
        service.pause()
        service.pause()
        service.tick()
        #expect(service.phase == .idle && service.mode == .rest)
        #expect(fixture.requests.isEmpty && fixture.reminders.isEmpty && fixture.sounds == 1)
        #expect(fixture.activity.count(for: .pomodoroCompleted) == 1)
    }

    @Test
    func deadlineCrossingBetweenClockReadsNeverFreezesAnExpiredCountdown() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = true
        service.start()
        let deadline = try #require(service.engine.deadline)
        fixture.now = deadline.addingTimeInterval(0.125)
        fixture.clockSamples = [deadline.addingTimeInterval(-0.001), fixture.now]

        service.pause()

        #expect(service.phase == .paused && service.mode == .focus,
            "A pause sampled before the deadline must not be completed by a later clock read")
        #expect(abs(service.engine.remaining(at: deadline) - 0.001) < 0.000_001,
            "Completion and pause must use the same instant so remaining time cannot freeze at zero")
        #expect(fixture.sounds == 0 && fixture.requests.isEmpty && fixture.reminders.isEmpty)
        fixture.now = deadline.addingTimeInterval(10_000)
        service.start()
        fixture.now += 0.125
        service.tick()
        #expect(service.phase == .idle && service.mode == .rest)
        #expect(fixture.sounds == 1 && fixture.reminders == [.focusCompleted])
        #expect(fixture.activity.count(for: .pomodoroCompleted) == 1)
    }

    @Test
    func repeatedLateTicksAndPausesKeepCompletionBounded() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = true
        for _ in 0..<16 {
            service.start()
            fixture.now += service.engine.duration(for: service.mode) + 10_000
            service.pause()
            for _ in 0..<16 {
                service.tick()
                service.pause()
            }
            #expect(service.phase == .idle && service.engine.deadline == nil)
        }
        #expect(fixture.sounds == 16 && fixture.reminders.count == 16 && fixture.requests.isEmpty)
        #expect(fixture.activity.count(for: .pomodoroStarted) == 8)
        #expect(fixture.activity.count(for: .pomodoroCompleted) == 8)
        #expect(fixture.activity.completedFocusSeconds == 8)
    }

    @Test(arguments: AppLanguage.allCases)
    func ordinaryCompletionTitlesKeepTheirRequestedLanguage(language: AppLanguage) throws {
        let fixture = try Fixture(language: language)
        defer { fixture.close() }
        let service = fixture.service
        for mode in [PomodoroMode.focus, .rest] {
            service.start()
            fixture.now += mode == .focus ? service.focusDuration : service.restDuration
            service.tick()
            #expect(fixture.requests.last?.content.title == AppLocalization.string(
                mode == .focus ? "专注结束" : "休息结束", language: language))
        }
        #expect(fixture.sounds == 2 && fixture.reminders.isEmpty)
    }

    @Test
    func changesDuringTheCountdownUseTheLatestCareAndMuteSettings() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.start()
        service.userCareEnabled = true
        fixture.now += service.focusDuration
        service.tick()
        #expect(fixture.requests.isEmpty && fixture.reminders == [.focusCompleted] && fixture.sounds == 1)
        service.start()
        service.userCareEnabled = false
        fixture.now += service.restDuration
        service.tick()
        #expect(fixture.requests.count == 1 && fixture.sounds == 2 && fixture.reminders == [.focusCompleted])
        service.start()
        service.notificationsMuted = true
        fixture.now += service.focusDuration
        service.tick()
        #expect(fixture.requests.count == 1 && fixture.sounds == 2 && fixture.reminders == [.focusCompleted])
    }

    @Test
    func unavailableIslandHandlerNeverFallsBackToAnExternalCareBanner() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.service.userCareEnabled = true
        fixture.service.onUserCareReminder = nil
        fixture.service.start()
        fixture.now += fixture.service.focusDuration
        fixture.service.tick()
        #expect(fixture.requests.isEmpty && fixture.reminders.isEmpty && fixture.sounds == 1)
    }

    @Test
    func scenePolicySuppressesTheSoundAndBannerAndReportsOneReviewEvent() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        var suppressed: [UserCareReminder] = []
        fixture.service.completionPresentationAllowed = { false }
        fixture.service.onSuppressedCompletion = { suppressed.append($0) }
        fixture.service.start()
        fixture.now += fixture.service.focusDuration
        fixture.service.tick()
        fixture.service.tick()
        #expect(fixture.sounds == 0 && fixture.requests.isEmpty && fixture.reminders.isEmpty)
        #expect(suppressed == [.focusCompleted])
        fixture.service.notificationsMuted = true
        fixture.service.start()
        fixture.now += fixture.service.restDuration
        fixture.service.tick()
        #expect(suppressed == [.focusCompleted], "The existing global mute must discard completions before scenario handling")
    }

    @Test
    func ownFocusCompletionPresentsAfterItsSceneEndsButAnOverlappingMeetingDefersIt() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let queue = SideNoticeQueue(now: { fixture.now })
        defer { queue.removeAll() }
        queue.configureNotificationScenarios(.init(enabled: true), displayIdentifiers: ["display"])
        let subscription = fixture.service.$engine.sink { engine in
            queue.setNotificationScenario(.focus, active: engine.mode == .focus && engine.phase != .idle)
        }
        fixture.service.completionPresentationAllowed = {
            queue.notificationBehavior(for: .ordinary, displayIdentifier: "display") == .show
        }
        fixture.service.onSuppressedCompletion = { reminder in
            queue.recordScenarioEvent(.init(id: "pomodoro-completion", title: String(describing: reminder)))
            queue.releaseScenarioEventVisibility(id: "pomodoro-completion")
        }
        fixture.service.start()
        #expect(queue.activeNotificationScenarios == [.focus])
        queue.enqueue(.init(id: "during-focus", title: "During focus"), expiresAfter: nil)
        let elapsed = fixture.service.focusDuration / 2
        fixture.now += elapsed
        fixture.service.pause()
        let paused = fixture.service.focusCountdownNotice(for: .right)
        fixture.now += 100
        fixture.service.tick()
        #expect(fixture.service.phase == .paused && queue.activeNotificationScenarios == [.focus])
        #expect(fixture.service.focusCountdownNotice(for: .right).detail == paused.detail)
        #expect(fixture.service.focusCountdownNotice(for: .right).progress == paused.progress)
        #expect(queue.notificationBehavior(for: .ordinary, displayIdentifier: "display") == .deferUntilEnd)
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
        #expect(fixture.sounds == 0 && fixture.requests.isEmpty)
        fixture.service.start()
        #expect(queue.activeNotificationScenarios == [.focus] && fixture.service.phase == .running)
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
        fixture.now += fixture.service.focusDuration - elapsed
        fixture.service.tick()
        #expect(queue.activeNotificationScenarios.isEmpty && fixture.sounds == 1 && fixture.requests.count == 1)
        #expect(queue.scenarioReview(displayIdentifier: "display").map(\.title) == ["During focus"])
        queue.dismissScenarioReview(displayIdentifier: "display")
        queue.setNotificationScenario(.meeting, active: true)
        fixture.service.start()
        fixture.now += fixture.service.restDuration
        fixture.service.tick()
        #expect(fixture.sounds == 1 && fixture.requests.count == 1)
        queue.setNotificationScenario(.meeting, active: false)
        #expect(queue.scenarioReview(displayIdentifier: "display").map(\.title) == ["restCompleted"])
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    private final class Fixture {
        let suiteName = "Zisla.PomodoroCare.\(UUID().uuidString)"
        let defaults: UserDefaults
        let language: AppLanguage
        var now = Date(timeIntervalSince1970: 10_000_000)
        var requests: [UNNotificationRequest] = []
        var sounds = 0
        var reminders: [UserCareReminder] = []
        var activity = DailyBriefingActivityTotals()
        var clockSamples: [Date] = []
        lazy var service: PomodoroService = {
            let service = PomodoroService(
                notificationRequestHandler: { [unowned self] in requests.append($0) },
                defaults: defaults,
                completionSoundHandler: { [unowned self] in sounds += 1 },
                language: { [unowned self] in language },
                now: { [unowned self] in clockSamples.isEmpty ? now : clockSamples.removeFirst() }
            )
            service.onUserCareReminder = { [unowned self] in reminders.append($0) }
            service.onDailyBriefingActivity = { [unowned self] kind, count, seconds, _ in
                activity.record(kind, count: count, focusSeconds: seconds)
            }
            service.setFocusDuration(1)
            service.setRestDuration(7 * 60)
            return service
        }()

        init(language: AppLanguage = .english) throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            self.language = language
        }

        func close() {
            service.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
