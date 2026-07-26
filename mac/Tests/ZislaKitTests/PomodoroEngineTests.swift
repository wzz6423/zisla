import Foundation
import IOKit.pwr_mgt
import Testing
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
}

@MainActor
struct PowerAssertionControllerTests {
    private static let displayType = kIOPMAssertPreventUserIdleDisplaySleep as String
    private static let idleSystemType = kIOPMAssertPreventUserIdleSystemSleep as String

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
