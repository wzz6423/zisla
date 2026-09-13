import Foundation
import Testing

@testable import ZislaKit

struct SystemClockTimerStoreTests {
    @Test
    func runningTimerUsesAbsoluteSystemDeadline() {
        let deadline = Date(timeIntervalSince1970: 1_000_060)
        let value = store([timer("running", state: 3, fireTime: datePayload(deadline))])

        #expect(SystemClockTimerStore.snapshot(from: value) == SystemClockTimerSnapshot(
            identifier: "running", state: .running(deadline: deadline)
        ))
    }

    @Test
    func pausedTimerUsesRemainingIntervalInsteadOfOriginalDuration() {
        let value = store([timer("paused", state: 2, fireTime: intervalPayload(42.5))])

        #expect(SystemClockTimerStore.snapshot(from: value) == SystemClockTimerSnapshot(
            identifier: "paused", state: .paused(remaining: 42.5)
        ))
    }

    @Test(arguments: [-1, 0, 1, 4, 99])
    func stoppedPresetsAndUnknownStatesAreNotCountdowns(state: Int) {
        #expect(SystemClockTimerStore.snapshot(from: store([
            timer("preset", state: state, fireTime: intervalPayload(300)),
        ])) == nil)
    }

    @Test
    func earliestRunningTimerTakesPriorityOverPausedTimers() {
        let early = Date(timeIntervalSinceReferenceDate: 100)
        let late = early.addingTimeInterval(60)
        let records = [
            timer("a-later", state: 3, fireTime: datePayload(late)),
            timer("paused", state: 2, fireTime: intervalPayload(1)),
            timer("z-earlier", state: 3, fireTime: datePayload(early)),
        ]

        #expect(SystemClockTimerStore.snapshot(from: store(records))?.identifier == "z-earlier")
        #expect(SystemClockTimerStore.snapshot(from: store(records.reversed()))?.identifier == "z-earlier")
    }

    @Test
    func pausedSelectionAndEqualDeadlineTiesAreStable() {
        let paused = [
            timer("a-long", state: 2, fireTime: intervalPayload(20)),
            timer("z", state: 2, fireTime: intervalPayload(10)),
            timer("y", state: 2, fireTime: intervalPayload(10)),
        ]
        #expect(SystemClockTimerStore.snapshot(from: store(paused))?.identifier == "y")
        #expect(SystemClockTimerStore.snapshot(from: store(paused.reversed()))?.identifier == "y")

        let deadline = Date(timeIntervalSince1970: 200)
        let running = [
            timer("b", state: 3, fireTime: datePayload(deadline)),
            timer("a", state: 3, fireTime: datePayload(deadline)),
        ]
        #expect(SystemClockTimerStore.snapshot(from: store(running))?.identifier == "a")
        #expect(SystemClockTimerStore.snapshot(from: store(running.reversed()))?.identifier == "a")
    }

    @Test
    func malformedRecordsDoNotHideAnotherValidTimer() {
        let invalid: [Any] = [
            NSNull(), "invalid", [:], ["$MTTimer": "invalid"],
            timer("", state: 2, fireTime: intervalPayload(30)),
            timer("missing", state: 3, fireTime: [:]),
            timer("wrong-type", state: 3, fireTime: intervalPayload(30)),
            timer("wrong-type", state: 2, fireTime: datePayload(Date())),
            timer("negative", state: 2, fireTime: intervalPayload(-1)),
            timer("zero", state: 2, fireTime: intervalPayload(0)),
            timer("nan", state: 2, fireTime: intervalPayload(.nan)),
            timer("infinite", state: 2, fireTime: intervalPayload(.infinity)),
            timer("invalid-date", state: 3, fireTime: datePayload(Date(timeIntervalSince1970: .nan))),
            timer("fractional-state", state: 2.5, fireTime: intervalPayload(30)),
        ]
        let valid = timer("valid", state: 2, fireTime: intervalPayload(7))

        for record in invalid {
            #expect(SystemClockTimerStore.snapshot(from: store([record])) == nil)
            #expect(SystemClockTimerStore.snapshot(from: store([record, valid]))?.identifier == "valid")
        }
    }

    @Test
    func missingAndMalformedStoresAreEmpty() {
        let values: [Any?] = [nil, NSNull(), "invalid", [:], ["MTTimers": "invalid"], store([])]
        for value in values {
            #expect(SystemClockTimerStore.snapshot(from: value) == nil)
        }
    }

    @Test
    func expiredDeadlineIsRetainedUntilSystemStopsTimer() {
        let deadline = Date(timeIntervalSince1970: 1)
        #expect(SystemClockTimerStore.snapshot(from: store([
            timer("expired", state: 3, fireTime: datePayload(deadline)),
        ]))?.state == .running(deadline: deadline))
    }

    @Test
    func boundedMalformedInputFuzzNeverProducesInvalidTime() {
        var seed: UInt64 = 0x5A15_A71E
        let payloads: [Any] = [
            NSNull(), "invalid", [:], intervalPayload(-1), intervalPayload(0),
            intervalPayload(.nan), intervalPayload(.infinity), intervalPayload(42),
            datePayload(Date(timeIntervalSince1970: .infinity)),
            datePayload(Date(timeIntervalSince1970: 500)),
        ]
        for _ in 0..<512 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let state = Int((seed >> 32) % 6)
            let payload = payloads[Int(seed % UInt64(payloads.count))]
            let value = store([timer("fuzz", state: state, fireTime: payload)])
            guard let snapshot = SystemClockTimerStore.snapshot(from: value) else { continue }
            #expect(!snapshot.identifier.isEmpty)
            switch snapshot.state {
            case .running(let deadline):
                #expect(state == 3)
                #expect(deadline.timeIntervalSinceReferenceDate.isFinite)
            case .paused(let remaining):
                #expect(state == 2)
                #expect(remaining.isFinite && remaining > 0)
            }
        }
    }

    private func store(_ timers: some Sequence<Any>) -> [String: Any] {
        ["MTTimers": Array(timers)]
    }

    private func timer(_ id: String, state: Any, fireTime: Any) -> [String: Any] {
        ["$MTTimer": [
            "MTTimerID": id,
            "MTTimerState": state,
            "MTTimerDuration": 1_500.0,
            "MTTimerFireTime": fireTime,
        ]]
    }

    private func datePayload(_ date: Date) -> [String: Any] {
        ["$MTTimerDate": ["MTTimerTimeDate": date]]
    }

    private func intervalPayload(_ remaining: TimeInterval) -> [String: Any] {
        ["$MTTimerTimeInterval": ["MTTimerTimeInterval": remaining]]
    }
}
