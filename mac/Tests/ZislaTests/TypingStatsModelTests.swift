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

    @Test(arguments: [false, true], [false, true])
    func snapshotStartedBeforeClearCannotReplaceItsResult(readFails: Bool, clearFails: Bool) async throws {
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
        recordKey(in: model)
        await model.refresh()
        #expect(model.snapshot?.today.characterCount == 1)
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer {
            started.continuation.finish()
            resume.continuation.finish()
        }
        await persistence.pauseNextSnapshot {
            started.continuation.yield()
            for await _ in resume.stream { break }
        }
        await persistence.setFailures(clear: clearFails, snapshot: readFails)
        let refresh = Task { await model.refresh(for: .overview, showsActivity: true) }
        for await _ in started.stream { break }
        await persistence.setFailures(clear: clearFails)

        #expect(await model.clearAll() == !clearFails)
        let clearedSnapshot = model.snapshot
        let clearedStatus = model.sourceStatus
        resume.continuation.yield()
        await refresh.value

        #expect(model.snapshot?.today.characterCount == clearedSnapshot?.today.characterCount)
        #expect(model.snapshot?.allTimeKeyCounts == clearedSnapshot?.allTimeKeyCounts)
        #expect(model.sourceStatus == clearedStatus)
        #expect(!model.isRefreshing)
        await persistence.setFailures()
        recordKey(in: model)
        await model.refresh()
        let expectedCount: Int64 = clearFails ? 2 : 1
        #expect(model.snapshot?.today.characterCount == expectedCount)
        #expect(model.sourceStatus == .available)
        #expect(try await store.loadSnapshot().today.characterCount == expectedCount)
    }

    @Test(arguments: [false, true], [false, true])
    func reportStartedBeforeClearCannotReplaceItsResult(readFails: Bool, clearFails: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypingStatsModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = now
        let range = TypingDateRange(startDate: now, endDate: now)
        let store = TypingStatsStore(
            databaseURL: directory.appendingPathComponent("typing-stats.sqlite3"),
            nowProvider: { now }
        )
        let persistence = FailingTypingStatsPersistence(store: store)
        let model = TypingStatsModel(persistence: persistence)
        recordKey(in: model)
        await model.refresh()
        await model.loadReport(range: range, comparisonRange: nil)
        #expect(model.reportSnapshot?.metrics.characterCount == 1)
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer {
            started.continuation.finish()
            resume.continuation.finish()
        }
        await persistence.pauseNextReport {
            started.continuation.yield()
            for await _ in resume.stream { break }
        }
        await persistence.setFailures(clear: clearFails, report: readFails)
        let report = Task { await model.loadReport(range: range, comparisonRange: nil) }
        for await _ in started.stream { break }
        await persistence.setFailures(clear: clearFails)

        #expect(await model.clearAll() == !clearFails)
        let clearedReport = model.reportSnapshot
        let clearedError = model.reportErrorMessage
        resume.continuation.yield()
        await report.value

        #expect(model.reportSnapshot?.metrics.characterCount == clearedReport?.metrics.characterCount)
        #expect(model.reportErrorMessage == clearedError)
        #expect(!model.isLoadingReport)
        await persistence.setFailures()
        recordKey(in: model)
        await model.refresh()
        await model.loadReport(range: range, comparisonRange: nil)
        let expectedCount: Int64 = clearFails ? 2 : 1
        #expect(model.reportSnapshot?.metrics.characterCount == expectedCount)
        #expect(model.reportErrorMessage == nil)
        #expect(try await store.loadReport(range: range).metrics.characterCount == expectedCount)
    }

    @Test(arguments: [false, true], [false, true])
    func readStartedDuringClearCannotReplaceItsResult(isReport: Bool, clearFails: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypingStatsModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = now
        let range = TypingDateRange(startDate: now, endDate: now)
        let store = TypingStatsStore(
            databaseURL: directory.appendingPathComponent("typing-stats.sqlite3"),
            nowProvider: { now }
        )
        let clearStarted = AsyncStream<Void>.makeStream()
        let resumeClear = AsyncStream<Void>.makeStream()
        let readStarted = AsyncStream<Void>.makeStream()
        let resumeRead = AsyncStream<Void>.makeStream()
        defer {
            clearStarted.continuation.finish()
            resumeClear.continuation.finish()
            readStarted.continuation.finish()
            resumeRead.continuation.finish()
        }
        let persistence = FailingTypingStatsPersistence(store: store, beforeClear: {
            clearStarted.continuation.yield()
            for await _ in resumeClear.stream { break }
        })
        let model = TypingStatsModel(persistence: persistence)
        recordKey(in: model)
        await model.refresh()
        await model.loadReport(range: range, comparisonRange: nil)
        await persistence.setFailures(clear: clearFails)
        let clear = Task { await model.clearAll() }
        for await _ in clearStarted.stream { break }
        let pauseRead: @Sendable () async -> Void = {
            readStarted.continuation.yield()
            for await _ in resumeRead.stream { break }
        }
        if isReport {
            await persistence.pauseNextReport(pauseRead)
        } else {
            await persistence.pauseNextSnapshot(pauseRead)
        }
        let read = Task {
            if isReport {
                await model.loadReport(range: range, comparisonRange: nil)
            } else {
                await model.refresh()
            }
        }
        for await _ in readStarted.stream { break }
        resumeClear.continuation.yield()
        #expect(await clear.value == !clearFails)
        let clearStatus = model.sourceStatus
        resumeRead.continuation.yield()
        await read.value

        let expectedCount: Int64 = clearFails ? 1 : 0
        #expect(model.snapshot?.today.characterCount == expectedCount)
        #expect(model.reportSnapshot?.metrics.characterCount == expectedCount)
        #expect(model.sourceStatus == clearStatus)
        #expect(model.reportErrorMessage == nil)
        #expect(!model.isRefreshing)
        #expect(!model.isLoadingReport)
        #expect(try await store.loadSnapshot().today.characterCount == expectedCount)
    }

    @Test(arguments: [false, true], [false, true])
    func failedPostClearReloadInvalidatesReadsStartedAfterDeletion(clearReportFails: Bool, readFails: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypingStatsModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = now
        let range = TypingDateRange(startDate: now, endDate: now)
        let store = TypingStatsStore(
            databaseURL: directory.appendingPathComponent("typing-stats.sqlite3"),
            nowProvider: { now }
        )
        let persistence = FailingTypingStatsPersistence(store: store)
        let model = TypingStatsModel(persistence: persistence)
        recordKey(in: model)
        await model.refresh()
        await model.loadReport(range: range, comparisonRange: nil)
        let reloadStarted = AsyncStream<Void>.makeStream()
        let resumeReload = AsyncStream<Void>.makeStream()
        let readStarted = AsyncStream<Void>.makeStream()
        let resumeRead = AsyncStream<Void>.makeStream()
        defer {
            reloadStarted.continuation.finish()
            resumeReload.continuation.finish()
            readStarted.continuation.finish()
            resumeRead.continuation.finish()
        }
        let pauseReload: @Sendable () async -> Void = {
            reloadStarted.continuation.yield()
            for await _ in resumeReload.stream { break }
        }
        if clearReportFails {
            await persistence.pauseNextReport(pauseReload)
        } else {
            await persistence.pauseNextSnapshot(pauseReload)
        }
        await persistence.setFailures(snapshot: !clearReportFails, report: clearReportFails)
        let clear = Task { await model.clearAll() }
        for await _ in reloadStarted.stream { break }
        #expect(try await store.loadSnapshot().today.characterCount == 0)
        await persistence.setFailures(
            snapshot: !clearReportFails && readFails,
            report: clearReportFails && readFails
        )
        let pauseRead: @Sendable () async -> Void = {
            readStarted.continuation.yield()
            for await _ in resumeRead.stream { break }
        }
        if clearReportFails {
            await persistence.pauseNextReport(pauseRead)
        } else {
            await persistence.pauseNextSnapshot(pauseRead)
        }
        let read = Task {
            if clearReportFails {
                await model.loadReport(range: range, comparisonRange: nil)
            } else {
                await model.refresh(for: .overview, showsActivity: true)
            }
        }
        for await _ in readStarted.stream { break }
        resumeReload.continuation.yield()
        #expect(await clear.value == false)
        let snapshotCount = model.snapshot?.today.characterCount
        let reportCount = model.reportSnapshot?.metrics.characterCount
        let sourceStatus = model.sourceStatus
        let reportError = model.reportErrorMessage
        resumeRead.continuation.yield()
        await read.value

        #expect(model.snapshot?.today.characterCount == snapshotCount)
        #expect(model.reportSnapshot?.metrics.characterCount == reportCount)
        #expect(model.sourceStatus == sourceStatus)
        #expect(model.reportErrorMessage == reportError)
        #expect(!model.isRefreshing)
        #expect(!model.isLoadingReport)
        await persistence.setFailures()
        recordKey(in: model)
        await model.refresh()
        await model.loadReport(range: range, comparisonRange: nil)
        #expect(model.snapshot?.today.characterCount == 1)
        #expect(model.reportSnapshot?.metrics.characterCount == 1)
        #expect(model.sourceStatus == .available)
        #expect(model.reportErrorMessage == nil)
    }

    @Test(arguments: [false, true], [false, true])
    func oldReportCannotEndPostClearReportLoading(readFails: Bool, clearFails: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypingStatsModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = now
        let range = TypingDateRange(startDate: now, endDate: now)
        let store = TypingStatsStore(
            databaseURL: directory.appendingPathComponent("typing-stats.sqlite3"),
            nowProvider: { now }
        )
        let persistence = FailingTypingStatsPersistence(store: store)
        let model = TypingStatsModel(persistence: persistence)
        recordKey(in: model)
        await model.refresh()
        await model.loadReport(range: range, comparisonRange: nil)
        let oldStarted = AsyncStream<Void>.makeStream()
        let resumeOld = AsyncStream<Void>.makeStream()
        let newStarted = AsyncStream<Void>.makeStream()
        let resumeNew = AsyncStream<Void>.makeStream()
        defer {
            oldStarted.continuation.finish()
            resumeOld.continuation.finish()
            newStarted.continuation.finish()
            resumeNew.continuation.finish()
        }
        await persistence.pauseNextReport {
            oldStarted.continuation.yield()
            for await _ in resumeOld.stream { break }
        }
        await persistence.setFailures(clear: clearFails, report: readFails)
        let oldReport = Task { await model.loadReport(range: range, comparisonRange: nil) }
        for await _ in oldStarted.stream { break }
        await persistence.setFailures(clear: clearFails)
        #expect(await model.clearAll() == !clearFails)
        await persistence.pauseNextReport {
            newStarted.continuation.yield()
            for await _ in resumeNew.stream { break }
        }
        let newReport = Task { await model.loadReport(range: range, comparisonRange: nil) }
        for await _ in newStarted.stream { break }

        resumeOld.continuation.yield()
        await oldReport.value
        let expectedCount: Int64 = clearFails ? 1 : 0
        #expect(model.reportSnapshot?.metrics.characterCount == expectedCount)
        #expect(model.reportErrorMessage == nil)
        #expect(model.isLoadingReport)

        resumeNew.continuation.yield()
        await newReport.value
        #expect(model.reportSnapshot?.metrics.characterCount == expectedCount)
        #expect(model.reportErrorMessage == nil)
        #expect(!model.isLoadingReport)
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
    private var reportFails = false
    private var beforeFirstRecord: (@Sendable () async -> Void)?
    private let beforeClear: (@Sendable () async -> Void)?
    private let beforeClearReturns: (@Sendable () async -> Void)?
    private var beforeNextSnapshotReturns: (@Sendable () async -> Void)?
    private var beforeNextReportReturns: (@Sendable () async -> Void)?

    init(
        store: TypingStatsStore,
        beforeFirstRecord: (@Sendable () async -> Void)? = nil,
        beforeClear: (@Sendable () async -> Void)? = nil,
        beforeClearReturns: (@Sendable () async -> Void)? = nil
    ) {
        self.store = store
        self.beforeFirstRecord = beforeFirstRecord
        self.beforeClear = beforeClear
        self.beforeClearReturns = beforeClearReturns
    }

    func setFailures(record: Bool = false, clear: Bool = false, snapshot: Bool = false, report: Bool = false) {
        recordFails = record
        clearFails = clear
        snapshotFails = snapshot
        reportFails = report
    }

    func pauseNextSnapshot(_ beforeReturn: @escaping @Sendable () async -> Void) {
        beforeNextSnapshotReturns = beforeReturn
    }

    func pauseNextReport(_ beforeReturn: @escaping @Sendable () async -> Void) {
        beforeNextReportReturns = beforeReturn
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
        let fails = snapshotFails
        let beforeReturn = beforeNextSnapshotReturns
        beforeNextSnapshotReturns = nil
        let snapshot = try await store.loadSnapshot(timelineRange: timelineRange)
        await beforeReturn?()
        if fails { throw TypingStatsStoreError.busy }
        return snapshot
    }

    func loadReport(
        range: TypingDateRange,
        comparisonRange: TypingDateRange?,
        rhythmRange: TypingDateRange?,
        rhythmComparisonRange: TypingDateRange?
    ) async throws -> TypingRangeReportSnapshot {
        let fails = reportFails
        let beforeReturn = beforeNextReportReturns
        beforeNextReportReturns = nil
        let report = try await store.loadReport(
            range: range,
            comparisonRange: comparisonRange,
            rhythmRange: rhythmRange,
            rhythmComparisonRange: rhythmComparisonRange
        )
        await beforeReturn?()
        if fails { throw TypingStatsStoreError.busy }
        return report
    }

    func clearAll() async throws {
        let clearFails = clearFails
        await beforeClear?()
        if !clearFails { try await store.clearAll() }
        await beforeClearReturns?()
        if clearFails { throw TypingStatsStoreError.busy }
    }
}
