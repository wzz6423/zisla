import Foundation
import SQLite3
import ZislaCore

/// Reads ZCode Desktop and `zcode-cli` turns from their shared local SQLite state.
/// Only status, timestamps, model identifiers, and error codes are queried; message content is not read.
public final class ZCodeSessionActivityDetector: AIActivityDetecting {
    public let databaseURL: URL
    public let recencyThreshold: TimeInterval

    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        databaseURL: URL? = nil,
        recencyThreshold: TimeInterval = 30 * 60,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL(
            home: fileManager.homeDirectoryForCurrentUser
        )
        self.recencyThreshold = max(0, recencyThreshold)
        self.now = now
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return [] }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)

        let sql = """
            SELECT t.session_id,
                   t.turn_id,
                   LOWER(t.status),
                   t.started_at,
                   t.completed_at,
                   t.error_code,
                   (
                       SELECT m.model_id
                       FROM model_usage m
                       WHERE m.session_id = t.session_id
                         AND m.turn_id = t.turn_id
                       ORDER BY m.started_at DESC
                       LIMIT 1
                   ),
                   s.time_updated
            FROM turn_usage t
            LEFT JOIN session s ON s.id = t.session_id
            WHERE LOWER(t.status) IN ('running', 'error')
              AND (
                  CASE LOWER(t.status)
                      WHEN 'running' THEN COALESCE(s.time_updated, t.started_at)
                      ELSE COALESCE(t.completed_at, t.started_at, s.time_updated)
                  END
              ) >= ?
            ORDER BY CASE LOWER(t.status)
                         WHEN 'running' THEN COALESCE(s.time_updated, t.started_at)
                         ELSE COALESCE(t.completed_at, t.started_at, s.time_updated)
                     END DESC
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(statement) }

        let cutoff = Int64((now().timeIntervalSince1970 - recencyThreshold) * 1_000)
        sqlite3_bind_int64(statement, 1, cutoff)

        var tasks: [AIProgressTask] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sessionID = stringColumn(statement, 0),
                  let turnID = stringColumn(statement, 1),
                  let rawStatus = stringColumn(statement, 2),
                  let status = AIProgressStatus(rawValue: rawStatus),
                  let startedAtMilliseconds = optionalInt64Column(statement, 3) else {
                continue
            }

            let completedAtMilliseconds = optionalInt64Column(statement, 4)
            let sessionUpdatedAtMilliseconds = optionalInt64Column(statement, 7)
            let updatedMilliseconds = status == .running
                ? (sessionUpdatedAtMilliseconds ?? startedAtMilliseconds)
                : (completedAtMilliseconds ?? startedAtMilliseconds)
            let updatedAt = Date(timeIntervalSince1970: Double(updatedMilliseconds) / 1_000)
            let model = stringColumn(statement, 6)
            tasks.append(AIProgressTask(
                id: Self.taskID(forSessionID: sessionID, turnID: turnID),
                provider: .zcode,
                title: "ZCode",
                detail: model,
                progress: nil,
                status: status,
                updatedAt: updatedAt,
                startedAt: Date(timeIntervalSince1970: Double(startedAtMilliseconds) / 1_000),
                failureReason: status == .error ? stringColumn(statement, 5) : nil
            ))
        }
        return tasks
    }

    public static func taskID(forSessionID sessionID: String, turnID: String) -> String {
        "zcode-session-\(sessionID)-turn-\(turnID)"
    }

    public static func defaultDatabaseURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".zcode/cli/db/db.sqlite", isDirectory: false)
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private func optionalInt64Column(_ statement: OpaquePointer?, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }
}
