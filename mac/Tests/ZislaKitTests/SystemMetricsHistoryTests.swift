import Foundation
import SQLite3
import Testing

@testable import ZislaKit

/// In-memory stand-in for the history archive so the store logic can be exercised without touching disk.
final class MemoryHistoryPersistence: SystemMetricsHistoryPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SystemMetricsRecord] = []
    private(set) var appendCount = 0
    private(set) var appendedCapacities: [Int] = []
    private(set) var removeAllCount = 0

    init(seed: [SystemMetricsRecord] = []) {
        stored = seed
    }

    func loadRecords() -> [SystemMetricsRecord] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func appendRecord(_ record: SystemMetricsRecord, capacity: Int) {
        lock.lock()
        defer { lock.unlock() }
        stored.append(record)
        appendCount += 1
        appendedCapacities.append(capacity)
        let overflow = stored.count - max(1, capacity)
        if overflow > 0 {
            stored.removeFirst(overflow)
        }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        stored = []
        removeAllCount += 1
    }
}

private final class BlockingHistoryPersistence: SystemMetricsHistoryPersisting, @unchecked Sendable {
    private let condition = NSCondition()
    private var stored: [SystemMetricsRecord]
    private var loadCanFinish = false
    let loadStarted: AsyncStream<Void>
    private let loadStartedContinuation: AsyncStream<Void>.Continuation

    init(seed: [SystemMetricsRecord]) {
        stored = seed
        (loadStarted, loadStartedContinuation) = AsyncStream<Void>.makeStream()
    }

    func loadRecords() -> [SystemMetricsRecord] {
        condition.lock()
        loadStartedContinuation.yield(())
        loadStartedContinuation.finish()
        while !loadCanFinish {
            condition.wait()
        }
        let records = stored
        condition.unlock()
        return records
    }

    func appendRecord(_ record: SystemMetricsRecord, capacity: Int) {
        condition.lock()
        stored.append(record)
        stored = Array(stored.suffix(max(1, capacity)))
        condition.unlock()
    }

    func removeAll() {
        condition.lock()
        stored = []
        condition.unlock()
    }

    func releaseLoad() {
        condition.lock()
        loadCanFinish = true
        condition.broadcast()
        condition.unlock()
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

    @Test
    func removeAllEmptiesTheArchive() {
        let persistence = MemoryHistoryPersistence(seed: [record(at: 1)])
        let store = SystemMetricsHistoryStore(persistence: persistence, capacity: 8)
        #expect(store.stats.count == 1)

        store.removeAll()

        #expect(store.records.isEmpty)
        #expect(store.stats == .empty)
        #expect(persistence.loadRecords().isEmpty)
        #expect(persistence.removeAllCount == 1)
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
    func defaultArchiveCapacityCoversThirtyDaysOfMinuteSamples() {
        let service = SystemMonitorService(historyPersistence: MemoryHistoryPersistence())

        #expect(SystemMetricsHistoryStore.defaultCapacity == 30 * 24 * 60)
        #expect(SystemMonitorService.defaultHistoryCapacity == 30 * 24 * 60)
        #expect(service.historyRecordingInterval == 60)
    }

    @Test @MainActor
    func cancellingAStatsLoadDoesNotPublishItsResult() async {
        let persistence = BlockingHistoryPersistence(seed: [record(at: 60)])
        let service = SystemMonitorService(historyPersistence: persistence)
        let load = Task { await service.loadHistoryStats() }

        for await _ in persistence.loadStarted { break }
        load.cancel()
        persistence.releaseLoad()
        await load.value

        #expect(service.historyStats == .empty)
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

    private func createLegacyDatabase(at url: URL, additionalColumns: [String] = []) throws {
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
        INSERT INTO metrics (
            timestamp, cpu_usage, cpu_user, cpu_system, cpu_idle,
            memory_used_bytes, memory_total_bytes, memory_pressure_ratio, disk_used_bytes, disk_total_bytes,
            network_receive_bytes_per_second, network_send_bytes_per_second, network_received_bytes, network_sent_bytes
        ) VALUES (1000, 0.25, 0.2, 0.05, 0.75, 8000, 16000, 0.1, 100, 200, 10, 20, 0, 0);
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
