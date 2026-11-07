import CryptoKit
import Foundation
import SQLite3
import Testing

@testable import ZislaKit

struct ClipboardHistoryDatabaseDedupTests {
    @Test(arguments: DedupContentKind.allCases)
    fileprivate func candidateQueriesStayBoundedAsHistoryGrows(kind: DedupContentKind) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let trace = DedupQueryTrace()
        let database = ClipboardHistoryDatabase(
            storageURL: url,
            connectionObserver: { trace.attach(to: $0) }
        )
        try await database.apply((0..<16).map {
            .upsert(item(kind.content("seed-\($0)"), time: Double($0), pinned: $0.isMultiple(of: 3)), capacity: nil)
        })
        trace.reset()
        try await database.apply([.upsert(item(kind.content("small-probe")), capacity: nil)])
        let small = trace.queries

        try await database.apply((16..<96).map {
            .upsert(item(kind.content("seed-\($0)"), time: Double($0), pinned: $0.isMultiple(of: 3)), capacity: nil)
        })
        trace.reset()
        try await database.apply([.upsert(item(kind.content("large-probe")), capacity: nil)])
        let large = trace.queries

        #expect(small.count == 2)
        #expect(large.count == 2)
        for (before, after) in zip(small, large) {
            #expect(after.fullScanSteps == 0, "Deduplication scanned history rows: \(after.sql)")
            #expect(after.vmSteps <= before.vmSteps + 12, "Deduplication work grew with unrelated history")
            let plan = try queryPlan(after.sql, at: url)
            #expect(
                plan.contains { $0.contains("content_type=? AND content_digest=?") },
                "Candidate lookup must use both parts of the small index: \(plan)"
            )
        }
    }

    @Test(arguments: DedupContentKind.allCases)
    fileprivate func duplicatesRetainPinAcrossPagesAndPreserveIncomingIdentity(kind: DedupContentKind) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        var database: ClipboardHistoryDatabase? = ClipboardHistoryDatabase(storageURL: url)
        let original = item(kind.content("duplicate"), time: 1, pinned: true)
        let fillers = (0..<4).map { item(kind.content("filler-\($0)"), time: Double(100 + $0), pinned: true) }
        try await database?.apply(([original] + fillers).map { .upsert($0, capacity: nil) })
        let firstPage = try await database!.loadPage(
            scope: .all, searchText: "", category: .all, offset: 0, limit: 2
        )
        #expect(!firstPage.items.contains { $0.id == original.id })

        let incoming = item(kind.content("duplicate"), time: 500)
        try await database?.apply([.upsert(incoming, capacity: nil)])
        database = nil
        let reopened = ClipboardHistoryDatabase(storageURL: url)
        let page = try await loadAll(reopened)
        let replacement = try #require(page.items.first { $0.content == incoming.content })
        #expect(page.totalCount == fillers.count + 1)
        #expect(replacement.id == incoming.id)
        #expect(replacement.lastCopiedAt == incoming.lastCopiedAt)
        #expect(replacement.isPinned)
        #expect(!page.items.contains { $0.id == original.id })

        var unpinned = replacement
        unpinned.isPinned = false
        try await reopened.apply([.upsert(unpinned, capacity: nil)])
        #expect(try await loadAll(reopened).items.first { $0.id == incoming.id }?.isPinned == false)
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE id = '\(unpinned.id.uuidString)' AND length(content_digest) = 32", at: url) == 1)
        unpinned.content = kind.content("changed under the same identity")
        try await reopened.apply([.upsert(unpinned, capacity: nil)])
        #expect(try await loadAll(reopened).items.contains(unpinned))
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE id = '\(unpinned.id.uuidString)' AND length(content_digest) = 32", at: url) == 1)
    }

    @Test
    func sameDigestTypeChangeDeduplicatesWithinOneTransaction() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let database = ClipboardHistoryDatabase(storageURL: url)
        let original = item(.text("A"), pinned: true)
        let changed = item(.image(Data("A".utf8)), id: original.id, time: 2, pinned: true)
        let replacement = item(changed.content, time: 3)
        try await database.apply([
            .upsert(original, capacity: nil),
            .upsert(changed, capacity: nil),
            .upsert(replacement, capacity: nil),
        ])
        let page = try await loadAll(database)
        #expect(page.totalCount == 1)
        #expect(page.items.first?.id == replacement.id)
        #expect(page.items.first?.content == changed.content)
        #expect(page.items.first?.isPinned == true)
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE length(content_digest) = 32", at: url) == 1)
    }

    @Test
    func anyPinnedLegacyDuplicateKeepsTheReplacementPinned() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        try createLegacySchema(at: url, version: 4)
        let duplicate = ClipboardHistoryContent.text("duplicate")
        let old = [item(duplicate), item(duplicate, pinned: true)]
        try insertLegacy(old, at: url, hasFileColumns: true)
        let database = ClipboardHistoryDatabase(storageURL: url)
        let replacement = item(duplicate, time: 2)
        try await database.apply([.upsert(replacement, capacity: nil)])
        let page = try await loadAll(database)
        #expect(page.totalCount == 1)
        #expect(page.items.first?.id == replacement.id)
        #expect(page.items.first?.isPinned == true)
    }

    @Test
    func backfillReadsOnlyMissingPayloadsWithBoundedWork() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        try createLegacySchema(at: url, version: 4)
        let legacy = (0..<72).map {
            item(DedupContentKind.allCases[$0 % 3].content("legacy-\($0)"), time: Double($0))
        }
        try insertLegacy(legacy, at: url, hasFileColumns: true)
        let trace = DedupQueryTrace()
        let database = ClipboardHistoryDatabase(storageURL: url, connectionObserver: { trace.attach(to: $0) })
        let page = try await database.loadPage(
            scope: .all, searchText: "", category: .all, offset: 0, limit: 1
        )
        #expect(page.totalCount == legacy.count)
        let initialReads = trace.backfillQueries
        #expect(initialReads.allSatisfy { $0.fullScanSteps == 0 })
        #expect(initialReads.reduce(0) { $0 + $1.vmSteps } < Int32(legacy.count * 60 + 100))
        #expect(trace.activeCursorDigestUpdates == 0, "Backfill must finish the indexed read before changing its key")
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE length(content_digest) = 32", at: url) == legacy.count)
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE content_digest IS NULL", at: url) == 0)

        try insertLegacy([item(DedupContentKind.image.content("later"))], at: url, hasFileColumns: true)
        trace.reset()
        try await database.apply([.upsert(item(.text("unrelated text")), capacity: nil)])
        let laterReads = trace.backfillQueries
        #expect(!laterReads.isEmpty)
        #expect(laterReads.allSatisfy { $0.fullScanSteps == 0 })
        #expect(trace.activeCursorDigestUpdates == 0)
        #expect(laterReads.map(\.vmSteps).max()! <= initialReads.map(\.vmSteps).max()!)
        for read in laterReads {
            #expect(try queryPlan(read.sql, at: url).contains {
                $0.contains("content_type=? AND content_digest=?")
            })
        }
    }

    @Test(arguments: DedupContentKind.allCases)
    fileprivate func forgedDigestCannotDeleteOrInheritPinFromDifferentContent(kind: DedupContentKind) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let database = ClipboardHistoryDatabase(storageURL: url)
        let unrelated = item(kind.content("unrelated"), pinned: true)
        let incoming = item(kind.content("incoming"), time: 2)
        try await database.apply([.upsert(unrelated, capacity: nil)])
        try withDatabase(at: url) { handle in
            let statement = try prepare("UPDATE clipboard_history SET content_digest = ? WHERE id = ?", on: handle)
            defer { sqlite3_finalize(statement) }
            try bind(digest(incoming.content), to: statement, index: 1)
            try bind(unrelated.id.uuidString, to: statement, index: 2)
            try requireDone(statement, on: handle)
        }
        try await database.apply([.upsert(incoming, capacity: nil)])
        let replacement = item(incoming.content, time: 3)
        try await database.apply([.upsert(replacement, capacity: nil)])
        let page = try await loadAll(database)
        #expect(page.totalCount == 2)
        #expect(page.items.contains(unrelated))
        #expect(page.items.contains(replacement))
        #expect(!page.items.contains { $0.id == incoming.id })
        #expect(page.items.first { $0.id == replacement.id }?.isPinned == false)
    }

    @Test(arguments: [0, 4, 16])
    func legacySchemaUpgradesInPlaceAndReopens(schema: Int) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let version = schema == 16 ? 4 : schema
        let legacy = [
            item(.text("legacy é 文本"), time: 1, pinned: true),
            item(.image(Data([0, 1, 2, 255])), time: 2),
        ] + (version == 4 ? [item(DedupContentKind.file.content("legacy-file"), time: 3)] : [])
        if schema == 16 { try execute("PRAGMA encoding = 'UTF-16le'", at: url) }
        try createLegacySchema(at: url, version: version)
        try insertLegacy(legacy, at: url, hasFileColumns: version == 4)
        if version == 4 {
            try execute(
                """
                UPDATE clipboard_history SET content_category = '文档' WHERE content_type = 0;
                CREATE TRIGGER reject_category_reclassification
                BEFORE UPDATE OF content_category ON clipboard_history
                WHEN OLD.content_category IS NOT NULL
                BEGIN SELECT RAISE(ABORT, 'version four categories must remain unchanged'); END;
                """,
                at: url
            )
        }
        var database: ClipboardHistoryDatabase? = ClipboardHistoryDatabase(storageURL: url)
        #expect(try await loadAll(database!).items.sorted { $0.id.uuidString < $1.id.uuidString }
            == legacy.sorted { $0.id.uuidString < $1.id.uuidString })
        #expect(try scalar("PRAGMA user_version", at: url) == 5)
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE length(content_digest) = 32", at: url) == legacy.count)
        database = nil
        let reopened = ClipboardHistoryDatabase(storageURL: url)
        #expect(try await loadAll(reopened).totalCount == legacy.count)
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE content_digest IS NULL", at: url) == 0)
        if version == 4 {
            #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE content_category = '文档'", at: url) == 1)
        }
        let replacement = item(legacy[0].content, time: 20)
        try await reopened.apply([.upsert(replacement, capacity: nil)])
        let page = try await loadAll(reopened)
        #expect(page.totalCount == legacy.count)
        #expect(page.items.first { $0.id == replacement.id }?.isPinned == true)
    }

    @Test(arguments: [false, true])
    func migrationFailureRollsBackAndCanRetry(failDuringBackfill: Bool) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let legacy = [item(.text("first")), item(.image(Data([1, 0, 2])), time: 2)]
        try createLegacySchema(at: url, version: 4)
        try insertLegacy(legacy, at: url, hasFileColumns: true)
        if failDuringBackfill {
            try execute(
                """
                ALTER TABLE clipboard_history ADD COLUMN content_digest BLOB;
                CREATE TRIGGER reject_second_digest
                BEFORE UPDATE OF content_digest ON clipboard_history
                WHEN OLD.rowid = 2
                BEGIN SELECT RAISE(ABORT, 'injected digest backfill failure'); END;
                """,
                at: url
            )
        }
        let fault = DedupMigrationFault()
        let database = ClipboardHistoryDatabase(
            storageURL: url,
            connectionObserver: { handle in
                if !failDuringBackfill { fault.attach(to: handle) }
            }
        )
        await #expect(throws: (any Error).self) { try await loadAll(database) }
        #expect(try scalar("PRAGMA user_version", at: url) == 4)
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history", at: url) == legacy.count)
        #expect(try scalar("SELECT COUNT(*) FROM sqlite_master WHERE name = 'clipboard_history_content_lookup'", at: url) == 0)
        if failDuringBackfill {
            #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE content_digest IS NOT NULL", at: url) == 0)
            try execute("DROP TRIGGER reject_second_digest", at: url)
        } else {
            #expect(try scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_history') WHERE name = 'content_digest'", at: url) == 0)
            fault.disable()
        }
        #expect(try await loadAll(database).totalCount == legacy.count)
        #expect(try scalar("PRAGMA user_version", at: url) == 5)
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE length(content_digest) = 32", at: url) == legacy.count)
    }

    @Test(arguments: [false, true])
    func legacyWriterNullsAndStaleUpdatesAreRepaired(reopen: Bool) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        var database: ClipboardHistoryDatabase? = ClipboardHistoryDatabase(storageURL: url)
        let original = DedupContentKind.allCases.map { item($0.content("old"), pinned: true) }
        try await database?.apply(original.map { .upsert($0, capacity: nil) })
        let changed = zip(original, DedupContentKind.allCases).map { old, kind in
            item(kind.content("changed"), id: old.id, time: 2, pinned: true)
        }
        let inserted = DedupContentKind.allCases.map { item($0.content("old-writer-insert"), time: 3) }
        try insertLegacy(changed + inserted, at: url, hasFileColumns: true)
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE content_digest IS NULL", at: url) == 6)
        if reopen {
            database = nil
            database = ClipboardHistoryDatabase(storageURL: url)
        }
        let replacements = (changed + inserted).map { item($0.content, time: 10) }
        try await database?.apply(replacements.map { .upsert($0, capacity: nil) })
        let reopened = ClipboardHistoryDatabase(storageURL: url)
        let page = try await loadAll(reopened)
        #expect(page.totalCount == replacements.count)
        #expect(Set(page.items.map(\.id)) == Set(replacements.map(\.id)))
        #expect(page.items.filter(\.isPinned).count == changed.count)
        #expect(page.items.allSatisfy { $0.lastCopiedAt == Date(timeIntervalSinceReferenceDate: 10) })
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE length(content_digest) = 32", at: url) == replacements.count)
    }

    @Test
    func failedReplacementRestoresDeletedDuplicateAndUnhashedLegacyRow() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let database = ClipboardHistoryDatabase(storageURL: url)
        try await database.apply([.upsert(item(.text("schema initialization")), capacity: nil)])
        let original = item(.text("duplicate"), pinned: true)
        try insertLegacy([original], at: url, hasFileColumns: true)
        try execute(
            """
            CREATE TRIGGER reject_replacement
            BEFORE INSERT ON clipboard_history
            WHEN NEW.text_value = 'duplicate'
            BEGIN SELECT RAISE(ABORT, 'injected replacement failure'); END;
            """,
            at: url
        )
        let replacement = item(original.content, time: 2)
        await #expect(throws: (any Error).self) {
            try await database.apply([.upsert(replacement, capacity: nil)])
        }
        #expect(try await loadAll(database).items.contains(original))
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE text_value = 'duplicate' AND content_digest IS NULL", at: url) == 1)
        try execute("DROP TRIGGER reject_replacement", at: url)
        try await database.apply([.upsert(replacement, capacity: nil)])
        let page = try await loadAll(database)
        #expect(!page.items.contains { $0.id == original.id })
        #expect(page.items.first { $0.id == replacement.id }?.isPinned == true)
    }

    @Test
    func emptyAndByteBoundariesKeepPersistedEquality() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let database = ClipboardHistoryDatabase(storageURL: url)
        try await database.apply([])
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try await loadAll(database).items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let text = ["", "A", "a", " A ", "é", "e\u{301}", "' OR 1=1; --", "prefix\u{0}first"]
        let contents = text.map(ClipboardHistoryContent.text)
            + [.image(Data()), .image(Data([0])), .image(Data([0, 1])), .image(Data("A".utf8))]
        try await database.apply(contents.enumerated().map {
            .upsert(item($0.element, time: Double($0.offset)), capacity: nil)
        })
        let last = item(.text("prefix\u{0}second"), time: 100)
        try await database.apply([.upsert(last, capacity: nil)])
        let page = try await loadAll(database)
        #expect(page.totalCount == contents.count)
        #expect(page.items.first { $0.id == last.id }?.content == .text("prefix"))
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE content_type = 0 AND text_value = 'prefix'", at: url) == 1)
        #expect(page.items.contains { $0.content == .image(Data([0, 1])) })
        #expect(page.items.contains { $0.content == .image(Data("A".utf8)) })
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history WHERE content_type = 0 AND length(content_digest) = 32", at: url) == text.count)
    }

    private func item(
        _ content: ClipboardHistoryContent,
        id: UUID = UUID(),
        time: Double = 1,
        pinned: Bool = false
    ) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id, content: content,
            lastCopiedAt: Date(timeIntervalSinceReferenceDate: time), isPinned: pinned
        )
    }

    private func loadAll(_ database: ClipboardHistoryDatabase) async throws -> ClipboardHistoryPage {
        try await database.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 100)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-dedup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createLegacySchema(at url: URL, version: Int) throws {
        let fileColumns = version == 4
            ? ", file_url TEXT, file_display_name TEXT, file_bookmark BLOB, content_category TEXT"
            : ""
        try execute(
            """
            CREATE TABLE clipboard_history (
                id TEXT PRIMARY KEY NOT NULL, content_type INTEGER NOT NULL,
                text_value TEXT, image_data BLOB, last_copied_at REAL NOT NULL,
                is_pinned INTEGER NOT NULL\(fileColumns)
            );
            PRAGMA user_version = \(version);
            """,
            at: url
        )
    }

    private func insertLegacy(_ items: [ClipboardHistoryItem], at url: URL, hasFileColumns: Bool) throws {
        try withDatabase(at: url) { database in
            let files = hasFileColumns ? ", file_url, file_display_name, file_bookmark, content_category" : ""
            let fileValues = hasFileColumns ? ", ?, ?, ?, ?" : ""
            let fileUpdates = hasFileColumns
                ? ", file_url = excluded.file_url, file_display_name = excluded.file_display_name, file_bookmark = excluded.file_bookmark, content_category = excluded.content_category"
                : ""
            let statement = try prepare(
                """
                INSERT INTO clipboard_history (
                    id, content_type, text_value, image_data, last_copied_at, is_pinned\(files)
                ) VALUES (?, ?, ?, ?, ?, ?\(fileValues))
                ON CONFLICT(id) DO UPDATE SET content_type = excluded.content_type,
                    text_value = excluded.text_value, image_data = excluded.image_data,
                    last_copied_at = excluded.last_copied_at, is_pinned = excluded.is_pinned\(fileUpdates)
                """,
                on: database
            )
            defer { sqlite3_finalize(statement) }
            for item in items {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(item.id.uuidString, to: statement, index: 1)
                switch item.content {
                case .text(let value):
                    sqlite3_bind_int(statement, 2, 0)
                    try bind(value, to: statement, index: 3)
                case .image(let data):
                    sqlite3_bind_int(statement, 2, 1)
                    try bind(data, to: statement, index: 4)
                case .file(let file):
                    sqlite3_bind_int(statement, 2, 2)
                    try bind(file.url.absoluteString, to: statement, index: 7)
                    try bind(file.displayName, to: statement, index: 8)
                    try bind(file.bookmark, to: statement, index: 9)
                }
                sqlite3_bind_double(statement, 5, item.lastCopiedAt.timeIntervalSinceReferenceDate)
                sqlite3_bind_int(statement, 6, item.isPinned ? 1 : 0)
                if hasFileColumns { try bind(item.category.rawValue, to: statement, index: 10) }
                try requireDone(statement, on: database)
            }
        }
    }

    private func digest(_ content: ClipboardHistoryContent) -> Data {
        let data: Data
        switch content {
        case .text(let text): data = Data(text.utf8.prefix { $0 != 0 })
        case .image(let image): data = image
        case .file(let file): data = Data(file.url.absoluteString.utf8)
        }
        return Data(SHA256.hash(data: data))
    }

    private func queryPlan(_ sql: String, at url: URL) throws -> [String] {
        try withDatabase(at: url) { database in
            let statement = try prepare("EXPLAIN QUERY PLAN \(sql)", on: database)
            defer { sqlite3_finalize(statement) }
            var result: [String] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    if let detail = sqlite3_column_text(statement, 3) { result.append(String(cString: detail)) }
                case SQLITE_DONE:
                    return result
                default:
                    throw DedupSQLiteError(message: String(cString: sqlite3_errmsg(database)))
                }
            }
        }
    }

    private func scalar(_ sql: String, at url: URL) throws -> Int {
        try withDatabase(at: url) { database in
            let statement = try prepare(sql, on: database)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw DedupSQLiteError() }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private func execute(_ sql: String, at url: URL) throws {
        try withDatabase(at: url) { database in
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw DedupSQLiteError(message: String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func withDatabase<T>(at url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw DedupSQLiteError()
        }
        defer { sqlite3_close(handle) }
        return try body(handle)
    }

    private func prepare(_ sql: String, on database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw DedupSQLiteError(message: String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer, index: Int32) throws {
        let result = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else { throw DedupSQLiteError() }
    }

    private func bind(_ value: Data, to statement: OpaquePointer, index: Int32) throws {
        let result = value.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else { throw DedupSQLiteError() }
    }

    private func requireDone(_ statement: OpaquePointer, on database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DedupSQLiteError(message: String(cString: sqlite3_errmsg(database)))
        }
    }
}

private enum DedupContentKind: CaseIterable, Sendable {
    case text, image, file

    func content(_ value: String) -> ClipboardHistoryContent {
        switch self {
        case .text: return .text("synthetic \(value)")
        case .image:
            var data = Data(repeating: 0xA5, count: 8 * 1024)
            data.replaceSubrange(0..<value.utf8.count, with: value.utf8)
            return .image(data)
        case .file:
            return .file(ClipboardFileReference(
                url: URL(fileURLWithPath: "/synthetic-clipboard/\(value).dat"),
                displayName: value, bookmark: Data([1, 2])
            ))
        }
    }
}

private final class DedupQueryTrace: @unchecked Sendable {
    struct Query: Sendable {
        var sql: String
        var fullScanSteps: Int32
        var vmSteps: Int32
    }

    private let lock = NSLock()
    private var captured: [Query] = []
    private var backfills: [Query] = []
    private var activeCursorUpdates = 0
    var queries: [Query] { lock.withLock { captured } }
    var backfillQueries: [Query] { lock.withLock { backfills } }
    var activeCursorDigestUpdates: Int { lock.withLock { activeCursorUpdates } }
    func reset() {
        lock.withLock {
            captured.removeAll()
            backfills.removeAll()
            activeCursorUpdates = 0
        }
    }

    func attach(to database: OpaquePointer) {
        sqlite3_trace_v2(database, UInt32(SQLITE_TRACE_STMT | SQLITE_TRACE_PROFILE), { event, context, rawStatement, _ in
            guard let context, let rawStatement else { return 0 }
            let trace = Unmanaged<DedupQueryTrace>.fromOpaque(context).takeUnretainedValue()
            let statement = OpaquePointer(rawStatement)
            guard let rawSQL = sqlite3_sql(statement) else { return 0 }
            let sql = String(cString: rawSQL)
            if event == UInt32(SQLITE_TRACE_STMT) {
                if sql == "UPDATE clipboard_history SET content_digest = ? WHERE rowid = ?" {
                    var cursor = sqlite3_next_stmt(sqlite3_db_handle(statement), nil)
                    while let read = cursor {
                        if let rawReadSQL = sqlite3_sql(read),
                           String(cString: rawReadSQL).hasPrefix("SELECT"),
                           sqlite3_stmt_busy(read) != 0 {
                            trace.lock.withLock { trace.activeCursorUpdates += 1 }
                        }
                        cursor = sqlite3_next_stmt(sqlite3_db_handle(statement), read)
                    }
                }
                return 0
            }
            let isBackfill = sql.contains("WHERE content_type IN (0, 1, 2) AND content_digest IS NULL")
            guard isBackfill || sql.contains("WHERE id <> ?") else { return 0 }
            let query = Query(
                sql: sql,
                fullScanSteps: sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_FULLSCAN_STEP, 1),
                vmSteps: sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_VM_STEP, 1)
            )
            trace.lock.withLock {
                if isBackfill { trace.backfills.append(query) }
                else { trace.captured.append(query) }
            }
            return 0
        }, Unmanaged.passUnretained(self).toOpaque())
    }
}

private final class DedupMigrationFault: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    func disable() { lock.withLock { enabled = false } }

    func attach(to database: OpaquePointer) {
        guard lock.withLock({ enabled }) else { return }
        sqlite3_set_authorizer(database, { _, action, name, _, _, _ in
            action == SQLITE_CREATE_INDEX && name.map { String(cString: $0) } == "clipboard_history_content_lookup"
                ? SQLITE_DENY : SQLITE_OK
        }, nil)
    }
}

private struct DedupSQLiteError: LocalizedError {
    var message = "unable to execute synthetic clipboard SQL"
    var errorDescription: String? { message }
}
