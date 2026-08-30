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
    func clipboardDatabaseIsRestrictedToTheCurrentUser() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()

        #expect(store.record(.text("private clipboard")))
        store.flushPendingChanges()

        let databaseFileNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(storageURL.lastPathComponent) }
        #expect(databaseFileNames.contains(storageURL.lastPathComponent))
        for fileName in databaseFileNames {
            let path = directory.appendingPathComponent(fileName).path
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
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
    func asynchronousPersistenceFailureRetainsMutationOrderForTheNextBatch() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(
            storageURL: storageURL,
            persistenceDelay: .milliseconds(1)
        )
        await store.waitUntilLoaded()

        #expect(store.record(.text("existing")))
        store.flushPendingChanges()
        try executeSQL(
            """
            CREATE TRIGGER reject_history_removal
            BEFORE DELETE ON clipboard_history
            BEGIN
                SELECT RAISE(ABORT, 'simulated asynchronous persistence failure');
            END
            """,
            at: storageURL
        )

        store.removeAllHistory()
        try await waitUntil { store.errorDescription != nil }
        try executeSQL("DROP TRIGGER reject_history_removal", at: storageURL)

        #expect(store.record(.text("later")))
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL)
        await restored.waitUntilLoaded()
        #expect(restored.historyItems.map(\.content) == [.text("later")])
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
            VALUES ('\(UUID().uuidString)', 0, 'https://legacy.example/path', NULL, 950.0, 0);
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned)
            VALUES ('\(UUID().uuidString)', 1, NULL, x'00010203', 900.0, 0);
            """,
            at: storageURL
        )

        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()
        #expect(store.errorDescription == nil)
        #expect(store.pinnedItems.map(\.content) == [.text("旧文字")])
        #expect(store.historyItems.map(\.content) == [
            .text("https://legacy.example/path"),
            .image(Data([0, 1, 2, 3])),
        ])

        // After migration, file items can still be written and read back.
        let fileURL = directory.appendingPathComponent("新文件.dat")
        try Data([9]).write(to: fileURL)
        #expect(store.recordPinned(try ClipboardHistoryContent.file(at: fileURL)))
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL)
        await restored.waitUntilLoaded()
        #expect(restored.items.contains { $0.content == .text("旧文字") })
        #expect(restored.items.contains { if case .file = $0.content { return true }; return false })

        restored.updateQuery(scope: .all, searchText: "", category: .image)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 1)
        #expect(restored.items.map(\.content) == [.image(Data([0, 1, 2, 3]))])

        restored.updateQuery(scope: .all, searchText: "", category: .url)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 1)
        #expect(restored.items.map(\.content) == [.text("https://legacy.example/path")])

        restored.updateQuery(scope: .all, searchText: "", category: .text)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 1)
        #expect(restored.items.map(\.content) == [.text("旧文字")])
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

    @Test
    func initialLoadShowsOnlyRecentEightHistoryItemsUntilExpanded() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()

        for value in 0..<10 {
            #expect(store.record(.text("history \(value)")))
        }
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL)
        await restored.waitUntilLoaded()

        #expect(restored.isShowingHistoryPreview)
        #expect(restored.historyItems.map(\.content) == (2...9).reversed().map { .text("history \($0)") })

        restored.loadFullHistory()
        await restored.waitUntilLoaded()

        #expect(!restored.isShowingHistoryPreview)
        #expect(restored.historyItems.map(\.content) == (0...9).reversed().map { .text("history \($0)") })
    }

    @Test
    func historyCanJumpToAPageByItsOneBasedNumber() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await store.waitUntilLoaded()

        #expect(store.record(.text("oldest value")))
        #expect(store.record(.text("middle value")))
        #expect(store.record(.text("latest value")))
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await restored.waitUntilLoaded()
        restored.loadPage(number: 2)
        await restored.waitUntilLoaded()

        #expect(restored.currentPage == 1)
        #expect(restored.items.map(\.content) == [.text("oldest value")])

        restored.loadPage(number: 0)
        restored.loadPage(number: 3)

        #expect(restored.currentPage == 1)
    }

    @Test
    func categoryFilterAppliesToPaginationAndTotalCount() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await store.waitUntilLoaded()

        #expect(store.record(.image(Data([1, 2, 3]))))
        #expect(store.record(.text("文本一")))
        #expect(store.record(.image(Data([4, 5, 6]))))
        #expect(store.record(.text("文本二")))
        #expect(store.record(.image(Data([7, 8, 9]))))
        store.flushPendingChanges()

        let allItems = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await allItems.waitUntilLoaded()
        #expect(allItems.totalItemCount == 5)
        #expect(allItems.items.count == 2)
        #expect(allItems.categoryCounts[.image] == 3)
        #expect(allItems.categoryCounts[.text] == 2)

        allItems.updateQuery(scope: .all, searchText: "", category: .image)
        await allItems.waitUntilLoaded()
        #expect(allItems.totalItemCount == 3)
        #expect(allItems.items.count == 2)
        #expect(allItems.items.allSatisfy { $0.category == .image })
        #expect(allItems.categoryCounts[.text] == 2)

        allItems.loadNextPage()
        await allItems.waitUntilLoaded()
        #expect(allItems.items.count == 1)
        #expect(allItems.items.first?.category == .image)

        allItems.updateQuery(scope: .all, searchText: "", category: .text)
        await allItems.waitUntilLoaded()
        #expect(allItems.totalItemCount == 2)
        #expect(allItems.items.allSatisfy { $0.category == .text })

        allItems.updateQuery(scope: .all, searchText: "图片", category: .image)
        await allItems.waitUntilLoaded()
        #expect(allItems.totalItemCount == 3)
        #expect(allItems.items.allSatisfy { $0.category == .image })
    }

    @Test
    func categoryFilterDistinguishesFileTypes() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let imageURL = directory.appendingPathComponent("image.png")
        let videoURL = directory.appendingPathComponent("video.mp4")
        let documentURL = directory.appendingPathComponent("document.txt")
        try Data([0]).write(to: imageURL)
        try Data([1]).write(to: videoURL)
        try Data([2]).write(to: documentURL)
        let imageContent = try ClipboardHistoryContent.file(at: imageURL)
        let videoContent = try ClipboardHistoryContent.file(at: videoURL)
        let documentContent = try ClipboardHistoryContent.file(at: documentURL)

        let store = ClipboardHistoryStore(storageURL: storageURL, pageSize: 1)
        await store.waitUntilLoaded()
        #expect(store.record(imageContent))
        #expect(store.record(videoContent))
        #expect(store.record(documentContent))
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL, pageSize: 1)
        await restored.waitUntilLoaded()
        #expect(restored.categoryCounts[.image] == 1)
        #expect(restored.categoryCounts[.video] == 1)
        #expect(restored.categoryCounts[.document] == 1)

        restored.updateQuery(scope: .all, searchText: "", category: .video)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 1)
        #expect(restored.items.first?.content == videoContent)

        restored.updateQuery(scope: .all, searchText: "", category: .image)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 1)
        #expect(restored.items.first?.content == imageContent)

        restored.updateQuery(scope: .all, searchText: "", category: .document)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 1)
        #expect(restored.items.first?.content == documentContent)
    }

    @Test
    func recordingRespectsActiveCategoryFilter() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardHistoryStore(
            storageURL: directory.appendingPathComponent("clipboard-history.sqlite")
        )
        await store.waitUntilLoaded()

        store.updateQuery(scope: .all, searchText: "", category: .image)
        await store.waitUntilLoaded()
        #expect(store.record(.text("不应显示")))
        #expect(store.items.isEmpty)
        #expect(store.record(.image(Data([1]))))
        #expect(store.items.map(\.content) == [.image(Data([1]))])
    }

    @Test
    func urlCategoryRecognizesCompleteHTTPAndHTTPSLinks() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardHistoryStore(
            storageURL: directory.appendingPathComponent("clipboard-history.sqlite")
        )
        await store.waitUntilLoaded()

        #expect(store.record(.text("https://example.com")))
        #expect(store.record(.text("http://github.com/user/repo")))
        #expect(store.record(.text("普通文本")))
        #expect(store.record(.text("包含链接 https://example.com 的文本")))
        #expect(store.record(.text("https://example.com/path?query=value#fragment")))
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(
            storageURL: directory.appendingPathComponent("clipboard-history.sqlite")
        )
        await restored.waitUntilLoaded()

        let urlItems = restored.items.filter { $0.category == .url }
        let textItems = restored.items.filter { $0.category == .text }

        #expect(urlItems.count == 3)
        #expect(urlItems.contains { $0.content == .text("https://example.com") })
        #expect(urlItems.contains { $0.content == .text("http://github.com/user/repo") })
        #expect(urlItems.contains { $0.content == .text("https://example.com/path?query=value#fragment") })

        #expect(textItems.count == 2)
        #expect(textItems.contains { $0.content == .text("普通文本") })
        #expect(textItems.contains { $0.content == .text("包含链接 https://example.com 的文本") })
    }

    @Test
    func urlCategoryAcceptsNormalizedHTTPLinks() {
        #expect(FileShelfCategory.url.rawValue == "URL")
        #expect(FileShelfCategory.clipboardCases.contains(.url))
        #expect(!FileShelfCategory.fileShelfCases.contains(.url))
        #expect(FileShelfCategory.fileShelfCases.contains(.document))
        #expect(!FileShelfCategory.fileShelfCases.contains(.text))
        #expect(
            ClipboardHistoryItem(content: .text("  HTTPS://Example.com/中文路径  ")).category == .url
        )
        #expect(
            ClipboardHistoryItem(content: .text("https://example.com/path with spaces")).category == .text
        )
        #expect(ClipboardHistoryItem(content: .text("www.example.com")).category == .text)
        #expect(ClipboardHistoryItem(content: .text("ftp://example.com")).category == .text)
    }

    @Test
    func urlCategoryFilterWorksWithPaginationAndCounts() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await store.waitUntilLoaded()

        #expect(store.record(.text("https://example.com")))
        #expect(store.record(.text("普通文档")))
        #expect(store.record(.text("http://github.com")))
        #expect(store.record(.image(Data([1, 2, 3]))))
        #expect(store.record(.text("https://apple.com")))
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL, pageSize: 2)
        await restored.waitUntilLoaded()
        #expect(restored.categoryCounts[.url] == 3)
        #expect(restored.categoryCounts[.text] == 1)
        #expect(restored.categoryCounts[.image] == 1)

        restored.updateQuery(scope: .all, searchText: "", category: .url)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 3)
        #expect(restored.items.count == 2)
        #expect(restored.items.allSatisfy { $0.category == .url })

        restored.loadNextPage()
        await restored.waitUntilLoaded()
        #expect(restored.items.count == 1)
        #expect(restored.items.first?.category == .url)

        restored.updateQuery(scope: .all, searchText: "github", category: .url)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 1)
        #expect(restored.items.map(\.content) == [.text("http://github.com")])
    }

    @Test
    func pathCategoryFiltersPlainFilePaths() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let pathRawValue = "路径"
        #expect(FileShelfCategory.allCases.contains { $0.rawValue == pathRawValue })
        guard let pathCategory = FileShelfCategory(rawValue: pathRawValue) else { return }

        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()
        #expect(store.record(.text("/Users/example/Documents/report.pdf")))
        #expect(store.record(.text("file:///Users/example/Documents/archive.zip")))
        #expect(store.record(.text("普通文本")))
        store.flushPendingChanges()

        let restored = ClipboardHistoryStore(storageURL: storageURL)
        await restored.waitUntilLoaded()
        #expect(restored.categoryCounts[pathCategory] == 2)
        #expect(
            ClipboardHistoryItem(content: .text("/Users/example/Documents/report.pdf")).category
                == pathCategory
        )
        #expect(
            ClipboardHistoryItem(content: .text("file:///Users/example/Documents/archive.zip")).category
                == pathCategory
        )

        restored.updateQuery(scope: .all, searchText: "", category: pathCategory)
        await restored.waitUntilLoaded()
        #expect(restored.totalItemCount == 2)
        #expect(restored.items.allSatisfy { $0.category == pathCategory })
    }

    @Test
    func legacyDocumentTextIsReclassifiedAsURLOnMigration() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")

        try executeSQL(
            """
            CREATE TABLE clipboard_history (
                id TEXT PRIMARY KEY NOT NULL,
                content_type INTEGER NOT NULL,
                text_value TEXT,
                image_data BLOB,
                last_copied_at REAL NOT NULL,
                is_pinned INTEGER NOT NULL,
                file_url TEXT,
                file_display_name TEXT,
                file_bookmark BLOB,
                content_category TEXT
            );
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned, content_category)
            VALUES ('\(UUID().uuidString)', 0, '  HTTPS://Example.com/中文路径  ', NULL, 1000.0, 0, '文档');
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned, content_category)
            VALUES ('\(UUID().uuidString)', 0, '普通文本', NULL, 900.0, 0, '文档');
            """,
            at: storageURL
        )

        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()
        #expect(store.errorDescription == nil)
        #expect(store.categoryCounts[.url] == 1)
        #expect(store.categoryCounts[.text] == 1)

        store.updateQuery(scope: .all, searchText: "", category: .url)
        await store.waitUntilLoaded()
        #expect(store.totalItemCount == 1)
        #expect(store.items.map(\.content) == [.text("  HTTPS://Example.com/中文路径  ")])

        store.updateQuery(scope: .all, searchText: "", category: .text)
        await store.waitUntilLoaded()
        #expect(store.totalItemCount == 1)
        #expect(store.items.map(\.content) == [.text("普通文本")])
    }

    @Test
    func legacyTextPathsAreReclassifiedOnMigration() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let pathRawValue = "路径"
        #expect(FileShelfCategory.allCases.contains { $0.rawValue == pathRawValue })
        guard let pathCategory = FileShelfCategory(rawValue: pathRawValue) else { return }

        try executeSQL(
            """
            CREATE TABLE clipboard_history (
                id TEXT PRIMARY KEY NOT NULL,
                content_type INTEGER NOT NULL,
                text_value TEXT,
                image_data BLOB,
                last_copied_at REAL NOT NULL,
                is_pinned INTEGER NOT NULL,
                file_url TEXT,
                file_display_name TEXT,
                file_bookmark BLOB,
                content_category TEXT
            );
            PRAGMA user_version = 2;
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned, content_category)
            VALUES ('\(UUID().uuidString)', 0, '/Users/example/Documents/report.pdf', NULL, 1000.0, 0, '文本');
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned, content_category)
            VALUES ('\(UUID().uuidString)', 0, 'https://legacy.example/file', NULL, 950.0, 0, '文本');
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned, content_category)
            VALUES ('\(UUID().uuidString)', 0, '普通文本', NULL, 900.0, 0, '文本');
            """,
            at: storageURL
        )

        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()
        #expect(store.errorDescription == nil)
        #expect(store.categoryCounts[pathCategory] == 1)
        #expect(store.categoryCounts[.url] == 1)
        #expect(store.categoryCounts[.text] == 1)

        store.updateQuery(scope: .all, searchText: "", category: pathCategory)
        await store.waitUntilLoaded()
        #expect(store.totalItemCount == 1)
        #expect(store.items.map(\.content) == [.text("/Users/example/Documents/report.pdf")])
    }

    @Test
    func staleDocumentTextRowsAreReclassifiedAfterCategorySchemaUpgrade() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("clipboard-history.sqlite")

        try executeSQL(
            """
            CREATE TABLE clipboard_history (
                id TEXT PRIMARY KEY NOT NULL,
                content_type INTEGER NOT NULL,
                text_value TEXT,
                image_data BLOB,
                last_copied_at REAL NOT NULL,
                is_pinned INTEGER NOT NULL,
                file_url TEXT,
                file_display_name TEXT,
                file_bookmark BLOB,
                content_category TEXT
            );
            PRAGMA user_version = 3;
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned, content_category)
            VALUES ('\(UUID().uuidString)', 0, '旧文档文本一', NULL, 1000.0, 0, '文档');
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned, content_category)
            VALUES ('\(UUID().uuidString)', 0, '旧文档文本二', NULL, 900.0, 0, '文档');
            INSERT INTO clipboard_history (id, content_type, text_value, image_data, last_copied_at, is_pinned, content_category)
            VALUES ('\(UUID().uuidString)', 0, 'https://legacy.example', NULL, 800.0, 0, '文档');
            """,
            at: storageURL
        )

        let store = ClipboardHistoryStore(storageURL: storageURL)
        await store.waitUntilLoaded()
        #expect(store.categoryCounts[.document, default: 0] == 0)
        #expect(store.categoryCounts[.text] == 2)
        #expect(store.categoryCounts[.url] == 1)

        store.updateQuery(scope: .all, searchText: "", category: .document)
        await store.waitUntilLoaded()
        #expect(store.totalItemCount == 0)
        #expect(store.items.isEmpty)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw PersistenceWaitTimeout()
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

private struct PersistenceWaitTimeout: Error {}
