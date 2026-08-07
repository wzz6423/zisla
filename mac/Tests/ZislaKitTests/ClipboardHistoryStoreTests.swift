import Foundation
import SQLite3
import Testing

@testable import ZislaKit

@MainActor
struct ClipboardHistoryStoreTests {
    @Test
    func defaultCapacityIsUnlimited() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ClipboardHistoryStore(
            storageURL: directory.appendingPathComponent("clipboard-history.sqlite")
        )
        await store.waitUntilLoaded()

        #expect(store.capacity == nil)
    }

    @Test
    func pinnedItemsSurviveHistoryCapacityAndPersist() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL, capacity: 2)
        await store.waitUntilLoaded()

        #expect(store.record(.text("常用信息")))
        let pinnedID = try #require(store.items.first?.id)
        store.setPinned(id: pinnedID, isPinned: true)
        #expect(store.record(.text("第一条历史")))
        #expect(store.record(.text("第二条历史")))
        #expect(store.record(.text("第三条历史")))

        #expect(store.pinnedItems.map(\.content) == [.text("常用信息")])
        #expect(store.historyItems.map(\.content) == [.text("第三条历史"), .text("第二条历史")])

        store.flushPendingChanges()
        let restored = ClipboardHistoryStore(storageURL: storageURL, capacity: 2)
        await restored.waitUntilLoaded()
        #expect(restored.items == store.items)
    }

    @Test
    func recordingExistingContentMovesItToTheLatestHistoryPosition() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardHistoryStore(
            storageURL: directory.appendingPathComponent("clipboard-history.sqlite"),
            capacity: 3
        )
        await store.waitUntilLoaded()

        #expect(store.record(.text("first")))
        #expect(store.record(.text("second")))
        #expect(store.record(.text("first")))

        #expect(store.historyItems.map(\.content) == [.text("first"), .text("second")])
        store.flushPendingChanges()
    }

    @Test
    func rejectsImagesOverConfiguredLimit() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardHistoryStore(
            storageURL: directory.appendingPathComponent("clipboard-history.sqlite"),
            maxImageBytes: 3
        )
        await store.waitUntilLoaded()

        #expect(!store.record(.image(Data([0, 1, 2, 3]))))
        #expect(store.items.isEmpty)
    }

    @Test
    func changesAreCoalescedUntilTheyAreFlushed() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(
            storageURL: storageURL,
            persistenceDelay: .seconds(60)
        )
        await store.waitUntilLoaded()

        #expect(store.record(.text("first")))
        #expect(store.record(.text("second")))
        #expect(!FileManager.default.fileExists(atPath: storageURL.path))

        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL)
        await restored.waitUntilLoaded()
        #expect(restored.historyItems.map(\.content) == [.text("second"), .text("first")])
    }

    @Test
    func removalsAndHistoryClearArePersistedIncrementally() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()

        #expect(store.record(.text("pinned")))
        let pinnedID = try #require(store.items.first?.id)
        store.setPinned(id: pinnedID, isPinned: true)
        #expect(store.record(.text("remove")))
        let removedID = try #require(store.historyItems.first?.id)
        #expect(store.record(.text("clear")))
        store.flushPendingChanges()

        store.remove(id: removedID)
        store.removeAllHistory()
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL)
        await restored.waitUntilLoaded()
        #expect(restored.items.map(\.content) == [.text("pinned")])
        #expect(restored.items.first?.isPinned == true)
    }

    @Test
    func historyClearRemovesItemsBeyondCurrentPage() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await store.waitUntilLoaded()

        #expect(store.record(.text("older history")))
        #expect(store.record(.text("newer history")))
        #expect(store.recordPinned(.text("older pinned")))
        #expect(store.recordPinned(.text("newer pinned")))
        store.flushPendingChanges()

        let firstPage = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await firstPage.waitUntilLoaded()
        #expect(firstPage.items.allSatisfy { $0.isPinned })
        #expect(firstPage.totalItemCount == 4)

        firstPage.removeAllHistory()
        firstPage.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 2)
        #expect(restored.items.allSatisfy { $0.isPinned })
    }

    @Test
    func oldJSONStorageIsIgnored() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("clipboard-history.json")
        let databaseURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let legacyItems = [ClipboardHistoryItem(content: .text("legacy"))]
        try JSONEncoder().encode(legacyItems).write(to: legacyURL)

        let store = ClipboardHistoryStore(storageURL: databaseURL)
        await store.waitUntilLoaded()

        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: databaseURL.path))
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test
    func corruptedDatabaseIsNotOverwritten() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let corrupted = Data("not a sqlite database".utf8)
        try corrupted.write(to: storageURL)

        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()
        #expect(store.errorDescription != nil)

        #expect(store.record(.text("new value")))
        store.flushPendingChanges()

        #expect(store.errorDescription != nil)
        #expect(try Data(contentsOf: storageURL) == corrupted)
    }

    @Test
    func updatingTextDoesNotRewriteUnchangedImageBlob() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()

        #expect(store.record(.image(Data([0, 1, 2, 3]))))
        #expect(store.record(.text("text")))
        store.flushPendingChanges()
        try executeSQL(
            """
            CREATE TRIGGER reject_unchanged_image_update
            BEFORE UPDATE ON clipboard_history
            WHEN OLD.content_type = 1
            BEGIN
                SELECT RAISE(ABORT, 'unchanged image was rewritten');
            END
            """,
            at: storageURL
        )

        #expect(store.record(.text("text")))
        store.flushPendingChanges()

        #expect(store.errorDescription == nil)
        let restored = ClipboardHistoryStore(storageURL: storageURL)
        await restored.waitUntilLoaded()
        #expect(restored.items.map(\.content) == store.items.map(\.content))
    }

    @Test
    func recordPinnedAddsEmojiTextAndKeepsItPinnedAcrossRestart() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL, capacity: 2)
        await store.waitUntilLoaded()

        let emoji = "常用信息 🎉👨‍👩‍👧‍👦🚀"
        #expect(store.recordPinned(.text(emoji)))
        // Append history past capacity; pinned items must not be evicted.
        #expect(store.record(.text("历史一")))
        #expect(store.record(.text("历史二")))
        #expect(store.record(.text("历史三")))

        #expect(store.pinnedItems.map(\.content) == [.text(emoji)])
        #expect(store.pinnedItems.first?.isPinned == true)

        store.flushPendingChanges()
        let restored = ClipboardHistoryStore(storageURL: storageURL, capacity: 2)
        await restored.waitUntilLoaded()
        #expect(restored.pinnedItems.map(\.content) == [.text(emoji)])
        #expect(restored.pinnedItems.first?.isPinned == true)
    }

    @Test
    func recordPinnedDeduplicatesRepeatedRecords() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardHistoryStore(
            storageURL: directory.appendingPathComponent("clipboard-history.sqlite")
        )
        await store.waitUntilLoaded()

        #expect(store.recordPinned(.text("重复")))
        #expect(store.recordPinned(.text("重复")))

        #expect(store.pinnedItems.map(\.content) == [.text("重复")])
        #expect(store.items.count == 1)
        store.flushPendingChanges()
    }

    @Test
    func fileItemIsWrittenAndRestoredAfterRestart() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let fileURL = directory.appendingPathComponent("附件.txt")
        try Data("hello".utf8).write(to: fileURL)

        let store = ClipboardHistoryStore(storageURL: storageURL, capacity: 2)
        await store.waitUntilLoaded()
        let content = try ClipboardHistoryContent.file(at: fileURL)
        #expect(store.recordPinned(content))

        let pinned = try #require(store.pinnedItems.first)
        #expect(pinned.isPinned)
        guard case .file(let reference) = pinned.content else {
            Issue.record("期望文件内容")
            return
        }
        #expect(reference.displayName == "附件.txt")
        #expect(reference.url.standardizedFileURL == fileURL.standardizedFileURL)

        store.flushPendingChanges()
        let restored = ClipboardHistoryStore(storageURL: storageURL, capacity: 2)
        await restored.waitUntilLoaded()
        let restoredItem = try #require(restored.pinnedItems.first)
        #expect(restoredItem.isPinned)
        guard case .file(let restoredReference) = restoredItem.content else {
            Issue.record("重启后期望文件内容")
            return
        }
        #expect(restoredReference.displayName == "附件.txt")
        #expect(restoredReference.url.standardizedFileURL == fileURL.standardizedFileURL)
    }

    @Test
    func missingFileItemIsDroppedOnLoad() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let fileURL = directory.appendingPathComponent("临时.txt")
        try Data("bye".utf8).write(to: fileURL)

        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()
        #expect(store.recordPinned(try ClipboardHistoryContent.file(at: fileURL)))
        #expect(store.record(.text("保留文字")))
        store.flushPendingChanges()

        try FileManager.default.removeItem(at: fileURL)
        let restored = ClipboardHistoryStore(storageURL: storageURL)
        await restored.waitUntilLoaded()
        #expect(restored.items.map(\.content) == [.text("保留文字")])
    }

    @Test
    func legacyTextAndImageRowsRemainReadableAfterMigration() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        // Build a history DB with only the old 6 columns to simulate pre-migration data.
        try executeSQL(
            """
            CREATE TABLE clipboard_history (
                id TEXT PRIMARY KEY NOT NULL,
                content_type INTEGER NOT NULL,
                text_value TEXT,
                image_data BLOB,
                last_copied_at REAL NOT NULL,
                is_pinned INTEGER NOT NULL
            );
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned)
            VALUES ('\(UUID().uuidString)', 0, '旧文字', NULL, 1000.0, 1);
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned)
            VALUES ('\(UUID().uuidString)', 1, NULL, x'00010203', 900.0, 0);
            """,
            at: storageURL
        )

        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()
        #expect(store.errorDescription == nil)
        #expect(store.pinnedItems.map(\.content) == [.text("旧文字")])
        #expect(store.historyItems.map(\.content) == [.image(Data([0, 1, 2, 3]))])

        // After migration, file items can still be written and read back.
        let fileURL = directory.appendingPathComponent("新文件.dat")
        try Data([9]).write(to: fileURL)
        #expect(store.recordPinned(try ClipboardHistoryContent.file(at: fileURL)))
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL)
        await restored.waitUntilLoaded()
        #expect(restored.items.contains { $0.content == .text("旧文字") })
        #expect(restored.items.contains { if case .file = $0.content { return true }; return false })
    }

    @Test
    func historyIsPagedAndOlderItemsRemainSearchable() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await store.waitUntilLoaded()

        #expect(store.record(.text("old searchable value")))
        #expect(store.record(.text("middle value")))
        #expect(store.record(.text("latest value")))
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 3)
        #expect(restored.items.count == 2)
        #expect(restored.historyItems.map(\.content) == [
            .text("latest value"),
            .text("middle value"),
        ])

        restored.updateQuery(scope: .all, searchText: "old searchable")
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 1)
        #expect(restored.items.map(\.content) == [.text("old searchable value")])

        restored.updateQuery(scope: .all, searchText: "")
        await restored.waitUntilLoaded()
        restored.loadNextPage()
        await restored.waitUntilLoaded()
        #expect(restored.items.map(\.content) == [.text("old searchable value")])
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func executeSQL(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw SQLiteTestError(message: "unable to open test database")
        }
        defer { sqlite3_close(database) }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            throw SQLiteTestError(
                message: errorMessage.map { String(cString: $0) } ?? "unable to execute test SQL"
            )
        }
    }
}

private struct SQLiteTestError: Error {
    let message: String
}
