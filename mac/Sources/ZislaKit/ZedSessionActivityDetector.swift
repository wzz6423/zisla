import Foundation
import SQLite3
import ZislaCore

/// 从 Zed 的本地线程索引推断最近活动的 Agent；仅查询标识和时间戳，不读取摘要或压缩会话正文。
public final class ZedSessionActivityDetector: AIActivityDetecting {
    public let databaseURL: URL
    public let maxThreads: Int
    public let recencyThreshold: TimeInterval

    private let now: () -> Date
    private let fileManager: FileManager

    public init(
        databaseURL: URL? = nil,
        maxThreads: Int = 4,
        recencyThreshold: TimeInterval = 30 * 60,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL(
            home: fileManager.homeDirectoryForCurrentUser
        )
        self.maxThreads = min(max(1, maxThreads), Int(Int32.max))
        self.recencyThreshold = max(0, recencyThreshold)
        self.now = now
        self.fileManager = fileManager
    }

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
            let message = sqliteMessage(database, fallback: AppLocalization.text("无法打开 Zed 线程数据库"))
            sqlite3_close(database)
            throw AIStateRepositoryError.storageFailure(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)

        let sql = """
            SELECT id, updated_at, created_at
            FROM threads
            ORDER BY updated_at DESC
            LIMIT ?
            """
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            let message = sqliteMessage(database, fallback: AppLocalization.text("无法查询 Zed 线程"))
            sqlite3_finalize(statement)
            throw AIStateRepositoryError.storageFailure(message)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int(statement, 1, Int32(maxThreads)) == SQLITE_OK else {
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(database, fallback: AppLocalization.text("无法设置 Zed 线程查询范围"))
            )
        }

        let earliestActivity = now().addingTimeInterval(-recencyThreshold)
        var tasks: [AIProgressTask] = []
        readRows: while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let threadID = stringColumn(statement, 0)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !threadID.isEmpty,
                      let updatedAtText = stringColumn(statement, 1),
                      let updatedAt = Self.parseDate(updatedAtText),
                      updatedAt > earliestActivity else {
                    continue
                }

                tasks.append(AIProgressTask(
                    id: Self.taskID(forThreadID: threadID),
                    provider: .zed,
                    title: "Zed Agent",
                    detail: nil,
                    progress: nil,
                    status: .running,
                    updatedAt: updatedAt,
                    sessionURL: nil,
                    effort: nil,
                    startedAt: stringColumn(statement, 2).flatMap(Self.parseDate)
                ))
            case SQLITE_DONE:
                break readRows
            default:
                throw AIStateRepositoryError.storageFailure(
                    sqliteMessage(database, fallback: AppLocalization.text("无法读取 Zed 线程"))
                )
            }
        }

        return tasks.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func taskID(forThreadID threadID: String) -> String {
        "zed-thread-\(threadID)"
    }

    public static func defaultDatabaseURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent("Library/Application Support/Zed/threads/threads.db", isDirectory: false)
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }

    private func sqliteMessage(_ database: OpaquePointer?, fallback: String) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return fallback }
        return String(cString: message)
    }
}
