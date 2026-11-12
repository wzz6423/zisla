import Combine
import Foundation
import SQLite3
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIUsageHistoryMonitorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A full-window snapshot may include older retained dates without requesting or replacing the island's lazy arrays.
    @Test @MainActor
    func independentWindowReadsDoNotLoadOrUnloadIslandHistory() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        try repository.recordUsage([sample("current", at: now), sample("old", at: now.addingTimeInterval(-200 * 86400))])
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], environment: [:], now: { now })
        defer { monitor.stop() }
        let full = try await monitor.readUsageHistory()
        #expect(full.usageSamples.count == 2)
        #expect(monitor.state.usageSamples.isEmpty && monitor.state.modelUsageSamples.isEmpty && monitor.usageHistoryState == .idle)
        monitor.reload()
        let island = monitor.state
        #expect(try await monitor.readUsageHistory() == full)
        #expect(monitor.state == island)
        monitor.unloadUsageHistory()
        #expect(full.usageSamples.count == 2 && full.modelUsageSamples.count == 2)
        #expect(try await monitor.readUsageHistory() == full)
        #expect(monitor.usageHistoryState == .idle && monitor.state.usageSamples.isEmpty)
    }

    /// In-flight window and lazy island reads must be invalidated as soon as clear begins, before old data can publish.
    @Test @MainActor
    func clearingRejectsOldReadsAndPreservesTaskUpdatesFromTheSameQueue() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let value = sample("clear-replay", at: now)
        try repository.recordDetectedUsage([value])
        let detector = BlockingHistoryActivityDetector(task: AIProgressTask(id: "active", provider: .codex,
            title: "Fixture", progress: nil, updatedAt: now))
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [detector], environment: [:], now: { now })
        defer { detector.release(); monitor.stop() }
        monitor.refreshActiveTasks()
        for await _ in detector.started { break }
        let ready = AsyncStream<Void>.makeStream()
        let staleRead = Task {
            ready.continuation.yield(())
            return try await monitor.readUsageHistory()
        }
        for await _ in ready.stream { break }
        monitor.loadUsageHistory()
        let began = AsyncStream<Void>.makeStream()
        let observation = monitor.$isClearingUsageHistory.sink { if $0 { began.continuation.yield(()) } }
        let clear = Task { try await monitor.clearUsageHistory() }
        for await _ in began.stream { break }
        #expect(monitor.isClearingUsageHistory)
        let duringReady = AsyncStream<Void>.makeStream()
        let duringClear = Task {
            duringReady.continuation.yield(())
            return try await monitor.readUsageHistory()
        }
        for await _ in duringReady.stream { break }
        do { try await monitor.clearUsageHistory(); Issue.record("A second clear was accepted while the first was pending") }
        catch is CancellationError {}
        detector.release()
        try await clear.value
        do { _ = try await duringClear.value; Issue.record("Reading during clear succeeded") }
        catch is CancellationError {}
        do { _ = try await staleRead.value; Issue.record("The old history read was accepted after clear") }
        catch is CancellationError {}
        observation.cancel()
        #expect(monitor.usageHistoryRevision == 1 && !monitor.isClearingUsageHistory)
        #expect(monitor.state.usageSamples.isEmpty && monitor.state.modelUsageSamples.isEmpty)
        #expect(monitor.usageHistoryState == .loaded)
        #expect(try await monitor.readUsageHistory() == AIUsageHistory())
        #expect(monitor.state.tasks.map(\.id) == ["active"], "Task updates queued before clear must still publish")
        #expect(try repository.recordDetectedUsage([value]) == 0)
    }

    /// Read and clear errors must surface from unusable storage without leaving the shared action permanently busy.
    @Test @MainActor
    func storageFailureAndCancelledReadsDoNotMutateLoadedState() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("fixture".utf8).write(to: root)
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], environment: [:], now: { now })
        defer { monitor.stop() }
        do { _ = try await monitor.readUsageHistory(); Issue.record("Unusable storage unexpectedly loaded") }
        catch {}
        do { try await monitor.clearUsageHistory(); Issue.record("Unusable storage unexpectedly cleared") }
        catch {}
        #expect(!monitor.isClearingUsageHistory && monitor.usageHistoryRevision == 0)
        #expect(monitor.state.usageSamples.isEmpty && monitor.usageHistoryState == .idle)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await monitor.readUsageHistory()
        }
        do { _ = try await cancelled.value; Issue.record("A cancelled read unexpectedly returned") }
        catch is CancellationError {}
        #expect(try Data(contentsOf: root) == Data("fixture".utf8))
    }

    /// A failed transaction must restore an already requested island snapshot and leave the action retryable.
    @Test(.timeLimit(.minutes(1))) @MainActor
    func failedClearReloadsTheRequestedIslandAndRetryEmptiesIt() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        try repository.recordDetectedUsage([sample("rollback", at: now)])
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], environment: [:], now: { now })
        defer { monitor.stop() }
        monitor.reload()
        let previous = monitor.state
        var database: OpaquePointer?
        try #require(sqlite3_open(repository.databaseURL.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try #require(sqlite3_exec(database, "CREATE TRIGGER fail_clear BEFORE DELETE ON detected_usage_daily BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
        let states = AsyncStream<AIUsageHistoryState>.makeStream()
        let observation = monitor.$usageHistoryState.dropFirst().sink { states.continuation.yield($0) }
        defer { observation.cancel() }
        do { try await monitor.clearUsageHistory(); Issue.record("The injected clear failure was ignored") }
        catch {}
        for await state in states.stream { if state == .loaded { break } }
        #expect(monitor.state == previous && monitor.usageHistoryRevision == 0 && !monitor.isClearingUsageHistory)
        try #require(sqlite3_exec(database, "DROP TRIGGER fail_clear", nil, nil, nil) == SQLITE_OK)
        try await monitor.clearUsageHistory()
        #expect(monitor.state.usageSamples.isEmpty && monitor.state.modelUsageSamples.isEmpty && monitor.usageHistoryState == .loaded)
        #expect(monitor.usageHistoryRevision == 1)
    }

    #if DEBUG
    /// Clearing simulation changes only this process's preview; a new monitor restores it without modifying real reports.
    @Test @MainActor
    func debugClearAndRestartKeepRealReportsUntouched() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        try repository.recordUsage(sample("real", at: now))
        let real = try repository.loadUsageHistory()
        let environment = ["ZISLA_DEBUG_AI_MODEL_USAGE": "codex:preview:100:20"]
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], environment: environment, now: { now })
        defer { monitor.stop() }
        #expect(try await monitor.readUsageHistory().usageSamples.map(\.totalTokens) == [120])
        monitor.loadUsageHistory()
        try await monitor.clearUsageHistory()
        #expect(try await monitor.readUsageHistory() == AIUsageHistory())
        monitor.unloadUsageHistory()
        monitor.loadUsageHistory()
        monitor.reload()
        #expect(monitor.state.usageSamples.isEmpty && monitor.state.modelUsageSamples.isEmpty)
        #expect(try repository.loadUsageHistory() == real)
        let restarted = AIStateMonitor(directoryURL: root, activityDetectors: [], environment: environment, now: { now })
        defer { restarted.stop() }
        #expect(try await restarted.readUsageHistory().modelUsageSamples.map(\.model) == ["preview"])
        #expect(try repository.loadUsageHistory() == real)
    }
    #endif

    private func sample(_ id: String, at date: Date) -> AIUsageSample {
        AIUsageSample(sourceID: id, provider: .codex, timestamp: date, inputTokens: 10, outputTokens: 2, model: id)
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("zisla-ai-history-monitor-\(UUID())")
    }
}

private final class BlockingHistoryActivityDetector: AIActivityDetecting, @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private let task: AIProgressTask
    let started: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init(task: AIProgressTask) {
        self.task = task
        (started, continuation) = AsyncStream<Void>.makeStream()
    }

    func activeTasks() throws -> [AIProgressTask] {
        condition.lock()
        defer { condition.unlock() }
        continuation.yield(())
        while !released { condition.wait() }
        return [task]
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}
