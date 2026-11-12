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

    /// A cumulative source must keep its previous day intact and charge only growth to the next day.
    @Test
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

    /// Schema 6's compressed aggregates cannot prove which models produced manual or otherwise unclassified history.
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

    /// Older upgrades trim history before backfilling models, so their dependent tables must already exist.
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

    /// The old generic parser's surrounding model label is not evidence of a historical message's actual model.
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

    /// Retention and half-open queries must keep model rows aligned with their authoritative aggregate day.
    @Test
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
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_daily") == 2)
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_events") == 3)
    }

    /// Existing ledgers can already fit the visible limit while retaining source-linked detail for an evicted day.
    @Test(arguments: [false, true])
    func existingOrphanedDailyLedgerIsPrunedWhenLoadingHistory(includeHistory: Bool) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root, maximumUsageSamples: 1)
        let old = sample("orphaned", .codex, "old-model", 100, 20)
        try repository.recordDetectedUsage([old])
        var current = sample("retained", .claude, "current-model", 30, 5)
        current.timestamp = old.timestamp.addingTimeInterval(86_400)
        try repository.recordDetectedUsage([current])
        try sql(repository.databaseURL, """
            INSERT OR REPLACE INTO detected_usage_daily(source_id,provider,timestamp,model,input_tokens,output_tokens)
            VALUES('orphaned','codex',\(day.timeIntervalSinceReferenceDate),'old-model',100,20);
            INSERT INTO detected_usage_baselines(timestamp,input_tokens,output_tokens)
            VALUES(\(day.timeIntervalSinceReferenceDate),100,20);
            """)
        let restarted = AIStateRepository(directoryURL: root, maximumUsageSamples: 1)
        if includeHistory { _ = try restarted.loadUsageHistory() }
        else { _ = try restarted.load(includeUsageSamples: false) }
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_daily") == 1)
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_daily WHERE model = 'old-model'") == 0)
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_events") == 2)
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_baselines") == 1)
        #expect(try restarted.recordDetectedUsage([old, current]) == 0)
        #expect(try restarted.loadUsageHistory().usageSamples.map(\.totalTokens) == [35])
        var expiredGrowth = old
        expiredGrowth.inputTokens = 110
        expiredGrowth.outputTokens = 22
        _ = try restarted.recordDetectedUsage([expiredGrowth])
        #expect(try restarted.loadUsageHistory().usageSamples.map(\.totalTokens) == [35])
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_daily") == 1)
        var growth = old
        growth.timestamp = current.timestamp.addingTimeInterval(86_400)
        growth.inputTokens = 150
        growth.outputTokens = 30
        growth.model = "new-model"
        #expect(try restarted.recordDetectedUsage([growth]) == 1)
        #expect(try restarted.loadUsageHistory().usageSamples.map(\.totalTokens) == [48])
        #expect(try restarted.loadUsageHistory().modelUsageSamples.map(\.model) == ["new-model"])
        #expect(try restarted.recordDetectedUsage([old, current, growth]) == 0)
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_daily") == 1)
    }

    /// Trimming one segment must not make a partial unknown reading appear to contain the source's full history.
    @Test(arguments: [true, false])
    func trimmedUnknownSegmentsCannotBeReclassifiedByLaterMetadata(inputOnly: Bool) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root, maximumUsageSamples: 1)
        let first = sample("trimmed-unknown", .zed, nil, inputOnly ? 100 : 0, inputOnly ? 0 : 20)
        var second = first
        second.timestamp = first.timestamp.addingTimeInterval(86_400)
        second.inputTokens = inputOnly ? 150 : 0
        second.outputTokens = inputOnly ? 0 : 30
        try repository.recordDetectedUsage([first, second])
        second.model = "late-model"
        #expect(try repository.recordDetectedUsage([second]) == 0)
        let history = try repository.loadUsageHistory()
        #expect(history.usageSamples.map(\.totalTokens) == [inputOnly ? 50 : 10])
        #expect(history.modelUsageSamples.map(\.model) == [nil])
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_daily") == 1)
    }

    /// Pruning shares the usage transaction so failed removal cannot advance a source without its daily delta.
    @Test
    func failedDetailedLedgerPruningRollsBackNewUsageAndCanRetryOnce() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root, maximumUsageSamples: 1)
        let first = sample("retention-transaction", .codex, "old-model", 100, 20)
        try repository.recordDetectedUsage([first])
        try sql(repository.databaseURL, """
            CREATE TRIGGER fail_daily_pruning BEFORE DELETE ON detected_usage_daily
            BEGIN SELECT RAISE(ABORT, 'fixture pruning failure'); END;
            """)
        var second = first
        second.timestamp = first.timestamp.addingTimeInterval(86_400)
        second.inputTokens = 150
        second.outputTokens = 30
        second.model = "new-model"
        #expect(throws: (any Error).self) { try repository.recordDetectedUsage([second]) }
        #expect(try repository.loadUsageHistory().usageSamples.map(\.totalTokens) == [120])
        #expect(try scalar(repository.databaseURL, "SELECT input_tokens FROM detected_usage_events") == 100)
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_daily") == 1)
        try sql(repository.databaseURL, "DROP TRIGGER fail_daily_pruning")
        #expect(try repository.recordDetectedUsage([second]) == 1)
        #expect(try repository.loadUsageHistory().usageSamples.map(\.totalTokens) == [60])
        #expect(try repository.loadUsageHistory().modelUsageSamples.map(\.model) == ["new-model"])
        #expect(try repository.recordDetectedUsage([first, second]) == 0)
    }

    /// Clearing reporting tables must preserve tasks and replay protection while charging later growth in full.
    @Test
    func clearingHistoryKeepsTasksNoticesAndHighWaterMarksWithoutSwallowingNewGrowth() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let task = AIProgressTask(id: "clear-task", provider: .codex, title: "Fixture", progress: nil, updatedAt: day)
        let notice = IslandNotice(id: "clear-notice", title: "Fixture", createdAt: day)
        try repository.upsert(task)
        try repository.enqueueNotice(notice)
        var detected = sample("clear-source", .codex, nil, 100, 20)
        try repository.recordDetectedUsage([detected])
        try repository.recordUsage(sample("manual-clear", .claude, "manual", 5, 2))
        try sql(repository.databaseURL, """
            INSERT INTO detected_usage_baselines VALUES(\(day.timeIntervalSinceReferenceDate), 999999, 999999);
            INSERT INTO detected_usage_cursor VALUES(1, \(day.addingTimeInterval(864000).timeIntervalSinceReferenceDate));
            """)
        try repository.clearUsageHistory()
        for table in ["usage_samples", "model_usage_samples", "detected_usage_daily", "detected_usage_baselines", "detected_usage_cursor"] {
            #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM \(table)") == 0)
        }
        #expect(try scalar(repository.databaseURL, "SELECT input_tokens FROM detected_usage_events WHERE source_id = 'clear-source'") == 100)
        let state = try repository.load()
        #expect(state.tasks == [task] && state.notices == [notice])
        #expect(state.usageSamples.isEmpty && state.modelUsageSamples.isEmpty)
        #expect(try repository.recordDetectedUsage([detected]) == 0)
        detected.model = "discovered-model"
        #expect(try repository.recordDetectedUsage([detected]) == 0)
        #expect(try repository.loadUsageHistory() == AIUsageHistory())
        detected.inputTokens = 150
        detected.outputTokens = 30
        #expect(try repository.recordDetectedUsage([detected]) == 1)
        let history = try AIStateRepository(directoryURL: root).loadUsageHistory()
        #expect(history.usageSamples.map(\.inputTokens) == [50])
        #expect(history.usageSamples.map(\.outputTokens) == [10])
        #expect(history.modelUsageSamples.map(\.model) == ["discovered-model"])
        #expect(history.modelUsageSamples.map(\.totalTokens) == [60])
        #expect(try repository.recordDetectedUsage([detected]) == 0)
        try repository.clearUsageHistory()
        try repository.clearUsageHistory()
        #expect(try repository.loadUsageHistory() == AIUsageHistory())
    }

    /// A failing delete must roll back every reporting table so the unchanged history remains retryable.
    @Test
    func clearFailureRollsBackAllLedgersAndRetryKeepsReplayProtection() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let detected = sample("clear-rollback", .codex, "model", 100, 20)
        try repository.recordDetectedUsage([detected])
        let original = try repository.loadUsageHistory()
        try sql(repository.databaseURL, """
            CREATE TRIGGER fail_history_clear BEFORE DELETE ON detected_usage_daily
            BEGIN SELECT RAISE(ABORT, 'fixture clear failure'); END;
            """)
        #expect(throws: (any Error).self) { try repository.clearUsageHistory() }
        #expect(try repository.loadUsageHistory() == original)
        #expect(try scalar(repository.databaseURL, "SELECT COUNT(*) FROM detected_usage_daily") == 1)
        #expect(try scalar(repository.databaseURL, "SELECT input_tokens FROM detected_usage_events") == 100)
        try sql(repository.databaseURL, "DROP TRIGGER fail_history_clear")
        try repository.clearUsageHistory()
        #expect(try repository.recordDetectedUsage([detected]) == 0)
        #expect(try repository.loadUsageHistory() == AIUsageHistory())
    }

    /// Legacy generic evidence may archive identities after clear, but it must never restore discarded report rows.
    @Test
    func legacyGenericArchiveAfterClearSeedsOnlyFutureGrowth() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let document = Data(#"{"messages":[{"id":"old","usage":{"input_tokens":100,"output_tokens":20}}],"timestamp":"2026-11-08T00:00:00Z"}"#.utf8)
        let legacy = sample("gemini-clear-entry-\(AIUsageLogIdentity.digest(document))-usage-0", .gemini, nil, 100, 20)
        try repository.recordDetectedUsage([legacy])
        try repository.clearUsageHistory()
        var current = sample("gemini-clear-usage-v2-old", .gemini, "current", 100, 20)
        current.legacySourceID = "gemini-clear-entry-current-usage-"
        current.genericContext = .init(document: document, path: [.key("messages"), .index(0), .key("usage")])
        #expect(try repository.recordDetectedUsage([current]) == 0)
        #expect(try repository.loadUsageHistory() == AIUsageHistory())
        current.inputTokens = 150
        current.outputTokens = 30
        current.genericContext = .init(document: Data(#"{"messages":[{"id":"old","usage":{"input_tokens":150,"output_tokens":30}}],"timestamp":"2026-11-08T00:00:00Z"}"#.utf8), path: [.key("messages"), .index(0), .key("usage")])
        #expect(try repository.recordDetectedUsage([current]) == 1)
        let history = try repository.loadUsageHistory()
        #expect(history.usageSamples.map(\.totalTokens) == [60])
        #expect(history.modelUsageSamples.map(\.model) == ["current"])
        #expect(try repository.recordDetectedUsage([legacy, current]) == 0)
    }

    /// A failed model insert must not acknowledge the event, or its retry would silently lose the token delta.
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

    /// Late legacy snapshots without message evidence must not block later scans or be consumed by another source.
    @Test
    func laterLegacyGenericEventsRemainIndependentOfTheCurrentHighWaterMark() throws {
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
        #expect(try repository.recordDetectedUsage([current]) == 1)
        #expect(try repository.loadUsageSamples().first?.totalTokens == 198)
        #expect(try repository.recordDetectedUsage([current]) == 0)
        current.inputTokens = 140
        current.outputTokens = 30
        #expect(try repository.recordDetectedUsage([current]) == 1)
        let history = try repository.loadUsageHistory()
        #expect(history.usageSamples.first?.totalTokens == 313)
        #expect(history.modelUsageSamples.map(\.totalTokens).reduce(0, +) == 313)
        #expect(try repository.recordDetectedUsage([current]) == 0)
        #expect(try repository.loadUsageHistory() == history)
    }

    /// Root evidence can contain private messages; persistence and snapshot equality must use only usage metadata.
    @Test
    func transientGenericEvidenceIsNotEncodedAndDoesNotChangeUsageEquality() throws {
        var value = sample("evidence", .gemini, "model", 10, 2)
        value.genericContext = AIGenericUsageContext(document: Data(#"{"content":"fixture-private-message"}"#.utf8), path: [.key("usage")])
        let encoded = try JSONEncoder().encode(value)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains("fixture-private-message"))
        #expect(!json.contains("genericContext"))
        #expect(try JSONDecoder().decode(AIUsageSample.self, from: encoded) == value)
        #expect(try JSONDecoder().decode(AIUsageSample.self, from: encoded).genericContext == nil)
    }

    @Test(arguments: ["invalid", "-entry-no-file-usage-", "gemini-file-entry-bad", "gemini-file-usage-", ""])
    func malformedGenericPrefixesNeverCrashOrConsumeAnotherEvent(prefix: String) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        var value = sample("invalid-prefix", .gemini, "model", 10, 2)
        value.legacySourceID = prefix
        try repository.recordDetectedUsage([sample("gemini-file-entry-root-usage-x", .gemini, nil, 100, 20)])
        #expect(try repository.recordDetectedUsage([value]) == 1)
        #expect(try repository.loadUsageSamples().first?.totalTokens == 132)
        #expect(try repository.recordDetectedUsage([value]) == 0)
    }

    @Test
    func exactGenericRootProofNeverMatchesAnotherProvider() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let document = Data(#"{"timestamp":"2027-01-15T08:00:00Z","messages":[{"id":"old","usage":{"input_tokens":150,"output_tokens":20}}]}"#.utf8)
        var value = sample("gemini-file-usage-v2-old", .gemini, "model", 150, 20)
        value.legacySourceID = "gemini-file-entry-root-usage-"
        value.genericContext = .init(document: document, path: [.key("messages"), .index(0), .key("usage")])
        try repository.recordDetectedUsage([sample("gemini-file-entry-root-usage-0", .claude, nil, 150, 20)])
        #expect(try repository.recordDetectedUsage([value]) == 1)
        #expect(try repository.loadUsageSamples().first?.totalTokens == 340)
        #expect(try repository.loadUsageHistory().modelUsageSamples.contains { $0.provider == .gemini && $0.totalTokens == 170 })
    }

    /// A match found after exhausting the shared search budget cannot prove that no competing association exists.
    @Test(arguments: [30, 31])
    func genericRecoveryHashBudgetRejectsAPartiallyExaminedCandidateSet(priorCandidates: Int) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let timestamp = try Date.ISO8601FormatStyle().parse("2026-11-08T00:00:00Z")
        let canonical = Data(#"{"messages":[{"id":"old","usage":{"input_tokens":100,"output_tokens":20}}],"timestamp":"2026-11-08T00:00:00Z"}"#.utf8)
        let digest = AIUsageLogIdentity.digest(canonical)
        try repository.recordDetectedUsage(["a", "b"].map { file in
            AIUsageSample(sourceID: "gemini-\(file)-entry-\(digest)-usage-0", provider: .gemini,
                timestamp: timestamp, inputTokens: 100, outputTokens: 20)
        })
        let failedMessages = (0..<priorCandidates).map { index in
            ["id": "unrelated-\(index)", "usage": ["input_tokens": 150, "output_tokens": 20]] as [String: Any]
        }
        let firstDocument = try JSONSerialization.data(withJSONObject:
            ["timestamp": "2026-11-08T00:00:00Z", "messages": failedMessages], options: [.sortedKeys])
        var current = (0..<priorCandidates).map { index -> AIUsageSample in
            var value = AIUsageSample(sourceID: "gemini-a-usage-v2-\(index)", provider: .gemini,
                timestamp: timestamp, inputTokens: 150, outputTokens: 20, model: "unrelated",
                legacySourceID: "gemini-a-entry-current-usage-")
            value.genericContext = .init(document: firstDocument, path: [.key("messages"), .index(index), .key("usage")])
            return value
        }
        let secondDocument = Data(#"{"messages":[{"id":"old","usage":{"input_tokens":150,"output_tokens":20}},{"id":"new","usage":{"input_tokens":30,"output_tokens":5}}],"timestamp":"2026-11-08T00:00:00Z"}"#.utf8)
        for index in 0..<2 {
            var value = AIUsageSample(sourceID: "gemini-b-usage-v2-\(index)", provider: .gemini,
                timestamp: timestamp, inputTokens: index == 0 ? 150 : 30, outputTokens: index == 0 ? 20 : 5,
                model: index == 0 ? "current" : "fresh", legacySourceID: "gemini-b-entry-current-usage-")
            value.genericContext = .init(document: secondDocument, path: [.key("messages"), .index(index), .key("usage")])
            current.append(value)
        }
        let complete = priorCandidates == 30
        #expect(try repository.recordDetectedUsage(current) == (complete ? 1 : 0))
        #expect(try repository.loadUsageSamples().first?.totalTokens == (complete ? 325 : 240))
        var growth = try #require(current.first { $0.model == "current" })
        growth.inputTokens += 10
        #expect(try repository.recordDetectedUsage([growth]) == 1)
        #expect(try repository.loadUsageSamples().first?.totalTokens == (complete ? 335 : 250))
        #expect(try repository.recordDetectedUsage(Array(current.reversed())) == 0)
    }

    /// Two plausible histories cannot establish one message's baseline, so neither may consume the other's tokens.
    @Test(arguments: [false, true])
    func twoHistoricalRootsCannotAssignTheirBaselinesToTheSameCurrentMessage(reverse: Bool) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let timestamp = try Date.ISO8601FormatStyle().parse("2026-11-08T00:00:00Z")
        let documents = [100, 110].map { input in
            Data("{\"messages\":[{\"id\":\"old\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":20}}],\"timestamp\":\"2026-11-08T00:00:00Z\"}".utf8)
        }
        let history = documents.enumerated().map { index, document in
            AIUsageSample(sourceID: "gemini-conflict-entry-\(AIUsageLogIdentity.digest(document))-usage-0",
                provider: .gemini, timestamp: timestamp, inputTokens: index == 0 ? 100 : 110, outputTokens: 20)
        }
        try repository.recordDetectedUsage(reverse ? Array(history.reversed()) : history)
        var value = AIUsageSample(sourceID: "gemini-conflict-usage-v2-old", provider: .gemini,
            timestamp: timestamp, inputTokens: 150, outputTokens: 20, model: "current",
            legacySourceID: "gemini-conflict-entry-current-usage-")
        value.genericContext = .init(document: Data(#"{"messages":[{"id":"old","usage":{"input_tokens":150,"output_tokens":20}}],"timestamp":"2026-11-08T00:00:00Z"}"#.utf8),
            path: [.key("messages"), .index(0), .key("usage")])
        #expect(try repository.recordDetectedUsage([value]) == 0)
        #expect(try repository.loadUsageSamples().first?.totalTokens == 250)
        #expect(try repository.loadUsageHistory().modelUsageSamples.allSatisfy { $0.model == nil })
        value.inputTokens += 10
        #expect(try repository.recordDetectedUsage([value]) == 1)
        #expect(try repository.loadUsageSamples().first?.totalTokens == 260)
        #expect(try repository.loadUsageHistory().modelUsageSamples.contains { $0.model == "current" && $0.totalTokens == 10 })
    }

    /// A retired identifier may be observed again; its ledger must remain independent of the current source's baseline.
    @Test
    func reappearingLegacySourcePreservesItsLedgerWithoutBlockingCurrentRescans() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let prefix = "gemini-reappeared-entry-root-usage-"
        let old = sample(prefix + "0", .gemini, nil, 100, 20)
        try repository.recordDetectedUsage([old])
        var current = sample("gemini-reappeared-usage-v2-current", .gemini, "current", 150, 20)
        current.legacySourceID = prefix
        #expect(try repository.recordDetectedUsage([current]) == 0)
        #expect(try repository.recordDetectedUsage([old]) == 0)
        let before = try repository.loadUsageHistory()
        #expect(before.usageSamples.first?.totalTokens == 120)
        #expect(try repository.recordDetectedUsage([current]) == 0)
        #expect(try repository.loadUsageHistory() == before)
        current.inputTokens += 10
        #expect(try repository.recordDetectedUsage([current]) == 1)
        #expect(try repository.loadUsageSamples().first?.totalTokens == 130)
        #expect(try repository.loadUsageHistory().modelUsageSamples.contains { $0.model == "current" && $0.totalTokens == 10 })
        #expect(try repository.recordDetectedUsage([current]) == 0)
        var legacyGrowth = old
        legacyGrowth.inputTokens += 10
        #expect(try repository.recordDetectedUsage([legacyGrowth]) == 1)
        #expect(try repository.loadUsageSamples().first?.totalTokens == 140)
        #expect(try repository.recordDetectedUsage([old, legacyGrowth, current]) == 0)
    }

    /// Recovery needs the original serialized date form to prove identity while charging growth to the new recorded day.
    @Test(arguments: ["seconds", "milliseconds", "iso", "fractional"])
    func recoveryVerifiesSupportedHistoricalTimestampFormats(format: String) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let timestamp = try Date.ISO8601FormatStyle().parse("2026-11-08T00:00:00Z")
        let date: Any = switch format {
        case "seconds": timestamp.timeIntervalSince1970
        case "milliseconds": timestamp.timeIntervalSince1970 * 1_000
        case "fractional": timestamp.ISO8601Format(.init(includingFractionalSeconds: true))
        default: timestamp.ISO8601Format()
        }
        let oldDocument = try JSONSerialization.data(withJSONObject:
            ["timestamp": date, "messages": [["id": "old", "usage": ["input_tokens": 100, "output_tokens": 20]]]], options: [.sortedKeys])
        try repository.recordDetectedUsage([AIUsageSample(
            sourceID: "gemini-time-entry-\(AIUsageLogIdentity.digest(oldDocument))-usage-0", provider: .gemini,
            timestamp: timestamp, inputTokens: 100, outputTokens: 20, model: "unreliable-old-model")])
        var current = AIUsageSample(sourceID: "gemini-time-usage-v2-old", provider: .gemini,
            timestamp: timestamp.addingTimeInterval(172_800), inputTokens: 150, outputTokens: 20,
            model: "current", legacySourceID: "gemini-time-entry-current-usage-")
        current.genericContext = .init(document: Data(#"{"messages":[{"id":"old","model":"current","timestamp":"2026-11-10T00:00:00Z","usage":{"input_tokens":150,"output_tokens":20}}],"timestamp":"2026-11-10T00:00:00Z"}"#.utf8),
            path: [.key("messages"), .index(0), .key("usage")])
        #expect(try repository.recordDetectedUsage([current]) == 1)
        let history = try repository.loadUsageHistory()
        #expect(history.usageSamples.map(\.totalTokens) == [120, 50])
        #expect(history.modelUsageSamples.map(\.model) == [nil, "current"])
        #expect(try repository.recordDetectedUsage([current]) == 0)
    }

    /// Damaged evidence still consumes a candidate slot; discarding it first would let malformed inputs bypass the bound.
    @Test(arguments: [32, 33])
    func malformedEvidenceCannotBypassTheCompleteCandidateBudget(candidateCount: Int) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let timestamp = try Date.ISO8601FormatStyle().parse("2026-11-08T00:00:00Z")
        let oldDocument = Data(#"{"id":"old","timestamp":"2026-11-08T00:00:00Z","usage":{"input_tokens":100,"output_tokens":20}}"#.utf8)
        try repository.recordDetectedUsage([AIUsageSample(sourceID: "gemini-noise-entry-\(AIUsageLogIdentity.digest(oldDocument))-usage-0",
            provider: .gemini, timestamp: timestamp, inputTokens: 100, outputTokens: 20)])
        var current = AIUsageSample(sourceID: "gemini-noise-usage-v2-old", provider: .gemini,
            timestamp: timestamp, inputTokens: 150, outputTokens: 20, model: "current",
            legacySourceID: "gemini-noise-entry-current-usage-")
        current.genericContext = .init(document: Data(#"{"id":"old","timestamp":"2026-11-08T00:00:00Z","usage":{"input_tokens":150,"output_tokens":20}}"#.utf8), path: [.key("usage")])
        let damaged = (1..<candidateCount).map { index -> AIUsageSample in
            var value = AIUsageSample(sourceID: "gemini-noise-usage-v2-invalid-\(index)", provider: .gemini,
                timestamp: timestamp, inputTokens: 1, outputTokens: 0, model: "noise", legacySourceID: current.legacySourceID)
            value.genericContext = .init(document: Data("{truncated-\(index)".utf8), path: [.key("usage")])
            return value
        }
        #expect(try repository.recordDetectedUsage([current] + damaged) == (candidateCount == 32 ? 1 : 0))
        #expect(try repository.loadUsageSamples().first?.totalTokens == (candidateCount == 32 ? 201 : 120))
        current.inputTokens += 10
        #expect(try repository.recordDetectedUsage([current]) == 1)
        #expect(try repository.loadUsageSamples().first?.totalTokens == (candidateCount == 32 ? 211 : 130))
    }

    /// Repository callers can bypass the detector, so oversized evidence must establish only a future-growth baseline.
    @Test(arguments: [65_536, 65_537])
    func oversizedEvidenceCannotRecoverHistoryThroughDirectRepositoryInput(byteCount: Int) throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        let timestamp = try Date.ISO8601FormatStyle().parse("2026-11-08T00:00:00Z")
        var document: [String: Any] = ["id": "old", "timestamp": "2026-11-08T00:00:00Z", "padding": "",
            "usage": ["input_tokens": 100, "output_tokens": 20]]
        let empty = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        document["padding"] = String(repeating: "p", count: byteCount - empty.count)
        let oldDocument = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        #expect(oldDocument.count == byteCount)
        try repository.recordDetectedUsage([AIUsageSample(sourceID: "gemini-bytes-entry-\(AIUsageLogIdentity.digest(oldDocument))-usage-0",
            provider: .gemini, timestamp: timestamp, inputTokens: 100, outputTokens: 20)])
        document["usage"] = ["input_tokens": 150, "output_tokens": 20]
        var current = AIUsageSample(sourceID: "gemini-bytes-usage-v2-old", provider: .gemini,
            timestamp: timestamp, inputTokens: 150, outputTokens: 20, model: "current",
            legacySourceID: "gemini-bytes-entry-current-usage-")
        current.genericContext = .init(document: try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]), path: [.key("usage")])
        #expect(try repository.recordDetectedUsage([current]) == (byteCount == 65_536 ? 1 : 0))
        #expect(try repository.loadUsageSamples().first?.totalTokens == (byteCount == 65_536 ? 170 : 120))
        current.inputTokens += 10
        #expect(try repository.recordDetectedUsage([current]) == 1)
        #expect(try repository.loadUsageSamples().first?.totalTokens == (byteCount == 65_536 ? 180 : 130))
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

    /// Places fixtures inside a fixed calendar day so token assertions do not depend on the wall clock.
    private func sample(_ id: String, _ provider: AIProvider, _ model: String?, _ input: Int, _ output: Int) -> AIUsageSample {
        AIUsageSample(sourceID: id, provider: provider, timestamp: day.addingTimeInterval(10),
            inputTokens: input, outputTokens: output, model: model)
    }

    /// Gives each parallel test its own disposable database path, leaving the user's persisted history untouched.
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

    /// Reads the disposable database directly because hidden retained detail is absent from report projections.
    private func scalar(_ url: URL, _ query: String) throws -> Int64 {
        var database: OpaquePointer?
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        try #require(sqlite3_step(statement) == SQLITE_ROW)
        return sqlite3_column_int64(statement, 0)
    }
}
