import Combine
import Foundation
import Testing

@testable import KeyboardKit

@MainActor
struct TypingStatsModelTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)
    private let application = TypingApplicationIdentity(
        processKey: "com.example.editor",
        displayName: "Editor",
        processName: "Editor",
        bundleIdentifier: "com.example.editor"
    )

    @Test(arguments: [false, true])
    func failedClearPreservesBufferedInput(hasCommittedInput: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypingStatsModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = now
        let store = TypingStatsStore(
            databaseURL: directory.appendingPathComponent("typing-stats.sqlite3"),
            nowProvider: { now }
        )
        let persistence = FailingTypingStatsPersistence(store: store)
        let model = TypingStatsModel(persistence: persistence)
        if hasCommittedInput {
            recordKey(in: model)
            #expect(await model.flushPending())
        }
        await persistence.setFailures(record: true, clear: true)
        recordKey(in: model)
        #expect(await model.flushPending() == false)

        #expect(await model.clearAll() == false)
        #expect(model.isClearing == false)
        #expect(model.sourceStatus != .available)

        await persistence.setFailures()
        #expect(await model.flushPending())
        #expect(await model.flushPending())
        let snapshot = try await store.loadSnapshot()
        let expectedCount: Int64 = hasCommittedInput ? 2 : 1
        #expect(snapshot.today.characterCount == expectedCount)
        #expect(snapshot.allTimeKeyCounts[0] == expectedCount)
    }

    @Test(arguments: [false, true])
    func successfulClearDoesNotRetryDeletedInput(snapshotFails: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypingStatsModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = now
        let store = TypingStatsStore(
            databaseURL: directory.appendingPathComponent("typing-stats.sqlite3"),
            nowProvider: { now }
        )
        let persistence = FailingTypingStatsPersistence(store: store)
        let model = TypingStatsModel(persistence: persistence)
        await persistence.setFailures(record: true, snapshot: snapshotFails)
        recordKey(in: model)
        #expect(await model.flushPending() == false)

        #expect(await model.clearAll() == !snapshotFails)
        #expect(model.isClearing == false)

        await persistence.setFailures()
        #expect(await model.flushPending())
        let snapshot = try await store.loadSnapshot()
        #expect(snapshot.today.characterCount == 0)
        #expect(snapshot.allTimeKeyCounts.isEmpty)
    }

    @Test(arguments: [false, true])
    func clearingDuringFailedWritePreservesOrDiscardsAllBufferedInput(clearFails: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypingStatsModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = now
        let store = TypingStatsStore(
            databaseURL: directory.appendingPathComponent("typing-stats.sqlite3"),
            nowProvider: { now }
        )
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer {
            started.continuation.finish()
            resume.continuation.finish()
        }
        let persistence = FailingTypingStatsPersistence(store: store, beforeFirstRecord: {
            started.continuation.yield()
            for await _ in resume.stream { break }
        })
        await persistence.setFailures(record: true, clear: clearFails)
        let model = TypingStatsModel(persistence: persistence)
        recordKey(in: model)
        let flush = Task { await model.flushPending() }
        for await _ in started.stream { break }
        recordKey(in: model)
        let clearing = model.$isClearing.filter { $0 }.prefix(1).sink { _ in
            resume.continuation.yield()
        }
        defer { clearing.cancel() }

        #expect(await model.clearAll() == !clearFails)
        #expect(await flush.value == false)
        #expect(model.isClearing == false)
        await persistence.setFailures()
        #expect(await model.flushPending())
        #expect(await model.flushPending())

        let snapshot = try await store.loadSnapshot()
        let expectedCount: Int64 = clearFails ? 2 : 0
        #expect(snapshot.today.characterCount == expectedCount)
        #expect(snapshot.allTimeKeyCounts[0, default: 0] == expectedCount)
    }

    @Test(arguments: [false, true], [false, true])
    func refreshingDuringClearDoesNotWriteBufferedInput(clearFails: Bool, hasRetryBatch: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypingStatsModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = now
        let store = TypingStatsStore(
            databaseURL: directory.appendingPathComponent("typing-stats.sqlite3"),
            nowProvider: { now }
        )
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer {
            started.continuation.finish()
            resume.continuation.finish()
        }
        let persistence = FailingTypingStatsPersistence(store: store, beforeClearReturns: {
            started.continuation.yield()
            for await _ in resume.stream { break }
        })
        let model = TypingStatsModel(persistence: persistence)
        recordKey(in: model)
        #expect(await model.flushPending())
        await persistence.setFailures(record: true, clear: clearFails)
        recordKey(in: model)
        if hasRetryBatch { #expect(await model.flushPending() == false) }
        recordKey(in: model)

        let clear = Task { await model.clearAll() }
        for await _ in started.stream { break }
        #expect(model.isClearing)
        await persistence.setFailures(clear: clearFails)
        #expect(await model.flushPending() == false)
        await model.refresh()
        let duringClear = try await store.loadSnapshot()
        let committedCount: Int64 = clearFails ? 1 : 0
        #expect(duringClear.today.characterCount == committedCount)
        #expect(duringClear.allTimeKeyCounts[0, default: 0] == committedCount)

        resume.continuation.yield()
        #expect(await clear.value == !clearFails)
        #expect(model.isClearing == false)
        #expect(await model.flushPending())
        let afterClear = try await store.loadSnapshot()
        let expectedCount: Int64 = clearFails ? 3 : 0
        #expect(afterClear.today.characterCount == expectedCount)
        #expect(afterClear.allTimeKeyCounts[0, default: 0] == expectedCount)

        recordKey(in: model)
        #expect(await model.flushPending())
        let resumed = try await store.loadSnapshot()
        #expect(resumed.today.characterCount == expectedCount + 1)
        #expect(resumed.allTimeKeyCounts[0, default: 0] == expectedCount + 1)
    }

    private func recordKey(in model: TypingStatsModel) {
        model.recordKeyDown(
            keyCode: 0,
            isRepeat: false,
            isShortcutModified: false,
            application: application,
            at: now
        )
    }
}

private actor FailingTypingStatsPersistence: TypingStatsPersistence {
    private let store: TypingStatsStore
    private var recordFails = false
    private var clearFails = false
    private var snapshotFails = false
    private var beforeFirstRecord: (@Sendable () async -> Void)?
    private let beforeClearReturns: (@Sendable () async -> Void)?

    init(
        store: TypingStatsStore,
        beforeFirstRecord: (@Sendable () async -> Void)? = nil,
        beforeClearReturns: (@Sendable () async -> Void)? = nil
    ) {
        self.store = store
        self.beforeFirstRecord = beforeFirstRecord
        self.beforeClearReturns = beforeClearReturns
    }

    func setFailures(record: Bool = false, clear: Bool = false, snapshot: Bool = false) {
        recordFails = record
        clearFails = clear
        snapshotFails = snapshot
    }

    func record(_ batch: TypingStatsWriteBatch) async throws {
        if let beforeFirstRecord {
            self.beforeFirstRecord = nil
            await beforeFirstRecord()
        }
        if recordFails { throw TypingStatsStoreError.busy }
        try await store.record(batch)
    }

    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot {
        if snapshotFails { throw TypingStatsStoreError.busy }
        return try await store.loadSnapshot(timelineRange: timelineRange)
    }

    func clearAll() async throws {
        let clearFails = clearFails
        if !clearFails { try await store.clearAll() }
        await beforeClearReturns?()
        if clearFails { throw TypingStatsStoreError.busy }
    }
}
