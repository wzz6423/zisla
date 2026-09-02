import Foundation
import Testing
@testable import ZislaCore

struct IntegerOverflowTests {
    @Test
    func aiUsageTokenMathSaturatesAtIntMaxOnOverflow() {
        let nearMax = Int.max - 10
        let addend = 20

        let result = AIUsageTokenMath.adding(nearMax, addend)

        #expect(result == Int.max)
    }

    @Test
    func aiUsageTokenMathReturnsCorrectSumWhenNoOverflow() {
        #expect(AIUsageTokenMath.adding(100, 200) == 300)
        #expect(AIUsageTokenMath.adding(0, 0) == 0)
        #expect(AIUsageTokenMath.adding(1_000_000, 2_000_000) == 3_000_000)
    }

    @Test
    func aiUsageTokenMathTreatsNegativeValuesAsZero() {
        #expect(AIUsageTokenMath.nonnegative(-100) == 0)
        #expect(AIUsageTokenMath.nonnegative(0) == 0)
        #expect(AIUsageTokenMath.nonnegative(100) == 100)
        #expect(AIUsageTokenMath.adding(-50, 100) == 100)
        #expect(AIUsageTokenMath.adding(100, -50) == 100)
    }

    @Test
    func totalTokensSaturatesAtIntMaxInsteadOfOverflowing() {
        let sample = AIUsageSample(
            provider: .claude,
            timestamp: Date(),
            inputTokens: Int.max - 5,
            outputTokens: 10
        )

        #expect(sample.totalTokens == Int.max)
    }

    @Test
    func dailyUsageSamplesSaturatesWhenAggregatingLargeTokenCounts() {
        let day = Date(timeIntervalSinceReferenceDate: 0)
        let samples = [
            AIUsageSample(
                provider: .claude,
                timestamp: day,
                inputTokens: Int.max - 100,
                outputTokens: Int.max - 50
            ),
            AIUsageSample(
                provider: .claude,
                timestamp: day.addingTimeInterval(60),
                inputTokens: 200,
                outputTokens: 100
            ),
        ]

        let aggregated = AIUsageAnalytics.dailyUsageSamples(
            samples: samples,
            calendar: .current
        )

        #expect(aggregated.count == 1)
        #expect(aggregated[0].inputTokens == Int.max)
        #expect(aggregated[0].outputTokens == Int.max)
    }

    @Test
    func dailyUsageSeriesSaturatesInputAndOutputSeparately() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 86_400)
        let samples = [
            AIUsageSample(
                provider: .claude,
                timestamp: day.addingTimeInterval(100),
                inputTokens: Int.max - 50,
                outputTokens: 100
            ),
            AIUsageSample(
                provider: .grok,
                timestamp: day.addingTimeInterval(200),
                inputTokens: 100,
                outputTokens: Int.max - 50
            ),
            AIUsageSample(
                provider: .gpt,
                timestamp: day.addingTimeInterval(300),
                inputTokens: 100,
                outputTokens: 100
            ),
        ]

        let series = AIUsageAnalytics.dailyUsageSeries(
            samples: samples,
            endingAt: day.addingTimeInterval(3600),
            days: 1,
            calendar: calendar
        )

        #expect(series.count == 1)
        #expect(series[0].inputTokens == Int.max)
        #expect(series[0].outputTokens == Int.max)
    }

    @Test
    func cumulativeUsageSeriesSaturatesAtIntMax() {
        let samples = [
            AIUsageSample(
                provider: .claude,
                timestamp: Date(timeIntervalSince1970: 100),
                inputTokens: Int.max - 100,
                outputTokens: 50
            ),
            AIUsageSample(
                provider: .grok,
                timestamp: Date(timeIntervalSince1970: 200),
                inputTokens: 100,
                outputTokens: 100
            ),
        ]

        let series = AIUsageAnalytics.cumulativeUsageSeries(
            samples: samples,
            endingAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(series.last?.tokens == Int.max)
    }

    @Test
    func cumulativeDetailSeriesSaturatesInputOutputAndTotal() {
        let samples = [
            AIUsageSample(
                provider: .claude,
                timestamp: Date(timeIntervalSince1970: 100),
                inputTokens: Int.max - 100,
                outputTokens: 10
            ),
            AIUsageSample(
                provider: .grok,
                timestamp: Date(timeIntervalSince1970: 200),
                inputTokens: 200,
                outputTokens: Int.max - 20
            ),
            AIUsageSample(
                provider: .gpt,
                timestamp: Date(timeIntervalSince1970: 300),
                inputTokens: 50,
                outputTokens: 50
            ),
        ]

        let series = AIUsageAnalytics.cumulativeDetailSeries(
            samples: samples,
            endingAt: Date(timeIntervalSince1970: 1_000)
        )

        let final = series.last!
        #expect(final.inputTokens == Int.max)
        #expect(final.outputTokens == Int.max)
        #expect(final.totalTokens == Int.max)
    }

    @Test
    func repositoryRecordUsageSaturatesWhenUpdatingExistingSample() throws {
        let directory = temporaryDirectory(named: "overflow-record-usage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 700_000_000))
        let sourceID = "zisla-daily-total:\(day.timeIntervalSinceReferenceDate)"

        try repository.recordUsage(AIUsageSample(
            sourceID: sourceID,
            provider: .claude,
            timestamp: day,
            inputTokens: Int.max - 100,
            outputTokens: Int.max - 50
        ))
        try repository.recordUsage(AIUsageSample(
            sourceID: sourceID,
            provider: .claude,
            timestamp: day,
            inputTokens: 200,
            outputTokens: 100
        ))

        let stored = try repository.load().usageSamples
        #expect(stored.count == 1)
        #expect(stored[0].inputTokens == Int.max)
        #expect(stored[0].outputTokens == Int.max)
    }

    @Test
    func repositoryRecordDetectedUsageSaturatesWhenUpdatingEvent() throws {
        let directory = temporaryDirectory(named: "overflow-detected-usage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let timestamp = Date(timeIntervalSinceReferenceDate: 700_000_000)

        #expect(try repository.recordDetectedUsage([
            AIUsageSample(
                sourceID: "event-overflow",
                provider: .codex,
                timestamp: timestamp,
                inputTokens: Int.max - 100,
                outputTokens: 50
            )
        ]) == 1)

        #expect(try repository.recordDetectedUsage([
            AIUsageSample(
                sourceID: "event-overflow",
                provider: .codex,
                timestamp: timestamp,
                inputTokens: Int.max - 20,
                outputTokens: 100
            )
        ]) == 1)

        let stored = try repository.load().usageSamples
        #expect(stored.count == 1)
        #expect(stored[0].totalTokens == Int.max)
    }

    @Test
    func repositorySaturatesDetectedEventTotalsBeyondSQLiteIntegerSumRange() throws {
        let directory = temporaryDirectory(named: "overflow-detected-event-total")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let timestamp = Date(timeIntervalSinceReferenceDate: 700_000_000)

        #expect(try repository.recordDetectedUsage([
            AIUsageSample(
                sourceID: "overflow-event-a",
                provider: .codex,
                timestamp: timestamp,
                inputTokens: Int.max,
                outputTokens: Int.max
            ),
            AIUsageSample(
                sourceID: "overflow-event-b",
                provider: .codex,
                timestamp: timestamp.addingTimeInterval(1),
                inputTokens: Int.max,
                outputTokens: Int.max
            ),
        ]) == 1)

        let stored = try repository.load().usageSamples
        #expect(stored.count == 1)
        #expect(stored[0].inputTokens == Int.max)
        #expect(stored[0].outputTokens == Int.max)
    }
}

private func temporaryDirectory(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-\(name)-\(UUID().uuidString)", isDirectory: true)
}
