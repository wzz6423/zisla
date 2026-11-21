import AppKit
import Combine
import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@MainActor
struct AIAccountBalanceMonitorTests {
    #if DEBUG
    @Test(arguments: [Set<AIProvider>(), [.codex]])
    func fixtureProvidersOverrideRealSelectionsWithoutChangingUsageHistory(providers: Set<AIProvider>) async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let environment = ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": "claude:10:70,gpt:0,cursor:20"]
        let service = AIAccountBalanceService(credentials: { _, _, _ in
            Issue.record("The monitor's explicit quota fixture must never read credentials")
            return nil
        }, now: { now }, debugBalances: { AIAccountBalanceDebug.balances(environment: environment, now: now) })
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: service,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600,
            environment: environment, now: { now })
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders(providers)
        monitor.start()
        try #require(await waitFor { monitor.accountBalances.count == 3 },
            "The fixture must publish Claude, ChatGPT, and Cursor even when no real providers are selected")
        #expect(monitor.accountBalances.map(\.providers) == [[.claude], [.gpt], [.cursor]])
        monitor.configureAccountBalanceProviders([])
        #expect(monitor.accountBalances.count == 3, "Real account selection changes must not hide the active fixture")
        #expect(try AIStateRepository(directoryURL: root).load().usageSamples.isEmpty)
    }

    @Test func qoderDebugFixtureOverridesEmptyRealRegionSelection() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let environment = ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": "coder:10"]
        let service = AIAccountBalanceService(credentials: { _, _, _ in
            Issue.record("An explicit Qoder fixture must not read credentials")
            return nil
        }, now: { now }, debugBalances: { AIAccountBalanceDebug.balances(environment: environment, now: now) })
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: service,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600,
            environment: environment, now: { now })
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([], qoderRegions: [])
        monitor.start()
        try #require(await waitFor { monitor.accountBalances.count == 1 })
        let row = try #require(monitor.accountBalances.first)
        #expect(row.providers == [.coder] && row.isDebug && row.windows.first?.remainingPercent == 10)
        monitor.configureAccountBalanceProviders([], qoderRegions: [.china])
        #expect(monitor.accountBalances == [row], "Real region choices must not hide the explicit fixture")
    }

    @Test(arguments: ["claude:nan", "cursor:20,", " "])
    func malformedFixtureDoesNotScheduleLiveAccountRefresh(raw: String) async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = ImmediateBalanceDetector()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600,
            environment: ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": raw])
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([.codex])
        monitor.start()
        #expect(!monitor.isRefreshingAccountBalances && monitor.accountBalances.isEmpty)
        #expect(try await !waitFor { await detector.callCount > 0 },
            "An invalid fixture must leave every real account source untouched")
    }

    @Test(arguments: [[:], ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": ""]])
    func clearedFixtureRestoresProviderSelection(environment: [String: String]) async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = BalanceDetectorGate()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600, environment: environment)
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([.codex])
        monitor.start()
        try #require(await waitFor { await detector.calls.count == 1 })
        #expect(await detector.calls.first?.providers == [.codex])
        await detector.release(0, result: .success([]))
        try #require(await waitFor { !monitor.isRefreshingAccountBalances })
        monitor.configureAccountBalanceProviders([])
        #expect(!monitor.isRefreshingAccountBalances && monitor.accountBalances.isEmpty)
        #expect(await detector.calls.count == 1)
    }
    #endif

    /// Cancelling before the main-actor refresh starts must prevent even an uncooperative detector from reading credentials.
    @Test(arguments: [false, true])
    func cancellationBeforeRefreshStartsDoesNotInvokeDetector(removeProviders: Bool) async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = ImmediateBalanceDetector()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([.claude])
        monitor.start()
        #expect(monitor.isRefreshingAccountBalances)
        if removeProviders {
            monitor.configureAccountBalanceProviders([])
        } else {
            monitor.stop()
        }
        #expect(!monitor.isRefreshingAccountBalances && monitor.accountBalances.isEmpty)
        #expect(try await !waitFor { await detector.callCount > 0 },
            "A refresh cancelled before it starts must not invoke the account detector")
        #expect(!monitor.isRefreshingAccountBalances && monitor.accountBalances.isEmpty)
    }

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
        monitor.configureAccountBalanceProviders([.coder], qoderRegions: [.global])
        monitor.start()
        try #require(await waitFor { await detector.calls.count == 1 })
        monitor.configureAccountBalanceProviders([.coder], qoderRegions: [.china])
        try #require(await waitFor { await detector.calls.count == 2 })
        #expect(await detector.calls.map(\.regions) == [[.global], [.china]])
        await detector.release(1, result: .success([balance(.coder, percent: 70, qoderRegion: .china)]))
        try #require(await waitFor { monitor.accountBalances.first?.windows.first?.remainingPercent == 70 })
        await detector.release(0, result: .success([balance(.coder, percent: 0, qoderRegion: .global)]))
        try #require(await waitFor { await detector.completed.contains(0) })
        #expect(await detector.cancelled.contains(0))
        #expect(monitor.accountBalances.first?.windows.first?.remainingPercent == 70)
        monitor.configureAccountBalanceProviders([])
        #expect(monitor.accountBalances.isEmpty && !monitor.isRefreshingAccountBalances)
        monitor.refresh()
        #expect(await detector.calls.count == 2)
    }

    @Test(arguments: [false, true])
    func noProviderOrNoQoderRegionNeverStartsAQuotaRefresh(selectQoder: Bool) async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = ImmediateBalanceDetector()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        if selectQoder { monitor.configureAccountBalanceProviders([.coder], qoderRegions: []) }
        monitor.start()
        monitor.refresh()
        #expect(!monitor.isRefreshingAccountBalances && monitor.accountBalances.isEmpty)
        #expect(await detector.callCount == 0, "An empty effective account selection must not invoke the detector")
    }

    @Test func qoderRegionsCoexistAndRemovingOneKeepsTheOtherAndUnrelatedProviderReadings() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = BalanceDetectorGate()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        let providers: Set<AIProvider> = [.coder, .trae, .zed]
        let global = balance(.coder, percent: 10, qoderRegion: .global)
        let china = balance(.coder, percent: 70, qoderRegion: .china)
        let otherRows = [balance(.trae, percent: 50), balance(.zed, percent: 80)]
        monitor.configureAccountBalanceProviders(providers, qoderRegions: [.global, .china])
        monitor.start()
        try #require(await waitFor { await detector.calls.count == 1 })
        #expect(await detector.calls.first?.regions == [.global, .china])
        await detector.release(0, result: .success([global, china] + otherRows))
        try #require(await waitFor { monitor.accountBalances.count == 4 })
        #expect(monitor.accountBalances.filter { $0.providers.contains(.coder) } == [global, china])
        monitor.refreshAccountBalancesAfterCredentialChange()
        try #require(await waitFor { await detector.calls.count == 2 })
        monitor.configureAccountBalanceProviders(providers, qoderRegions: [.china])
        #expect(monitor.accountBalances == [china] + otherRows,
            "Only the deselected Qoder region must disappear before the replacement refresh completes")
        try #require(await waitFor { await detector.calls.count == 3 })
        await detector.release(2, result: .success([china] + otherRows))
        try #require(await waitFor { !monitor.isRefreshingAccountBalances })
        await detector.release(1, result: .success([global, balance(.coder, percent: 0, qoderRegion: .china)] + otherRows))
        try #require(await waitFor { await detector.completed.contains(1) })
        #expect(await detector.cancelled.contains(1))
        #expect(monitor.accountBalances == [china] + otherRows, "A cancelled two-region response must not restore the removed region")
        monitor.configureAccountBalanceProviders(providers, qoderRegions: [])
        #expect(monitor.accountBalances == otherRows)
        try #require(await waitFor { await detector.calls.count == 4 })
        #expect(await detector.calls.last?.providers == [.trae, .zed])
        #expect(await detector.calls.last?.regions.isEmpty == true)
        await detector.release(3, result: .success(otherRows))
        try #require(await waitFor { !monitor.isRefreshingAccountBalances })
    }

    @Test func qoderRegionChangesWithoutQoderSelectionDoNotCancelOrRestartOtherProviders() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = BalanceDetectorGate()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([.trae, .zed], qoderRegions: [.global])
        monitor.start()
        try #require(await waitFor { await detector.calls.count == 1 })
        monitor.configureAccountBalanceProviders([.trae, .zed], qoderRegions: [.china])
        monitor.configureAccountBalanceProviders([.trae, .zed], qoderRegions: [])
        #expect(monitor.isRefreshingAccountBalances)
        let rows = [balance(.trae, percent: 50), balance(.zed, percent: 80)]
        await detector.release(0, result: .success(rows))
        try #require(await waitFor { monitor.accountBalances == rows })
        #expect(await detector.calls.count == 1)
        #expect(await detector.cancelled.isEmpty,
            "Qoder region changes must leave an unrelated in-flight refresh running")
        monitor.configureAccountBalanceProviders([.coder, .trae, .zed], qoderRegions: [.china])
        try #require(await waitFor { await detector.calls.count == 2 })
        #expect(await detector.calls.last?.regions == [.china])
        await detector.release(1, result: .success(rows + [balance(.coder, percent: 70, qoderRegion: .china)]))
        try #require(await waitFor { !monitor.isRefreshingAccountBalances })
    }

    @Test func detectorFailurePublishesBothSelectedRegionStatusesAndNoDeselectedRegion() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = BalanceDetectorGate()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
            accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        monitor.configureAccountBalanceProviders([.coder, .zed], qoderRegions: [.global, .china])
        monitor.start()
        try #require(await waitFor { await detector.calls.count == 1 })
        await detector.release(0, result: .failure(URLError(.timedOut)))
        try #require(await waitFor { !monitor.isRefreshingAccountBalances })
        #expect(monitor.accountBalances.filter { $0.providers.contains(.coder) }.map(\.qoderRegion) == [.global, .china])
        #expect(monitor.accountBalances.allSatisfy { $0.status == .unavailable && $0.windows.isEmpty })
        monitor.configureAccountBalanceProviders([.coder, .zed], qoderRegions: [])
        #expect(monitor.accountBalances.map(\.providers) == [[.zed]])
        try #require(await waitFor { await detector.calls.count == 2 })
        await detector.release(1, result: .failure(URLError(.timedOut)))
        try #require(await waitFor { !monitor.isRefreshingAccountBalances })
        #expect(monitor.accountBalances.map(\.providers) == [[.zed]])
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

    private func balance(_ provider: AIProvider, percent: Double, qoderRegion: AIAccountBalanceQoderRegion? = nil) -> AIAccountBalance {
        var row = AIAccountBalanceCatalog.placeholder(for: [provider], qoderRegion: qoderRegion)
        row.status = .available
        row.windows = [.init(id: "fixture", kind: .all, remainingPercent: percent)]
        return row
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

private actor ImmediateBalanceDetector: AIAccountBalanceDetecting {
    private(set) var callCount = 0

    func accountBalances(for providers: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion>) async throws -> [AIAccountBalance] {
        callCount += 1
        return []
    }
}

private actor BalanceDetectorGate: AIAccountBalanceDetecting {
    struct Call: Sendable { var providers: Set<AIProvider>; var regions: Set<AIAccountBalanceQoderRegion> }
    private var continuations: [Int: CheckedContinuation<[AIAccountBalance], Error>] = [:]
    private(set) var calls: [Call] = []
    private(set) var cancelled: Set<Int> = []
    private(set) var completed: Set<Int> = []
    /// Holds completion even after cancellation so tests can prove late results are discarded by the monitor.
    func accountBalances(for providers: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion>) async throws -> [AIAccountBalance] {
        let index = calls.count
        calls.append(.init(providers: providers, regions: qoderRegions))
        defer { completed.insert(index); if Task.isCancelled { cancelled.insert(index) } }
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }
    func release(_ index: Int, result: Result<[AIAccountBalance], Error>) { continuations.removeValue(forKey: index)?.resume(with: result) }
}
