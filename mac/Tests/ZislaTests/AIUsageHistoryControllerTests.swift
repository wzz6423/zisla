import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized)
struct AIUsageHistoryControllerTests {
    /// A delayed old request must never overwrite a newer snapshot, even if the dependency ignores cancellation.
    @Test @MainActor
    func newestReadWinsAndClearCannotReviveAnOldSnapshot() async {
        let reads = HistoryReadGate()
        let controller = AIUsageHistoryController(read: { try await reads.read() }, clear: {}, write: { _, _ in })
        let first = Task { await controller.load() }
        for await _ in reads.started { break }
        let second = Task { await controller.load() }
        for await _ in reads.started { break }
        reads.complete(1, with: .success(history(20)))
        await second.value
        reads.complete(0, with: .success(history(10)))
        await first.value
        #expect(controller.history == history(20) && controller.loadState == .loaded)
        let third = Task { await controller.load() }
        for await _ in reads.started { break }
        await controller.clearHistory()
        reads.complete(2, with: .success(history(30)))
        await third.value
        #expect(controller.history == AIUsageHistory() && controller.loadState == .loaded)
        #expect(!controller.isBusy)
    }

    /// Clear failures during an outstanding load must release loading state and retain the last committed snapshot.
    @Test @MainActor
    func readAndClearFailuresRetainHistoryAndCanRetry() async {
        let reads = HistoryReadGate()
        let controller = AIUsageHistoryController(read: { try await reads.read() },
            clear: { throw CocoaError(.fileWriteNoPermission) }, write: { _, _ in })
        let initial = Task { await controller.load() }
        for await _ in reads.started { break }
        reads.complete(0, with: .success(history(10)))
        await initial.value
        let refresh = Task { await controller.load() }
        for await _ in reads.started { break }
        await controller.clearHistory()
        #expect(controller.loadState == .loaded && !controller.isBusy && !controller.isLoading)
        #expect(controller.history == history(10) && controller.statusMessage != nil)
        reads.complete(1, with: .success(history(99)))
        await refresh.value
        #expect(controller.history == history(10))
        let failure = Task { await controller.load() }
        for await _ in reads.started { break }
        reads.complete(2, with: .failure(CocoaError(.fileReadCorruptFile)))
        await failure.value
        if case .failed = controller.loadState {} else { Issue.record("Read error must remain visible") }
        #expect(controller.history == history(10))
        let retry = Task { await controller.load() }
        for await _ in reads.started { break }
        reads.complete(3, with: .success(history(20)))
        await retry.value
        #expect(controller.loadState == .loaded && controller.history == history(20))
        let emptyRead = HistoryReadGate()
        let emptyController = AIUsageHistoryController(read: { try await emptyRead.read() },
            clear: { throw CocoaError(.fileWriteNoPermission) }, write: { _, _ in })
        let pending = Task { await emptyController.load() }
        for await _ in emptyRead.started { break }
        await emptyController.clearHistory()
        #expect(emptyController.loadState == .idle && !emptyController.isLoading)
        emptyRead.complete(0, with: .success(history(1)))
        await pending.value
        #expect(emptyController.history == AIUsageHistory())
    }

    @Test @MainActor
    func cancellingAWindowReadLeavesTheCommittedSnapshotUnchanged() async {
        let reads = HistoryReadGate()
        let controller = AIUsageHistoryController(read: { try await reads.read() }, clear: {}, write: { _, _ in })
        let request = Task { await controller.load() }
        for await _ in reads.started { break }
        request.cancel()
        reads.complete(0, with: .success(history(10)))
        await request.value
        #expect(controller.loadState == .idle && controller.history == AIUsageHistory())
    }

    /// Reopening and exporting reread all history, so snapshots created while a window was hidden are included.
    @Test @MainActor
    func reopenAndExportUseTheLatestCommittedSnapshotIncludingAnEmptyClear() async {
        var snapshot = history(10)
        var exports: [AIUsageHistory] = []
        let controller = AIUsageHistoryController(read: { snapshot }, clear: { snapshot = .init() },
            write: { value, _ in exports.append(value) })
        await controller.load()
        snapshot = history(20)
        await controller.load()
        #expect(controller.history == snapshot)
        snapshot = history(30)
        await controller.export(to: URL(fileURLWithPath: "/fixture.xlsx"))
        #expect(exports == [snapshot] && controller.history == snapshot)
        #expect(controller.statusMessage != nil && !controller.isBusy)
        snapshot = .init()
        await controller.export(to: URL(fileURLWithPath: "/empty.xlsx"))
        #expect(exports.count == 1 && controller.history == .init())
        #expect(controller.statusMessage == nil && !controller.isBusy)
        await controller.export(to: URL(fileURLWithPath: "/still-empty.xlsx"))
        #expect(exports.count == 1)
    }

    /// A failed or cancelled exporter must release its busy state; overlapping refreshes and clears are suppressed.
    @Test @MainActor
    func exportFailureAndCancellationKeepTheSnapshotAndReleaseBusyState() async {
        let writes = HistoryWriteGate()
        let snapshot = history(10)
        let controller = AIUsageHistoryController(read: { snapshot }, clear: {}, write: { _, _ in try await writes.write() })
        await controller.load()
        let failed = Task { await controller.export(to: URL(fileURLWithPath: "/fixture.xlsx")) }
        for await _ in writes.started { break }
        #expect(controller.action == .export)
        await controller.load()
        await controller.clearHistory()
        #expect(controller.history == snapshot && controller.action == .export)
        writes.complete(.failure(CocoaError(.fileWriteOutOfSpace)))
        await failed.value
        #expect(controller.statusMessage != nil && !controller.isBusy && controller.history == snapshot)
        let cancelled = Task { await controller.export(to: URL(fileURLWithPath: "/cancelled.xlsx")) }
        for await _ in writes.started { break }
        controller.cancelExport()
        writes.complete(.success(()))
        await cancelled.value
        #expect(controller.statusMessage == nil && !controller.isBusy && controller.history == snapshot)
    }

    /// The real writer must produce an xlsx atomically in an isolated folder and surface missing-directory and cancellation errors.
    @Test @MainActor
    func realExporterWritesAnArchiveAndLeavesNoFileAfterCancellationOrFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-ai-export-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("usage.xlsx")
        try await AIUsageHistoryExporter.write(history: history(10), to: destination)
        let data = try Data(contentsOf: destination)
        #expect(data.starts(with: [0x50, 0x4b, 0x03, 0x04]))
        let missing = root.appendingPathComponent("missing/usage.xlsx")
        do { try await AIUsageHistoryExporter.write(history: history(10), to: missing); Issue.record("Missing destination folder unexpectedly succeeded") }
        catch {}
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        let cancelled = root.appendingPathComponent("cancelled.xlsx")
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await AIUsageHistoryExporter.write(history: history(10), to: cancelled)
        }
        do { try await work.value; Issue.record("A cancelled writer unexpectedly saved a file") }
        catch is CancellationError {}
        #expect(!FileManager.default.fileExists(atPath: cancelled.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["usage.xlsx"])
    }

    @MainActor
    private func history(_ input: Int) -> AIUsageHistory {
        let sample = AIUsageSample(provider: .codex, timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            inputTokens: input, outputTokens: 2, model: "fixture")
        return AIUsageHistory(usageSamples: [sample], modelUsageSamples: [sample])
    }
}

@MainActor
private final class HistoryReadGate {
    let started: AsyncStream<Void>
    private let start: AsyncStream<Void>.Continuation
    private var pending: [CheckedContinuation<AIUsageHistory, any Error>?] = []

    init() { (started, start) = AsyncStream<Void>.makeStream() }

    func read() async throws -> AIUsageHistory {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            start.yield(())
        }
    }

    func complete(_ index: Int, with result: Result<AIUsageHistory, any Error>) {
        pending[index]?.resume(with: result)
        pending[index] = nil
    }
}

@MainActor
private final class HistoryWriteGate {
    let started: AsyncStream<Void>
    private let start: AsyncStream<Void>.Continuation
    private var pending: CheckedContinuation<Void, any Error>?

    init() { (started, start) = AsyncStream<Void>.makeStream() }

    func write() async throws {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            start.yield(())
        }
    }

    func complete(_ result: Result<Void, any Error>) {
        pending?.resume(with: result)
        pending = nil
    }
}
