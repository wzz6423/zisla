import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

private struct QuotaFixtureReader: AIQuotaReading {
    let providerID: String
    let result: Result<[AIQuotaAccount], QuotaFixtureError>

    func read() async throws -> [AIQuotaAccount] { try result.get() }
}

private enum QuotaFixtureError: Error { case failed }

@MainActor
struct AIQuotaMonitorTests {
    @Test
    func keepsSuccessfulAccountsWhenAnotherProviderFails() async {
        let account = AIQuotaAccount(
            id: "one", providerID: "codex", label: "Main", windows: [
                AIQuotaWindow(id: "weekly", label: "Weekly", remainingPercent: 70),
            ], observedAt: Date()
        )
        let monitor = AIQuotaMonitor(readers: [
            QuotaFixtureReader(providerID: "codex", result: .success([account])),
            QuotaFixtureReader(providerID: "antigravity", result: .failure(.failed)),
        ])

        await monitor.refresh()

        #expect(monitor.snapshot.accounts == [account])
        #expect(monitor.errors["antigravity"] != nil)
        #expect(!monitor.isRefreshing)
    }

    @Test
    func refreshNeverRunsMoreThanFourProvidersAtOnce() async {
        let gate = AIQuotaReaderGate()
        let readers = (0..<5).map { index in
            AIQuotaControlledReader(id: "\(index)") { await gate.read("\(index)") }
        }
        let monitor = AIQuotaMonitor(readers: readers)
        let refresh = Task { await monitor.refresh() }
        #expect(await aiQuotaEventually { await gate.started.count == 4 })
        #expect(await gate.maximumConcurrent == 4)
        await gate.releaseAll()
        #expect(await aiQuotaEventually { await gate.started.count == 5 })
        await gate.releaseAll()
        await refresh.value
        #expect(monitor.snapshot.accounts.count == 5)
        #expect(await gate.maximumConcurrent == 4)
        #expect(!monitor.isRefreshing)
    }

    @Test
    func anOldRefreshCannotOverwriteANewConfiguration() async {
        let gate = AIQuotaReaderGate()
        let monitor = AIQuotaMonitor(readers: [AIQuotaControlledReader(id: "old") { await gate.read("old") }])
        let oldRefresh = Task { await monitor.refresh() }
        #expect(await aiQuotaEventually { await gate.started == ["old"] })
        let newAccount = AIQuotaAccount(id: "new", providerID: "codex", label: "New", windows: [], observedAt: AIQuotaFixtures.now)
        monitor.configure(readers: [QuotaFixtureReader(providerID: "new", result: .success([newAccount]))])
        await monitor.refresh()
        #expect(monitor.snapshot.accounts == [newAccount])
        await gate.releaseAll()
        await oldRefresh.value
        #expect(monitor.snapshot.accounts == [newAccount])
        #expect(!monitor.isRefreshing)
        #expect(monitor.errors.isEmpty)
        monitor.stop()
        #expect(monitor.snapshot.accounts.isEmpty)
    }

    @Test
    func cancellingTheRefreshCallerDoesNotLeaveRefreshPermanentlyBusy() async {
        let gate = AIQuotaReaderGate()
        let monitor = AIQuotaMonitor(readers: [AIQuotaControlledReader(id: "old") { await gate.read("old") }])
        let refresh = Task { await monitor.refresh() }
        #expect(await aiQuotaEventually { await gate.started.count == 1 })
        refresh.cancel()
        await gate.releaseAll()
        await refresh.value
        #expect(!monitor.isRefreshing)
        #expect(monitor.snapshot.accounts.isEmpty)
        monitor.configure(readers: [])
        await monitor.refresh()
        #expect(!monitor.isRefreshing)
    }

    @Test
    func pollingDoesNotRetainTheMonitorWhileSleeping() async {
        let sleeper = AIQuotaSleepGate()
        var monitor: AIQuotaMonitor? = AIQuotaMonitor(readers: [], sleeper: { await sleeper.sleep($0) })
        weak var weakMonitor = monitor
        monitor?.start()
        monitor?.start()
        #expect(await aiQuotaEventually { await sleeper.durations.count == 1 })
        #expect(await sleeper.durations == [.seconds(60)])
        monitor = nil
        #expect(weakMonitor == nil)
        await sleeper.releaseAll()
    }
}

private struct AIQuotaControlledReader: AIQuotaReading {
    let id: String
    var providerID: String { "codex" }
    let operation: @Sendable () async -> [AIQuotaAccount]
    func read() async throws -> [AIQuotaAccount] { await operation() }
}

private actor AIQuotaReaderGate {
    private var pending: [String: CheckedContinuation<Void, Never>] = [:]
    private(set) var started: [String] = []
    private var active = 0
    private(set) var maximumConcurrent = 0

    func read(_ id: String) async -> [AIQuotaAccount] {
        started.append(id)
        active += 1
        maximumConcurrent = max(maximumConcurrent, active)
        await withCheckedContinuation { pending[id] = $0 }
        active -= 1
        return [AIQuotaAccount(id: id, providerID: "codex", label: id, windows: [], observedAt: AIQuotaFixtures.now)]
    }

    func releaseAll() {
        let values = Array(pending.values)
        pending.removeAll()
        for value in values { value.resume() }
    }
}
