import Foundation
import SQLite3
import ZislaCore

/// Infers active tasks from WorkBuddy Desktop's shared local session database.
///
/// WorkBuddy keeps every conversation in `~/.workbuddy/workbuddy.db`. The legacy
/// `~/.workbuddy/app/sessions.json` index is no longer rewritten, so it cannot tell whether a
/// conversation is still running. Only status, timestamps, title, and model identifier are
/// queried; message content is never read.
public final class WorkBuddySessionActivityDetector: AIActivityDetecting {
    /// `custom_title` is set when the user renames a conversation and takes precedence over `title`.
    private static let defaultTitle = "WorkBuddy"

    private static let activeStatuses = ["working", "pending", "blocked", "error"]

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

    /// Detection is best effort: WorkBuddy owns its schema and may migrate it between releases,
    /// so a missing file or an unexpected schema reports "no active task" instead of failing the
    /// whole AI state refresh.
    public func activeTasks() throws -> [AIProgressTask] {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return [] }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)

        // The status list mirrors `AIProgressStatus`; finished and archived rows stay out of SQL so
        // the scan never depends on the 70+ historical sessions a user accumulates.
        let sql = """
            SELECT s.id,
                   COALESCE(
                       NULLIF(TRIM(s.custom_title), ''),
                       NULLIF(TRIM(s.title), '')
                   ),
                   LOWER(s.status),
                   s.model,
                   s.created_at,
                   COALESCE(s.last_activity_at, s.updated_at)
            FROM sessions s
            WHERE s.deleted_at IS NULL
              AND LOWER(s.status) IN (\(Self.activeStatuses.map { "'\($0)'" }.joined(separator: ", ")))
              AND COALESCE(s.last_activity_at, s.updated_at) >= ?
            ORDER BY COALESCE(s.last_activity_at, s.updated_at) DESC, s.id ASC
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(statement) }

        // `created_at`, `updated_at`, and `last_activity_at` are Unix milliseconds.
        let cutoff = Self.clampedMilliseconds(now().timeIntervalSince1970 - recencyThreshold)
        guard sqlite3_bind_int64(statement, 1, cutoff) == SQLITE_OK else { return [] }

        var tasks: [AIProgressTask] = []
        readRows: while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let conversationID = stringColumn(statement, 0)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !conversationID.isEmpty,
                    let rawStatus = stringColumn(statement, 2),
                    let status = Self.status(forDatabaseValue: rawStatus),
                    let updatedAtMilliseconds = optionalInt64Column(statement, 5) else {
                    continue
                }

                let title = stringColumn(statement, 1)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                tasks.append(AIProgressTask(
                    id: Self.taskID(forConversationID: conversationID),
                    provider: .harness,
                    title: (title?.isEmpty == false ? title : nil) ?? Self.defaultTitle,
                    detail: stringColumn(statement, 3),
                    progress: nil,
                    status: status,
                    updatedAt: Date(timeIntervalSince1970: Double(updatedAtMilliseconds) / 1_000),
                    sessionURL: Self.sessionURL(for: conversationID),
                    effort: nil,
                    startedAt: optionalInt64Column(statement, 4).map {
                        Date(timeIntervalSince1970: Double($0) / 1_000)
                    }
                ))
            case SQLITE_DONE:
                break readRows
            default:
                return []
            }
        }
        return tasks
    }

    public static func taskID(forConversationID conversationID: String) -> String {
        "workbuddy-session-\(conversationID)"
    }

    public static func defaultDatabaseURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".workbuddy/workbuddy.db", isDirectory: false)
    }

    /// WorkBuddy registers the `workbuddy` URL scheme and routes `workbuddy://chat/<id>` to a
    /// conversation, so the island can jump straight to the running task.
    static func sessionURL(for conversationID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "workbuddy"
        components.host = "chat"
        components.path = "/\(conversationID)"
        return components.url
    }

    static func status(forDatabaseValue value: String) -> AIProgressStatus? {
        switch value.lowercased() {
        case "working", "running": .running
        case "pending", "queued": .queued
        case "blocked": .blocked
        case "error", "failed": .error
        default: nil
        }
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

    private static func clampedMilliseconds(_ seconds: TimeInterval) -> Int64 {
        guard seconds.isFinite else {
            return seconds.sign == .minus ? Int64.min : Int64.max
        }
        let milliseconds = seconds * 1_000
        if milliseconds <= Double(Int64.min) { return Int64.min }
        if milliseconds >= Double(Int64.max) { return Int64.max }
        return Int64(milliseconds)
    }
}
