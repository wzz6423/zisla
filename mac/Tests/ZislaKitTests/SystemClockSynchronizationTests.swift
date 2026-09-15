import Combine
import Foundation
import Testing
import UserNotifications
import XCTest

@testable import ZislaKit

@MainActor
struct SystemClockSynchronizationTests {
    @Test
    func startPauseResumeAndCancellationFollowSystemState() {
        let fixture = Fixture()
        let service = fixture.service
        defer { service.stop() }
        fixture.snapshot = .init(identifier: "timer", state: .running(deadline: fixture.now.addingTimeInterval(90)))

        service.startSystemClockMonitoring()
        #expect(service.phase == .running)
        #expect(service.displayClock == "01:30")
        #expect(service.displayClockWithHours == "00:01:30")

        fixture.now.addTimeInterval(30)
        service.tick()
        #expect(service.displayClock == "01:00")

        fixture.snapshot = .init(identifier: "timer", state: .paused(remaining: 60))
        service.tick()
        fixture.now.addTimeInterval(600)
        service.tick()
        #expect(service.phase == .paused)
        #expect(service.displayClock == "01:00")
        #expect(service.displayClockWithHours == "00:01:00")

        fixture.snapshot = .init(identifier: "timer", state: .running(deadline: fixture.now.addingTimeInterval(60)))
        service.tick()
        fixture.now.addTimeInterval(1)
        service.tick()
        #expect(service.phase == .running)
        #expect(service.displayClock == "00:59")

        fixture.snapshot = nil
        service.tick()
        #expect(service.phase == .idle)
        #expect(service.engine.deadline == nil)
        #expect(fixture.notifications.isEmpty)
    }

    @Test
    func wakeAndSystemEditsUseAbsoluteDeadline() {
        let fixture = Fixture()
        let service = fixture.service
        defer { service.stop() }
        fixture.snapshot = .init(identifier: "timer", state: .running(deadline: fixture.now.addingTimeInterval(3_723)))
        service.startSystemClockMonitoring()
        #expect(service.displayClock == "01:02:03")

        fixture.now.addTimeInterval(3_600)
        service.tick()
        #expect(service.displayClock == "02:03")

        fixture.snapshot = .init(identifier: "timer", state: .running(deadline: fixture.now.addingTimeInterval(300)))
        service.tick()
        #expect(service.displayClock == "05:00")
        #expect(service.displayClockWithHours == "00:05:00")
    }

    @Test
    func expirationDoesNotSwitchToRestOrSendDuplicateNotification() {
        let fixture = Fixture()
        let service = fixture.service
        defer { service.stop() }
        let firedDate = fixture.now.addingTimeInterval(1)
        var record: [String: Any] = [
            "MTTimerID": "timer",
            "MTTimerState": 3,
            "MTTimerFireTime": ["$MTTimerDate": ["MTTimerTimeDate": firedDate]],
        ]
        fixture.snapshot = SystemClockTimerStore.snapshot(from: ["MTTimers": [["$MTTimer": record]]])
        service.startSystemClockMonitoring()
        #expect(service.displayClock == "00:01")

        fixture.now.addTimeInterval(10)
        service.tick()
        #expect(service.displayClock == "00:00")

        record["MTTimerState"] = 1
        record["MTTimerFireTime"] = nil
        record["MTTimerFiredDate"] = firedDate
        record["MTTimerDismissedDate"] = firedDate.addingTimeInterval(-60)
        fixture.snapshot = SystemClockTimerStore.snapshot(from: ["MTTimers": [["$MTTimer": record]]])
        service.tick()
        fixture.now.addTimeInterval(60)
        service.tick()

        #expect(service.mode == .focus)
        #expect(service.phase == .running)
        #expect(service.displayClock == "00:00")
        #expect(service.displayClockWithHours == "00:00:00")
        #expect(fixture.notifications.isEmpty)

        record["MTTimerDismissedDate"] = fixture.now
        fixture.snapshot = SystemClockTimerStore.snapshot(from: ["MTTimers": [["$MTTimer": record]]])
        service.tick()
        #expect(service.phase == .idle)
        #expect(service.engine.deadline == nil)
        #expect(fixture.notifications.isEmpty)
    }

    @Test
    func absentSystemTimerClearsDisplayAndLaterTimerIsDetected() {
        let fixture = Fixture()
        let service = fixture.service
        defer { service.stop() }
        service.startSystemClockMonitoring()
        #expect(service.phase == .idle)

        fixture.snapshot = .init(identifier: "new", state: .paused(remaining: 12.1))
        service.tick()
        #expect(service.phase == .paused)
        #expect(service.displayClock == "00:13")

        fixture.snapshot = nil
        service.tick()
        #expect(service.phase == .idle)

        fixture.snapshot = .init(identifier: "recovered", state: .running(deadline: fixture.now.addingTimeInterval(30)))
        service.tick()
        #expect(service.phase == .running)
        #expect(service.displayClock == "00:30")
    }

    @Test
    func repeatedSnapshotsPublishOnlyChangedClockText() {
        let fixture = Fixture()
        let service = fixture.service
        defer { service.stop() }
        fixture.snapshot = .init(identifier: "timer", state: .running(deadline: fixture.now.addingTimeInterval(60)))
        service.startSystemClockMonitoring()
        var engineUpdates = 0
        var clocks: [String] = []
        let engineObservation = service.$engine.dropFirst().sink { _ in engineUpdates += 1 }
        let clockObservation = service.$displayClock.dropFirst().sink { clocks.append($0) }

        service.tick()
        fixture.now.addTimeInterval(0.5)
        service.tick()
        #expect(engineUpdates == 0)
        #expect(clocks.isEmpty)

        fixture.now.addTimeInterval(0.5)
        service.tick()
        #expect(engineUpdates == 0)
        #expect(clocks == ["00:59"])
        withExtendedLifetime((engineObservation, clockObservation)) {}
    }

    @Test
    func monitoringStartIsIdempotentAndStopReleasesPolling() {
        let fixture = Fixture()
        let service = fixture.service
        fixture.snapshot = .init(identifier: "timer", state: .paused(remaining: 30))
        service.startSystemClockMonitoring()
        service.startSystemClockMonitoring()
        #expect(fixture.reads == 1)

        service.stop()
        service.tick()
        #expect(service.phase == .idle)
        #expect(fixture.reads == 1)
        #expect(fixture.snapshot?.state == .paused(remaining: 30))

        service.startSystemClockMonitoring()
        #expect(service.phase == .paused)
        #expect(service.displayClock == "00:30")
        #expect(fixture.reads == 2)
        service.stop()
    }

    @Test(arguments: [false, true])
    func monitoringDetectsNewTimerWithoutManualRefresh(changesDuration: Bool) async {
        let fixture = Fixture()
        let service = fixture.service
        defer { service.stop() }
        service.startSystemClockMonitoring()
        #expect(service.phase == .idle)
        if changesDuration {
            service.setFocusDuration(90)
            #expect(service.displayClock == "01:30")
        }

        let nextRead = XCTestExpectation(description: "Monitoring refreshes the system timer automatically")
        fixture.onNextRead = { nextRead.fulfill() }
        fixture.snapshot = .init(identifier: "new", state: .running(deadline: fixture.now.addingTimeInterval(60)))

        let result = await XCTWaiter.fulfillment(of: [nextRead], timeout: 5)
        #expect(result == .completed)
        #expect(service.phase == .running)
        #expect(service.displayClock == "01:00")
    }

    @Test
    func focusDurationChangesStayLocalWhenSystemMonitoringIsDisabled() {
        let fixture = Fixture()
        let service = fixture.service
        defer { service.stop() }
        fixture.snapshot = .init(identifier: "system", state: .running(deadline: fixture.now.addingTimeInterval(60)))

        service.setFocusDuration(90)
        service.tick()

        #expect(service.phase == .idle)
        #expect(service.focusDuration == 90)
        #expect(service.displayClock == "01:30")
        #expect(fixture.defaults.double(forKey: "zisla.pomodoro.focusDuration") == 90)
        #expect(fixture.reads == 0)
        #expect(fixture.notifications.isEmpty)
    }

    @Test
    func synchronizationPreservesSavedPomodoroDurations() {
        let fixture = Fixture()
        let service = fixture.service
        defer { service.stop() }
        service.setFocusDuration(1_800)
        service.setRestDuration(600)
        fixture.snapshot = .init(identifier: "timer", state: .running(deadline: fixture.now.addingTimeInterval(10)))
        service.startSystemClockMonitoring()
        fixture.snapshot = nil
        service.tick()

        #expect(service.focusDuration == 1_800)
        #expect(service.restDuration == 600)
        #expect(fixture.defaults.double(forKey: "zisla.pomodoro.focusDuration") == 1_800)
        #expect(fixture.defaults.double(forKey: "zisla.pomodoro.restDuration") == 600)
    }

    @MainActor
    private final class Fixture {
        let suiteName = "SystemClockSynchronizationTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var now = Date(timeIntervalSince1970: 1_000_000)
        var snapshot: SystemClockTimerSnapshot?
        var notifications: [UNNotificationRequest] = []
        var reads = 0
        var onNextRead: (() -> Void)?

        lazy var service = PomodoroService(
            notificationRequestHandler: { [unowned self] in notifications.append($0) },
            defaults: defaults,
            systemClockTimerReader: { [unowned self] in
                reads += 1
                let handler = onNextRead
                onNextRead = nil
                handler?()
                return snapshot
            },
            now: { [unowned self] in now }
        )

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
        }

        isolated deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
