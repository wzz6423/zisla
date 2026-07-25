import Foundation
import ZislaCore
import SQLite3

/// 从 opencode 的 SQLite 数据库推断活动 AI 会话。
///
/// 数据库路径：`~/.local/share/opencode/opencode.db`
/// 活动判定：非归档会话中最新消息为 user（等待响应）或 assistant 未完成（仍在生成）。
public final class OpenCodeSessionActivityDetector: AIActivityDetecting {
    private struct SessionRow {
        var id: String
        var title: String
        var updatedAt: Int64
        var latestRole: String?
        var latestCompleted: Int64?
        var latestModel: String?
        var latestFinish: String?
    }

    private struct CachedResult {
        var modificationDate: Date
        var size: UInt64
        var tasks: [AIProgressTask]
    }

    public let databaseURL: URL
    public let maxSessions: Int
    public let recencyThreshold: TimeInterval

    private var cache: CachedResult?
    private let fileManager: FileManager

    public init(
        databaseURL: URL? = nil,
        maxSessions: Int = 10,
        recencyThreshold: TimeInterval = 30 * 60,
        fileManager: FileManager = .default
    ) {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else {
            self.databaseURL = Self.defaultDatabaseURL(
                home: fileManager.homeDirectoryForCurrentUser
            )
        }
        self.maxSessions = max(1, maxSessions)
        self.recencyThreshold = recencyThreshold
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return [] }

        let values = try? databaseURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
        ])
        let modDate = values?.contentModificationDate ?? .distantPast
        let size = UInt64(max(0, values?.fileSize ?? 0))

        if let cached = cache,
           cached.modificationDate == modDate,
           cached.size == size {
            return cached.tasks
        }

        let tasks = queryActiveSessions()
        cache = CachedResult(modificationDate: modDate, size: size, tasks: tasks)
        return tasks
    }

    public static func taskID(forSessionID sessionID: String) -> String {
        "opencode-session-\(sessionID)"
    }

    public static func defaultDatabaseURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".local/share/opencode/opencode.db", isDirectory: false)
    }

    // MARK: - SQLite Query

    private func queryActiveSessions() -> [AIProgressTask] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        // Set a short busy timeout to avoid blocking if the DB is locked.
        sqlite3_busy_timeout(db, 500)

        let sql = """
            SELECT s.id, s.title, s.time_updated,
                   json_extract(m.data, '$.role') AS role,
                   json_extract(m.data, '$.time.completed') AS completed,
                   json_extract(m.data, '$.modelID') AS model,
                   json_extract(m.data, '$.finish') AS finish
            FROM session s
            LEFT JOIN message m ON m.session_id = s.id
                AND m.time_updated = (
                    SELECT MAX(m2.time_updated) FROM message m2 WHERE m2.session_id = s.id
                )
            WHERE s.time_archived IS NULL
            ORDER BY s.time_updated DESC
            LIMIT ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(maxSessions))

        var rows: [SessionRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = stringColumn(stmt, 0) ?? ""
            let title = stringColumn(stmt, 1) ?? "opencode"
            let updatedAt = sqlite3_column_int64(stmt, 2)
            let role = stringColumn(stmt, 3)
            let completed = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(stmt, 4)
            let model = stringColumn(stmt, 5)
            let finish = stringColumn(stmt, 6)

            guard !id.isEmpty else { continue }
            rows.append(SessionRow(
                id: id,
                title: title,
                updatedAt: updatedAt,
                latestRole: role,
                latestCompleted: completed,
                latestModel: model,
                latestFinish: finish
            ))
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let thresholdMs = Int64(recencyThreshold * 1000)

        return rows.compactMap { row in
            guard nowMs - row.updatedAt < thresholdMs else { return nil }

            let isActive: Bool
            switch row.latestRole {
            case "user":
                isActive = true
            case "assistant":
                if let completed = row.latestCompleted, completed > 0,
                   row.latestFinish == "stop" {
                    isActive = false
                } else {
                    isActive = true
                }
            default:
                isActive = false
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
                effort: nil,
                startedAt: nil
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
}
