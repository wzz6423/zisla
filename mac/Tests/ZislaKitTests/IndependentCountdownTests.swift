import Combine
import Foundation
import Testing
import UserNotifications
import ZislaCore
@testable import ZislaKit

@MainActor
struct IndependentCountdownTests {
    @Test
    func pauseResumeCancelAndPomodoroResetAffectOnlyTheSelectedTimer() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.setFocusDuration(100)
        let tea = service.addCountdown(name: "Tea", duration: 60)
        let meeting = service.addCountdown(name: "Meeting", duration: 120)
        service.start()
        service.toggleCountdown(id: tea)
        service.toggleCountdown(id: meeting)
        fixture.date += 10
        service.toggleCountdown(id: tea)
        #expect(service.countdowns.first { $0.id == tea }?.displayClock == "00:50")
        fixture.date += 20
        service.tick()
        #expect(service.countdowns.first { $0.id == tea }?.displayClock == "00:50")
        #expect(service.countdowns.first { $0.id == meeting }?.displayClock == "01:30")
        #expect(service.displayClock == "01:10")
        service.reset()
        #expect(service.countdowns.first { $0.id == meeting }?.engine.phase == .running)
        service.toggleCountdown(id: tea)
        fixture.date += 5
        service.tick()
        #expect(service.countdowns.first { $0.id == tea }?.displayClock == "00:45")
        service.cancelCountdown(id: meeting)
        #expect(service.countdowns.map(\.id) == [tea])
        #expect(fixture.notifications.isEmpty && fixture.sounds == 0)
        service.stop()
        #expect(service.countdowns.isEmpty && !service.hasActiveCountdowns)
    }

    @Test
    func missedTicksCompleteEveryDueTimerExactlyOnceAndKeepLaterTimersRunning() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.setFocusDuration(10)
        service.start()
        let first = service.addCountdown(name: "Tea", duration: 10)
        let second = service.addCountdown(name: "Meeting", duration: 20)
        let later = service.addCountdown(duration: 100)
        for id in [first, second, later] { service.toggleCountdown(id: id) }
        fixture.date += 30
        service.tick()
        service.tick()
        #expect(fixture.notifications.count == 3 && fixture.sounds == 3)
        #expect(Set(fixture.notifications.map(\.identifier)).count == 3)
        #expect(fixture.notifications.map(\.content.title).contains("Tea"))
        #expect(fixture.notifications.map(\.content.title).contains("Meeting"))
        #expect(service.mode == .rest && service.phase == .idle)
        #expect(service.countdowns.map(\.id) == [later])
        #expect(service.countdowns.first?.displayClock == "01:10")
    }

    @Test
    func pausingAtTheDeadlineCannotReviveAnExpiredCountdown() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let id = fixture.service.addCountdown(duration: 1)
        fixture.service.toggleCountdown(id: id)
        fixture.date += 1
        fixture.service.toggleCountdown(id: id)
        #expect(fixture.service.countdowns.isEmpty)
        #expect(fixture.notifications.count == 1)
        fixture.service.toggleCountdown(id: id)
        fixture.service.tick()
        #expect(fixture.notifications.count == 1)
    }

    @Test
    func mutedTimersCompleteWithoutNotificationsAndCancellationNeverCompletes() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.service.notificationsMuted = true
        let muted = fixture.service.addCountdown(duration: 1)
        fixture.service.toggleCountdown(id: muted)
        fixture.date += 1
        fixture.service.tick()
        fixture.service.notificationsMuted = false
        let canceled = fixture.service.addCountdown(duration: 1)
        fixture.service.toggleCountdown(id: canceled)
        fixture.service.cancelCountdown(id: canceled)
        fixture.date += 2
        fixture.service.tick()
        #expect(fixture.notifications.isEmpty && fixture.sounds == 0)
        #expect(!fixture.service.hasActiveCountdowns)
    }

    @Test
    func nearestRunningTimersWinAndPausedTimersKeepTheirNamesAndFrozenTime() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        #expect(service.countdownNotices(for: .left).isEmpty)
        service.setFocusDuration(100)
        service.setName("Writing")
        service.start()
        let tea = service.addCountdown(name: "Tea", duration: 10)
        let meeting = service.addCountdown(name: "Meeting", duration: 30)
        service.toggleCountdown(id: tea)
        service.toggleCountdown(id: meeting)
        #expect(service.countdownNotices(for: .left, limit: 2).map(\.title) == ["Tea", "Meeting"])
        service.toggleCountdown(id: tea)
        #expect(service.countdownNotices(for: .left, limit: 2).map(\.title) == ["Meeting", "Writing"])
        service.pause()
        service.toggleCountdown(id: meeting)
        fixture.date += 1000
        let paused = service.countdownNotices(for: .right, limit: 2)
        #expect(paused.map(\.title) == ["Tea", "Meeting"])
        #expect(paused.map(\.detail) == ["00:00:10", "00:00:30"])
        #expect(paused.allSatisfy { $0.metadata?["timerPhase"] == "paused" })
        #expect(service.countdownNotices(for: .left, limit: 0).isEmpty)
    }

    @Test
    func equalDeadlinesKeepCreationOrderAndNamesUpdateWithoutResettingTime() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        let first = service.addCountdown(duration: 60)
        let second = service.addCountdown(duration: 60)
        service.toggleCountdown(id: first)
        service.toggleCountdown(id: second)
        fixture.date += 10
        service.renameCountdown(id: first, name: "  Tea  ")
        service.renameCountdown(id: second, name: " \n ")
        let notices = service.countdownNotices(for: .left, limit: 2)
        #expect(notices.count == 1)
        #expect(notices.first?.metadata?["timerIDs"] == "\(first.uuidString),\(second.uuidString)")
        #expect(notices.first?.title == "Tea & Timer" && notices.first?.detail == "00:00:50")
        #expect(notices.first?.metadata?["timerName"] == "Tea")
        #expect(service.countdowns.first?.engine.deadline == fixture.date.addingTimeInterval(50))
    }

    @Test
    func matchingDisplayedTimesMergeNamesAndDifferentPhasesRemainIndependent() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        let first = service.addCountdown(name: "A", duration: 60)
        let second = service.addCountdown(name: "B", duration: 60)
        let later = service.addCountdown(name: "C", duration: 120)
        service.toggleCountdown(id: first)
        service.toggleCountdown(id: second)
        service.toggleCountdown(id: later)
        let groups = service.countdownNotices(for: .left, limit: 2)
        #expect(groups.map(\.title) == ["A & B", "C"])
        #expect(groups.first?.metadata?["timerName"] == "A & B")
        service.toggleCountdown(id: first)
        #expect(service.countdownNotices(for: .left, limit: 3).map(\.title) == ["B", "C", "A"])
    }

    @Test
    func mergedTimersSharePauseResumeAndCancelWithoutAffectingAnotherCountdown() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.setFocusDuration(60)
        service.setName("A")
        service.start()
        let first = service.addCountdown(name: "B", duration: 60)
        let second = service.addCountdown(name: "C", duration: 60)
        let later = service.addCountdown(name: "Other", duration: 120)
        for id in [first, second, later] { service.toggleCountdown(id: id) }
        let notice = try #require(service.countdownNotices(for: .left).first)
        #expect(notice.title == "A & B & C")
        let members = try #require(notice.metadata?["timerIDs"]).components(separatedBy: ",")
        fixture.date += 10
        service.toggleCountdownGroup(members)
        #expect(service.phase == .paused)
        #expect(service.countdowns.filter { $0.id != later }.allSatisfy { $0.engine.phase == .paused })
        #expect(service.countdowns.first { $0.id == later }?.engine.phase == .running)
        fixture.date += 20
        service.toggleCountdownGroup(members)
        #expect(service.phase == .running && service.displayClock == "00:50")
        #expect(service.countdowns.filter { $0.id != later }.allSatisfy { $0.displayClock == "00:50" })
        service.cancelCountdownGroup(members)
        #expect(service.phase == .idle && service.countdowns.map(\.id) == [later])
        #expect(fixture.notifications.isEmpty && fixture.sounds == 0)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1, 0, .greatestFiniteMagnitude])
    func invalidAndLargeDurationsUseTheExistingEngineBounds(duration: Double) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let id = fixture.service.addCountdown(duration: duration)
        let timer = try #require(fixture.service.countdowns.first)
        #expect(timer.engine.focusDuration.isFinite && timer.engine.focusDuration > 0)
        #expect(timer.engine.focusDuration <= PomodoroEngine.maximumDuration)
        fixture.service.setCountdownDuration(id: id, duration: 3723)
        #expect(fixture.service.countdowns.first?.displayClock == "01:02:03")
        fixture.service.toggleCountdown(id: id)
        fixture.service.setCountdownDuration(id: id, duration: 1)
        #expect(fixture.service.countdowns.first?.engine.focusDuration == 3723)
    }

    @Test
    func missingIDsCannotChangeAnotherTimerAndClockPublishesOnlyOnSecondChanges() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        let id = service.addCountdown(duration: 60)
        let missing = UUID()
        let original = service.countdowns
        service.toggleCountdown(id: missing)
        service.renameCountdown(id: missing, name: "Wrong timer")
        service.setCountdownDuration(id: missing, duration: 1)
        service.cancelCountdown(id: missing)
        #expect(service.countdowns == original && service.phase == .idle)
        service.toggleCountdown(id: id)
        var updates = 0
        let subscription = service.$countdowns.dropFirst().sink { _ in updates += 1 }
        fixture.date += 0.1
        service.tick()
        #expect(updates == 0)
        fixture.date += 1
        service.tick()
        #expect(updates == 1 && service.countdowns.first?.displayClock == "00:59")
        subscription.cancel()
    }

    @Test
    func pomodoroNameIsRestoredWhileIndependentTimersStaySessionScoped() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.service.setName("  Writing  ")
        fixture.service.addCountdown(name: "Tea")
        let restored = PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults)
        defer { restored.stop() }
        #expect(restored.name == "Writing" && restored.countdowns.isEmpty)
    }

    @MainActor
    private final class Fixture {
        let suite = "IndependentCountdownTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        private let clock = Clock()
        var date: Date {
            get { clock.date }
            set { clock.date = newValue }
        }
        var notifications: [UNNotificationRequest] { clock.notifications }
        var sounds: Int { clock.sounds }
        lazy var service = PomodoroService(
            notificationRequestHandler: { [clock] in clock.notifications.append($0) },
            defaults: defaults,
            completionSoundHandler: { [clock] in clock.sounds += 1 },
            language: { .english }, now: { [clock] in clock.date }
        )

        private final class Clock {
            var date = Date(timeIntervalSince1970: 10_000)
            var notifications: [UNNotificationRequest] = []
            var sounds = 0
        }

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
        }

        func close() {
            service.stop()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
