import Foundation
import SQLite3
import Testing

@testable import ZislaCore

struct AIModelDailyUsageTests {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    @Test
    func manualAndDetectedUsageKeepIndependentModelTotalsAcrossRestartAndRescans() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let detected = sample("event", .codex, "gpt-6.1-sol", 100, 20)
        try repository.recordUsage([sample("manual", .claude, "claude-sonnet-4-5", 30, 5)])
        try repository.recordDetectedUsage([detected, detected])
        let restarted = AIStateRepository(directoryURL: root)
        #expect(try restarted.recordDetectedUsage([detected]) == 0)
        let history = try restarted.loadUsageHistory()
        #expect(history.usageSamples.map(\.totalTokens) == [155])
        #expect(history.modelUsageSamples.map(\.totalTokens).sorted() == [35, 120])
        let rows = AIUsageAnalytics.dailyModelUsage(history: history, endingAt: day.addingTimeInterval(3600))
        #expect(rows.first?.models.map(\.model) == ["gpt-6.1-sol", "claude-sonnet-4-5"])
        #expect(rows.first?.totalTokens == 155)
    }

    @Test
    /// A cumulative source must keep its previous day intact and charge only growth to the next day.
    func cumulativeGrowthAcrossMidnightRecordsOnlyTheNewDayDelta() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let first = sample("cumulative", .zed, nil, 100, 20)
        var second = first
        second.timestamp = day.addingTimeInterval(86_410)
        second.inputTokens = 150
        second.outputTokens = 30
        try repository.recordDetectedUsage([first])
        try repository.recordDetectedUsage([second])
        #expect(try repository.recordDetectedUsage([first, second]) == 0)
        let history = try repository.loadUsageHistory()
        #expect(history.usageSamples.map(\.totalTokens) == [120, 60])
        #expect(history.modelUsageSamples.map(\.totalTokens) == [120, 60])
        #expect(history.modelUsageSamples.allSatisfy { $0.model == nil && $0.provider == .zed })
        var reduced = second
        reduced.inputTokens = 10
        reduced.timestamp = first.timestamp
        #expect(try repository.recordDetectedUsage([reduced]) == 0)
        #expect(try repository.loadUsageHistory() == history)
    }

    @Test
    func modelMetadataBackfillReclassifiesUnknownUsageWithoutAddingTokensOrChangingDays() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let first = sample("missing-model", .codex, nil, 100, 20)
        try repository.recordDetectedUsage([first])
        var enriched = first
        enriched.model = "  gpt-6.1-sol  "
        #expect(try repository.recordDetectedUsage([enriched]) == 0)
        let history = try repository.loadUsageHistory()
        #expect(history.usageSamples.map(\.totalTokens) == [120])
        #expect(history.modelUsageSamples.count == 1)
        #expect(history.modelUsageSamples.first?.model == "gpt-6.1-sol")
        #expect(history.modelUsageSamples.first?.timestamp == day)
    }

    @Test
    func crossDayModelDiscoveryDoesNotReclassifyPreviouslyUnknownCumulativeUsage() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let first = sample("later-model", .zed, nil, 100, 20)
        var second = first
        second.timestamp = first.timestamp.addingTimeInterval(86_400)
        second.model = "model-b"
        second.inputTokens = 150
        second.outputTokens = 30
        try repository.recordDetectedUsage([first, second])
        let history = try repository.loadUsageHistory()
        #expect(history.modelUsageSamples.map(\.model) == [nil, "model-b"])
        #expect(history.modelUsageSamples.map(\.totalTokens) == [120, 60])
        #expect(try repository.recordDetectedUsage([first, second]) == 0)
        #expect(try repository.loadUsageHistory() == history)
    }

    @Test
    func lateModelMetadataCannotReclassifyMultipleUnknownDailySegments() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let first = sample("unknown-segments", .zed, nil, 100, 20)
        var second = first
        second.timestamp = first.timestamp.addingTimeInterval(86_400)
        second.inputTokens = 150
        second.outputTokens = 30
        try repository.recordDetectedUsage([first, second])
        second.model = "current-model"
        #expect(try repository.recordDetectedUsage([second]) == 0)
        #expect(try repository.loadUsageHistory().modelUsageSamples.map(\.model) == [nil, nil])
        #expect(try repository.loadUsageHistory().modelUsageSamples.map(\.totalTokens) == [120, 60])
    }

    @Test
    func cumulativeSourceModelChangesAttributeOnlyItsNewTokenDelta() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let first = sample("model-switch", .codex, "model-a", 100, 20)
        var second = first
        second.timestamp = first.timestamp.addingTimeInterval(86_400)
        second.model = "model-b"
        second.inputTokens = 150
        second.outputTokens = 30
        try repository.recordDetectedUsage([first, second])
        #expect(try repository.loadUsageHistory().modelUsageSamples.map(\.model) == ["model-a", "model-b"])
        #expect(try repository.recordDetectedUsage([first, second]) == 0)
        var unknown = second
        unknown.model = nil
        unknown.inputTokens = 170
        try repository.recordDetectedUsage([unknown])
        #expect(try repository.loadUsageHistory().modelUsageSamples.map(\.totalTokens) == [120, 20, 60])
        #expect(try repository.loadUsageHistory().modelUsageSamples.filter { $0.model == nil }.first?.inputTokens == 20)
    }

    @Test
    func migrationBackfillsOnlyRealEventMetadataAndLeavesCompressedHistoryUnclassified() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        try repository.recordUsage(sample("manual", .claude, "cannot-recover", 40, 10))
        let detected = sample("event", .codex, "gpt-6.1-sol", 100, 20)
        try repository.recordDetectedUsage([detected])
        try sql(repository.databaseURL, "DROP TABLE model_usage_samples; DROP TABLE detected_usage_daily; PRAGMA user_version = 6")
        let migrated = try AIStateRepository(directoryURL: root).loadUsageHistory()
        #expect(migrated.usageSamples.first?.totalTokens == 170)
        #expect(migrated.modelUsageSamples.map(\.model) == ["gpt-6.1-sol"])
        #expect(try repository.recordDetectedUsage([detected]) == 0)
        let rows = AIUsageAnalytics.dailyModelUsage(history: migrated, endingAt: day.addingTimeInterval(3600))
        #expect(rows.first?.models.map(\.totalTokens) == [120, 50])
        #expect(rows.first?.models.last?.provider == nil)
        #expect(rows.first?.models.last?.model == nil)
        #expect(try repository.loadUsageHistory() == migrated)
    }

    @Test
    func preDailySchemaMigrationCanTrimBeforeModelBackfillWithoutMissingTables() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root, maximumUsageSamples: 1)
        _ = try repository.load()
        try sql(repository.databaseURL, """
            DROP TABLE model_usage_samples;
            DROP TABLE detected_usage_daily;
            PRAGMA user_version = 2;
            INSERT INTO usage_samples(source_id,provider,timestamp,input_tokens,output_tokens) VALUES
            ('legacy-one','codex',\(day.timeIntervalSinceReferenceDate),10,2),
            ('legacy-two','claude',\(day.addingTimeInterval(86_400).timeIntervalSinceReferenceDate),20,3);
            """)
        let history = try repository.loadUsageHistory()
        #expect(history.usageSamples.count == 1)
        #expect(history.usageSamples.first?.totalTokens == 23)
        #expect(history.modelUsageSamples.isEmpty)
    }

    @Test
    func schemaSixGenericSourcesDoNotBackfillAnUnreliableFirstModel() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        try repository.recordDetectedUsage([sample("gemini-file-entry-root-usage-0", .gemini, "unreliable-first-model", 10, 2)])
        try sql(repository.databaseURL, "DROP TABLE model_usage_samples; DROP TABLE detected_usage_daily; PRAGMA user_version = 6")
        let history = try repository.loadUsageHistory()
        #expect(history.usageSamples.first?.totalTokens == 12)
        #expect(history.modelUsageSamples.first?.model == nil)
    }

    @Test
    /// Retention and half-open queries must keep model rows aligned with their authoritative aggregate day.
    func modelSummariesRemainBoundedByRetainedDaysAndSupportHalfOpenRanges() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root, maximumUsageSamples: 2)
        for offset in 0..<3 {
            var value = sample("event-\(offset)", .codex, "gpt", 10, 2)
            value.timestamp = day.addingTimeInterval(Double(offset) * 86_400 + 10)
            try repository.recordDetectedUsage([value])
        }
        let history = try repository.loadUsageHistory(startingAt: day.addingTimeInterval(86_400),
            endingBefore: day.addingTimeInterval(172_800))
        #expect(history.usageSamples.count == 1)
        #expect(history.modelUsageSamples.count == 1)
        #expect(try repository.load().modelUsageSamples.count == 2)
        #expect(try repository.load(includeUsageSamples: false).modelUsageSamples.isEmpty)
        #expect(try repository.recordDetectedUsage([sample("event-0", .codex, "gpt", 10, 2)]) == 0)
        #expect(try repository.load().modelUsageSamples.count == 2)
    }

    @Test
    func failedModelWriteRollsBackDailyTotalAndDedupeHighWaterMark() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        _ = try repository.load()
        try sql(repository.databaseURL, """
            CREATE TRIGGER fail_model_usage BEFORE INSERT ON model_usage_samples
            BEGIN SELECT RAISE(ABORT, 'fixture disk failure'); END
            """)
        let value = sample("transaction", .codex, "gpt", 10, 2)
        #expect(throws: (any Error).self) { try repository.recordDetectedUsage([value]) }
        #expect(try repository.loadUsageHistory().usageSamples.isEmpty)
        try sql(repository.databaseURL, "DROP TRIGGER fail_model_usage")
        #expect(try repository.recordDetectedUsage([value]) == 1)
        #expect(try repository.loadUsageHistory().modelUsageSamples.first?.totalTokens == 12)
    }

    @Test
    func aggregationNormalizesMissingModelsSeparatesProvidersAndSaturatesCounts() {
        let samples = [sample("a", .codex, "  ", -10, 5), sample("b", .codex, nil, Int.max, 2),
            sample("c", .claude, "gpt", 7, 3), sample("d", .codex, "gpt", 8, 4)]
        let models = AIUsageAnalytics.dailyModelUsageSamples(samples: samples)
        #expect(models.count == 3)
        #expect(models.filter { $0.model == nil }.first?.totalTokens == Int.max)
        #expect(models.filter { $0.model == "gpt" }.map(\.provider) == [.claude, .codex])
    }

    @Test
    func legacyStateJSONDefaultsModelHistoryToEmpty() throws {
        let state = try JSONDecoder().decode(AIState.self, from: Data(#"{"tasks":[],"usageSamples":[],"notices":[]}"#.utf8))
        #expect(state.modelUsageSamples.isEmpty)
        #expect(try JSONDecoder().decode(AIState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test
    func legacyBaselinesReconcileRescansWithoutInventingOrDoubleCountingModelUsage() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let historical = sample("history", .codex, "historical-model", 100, 20)
        try repository.recordUsage(sample("manual", .claude, "manual-model", 40, 10))
        try repository.recordDetectedUsage([historical])
        try sql(repository.databaseURL, """
            DELETE FROM detected_usage_events;
            DELETE FROM detected_usage_daily;
            DELETE FROM model_usage_samples WHERE origin = 'detected';
            INSERT INTO detected_usage_baselines(timestamp,input_tokens,output_tokens)
            VALUES(\(day.timeIntervalSinceReferenceDate),100,20);
            """)
        #expect(try repository.recordDetectedUsage([historical]) == 0)
        let new = sample("new", .codex, "new-model", 30, 5)
        try repository.recordDetectedUsage([new])
        #expect(try repository.recordDetectedUsage([historical, new]) == 0)
        let history = try repository.loadUsageHistory()
        #expect(history.usageSamples.first?.totalTokens == 205)
        #expect(history.modelUsageSamples.map(\.totalTokens).reduce(0, +) == 205)
    }

    @Test
    func laterLegacyGenericEventsMergeIntoAnExistingDayBaselineWithoutBlockingScans() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let prefix = "gemini-fixture-entry-root-usage-"
        try repository.recordDetectedUsage([sample(prefix + "0", .gemini, nil, 100, 20)])
        var current = sample("gemini-fixture-event-v2-message", .gemini, "current-model", 10, 2)
        current.legacySourceID = prefix
        #expect(try repository.recordDetectedUsage([current]) == 0)
        try repository.recordDetectedUsage([sample(prefix + "1", .gemini, nil, 30, 5)])
        current.inputTokens = 45
        current.outputTokens = 10
        #expect(try repository.recordDetectedUsage([current]) == 0)
        #expect(try repository.loadUsageSamples().first?.totalTokens == 155)
        #expect(try repository.recordDetectedUsage([current]) == 0)
        current.inputTokens = 140
        current.outputTokens = 30
        #expect(try repository.recordDetectedUsage([current]) == 1)
        let history = try repository.loadUsageHistory()
        #expect(history.usageSamples.first?.totalTokens == 170)
        #expect(history.modelUsageSamples.map(\.totalTokens).reduce(0, +) == 170)
        #expect(try repository.recordDetectedUsage([current]) == 0)
        #expect(try repository.loadUsageHistory() == history)
    }

    @Test
    func corruptedModelRowsAreRejectedWithoutChangingTheDailyTotal() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        try repository.recordDetectedUsage([sample("corrupted", .codex, "model", 10, 2)])
        try sql(repository.databaseURL, "UPDATE model_usage_samples SET provider = 'invalid-provider'")
        #expect(throws: AIStateRepositoryError.corruptedState) { try repository.loadUsageHistory() }
        #expect(try repository.loadUsageSamples().first?.totalTokens == 12)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteTimestampsFailBeforeWritingTotalsOrModelRows(timestamp: Double) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        var value = sample("invalid-date", .codex, "model", 10, 2)
        value.timestamp = Date(timeIntervalSinceReferenceDate: timestamp)
        #expect(throws: AIStateRepositoryError.corruptedState) { try repository.recordUsage(value) }
        #expect(throws: AIStateRepositoryError.corruptedState) { try repository.recordDetectedUsage([value]) }
        #expect(try repository.loadUsageHistory() == AIUsageHistory())
    }

    @Test
    func modelHistoryRejectsInvalidDataExceedingThePreservedDailyTotal() {
        let history = AIUsageHistory(usageSamples: [sample("total", .claude, "wrong-first-model", 10, 2)],
            modelUsageSamples: [sample("oversized", .codex, "untrusted-model", 100, 20)])
        let rows = AIUsageAnalytics.dailyModelUsage(history: history, endingAt: day.addingTimeInterval(100))
        #expect(rows.first?.models == [AIModelUsage(provider: nil, model: nil, inputTokens: 10, outputTokens: 2)])
        #expect(rows.first?.totalTokens == 12)
    }

    private func sample(_ id: String, _ provider: AIProvider, _ model: String?, _ input: Int, _ output: Int) -> AIUsageSample {
        AIUsageSample(sourceID: id, provider: provider, timestamp: day.addingTimeInterval(10),
            inputTokens: input, outputTokens: output, model: model)
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("zisla-model-usage-\(UUID())", isDirectory: true)
    }

    /// Writes only isolated schema fixtures and surfaces setup failures before migration assertions run.
    private func sql(_ url: URL, _ query: String) throws {
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let result = sqlite3_exec(database, query, nil, nil, nil)
        #expect(result == SQLITE_OK, "\(query): \(String(cString: sqlite3_errmsg(database)))")
        if result != SQLITE_OK { throw CocoaError(.fileReadCorruptFile) }
    }
}
