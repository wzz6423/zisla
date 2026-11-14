import Foundation
import SQLite3
import Testing

@testable import ZislaKit

/// In-memory stand-in for the history archive so the store logic can be exercised without touching disk.
final class MemoryHistoryPersistence: SystemMetricsHistoryPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SystemMetricsRecord] = []
    private(set) var appendCount = 0
    private(set) var appendedCapacities: [Int?] = []
    private(set) var removeAllCount = 0
    var allowsRecordLoading = true

    init(seed: [SystemMetricsRecord] = []) {
        stored = seed
    }

    func loadRecords() -> [SystemMetricsRecord] {
        lock.lock()
        defer { lock.unlock() }
        #expect(allowsRecordLoading, "Background recording and summaries must not load the full archive")
        return stored
    }

    func loadStats(capacity: Int?) -> SystemMetricsHistoryStats? {
        lock.lock()
        defer { lock.unlock() }
        let timestamps = stored.map(\.timestamp).sorted()
        let count = min(timestamps.count, capacity.map { max(1, $0) } ?? timestamps.count)
        return SystemMetricsHistoryStats(
            count: count,
            oldest: count > 0 ? timestamps[timestamps.count - count] : nil,
            newest: timestamps.last
        )
    }

    func appendRecord(_ record: SystemMetricsRecord, capacity: Int?) {
        lock.lock()
        defer { lock.unlock() }
        stored.append(record)
        appendCount += 1
        appendedCapacities.append(capacity)
        if let capacity {
            let overflow = stored.count - max(1, capacity)
            if overflow > 0 {
                stored.removeFirst(overflow)
            }
        }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        stored = []
        removeAllCount += 1
    }
}

final class BlockingHistoryPersistence: SystemMetricsHistoryPersisting, @unchecked Sendable {
    enum Operation: Sendable {
        case load, append, clear
    }

    private let condition = NSCondition()
    private var stored: [SystemMetricsRecord]
    private let blockedOperation: Operation
    private var operationCanFinish = false
    private var events: [(operation: Operation, isMainThread: Bool)] = []
    let operationStarted: AsyncStream<Void>
    private let operationStartedContinuation: AsyncStream<Void>.Continuation

    init(seed: [SystemMetricsRecord] = [], blockedOperation: Operation = .load) {
        stored = seed
        self.blockedOperation = blockedOperation
        (operationStarted, operationStartedContinuation) = AsyncStream<Void>.makeStream()
    }

    var mainThreadOperations: [Operation] {
        condition.lock()
        defer { condition.unlock() }
        return events.filter(\.isMainThread).map(\.operation)
    }

    var appendCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return events.filter { $0.operation == .append }.count
    }

    var persistedRecords: [SystemMetricsRecord] {
        condition.lock()
        defer { condition.unlock() }
        return stored
    }

    func loadRecords() -> [SystemMetricsRecord] {
        condition.lock()
        waitIfNeeded(for: .load)
        let records = stored
        condition.unlock()
        return records
    }

    func appendRecord(_ record: SystemMetricsRecord, capacity: Int?) {
        condition.lock()
        waitIfNeeded(for: .append)
        stored.append(record)
        if let capacity {
            stored = Array(stored.suffix(max(1, capacity)))
        }
        condition.unlock()
    }

    func removeAll() {
        condition.lock()
        waitIfNeeded(for: .clear)
        stored = []
        condition.unlock()
    }

    func release() {
        condition.lock()
        operationCanFinish = true
        condition.broadcast()
        condition.unlock()
    }

    private func waitIfNeeded(for operation: Operation) {
        events.append((operation, Thread.isMainThread))
        guard operation == blockedOperation else { return }
        operationStartedContinuation.yield(())
        operationStartedContinuation.finish()
        // The old synchronous implementation must fail the thread assertion without deadlocking.
        guard !Thread.isMainThread else { return }
        while !operationCanFinish {
            condition.wait()
        }
    }
}

private func record(
    at seconds: TimeInterval,
    cpuUsage: Double = 0.25,
    gpuUsage: Double? = nil,
    fanRPMs: [Double] = [],
    memoryUsed: UInt64 = 8_000,
    memoryTotal: UInt64 = 16_000,
    batteryLevel: Double? = nil,
    systemPowerWatts: Double? = nil
) -> SystemMetricsRecord {
    SystemMetricsRecord(
        timestamp: Date(timeIntervalSince1970: seconds),
        cpuUsage: cpuUsage,
        cpuUser: 0.2,
        cpuSystem: 0.05,
        cpuIdle: 0.75,
        gpuUsage: gpuUsage,
        memoryUsedBytes: memoryUsed,
        memoryTotalBytes: memoryTotal,
        memoryPressureRatio: 0.1,
        diskUsedBytes: 100,
        diskTotalBytes: 200,
        diskReadBytesPerSecond: 1_024,
        diskWriteBytesPerSecond: 2_048,
        fanRPMs: fanRPMs,
        networkReceiveBytesPerSecond: 10,
        networkSendBytesPerSecond: 20,
        batteryLevel: batteryLevel,
        systemPowerWatts: systemPowerWatts
    )
}

struct SystemMetricsHistoryStoreTests {
    @Test
    func backgroundRecordingKeepsTheArchiveLazyEvenAfterAnExplicitRead() {
        let seed = (0..<64_000).map { record(at: Double($0) * 60) }
        let persistence = MemoryHistoryPersistence(seed: seed)
        persistence.allowsRecordLoading = false
        let store = SystemMetricsHistoryStore(persistence: persistence)

        #expect(store.stats.count == seed.count)
        let appended = record(at: Double(seed.count) * 60)
        store.append(appended)
        #expect(store.stats.count == seed.count + 1)
        #expect(store.stats.oldest == seed.first?.timestamp)
        #expect(store.stats.newest == appended.timestamp)

        persistence.allowsRecordLoading = true
        #expect(store.records.last == appended)
        persistence.allowsRecordLoading = false
        let next = record(at: Double(seed.count + 1) * 60)
        store.append(next)
        #expect(store.stats.count == seed.count + 2)

        store.removeAll()
        #expect(store.stats == .empty)
        store.append(next)
        #expect(store.stats == SystemMetricsHistoryStats(count: 1, oldest: next.timestamp, newest: next.timestamp))
    }

    @Test(arguments: [nil, 0, 1, 2, 8] as [Int?])
    func existingPersistenceConformersCanDeriveSummaries(capacity: Int?) {
        let persistence = BlockingHistoryPersistence(seed: [record(at: 180), record(at: 60), record(at: 120)])
        persistence.release()
        let expected = [60.0, 120, 180].suffix(capacity.map { max(1, $0) } ?? 3)

        #expect(persistence.loadStats(capacity: capacity) == SystemMetricsHistoryStats(
            count: expected.count,
            oldest: expected.first.map { Date(timeIntervalSince1970: $0) },
            newest: expected.last.map { Date(timeIntervalSince1970: $0) }
        ))
        persistence.removeAll()
        #expect(persistence.loadStats(capacity: capacity) == .empty)
    }

    @Test(arguments: [0, 1, 43_200, 64_000])
    func defaultCapacityKeepsAllSamplesAcrossLoadingAppendingAndReloading(sampleCount: Int) {
        let seed = (0..<sampleCount).map { record(at: Double($0) * 60) }
        let persistence = MemoryHistoryPersistence(seed: Array(seed.reversed()))
        let store = SystemMetricsHistoryStore(persistence: persistence)

        #expect(store.stats.count == sampleCount)
        #expect(store.stats.oldest == seed.first?.timestamp)
        #expect(store.stats.newest == seed.last?.timestamp)

        let appended = record(at: Double(sampleCount) * 60)
        store.append(appended)

        #expect(store.stats.count == sampleCount + 1)
        #expect(store.records.first == (seed.first ?? appended))
        #expect(store.records.last == appended)
        #expect(persistence.loadRecords().count == sampleCount + 1)
        let reopened = SystemMetricsHistoryStore(persistence: persistence)
        #expect(reopened.stats == store.stats)
        #expect(reopened.records.enumerated().allSatisfy { index, sample in
            sample.timestamp.timeIntervalSince1970 == Double(index) * 60
        })
    }

    @Test
    func appendWritesOneSampleAtATimeUntilCapacity() {
        let persistence = MemoryHistoryPersistence()
        let store = SystemMetricsHistoryStore(persistence: persistence, capacity: 3)

        for index in 0..<3 {
            store.append(record(at: TimeInterval(index)))
        }

        #expect(persistence.appendCount == 3)
        #expect(persistence.appendedCapacities == [3, 3, 3])
        #expect(store.records.map(\.timestamp.timeIntervalSince1970) == [0, 1, 2])
    }

    @Test
    func overflowDropsTheOldestSamplesFromMemoryAndTheArchive() {
        let persistence = MemoryHistoryPersistence()
        let store = SystemMetricsHistoryStore(persistence: persistence, capacity: 2)

        for index in 0..<4 {
            store.append(record(at: TimeInterval(index)))
        }

        // The archive is trimmed by the append itself; nothing rewrites the whole table.
        #expect(persistence.appendCount == 4)
        #expect(store.records.map(\.timestamp.timeIntervalSince1970) == [2, 3])
        #expect(persistence.loadRecords().map(\.timestamp.timeIntervalSince1970) == [2, 3])
        #expect(store.stats.count == 2)
        #expect(store.stats.oldest?.timeIntervalSince1970 == 2)
        #expect(store.stats.newest?.timeIntervalSince1970 == 3)
        #expect(store.stats.span == 1)
    }

    @Test
    func loadTrimsOversizedArchivesAndSortsByTime() {
        let seed = [record(at: 5), record(at: 1), record(at: 3)]
        let store = SystemMetricsHistoryStore(persistence: MemoryHistoryPersistence(seed: seed), capacity: 2)

        #expect(store.records.map(\.timestamp.timeIntervalSince1970) == [3, 5])
    }

    @Test(arguments: [0, -1, Int.min])
    func explicitNonPositiveCapacityKeepsOneSample(capacity: Int) {
        let persistence = MemoryHistoryPersistence(seed: [record(at: 60), record(at: 120)])
        let store = SystemMetricsHistoryStore(persistence: persistence, capacity: capacity)
        #expect(store.records.map(\.timestamp.timeIntervalSince1970) == [120])

        store.append(record(at: 180))

        #expect(store.records.map(\.timestamp.timeIntervalSince1970) == [180])
        #expect(persistence.loadRecords().map(\.timestamp.timeIntervalSince1970) == [180])
    }

    @Test(arguments: [nil, 8] as [Int?])
    func removeAllEmptiesTheArchiveAndAllowsRecordingAgain(capacity: Int?) {
        let persistence = MemoryHistoryPersistence(seed: [record(at: 1)])
        let store = SystemMetricsHistoryStore(persistence: persistence, capacity: capacity)
        #expect(store.stats.count == 1)

        store.removeAll()

        #expect(store.records.isEmpty)
        #expect(store.stats == .empty)
        #expect(persistence.loadRecords().isEmpty)
        #expect(persistence.removeAllCount == 1)

        store.append(record(at: 2))
        #expect(store.records == [record(at: 2)])
        #expect(persistence.loadRecords() == store.records)
    }
}

struct SystemMetricsHistoryRecorderTests {
    @Test
    func recordsTheFirstSampleAndThenHonoursTheInterval() {
        var recorder = SystemMetricsHistoryRecorder(recordingInterval: 60)
        let start = Date(timeIntervalSince1970: 1_000)

        #expect(recorder.shouldRecord(at: start))
        recorder.markRecorded(at: start)

        #expect(!recorder.shouldRecord(at: start.addingTimeInterval(59)))
        #expect(recorder.shouldRecord(at: start.addingTimeInterval(60)))
        recorder.markRecorded(at: start.addingTimeInterval(60))
        #expect(!recorder.shouldRecord(at: start.addingTimeInterval(119)))
    }

    @Test
    func resetMakesTheNextSampleRecordable() {
        var recorder = SystemMetricsHistoryRecorder(recordingInterval: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        recorder.markRecorded(at: start)

        recorder.reset()

        #expect(recorder.shouldRecord(at: start))
    }

    @Test
    func recordingIntervalNeverFallsBelowOneSecond() {
        #expect(SystemMetricsHistoryRecorder(recordingInterval: 0).recordingInterval == 1)
    }
}

struct SystemMetricsHistorySeriesBuilderTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test
    func batteryAndSystemPowerKeepUnitsZerosAndMissingSegments() throws {
        let records = [
            record(at: 100, batteryLevel: 0.8, systemPowerWatts: 24),
            record(at: 160),
            record(at: 220, batteryLevel: 0, systemPowerWatts: 0),
        ]
        let sections = SystemMetricsHistorySeriesBuilder.sections(records: records, range: .all, now: now)
        let battery = try #require(sections.first { $0.id == "battery" })
        let power = try #require(sections.first { $0.id == "power" })
        #expect(battery.unit == .ratio)
        #expect(power.unit == .watts)
        #expect(battery.series[0].points.map(\.value) == [0.8, 0])
        #expect(power.series[0].points.map(\.value) == [24, 0])
        #expect(power.series[0].points.map(\.segment) == [0, 1])
        #expect(power.series[0].points.map(\.date.timeIntervalSince1970) == [100, 220])

        let unavailable = SystemMetricsHistorySeriesBuilder.sections(
            records: [record(at: 100)], range: .all, now: now
        )
        #expect(!unavailable.contains { $0.id == "battery" || $0.id == "power" })
    }

    @Test
    func powerHistoryBucketsWithinContinuousSegmentsAndBoundsFragmentedHistory() throws {
        let records = (0..<100).map { index in
            record(at: Double(index) * 60, batteryLevel: 0.5, systemPowerWatts: Double(index))
        }
        let sections = SystemMetricsHistorySeriesBuilder.sections(
            records: records, range: .all, now: now, maximumPoints: 10
        )
        let points = try #require(sections.first { $0.id == "power" }?.series.first?.points)
        #expect(points.count == 10)
        #expect(points.first?.value == 4.5)
        #expect(points.last?.value == 94.5)

        let fragmented = (0..<100).map { index in
            record(at: Double(index) * 60, systemPowerWatts: index.isMultiple(of: 2) ? 10 : nil)
        }
        let fragmentedSections = SystemMetricsHistorySeriesBuilder.sections(
            records: fragmented, range: .all, now: now, maximumPoints: 8
        )
        let fragmentedPoints = try #require(fragmentedSections.first { $0.id == "power" }?.series.first?.points)
        #expect(fragmentedPoints.count == 8)
        #expect(Set(fragmentedPoints.map(\.segment)).count == 8)
        #expect(fragmentedPoints.last?.date == fragmented[98].timestamp)
    }

    @Test
    func sectionsCoverEveryCategoryAndSkipUnavailableOnes() throws {
        let records = [
            record(at: now.timeIntervalSince1970 - 120, gpuUsage: 0.5, fanRPMs: [1_200, 1_300]),
            record(at: now.timeIntervalSince1970 - 60, gpuUsage: 0.7, fanRPMs: [1_400]),
        ]

        let sections = SystemMetricsHistorySeriesBuilder.sections(records: records, range: .week, now: now)

        #expect(sections.map(\.id) == ["cpu", "gpu", "memory", "disk", "fans", "network"])
        let fans = try #require(sections.first { $0.id == "fans" })
        #expect(fans.series.count == 2)
        #expect(fans.unit == .rpm)
        // The second fan only reported one sample; it must not invent a point for the sample it missed.
        #expect(fans.series[1].points.count == 1)
    }

    @Test
    func sectionsOmitFansWhenTheMachineNeverReportsThem() {
        let sections = SystemMetricsHistorySeriesBuilder.sections(
            records: [record(at: now.timeIntervalSince1970 - 60)],
            range: .week,
            now: now
        )

        #expect(!sections.contains { $0.id == "fans" })
        #expect(!sections.contains { $0.id == "gpu" })
    }

    @Test
    func rangeFiltersOlderSamples() {
        let records = [
            record(at: now.timeIntervalSince1970 - 8 * 24 * 3600),
            record(at: now.timeIntervalSince1970 - 60),
        ]

        let week = SystemMetricsHistorySeriesBuilder.sections(records: records, range: .week, now: now)
        let all = SystemMetricsHistorySeriesBuilder.sections(records: records, range: .all, now: now)

        #expect(week.first?.series.first?.points.count == 1)
        #expect(all.first?.series.first?.points.count == 2)
    }

    @Test
    func allRangeExcludesSamplesAfterTheRequestedEnd() {
        let records = [
            record(at: now.timeIntervalSince1970 - 60),
            record(at: now.timeIntervalSince1970 + 60),
        ]

        let all = SystemMetricsHistorySeriesBuilder.sections(records: records, range: .all, now: now)

        #expect(all.first?.series.first?.points.map(\.date) == [now.addingTimeInterval(-60)])
    }

    @Test @MainActor
    func defaultArchiveKeepsMinuteSamplesWithoutACapacityLimit() {
        let service = SystemMonitorService(historyPersistence: MemoryHistoryPersistence())

        #expect(SystemMetricsHistoryStore.defaultCapacity == nil)
        #expect(SystemMonitorService.defaultHistoryCapacity == nil)
        #expect(service.historyRecordingInterval == 60)
    }

    @Test @MainActor
    func cancellingAStatsLoadDoesNotPublishItsResult() async {
        let persistence = BlockingHistoryPersistence(seed: [record(at: 60)])
        let service = SystemMonitorService(historyPersistence: persistence)
        let load = Task { await service.loadHistoryStats() }

        for await _ in persistence.operationStarted { break }
        load.cancel()
        persistence.release()
        await load.value

        #expect(service.historyStats == .empty)
    }

    @Test(arguments: ["clear", "stop", "disable", "reenable"])
    @MainActor
    func historyLifecycleChangesInvalidateInFlightStatsLoads(action: String) async {
        let persistence = BlockingHistoryPersistence(seed: [record(at: 60)])
        defer { persistence.release() }
        let service = SystemMonitorService(historyPersistence: persistence, isRecordingHistory: true)
        let load = Task { await service.loadHistoryStats() }
        for await _ in persistence.operationStarted { break }
        switch action {
        case "stop": service.stop()
        case "disable": service.setHistoryRecordingEnabled(false)
        case "reenable":
            service.setHistoryRecordingEnabled(false)
            service.setHistoryRecordingEnabled(true)
        default: service.clearHistory()
        }
        persistence.release()
        await load.value

        if action == "clear" || action == "stop" {
            #expect(service.historyStats == .empty)
        }
        await service.loadHistoryStats()
        #expect(service.historyStats.count == (action == "clear" ? 0 : 1))
    }

    @Test(arguments: ["clear", "cancel"])
    @MainActor
    func invalidatedHistorySectionsReturnNoStalePoints(action: String) async {
        let persistence = BlockingHistoryPersistence(seed: [record(at: 60)])
        defer { persistence.release() }
        let service = SystemMonitorService(historyPersistence: persistence)
        let load = Task { await service.historySections(range: .all) }
        for await _ in persistence.operationStarted { break }
        if action == "clear" {
            service.clearHistory()
        } else {
            load.cancel()
        }
        persistence.release()

        #expect(await load.value == [])
        let reloaded = await service.historySections(range: .all)
        #expect(reloaded.isEmpty == (action == "clear"))
    }

    @Test
    func longRangesAreBucketedIntoAveragedPoints() throws {
        let records = (0..<1_000).map { index in
            record(
                at: now.timeIntervalSince1970 - Double(1_000 - index),
                cpuUsage: index < 500 ? 0.2 : 0.8
            )
        }

        let sections = SystemMetricsHistorySeriesBuilder.sections(
            records: records,
            range: .all,
            now: now,
            maximumPoints: 100
        )
        let cpu = try #require(sections.first { $0.id == "cpu" }?.series.first { $0.id == "cpu.usage" })

        #expect(cpu.points.count == 100)
        // Averaging must stay monotonic in time and keep both plateaus visible.
        #expect(cpu.points.first?.value ?? 0 < 0.25)
        #expect(cpu.points.last?.value ?? 0 > 0.75)
        #expect(zip(cpu.points, cpu.points.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    @Test
    func emptyHistoryProducesNoSections() {
        #expect(SystemMetricsHistorySeriesBuilder.sections(records: [], range: .week, now: now).isEmpty)
    }

    @Test
    func fanTitlesFallBackBeyondTwoFans() {
        #expect(SystemMetricsHistorySeriesBuilder.fanTitleKey(for: 0) == "左")
        #expect(SystemMetricsHistorySeriesBuilder.fanTitleKey(for: 1) == "右")
        #expect(SystemMetricsHistorySeriesBuilder.fanTitleKey(for: 2) == "风扇 %ld")
    }
}

struct SystemMetricsHistoryExportTests {
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    @Test @MainActor
    func exportSnapshotsFollowTheOrderOfClearingHistory() async throws {
        let original = record(at: 60, cpuUsage: 0.42)
        let persistence = BlockingHistoryPersistence(seed: [original])
        defer { persistence.release() }
        let service = SystemMonitorService(historyPersistence: persistence)
        let beforeClear = Task { await service.exportHistoryWorkbook(now: now) }
        for await _ in persistence.operationStarted { break }
        service.clearHistory()
        let afterClear = Task { await service.exportHistoryWorkbook(now: now) }
        persistence.release()
        let originalSheet = try #require(try Self.extract(await beforeClear.value)["xl/worksheets/sheet1.xml"])
        let clearedSheet = try #require(try Self.extract(await afterClear.value)["xl/worksheets/sheet1.xml"])

        #expect(originalSheet.components(separatedBy: "<row ").count - 1 == 2)
        #expect(originalSheet.contains("<v>0.42</v>"))
        #expect(clearedSheet.components(separatedBy: "<row ").count - 1 == 1)
        #expect(!clearedSheet.contains("<v>0.42</v>"))
    }

    @Test
    func workbookExportsMeasuredPowerAndLeavesMissingBatteryValuesBlank() throws {
        let workbook = SystemMetricsHistoryExport.workbookData(records: [
            record(at: 100, batteryLevel: 0.8, systemPowerWatts: 24),
            record(at: 160),
            record(at: 220, batteryLevel: 0, systemPowerWatts: 0),
        ])
        let sheet = try #require(try Self.extract(workbook)["xl/worksheets/sheet1.xml"])
        let header = try #require(sheet.components(separatedBy: "<row r=\"1\">").last?.components(separatedBy: "</row>").first)
        let cells = header.components(separatedBy: "<c ").dropFirst()
        func column(_ key: String) throws -> String {
            let cell = try #require(cells.first { $0.contains(">\(key)<") })
            let reference = try #require(cell.components(separatedBy: "r=\"").last?.components(separatedBy: "\"").first)
            return String(reference.dropLast())
        }
        let batteryColumn = try column("battery_level")
        let powerColumn = try column("system_power_watts")
        #expect(sheet.contains("r=\"\(batteryColumn)2\" s=\"0\"><v>0.8</v>"))
        #expect(sheet.contains("r=\"\(powerColumn)2\" s=\"0\"><v>24</v>"))
        #expect(!sheet.contains("r=\"\(batteryColumn)3\""))
        #expect(!sheet.contains("r=\"\(powerColumn)3\""))
        #expect(sheet.contains("r=\"\(powerColumn)4\" s=\"0\"><v>0</v>"))

        let unavailable = try #require(try Self.extract(SystemMetricsHistoryExport.workbookData(
            records: [record(at: 100)]
        ))["xl/worksheets/sheet1.xml"])
        #expect(!unavailable.contains("battery_level"))
        #expect(!unavailable.contains("system_power_watts"))
    }

    @Test
    func excelSerialMatchesTheSpreadsheetEpoch() {
        // 1900-01-01T00:00:00Z is serial 2 in the workbook date system.
        let newYear = Date(timeIntervalSince1970: -2_208_988_800)
        #expect(abs(SystemMetricsHistoryExport.excelSerial(for: newYear, timeZone: .gmt) - 2) < 0.000_001)
        // 1899-12-30T00:00:00Z, two days earlier, is the origin.
        let origin = newYear.addingTimeInterval(-2 * 86_400)
        #expect(abs(SystemMetricsHistoryExport.excelSerial(for: origin, timeZone: .gmt)) < 0.000_001)

        // 2026-09-11T00:00:00Z is serial 46276.
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026,
            month: 9,
            day: 11
        )
        let target = components.date ?? origin
        #expect(abs(SystemMetricsHistoryExport.excelSerial(for: target, timeZone: .gmt) - 46_276) < 0.000_001)
    }

    @Test
    func columnNamesUseSpreadsheetLetters() {
        #expect(SystemMetricsHistoryExport.columnName(1) == "A")
        #expect(SystemMetricsHistoryExport.columnName(26) == "Z")
        #expect(SystemMetricsHistoryExport.columnName(27) == "AA")
        #expect(SystemMetricsHistoryExport.columnName(28) == "AB")
    }

    @Test
    func defaultFileNameIsStableAndUsesTheSpreadsheetExtension() {
        let name = SystemMetricsHistoryExport.defaultFileName(now: now, timeZone: .gmt)
        #expect(name == "zisla-metrics-20260910-002640.xlsx")
    }

    /// The produced archive is checked with the system `unzip`, which proves the hand-rolled
    /// container is a real ZIP rather than only internally consistent.
    @Test
    func workbookIsAValidOOXMLPackage() throws {
        let records = [
            record(at: now.timeIntervalSince1970 - 60, gpuUsage: 0.42, fanRPMs: [1_200, 1_400]),
            record(at: now.timeIntervalSince1970, gpuUsage: 0.55, fanRPMs: [1_300, 1_500]),
        ]
        let workbook = SystemMetricsHistoryExport.workbookData(
            records: records,
            timeZone: .gmt,
            modificationDate: now
        )

        let extracted = try Self.extract(workbook)
        let sheet = try #require(extracted["xl/worksheets/sheet1.xml"])
        #expect(extracted.count == 6)
        #expect(extracted["[Content_Types].xml"]?.contains("spreadsheetml.sheet.main+xml") == true)
        #expect(extracted["xl/workbook.xml"]?.contains("<sheet name=\"Zisla Metrics\"") == true)
        #expect(sheet.contains("t=\"inlineStr\""))
        #expect(sheet.contains(">timestamp<"))
        #expect(sheet.contains(">cpu_usage<"))
        #expect(sheet.contains(">fan_2_rpm<"))
        // Two data rows plus the header row.
        #expect(sheet.components(separatedBy: "<row ").count - 1 == 3)
    }

    @Test
    func workbookOmitsFanColumnsWhenNoFanWasReported() throws {
        let workbook = SystemMetricsHistoryExport.workbookData(
            records: [record(at: now.timeIntervalSince1970)],
            timeZone: .gmt,
            modificationDate: now
        )

        let sheet = try #require(try Self.extract(workbook)["xl/worksheets/sheet1.xml"])
        #expect(!sheet.contains("fan_1_rpm"))
        #expect(sheet.contains(">network_sent_bytes<"))
    }

    /// Counters this machine never reported would only produce empty columns, so the header row
    /// shrinks to what actually exists — gpu_usage stays, renderer/tiler/temperatures go.
    @Test
    func workbookOmitsColumnsTheMachineNeverReported() throws {
        let workbook = SystemMetricsHistoryExport.workbookData(
            records: [
                record(at: now.timeIntervalSince1970 - 60, gpuUsage: 0.42, fanRPMs: [1_200]),
                record(at: now.timeIntervalSince1970, gpuUsage: 0.55, fanRPMs: [1_300]),
            ],
            timeZone: .gmt,
            modificationDate: now
        )

        let sheet = try #require(try Self.extract(workbook)["xl/worksheets/sheet1.xml"])
        #expect(sheet.contains(">gpu_usage<"))
        #expect(!sheet.contains("gpu_renderer"))
        #expect(!sheet.contains("gpu_tiler"))
        #expect(!sheet.contains("temperature"))
    }

    @Test
    func workbookOmitsEveryGpuColumnWhenGpuIsUnavailable() throws {
        let workbook = SystemMetricsHistoryExport.workbookData(
            records: [record(at: now.timeIntervalSince1970)],
            timeZone: .gmt,
            modificationDate: now
        )

        let sheet = try #require(try Self.extract(workbook)["xl/worksheets/sheet1.xml"])
        #expect(!sheet.contains("gpu_"))
    }

    fileprivate static func extract(_ workbook: Data) throws -> [String: String] {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zisla-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let archive = directory.appendingPathComponent("workbook.xlsx")
        try workbook.write(to: archive)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", archive.path, "-d", directory.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "unzip rejected the generated workbook")

        var parts: [String: String] = [:]
        for part in ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"] {
            let url = directory.appendingPathComponent(part)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                parts[part] = text
            }
        }
        return parts
    }
}

struct SystemMetricsHistoryDatabaseTests {
    @Test(arguments: [nil, -1, 0, 1, 2, 8] as [Int?])
    func summariesMatchRetainedRecordsWithoutPruningTheArchive(capacity: Int?) throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        let persistence = LazySystemMetricsHistoryPersistence(makeDatabase: { database })
        #expect(persistence.loadStats(capacity: capacity) == .empty)
        for timestamp in [180.0, 60, 120, 120] {
            database.appendRecord(record(at: timestamp, fanRPMs: [1_200, 1_400]), capacity: nil)
        }
        let expected = [60.0, 120, 180].suffix(capacity.map { max(1, $0) } ?? 3)

        #expect(persistence.loadStats(capacity: capacity) == SystemMetricsHistoryStats(
            count: expected.count,
            oldest: expected.first.map { Date(timeIntervalSince1970: $0) },
            newest: expected.last.map { Date(timeIntervalSince1970: $0) }
        ))
        #expect(database.loadRecords().count == 3, "Loading a summary must not apply retention to disk")

        persistence.removeAll()
        #expect(persistence.loadStats(capacity: capacity) == .empty)
    }

    @Test
    func summariesStayAvailableWhenFanRecordsCannotBeRead() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        let persistence = LazySystemMetricsHistoryPersistence(makeDatabase: { database })
        database.appendRecord(record(at: 60, fanRPMs: [1_200]), capacity: nil)
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let inspection = try #require(connection)
        defer { sqlite3_close(inspection) }
        #expect(sqlite3_exec(inspection, "ALTER TABLE metric_fans RENAME TO unavailable_fans", nil, nil, nil) == SQLITE_OK)

        #expect(persistence.loadRecords().isEmpty)
        #expect(persistence.loadStats(capacity: nil) == SystemMetricsHistoryStats(
            count: 1,
            oldest: Date(timeIntervalSince1970: 60),
            newest: Date(timeIntervalSince1970: 60)
        ), "A summary must read only the timestamp index, without decoding metric or fan records")
    }

    @Test
    func summaryReadsRecoverAfterATransientQueryFailure() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        database.appendRecord(record(at: 60), capacity: nil)
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let inspection = try #require(connection)
        defer { sqlite3_close(inspection) }
        #expect(sqlite3_exec(inspection, "ALTER TABLE metrics RENAME TO unavailable_metrics", nil, nil, nil) == SQLITE_OK)
        #expect(database.loadStats(capacity: nil) == nil)

        #expect(sqlite3_exec(inspection, "ALTER TABLE unavailable_metrics RENAME TO metrics", nil, nil, nil) == SQLITE_OK)
        #expect(database.loadStats(capacity: nil)?.count == 1)
        #expect(database.loadRecords() == [record(at: 60)])
    }

    @Test
    func repeatedSummaryReadsKeepTheLastSnapshotWhileStorageIsUnavailable() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        let store = SystemMetricsHistoryStore(persistence: database)
        store.append(record(at: 60))
        let expected = store.stats
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let inspection = try #require(connection)
        defer { sqlite3_close(inspection) }
        #expect(sqlite3_exec(inspection, "ALTER TABLE metrics RENAME TO unavailable_metrics", nil, nil, nil) == SQLITE_OK)
        #expect(database.loadStats(capacity: nil) == nil)

        store.append(record(at: 120))
        #expect(store.stats == expected,
                "A failed recording refresh must preserve the last successfully read summary")
        for _ in 0..<3 {
            #expect(store.stats == expected, "Reading a displayed snapshot must not require another storage read")
        }
        #expect(sqlite3_exec(inspection, "ALTER TABLE unavailable_metrics RENAME TO metrics", nil, nil, nil) == SQLITE_OK)
        #expect(store.stats == expected)
        store.append(record(at: 120))
        #expect(store.stats.count == 2)
        #expect(store.stats.newest == Date(timeIntervalSince1970: 120))
        database.removeAll()
        #expect(store.stats.count == 2)
        #expect(sqlite3_exec(inspection, """
            CREATE TRIGGER reject_record BEFORE INSERT ON metrics
            BEGIN SELECT RAISE(ABORT, 'injected recording failure'); END;
            """, nil, nil, nil) == SQLITE_OK)
        store.append(record(at: 180))
        #expect(store.stats == .empty, "A successfully read empty archive must replace the cached summary")
    }

    @Test
    func summariesAndRecordingTolerateAnUnavailableDatabase() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let blockedParent = url.deletingLastPathComponent().appendingPathComponent("not-a-directory")
        try Data().write(to: blockedParent)
        let store = SystemMetricsHistoryStore(persistence: SystemMetricsHistoryDatabase(
            databaseURL: blockedParent.appendingPathComponent("history.sqlite")
        ))

        #expect(store.stats == .empty)
        store.append(record(at: 60))
        #expect(store.stats == .empty)
        #expect(store.records.isEmpty)
        #expect(try Data(contentsOf: blockedParent).isEmpty)
    }

    @Test(arguments: [nil, 2] as [Int?])
    func storeSummariesTrackReplacedAndOutOfOrderSamples(capacity: Int?) throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        let store = SystemMetricsHistoryStore(persistence: database, capacity: capacity)
        for timestamp in [180.0, 60, 120, 120, 240] {
            store.append(record(at: timestamp))
            let records = database.loadRecords()
            #expect(store.records == records)
            #expect(store.stats == SystemMetricsHistoryStats(
                count: records.count,
                oldest: records.first?.timestamp,
                newest: records.last?.timestamp
            ))
        }
    }

    @Test
    func failedWritesAndClearsKeepTheStoreConsistentWithTheArchive() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        let store = SystemMetricsHistoryStore(persistence: database)
        let original = record(at: 60, fanRPMs: [900])
        store.append(original)
        let originalStats = store.stats
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let inspection = try #require(connection)
        defer { sqlite3_close(inspection) }
        #expect(sqlite3_exec(inspection, """
            CREATE TRIGGER fail_write BEFORE INSERT ON metric_fans
            WHEN NEW.rpm = -1 BEGIN SELECT RAISE(ABORT, 'injected write failure'); END;
            CREATE TRIGGER fail_clear BEFORE DELETE ON metrics
            BEGIN SELECT RAISE(ABORT, 'injected clear failure'); END;
            CREATE TRIGGER fail_clear_fans BEFORE DELETE ON metric_fans
            BEGIN SELECT RAISE(ABORT, 'injected clear failure'); END;
            """, nil, nil, nil) == SQLITE_OK)

        store.append(record(at: 120, fanRPMs: [-1]))
        #expect(store.stats == originalStats)
        #expect(store.records == [original])
        store.removeAll()
        #expect(store.stats == originalStats)
        #expect(store.records == [original])

        #expect(sqlite3_exec(inspection, "DROP TRIGGER fail_write; DROP TRIGGER fail_clear; DROP TRIGGER fail_clear_fans", nil, nil, nil) == SQLITE_OK)
        store.removeAll()
        #expect(store.stats == .empty)
        let recovered = record(at: 180)
        store.append(recovered)
        #expect(store.records == [recovered])
        #expect(store.stats.count == 1)
    }

    @Test
    func unlimitedDatabaseAndLazyPersistenceKeepSamplesUntilExplicitlyCleared() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        let persistence = LazySystemMetricsHistoryPersistence(makeDatabase: { database })
        for timestamp in [180.0, 60, 120] {
            persistence.appendRecord(record(at: timestamp, fanRPMs: [1_000]), capacity: nil)
        }
        database.appendRecord(record(at: 120, fanRPMs: [2_000, 2_100]), capacity: nil)

        let reloaded = persistence.loadRecords()
        #expect(reloaded.map(\.timestamp.timeIntervalSince1970) == [60, 120, 180])
        #expect(reloaded[0].fanRPMs == [1_000])
        #expect(reloaded[1].fanRPMs == [2_000, 2_100])

        persistence.removeAll()
        #expect(database.loadRecords().isEmpty)
        database.appendRecord(record(at: 240), capacity: nil)
        #expect(SystemMetricsHistoryDatabase(databaseURL: url).loadRecords() == [record(at: 240)])
    }

    @Test(arguments: [0, -1, Int.min])
    func explicitNonPositiveCapacityKeepsOneSample(capacity: Int) throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        for timestamp in [60.0, 120, 180] {
            database.appendRecord(record(at: timestamp), capacity: capacity)
        }

        #expect(database.loadRecords().map(\.timestamp.timeIntervalSince1970) == [180])
    }

    @Test
    func unlimitedAppendRollsBackFailedWritesWithoutLosingExistingSamples() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        let original = record(at: 60, fanRPMs: [900])
        database.appendRecord(original, capacity: nil)
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let inspection = try #require(connection)
        defer { sqlite3_close(inspection) }
        #expect(sqlite3_exec(inspection, """
            CREATE TRIGGER fail_fan_write BEFORE INSERT ON metric_fans
            WHEN NEW.rpm = -1 BEGIN SELECT RAISE(ABORT, 'injected fan write failure'); END;
            """, nil, nil, nil) == SQLITE_OK)

        for timestamp in [120.0, 60] {
            database.appendRecord(record(at: timestamp, fanRPMs: [-1]), capacity: nil)
            #expect(database.loadRecords() == [original])
            #expect(SystemMetricsHistoryDatabase(databaseURL: url).loadRecords() == [original])
        }

        #expect(sqlite3_exec(inspection, "DROP TRIGGER fail_fan_write", nil, nil, nil) == SQLITE_OK)
        let recovered = record(at: 120, fanRPMs: [1_000])
        database.appendRecord(recovered, capacity: nil)
        #expect(SystemMetricsHistoryDatabase(databaseURL: url).loadRecords() == [original, recovered])
    }

    @Test
    func defaultCapacityPreservesOversizedLegacyArchiveWhenRecordingAndReopening() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let sampleCount = 64_000
        try createLegacyDatabase(at: url, sampleCount: sampleCount)
        let store = SystemMetricsHistoryStore(
            persistence: SystemMetricsHistoryDatabase(databaseURL: url)
        )

        #expect(store.stats.count == sampleCount)
        #expect(store.stats.oldest?.timeIntervalSince1970 == 1_000)
        #expect(store.stats.newest?.timeIntervalSince1970 == 1_000 + Double(sampleCount - 1) * 60)

        let appended = record(
            at: 1_000 + Double(sampleCount) * 60,
            fanRPMs: [1_200, 1_400], batteryLevel: 0.8, systemPowerWatts: 24
        )
        store.append(appended)

        let reopened = SystemMetricsHistoryStore(
            persistence: SystemMetricsHistoryDatabase(databaseURL: url)
        )
        #expect(reopened.stats.count == sampleCount + 1)
        #expect(reopened.stats.oldest?.timeIntervalSince1970 == 1_000)
        #expect(reopened.records.last == appended)
        #expect(reopened.records.enumerated().allSatisfy { index, sample in
            sample.timestamp.timeIntervalSince1970 == 1_000 + Double(index) * 60
        })
    }

    @Test
    func oldRecordsDecodeWithMissingBatteryFields() throws {
        let encoded = try JSONEncoder().encode(record(at: 100))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "batteryLevel")
        object.removeValue(forKey: "systemPowerWatts")
        let decoded = try JSONDecoder().decode(SystemMetricsRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.batteryLevel == nil)
        #expect(decoded.systemPowerWatts == nil)
        #expect(decoded.cpuUsage == 0.25)
    }

    @Test(arguments: [false, true])
    func legacyDatabaseAddsNullableBatteryColumnsWithoutLosingOldRecords(hasBatteryColumn: Bool) throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        try createLegacyDatabase(at: url, additionalColumns: hasBatteryColumn ? ["battery_level REAL"] : [])
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        let migrated = try #require(database.loadRecords().first)
        #expect(migrated.timestamp == Date(timeIntervalSince1970: 1_000))
        #expect(migrated.cpuUsage == 0.25)
        #expect(migrated.memoryUsedBytes == 8_000)
        #expect(migrated.batteryLevel == nil && migrated.systemPowerWatts == nil)
        database.appendRecord(record(at: 1_060, batteryLevel: 0.8, systemPowerWatts: 24), capacity: 10)
        database.appendRecord(record(at: 1_120, batteryLevel: 0, systemPowerWatts: 0), capacity: 10)
        database.appendRecord(record(at: 1_180), capacity: 10)
        let reloaded = SystemMetricsHistoryDatabase(databaseURL: url).loadRecords()
        #expect(reloaded.count == 4)
        #expect(reloaded.map(\.batteryLevel) == [nil, 0.8, 0, nil])
        #expect(reloaded.map(\.systemPowerWatts) == [nil, 24, 0, nil])
        let workbook = SystemMetricsHistoryExport.workbookData(records: reloaded)
        let sheet = try #require(try SystemMetricsHistoryExportTests.extract(workbook)["xl/worksheets/sheet1.xml"])
        #expect(sheet.contains(">battery_level<"))
        #expect(sheet.contains(">system_power_watts<"))
        #expect(sheet.components(separatedBy: "<row ").count - 1 == 5)
    }

    @Test
    func failedBatteryMigrationRollsBackBothColumnsAndCanRecover() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let inspection = try #require(connection)
        defer { sqlite3_close(inspection) }
        let columnLimit = Int(sqlite3_limit(inspection, SQLITE_LIMIT_COLUMN, -1))
        // Leave room for one column so the second ALTER fails after the first has run.
        let additionalColumns = (0..<(columnLimit - 23)).map { "reserved_\($0) REAL" }
        try createLegacyDatabase(at: url, additionalColumns: additionalColumns)
        #expect(SystemMetricsHistoryDatabase(databaseURL: url).loadRecords().isEmpty)
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(inspection, "SELECT name FROM pragma_table_info('metrics')", -1, &statement, nil) == SQLITE_OK)
        let columnsQuery = try #require(statement)
        defer { sqlite3_finalize(columnsQuery) }
        var columns: [String] = []
        while sqlite3_step(columnsQuery) == SQLITE_ROW {
            if let name = sqlite3_column_text(columnsQuery, 0) { columns.append(String(cString: name)) }
        }
        #expect(columns.count == columnLimit - 1)
        #expect(!columns.contains("battery_level"))
        #expect(!columns.contains("system_power_watts"))
        #expect(sqlite3_exec(inspection, "ALTER TABLE metrics DROP COLUMN reserved_0", nil, nil, nil) == SQLITE_OK)
        let recovered = try #require(SystemMetricsHistoryDatabase(databaseURL: url).loadRecords().first)
        #expect(recovered.cpuUsage == 0.25)
        #expect(recovered.batteryLevel == nil && recovered.systemPowerWatts == nil)
    }

    @Test
    func samplesRoundTripThroughSQLite() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        database.appendRecord(
            record(at: 1_000, gpuUsage: 0.5, fanRPMs: [1_200, 1_400], memoryUsed: 8_000, memoryTotal: 16_000),
            capacity: 10
        )
        database.appendRecord(record(at: 1_060), capacity: 10)

        let reloaded = SystemMetricsHistoryDatabase(databaseURL: url).loadRecords()

        #expect(reloaded.count == 2)
        #expect(reloaded.map(\.timestamp.timeIntervalSince1970) == [1_000, 1_060])
        #expect(reloaded[0].cpuUsage == 0.25)
        #expect(reloaded[0].cpuUser == 0.2)
        #expect(reloaded[0].gpuUsage == 0.5)
        #expect(reloaded[0].memoryUsedBytes == 8_000)
        #expect(reloaded[0].memoryTotalBytes == 16_000)
        #expect(reloaded[0].fanRPMs == [1_200, 1_400])
        #expect(reloaded[0].diskReadBytesPerSecond == 1_024)
        #expect(reloaded[0].networkSendBytesPerSecond == 20)
    }

    @Test
    func unavailableCountersStayUnsetInsteadOfBecomingZero() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        database.appendRecord(record(at: 1_000), capacity: 10)

        let reloaded = database.loadRecords()

        #expect(reloaded.count == 1)
        #expect(reloaded[0].gpuUsage == nil)
        #expect(reloaded[0].gpuRenderer == nil)
        #expect(reloaded[0].gpuTiler == nil)
        #expect(reloaded[0].cpuTemperatureCelsius == nil)
        #expect(reloaded[0].diskTemperatureCelsius == nil)
        #expect(reloaded[0].fanRPMs.isEmpty)
    }

    @Test
    func samplesAreReadOldestFirstRegardlessOfInsertOrder() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        for timestamp in [300.0, 60, 180, 120] {
            database.appendRecord(record(at: timestamp), capacity: 10)
        }

        #expect(database.loadRecords().map(\.timestamp.timeIntervalSince1970) == [60, 120, 180, 300])
    }

    @Test
    func capacityDropsTheOldestSamplesFromTheArchive() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)

        for index in 0..<5 {
            database.appendRecord(record(at: Double(index) * 60), capacity: 3)
        }

        #expect(database.loadRecords().map(\.timestamp.timeIntervalSince1970) == [120, 180, 240])
    }

    @Test
    func recordingTheSameTimestampReplacesItsFanReadings() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        database.appendRecord(record(at: 60, fanRPMs: [1_000, 1_100]), capacity: 10)
        database.appendRecord(record(at: 60, fanRPMs: [2_000]), capacity: 10)

        let reloaded = database.loadRecords()

        #expect(reloaded.count == 1)
        #expect(reloaded[0].fanRPMs == [2_000])
    }

    @Test
    func pruningRemovesTheFanRowsOfDroppedSamples() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        database.appendRecord(record(at: 60, fanRPMs: [1_000, 1_100]), capacity: 1)
        database.appendRecord(record(at: 120, fanRPMs: [2_000, 2_100]), capacity: 1)

        let reloaded = database.loadRecords()

        #expect(reloaded.count == 1)
        #expect(reloaded[0].timestamp.timeIntervalSince1970 == 120)
        #expect(reloaded[0].fanRPMs == [2_000, 2_100])
    }

    @Test
    func removingEverythingLeavesAnEmptyArchive() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        database.appendRecord(record(at: 60, fanRPMs: [900]), capacity: 10)

        database.removeAll()

        #expect(database.loadRecords().isEmpty)
        // A later sample still records, so clearing is not a one-way door.
        database.appendRecord(record(at: 120), capacity: 10)
        #expect(database.loadRecords().map(\.timestamp.timeIntervalSince1970) == [120])
    }

    /// A truncated or foreign file used to be skipped line by line; the archive must recover the same
    /// way rather than disabling recording for the rest of the process.
    @Test
    func aFileThatIsNotADatabaseIsReplacedInsteadOfDisablingRecording() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        try Data("this is not a sqlite database".utf8).write(to: url)

        let database = SystemMetricsHistoryDatabase(databaseURL: url)
        database.appendRecord(record(at: 60, fanRPMs: [1_500]), capacity: 10)

        #expect(database.loadRecords().map(\.timestamp.timeIntervalSince1970) == [60])
        // The replacement is a real archive, not an in-memory fallback.
        #expect(
            SystemMetricsHistoryDatabase(databaseURL: url).loadRecords().map(\.timestamp.timeIntervalSince1970)
                == [60]
        )
    }

    @Test
    func theArchiveIsOnlyReadableByItsOwner() throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        SystemMetricsHistoryDatabase(databaseURL: url).appendRecord(record(at: 60), capacity: 10)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(permissions & 0o777 == 0o600)
    }

    private func createLegacyDatabase(
        at url: URL, additionalColumns: [String] = [], sampleCount: Int = 1
    ) throws {
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let legacy = try #require(connection)
        defer { sqlite3_close(legacy) }
        let schema = """
        CREATE TABLE metrics (
            timestamp REAL PRIMARY KEY, cpu_usage REAL NOT NULL, cpu_user REAL NOT NULL,
            cpu_system REAL NOT NULL, cpu_idle REAL NOT NULL, cpu_temperature REAL,
            gpu_usage REAL, gpu_renderer REAL, gpu_tiler REAL, gpu_temperature REAL,
            memory_used_bytes INTEGER NOT NULL, memory_total_bytes INTEGER NOT NULL,
            memory_pressure_ratio REAL NOT NULL, disk_used_bytes INTEGER NOT NULL,
            disk_total_bytes INTEGER NOT NULL, disk_read_bytes_per_second REAL,
            disk_write_bytes_per_second REAL, disk_temperature REAL,
            network_receive_bytes_per_second REAL NOT NULL, network_send_bytes_per_second REAL NOT NULL,
            network_received_bytes INTEGER NOT NULL, network_sent_bytes INTEGER NOT NULL
            \(additionalColumns.map { ", " + $0 }.joined())
        );
        WITH RECURSIVE samples(sample_index) AS (
            SELECT 0
            UNION ALL
            SELECT sample_index + 1 FROM samples WHERE sample_index + 1 < \(sampleCount)
        )
        INSERT INTO metrics (
            timestamp, cpu_usage, cpu_user, cpu_system, cpu_idle,
            memory_used_bytes, memory_total_bytes, memory_pressure_ratio, disk_used_bytes, disk_total_bytes,
            network_receive_bytes_per_second, network_send_bytes_per_second, network_received_bytes, network_sent_bytes
        ) SELECT 1000 + sample_index * 60, 0.25, 0.2, 0.05, 0.75,
                 8000, 16000, 0.1, 100, 200, 10, 20, 0, 0 FROM samples;
        """
        #expect(sqlite3_exec(legacy, schema, nil, nil, nil) == SQLITE_OK)
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zisla-history-database-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.sqlite")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
