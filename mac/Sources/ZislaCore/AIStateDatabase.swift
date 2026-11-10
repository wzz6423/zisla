import Foundation
import SQLite3

private let aiSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct DetectedUsageTotal {
    var timestamp: Date
    var inputTokens: Int
    var outputTokens: Int
}

final class AIStateDatabase {
    let url: URL
    private let maximumUsageSamples: Int
    private var connection: OpaquePointer?

    /// Creates the additive ledgers before older migrations can trim history, preserving existing daily totals.
    init(url: URL, maximumUsageSamples: Int) throws {
        self.url = url
        self.maximumUsageSamples = max(1, maximumUsageSamples)
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: directory.path
            )
            if !fileManager.fileExists(atPath: url.path) {
                guard fileManager.createFile(
                    atPath: url.path,
                    contents: nil,
                    attributes: [.posixPermissions: NSNumber(value: 0o600)]
                ) else {
                    throw AIStateRepositoryError.storageFailure(AppLocalization.text("无法创建私有 AI 状态数据库"))
                }
            }
            try setPrivateFilePermissions(using: fileManager)
        } catch let error as AIStateRepositoryError {
            throw error
        } catch {
            throw AIStateRepositoryError.storageFailure(error.localizedDescription)
        }

        var opened: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &opened,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let opened else {
            let message = sqliteMessage(opened, fallback: AppLocalization.text("无法打开 AI 状态数据库"))
            sqlite3_close(opened)
            throw AIStateRepositoryError.storageFailure(message)
        }
        connection = opened

        do {
            guard sqlite3_busy_timeout(opened, 1_000) == SQLITE_OK else {
                throw AIStateRepositoryError.storageFailure(
                    sqliteMessage(opened, fallback: AppLocalization.text("无法配置 AI 状态数据库"))
                )
            }
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=NORMAL")
            try execute("""
                CREATE TABLE IF NOT EXISTS tasks (
                    position INTEGER PRIMARY KEY AUTOINCREMENT,
                    id TEXT UNIQUE NOT NULL,
                    payload BLOB NOT NULL
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS usage_samples (
                    position INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_id TEXT UNIQUE,
                    provider TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    input_tokens INTEGER NOT NULL,
                    output_tokens INTEGER NOT NULL,
                    cost_usd REAL,
                    model TEXT
                )
                """)
            try execute("""
                CREATE INDEX IF NOT EXISTS usage_samples_timestamp
                ON usage_samples(timestamp)
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS detected_usage_cursor (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    timestamp REAL NOT NULL
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS detected_usage_baselines (
                    timestamp REAL PRIMARY KEY,
                    input_tokens INTEGER NOT NULL,
                    output_tokens INTEGER NOT NULL
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS notices (
                    position INTEGER PRIMARY KEY AUTOINCREMENT,
                    payload BLOB NOT NULL
                )
            """)
            try execute("""
                CREATE TABLE IF NOT EXISTS model_usage_samples (
                    timestamp REAL NOT NULL,
                    provider TEXT NOT NULL,
                    model TEXT NOT NULL,
                    origin TEXT NOT NULL,
                    input_tokens INTEGER NOT NULL,
                    output_tokens INTEGER NOT NULL,
                    PRIMARY KEY(timestamp, provider, model, origin)
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS detected_usage_daily (
                    source_id TEXT NOT NULL,
                    provider TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    model TEXT NOT NULL,
                    input_tokens INTEGER NOT NULL,
                    output_tokens INTEGER NOT NULL,
                    PRIMARY KEY(source_id, timestamp, model)
                )
                """)
            try execute("CREATE INDEX IF NOT EXISTS detected_usage_daily_timestamp ON detected_usage_daily(timestamp)")
            try migrateUsageToDailyTotalsIfNeeded()
            try migrateDetectedUsageCursorIfNeeded()
            try migrateDetectedUsageEventsIfNeeded()
            try migrateModelUsageIfNeeded()
            try setPrivateFilePermissions(using: fileManager)
        } catch {
            close()
            throw error
        }
    }

    deinit {
        close()
    }

    func trimUsageIfNeeded() throws {
        let countStatement = try prepare("SELECT COUNT(*) FROM usage_samples")
        defer { sqlite3_finalize(countStatement) }
        guard try stepHasRow(countStatement, fallback: AppLocalization.text("无法读取 AI 用量记录数量")),
              sqlite3_column_int64(countStatement, 0) > Int64(maximumUsageSamples) else {
            return
        }
        try trimUsage()
    }

    /// Loads both histories together only when requested so normal task snapshots stay small.
    func load(includeUsageSamples: Bool = true) throws -> AIState {
        AIState(
            tasks: try loadTasks(),
            usageSamples: includeUsageSamples ? try loadUsage() : [],
            notices: try loadNotices(),
            modelUsageSamples: includeUsageSamples ? try loadModelUsage() : []
        )
    }

    func loadUsageSamples(startingAt startDate: Date? = nil) throws -> [AIUsageSample] {
        try loadUsage(startingAt: startDate)
    }

    /// Reads aggregate and model rows in one transaction so concurrent writers cannot expose mismatched totals.
    func loadUsageHistory(startingAt startDate: Date?, endingBefore endDate: Date?) throws -> AIUsageHistory {
        try transaction {
            AIUsageHistory(usageSamples: try loadUsage(startingAt: startDate, endingBefore: endDate),
                modelUsageSamples: try loadModelUsage(startingAt: startDate, endingBefore: endDate))
        }
    }

    func upsertTask(_ task: AIProgressTask) throws {
        let statement = try prepare("""
            INSERT INTO tasks(id, payload) VALUES(?, ?)
            ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
            """)
        defer { sqlite3_finalize(statement) }
        try bind(task.id, to: 1, in: statement)
        try bind(try JSONEncoder().encode(task), to: 2, in: statement)
        try stepDone(statement)
    }

    func task(id: String) throws -> AIProgressTask? {
        let statement = try prepare("SELECT payload FROM tasks WHERE id = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        try bind(id, to: 1, in: statement)
        guard try stepHasRow(statement, fallback: AppLocalization.text("无法查询 AI 任务")) else { return nil }
        return try decode(AIProgressTask.self, from: blob(at: 0, in: statement))
    }

    func removeTask(id: String) throws -> Bool {
        let statement = try prepare("DELETE FROM tasks WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(id, to: 1, in: statement)
        try stepDone(statement)
        return sqlite3_changes(connection) > 0
    }

    func clearTasks() throws {
        try execute("DELETE FROM tasks")
    }

    /// Commits manual daily totals and model rows atomically; a failed model write must roll back both.
    @discardableResult
    func recordUsage(_ samples: [AIUsageSample]) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        guard samples.allSatisfy({ $0.timestamp.timeIntervalSinceReferenceDate.isFinite }) else {
            throw AIStateRepositoryError.corruptedState
        }
        return try transaction {
            let changed = try recordUsageDeltasInCurrentTransaction(
                AIUsageAnalytics.dailyUsageSamples(samples: samples, calendar: .current))
            try addModelUsage(AIUsageAnalytics.dailyModelUsageSamples(samples: samples), origin: "manual")
            try trimModelUsage()
            return changed
        }
    }

    /// Rejects invalid timestamps before migration or deduplication can mutate the ledger.
    @discardableResult
    func recordDetectedUsage(_ samples: [AIUsageSample]) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        guard samples.allSatisfy({ $0.timestamp.timeIntervalSinceReferenceDate.isFinite }) else {
            throw AIStateRepositoryError.corruptedState
        }
        return try transaction {
            try recordDetectedUsageInCurrentTransaction(samples)
        }
    }

    func enqueueNotices(_ notices: [IslandNotice]) throws {
        guard !notices.isEmpty else { return }
        try transaction {
            let statement = try prepare("INSERT INTO notices(payload) VALUES(?)")
            defer { sqlite3_finalize(statement) }
            for notice in notices {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(try JSONEncoder().encode(notice), to: 1, in: statement)
                try stepDone(statement)
            }
        }
    }

    private func loadTasks() throws -> [AIProgressTask] {
        let statement = try prepare("SELECT payload FROM tasks ORDER BY position")
        defer { sqlite3_finalize(statement) }
        var result: [AIProgressTask] = []
        while try stepHasRow(statement, fallback: AppLocalization.text("无法读取 AI 任务列表")) {
            result.append(try decode(AIProgressTask.self, from: blob(at: 0, in: statement)))
        }
        return result
    }

    /// Uses a half-open range so a briefing never includes the following day's aggregate.
    private func loadUsage(startingAt startDate: Date? = nil, endingBefore endDate: Date? = nil) throws -> [AIUsageSample] {
        let statement = try prepare("""
            SELECT source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model
            FROM usage_samples WHERE timestamp >= ? AND timestamp < ? ORDER BY position
            """
        )
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_double(statement, 1, startDate?.timeIntervalSinceReferenceDate ?? -Double.greatestFiniteMagnitude))
        try check(sqlite3_bind_double(statement, 2, endDate?.timeIntervalSinceReferenceDate ?? Double.greatestFiniteMagnitude))
        var result: [AIUsageSample] = []
        while try stepHasRow(statement, fallback: AppLocalization.text("无法读取 AI 用量记录")) {
            result.append(try usageSample(
                from: statement,
                sourceID: optionalText(at: 0, in: statement),
                columnOffset: 1
            ))
        }
        return result
    }

    /// Combines manual and detected origins only after reading the same bounded date range.
    private func loadModelUsage(startingAt startDate: Date? = nil, endingBefore endDate: Date? = nil) throws -> [AIUsageSample] {
        let statement = try prepare("""
            SELECT provider, timestamp, input_tokens, output_tokens, NULL, NULLIF(model, '')
            FROM model_usage_samples WHERE timestamp >= ? AND timestamp < ?
            ORDER BY timestamp, provider, model, origin
            """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_double(statement, 1, startDate?.timeIntervalSinceReferenceDate ?? -Double.greatestFiniteMagnitude))
        try check(sqlite3_bind_double(statement, 2, endDate?.timeIntervalSinceReferenceDate ?? Double.greatestFiniteMagnitude))
        var samples: [AIUsageSample] = []
        while try stepHasRow(statement, fallback: AppLocalization.text("无法读取 AI 用量记录")) {
            samples.append(try usageSample(from: statement, sourceID: nil, columnOffset: 0))
        }
        return AIUsageAnalytics.dailyModelUsageSamples(samples: samples)
    }

    private func migrateUsageToDailyTotalsIfNeeded() throws {
        guard try usageSchemaVersion() < 3 else { return }

        let samples = try loadUsage()
        let dailyTotals = AIUsageAnalytics.dailyUsageSamples(samples: samples, calendar: .current)
        let detectedTotals = AIUsageAnalytics.dailyUsageSamples(
            samples: samples.filter(AIUsageAnalytics.isLegacyDetectedUsageSample),
            calendar: .current
        )

        try transaction {
            try execute("DELETE FROM usage_samples")
            try execute("DELETE FROM detected_usage_baselines")
            _ = try recordUsageDeltasInCurrentTransaction(dailyTotals)
            for total in detectedTotals {
                try replaceDetectedUsageBaseline(DetectedUsageTotal(
                    timestamp: total.timestamp,
                    inputTokens: total.inputTokens,
                    outputTokens: total.outputTokens
                ))
            }
            try setUsageSchemaVersion(3)
        }
    }

    private func migrateDetectedUsageCursorIfNeeded() throws {
        guard try usageSchemaVersion() < 5 else { return }
        let legacyTotals = try legacyDetectedUsageTotals()

        try transaction {
            for total in legacyTotals {
                try replaceDetectedUsageBaseline(total)
            }
            try execute("DELETE FROM detected_usage_cursor")
            try execute("DROP TABLE IF EXISTS detected_usage_totals")
            try execute("DROP TABLE IF EXISTS detected_usage_events")
            try setUsageSchemaVersion(5)
        }
    }

    private func migrateDetectedUsageEventsIfNeeded() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS detected_usage_events (
                source_id TEXT PRIMARY KEY,
                provider TEXT NOT NULL,
                timestamp REAL NOT NULL,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                cost_usd REAL,
                model TEXT
            )
            """)
        try execute("""
            CREATE INDEX IF NOT EXISTS detected_usage_events_timestamp
            ON detected_usage_events(timestamp)
            """)
        guard try usageSchemaVersion() < 6 else { return }
        try setUsageSchemaVersion(6)
    }

    /// Backfills only surviving event metadata; old generic indices cannot prove their original model.
    private func migrateModelUsageIfNeeded() throws {
        guard try usageSchemaVersion() < 7 else { return }
        try transaction {
            try execute("DELETE FROM detected_usage_daily")
            try execute("DELETE FROM model_usage_samples")
            let statement = try prepare("""
                SELECT source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model
                FROM detected_usage_events ORDER BY timestamp, source_id
                """)
            defer { sqlite3_finalize(statement) }
            var days: Set<Date> = []
            while try stepHasRow(statement, fallback: AppLocalization.text("无法读取 AI 用量记录")) {
                var sample = try usageSample(from: statement, sourceID: optionalText(at: 0, in: statement), columnOffset: 1)
                if let sourceID = sample.sourceID, sourceID.contains("-entry-"), sourceID.contains("-usage-") {
                    sample.model = nil
                }
                try addDetectedModelDelta(sample)
                days.insert(Calendar.current.startOfDay(for: sample.timestamp))
            }
            for day in days.sorted() { try refreshDetectedModelUsage(at: day) }
            try trimModelUsage()
            try setUsageSchemaVersion(7)
        }
    }

    /// Keeps origins separate and saturates token sums so repeated manual increments cannot overflow.
    private func addModelUsage(_ samples: [AIUsageSample], origin: String) throws {
        let lookup = try prepare("""
            SELECT input_tokens, output_tokens FROM model_usage_samples
            WHERE timestamp = ? AND provider = ? AND model = ? AND origin = ?
            """)
        defer { sqlite3_finalize(lookup) }
        let insert = try prepare("""
            INSERT INTO model_usage_samples(timestamp, provider, model, origin, input_tokens, output_tokens)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(timestamp, provider, model, origin) DO UPDATE SET
                input_tokens = excluded.input_tokens, output_tokens = excluded.output_tokens
            """)
        defer { sqlite3_finalize(insert) }
        for sample in samples where sample.totalTokens > 0 {
            let day = Calendar.current.startOfDay(for: sample.timestamp)
            let model = AIUsageAnalytics.normalizedModel(sample.model) ?? ""
            sqlite3_reset(lookup)
            sqlite3_clear_bindings(lookup)
            try check(sqlite3_bind_double(lookup, 1, day.timeIntervalSinceReferenceDate))
            try bind(sample.provider.rawValue, to: 2, in: lookup)
            try bind(model, to: 3, in: lookup)
            try bind(origin, to: 4, in: lookup)
            let exists = try stepHasRow(lookup, fallback: AppLocalization.text("无法查询 AI 用量记录"))
            let input = AIUsageTokenMath.adding(exists ? tokenCount(at: 0, in: lookup) : 0, sample.inputTokens)
            let output = AIUsageTokenMath.adding(exists ? tokenCount(at: 1, in: lookup) : 0, sample.outputTokens)
            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
            try check(sqlite3_bind_double(insert, 1, day.timeIntervalSinceReferenceDate))
            try bind(sample.provider.rawValue, to: 2, in: insert)
            try bind(model, to: 3, in: insert)
            try bind(origin, to: 4, in: insert)
            try check(sqlite3_bind_int64(insert, 5, Int64(input)))
            try check(sqlite3_bind_int64(insert, 6, Int64(output)))
            try stepDone(insert)
        }
    }

    /// Splits each source by day and model so later cumulative updates never rewrite earlier usage.
    private func addDetectedModelDelta(_ sample: AIUsageSample) throws {
        guard sample.totalTokens > 0 else { return }
        let model = AIUsageAnalytics.normalizedModel(sample.model) ?? ""
        let day = Calendar.current.startOfDay(for: sample.timestamp)
        let lookup = try prepare("""
            SELECT input_tokens, output_tokens FROM detected_usage_daily
            WHERE source_id = ? AND timestamp = ? AND model = ?
            """)
        defer { sqlite3_finalize(lookup) }
        try bind(sample.sourceID, to: 1, in: lookup)
        try check(sqlite3_bind_double(lookup, 2, day.timeIntervalSinceReferenceDate))
        try bind(model, to: 3, in: lookup)
        let exists = try stepHasRow(lookup, fallback: AppLocalization.text("无法查询 AI 用量记录"))
        let input = AIUsageTokenMath.adding(exists ? tokenCount(at: 0, in: lookup) : 0, sample.inputTokens)
        let output = AIUsageTokenMath.adding(exists ? tokenCount(at: 1, in: lookup) : 0, sample.outputTokens)
        let insert = try prepare("""
            INSERT INTO detected_usage_daily(source_id, provider, timestamp, model, input_tokens, output_tokens)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_id, timestamp, model) DO UPDATE SET
                input_tokens = excluded.input_tokens, output_tokens = excluded.output_tokens
            """)
        defer { sqlite3_finalize(insert) }
        try bind(sample.sourceID, to: 1, in: insert)
        try bind(sample.provider.rawValue, to: 2, in: insert)
        try check(sqlite3_bind_double(insert, 3, day.timeIntervalSinceReferenceDate))
        try bind(model, to: 4, in: insert)
        try check(sqlite3_bind_int64(insert, 5, Int64(input)))
        try check(sqlite3_bind_int64(insert, 6, Int64(output)))
        try stepDone(insert)
    }

    /// Rebuilds a day's detected rows from its ledger after metadata enrichment or legacy identity changes.
    private func refreshDetectedModelUsage(at day: Date) throws {
        let delete = try prepare("DELETE FROM model_usage_samples WHERE timestamp = ? AND origin = 'detected'")
        defer { sqlite3_finalize(delete) }
        try check(sqlite3_bind_double(delete, 1, day.timeIntervalSinceReferenceDate))
        try stepDone(delete)
        let statement = try prepare("""
            SELECT provider, timestamp, input_tokens, output_tokens, NULL, NULLIF(model, '')
            FROM detected_usage_daily WHERE timestamp = ? ORDER BY source_id, model
            """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_double(statement, 1, day.timeIntervalSinceReferenceDate))
        var samples: [AIUsageSample] = []
        while try stepHasRow(statement, fallback: AppLocalization.text("无法读取 AI 用量记录")) {
            samples.append(try usageSample(from: statement, sourceID: nil, columnOffset: 0))
        }
        try addModelUsage(AIUsageAnalytics.dailyModelUsageSamples(samples: samples), origin: "detected")
    }

    /// Drops model rows only after their aggregate day is removed, preserving the retained-history boundary.
    private func trimModelUsage() throws {
        try execute("DELETE FROM model_usage_samples WHERE timestamp NOT IN (SELECT timestamp FROM usage_samples)")
    }

    private func legacyDetectedUsageTotals() throws -> [DetectedUsageTotal] {
        guard try tableExists("detected_usage_totals") else { return [] }
        let statement = try prepare("""
            SELECT timestamp, input_tokens, output_tokens
            FROM detected_usage_totals ORDER BY timestamp
            """)
        defer { sqlite3_finalize(statement) }
        var totals: [DetectedUsageTotal] = []
        while try stepHasRow(statement, fallback: AppLocalization.text("无法读取历史 AI 用量汇总")) {
            totals.append(DetectedUsageTotal(
                timestamp: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 0)),
                inputTokens: tokenCount(at: 1, in: statement),
                outputTokens: tokenCount(at: 2, in: statement)
            ))
        }
        return totals
    }

    private func tableExists(_ name: String) throws -> Bool {
        let statement = try prepare("""
            SELECT 1 FROM sqlite_master
            WHERE type = 'table' AND name = ? LIMIT 1
            """)
        defer { sqlite3_finalize(statement) }
        try bind(name, to: 1, in: statement)
        return try stepHasRow(statement, fallback: AppLocalization.text("无法查询 AI 状态数据库结构"))
    }

    private func recordUsageDeltasInCurrentTransaction(_ samples: [AIUsageSample]) throws -> Int {
        let lookup = try prepare("""
            SELECT provider, timestamp, input_tokens, output_tokens, cost_usd, model
            FROM usage_samples WHERE source_id = ? LIMIT 1
            """)
        defer { sqlite3_finalize(lookup) }
        let insert = try prepare("""
            INSERT INTO usage_samples(
                source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model
            ) VALUES(?, ?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(insert) }
        let update = try prepare("""
            UPDATE usage_samples SET
                provider = ?, timestamp = ?, input_tokens = ?, output_tokens = ?,
                cost_usd = ?, model = ?
            WHERE source_id = ?
            """)
        defer { sqlite3_finalize(update) }

        var inserted = 0
        for sample in samples {
            guard let sourceID = sample.sourceID else { continue }
            sqlite3_reset(lookup)
            sqlite3_clear_bindings(lookup)
            try bind(sourceID, to: 1, in: lookup)
            if try stepHasRow(lookup, fallback: AppLocalization.text("无法查询 AI 用量记录")) {
                let existing = try usageSample(
                    from: lookup,
                    sourceID: sourceID,
                    columnOffset: 0
                )
                let next = AIUsageSample(
                    sourceID: sourceID,
                    provider: existing.provider,
                    timestamp: existing.timestamp,
                    inputTokens: AIUsageTokenMath.adding(existing.inputTokens, sample.inputTokens),
                    outputTokens: AIUsageTokenMath.adding(existing.outputTokens, sample.outputTokens),
                    costUSD: existing.costUSD ?? sample.costUSD,
                    model: existing.model ?? sample.model
                )
                guard existing != next else { continue }
                sqlite3_reset(update)
                sqlite3_clear_bindings(update)
                try bindUpdate(next, to: update)
                try stepDone(update)
                inserted += 1
                continue
            }

            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
            try bind(sample, to: insert)
            try stepDone(insert)
            inserted += 1
        }
        try trimUsageIfNeeded()
        return inserted
    }

    /// Advances cumulative high-water marks and emits only new daily deltas, including metadata-only updates.
    private func recordDetectedUsageInCurrentTransaction(_ samples: [AIUsageSample]) throws -> Int {
        let legacyCursor = try detectedUsageCursor()
        let lookup = try prepare("""
            SELECT provider, timestamp, input_tokens, output_tokens, cost_usd, model
            FROM detected_usage_events WHERE source_id = ? LIMIT 1
            """)
        defer { sqlite3_finalize(lookup) }
        let insert = try prepare("""
            INSERT INTO detected_usage_events(
                source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model
            ) VALUES(?, ?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(insert) }
        let update = try prepare("""
            UPDATE detected_usage_events SET
                provider = ?, timestamp = ?, input_tokens = ?, output_tokens = ?,
                cost_usd = ?, model = ?
            WHERE source_id = ?
            """)
        defer { sqlite3_finalize(update) }

        var rawDeltasByDay: [Date: AIUsageSample] = [:]
        var cursorDeltas: [AIUsageSample] = []
        var modelDays: Set<Date> = []
        let ambiguousGenericSources = try prepareGenericUsageMigration(samples, using: lookup, modelDays: &modelDays)
        for sample in samples {
            let sourceID = detectedUsageSourceID(for: sample)
            let normalized = AIUsageSample(
                sourceID: sourceID,
                provider: sample.provider,
                timestamp: sample.timestamp,
                inputTokens: AIUsageTokenMath.nonnegative(sample.inputTokens),
                outputTokens: AIUsageTokenMath.nonnegative(sample.outputTokens),
                costUSD: sample.costUSD,
                model: AIUsageAnalytics.normalizedModel(sample.model)
            )

            var existing = try detectedUsageEvent(sourceID: sourceID, using: lookup)
            if existing == nil {
                try migrateLegacyDetectedUsageEventIfNeeded(for: normalized)
                existing = try detectedUsageEvent(sourceID: sourceID, using: lookup)
            }
            if let existing {
                let inputDelta = max(0, normalized.inputTokens - existing.inputTokens)
                let outputDelta = max(0, normalized.outputTokens - existing.outputTokens)
                let addsMetadata = (existing.costUSD == nil && normalized.costUSD != nil)
                    || (existing.model == nil && normalized.model != nil)
                guard inputDelta > 0 || outputDelta > 0 || addsMetadata else { continue }

                let updated = AIUsageSample(
                    sourceID: sourceID,
                    provider: existing.provider,
                    timestamp: inputDelta > 0 || outputDelta > 0
                        ? max(existing.timestamp, normalized.timestamp) : existing.timestamp,
                    inputTokens: AIUsageTokenMath.adding(existing.inputTokens, inputDelta),
                    outputTokens: AIUsageTokenMath.adding(existing.outputTokens, outputDelta),
                    costUSD: existing.costUSD ?? normalized.costUSD,
                    model: existing.model ?? normalized.model
                )
                sqlite3_reset(update)
                sqlite3_clear_bindings(update)
                try bindUpdate(updated, to: update)
                try stepDone(update)
                if existing.model == nil, let model = updated.model,
                   normalized.timestamp == existing.timestamp, inputDelta == 0, outputDelta == 0 {
                    let day = Calendar.current.startOfDay(for: existing.timestamp)
                    let enrich = try prepare("""
                        UPDATE detected_usage_daily SET model = ?
                        WHERE source_id = ? AND model = '' AND timestamp = ?
                            AND (SELECT COUNT(*) FROM detected_usage_daily WHERE source_id = ?) = 1
                        """)
                    defer { sqlite3_finalize(enrich) }
                    try bind(model, to: 1, in: enrich)
                    try bind(sourceID, to: 2, in: enrich)
                    try check(sqlite3_bind_double(enrich, 3, day.timeIntervalSinceReferenceDate))
                    try bind(sourceID, to: 4, in: enrich)
                    try stepDone(enrich)
                    if sqlite3_changes(connection) > 0 { modelDays.insert(day) }
                }
                if inputDelta > 0 || outputDelta > 0 {
                    let delta = AIUsageSample(
                        sourceID: sourceID,
                        provider: existing.provider,
                        timestamp: updated.timestamp,
                        inputTokens: inputDelta,
                        outputTokens: outputDelta,
                        model: normalized.model
                    )
                    try addDetectedModelDelta(delta)
                    modelDays.insert(Calendar.current.startOfDay(for: delta.timestamp))
                    appendDetectedUsageDelta(delta, to: &rawDeltasByDay)
                    if legacyCursor.map({ delta.timestamp > $0 }) ?? false {
                        cursorDeltas.append(delta)
                    }
                }
                continue
            }

            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
            try bind(normalized, to: insert)
            try stepDone(insert)
            guard !ambiguousGenericSources.contains(sourceID) else { continue }
            try addDetectedModelDelta(normalized)
            modelDays.insert(Calendar.current.startOfDay(for: normalized.timestamp))
            appendDetectedUsageDelta(normalized, to: &rawDeltasByDay)
            if legacyCursor.map({ normalized.timestamp > $0 }) ?? false {
                cursorDeltas.append(normalized)
            }
        }

        let dailyDeltas: [AIUsageSample]
        if legacyCursor != nil {
            dailyDeltas = AIUsageAnalytics.dailyUsageSamples(
                samples: cursorDeltas,
                calendar: .current
            )
        } else {
            dailyDeltas = try visibleDetectedUsageDeltas(from: rawDeltasByDay)
        }
        let changed = try recordUsageDeltasInCurrentTransaction(dailyDeltas)
        if legacyCursor != nil {
            try execute("DELETE FROM detected_usage_cursor")
        }
        for day in modelDays.sorted() { try refreshDetectedModelUsage(at: day) }
        try trimModelUsage()
        return changed
    }

    private func appendDetectedUsageDelta(
        _ delta: AIUsageSample,
        to deltasByDay: inout [Date: AIUsageSample]
    ) {
        guard delta.inputTokens > 0 || delta.outputTokens > 0 else { return }
        let day = Calendar.current.startOfDay(for: delta.timestamp)
        if var existing = deltasByDay[day] {
            existing.inputTokens = AIUsageTokenMath.adding(existing.inputTokens, delta.inputTokens)
            existing.outputTokens = AIUsageTokenMath.adding(existing.outputTokens, delta.outputTokens)
            deltasByDay[day] = existing
        } else {
            deltasByDay[day] = AIUsageSample(
                provider: delta.provider,
                timestamp: day,
                inputTokens: delta.inputTokens,
                outputTokens: delta.outputTokens
            )
        }
    }

    private func visibleDetectedUsageDeltas(
        from rawDeltasByDay: [Date: AIUsageSample]
    ) throws -> [AIUsageSample] {
        var visible: [AIUsageSample] = []
        for day in rawDeltasByDay.keys.sorted() {
            guard let rawDelta = rawDeltasByDay[day] else { continue }
            let observed = try detectedUsageEventTotal(at: day)
            let baseline = try detectedUsageBaseline(at: day)
            let previousInput = max(0, observed.inputTokens - rawDelta.inputTokens)
            let previousOutput = max(0, observed.outputTokens - rawDelta.outputTokens)
            let inputDelta = max(0, observed.inputTokens - baseline.inputTokens)
                - max(0, previousInput - baseline.inputTokens)
            let outputDelta = max(0, observed.outputTokens - baseline.outputTokens)
                - max(0, previousOutput - baseline.outputTokens)
            guard inputDelta > 0 || outputDelta > 0 else { continue }
            visible.append(AIUsageSample(
                provider: rawDelta.provider,
                timestamp: day,
                inputTokens: inputDelta,
                outputTokens: outputDelta
            ))
        }
        return AIUsageAnalytics.dailyUsageSamples(samples: visible, calendar: .current)
    }

    /// Uses daily deltas rather than cumulative event snapshots so growth across midnight stays on its new day.
    private func detectedUsageEventTotal(at day: Date) throws -> DetectedUsageTotal {
        let statement = try prepare("""
            SELECT input_tokens, output_tokens
            FROM detected_usage_daily WHERE timestamp = ?
            """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_double(statement, 1, day.timeIntervalSinceReferenceDate))
        var inputTokens = 0
        var outputTokens = 0
        while try stepHasRow(statement, fallback: AppLocalization.text("无法读取 AI 用量事件汇总")) {
            inputTokens = AIUsageTokenMath.adding(
                inputTokens,
                tokenCount(at: 0, in: statement)
            )
            outputTokens = AIUsageTokenMath.adding(
                outputTokens,
                tokenCount(at: 1, in: statement)
            )
        }
        return DetectedUsageTotal(
            timestamp: day,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    private func detectedUsageBaseline(at day: Date) throws -> DetectedUsageTotal {
        let statement = try prepare("""
            SELECT input_tokens, output_tokens
            FROM detected_usage_baselines WHERE timestamp = ? LIMIT 1
            """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_double(statement, 1, day.timeIntervalSinceReferenceDate))
        guard try stepHasRow(statement, fallback: AppLocalization.text("无法读取 AI 用量基线")) else {
            return DetectedUsageTotal(timestamp: day, inputTokens: 0, outputTokens: 0)
        }
        return DetectedUsageTotal(
            timestamp: day,
            inputTokens: tokenCount(at: 0, in: statement),
            outputTokens: tokenCount(at: 1, in: statement)
        )
    }

    private func replaceDetectedUsageBaseline(_ total: DetectedUsageTotal) throws {
        let statement = try prepare("""
            INSERT INTO detected_usage_baselines(timestamp, input_tokens, output_tokens)
            VALUES(?, ?, ?)
            ON CONFLICT(timestamp) DO UPDATE SET
                input_tokens = excluded.input_tokens,
                output_tokens = excluded.output_tokens
            """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_double(statement, 1, total.timestamp.timeIntervalSinceReferenceDate))
        try check(sqlite3_bind_int64(
            statement,
            2,
            Int64(AIUsageTokenMath.nonnegative(total.inputTokens))
        ))
        try check(sqlite3_bind_int64(
            statement,
            3,
            Int64(AIUsageTokenMath.nonnegative(total.outputTokens))
        ))
        try stepDone(statement)
    }

    private func detectedUsageSourceID(for sample: AIUsageSample) -> String {
        if let sourceID = sample.sourceID, !sourceID.isEmpty {
            return sourceID
        }
        let timestamp = String(sample.timestamp.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
        return "zisla-detected-anonymous:\(sample.provider.rawValue):\(timestamp):\(sample.model ?? "")"
    }

    private func detectedUsageEvent(
        sourceID: String,
        using statement: OpaquePointer?
    ) throws -> AIUsageSample? {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bind(sourceID, to: 1, in: statement)
        guard try stepHasRow(statement, fallback: AppLocalization.text("无法查询检测到的 AI 用量记录")) else {
            return nil
        }
        return try usageSample(from: statement, sourceID: sourceID, columnOffset: 0)
    }

    /// Renames only an unambiguous old identity so rescans cannot claim a different source's history.
    private func migrateLegacyDetectedUsageEventIfNeeded(for sample: AIUsageSample) throws {
        guard let sourceID = sample.sourceID,
              let legacySourceID = try uniqueLegacyDetectedUsageSourceID(
                for: sourceID,
                provider: sample.provider,
                timestamp: sample.timestamp
              ) else {
            return
        }

        let statement = try prepare("""
            UPDATE detected_usage_events SET source_id = ?
            WHERE source_id = ?
            """)
        defer { sqlite3_finalize(statement) }
        try bind(sourceID, to: 1, in: statement)
        try bind(legacySourceID, to: 2, in: statement)
        try stepDone(statement)
        let daily = try prepare("UPDATE detected_usage_daily SET source_id = ? WHERE source_id = ?")
        defer { sqlite3_finalize(daily) }
        try bind(sourceID, to: 1, in: daily)
        try bind(legacySourceID, to: 2, in: daily)
        try stepDone(daily)
    }

    /// Archives unverifiable legacy model metadata while retaining the old day's numeric ledger.
    private func archiveGenericUsage(_ samples: [AIUsageSample], modelDays: inout Set<Date>) throws {
        for sample in samples {
            guard let oldID = sample.sourceID else { continue }
            let rows = try prepare("""
                SELECT provider, timestamp, input_tokens, output_tokens, NULL, NULL
                FROM detected_usage_daily WHERE source_id = ?
                """)
            defer { sqlite3_finalize(rows) }
            try bind(oldID, to: 1, in: rows)
            var history: [AIUsageSample] = []
            while try stepHasRow(rows, fallback: AppLocalization.text("无法读取 AI 用量记录")) {
                history.append(try usageSample(from: rows, sourceID: "zisla-legacy-generic:\(oldID)", columnOffset: 0))
            }
            let delete = try prepare("DELETE FROM detected_usage_daily WHERE source_id = ?")
            defer { sqlite3_finalize(delete) }
            try bind(oldID, to: 1, in: delete)
            try stepDone(delete)
            for row in history {
                try addDetectedModelDelta(row)
                modelDays.insert(row.timestamp)
            }
            let event = try prepare("""
                INSERT INTO detected_usage_events(source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model)
                SELECT ?, provider, timestamp, input_tokens, output_tokens, cost_usd, NULL
                FROM detected_usage_events WHERE source_id = ?
                ON CONFLICT(source_id) DO UPDATE SET
                    timestamp = MAX(timestamp, excluded.timestamp),
                    input_tokens = MAX(input_tokens, excluded.input_tokens),
                    output_tokens = MAX(output_tokens, excluded.output_tokens), model = NULL
                """)
            defer { sqlite3_finalize(event) }
            try bind("zisla-legacy-generic:\(oldID)", to: 1, in: event)
            try bind(oldID, to: 2, in: event)
            try stepDone(event)
            let remove = try prepare("DELETE FROM detected_usage_events WHERE source_id = ?")
            defer { sqlite3_finalize(remove) }
            try bind(oldID, to: 1, in: remove)
            try stepDone(remove)
        }
    }

    /// Resolves the whole scan before any high-water mark advances, so input order cannot spend unrelated history.
    private func prepareGenericUsageMigration(_ samples: [AIUsageSample], using lookup: OpaquePointer?,
        modelDays: inout Set<Date>) throws -> Set<String> {
        let generic = samples.filter { genericFileKey($0.legacySourceID) != nil }
        let groups = Dictionary(grouping: generic) { sample in
            genericFileKey(sample.legacySourceID)!
        }
        var ambiguous: Set<String> = []
        var hashesRemaining = AIGenericUsageContext.maximumRecoveryHashes
        for fileKey in groups.keys.sorted() {
            let current = groups[fileKey]!.sorted { ($0.sourceID ?? "") < ($1.sourceID ?? "") }
            let prefix = fileKey + "-entry-"
            let old = try prepare("""
                SELECT source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model
                FROM detected_usage_events WHERE source_id >= ? AND source_id < ?
                ORDER BY source_id
                """)
            defer { sqlite3_finalize(old) }
            try bind(prefix, to: 1, in: old)
            try bind(fileKey + "-entry.", to: 2, in: old)
            var legacy: [AIUsageSample] = []
            while try stepHasRow(old, fallback: AppLocalization.text("无法读取 AI 用量记录")) {
                let sample = try usageSample(from: old, sourceID: optionalText(at: 0, in: old), columnOffset: 1)
                if genericRootKey(sample.sourceID) != nil, current.contains(where: { $0.provider == sample.provider }) {
                    legacy.append(sample)
                }
            }
            guard !legacy.isEmpty else { continue }
            var unresolved: Set<String> = []
            for sample in current {
                if let sourceID = sample.sourceID,
                   try detectedUsageEvent(sourceID: sourceID, using: lookup) == nil {
                    unresolved.insert(sourceID)
                }
            }
            let roots = Dictionary(grouping: legacy) { sample in
                genericRootKey(sample.sourceID)!
            }
            var matched: [String: AIUsageSample] = [:]
            var conflicting: Set<String> = []
            var verifiedRoots: Set<String> = []
            for rootKey in roots.keys.sorted() {
                let history = roots[rootKey]!
                let exact = current.filter { candidate in
                    candidate.legacySourceID == rootKey && unresolved.contains(candidate.sourceID ?? "")
                        && history.allSatisfy { $0.provider == candidate.provider }
                }
                if history.count == exact.count && tokenMultiset(history) == tokenMultiset(exact) {
                    for sample in exact {
                        if let sourceID = sample.sourceID {
                            if matched[sourceID] != nil { conflicting.insert(sourceID) }
                            matched[sourceID] = sample
                        }
                    }
                    verifiedRoots.insert(rootKey)
                    continue
                }
                guard history.count == 1, let historical = history.first else { continue }
                let candidates = current.filter {
                    unresolved.contains($0.sourceID ?? "") && $0.provider == historical.provider
                        && $0.genericContext != nil
                }
                guard candidates.count <= AIGenericUsageContext.maximumRecoveryCandidates else { continue }
                var recovered: [AIUsageSample] = []
                for candidate in candidates {
                    if verifiesGenericContext(candidate, historical: historical, hashesRemaining: &hashesRemaining) {
                        recovered.append(candidate)
                    }
                }
                if hashesRemaining > 0, recovered.count == 1, let candidate = recovered.first, let sourceID = candidate.sourceID {
                    var baseline = candidate
                    baseline.inputTokens = historical.inputTokens
                    baseline.outputTokens = historical.outputTokens
                    if matched[sourceID] != nil { conflicting.insert(sourceID) }
                    matched[sourceID] = baseline
                    verifiedRoots.insert(rootKey)
                }
            }
            for sourceID in conflicting { matched.removeValue(forKey: sourceID) }
            try archiveGenericUsage(legacy, modelDays: &modelDays)
            let baseline = try prepare("""
                INSERT INTO detected_usage_events(source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model)
                VALUES(?,?,?,?,?,?,?)
                """)
            defer { sqlite3_finalize(baseline) }
            for sourceID in matched.keys.sorted() {
                var value = matched[sourceID]!
                value.model = current.first { $0.sourceID == sourceID }?.model
                sqlite3_reset(baseline)
                sqlite3_clear_bindings(baseline)
                try bind(value, to: baseline)
                try stepDone(baseline)
                unresolved.remove(sourceID)
            }
            if verifiedRoots.count < roots.count || !conflicting.isEmpty {
                ambiguous.formUnion(unresolved)
            }
        }
        return ambiguous
    }

    /// Accepts only the old provider/file/root delimiter shape, preventing malformed prefixes from grouping other events.
    private func genericFileKey(_ prefix: String?) -> String? {
        guard let prefix, prefix.hasSuffix("-usage-"), let entry = prefix.range(of: "-entry-"),
              entry.lowerBound > prefix.startIndex,
              let usage = prefix.range(of: "-usage-", options: .backwards),
              entry.upperBound < usage.lowerBound else { return nil }
        return String(prefix[..<entry.lowerBound])
    }

    /// The old traversal index establishes root membership only; it cannot identify a message inside that root.
    private func genericRootKey(_ sourceID: String?) -> String? {
        guard let sourceID, let usage = sourceID.range(of: "-usage-", options: .backwards),
              !sourceID[usage.upperBound...].isEmpty,
              sourceID[usage.upperBound...].allSatisfy({ $0.isNumber }),
              genericFileKey(String(sourceID[..<usage.upperBound])) != nil else { return nil }
        return String(sourceID[..<usage.upperBound])
    }

    /// Checks whole-root quantities without pairing messages through the old unordered traversal index.
    private func tokenMultiset(_ samples: [AIUsageSample]) -> [String] {
        samples.map { "\($0.inputTokens):\($0.outputTokens)" }.sorted()
    }

    /// Only a regenerated old root digest proves that a changed message owns a historical token baseline.
    private func verifiesGenericContext(_ sample: AIUsageSample, historical: AIUsageSample,
        hashesRemaining: inout Int) -> Bool {
        guard hashesRemaining > 0, let context = sample.genericContext,
              context.document.count <= AIGenericUsageContext.maximumDocumentBytes,
              let root = try? JSONSerialization.jsonObject(with: context.document) as? [String: Any],
              let historicalID = historical.sourceID,
              let digestStart = historicalID.range(of: "-entry-"),
              let digestEnd = historicalID.range(of: "-usage-", options: .backwards),
              digestStart.upperBound <= digestEnd.lowerBound else { return false }
        let digest = String(historicalID[digestStart.upperBound..<digestEnd.lowerBound])
        let dates: [Any] = [
            historical.timestamp.timeIntervalSince1970,
            historical.timestamp.timeIntervalSince1970 * 1_000,
            historical.timestamp.ISO8601Format(),
            historical.timestamp.ISO8601Format(.init(includingFractionalSeconds: true))
        ]
        for date in dates {
            for stripsMetadata in [false, true] {
                for removesMessageDate in [false, true] {
                    guard hashesRemaining > 0 else { return false }
                    guard let recovered = recoveredGenericDocument(root, path: context.path, historical: historical,
                        date: date, stripsMetadata: stripsMetadata, removesMessageDate: removesMessageDate),
                          let data = try? JSONSerialization.data(withJSONObject: recovered, options: [.sortedKeys]) else { continue }
                    hashesRemaining -= 1
                    if AIUsageLogIdentity.digest(data) == digest { return true }
                }
            }
        }
        return false
    }

    /// Removes appended siblings and restores only recorded numeric/date fields; unrelated message content stays untouched.
    private func recoveredGenericDocument(_ value: Any, path: [AIGenericUsageContext.PathComponent],
        historical: AIUsageSample, date: Any, stripsMetadata: Bool, removesMessageDate: Bool, isRoot: Bool = true) -> Any? {
        guard let first = path.first else {
            guard var usage = value as? [String: Any] else { return nil }
            let inputKeys = ["input_tokens", "inputTokens", "prompt_tokens", "promptTokens", "promptTokenCount", "prompt_token_count"]
            let outputKeys = ["output_tokens", "outputTokens", "completion_tokens", "completionTokens", "candidatesTokenCount", "candidates_token_count"]
            for key in inputKeys where usage[key] != nil { usage[key] = historical.inputTokens }
            for key in outputKeys where usage[key] != nil { usage[key] = historical.outputTokens }
            return usage
        }
        switch first {
        case let .index(index):
            guard let values = value as? [Any], values.indices.contains(index),
                  let recovered = recoveredGenericDocument(values[index], path: Array(path.dropFirst()),
                    historical: historical, date: date, stripsMetadata: stripsMetadata,
                    removesMessageDate: removesMessageDate, isRoot: false) else { return nil }
            return [recovered]
        case let .key(key):
            guard var dictionary = value as? [String: Any], let child = dictionary[key],
                  let recovered = recoveredGenericDocument(child, path: Array(path.dropFirst()),
                    historical: historical, date: date, stripsMetadata: stripsMetadata,
                    removesMessageDate: removesMessageDate, isRoot: false) else { return nil }
            dictionary[key] = recovered
            let dateKeys = ["timestamp", "ts", "created_at", "createdAt"]
            for dateKey in dateKeys where dictionary[dateKey] != nil {
                if removesMessageDate && !isRoot { dictionary.removeValue(forKey: dateKey) }
                else { dictionary[dateKey] = date }
            }
            if stripsMetadata { dictionary.removeValue(forKey: "model") }
            return dictionary
        }
    }

    private func uniqueLegacyDetectedUsageSourceID(
        for sourceID: String,
        provider: AIProvider,
        timestamp: Date
    ) throws -> String? {
        if let range = sourceID.range(of: "-update-v2-", options: .backwards) {
            return try uniqueLegacyDetectedUsageSourceID(
                matching: String(sourceID[..<range.lowerBound]),
                provider: provider,
                timestamp: timestamp
            )
        }
        if let range = sourceID.range(of: "-event-v2-") {
            return try uniqueLegacyDetectedUsageSourceID(
                matchingPrefix: String(sourceID[..<range.lowerBound]) + "-event-",
                provider: provider,
                timestamp: timestamp
            )
        }
        return nil
    }

    private func uniqueLegacyDetectedUsageSourceID(
        matching sourceID: String,
        provider: AIProvider,
        timestamp: Date
    ) throws -> String? {
        let statement = try prepare("""
            SELECT source_id FROM detected_usage_events
            WHERE source_id = ? AND provider = ? AND timestamp = ?
            LIMIT 2
            """)
        defer { sqlite3_finalize(statement) }
        try bind(sourceID, to: 1, in: statement)
        try bind(provider.rawValue, to: 2, in: statement)
        try check(sqlite3_bind_double(statement, 3, timestamp.timeIntervalSinceReferenceDate))
        return try uniqueDetectedUsageSourceID(from: statement)
    }

    private func uniqueLegacyDetectedUsageSourceID(
        matchingPrefix prefix: String,
        provider: AIProvider,
        timestamp: Date
    ) throws -> String? {
        let statement = try prepare("""
            SELECT source_id FROM detected_usage_events
            WHERE source_id LIKE ? AND source_id NOT LIKE ?
                AND provider = ? AND timestamp = ?
            ORDER BY source_id
            LIMIT 2
            """)
        defer { sqlite3_finalize(statement) }
        try bind(prefix + "%", to: 1, in: statement)
        try bind(prefix + "v2-%", to: 2, in: statement)
        try bind(provider.rawValue, to: 3, in: statement)
        try check(sqlite3_bind_double(statement, 4, timestamp.timeIntervalSinceReferenceDate))
        return try uniqueDetectedUsageSourceID(from: statement)
    }

    private func uniqueDetectedUsageSourceID(from statement: OpaquePointer?) throws -> String? {
        var sourceIDs: [String] = []
        while try stepHasRow(statement, fallback: AppLocalization.text("无法查询旧版检测到的 AI 用量记录")) {
            guard let sourceID = optionalText(at: 0, in: statement) else { continue }
            sourceIDs.append(sourceID)
        }
        return sourceIDs.count == 1 ? sourceIDs[0] : nil
    }

    private func detectedUsageCursor() throws -> Date? {
        let statement = try prepare("SELECT timestamp FROM detected_usage_cursor WHERE id = 1 LIMIT 1")
        defer { sqlite3_finalize(statement) }
        guard try stepHasRow(statement, fallback: AppLocalization.text("无法读取 AI 用量游标")) else { return nil }
        return Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 0))
    }

    private func replaceDetectedUsageCursor(_ timestamp: Date) throws {
        let statement = try prepare("""
            INSERT INTO detected_usage_cursor(id, timestamp) VALUES(1, ?)
            ON CONFLICT(id) DO UPDATE SET timestamp = excluded.timestamp
            """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_double(statement, 1, timestamp.timeIntervalSinceReferenceDate))
        try stepDone(statement)
    }

    private func usageSchemaVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard try stepHasRow(statement, fallback: AppLocalization.text("无法读取 AI 用量存储版本")) else {
            throw AIStateRepositoryError.storageFailure(AppLocalization.text("无法读取 AI 用量存储版本"))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func setUsageSchemaVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    private func loadNotices() throws -> [IslandNotice] {
        let statement = try prepare("SELECT payload FROM notices ORDER BY position")
        defer { sqlite3_finalize(statement) }
        var result: [IslandNotice] = []
        while try stepHasRow(statement, fallback: AppLocalization.text("无法读取通知列表")) {
            result.append(try decode(IslandNotice.self, from: blob(at: 0, in: statement)))
        }
        return result
    }

    private func setPrivateFilePermissions(using fileManager: FileManager) throws {
        let privateFiles = [
            url,
            URL(fileURLWithPath: url.path + "-journal"),
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
        ]
        for file in privateFiles where fileManager.fileExists(atPath: file.path) {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: file.path
            )
        }
    }

    /// Validates stored providers and timestamps before exposing any persisted row as usage.
    private func usageSample(
        from statement: OpaquePointer?,
        sourceID: String?,
        columnOffset: Int32
    ) throws -> AIUsageSample {
        guard let providerText = optionalText(at: columnOffset, in: statement),
              let provider = AIProvider(rawValue: providerText),
              sqlite3_column_double(statement, columnOffset + 1).isFinite else {
            throw AIStateRepositoryError.corruptedState
        }
        return AIUsageSample(
            sourceID: sourceID,
            provider: provider,
            timestamp: Date(
                timeIntervalSinceReferenceDate: sqlite3_column_double(statement, columnOffset + 1)
            ),
            inputTokens: tokenCount(at: columnOffset + 2, in: statement),
            outputTokens: tokenCount(at: columnOffset + 3, in: statement),
            costUSD: sqlite3_column_type(statement, columnOffset + 4) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(statement, columnOffset + 4),
            model: optionalText(at: columnOffset + 5, in: statement)
        )
    }

    private func bind(_ sample: AIUsageSample, to statement: OpaquePointer?) throws {
        try bind(sample.sourceID, to: 1, in: statement)
        try bind(sample.provider.rawValue, to: 2, in: statement)
        try check(sqlite3_bind_double(
            statement,
            3,
            sample.timestamp.timeIntervalSinceReferenceDate
        ))
        try check(sqlite3_bind_int64(
            statement,
            4,
            Int64(AIUsageTokenMath.nonnegative(sample.inputTokens))
        ))
        try check(sqlite3_bind_int64(
            statement,
            5,
            Int64(AIUsageTokenMath.nonnegative(sample.outputTokens))
        ))
        try bind(sample.costUSD, to: 6, in: statement)
        try bind(sample.model, to: 7, in: statement)
    }

    private func bindUpdate(_ sample: AIUsageSample, to statement: OpaquePointer?) throws {
        try bind(sample.provider.rawValue, to: 1, in: statement)
        try check(sqlite3_bind_double(
            statement,
            2,
            sample.timestamp.timeIntervalSinceReferenceDate
        ))
        try check(sqlite3_bind_int64(
            statement,
            3,
            Int64(AIUsageTokenMath.nonnegative(sample.inputTokens))
        ))
        try check(sqlite3_bind_int64(
            statement,
            4,
            Int64(AIUsageTokenMath.nonnegative(sample.outputTokens))
        ))
        try bind(sample.costUSD, to: 5, in: statement)
        try bind(sample.model, to: 6, in: statement)
        try bind(sample.sourceID, to: 7, in: statement)
    }

    /// Evicts aggregate days and their model display rows without dropping source high-water marks.
    private func trimUsage() throws {
        let statement = try prepare("""
            DELETE FROM usage_samples
            WHERE position NOT IN (
                SELECT position FROM usage_samples
                ORDER BY timestamp DESC, position DESC LIMIT ?
            )
            """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_int64(statement, 1, Int64(maximumUsageSamples)))
        try stepDone(statement)
        try trimModelUsage()
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? sqliteMessage(connection, fallback: AppLocalization.text("AI 状态数据库操作失败"))
            throw AIStateRepositoryError.storageFailure(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            sqlite3_finalize(statement)
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(connection, fallback: AppLocalization.text("无法准备 AI 状态数据库操作"))
            )
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(connection, fallback: AppLocalization.text("AI 状态数据库写入失败"))
            )
        }
    }

    private func stepHasRow(_ statement: OpaquePointer?, fallback: String) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(connection, fallback: fallback)
            )
        }
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(connection, fallback: AppLocalization.text("AI 状态数据库参数绑定失败"))
            )
        }
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            try check(sqlite3_bind_null(statement, index))
            return
        }
        try check(value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, aiSQLiteTransient)
        })
    }

    private func bind(_ value: Double?, to index: Int32, in statement: OpaquePointer?) throws {
        if let value {
            try check(sqlite3_bind_double(statement, index, value))
        } else {
            try check(sqlite3_bind_null(statement, index))
        }
    }

    private func bind(_ data: Data, to index: Int32, in statement: OpaquePointer?) throws {
        let result = data.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), aiSQLiteTransient)
        }
        try check(result)
    }

    private func optionalText(at index: Int32, in statement: OpaquePointer?) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func tokenCount(at index: Int32, in statement: OpaquePointer?) -> Int {
        AIUsageTokenMath.nonnegative(Int(sqlite3_column_int64(statement, index)))
    }

    private func blob(at index: Int32, in statement: OpaquePointer?) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AIStateRepositoryError.corruptedState
        }
    }

    private func close() {
        guard let connection else { return }
        sqlite3_close_v2(connection)
        self.connection = nil
    }

    private func sqliteMessage(_ database: OpaquePointer?, fallback: String) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return fallback }
        return String(cString: message)
    }
}
