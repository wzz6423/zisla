import Foundation
import SQLite3
import ZislaCore

/// Infers active tasks from the Gemini desktop app's local chat store at
/// `~/Library/Caches/com.google.GeminiMacOS/Gemini/<profile>/ChatInfo*.store`.
///
/// The store is a SwiftData database that keeps every message body encrypted in
/// `ZENCRYPTEDPROTOBYTES`; only the turn direction, index and timestamps are read. A chat counts as
/// running while its newest turn is still the user's, because the app persists the model turn once
/// the answer has been produced.
public final class GeminiDesktopSessionActivityDetector: AIActivityDetecting {
    /// Seconds between the Core Data reference date (2001-01-01) and the Unix epoch.
    private static let coreDataEpochOffset: TimeInterval = 978_307_200

    public let databaseURLs: [URL]
    public let maxChats: Int
    public let recencyThreshold: TimeInterval

    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        databaseURLs: [URL]? = nil,
        maxChats: Int = 4,
        recencyThreshold: TimeInterval = 15 * 60,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.databaseURLs = databaseURLs ?? Self.defaultDatabaseURLs(
            home: fileManager.homeDirectoryForCurrentUser,
            fileManager: fileManager
        )
        self.maxChats = min(max(1, maxChats), Int(Int32.max))
        self.recencyThreshold = max(0, recencyThreshold)
        self.now = now
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        var tasks: [AIProgressTask] = []
        for databaseURL in databaseURLs where fileManager.fileExists(atPath: databaseURL.path) {
            tasks.append(contentsOf: try activeTasks(inDatabaseAt: databaseURL))
        }

        return Array(tasks.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }.prefix(maxChats))
    }

    public static func taskID(forChatUUID chatUUID: String) -> String {
        "gemini-desktop-chat-\(chatUUID)"
    }

    /// Every signed-in profile keeps its own store and the file name carries the schema generation,
    /// so both are discovered instead of hard-coded.
    public static func defaultDatabaseURLs(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        let chatsRoot = home.appendingPathComponent(
            "Library/Caches/com.google.GeminiMacOS/Gemini",
            isDirectory: true
        )
        guard let profiles = try? fileManager.contentsOfDirectory(
            at: chatsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return profiles.sorted { $0.lastPathComponent < $1.lastPathComponent }.flatMap { profile in
            let stores = (try? fileManager.contentsOfDirectory(
                at: profile,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            // Newest schema generation first, so `ChatInfo2` wins over a leftover `ChatInfo`.
            return stores.filter {
                $0.lastPathComponent.hasPrefix("ChatInfo") && $0.pathExtension == "store"
            }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
    }

    /// Ranks the turns of every chat so only the newest one is examined. `ZMESSAGEINDEX` breaks the
    /// tie for chats synced from the server, whose turns land with near-identical creation times.
    private static let sql = """
        SELECT chatUuid, createdTime
        FROM (
            SELECT ZCHATUUID AS chatUuid,
                   ZISUSERTURN AS isUserTurn,
                   ZCREATEDTIME AS createdTime,
                   ROW_NUMBER() OVER (
                       PARTITION BY ZCHATUUID
                       ORDER BY ZCREATEDTIME DESC, ZMESSAGEINDEX DESC
                   ) AS turnRank
            FROM ZCHATMESSAGESTOREDMODEL
        )
        WHERE turnRank = 1 AND isUserTurn = 1 AND createdTime >= ?
        ORDER BY createdTime DESC
        LIMIT ?
        """

    private func activeTasks(inDatabaseAt databaseURL: URL) throws -> [AIProgressTask] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = sqliteMessage(database, fallback: "无法打开 Gemini 桌面端会话数据库")
            sqlite3_close(database)
            throw AIStateRepositoryError.storageFailure(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, Self.sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            let message = sqliteMessage(database, fallback: "无法查询 Gemini 桌面端会话")
            sqlite3_finalize(statement)
            throw AIStateRepositoryError.storageFailure(message)
        }
        defer { sqlite3_finalize(statement) }

        let cutoff = now().addingTimeInterval(-recencyThreshold).timeIntervalSince1970
            - Self.coreDataEpochOffset
        guard sqlite3_bind_double(statement, 1, cutoff) == SQLITE_OK,
              sqlite3_bind_int(statement, 2, Int32(maxChats)) == SQLITE_OK else {
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(database, fallback: "无法设置 Gemini 桌面端会话查询范围")
            )
        }

        var tasks: [AIProgressTask] = []
        readRows: while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let chatUUID = stringColumn(statement, 0)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !chatUUID.isEmpty,
                    sqlite3_column_type(statement, 1) != SQLITE_NULL else {
                    continue
                }

                let askedAt = Date(
                    timeIntervalSince1970: sqlite3_column_double(statement, 1)
                        + Self.coreDataEpochOffset
                )
                tasks.append(AIProgressTask(
                    id: Self.taskID(forChatUUID: chatUUID),
                    provider: .gemini,
                    title: "Gemini",
                    detail: "Desktop",
                    progress: nil,
                    status: .running,
                    updatedAt: askedAt,
                    sessionURL: nil,
                    effort: nil,
                    startedAt: askedAt
                ))
            case SQLITE_DONE:
                break readRows
            default:
                throw AIStateRepositoryError.storageFailure(
                    sqliteMessage(database, fallback: "无法读取 Gemini 桌面端会话")
                )
            }
        }

        return tasks
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private func sqliteMessage(_ database: OpaquePointer?, fallback: String) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return fallback }
        return String(cString: message)
    }
}
