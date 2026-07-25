import Foundation
import SQLite3

private let aiSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class AIStateDatabase {
    let url: URL
    private let maximumUsageSamples: Int
    private var connection: OpaquePointer?

    init(url: URL, maximumUsageSamples: Int) throws {
        self.url = url
        self.maximumUsageSamples = max(1, maximumUsageSamples)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var opened: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &opened,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let opened else {
            let message = sqliteMessage(opened, fallback: "无法打开 AI 状态数据库")
            sqlite3_close(opened)
            throw AIStateRepositoryError.storageFailure(message)
        }
        connection = opened

        do {
            guard sqlite3_busy_timeout(opened, 1_000) == SQLITE_OK else {
                throw AIStateRepositoryError.storageFailure(
                    sqliteMessage(opened, fallback: "无法配置 AI 状态数据库")
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
                CREATE TABLE IF NOT EXISTS notices (
                    position INTEGER PRIMARY KEY AUTOINCREMENT,
                    payload BLOB NOT NULL
                )
                """)
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
        guard sqlite3_step(countStatement) == SQLITE_ROW,
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
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
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
                if let sourceID = sample.sourceID {
                    sqlite3_reset(lookup)
                    sqlite3_clear_bindings(lookup)
                    try bind(sourceID, to: 1, in: lookup)
                    if sqlite3_step(lookup) == SQLITE_ROW {
                        let existing = try usageSample(
                            from: lookup,
                            sourceID: sourceID,
                            columnOffset: 0
                        )
                        guard existing != sample else { continue }
                        sqlite3_reset(update)
                        sqlite3_clear_bindings(update)
                        try bindUpdate(sample, to: update)
                        try stepDone(update)
                        continue
                    }
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
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try decode(AIProgressTask.self, from: blob(at: 0, in: statement)))
        }
        return result
    }

    private func loadUsage() throws -> [AIUsageSample] {
        let statement = try prepare("""
            SELECT source_id, provider, timestamp, input_tokens, output_tokens, cost_usd, model
            FROM usage_samples ORDER BY position
            """)
        defer { sqlite3_finalize(statement) }
        var result: [AIUsageSample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try usageSample(
                from: statement,
                sourceID: optionalText(at: 0, in: statement),
                columnOffset: 1
            ))
        }
        return result
    }

    private func loadNotices() throws -> [IslandNotice] {
        let statement = try prepare("SELECT payload FROM notices ORDER BY position")
        defer { sqlite3_finalize(statement) }
        var result: [IslandNotice] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try decode(IslandNotice.self, from: blob(at: 0, in: statement)))
        }
        return result
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
            inputTokens: Int(sqlite3_column_int64(statement, columnOffset + 2)),
            outputTokens: Int(sqlite3_column_int64(statement, columnOffset + 3)),
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
        try check(sqlite3_bind_int64(statement, 4, Int64(sample.inputTokens)))
        try check(sqlite3_bind_int64(statement, 5, Int64(sample.outputTokens)))
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
        try check(sqlite3_bind_int64(statement, 3, Int64(sample.inputTokens)))
        try check(sqlite3_bind_int64(statement, 4, Int64(sample.outputTokens)))
        try bind(sample.costUSD, to: 5, in: statement)
        try bind(sample.model, to: 6, in: statement)
        try bind(sample.sourceID, to: 7, in: statement)
    }

    private func trimUsage() throws {
        let statement = try prepare("""
            DELETE FROM usage_samples
            WHERE position NOT IN (
                SELECT position FROM usage_samples ORDER BY position DESC LIMIT ?
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
                ?? sqliteMessage(connection, fallback: "AI 状态数据库操作失败")
            throw AIStateRepositoryError.storageFailure(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            sqlite3_finalize(statement)
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(connection, fallback: "无法准备 AI 状态数据库操作")
            )
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(connection, fallback: "AI 状态数据库写入失败")
            )
        }
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(connection, fallback: "AI 状态数据库参数绑定失败")
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
