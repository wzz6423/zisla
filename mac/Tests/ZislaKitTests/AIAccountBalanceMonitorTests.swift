import AppKit
import Combine
import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@MainActor
struct AIAccountBalanceMonitorTests {
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
        #expect(await waitFor { await detector.calls.count == 1 })
        await detector.release(0, result: .success([balance(.claude, percent: 10)]))
        #expect(await waitFor { monitor.accountBalances.first?.severity == .critical })
        let row = monitor.accountBalances
        monitor.start()
        monitor.refresh()
        monitor.unloadUsageHistory()
        #expect(monitor.accountBalances == row, "Changing unrelated settings or closing usage history must retain the account reading")
        #expect(await detector.calls.count == 1)
        now = now.addingTimeInterval(180)
        monitor.refresh()
        #expect(await waitFor { await detector.calls.count == 2 })
        await detector.release(1, result: .success([balance(.claude, percent: 70)]))
        #expect(await waitFor { monitor.accountBalances.first?.severity == .normal })
        #expect(try AIStateRepository(directoryURL: root).load().usageSamples.isEmpty,
            "Balances and debug readings must never be persisted as Token consumption")
    }

    @Test func providerAndRegionChangesCancelOldGenerationAndUnselectedValuesCannotReappear() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = BalanceDetectorGate()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([.coder], qoderRegion: .global)
        monitor.start()
        #expect(await waitFor { await detector.calls.count == 1 })
        monitor.configureAccountBalanceProviders([.coder], qoderRegion: .china)
        #expect(await waitFor { await detector.calls.count == 2 })
        #expect(await detector.calls.map(\.region) == [.global, .china])
        await detector.release(1, result: .success([balance(.coder, percent: 70)]))
        #expect(await waitFor { monitor.accountBalances.first?.windows.first?.remainingPercent == 70 })
        await detector.release(0, result: .success([balance(.coder, percent: 0)]))
        #expect(await waitFor { await detector.completed.contains(0) })
        #expect(await detector.cancelled.contains(0))
        #expect(monitor.accountBalances.first?.windows.first?.remainingPercent == 70)
        monitor.configureAccountBalanceProviders([])
        #expect(monitor.accountBalances.isEmpty && !monitor.isRefreshingAccountBalances)
        monitor.refresh()
        #expect(await detector.calls.count == 2)
    }

    @Test func sleepStopAndLateCompletionCannotRestartRequestsButWakeRefreshes() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let center = NotificationCenter(), detector = BalanceDetectorGate()
        var monitor: AIStateMonitor? = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: center, detectorRefreshInterval: 3_600)
        monitor?.configureAccountBalanceProviders([.claude])
        monitor?.start()
        #expect(await waitFor { await detector.calls.count == 1 })
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        monitor?.refresh()
        #expect(await detector.calls.count == 1)
        await detector.release(0, result: .success([balance(.claude, percent: 0)]))
        #expect(await waitFor { await detector.completed.contains(0) })
        #expect(monitor?.accountBalances.isEmpty == true)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(await waitFor { await detector.calls.count == 2 })
        monitor?.stop()
        await detector.release(1, result: .success([balance(.claude, percent: 0)]))
        #expect(await waitFor { await detector.completed.contains(1) })
        #expect(monitor?.accountBalances.isEmpty == true && monitor?.isRefreshingAccountBalances == false)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(await detector.calls.count == 2)
        weak let retained = monitor
        monitor = nil
        #expect(await waitFor { retained == nil }, "Lifecycle observers must not retain a stopped monitor after pending background work completes")
    }

    @Test func detectorFailureInvalidatesOldAvailableQuotaAndRecoveryPublishesFreshReading() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = BalanceDetectorGate()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([.claude])
        monitor.start()
        #expect(await waitFor { await detector.calls.count == 1 })
        await detector.release(0, result: .success([balance(.claude, percent: 0)]))
        #expect(await waitFor { monitor.accountBalances.first?.severity == .exhausted })
        monitor.refreshAccountBalancesAfterCredentialChange()
        #expect(await waitFor { await detector.calls.count == 2 })
        await detector.release(1, result: .failure(URLError(.timedOut)))
        #expect(await waitFor { monitor.accountBalances.first?.status == .unavailable })
        #expect(monitor.accountBalances.first?.severity == nil && monitor.accountBalances.first?.updatedAt == nil)
        monitor.refreshAccountBalancesAfterCredentialChange()
        #expect(await waitFor { await detector.calls.count == 3 })
        await detector.release(2, result: .success([balance(.claude, percent: 70)]))
        #expect(await waitFor { monitor.accountBalances.first?.severity == .normal })
    }

    private func balance(_ provider: AIProvider, percent: Double) -> AIAccountBalance {
        .init(id: provider.rawValue, providers: [provider], status: .available,
            windows: [.init(id: "fixture", kind: .all, remainingPercent: percent)], isDebug: true)
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("zisla-balance-monitor-\(UUID())") }
    private func waitFor(_ condition: @MainActor () async -> Bool) async -> Bool {
        for _ in 0..<400 {
            if await condition() { return true }
            await Task.yield()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
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
    func accountBalances(for providers: Set<AIProvider>, qoderRegion: AIAccountBalanceQoderRegion) async throws -> [AIAccountBalance] {
        let index = calls.count
        calls.append(.init(providers: providers, region: qoderRegion))
        defer { completed.insert(index); if Task.isCancelled { cancelled.insert(index) } }
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }
    func release(_ index: Int, result: Result<[AIAccountBalance], Error>) { continuations.removeValue(forKey: index)?.resume(with: result) }
}
