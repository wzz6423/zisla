import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIUsageHistoryTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    /// Whole-day ranges include midnight rows and empty days; selecting one date cannot show another date's models.
    @Test
    func rangesAndSelectionPreserveEmptyDaysAndExactDateBounds() throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11)))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let samples = [sample(at: yesterday, input: 30), sample(at: today, input: 10), sample(at: tomorrow, input: 99)]
        let history = AIUsageHistory(usageSamples: samples, modelUsageSamples: samples)
        for (range, days) in [(SystemMetricsHistoryRange.day, 1), (.week, 7), (.month, 30)] {
            let domain = AIUsageHistoryPresentation.domain(history: history, range: range, now: today, calendar: calendar)
            #expect(domain.lowerBound == calendar.date(byAdding: .day, value: -(days - 1), to: today))
            #expect(domain.upperBound == tomorrow)
            let trend = AIUsageHistoryPresentation.trend(history: history, domain: domain, calendar: calendar)
            #expect(trend.count == days)
            #expect(trend.last?.totalTokens == 12)
            #expect(trend.allSatisfy { $0.totalTokens != 101 })
        }
        let selected = AIUsageHistoryPresentation.selectedDay(in: history, date: today.addingTimeInterval(3600), calendar: calendar)
        #expect(selected.date == today && selected.totalTokens == 12)
        #expect(selected.models.map(\.model) == ["fixture-model"])
        let emptyDate = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let empty = AIUsageHistoryPresentation.selectedDay(in: history, date: emptyDate, calendar: calendar)
        #expect(empty.date == emptyDate && empty.totalTokens == 0 && empty.models.isEmpty)
        let emptyDomain = AIUsageHistoryPresentation.domain(history: .init(), range: .all, now: today, calendar: calendar)
        #expect(emptyDomain == today...tomorrow)
    }

    /// A sparse archive spanning millennia must not allocate an array for every intervening zero day.
    @Test
    func allHistoryTrendKeepsEndpointsAndPeaksWithinThePointBudget() throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11)))
        let oldest = try #require(calendar.date(from: DateComponents(year: 1, month: 1, day: 1)))
        let peak = try #require(calendar.date(from: DateComponents(year: 1200, month: 8, day: 4)))
        let history = AIUsageHistory(usageSamples: [sample(at: oldest, input: 5), sample(at: peak, input: Int.max), sample(at: today, input: 8)])
        let domain = AIUsageHistoryPresentation.domain(history: history, range: .all, now: today, calendar: calendar)
        for budget in [3, 17, 240] {
            let points = AIUsageHistoryPresentation.trend(history: history, domain: domain, maximumPoints: budget, calendar: calendar)
            #expect(points.count <= budget)
            #expect(calendar.isDate(try #require(points.first).timestamp, inSameDayAs: oldest))
            #expect(calendar.isDate(try #require(points.last).timestamp, inSameDayAs: today))
            #expect(points.contains { $0.totalTokens == Int.max })
            #expect(zip(points, points.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp })
        }
        let ancient = Date(timeIntervalSince1970: -1_000_000_000_000)
        let distantHistory = AIUsageHistory(usageSamples: [sample(at: ancient, input: 1), sample(at: today, input: 2)])
        let distantDomain = AIUsageHistoryPresentation.domain(history: distantHistory, range: .all, now: today, calendar: calendar)
        #expect(AIUsageHistoryPresentation.trend(history: distantHistory, domain: distantDomain, calendar: calendar).count <= 240)
    }

    /// The budget boundary is also checked with a compact fixture suitable for removing bucketing in a bounded experiment.
    @Test
    func trendBudgetBoundsACompactMultiYearFixture() throws {
        let start = try #require(calendar.date(from: DateComponents(year: 2025, month: 1, day: 1)))
        let end = try #require(calendar.date(byAdding: .day, value: 512, to: start))
        let peak = try #require(calendar.date(byAdding: .day, value: 255, to: start))
        let history = AIUsageHistory(usageSamples: [sample(at: start, input: 1), sample(at: peak, input: 999)])
        let points = AIUsageHistoryPresentation.trend(history: history, domain: start...end, maximumPoints: 16, calendar: calendar)
        #expect(points.count <= 16 && points.contains { $0.totalTokens == 1001 })
        #expect(points.contains { $0.totalTokens == 0 })
    }

    /// Year pages retain only dates inside the archive and requested year, including leap days and zero-usage cells.
    @Test
    func heatmapPagesStayBoundedAndShareTheSelectedCalendarDates() throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11)))
        let leap = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 29)))
        let history = AIUsageHistory(usageSamples: [sample(at: leap, input: 10)])
        let domain = AIUsageHistoryPresentation.domain(history: history, range: .all, now: today, calendar: calendar)
        let weeks = AIUsageHistoryPresentation.heatmap(history: history, domain: domain, year: leap, now: today, calendar: calendar)
        let days = weeks.flatMap { $0 }.compactMap { $0 }
        #expect(weeks.count <= 54)
        #expect(days.contains { $0.date == leap && $0.tokens == 12 })
        #expect(days.allSatisfy { calendar.component(.year, from: $0.date) == 2024 && $0.date >= domain.lowerBound })
        #expect(days.contains { $0.tokens == 0 })
        let dayDomain = AIUsageHistoryPresentation.domain(history: history, range: .day, now: today, calendar: calendar)
        let dayCells = AIUsageHistoryPresentation.heatmap(history: history, domain: dayDomain, year: nil, now: today, calendar: calendar)
            .flatMap { $0 }.compactMap { $0 }
        #expect(dayCells.map(\.date) == [today])
    }

    /// A stored day can appear after local midnight following a timezone change; every view must include the full day.
    @Test(arguments: [SystemMetricsHistoryRange.day, .week, .month, .all])
    func nonMidnightSamplesAgreeAcrossTrendHeatmapAndDetails(range: SystemMetricsHistoryRange) throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11)))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let samples = [sample(at: today.addingTimeInterval(8 * 3600), input: 10),
            sample(at: tomorrow.addingTimeInterval(-0.25), input: 20), sample(at: tomorrow, input: 99)]
        let history = AIUsageHistory(usageSamples: samples, modelUsageSamples: samples)
        let domain = AIUsageHistoryPresentation.domain(history: history, range: range, now: today, calendar: calendar)
        let trend = AIUsageHistoryPresentation.trend(history: history, domain: domain, calendar: calendar)
        let heatmap = AIUsageHistoryPresentation.heatmap(history: history, domain: domain,
            year: range == .all ? today : nil, now: today, calendar: calendar).flatMap { $0 }.compactMap { $0 }
        let selected = AIUsageHistoryPresentation.selectedDay(in: history, date: today, calendar: calendar)
        #expect(trend.last?.totalTokens == 34 && heatmap.last?.tokens == 34 && selected.totalTokens == 34)
        #expect(selected.models.first?.totalTokens == 34)
    }

    /// The two worksheets must be real OOXML and keep model strings as text, including formula-like or XML content.
    @Test
    func workbookExportsCompleteTotalsAndEscapesUntrustedModelNames() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let model = "=SUM(A1)&<model>\u{0001}🧪"
        let history = AIUsageHistory(usageSamples: [sample(at: date, input: 20)],
            modelUsageSamples: [sample(at: date, input: 10, model: model)])
        let parts = try extract(AIUsageHistoryExport.workbookData(history: history, timeZone: calendar.timeZone))
        #expect(parts.count == 6)
        let totals = try #require(parts["xl/worksheets/sheet1.xml"])
        let models = try #require(parts["xl/worksheets/sheet2.xml"])
        #expect(totals.contains("<c r=\"D2\"><v>22</v></c>"))
        #expect(models.contains("=SUM(A1)&amp;&lt;model&gt;🧪"))
        #expect(!models.contains("<f>") && !models.contains("private-source"))
        #expect(models.contains("<row r=\"3\">"), "Unclassified remainder must remain in the export")
        for part in parts.values { #expect(XMLParser(data: Data(part.utf8)).parse()) }
    }

    /// Grouping and the ISO date label must use the same requested timezone across midnight.
    @Test
    func workbookUsesRequestedTimezoneForBothTotalsAndModelDates() throws {
        let before = try Date.ISO8601FormatStyle().parse("2026-11-10T23:30:00Z")
        let after = try Date.ISO8601FormatStyle().parse("2026-11-11T00:30:00Z")
        let samples = [sample(at: before, input: 10), sample(at: after, input: 20)]
        let history = AIUsageHistory(usageSamples: samples, modelUsageSamples: samples)
        let utc = try extract(AIUsageHistoryExport.workbookData(history: history, timeZone: calendar.timeZone))
        let shanghai = try extract(AIUsageHistoryExport.workbookData(history: history,
            timeZone: try #require(TimeZone(identifier: "Asia/Shanghai"))))
        let utcTotals = try #require(utc["xl/worksheets/sheet1.xml"])
        let localTotals = try #require(shanghai["xl/worksheets/sheet1.xml"])
        #expect(utcTotals.contains("2026-11-10") && utcTotals.contains("2026-11-11"))
        #expect(!localTotals.contains("2026-11-10") && localTotals.contains("2026-11-11"))
        #expect(localTotals.contains("<c r=\"D2\"><v>34</v></c>") && !localTotals.contains("<row r=\"3\">"))
        #expect(shanghai["xl/worksheets/sheet2.xml"]?.contains("<c r=\"F2\"><v>34</v></c>") == true)
    }

    @Test
    func emptyWorkbookHasHeadersAndCancellationDoesNotGenerateAFile() async throws {
        let parts = try extract(AIUsageHistoryExport.workbookData(history: .init()))
        for name in ["xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml"] {
            let sheet = try #require(parts[name])
            #expect(sheet.contains("<row r=\"1\">") && !sheet.contains("<row r=\"2\">"))
        }
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try AIUsageHistoryExport.workbookData(history: .init())
        }
        do { _ = try await work.value; Issue.record("Cancelled workbook generation succeeded") }
        catch is CancellationError {}
        #expect(AIUsageHistoryExport.defaultFileName(now: Date(timeIntervalSince1970: 0), timeZone: calendar.timeZone)
            == "zisla-ai-usage-19700101-000000.xlsx")
    }

    private func sample(at date: Date, input: Int, model: String = "fixture-model") -> AIUsageSample {
        AIUsageSample(sourceID: "private-source", provider: .codex, timestamp: date, inputTokens: input, outputTokens: 2, model: model)
    }

    private func extract(_ workbook: Data) throws -> [String: String] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-ai-workbook-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("fixture.xlsx")
        try workbook.write(to: archive)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", archive.path, "-d", directory.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "unzip must accept the actual xlsx package")
        var result: [String: String] = [:]
        for part in ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels",
            "xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml"] {
            result[part] = try String(contentsOf: directory.appendingPathComponent(part), encoding: .utf8)
        }
        return result
    }
}
