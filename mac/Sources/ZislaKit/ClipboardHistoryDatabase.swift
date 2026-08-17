import Dispatch
import Foundation
import SQLite3

private let clipboardSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct ClipboardHistoryDatabaseError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct ClipboardHistoryPage: Sendable {
    var items: [ClipboardHistoryItem]
    var totalCount: Int
    var categoryCounts: [FileShelfCategory: Int]
}

enum ClipboardHistoryMutation: Sendable {
    case upsert(ClipboardHistoryItem, capacity: Int?)
    case remove(UUID)
    case removeHistory
}

final class ClipboardHistoryDatabase: @unchecked Sendable {
    private static let currentSchemaVersion = 4

    private let storageURL: URL
    private let queue = DispatchQueue(
        label: "com.zisla.clipboard-history.database",
        qos: .utility
    )
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var connection: OpaquePointer?

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

    func loadPage(
        scope: ClipboardHistoryScope,
        searchText: String,
        category: FileShelfCategory,
        offset: Int,
        limit: Int
    ) async throws -> ClipboardHistoryPage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard FileManager.default.fileExists(atPath: storageURL.path) else {
                        continuation.resume(returning: ClipboardHistoryPage(
                            items: [],
                            totalCount: 0,
                            categoryCounts: [:]
                        ))
                        return
                    }
                    continuation.resume(returning: try readPage(
                        from: database(),
                        scope: scope,
                        searchText: searchText,
                        category: category,
                        offset: max(0, offset),
                        limit: max(1, limit)
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func persist(
        _ mutations: [ClipboardHistoryMutation],
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        queue.async { [self] in
            let errorDescription: String?
            do {
                try applyMutations(mutations)
                errorDescription = nil
            } catch {
                errorDescription = error.localizedDescription
            }
            Task { @MainActor in completion(errorDescription) }
        }
    }

    func apply(_ mutations: [ClipboardHistoryMutation]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try applyMutations(mutations)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func flush(_ mutations: [ClipboardHistoryMutation]) throws {
        try queue.sync {
            try applyMutations(mutations)
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
            try migrateFileColumns(on: opened)
            try execute(
                """
                CREATE INDEX IF NOT EXISTS clipboard_history_display_order
                ON clipboard_history(is_pinned DESC, last_copied_at DESC)
                """,
                on: opened
            )
            try execute(
                """
                CREATE INDEX IF NOT EXISTS clipboard_history_category_order
                ON clipboard_history(content_category, is_pinned DESC, last_copied_at DESC)
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

    /// Old databases have only the original six columns, so query metadata must be added and backfilled in place.
    private func migrateFileColumns(on database: OpaquePointer) throws {
        let existing = try columnNames(of: "clipboard_history", on: database)
        let additions = [
            ("file_url", "TEXT"),
            ("file_display_name", "TEXT"),
            ("file_bookmark", "BLOB"),
            ("content_category", "TEXT"),
        ]
        for (name, type) in additions where !existing.contains(name) {
            try execute("ALTER TABLE clipboard_history ADD COLUMN \(name) \(type)", on: database)
        }
        try backfillMissingCategories(on: database)
        try migrateURLCategoriesIfNeeded(on: database)
        try migrateTextCategoriesIfNeeded(on: database)
        try migratePathCategoriesIfNeeded(on: database)
    }

    private func backfillMissingCategories(on database: OpaquePointer) throws {
        try execute(
            """
            UPDATE clipboard_history
            SET content_category = '\(FileShelfCategory.text.rawValue)'
            WHERE content_category IS NULL AND content_type = 0
            """,
            on: database
        )
        try execute(
            """
            UPDATE clipboard_history
            SET content_category = '\(FileShelfCategory.image.rawValue)'
            WHERE content_category IS NULL AND content_type = 1
            """,
            on: database
        )

        let files = try uncategorizedFileCategories(on: database)
        guard !files.isEmpty else { return }
        let statement = try prepare(
            "UPDATE clipboard_history SET content_category = ? WHERE id = ?",
            on: database
        )
        defer { sqlite3_finalize(statement) }
        for file in files {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(file.category.rawValue, to: statement, index: 1, database: database)
            try bind(file.id, to: statement, index: 2, database: database)
            try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
        }
    }

    private func migrateURLCategoriesIfNeeded(on database: OpaquePointer) throws {
        guard try schemaVersion(on: database) < Self.currentSchemaVersion else { return }
        let urlIDs = try legacyCategoryIDs(matching: .url, on: database)
        if !urlIDs.isEmpty {
            let statement = try prepare(
                "UPDATE clipboard_history SET content_category = ? WHERE id = ?",
                on: database
            )
            defer { sqlite3_finalize(statement) }
            for id in urlIDs {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(FileShelfCategory.url.rawValue, to: statement, index: 1, database: database)
                try bind(id, to: statement, index: 2, database: database)
                try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
            }
        }
    }

    private func migrateTextCategoriesIfNeeded(on database: OpaquePointer) throws {
        let version = try schemaVersion(on: database)
        guard version < Self.currentSchemaVersion else { return }
        try execute(
            """
            UPDATE clipboard_history
            SET content_category = '\(FileShelfCategory.text.rawValue)'
            WHERE content_type = 0
              AND content_category = '\(FileShelfCategory.document.rawValue)'
            """,
            on: database
        )
        if version < 2 {
            try execute("PRAGMA user_version = 2", on: database)
        }
    }

    private func migratePathCategoriesIfNeeded(on database: OpaquePointer) throws {
        guard try schemaVersion(on: database) < Self.currentSchemaVersion else { return }
        let pathIDs = try legacyCategoryIDs(matching: .path, on: database)
        if !pathIDs.isEmpty {
            let statement = try prepare(
                "UPDATE clipboard_history SET content_category = ? WHERE id = ?",
                on: database
            )
            defer { sqlite3_finalize(statement) }
            for id in pathIDs {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(FileShelfCategory.path.rawValue, to: statement, index: 1, database: database)
                try bind(id, to: statement, index: 2, database: database)
                try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
            }
        }
        try execute("PRAGMA user_version = \(Self.currentSchemaVersion)", on: database)
    }

    private func legacyCategoryIDs(
        matching category: FileShelfCategory,
        on database: OpaquePointer
    ) throws -> [String] {
        let statement = try prepare(
            """
            SELECT id, text_value
            FROM clipboard_history
            WHERE content_type = 0
              AND content_category IN (
                  '\(FileShelfCategory.document.rawValue)',
                  '\(FileShelfCategory.text.rawValue)'
              )
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }

        var result: [String] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let id = textColumn(statement, index: 0),
                      let text = textColumn(statement, index: 1) else { continue }
                if ClipboardHistoryItem(content: .text(text)).category == category {
                    result.append(id)
                }
            case SQLITE_DONE:
                return result
            default:
                throw ClipboardHistoryDatabaseError(
                    message: sqliteMessage(database, fallback: "无法重新分类文本")
                )
            }
        }
    }

    private func schemaVersion(on database: OpaquePointer) throws -> Int {
        let statement = try prepare("PRAGMA user_version", on: database)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ClipboardHistoryDatabaseError(message: "无法读取剪贴板数据库版本")
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func uncategorizedFileCategories(
        on database: OpaquePointer
    ) throws -> [(id: String, category: FileShelfCategory)] {
        let statement = try prepare(
            """
            SELECT id, file_url, file_display_name
            FROM clipboard_history
            WHERE content_category IS NULL AND content_type = 2
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }
        var result: [(String, FileShelfCategory)] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let id = textColumn(statement, index: 0),
                      let urlText = textColumn(statement, index: 1),
                      let url = URL(string: urlText) else {
                    throw ClipboardHistoryDatabaseError(message: "剪贴板数据库包含无效文件路径")
                }
                let reference = ClipboardFileReference(
                    url: url,
                    displayName: textColumn(statement, index: 2) ?? url.lastPathComponent,
                    bookmark: Data()
                )
                result.append((id, ClipboardHistoryItem(content: .file(reference)).category))
            case SQLITE_DONE:
                return result
            default:
                throw ClipboardHistoryDatabaseError(
                    message: sqliteMessage(database, fallback: "无法迁移剪贴板分类")
                )
            }
        }
    }

    private func columnNames(of table: String, on database: OpaquePointer) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\(table))", on: database)
        defer { sqlite3_finalize(statement) }
        var names: Set<String> = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let name = textColumn(statement, index: 1) { names.insert(name) }
            case SQLITE_DONE:
                return names
            default:
                throw ClipboardHistoryDatabaseError(
                    message: sqliteMessage(database, fallback: "无法读取剪贴板表结构")
                )
            }
        }
    }

    private func readPage(
        from database: OpaquePointer,
        scope: ClipboardHistoryScope,
        searchText: String,
        category: FileShelfCategory,
        offset: Int,
        limit: Int
    ) throws -> ClipboardHistoryPage {
        let query = queryClause(scope: scope, searchText: searchText, category: category)
        let countStatement = try prepare(
            "SELECT COUNT(*) FROM clipboard_history\(query.sql)",
            on: database
        )
        defer { sqlite3_finalize(countStatement) }
        try bind(query.values, to: countStatement, database: database)
        guard sqlite3_step(countStatement) == SQLITE_ROW else {
            throw ClipboardHistoryDatabaseError(
                message: sqliteMessage(database, fallback: "无法统计剪贴板记录")
            )
        }
        let totalCount = Int(sqlite3_column_int64(countStatement, 0))
        let categoryCounts = try readCategoryCounts(
            from: database,
            scope: scope,
            searchText: searchText
        )

        let statement = try prepare(
            """
            SELECT id, content_type, text_value, image_data, last_copied_at, is_pinned,
                   file_url, file_display_name, file_bookmark
            FROM clipboard_history
            \(query.sql)
            ORDER BY is_pinned DESC, last_copied_at DESC
            LIMIT ? OFFSET ?
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(query.values, to: statement, database: database)
        let limitIndex = Int32(query.values.count + 1)
        try check(sqlite3_bind_int64(statement, limitIndex, sqlite3_int64(limit)), database: database)
        try check(
            sqlite3_bind_int64(statement, limitIndex + 1, sqlite3_int64(offset)),
            database: database
        )

        var items: [ClipboardHistoryItem] = []
        items.reserveCapacity(min(limit, totalCount))
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                items.append(try readItem(from: statement))
            case SQLITE_DONE:
                return ClipboardHistoryPage(
                    items: items,
                    totalCount: totalCount,
                    categoryCounts: categoryCounts
                )
            default:
                throw ClipboardHistoryDatabaseError(
                    message: sqliteMessage(database, fallback: "无法读取剪贴板数据库")
                )
            }
        }
    }

    private func readCategoryCounts(
        from database: OpaquePointer,
        scope: ClipboardHistoryScope,
        searchText: String
    ) throws -> [FileShelfCategory: Int] {
        let query = queryClause(scope: scope, searchText: searchText, category: .all)
        let statement = try prepare(
            """
            SELECT content_category, COUNT(*)
            FROM clipboard_history
            \(query.sql)
            GROUP BY content_category
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(query.values, to: statement, database: database)

        var counts: [FileShelfCategory: Int] = [:]
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let rawValue = textColumn(statement, index: 0),
                   let category = FileShelfCategory(rawValue: rawValue) {
                    counts[category] = Int(sqlite3_column_int64(statement, 1))
                }
            case SQLITE_DONE:
                return counts
            default:
                throw ClipboardHistoryDatabaseError(
                    message: sqliteMessage(database, fallback: "无法统计剪贴板分类")
                )
            }
        }
    }

    private func applyMutations(_ mutations: [ClipboardHistoryMutation]) throws {
        guard !mutations.isEmpty else { return }
        let database = try database()
        try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
        do {
            for mutation in mutations {
                switch mutation {
                case .upsert(var item, let capacity):
                    if try matchingItemIsPinned(item.content, excluding: item.id, in: database) {
                        item.isPinned = true
                    }
                    try deleteMatching(item.content, excluding: item.id, from: database)
                    try upsert([item], into: database)
                    if let capacity {
                        try trimHistory(to: capacity, in: database)
                    }
                case .remove(let id):
                    try delete([id], from: database)
                case .removeHistory:
                    try execute("DELETE FROM clipboard_history WHERE is_pinned = 0", on: database)
                }
            }
            try execute("COMMIT", on: database)
        } catch {
            try? execute("ROLLBACK", on: database)
            throw error
        }
    }

    private func readItem(from statement: OpaquePointer) throws -> ClipboardHistoryItem {
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
        case 2:
            guard let urlString = textColumn(statement, index: 6),
                  let url = URL(string: urlString) else {
                throw ClipboardHistoryDatabaseError(message: "剪贴板数据库包含无效文件路径")
            }
            content = .file(ClipboardFileReference(
                url: url,
                displayName: textColumn(statement, index: 7) ?? url.lastPathComponent,
                bookmark: dataColumn(statement, index: 8)
            ))
        default:
            throw ClipboardHistoryDatabaseError(message: "剪贴板数据库包含未知内容类型")
        }
        return ClipboardHistoryItem(
            id: id,
            content: content,
            lastCopiedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 4)),
            isPinned: sqlite3_column_int(statement, 5) != 0
        )
    }

    private func queryClause(
        scope: ClipboardHistoryScope,
        searchText: String,
        category: FileShelfCategory
    ) -> (sql: String, values: [String]) {
        var clauses: [String] = []
        var values: [String] = []
        switch scope {
        case .all:
            break
        case .pinned:
            clauses.append("is_pinned = 1")
        case .history:
            clauses.append("is_pinned = 0")
        }

        if category != .all {
            clauses.append("content_category = ?")
            values.append(category.rawValue)
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            clauses.append(
                """
                CASE content_type
                    WHEN 0 THEN COALESCE(text_value, '')
                    WHEN 1 THEN '图片'
                    WHEN 2 THEN COALESCE(file_display_name, '')
                    ELSE ''
                END LIKE ? ESCAPE '\\' COLLATE NOCASE
                """
            )
            let escaped = trimmed
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            values.append("%\(escaped)%")
        }
        return (clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND "), values)
    }

    private func matchingItemIsPinned(
        _ content: ClipboardHistoryContent,
        excluding id: UUID,
        in database: OpaquePointer
    ) throws -> Bool {
        let statement = try prepare(
            "SELECT is_pinned FROM clipboard_history WHERE id <> ? AND \(contentPredicate(content)) LIMIT 1",
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, to: statement, index: 1, database: database)
        try bind(content, to: statement, index: 2, database: database)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return sqlite3_column_int(statement, 0) != 0
        case SQLITE_DONE:
            return false
        default:
            throw ClipboardHistoryDatabaseError(
                message: sqliteMessage(database, fallback: "无法检查重复剪贴板记录")
            )
        }
    }

    private func deleteMatching(
        _ content: ClipboardHistoryContent,
        excluding id: UUID,
        from database: OpaquePointer
    ) throws {
        let statement = try prepare(
            "DELETE FROM clipboard_history WHERE id <> ? AND \(contentPredicate(content))",
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, to: statement, index: 1, database: database)
        try bind(content, to: statement, index: 2, database: database)
        try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
    }

    private func contentPredicate(_ content: ClipboardHistoryContent) -> String {
        switch content {
        case .text:
            "content_type = 0 AND text_value = ?"
        case .image:
            "content_type = 1 AND image_data = ?"
        case .file:
            "content_type = 2 AND file_url = ?"
        }
    }

    private func bind(
        _ content: ClipboardHistoryContent,
        to statement: OpaquePointer,
        index: Int32,
        database: OpaquePointer
    ) throws {
        switch content {
        case .text(let value):
            try bind(value, to: statement, index: index, database: database)
        case .image(let data):
            try bind(data, to: statement, index: index, database: database)
        case .file(let reference):
            try bind(reference.url.absoluteString, to: statement, index: index, database: database)
        }
    }

    private func trimHistory(to capacity: Int, in database: OpaquePointer) throws {
        let statement = try prepare(
            """
            DELETE FROM clipboard_history
            WHERE is_pinned = 0 AND id IN (
                SELECT id FROM clipboard_history
                WHERE is_pinned = 0
                ORDER BY last_copied_at DESC
                LIMIT -1 OFFSET ?
            )
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try check(
            sqlite3_bind_int64(statement, 1, sqlite3_int64(max(1, capacity))),
            database: database
        )
        try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
    }

    private func upsert(_ items: [ClipboardHistoryItem], into database: OpaquePointer) throws {
        guard !items.isEmpty else { return }
        let statement = try prepare(
            """
            INSERT INTO clipboard_history (
                id, content_type, text_value, image_data, last_copied_at, is_pinned,
                file_url, file_display_name, file_bookmark, content_category
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                content_type = excluded.content_type,
                text_value = excluded.text_value,
                image_data = excluded.image_data,
                last_copied_at = excluded.last_copied_at,
                is_pinned = excluded.is_pinned,
                file_url = excluded.file_url,
                file_display_name = excluded.file_display_name,
                file_bookmark = excluded.file_bookmark,
                content_category = excluded.content_category
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
                try bindFileNull(statement, database: database)
            case .image(let data):
                try check(sqlite3_bind_int(statement, 2, 1), database: database)
                try check(sqlite3_bind_null(statement, 3), database: database)
                try bind(data, to: statement, index: 4, database: database)
                try bindFileNull(statement, database: database)
            case .file(let reference):
                try check(sqlite3_bind_int(statement, 2, 2), database: database)
                try check(sqlite3_bind_null(statement, 3), database: database)
                try check(sqlite3_bind_null(statement, 4), database: database)
                try bind(reference.url.absoluteString, to: statement, index: 7, database: database)
                try bind(reference.displayName, to: statement, index: 8, database: database)
                try bind(reference.bookmark, to: statement, index: 9, database: database)
            }
            try check(
                sqlite3_bind_double(statement, 5, item.lastCopiedAt.timeIntervalSinceReferenceDate),
                database: database
            )
            try check(sqlite3_bind_int(statement, 6, item.isPinned ? 1 : 0), database: database)
            try bind(item.category.rawValue, to: statement, index: 10, database: database)
            try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
        }
    }

    private func bindFileNull(_ statement: OpaquePointer, database: OpaquePointer) throws {
        try check(sqlite3_bind_null(statement, 7), database: database)
        try check(sqlite3_bind_null(statement, 8), database: database)
        try check(sqlite3_bind_null(statement, 9), database: database)
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
        _ values: [String],
        to statement: OpaquePointer,
        database: OpaquePointer
    ) throws {
        for (offset, value) in values.enumerated() {
            try bind(value, to: statement, index: Int32(offset + 1), database: database)
        }
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
