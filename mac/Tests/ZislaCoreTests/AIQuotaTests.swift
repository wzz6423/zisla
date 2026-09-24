import Foundation
import Testing

@testable import ZislaCore

struct AIQuotaTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func eachAccountWindowHasAnIndependentThresholdBaseline() {
        var tracker = AIQuotaThresholdTracker()
        let initial = snapshot([
            account("a", windows: [window("five-hour", remaining: 91), window("weekly", remaining: 70)]),
            account("b", windows: [window("weekly", remaining: 65)]),
        ])
        #expect(tracker.consume(initial, at: now).isEmpty)

        let next = snapshot([
            account("a", windows: [window("five-hour", remaining: 79), window("weekly", remaining: 59)]),
            account("b", windows: [window("weekly", remaining: 39)]),
        ])
        let alerts = tracker.consume(next, at: now.addingTimeInterval(30))
        #expect(Set(alerts.map { "\($0.accountID)/\($0.windowID)/\($0.threshold)" }) == [
            "a/five-hour/80", "a/weekly/60", "b/weekly/40",
        ])
    }

    @Test
    func crossingSeveralLevelsEmitsOnlyTheLowestAndDoesNotRepeat() {
        var tracker = AIQuotaThresholdTracker()
        #expect(tracker.consume(snapshot([account("a", windows: [window("weekly", remaining: 91)])]), at: now).isEmpty)
        let low = snapshot([account("a", windows: [window("weekly", remaining: 4)])])
        #expect(tracker.consume(low, at: now.addingTimeInterval(10)).map(\.threshold) == [5])
        #expect(tracker.consume(low, at: now.addingTimeInterval(20)).isEmpty)
        let empty = snapshot([account("a", windows: [window("weekly", remaining: 0)])])
        #expect(tracker.consume(empty, at: now.addingTimeInterval(30)).map(\.threshold) == [0])
    }

    @Test
    func staleAndResetReadingsRebaselineWithoutBackfilledAlerts() {
        var tracker = AIQuotaThresholdTracker(maximumReadingAge: 120)
        let first = snapshot([account("a", windows: [window("weekly", remaining: 90)])])
        #expect(tracker.consume(first, at: now).isEmpty)

        let stale = snapshot([account("a", windows: [window("weekly", remaining: 40)], observedAt: now)])
        #expect(tracker.consume(stale, at: now.addingTimeInterval(300)).isEmpty)
        let fresh = snapshot([account("a", windows: [window("weekly", remaining: 30)], observedAt: now.addingTimeInterval(310))])
        #expect(tracker.consume(fresh, at: now.addingTimeInterval(310)).isEmpty)

        let reset = snapshot([account("a", windows: [window("weekly", remaining: 95, resetsAt: now.addingTimeInterval(604_800))], observedAt: now.addingTimeInterval(320))])
        #expect(tracker.consume(reset, at: now.addingTimeInterval(320)).isEmpty)
        let next = snapshot([account("a", windows: [window("weekly", remaining: 79, resetsAt: now.addingTimeInterval(604_800))], observedAt: now.addingTimeInterval(330))])
        #expect(tracker.consume(next, at: now.addingTimeInterval(330)).map(\.threshold) == [80])
    }

    @Test
    func moneyBalanceAndInvalidPercentNeverAlert() {
        var tracker = AIQuotaThresholdTracker()
        let initial = snapshot([account("a", balance: "$10", windows: [window("balance", remaining: nil), window("bad", remaining: .nan)])])
        #expect(tracker.consume(initial, at: now).isEmpty)
        let updated = snapshot([account("a", balance: "$2", windows: [window("balance", remaining: nil), window("bad", remaining: -.infinity)])])
        #expect(tracker.consume(updated, at: now.addingTimeInterval(30)).isEmpty)
    }

    @Test
    func allSevenLevelsFireOnceAndNoiseCannotRearmTheSameCycle() {
        var tracker = AIQuotaThresholdTracker()
        let reset = now.addingTimeInterval(3_600)
        _ = tracker.consume(snapshot([account("a", windows: [window("w", remaining: 100, resetsAt: reset)])]), at: now)
        var observed: [Int] = []
        for level in AIQuotaThresholdTracker.levels {
            let value = snapshot([account("a", windows: [window("w", remaining: Double(level), resetsAt: reset)])])
            observed += tracker.consume(value, at: now).map(\.threshold)
            let bounce = snapshot([account("a", windows: [window("w", remaining: Double(level + 1), resetsAt: reset)])])
            #expect(tracker.consume(bounce, at: now).isEmpty)
            #expect(tracker.consume(value, at: now).isEmpty)
        }
        #expect(observed == [80, 60, 40, 20, 10, 5, 0])
    }

    @Test
    func expiredWindowsAndFreshReadingsAfterLongSleepDoNotBackfillAlerts() {
        var tracker = AIQuotaThresholdTracker(maximumReadingAge: 120)
        _ = tracker.consume(snapshot([account("a", windows: [window("w", remaining: 100)])]), at: now)
        let afterSleep = now.addingTimeInterval(86_400)
        #expect(tracker.consume(snapshot([account("a", windows: [window("w", remaining: 20)], observedAt: afterSleep)]), at: afterSleep).isEmpty)
        let expired = window("w", remaining: 0, resetsAt: afterSleep)
        #expect(tracker.consume(snapshot([account("a", windows: [expired], observedAt: afterSleep)]), at: afterSleep).isEmpty)
        let restarted = window("w", remaining: 90, resetsAt: afterSleep.addingTimeInterval(3_600))
        #expect(tracker.consume(snapshot([account("a", windows: [restarted], observedAt: afterSleep)]), at: afterSleep).isEmpty)
    }

    @Test
    func delimiterCharactersCannotMergeAccountAndWindowIdentity() {
        var tracker = AIQuotaThresholdTracker()
        let values = snapshot([
            account("a#b", windows: [window("c", remaining: 95)]),
            account("a", windows: [window("b#c", remaining: 25)]),
        ])
        #expect(tracker.consume(values, at: now).isEmpty)
        let next = snapshot([
            account("a#b", windows: [window("c", remaining: 79)]),
            account("a", windows: [window("b#c", remaining: 19)]),
        ])
        #expect(tracker.consume(next, at: now).map(\.threshold) == [80, 20])
    }

    @Test
    func olderAndFutureObservationsCannotMoveTheBaseline() {
        var tracker = AIQuotaThresholdTracker()
        _ = tracker.consume(snapshot([account("a", windows: [window("w", remaining: 90)])]), at: now)
        let old = snapshot([account("a", windows: [window("w", remaining: 5)], observedAt: now.addingTimeInterval(-1))])
        #expect(tracker.consume(old, at: now).isEmpty)
        let next = snapshot([account("a", windows: [window("w", remaining: 79)], observedAt: now)])
        #expect(tracker.consume(next, at: now).map(\.threshold) == [80])
        let future = snapshot([account("a", windows: [window("w", remaining: 0)], observedAt: now.addingTimeInterval(60))])
        #expect(tracker.consume(future, at: now).isEmpty)
    }

    @Test
    func aFullRefillRearmsWindowsThatDoNotReportTheirResetTime() {
        var tracker = AIQuotaThresholdTracker()
        func reading(_ remaining: Double) -> AIQuotaSnapshot {
            snapshot([account("sub2api", windows: [window("subscription.daily", remaining: remaining)])])
        }
        #expect(tracker.consume(reading(100), at: now).isEmpty)
        #expect(tracker.consume(reading(79), at: now).map(\.threshold) == [80])
        #expect(tracker.consume(reading(81), at: now).isEmpty)
        #expect(tracker.consume(reading(79), at: now).isEmpty)
        #expect(tracker.consume(reading(100), at: now).isEmpty)
        #expect(tracker.consume(reading(79), at: now).map(\.threshold) == [80])
    }

    private func snapshot(_ accounts: [AIQuotaAccount]) -> AIQuotaSnapshot {
        AIQuotaSnapshot(accounts: accounts)
    }

    private func account(_ id: String, balance: String? = nil, windows: [AIQuotaWindow], observedAt: Date? = nil) -> AIQuotaAccount {
        AIQuotaAccount(id: id, providerID: "codex", label: id, balanceText: balance, windows: windows, observedAt: observedAt ?? now)
    }

    private func window(_ id: String, remaining: Double?, resetsAt: Date? = nil) -> AIQuotaWindow {
        AIQuotaWindow(id: id, label: id, remainingPercent: remaining, resetsAt: resetsAt)
    }
}
