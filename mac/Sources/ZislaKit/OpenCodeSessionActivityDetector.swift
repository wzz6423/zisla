import Foundation
import ZislaCore
import SQLite3

/// Infers active AI sessions from OpenCode's SQLite database.
///
/// Database path: `~/.local/share/opencode/opencode.db`.
/// A session is active when its latest unarchived message is a waiting user message or an unfinished assistant message.
public final class OpenCodeSessionActivityDetector: AIActivityDetecting {
    private struct SessionRow {
        var id: String
        var title: String
        var createdAt: Int64
        var updatedAt: Int64
        var latestRole: String?
        var latestCompleted: Int64?
        var latestUserCreated: Int64?
        var latestAssistantCreated: Int64?
        var latestAssistantCompleted: Int64?
        var latestAssistantFinish: String?
        var latestModel: String?
        var latestVariant: String?
        var latestFinish: String?
    }

    public let databaseURL: URL
    public let maxSessions: Int
    public let recencyThreshold: TimeInterval

    private let fileManager: FileManager
    private let runningProcessIdentifiers: () -> [Int32]

    public init(
        databaseURL: URL? = nil,
        maxSessions: Int = 10,
        recencyThreshold: TimeInterval = 30 * 60,
        fileManager: FileManager = .default,
        runningProcessIdentifiers: @escaping () -> [Int32] = OpenCodeSessionActivityDetector.defaultRunningProcessIdentifiers
    ) {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else {
            self.databaseURL = Self.defaultDatabaseURL(
                home: fileManager.homeDirectoryForCurrentUser
            )
        }
        self.maxSessions = max(1, maxSessions)
        self.recencyThreshold = recencyThreshold.isFinite ? max(0, recencyThreshold) : .greatestFiniteMagnitude
        self.fileManager = fileManager
        self.runningProcessIdentifiers = runningProcessIdentifiers
    }

    public func activeTasks() throws -> [AIProgressTask] {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return [] }
        return try queryActiveSessions()
    }

    public static func taskID(forSessionID sessionID: String) -> String {
        "opencode-session-\(sessionID)"
    }

    public static func defaultDatabaseURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".local/share/opencode/opencode.db", isDirectory: false)
    }

    public static func defaultRunningProcessIdentifiers() -> [Int32] {
        guard let data = CodexSessionActivityDetector.runProcessOutput(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,comm=,args="],
            timeout: 2
        ) else { return [] }
        return parseRunningProcessIdentifiers(data)
    }

    static func parseRunningProcessIdentifiers(_ data: Data) -> [Int32] {
        String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> Int32? in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 2,
                      let processIdentifier = Int32(fields[0]),
                      URL(fileURLWithPath: String(fields[1])).lastPathComponent == "opencode"
                else { return nil }
                return processIdentifier
            }
            .sorted(by: >)
    }

    // MARK: - SQLite Query

    private func queryActiveSessions() throws -> [AIProgressTask] {
        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let db else {
            let message = sqliteMessage(db, fallback: AppLocalization.text("无法打开 OpenCode 数据库"))
            sqlite3_close(db)
            throw AIStateRepositoryError.storageFailure(message)
        }
        defer { sqlite3_close(db) }

        // Set a short busy timeout to avoid blocking if the DB is locked.
        sqlite3_busy_timeout(db, 500)

        let sql = """
            SELECT s.id, s.title, s.time_created, s.time_updated,
                   json_extract(m.data, '$.role') AS role,
                   json_extract(m.data, '$.time.completed') AS completed,
                   (
                       SELECT MAX(CAST(json_extract(m2.data, '$.time.created') AS INTEGER))
                       FROM message m2
                       WHERE m2.session_id = s.id
                         AND json_extract(m2.data, '$.role') = 'user'
                   ) AS latest_user_created,
                   (
                       SELECT json_extract(m2.data, '$.time.created')
                       FROM message m2
                       WHERE m2.session_id = s.id
                         AND json_extract(m2.data, '$.role') = 'assistant'
                       ORDER BY CAST(json_extract(m2.data, '$.time.created') AS INTEGER) DESC,
                                m2.time_updated DESC,
                                m2.id DESC
                       LIMIT 1
                   ) AS latest_assistant_created,
                   (
                       SELECT json_extract(m2.data, '$.time.completed')
                       FROM message m2
                       WHERE m2.session_id = s.id
                         AND json_extract(m2.data, '$.role') = 'assistant'
                       ORDER BY CAST(json_extract(m2.data, '$.time.created') AS INTEGER) DESC,
                                m2.time_updated DESC,
                                m2.id DESC
                       LIMIT 1
                   ) AS latest_assistant_completed,
                   (
                       SELECT json_extract(m2.data, '$.finish')
                       FROM message m2
                       WHERE m2.session_id = s.id
                         AND json_extract(m2.data, '$.role') = 'assistant'
                       ORDER BY CAST(json_extract(m2.data, '$.time.created') AS INTEGER) DESC,
                                m2.time_updated DESC,
                                m2.id DESC
                       LIMIT 1
                   ) AS latest_assistant_finish,
                   COALESCE(
                       json_extract(m.data, '$.modelID'),
                       json_extract(m.data, '$.model.modelID'),
                       (
                           SELECT COALESCE(
                               json_extract(m2.data, '$.modelID'),
                               json_extract(m2.data, '$.model.modelID')
                           )
                           FROM message m2
                           WHERE m2.session_id = s.id
                             AND (
                                 json_extract(m2.data, '$.modelID') IS NOT NULL
                                 OR json_extract(m2.data, '$.model.modelID') IS NOT NULL
                             )
                           ORDER BY m2.time_updated DESC, m2.id DESC
                           LIMIT 1
                       )
                   ) AS model,
                   COALESCE(
                       json_extract(m.data, '$.variant'),
                       json_extract(m.data, '$.model.variant'),
                       (
                           SELECT COALESCE(
                               json_extract(m2.data, '$.variant'),
                               json_extract(m2.data, '$.model.variant')
                           )
                           FROM message m2
                           WHERE m2.session_id = s.id
                             AND (
                                 json_extract(m2.data, '$.variant') IS NOT NULL
                                 OR json_extract(m2.data, '$.model.variant') IS NOT NULL
                             )
                           ORDER BY m2.time_updated DESC, m2.id DESC
                           LIMIT 1
                       )
                   ) AS variant,
                   json_extract(m.data, '$.finish') AS finish
            FROM session s
            LEFT JOIN message m ON m.id = (
                SELECT m2.id
                FROM message m2
                WHERE m2.session_id = s.id
                ORDER BY m2.time_updated DESC, m2.time_created DESC, m2.id DESC
                LIMIT 1
            )
            WHERE s.time_archived IS NULL
            ORDER BY s.time_updated DESC
            LIMIT ?
            """

        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareResult == SQLITE_OK, let stmt else {
            let message = sqliteMessage(db, fallback: AppLocalization.text("无法查询 OpenCode 会话"))
            sqlite3_finalize(stmt)
            throw AIStateRepositoryError.storageFailure(message)
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_bind_int64(stmt, 1, Int64(maxSessions)) == SQLITE_OK else {
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(db, fallback: AppLocalization.text("无法设置 OpenCode 会话查询范围"))
            )
        }

        var rows: [SessionRow] = []
        readRows: while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW:
                let id = stringColumn(stmt, 0) ?? ""
                let title = stringColumn(stmt, 1) ?? "opencode"
                let createdAt = sqlite3_column_int64(stmt, 2)
                let updatedAt = sqlite3_column_int64(stmt, 3)
                let role = stringColumn(stmt, 4)
                let completed = sqlite3_column_type(stmt, 5) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_int64(stmt, 5)
                let latestUserCreated = optionalInt64Column(stmt, 6)
                let latestAssistantCreated = optionalInt64Column(stmt, 7)
                let latestAssistantCompleted = optionalInt64Column(stmt, 8)
                let latestAssistantFinish = stringColumn(stmt, 9)
                let model = stringColumn(stmt, 10)
                let variant = stringColumn(stmt, 11)
                let finish = stringColumn(stmt, 12)

                guard !id.isEmpty else { continue }
                rows.append(SessionRow(
                    id: id,
                    title: title,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    latestRole: role,
                    latestCompleted: completed,
                    latestUserCreated: latestUserCreated,
                    latestAssistantCreated: latestAssistantCreated,
                    latestAssistantCompleted: latestAssistantCompleted,
                    latestAssistantFinish: latestAssistantFinish,
                    latestModel: model,
                    latestVariant: variant,
                    latestFinish: finish
                ))
            case SQLITE_DONE:
                break readRows
            default:
                throw AIStateRepositoryError.storageFailure(
                    sqliteMessage(db, fallback: AppLocalization.text("无法读取 OpenCode 会话"))
                )
            }
        }

        let now = Date().timeIntervalSince1970
        let processIdentifier = runningProcessIdentifiers().first

        return rows.compactMap { row in
            guard now - Double(row.updatedAt) / 1000 < recencyThreshold else { return nil }

            let isActive: Bool
            if let latestUserCreated = row.latestUserCreated,
               latestUserCreated > (row.latestAssistantCreated ?? 0) {
                isActive = true
            } else if let assistantCreated = row.latestAssistantCreated {
                isActive = row.latestAssistantCompleted == nil
                    || row.latestAssistantCompleted == 0
                    || row.latestAssistantFinish != "stop"
                    || assistantCreated == 0
            } else {
                isActive = row.latestRole == "user"
            }
            guard isActive else { return nil }

            return AIProgressTask(
                id: Self.taskID(forSessionID: row.id),
                provider: .opencode,
                title: row.title.isEmpty ? "opencode" : row.title,
                detail: row.latestModel,
                progress: nil,
                status: .running,
                updatedAt: Date(timeIntervalSince1970: Double(row.updatedAt) / 1000),
                sessionURL: nil,
                effort: row.latestVariant,
                startedAt: Date(timeIntervalSince1970: Double(row.createdAt) / 1000),
                processIdentifier: processIdentifier
            )
        }
    }

    private func stringColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func optionalInt64Column(_ stmt: OpaquePointer?, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, index)
    }

    private func sqliteMessage(_ database: OpaquePointer?, fallback: String) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return fallback }
        return String(cString: message)
    }
}
