import Foundation
import Testing

@testable import ZislaKit

/// In-memory stand-in for the history log so the store logic can be exercised without touching disk.
private final class MemoryHistoryPersistence: SystemMetricsHistoryPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SystemMetricsRecord] = []
    private(set) var appendCount = 0
    private(set) var replaceCount = 0

    init(seed: [SystemMetricsRecord] = []) {
        stored = seed
    }

    func loadRecords() -> [SystemMetricsRecord] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func appendRecord(_ record: SystemMetricsRecord) {
        lock.lock()
        defer { lock.unlock() }
        stored.append(record)
        appendCount += 1
    }

    func replaceRecords(_ records: [SystemMetricsRecord]) {
        lock.lock()
        defer { lock.unlock() }
        stored = records
        replaceCount += 1
    }
}

private func record(
    at seconds: TimeInterval,
    cpuUsage: Double = 0.25,
    gpuUsage: Double? = nil,
    fanRPMs: [Double] = [],
    memoryUsed: UInt64 = 8_000,
    memoryTotal: UInt64 = 16_000
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
        networkSendBytesPerSecond: 20
    )
}

struct SystemMetricsHistoryStoreTests {
    @Test
    func appendKeepsTheLogAppendOnlyUntilCapacity() {
        let persistence = MemoryHistoryPersistence()
        let store = SystemMetricsHistoryStore(persistence: persistence, capacity: 3)

        for index in 0..<3 {
            store.append(record(at: TimeInterval(index)))
        }

        #expect(persistence.appendCount == 3)
        #expect(persistence.replaceCount == 0)
        #expect(store.records.map(\.timestamp.timeIntervalSince1970) == [0, 1, 2])
    }

    @Test
    func overflowDropsOldestSamplesAndRewritesTheLog() {
        let persistence = MemoryHistoryPersistence()
        let store = SystemMetricsHistoryStore(persistence: persistence, capacity: 2)

        for index in 0..<4 {
            store.append(record(at: TimeInterval(index)))
        }

        #expect(persistence.appendCount == 2)
        #expect(persistence.replaceCount == 2)
        #expect(store.records.map(\.timestamp.timeIntervalSince1970) == [2, 3])
        #expect(store.stats.count == 2)
        #expect(store.stats.oldest?.timeIntervalSince1970 == 2)
        #expect(store.stats.newest?.timeIntervalSince1970 == 3)
        #expect(store.stats.span == 1)
    }

    @Test
    func loadTrimsOversizedLogsAndSortsByTime() {
        let seed = [record(at: 5), record(at: 1), record(at: 3)]
        let store = SystemMetricsHistoryStore(persistence: MemoryHistoryPersistence(seed: seed), capacity: 2)

        #expect(store.records.map(\.timestamp.timeIntervalSince1970) == [3, 5])
    }

    @Test
    func removeAllEmptiesTheLog() {
        let persistence = MemoryHistoryPersistence(seed: [record(at: 1)])
        let store = SystemMetricsHistoryStore(persistence: persistence, capacity: 8)
        #expect(store.stats.count == 1)

        store.removeAll()

        #expect(store.records.isEmpty)
        #expect(store.stats == .empty)
        #expect(persistence.loadRecords().isEmpty)
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

    private static func extract(_ workbook: Data) throws -> [String: String] {
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

struct SystemMetricsFileHistoryPersistenceTests {
    @Test
    func appendAndLoadRoundTripThroughJSONLines() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zisla-history-file-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.jsonl")

        let persistence = SystemMetricsFileHistoryPersistence(fileURL: url)
        persistence.appendRecord(record(at: 10, gpuUsage: 0.5))
        persistence.appendRecord(record(at: 20, fanRPMs: [900]))

        let reloaded = SystemMetricsFileHistoryPersistence(fileURL: url).loadRecords()

        #expect(reloaded.count == 2)
        #expect(reloaded[0].gpuUsage == 0.5)
        #expect(reloaded[1].fanRPMs == [900])
    }

    @Test
    func corruptLinesAreSkippedInsteadOfFailingTheLoad() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zisla-history-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.jsonl")

        let persistence = SystemMetricsFileHistoryPersistence(fileURL: url)
        persistence.appendRecord(record(at: 10))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{ not json }\n".utf8))
        try handle.close()
        persistence.appendRecord(record(at: 20))

        #expect(persistence.loadRecords().map(\.timestamp.timeIntervalSince1970) == [10, 20])
    }

    @Test
    func replaceRecordsTruncatesTheLog() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zisla-history-replace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.jsonl")

        let persistence = SystemMetricsFileHistoryPersistence(fileURL: url)
        persistence.appendRecord(record(at: 10))
        persistence.replaceRecords([record(at: 20)])

        #expect(persistence.loadRecords().map(\.timestamp.timeIntervalSince1970) == [20])
        persistence.replaceRecords([])
        #expect(persistence.loadRecords().isEmpty)
    }
}
