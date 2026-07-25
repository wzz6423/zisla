import Foundation
import SQLite3
import Testing

@testable import ZislaKit

@MainActor
struct ClipboardHistoryStoreTests {
    @Test
    func defaultCapacityIs999() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ClipboardHistoryStore(
            storageURL: directory.appendingPathComponent("clipboard-history.sqlite")
        )

        #expect(store.capacity == 999)
    }

    @Test
    func pinnedItemsSurviveHistoryCapacityAndPersist() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL, capacity: 2)

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
        #expect(restored.items == store.items)
    }

    @Test
    func recordingExistingContentMovesItToTheLatestHistoryPosition() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardHistoryStore(
            storageURL: directory.appendingPathComponent("clipboard-history.sqlite"),
            capacity: 3
        )

        #expect(store.record(.text("first")))
        #expect(store.record(.text("second")))
        #expect(store.record(.text("first")))

        #expect(store.historyItems.map(\.content) == [.text("first"), .text("second")])
        store.flushPendingChanges()
    }

    @Test
    func rejectsImagesOverConfiguredLimit() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardHistoryStore(
            storageURL: directory.appendingPathComponent("clipboard-history.sqlite"),
            maxImageBytes: 3
        )

        #expect(!store.record(.image(Data([0, 1, 2, 3]))))
        #expect(store.items.isEmpty)
    }

    @Test
    func changesAreCoalescedUntilTheyAreFlushed() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(
            storageURL: storageURL,
            persistenceDelay: .seconds(60)
        )

        #expect(store.record(.text("first")))
        #expect(store.record(.text("second")))
        #expect(!FileManager.default.fileExists(atPath: storageURL.path))

        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL)
        #expect(restored.historyItems.map(\.content) == [.text("second"), .text("first")])
    }

    @Test
    func removalsAndHistoryClearArePersistedIncrementally() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL)

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
        #expect(restored.items.map(\.content) == [.text("pinned")])
        #expect(restored.items.first?.isPinned == true)
    }

    @Test
    func oldJSONStorageIsIgnored() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("clipboard-history.json")
        let databaseURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let legacyItems = [ClipboardHistoryItem(content: .text("legacy"))]
        try JSONEncoder().encode(legacyItems).write(to: legacyURL)

        let store = ClipboardHistoryStore(storageURL: databaseURL)

        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: databaseURL.path))
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test
    func corruptedDatabaseIsNotOverwritten() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let corrupted = Data("not a sqlite database".utf8)
        try corrupted.write(to: storageURL)

        let store = ClipboardHistoryStore(storageURL: storageURL)
        #expect(store.errorDescription != nil)

        #expect(store.record(.text("new value")))
        store.flushPendingChanges()

        #expect(store.errorDescription != nil)
        #expect(try Data(contentsOf: storageURL) == corrupted)
    }

    @Test
    func updatingTextDoesNotRewriteUnchangedImageBlob() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL)

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
        #expect(restored.items.map(\.content) == store.items.map(\.content))
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
