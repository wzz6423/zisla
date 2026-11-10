import AppKit
import Combine
import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@MainActor
struct AIAccountBalanceMonitorTests {
    /// A fixed clock and held detector distinguish idempotent startup, quota throttling, and nonpersisted balance state.
    @Test func startupIsIdempotentRefreshIsThrottledAndHistoryUnloadKeepsBalances() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var now = Date(timeIntervalSince1970: 1_910_000_000)
        let detector = BalanceDetectorGate()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600, usageRefreshInterval: 180, now: { now })
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([.claude])
        monitor.start()
        try #require(await waitFor { await detector.calls.count == 1 })
        await detector.release(0, result: .success([balance(.claude, percent: 10)]))
        try #require(await waitFor { monitor.accountBalances.first?.severity == .critical })
        let row = monitor.accountBalances
        monitor.start()
        monitor.refresh()
        monitor.unloadUsageHistory()
        #expect(monitor.accountBalances == row, "Changing unrelated settings or closing usage history must retain the account reading")
        #expect(await detector.calls.count == 1)
        now = now.addingTimeInterval(180)
        monitor.refresh()
        try #require(await waitFor { await detector.calls.count == 2 })
        await detector.release(1, result: .success([balance(.claude, percent: 70)]))
        try #require(await waitFor { monitor.accountBalances.first?.severity == .normal })
        #expect(try AIStateRepository(directoryURL: root).load().usageSamples.isEmpty,
            "Balances and debug readings must never be persisted as Token consumption")
    }

    /// Releasing the old region last proves that cancellation and generation guards prevent stale quota publication.
    @Test func providerAndRegionChangesCancelOldGenerationAndUnselectedValuesCannotReappear() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = BalanceDetectorGate()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([.coder], qoderRegion: .global)
        monitor.start()
        try #require(await waitFor { await detector.calls.count == 1 })
        monitor.configureAccountBalanceProviders([.coder], qoderRegion: .china)
        try #require(await waitFor { await detector.calls.count == 2 })
        #expect(await detector.calls.map(\.region) == [.global, .china])
        await detector.release(1, result: .success([balance(.coder, percent: 70)]))
        try #require(await waitFor { monitor.accountBalances.first?.windows.first?.remainingPercent == 70 })
        await detector.release(0, result: .success([balance(.coder, percent: 0)]))
        try #require(await waitFor { await detector.completed.contains(0) })
        #expect(await detector.cancelled.contains(0))
        #expect(monitor.accountBalances.first?.windows.first?.remainingPercent == 70)
        monitor.configureAccountBalanceProviders([])
        #expect(monitor.accountBalances.isEmpty && !monitor.isRefreshingAccountBalances)
        monitor.refresh()
        #expect(await detector.calls.count == 2)
    }

    /// Synthetic workspace events and late completions prove the running/awake boundary and observer ownership cleanup.
    @Test func sleepStopAndLateCompletionCannotRestartRequestsButWakeRefreshes() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let center = NotificationCenter(), detector = BalanceDetectorGate()
        var monitor: AIStateMonitor? = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: center, detectorRefreshInterval: 3_600)
        monitor?.configureAccountBalanceProviders([.claude])
        monitor?.start()
        try #require(await waitFor { await detector.calls.count == 1 })
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        monitor?.refresh()
        #expect(await detector.calls.count == 1)
        await detector.release(0, result: .success([balance(.claude, percent: 0)]))
        try #require(await waitFor { await detector.completed.contains(0) })
        #expect(monitor?.accountBalances.isEmpty == true)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try #require(await waitFor { await detector.calls.count == 2 })
        monitor?.stop()
        await detector.release(1, result: .success([balance(.claude, percent: 0)]))
        try #require(await waitFor { await detector.completed.contains(1) })
        #expect(monitor?.accountBalances.isEmpty == true && monitor?.isRefreshingAccountBalances == false)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(await detector.calls.count == 2)
        monitor?.refreshAccountBalancesAfterCredentialChange()
        monitor?.refresh()
        #expect(await detector.calls.count == 2 && monitor?.isRefreshingAccountBalances == false,
            "Changing saved credentials must not restart a stopped monitor")
        weak let retained = monitor
        monitor = nil
        try #require(await waitFor { retained == nil }, "Lifecycle observers must not retain a stopped monitor after pending background work completes")
    }

    /// A failed refresh must remove stale exhaustion and its timestamp before a later successful reading can recover.
    @Test func detectorFailureInvalidatesOldAvailableQuotaAndRecoveryPublishesFreshReading() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = BalanceDetectorGate()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([.claude])
        monitor.start()
        try #require(await waitFor { await detector.calls.count == 1 })
        await detector.release(0, result: .success([balance(.claude, percent: 0)]))
        try #require(await waitFor { monitor.accountBalances.first?.severity == .exhausted })
        monitor.refreshAccountBalancesAfterCredentialChange()
        try #require(await waitFor { await detector.calls.count == 2 })
        await detector.release(1, result: .failure(URLError(.timedOut)))
        try #require(await waitFor { monitor.accountBalances.first?.status == .unavailable })
        #expect(monitor.accountBalances.first?.severity == nil && monitor.accountBalances.first?.updatedAt == nil)
        monitor.refreshAccountBalancesAfterCredentialChange()
        try #require(await waitFor { await detector.calls.count == 3 })
        await detector.release(2, result: .success([balance(.claude, percent: 70)]))
        try #require(await waitFor { monitor.accountBalances.first?.severity == .normal })
    }

    private func balance(_ provider: AIProvider, percent: Double) -> AIAccountBalance {
        .init(id: provider.rawValue, providers: [provider], status: .available,
            windows: [.init(id: "fixture", kind: .all, remainingPercent: percent)], isDebug: true)
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("zisla-balance-monitor-\(UUID())") }
    /// Bounds asynchronous publication by elapsed time, yielding executor time instead of counting main-queue turns.
    private func waitFor(_ condition: @MainActor () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

private actor BalanceDetectorGate: AIAccountBalanceDetecting {
    struct Call: Sendable { var providers: Set<AIProvider>; var region: AIAccountBalanceQoderRegion }
    private var continuations: [Int: CheckedContinuation<[AIAccountBalance], Error>] = [:]
    private(set) var calls: [Call] = []
    private(set) var cancelled: Set<Int> = []
    private(set) var completed: Set<Int> = []
    /// Holds completion even after cancellation so tests can prove late results are discarded by the monitor.
    func accountBalances(for providers: Set<AIProvider>, qoderRegion: AIAccountBalanceQoderRegion) async throws -> [AIAccountBalance] {
        let index = calls.count
        calls.append(.init(providers: providers, region: qoderRegion))
        defer { completed.insert(index); if Task.isCancelled { cancelled.insert(index) } }
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }
    func release(_ index: Int, result: Result<[AIAccountBalance], Error>) { continuations.removeValue(forKey: index)?.resume(with: result) }
}
