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
            try migrateUsageToDailyTotalsIfNeeded()
            try migrateDetectedUsageCursorIfNeeded()
            try migrateDetectedUsageEventsIfNeeded()
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

    func load(includeUsageSamples: Bool = true) throws -> AIState {
        AIState(
            tasks: try loadTasks(),
            usageSamples: includeUsageSamples ? try loadUsage() : [],
            notices: try loadNotices()
        )
    }

    func loadUsageSamples(startingAt startDate: Date? = nil) throws -> [AIUsageSample] {
        try loadUsage(startingAt: startDate)
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

    @discardableResult
    func recordUsage(_ samples: [AIUsageSample]) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        return try transaction {
            try recordUsageDeltasInCurrentTransaction(samples)
        }
    }

    @discardableResult
    func recordDetectedUsage(_ samples: [AIUsageSample]) throws -> Int {
        guard !samples.isEmpty else { return 0 }
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

    private func loadUsage(startingAt startDate: Date? = nil) throws -> [AIUsageSample] {
        let statement = try prepare(startDate == nil
            ? """
            SELECT source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model
            FROM usage_samples ORDER BY position
            """
            : """
            SELECT source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model
            FROM usage_samples WHERE timestamp >= ? ORDER BY position
            """
        )
        defer { sqlite3_finalize(statement) }
        if let startDate {
            try check(sqlite3_bind_double(statement, 1, startDate.timeIntervalSinceReferenceDate))
        }
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
        for sample in samples {
            let sourceID = detectedUsageSourceID(for: sample)
            let normalized = AIUsageSample(
                sourceID: sourceID,
                provider: sample.provider,
                timestamp: sample.timestamp,
                inputTokens: AIUsageTokenMath.nonnegative(sample.inputTokens),
                outputTokens: AIUsageTokenMath.nonnegative(sample.outputTokens),
                costUSD: sample.costUSD,
                model: sample.model
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
                    timestamp: existing.timestamp,
                    inputTokens: AIUsageTokenMath.adding(existing.inputTokens, inputDelta),
                    outputTokens: AIUsageTokenMath.adding(existing.outputTokens, outputDelta),
                    costUSD: existing.costUSD ?? normalized.costUSD,
                    model: existing.model ?? normalized.model
                )
                sqlite3_reset(update)
                sqlite3_clear_bindings(update)
                try bindUpdate(updated, to: update)
                try stepDone(update)
                if inputDelta > 0 || outputDelta > 0 {
                    let delta = AIUsageSample(
                        sourceID: sourceID,
                        provider: existing.provider,
                        timestamp: existing.timestamp,
                        inputTokens: inputDelta,
                        outputTokens: outputDelta
                    )
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

    private func detectedUsageEventTotal(at day: Date) throws -> DetectedUsageTotal {
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else {
            throw AIStateRepositoryError.storageFailure(AppLocalization.text("无法计算 AI 用量日期范围"))
        }
        let statement = try prepare("""
            SELECT input_tokens, output_tokens
            FROM detected_usage_events WHERE timestamp >= ? AND timestamp < ?
            """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_double(statement, 1, day.timeIntervalSinceReferenceDate))
        try check(sqlite3_bind_double(statement, 2, nextDay.timeIntervalSinceReferenceDate))
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

    private func usageSample(
        from statement: OpaquePointer?,
        sourceID: String?,
        columnOffset: Int32
    ) throws -> AIUsageSample {
        guard let providerText = optionalText(at: columnOffset, in: statement),
              let provider = AIProvider(rawValue: providerText) else {
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
