import AVFoundation
import Combine
import Foundation
import IOKit.pwr_mgt
import Testing
import UserNotifications
@testable import ZislaKit

struct PomodoroEngineTests {
    @Test
    func startTransitionsIdleToRunningWithDeadline() {
        var engine = PomodoroEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)

        engine.start(at: now)

        #expect(engine.phase == .running)
        #expect(engine.mode == .focus)
        #expect(engine.deadline == now.addingTimeInterval(25 * 60))
        #expect(abs(engine.remaining(at: now) - 25 * 60) < 0.001)
    }

    @Test
    func pauseDoesNotAdvanceRemaining() {
        var engine = PomodoroEngine()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        engine.start(at: t0)

        let t1 = t0.addingTimeInterval(90)
        engine.pause(at: t1)
        let remainingAtPause = engine.remaining(at: t1)

        let t2 = t1.addingTimeInterval(120)
        #expect(engine.phase == .paused)
        #expect(abs(engine.remaining(at: t2) - remainingAtPause) < 0.001)
        #expect(abs(remainingAtPause - (25 * 60 - 90)) < 0.001)
    }

    @Test
    func completionSwitchesToNextModeIdle() {
        var engine = PomodoroEngine()
        let now = Date(timeIntervalSince1970: 3_000_000)
        engine.startWithRemaining(1, at: now)

        let completed = engine.completeIfNeeded(at: now.addingTimeInterval(1.1))
        #expect(completed)
        #expect(engine.mode == .rest)
        #expect(engine.phase == .idle)
        #expect(abs(engine.remaining(at: now) - 5 * 60) < 0.001)

        engine.startWithRemaining(0.5, at: now)
        let completedRest = engine.completeIfNeeded(at: now.addingTimeInterval(1))
        #expect(completedRest)
        #expect(engine.mode == .focus)
        #expect(engine.phase == .idle)
    }

    @Test
    func resetKeepsModeAndRestoresDuration() {
        var engine = PomodoroEngine(mode: .rest, phase: .paused, remainingWhenPaused: 12)
        engine.reset()
        #expect(engine.phase == .idle)
        #expect(engine.mode == .rest)
        #expect(engine.remaining() == 5 * 60)
    }

    @Test
    func formatMMSSUsesMinutesAndSecondsBelowOneHour() {
        var engine = PomodoroEngine()
        let now = Date(timeIntervalSince1970: 4_000_000)
        engine.startWithRemaining(61.2, at: now)
        #expect(PomodoroEngine.formatMMSS(at: now, engine: engine).count == 5)
    }

    @Test
    func formatMMSSIncludesAllComponentsForCustomLongDuration() {
        let engine = PomodoroEngine(focusDuration: 3_723)
        let now = Date(timeIntervalSince1970: 5_000_000)

        #expect(PomodoroEngine.formatMMSS(at: now, engine: engine) == "01:02:03")
    }

    @Test
    func formatHHMMSSIncludesZeroHourComponent() {
        let engine = PomodoroEngine(focusDuration: 29 * 60 + 28)
        let now = Date(timeIntervalSince1970: 6_000_000)

        #expect(PomodoroEngine.formatHHMMSS(at: now, engine: engine) == "00:29:28")
    }

    @Test
    func formatHHMMSSKeepsHoursForLongDurations() {
        let engine = PomodoroEngine(focusDuration: 3_723)
        let now = Date(timeIntervalSince1970: 7_000_000)
        #expect(PomodoroEngine.formatHHMMSS(at: now, engine: engine) == "01:02:03")
    }

    @Test
    func formatHHMMSSReflectsPausedRemaining() {
        var engine = PomodoroEngine()
        let t0 = Date(timeIntervalSince1970: 8_000_000)
        engine.startWithRemaining(90, at: t0)
        engine.pause(at: t0.addingTimeInterval(30))
        let later = t0.addingTimeInterval(300)
        #expect(PomodoroEngine.formatHHMMSS(at: later, engine: engine) == "00:01:00")
    }

    @Test
    func formatMMSSUnchangedBelowOneHourWhenHHMMSSPadsHours() {
        var engine = PomodoroEngine()
        let now = Date(timeIntervalSince1970: 9_000_000)
        engine.startWithRemaining(29 * 60 + 28, at: now)
        #expect(PomodoroEngine.formatMMSS(at: now, engine: engine) == "29:28")
        #expect(PomodoroEngine.formatHHMMSS(at: now, engine: engine) == "00:29:28")
    }

    @Test
    func invalidAndOversizedDurationsAreNormalizedBeforeFormatting() {
        let invalid = PomodoroEngine(focusDuration: .nan, restDuration: -Double.infinity)
        #expect(invalid.focusDuration == PomodoroMode.focus.duration)
        #expect(invalid.restDuration == PomodoroMode.rest.duration)

        let oversized = PomodoroEngine(focusDuration: .greatestFiniteMagnitude)
        #expect(oversized.focusDuration == PomodoroEngine.maximumDuration)
        #expect(!PomodoroEngine.formatMMSS(engine: oversized).isEmpty)
    }
}

@MainActor
struct PomodoroServiceTests {
    @Test
    func restartedFocusSessionUsesNewCountdownPresentationIDs() {
        let suiteName = "PomodoroServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = PomodoroService(
            notificationRequestHandler: { _ in },
            defaults: defaults
        )

        service.start()
        let firstLeftID = service.focusCountdownNoticeID(for: .left)
        let firstRightID = service.focusCountdownNoticeID(for: .right)

        service.start()
        #expect(service.focusCountdownNoticeID(for: .left) == firstLeftID)
        #expect(service.focusCountdownNoticeID(for: .right) == firstRightID)

        service.reset()
        service.start()
        let secondLeftID = service.focusCountdownNoticeID(for: .left)
        let secondRightID = service.focusCountdownNoticeID(for: .right)

        #expect(firstLeftID.hasPrefix(PomodoroService.focusCountdownNoticeIDPrefix))
        #expect(firstRightID.hasPrefix(PomodoroService.focusCountdownNoticeIDPrefix))
        #expect(firstLeftID != secondLeftID)
        #expect(firstRightID != secondRightID)
    }

    @Test
    func bundledCompletionMelodyLastsFiveToSixSeconds() throws {
        let url = try #require(PomodoroCompletionSound.resourceURL())
        let player = try AVAudioPlayer(contentsOf: url)

        #expect(player.numberOfChannels == 2)
        #expect((5...6).contains(player.duration))
    }

    @Test
    func completionSoundsOnceForEachModeWithoutASecondNotificationSound() {
        let suiteName = "PomodoroServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var now = Date(timeIntervalSince1970: 10_000_000)
        var sounds = 0
        var requests: [UNNotificationRequest] = []
        let service = PomodoroService(
            notificationRequestHandler: { requests.append($0) },
            defaults: defaults,
            completionSoundHandler: { sounds += 1 },
            now: { now }
        )
        service.setFocusDuration(1)
        service.setRestDuration(1)
        service.start()

        now = now.addingTimeInterval(1)
        service.tick()

        #expect(service.phase == .idle)
        #expect(service.mode == .rest)
        #expect(requests.count == 1)
        #expect(requests[0].content.sound == nil)
        #expect(sounds == 1)

        service.tick()
        #expect(sounds == 1)
        #expect(requests.count == 1)

        service.start()
        now = now.addingTimeInterval(1)
        service.tick()
        #expect(service.mode == .focus)
        #expect(sounds == 2)
        #expect(requests.count == 2)
    }

    @Test
    func mutedCompletionDoesNotSoundOrSendANotification() {
        let suiteName = "PomodoroServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var now = Date(timeIntervalSince1970: 10_000_000)
        var sounds = 0
        var notifications = 0
        let service = PomodoroService(
            notificationRequestHandler: { _ in notifications += 1 },
            defaults: defaults,
            completionSoundHandler: { sounds += 1 },
            now: { now }
        )
        service.notificationsMuted = true
        service.setFocusDuration(1)
        service.start()

        now = now.addingTimeInterval(1)
        service.tick()

        #expect(service.phase == .idle)
        #expect(sounds == 0)
        #expect(notifications == 0)
    }

    @Test
    func pauseResetAndStopDoNotSound() {
        let suiteName = "PomodoroServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var now = Date(timeIntervalSince1970: 10_000_000)
        var sounds = 0
        let service = PomodoroService(
            notificationRequestHandler: { _ in },
            defaults: defaults,
            completionSoundHandler: { sounds += 1 },
            now: { now }
        )
        service.setFocusDuration(1)

        service.start()
        service.pause()
        now = now.addingTimeInterval(2)
        service.tick()
        #expect(sounds == 0)

        service.start()
        service.reset()
        service.tick()
        #expect(sounds == 0)

        service.start()
        service.stop()
        service.tick()
        #expect(sounds == 0)
    }

    @Test
    func refreshDisplayPublishesOnlyWhenClockTextChanges() {
        let suiteName = "PomodoroServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = PomodoroService(defaults: defaults)
        var clocks: [String] = []
        let observation = service.$displayClock
            .dropFirst()
            .sink { clocks.append($0) }

        service.refreshDisplay()
        #expect(clocks.isEmpty)

        service.setFocusDuration(26 * 60)
        #expect(clocks == ["26:00"])
        withExtendedLifetime(observation) {}
    }

    @Test
    func corruptedStoredDurationsFallBackToDefaultsAndStaySafe() {
        let suiteName = "PomodoroServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(-1.0, forKey: "zisla.pomodoro.focusDuration")
        defaults.set(Double.nan, forKey: "zisla.pomodoro.restDuration")

        let service = PomodoroService(defaults: defaults)

        #expect(service.focusDuration == PomodoroMode.focus.duration)
        #expect(service.restDuration == PomodoroMode.rest.duration)
        #expect(service.displayClock == "25:00")
        #expect(defaults.double(forKey: "zisla.pomodoro.focusDuration") == PomodoroMode.focus.duration)
        #expect(defaults.double(forKey: "zisla.pomodoro.restDuration") == PomodoroMode.rest.duration)

        service.setFocusDuration(.greatestFiniteMagnitude)
        #expect(service.focusDuration == PomodoroEngine.maximumDuration)
        #expect(!service.displayClock.isEmpty)
    }
}

@MainActor
struct PowerAssertionControllerTests {
    private static let displayType = kIOPMAssertPreventUserIdleDisplaySleep as String
    private static let idleSystemType = kIOPMAssertPreventUserIdleSystemSleep as String

    @Test
    func manualKeepAwakePreventsLidSleepAndRestoresItWhenDisabled() async {
        let manager = FakePowerAssertionManager()
        let session = FakeLidClosedDisplaySession()
        let controller = makeController(manager: manager, session: session)

        await controller.setKeepDisplayAwakeIncludingLidClose(true)

        #expect(session.isActive, "Manual keep-awake must also disable lid-close sleep")
        #expect(controller.keepDisplayAwake)
        #expect(manager.activeIDs.count == 1)
        #expect(!controller.preventIdleSystemSleep)

        await controller.setKeepDisplayAwakeIncludingLidClose(false)

        #expect(!session.isActive)
        #expect(!controller.keepDisplayAwake)
        #expect(manager.activeIDs.isEmpty)
        #expect(controller.displayAwakeError == nil)
    }

    @Test(arguments: [false, true])
    func deniedAuthorizationPreservesEarlierDisplayState(wasAwake: Bool) async {
        let manager = FakePowerAssertionManager()
        let session = FakeLidClosedDisplaySession()
        session.failStart = true
        let controller = makeController(manager: manager, session: session)
        controller.setKeepDisplayAwake(wasAwake)

        await controller.setKeepDisplayAwakeIncludingLidClose(true)

        #expect(!session.isActive)
        #expect(controller.keepDisplayAwake == wasAwake)
        #expect(manager.activeIDs.count == (wasAwake ? 1 : 0))
        #expect(controller.displayAwakeError != nil)
        #expect(!controller.isChangingDisplayAwake)
    }

    @Test
    func failedDisplayAssertionDoesNotChangeLidSleepPolicy() async {
        let manager = FakePowerAssertionManager()
        manager.failingTypes = [Self.displayType]
        let session = FakeLidClosedDisplaySession()
        let controller = makeController(manager: manager, session: session)

        await controller.setKeepDisplayAwakeIncludingLidClose(true)

        #expect(!session.isActive)
        #expect(!controller.keepDisplayAwake)
        #expect(controller.displayAwakeError != nil)
    }

    @Test
    func repeatedEnableOwnsOnlyOneSleepSession() async {
        let session = FakeLidClosedDisplaySession()
        let manager = FakePowerAssertionManager()
        let controller = makeController(manager: manager, session: session)

        await controller.setKeepDisplayAwakeIncludingLidClose(true)
        await controller.setKeepDisplayAwakeIncludingLidClose(true)

        #expect(session.starts == 1)
        #expect(manager.activeIDs.count == 1)
        controller.releaseAll()
        #expect(!session.isActive)
        #expect(manager.activeIDs.isEmpty)
    }

    @Test
    func failedRestoreKeepsToggleOnAndCanBeRetried() async {
        let session = FakeLidClosedDisplaySession()
        let controller = makeController(manager: FakePowerAssertionManager(), session: session)
        await controller.setKeepDisplayAwakeIncludingLidClose(true)
        session.failStop = true

        await controller.setKeepDisplayAwakeIncludingLidClose(false)

        #expect(session.isActive)
        #expect(controller.keepDisplayAwake)
        #expect(controller.displayAwakeError != nil)
        session.failStop = false

        await controller.setKeepDisplayAwakeIncludingLidClose(false)

        #expect(!session.isActive)
        #expect(!controller.keepDisplayAwake)
        #expect(controller.displayAwakeError == nil)
    }

    @Test
    func teardownClosesLidSleepSession() async {
        let manager = FakePowerAssertionManager()
        let session = FakeLidClosedDisplaySession()
        var controller: PowerAssertionController? = makeController(manager: manager, session: session)
        await controller?.setKeepDisplayAwakeIncludingLidClose(true)

        controller = nil

        #expect(!session.isActive)
        #expect(manager.activeIDs.isEmpty)
    }

    @Test(arguments: [false, true])
    func releaseAllDuringAuthorizationRejectsLateResultsAndDuplicateRequests(failStart: Bool) async {
        let manager = FakePowerAssertionManager()
        let session = FakeLidClosedDisplaySession()
        let gate = DisplayAuthorizationGate()
        let controller = PowerAssertionController(manager: manager, startLidClosedSession: {
            await gate.wait()
            try session.start()
            return session
        })
        let pending = Task { await controller.setKeepDisplayAwakeIncludingLidClose(true) }
        for await _ in gate.started.stream { break }
        #expect(controller.isChangingDisplayAwake)
        await controller.setKeepDisplayAwakeIncludingLidClose(true)
        controller.releaseAll()
        session.failStart = failStart
        gate.resume()
        await pending.value

        #expect(!session.isActive)
        #expect(!controller.keepDisplayAwake)
        #expect(manager.activeIDs.isEmpty)
        #expect(!controller.isChangingDisplayAwake)
        #expect(controller.displayAwakeError == nil)
    }

    @Test(arguments: [false, true])
    func lateRestoreCannotOverwriteANewerAutomaticDisplayRequest(failStop: Bool) async {
        let manager = FakePowerAssertionManager()
        let session = FakeLidClosedDisplaySession()
        let controller = makeController(manager: manager, session: session)
        await controller.setKeepDisplayAwakeIncludingLidClose(true)
        let started = AsyncStream<Void>.makeStream()
        let resume = DispatchSemaphore(value: 0)
        session.beforeStop = {
            started.continuation.yield(())
            started.continuation.finish()
            resume.wait()
        }
        session.failStop = failStop
        let pending = Task { await controller.setKeepDisplayAwakeIncludingLidClose(false) }
        for await _ in started.stream { break }
        controller.releaseAll()
        controller.setKeepDisplayAwake(true)
        resume.signal()
        await pending.value

        #expect(controller.keepDisplayAwake)
        #expect(manager.activeIDs.count == 1)
        #expect(controller.displayAwakeError == nil)
        #expect(!controller.isChangingDisplayAwake)
    }

    @Test
    func automaticDisableCancelsTheManualLidOverride() async {
        let manager = FakePowerAssertionManager()
        let session = FakeLidClosedDisplaySession()
        let controller = makeController(manager: manager, session: session)
        await controller.setKeepDisplayAwakeIncludingLidClose(true)

        controller.setKeepDisplayAwake(false)

        #expect(!session.isActive)
        #expect(!controller.keepDisplayAwake)
        #expect(manager.activeIDs.isEmpty)
    }

    @Test
    func manualDisableAlsoReleasesAnAutomaticDisplayAssertion() async {
        let manager = FakePowerAssertionManager()
        let controller = makeController(manager: manager, session: FakeLidClosedDisplaySession())
        controller.setKeepDisplayAwake(true)

        await controller.setKeepDisplayAwakeIncludingLidClose(false)

        #expect(!controller.keepDisplayAwake)
        #expect(manager.activeIDs.isEmpty)
    }

    @Test
    func automaticDisplayRequestsDoNotRequestLidSleepAuthorization() {
        let manager = FakePowerAssertionManager()
        let session = FakeLidClosedDisplaySession()
        let controller = makeController(manager: manager, session: session)
        controller.setKeepDisplayAwake(true)
        controller.setPreventIdleSystemSleep(true)
        controller.setAIActivityActive(true)

        #expect(controller.keepDisplayAwake)
        #expect(!session.isActive)
        #expect(session.starts == 0)
        controller.releaseAll()
        #expect(manager.activeIDs.isEmpty)
    }

    private func makeController(
        manager: FakePowerAssertionManager,
        session: FakeLidClosedDisplaySession
    ) -> PowerAssertionController {
        PowerAssertionController(manager: manager, startLidClosedSession: {
            try session.start()
            return session
        })
    }

    @Test
    func lifecycleCreatesAndReleasesAssertions() {
        let manager = FakePowerAssertionManager()
        let controller = PowerAssertionController(manager: manager)

        controller.setKeepDisplayAwake(true)
        #expect(controller.keepDisplayAwake)
        #expect(manager.createCallCount == 1)
        #expect(manager.activeIDs.count == 1)

        controller.setPreventIdleSystemSleep(true)
        #expect(controller.preventIdleSystemSleep)
        #expect(manager.createCallCount == 2)
        #expect(manager.activeIDs.count == 2)
        #expect(manager.createdTypes == [Self.displayType, Self.idleSystemType])
        #expect(manager.createdLevels == [
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
        ])

        controller.releaseAll()
        #expect(controller.keepDisplayAwake == false)
        #expect(controller.preventIdleSystemSleep == false)
        #expect(manager.activeIDs.isEmpty)
        #expect(manager.releaseCallCount == 2)
    }

    @Test
    func disablingToggleReleasesMatchingAssertion() {
        let manager = FakePowerAssertionManager()
        let controller = PowerAssertionController(manager: manager)

        controller.setKeepDisplayAwake(true)
        controller.setKeepDisplayAwake(false)
        #expect(controller.keepDisplayAwake == false)
        #expect(manager.activeIDs.isEmpty)
    }

    @Test
    func activeAIKeepsDisplayAwakeWhenIdleSystemSleepPreventionIsEnabled() {
        let manager = FakePowerAssertionManager()
        let controller = PowerAssertionController(manager: manager)

        controller.setAIActivityActive(true)
        #expect(manager.createCallCount == 0)

        controller.setPreventIdleSystemSleep(true)
        #expect(controller.preventIdleSystemSleep)
        #expect(manager.createCallCount == 2)
        #expect(manager.activeIDs.count == 2)
        #expect(manager.createdTypes == [Self.idleSystemType, Self.displayType])

        controller.setAIActivityActive(false)
        #expect(manager.activeIDs.count == 1)
        #expect(manager.releaseCallCount == 1)

        controller.setPreventIdleSystemSleep(false)
        #expect(manager.activeIDs.isEmpty)
        #expect(manager.releaseCallCount == 2)
    }

    @Test
    func endingAIActivityDoesNotReleaseManualDisplayAssertion() {
        let manager = FakePowerAssertionManager()
        let controller = PowerAssertionController(manager: manager)

        controller.setKeepDisplayAwake(true)
        controller.setPreventIdleSystemSleep(true)
        controller.setAIActivityActive(true)
        #expect(manager.activeIDs.count == 3)

        controller.setAIActivityActive(false)
        #expect(controller.keepDisplayAwake)
        #expect(manager.activeIDs.count == 2)

        controller.setPreventIdleSystemSleep(false)
        #expect(controller.keepDisplayAwake)
        #expect(manager.activeIDs.count == 1)
        controller.setKeepDisplayAwake(false)
        #expect(manager.activeIDs.isEmpty)
    }

    @Test
    func failedCreateDoesNotEnableToggleOrRetainAnAssertionID() {
        let manager = FakePowerAssertionManager()
        manager.failingTypes = [Self.displayType, Self.idleSystemType]
        let controller = PowerAssertionController(manager: manager)

        controller.setKeepDisplayAwake(true)
        controller.setPreventIdleSystemSleep(true)

        #expect(controller.keepDisplayAwake == false)
        #expect(controller.preventIdleSystemSleep == false)
        #expect(manager.releaseCallCount == 0)
        #expect(manager.activeIDs.isEmpty)
    }
}

@MainActor
private final class DisplayAuthorizationGate {
    let started = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { pending in
            continuation = pending
            started.continuation.yield(())
            started.continuation.finish()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private final class FakeLidClosedDisplaySession: LidClosedDisplaySession, @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    private var startCount = 0
    var failStart = false
    var failStop = false
    var beforeStop: (@Sendable () -> Void)?

    var isActive: Bool { lock.withLock { active } }
    var starts: Int { lock.withLock { startCount } }

    func start() throws {
        try lock.withLock {
            if failStart { throw CocoaError(.userCancelled) }
            startCount += 1
            active = true
        }
    }

    func stop() throws {
        beforeStop?()
        try lock.withLock {
            if failStop { throw CocoaError(.fileWriteUnknown) }
            active = false
        }
    }

    func cancel() {
        lock.withLock { active = false }
    }
}

@MainActor
private final class FakePowerAssertionManager: PowerAssertionManaging {
    private(set) var createCallCount = 0
    private(set) var releaseCallCount = 0
    private(set) var activeIDs: Set<IOPMAssertionID> = []
    private(set) var createdTypes: [String] = []
    private(set) var createdLevels: [IOPMAssertionLevel] = []
    var failingTypes: Set<String> = []
    private var nextID: IOPMAssertionID = 100

    func create(
        type: CFString,
        name: CFString,
        level: IOPMAssertionLevel,
        assertionID: inout IOPMAssertionID
    ) -> IOReturn {
        createCallCount += 1
        guard !failingTypes.contains(type as String) else {
            return kIOReturnNotPermitted
        }
        createdTypes.append(type as String)
        createdLevels.append(level)
        nextID += 1
        assertionID = nextID
        activeIDs.insert(nextID)
        return kIOReturnSuccess
    }

    func release(assertionID: IOPMAssertionID) -> IOReturn {
        releaseCallCount += 1
        activeIDs.remove(assertionID)
        return kIOReturnSuccess
    }
}
