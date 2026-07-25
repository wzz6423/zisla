import Dispatch
import Foundation
import SQLite3

private let clipboardSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct ClipboardHistoryDatabaseError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

final class ClipboardHistoryDatabase: @unchecked Sendable {
    private let storageURL: URL
    private let queue = DispatchQueue(
        label: "com.zisla.clipboard-history.database",
        qos: .utility
    )
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var connection: OpaquePointer?
    private var persistedItems: [ClipboardHistoryItem] = []

    init(storageURL: URL) {
        self.storageURL = storageURL
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            closeConnection()
        } else {
            queue.sync { closeConnection() }
        }
    }

    func load() throws -> [ClipboardHistoryItem] {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: storageURL.path) else {
                persistedItems = []
                return []
            }
            let items = try readItems(from: database())
            persistedItems = items
            return items
        }
    }

    func persist(
        _ snapshot: [ClipboardHistoryItem],
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        queue.async { [self] in
            let errorDescription: String?
            do {
                try persistChanges(snapshot)
                errorDescription = nil
            } catch {
                errorDescription = error.localizedDescription
            }
            Task { @MainActor in completion(errorDescription) }
        }
    }

    func flush(_ snapshot: [ClipboardHistoryItem]) throws {
        try queue.sync {
            try persistChanges(snapshot)
        }
    }

    private func database() throws -> OpaquePointer {
        if let connection { return connection }

        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(
            storageURL.path,
            &opened,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard result == SQLITE_OK, let opened else {
            let message = sqliteMessage(opened, fallback: "无法打开剪贴板数据库")
            sqlite3_close(opened)
            throw ClipboardHistoryDatabaseError(message: message)
        }

        do {
            guard sqlite3_busy_timeout(opened, 1_000) == SQLITE_OK else {
                throw ClipboardHistoryDatabaseError(
                    message: sqliteMessage(opened, fallback: "无法配置剪贴板数据库")
                )
            }
            try execute("PRAGMA journal_mode = WAL", on: opened)
            try execute("PRAGMA synchronous = NORMAL", on: opened)
            try execute("PRAGMA temp_store = MEMORY", on: opened)
            try execute(
                """
                CREATE TABLE IF NOT EXISTS clipboard_history (
                    id TEXT PRIMARY KEY NOT NULL,
                    content_type INTEGER NOT NULL,
                    text_value TEXT,
                    image_data BLOB,
                    last_copied_at REAL NOT NULL,
                    is_pinned INTEGER NOT NULL
                )
                """,
                on: opened
            )
            connection = opened
            return opened
        } catch {
            sqlite3_close(opened)
            throw error
        }
    }

    private func readItems(from database: OpaquePointer) throws -> [ClipboardHistoryItem] {
        let statement = try prepare(
            """
            SELECT id, content_type, text_value, image_data, last_copied_at, is_pinned
            FROM clipboard_history
            ORDER BY is_pinned DESC, last_copied_at DESC
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }

        var items: [ClipboardHistoryItem] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let idText = textColumn(statement, index: 0),
                      let id = UUID(uuidString: idText) else {
                    throw ClipboardHistoryDatabaseError(message: "剪贴板数据库包含无效 ID")
                }
                let content: ClipboardHistoryContent
                switch sqlite3_column_int(statement, 1) {
                case 0:
                    content = .text(textColumn(statement, index: 2) ?? "")
                case 1:
                    content = .image(dataColumn(statement, index: 3))
                default:
                    throw ClipboardHistoryDatabaseError(message: "剪贴板数据库包含未知内容类型")
                }
                items.append(ClipboardHistoryItem(
                    id: id,
                    content: content,
                    lastCopiedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 4)),
                    isPinned: sqlite3_column_int(statement, 5) != 0
                ))
            case SQLITE_DONE:
                return items
            default:
                throw ClipboardHistoryDatabaseError(
                    message: sqliteMessage(database, fallback: "无法读取剪贴板数据库")
                )
            }
        }
    }

    private func persistChanges(_ snapshot: [ClipboardHistoryItem]) throws {
        guard snapshot != persistedItems else { return }

        let previousByID = Dictionary(uniqueKeysWithValues: persistedItems.map { ($0.id, $0) })
        let currentIDs = Set(snapshot.map(\.id))
        let upserts = snapshot.filter { previousByID[$0.id] != $0 }
        let deletedIDs = persistedItems.lazy.map(\.id).filter { !currentIDs.contains($0) }
        guard !upserts.isEmpty || !deletedIDs.isEmpty else {
            persistedItems = snapshot
            return
        }

        let database = try database()
        try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
        do {
            try upsert(upserts, into: database)
            try delete(Array(deletedIDs), from: database)
            try execute("COMMIT", on: database)
            persistedItems = snapshot
        } catch {
            try? execute("ROLLBACK", on: database)
            throw error
        }
    }

    private func upsert(_ items: [ClipboardHistoryItem], into database: OpaquePointer) throws {
        guard !items.isEmpty else { return }
        let statement = try prepare(
            """
            INSERT INTO clipboard_history (
                id, content_type, text_value, image_data, last_copied_at, is_pinned
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                content_type = excluded.content_type,
                text_value = excluded.text_value,
                image_data = excluded.image_data,
                last_copied_at = excluded.last_copied_at,
                is_pinned = excluded.is_pinned
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }

        for item in items {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(item.id.uuidString, to: statement, index: 1, database: database)
            switch item.content {
            case .text(let value):
                try check(sqlite3_bind_int(statement, 2, 0), database: database)
                try bind(value, to: statement, index: 3, database: database)
                try check(sqlite3_bind_null(statement, 4), database: database)
            case .image(let data):
                try check(sqlite3_bind_int(statement, 2, 1), database: database)
                try check(sqlite3_bind_null(statement, 3), database: database)
                try bind(data, to: statement, index: 4, database: database)
            }
            try check(
                sqlite3_bind_double(statement, 5, item.lastCopiedAt.timeIntervalSinceReferenceDate),
                database: database
            )
            try check(sqlite3_bind_int(statement, 6, item.isPinned ? 1 : 0), database: database)
            try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
        }
    }

    private func delete(_ ids: [UUID], from database: OpaquePointer) throws {
        guard !ids.isEmpty else { return }
        let statement = try prepare("DELETE FROM clipboard_history WHERE id = ?", on: database)
        defer { sqlite3_finalize(statement) }

        for id in ids {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(id.uuidString, to: statement, index: 1, database: database)
            try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
        }
    }

    private func prepare(_ sql: String, on database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw ClipboardHistoryDatabaseError(
                message: sqliteMessage(database, fallback: "无法准备剪贴板数据库操作")
            )
        }
        return statement
    }

    private func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? sqliteMessage(database, fallback: "剪贴板数据库操作失败")
            throw ClipboardHistoryDatabaseError(message: message)
        }
    }

    private func bind(
        _ value: String,
        to statement: OpaquePointer,
        index: Int32,
        database: OpaquePointer
    ) throws {
        let result = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, clipboardSQLiteTransient)
        }
        try check(result, database: database)
    }

    private func bind(
        _ data: Data,
        to statement: OpaquePointer,
        index: Int32,
        database: OpaquePointer
    ) throws {
        let result = data.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), clipboardSQLiteTransient)
        }
        try check(result, database: database)
    }

    private func check(
        _ result: Int32,
        expected: Int32 = SQLITE_OK,
        database: OpaquePointer
    ) throws {
        guard result == expected else {
            throw ClipboardHistoryDatabaseError(
                message: sqliteMessage(database, fallback: "剪贴板数据库操作失败")
            )
        }
    }

    private func textColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func dataColumn(_ statement: OpaquePointer, index: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func sqliteMessage(_ database: OpaquePointer?, fallback: String) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return fallback }
        return String(cString: message)
    }

    private func closeConnection() {
        guard let connection else { return }
        sqlite3_close_v2(connection)
        self.connection = nil
    }
}
