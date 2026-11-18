import AppKit
import Foundation
import SQLite3
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ClipboardHistorySourceAppTests {
    nonisolated private static let firstApp = ClipboardSourceApp(bundleIdentifier: "test.editor", name: "Editor")
    nonisolated private static let secondApp = ClipboardSourceApp(bundleIdentifier: "test.browser", name: "Research Tool")

    @Test(arguments: ["missing", "resolved", "unresolved", "known", "unknown", "malformed", "missingID", "emptyID", "missingName", "emptyName"])
    func captureUsesSavedSourceThenMetadataThenForeground(mode: String) {
        let pasteboard = NSPasteboard(name: .init("zisla-source-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var captured: [ClipboardHistoryItem] = []
        let monitor = ClipboardHistoryMonitor(
            pasteboard: pasteboard, pollInterval: 3600, workspaceNotificationCenter: NotificationCenter(),
            sourceAppProvider: { _ in Self.firstApp },
            sourceAppResolver: { $0 == Self.secondApp.bundleIdentifier ? Self.secondApp : nil }
        ) { content, source in
            captured.append(.init(content: content, sourceApp: source))
        }
        monitor.setEnabled(true)
        defer { monitor.setEnabled(false) }
        let content = ClipboardHistoryContent.text("synthetic copy")
        if mode == "known" || mode == "unknown" {
            #expect(ClipboardHistoryPasteboard.write(.init(content: content, sourceApp: mode == "known" ? Self.secondApp : nil), to: pasteboard))
            #expect(pasteboard.setString(Self.firstApp.bundleIdentifier, forType: ClipboardHistoryPasteboard.sourceAppType))
        } else {
            #expect(ClipboardHistoryPasteboard.write(content, to: pasteboard))
            switch mode {
            case "resolved", "unresolved":
                #expect(pasteboard.setString(mode == "resolved" ? Self.secondApp.bundleIdentifier : "test.exited", forType: ClipboardHistoryPasteboard.sourceAppType))
            case "malformed":
                #expect(pasteboard.setPropertyList(["bad"], forType: ClipboardHistoryPasteboard.sourceAppMarkerType))
            case "missingID", "emptyID", "missingName", "emptyName":
                var fields = ["bundleIdentifier": "test.marker", "name": "Marker"]
                if mode == "missingID" { fields.removeValue(forKey: "bundleIdentifier") }
                if mode == "emptyID" { fields["bundleIdentifier"] = "" }
                if mode == "missingName" { fields.removeValue(forKey: "name") }
                if mode == "emptyName" { fields["name"] = "" }
                #expect(pasteboard.setPropertyList(fields, forType: ClipboardHistoryPasteboard.sourceAppMarkerType))
            default: break
            }
        }
        monitor.pollNow()
        monitor.pollNow()
        #expect(captured.count == 1)
        #expect(captured.first?.content == content)
        let expected = ["known", "resolved"].contains(mode) ? Self.secondApp
            : (["missing", "unresolved"].contains(mode) ? Self.firstApp : nil)
        #expect(captured.first?.sourceApp == expected)
    }

    @Test
    func activationCapturesThePreviousAppBeforeTrackingTheNextAndDisableStopsCapture() {
        let pasteboard = NSPasteboard(name: .init("zisla-source-activation-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let center = NotificationCenter()
        var captured: [ClipboardHistoryItem] = []
        let monitor = ClipboardHistoryMonitor(
            pasteboard: pasteboard, pollInterval: 3600, workspaceNotificationCenter: center,
            sourceAppProvider: { notification in
                notification == nil ? Self.firstApp : notification?.userInfo?["syntheticSource"] as? ClipboardSourceApp
            }, sourceAppResolver: { _ in nil }
        ) { content, source in captured.append(.init(content: content, sourceApp: source)) }
        #expect(ClipboardHistoryPasteboard.write(.text("before enabling"), to: pasteboard))
        monitor.setEnabled(true)
        monitor.setEnabled(true)
        monitor.pollNow()
        #expect(captured.isEmpty)
        #expect(ClipboardHistoryPasteboard.write(.text("first copy"), to: pasteboard))
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: ["syntheticSource": Self.secondApp])
        #expect(captured.map(\.sourceApp) == [Self.firstApp])
        #expect(ClipboardHistoryPasteboard.write(.text("second copy"), to: pasteboard))
        monitor.pollNow()
        #expect(captured.map(\.sourceApp) == [Self.firstApp, Self.secondApp])
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(ClipboardHistoryPasteboard.write(.text("no foreground"), to: pasteboard))
        monitor.pollNow()
        #expect(captured.last?.sourceApp == nil)
        monitor.setEnabled(false)
        monitor.setEnabled(false)
        #expect(ClipboardHistoryPasteboard.write(.text("disabled copy"), to: pasteboard))
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: ["syntheticSource": Self.secondApp])
        monitor.pollNow()
        #expect(captured.count == 3)
        monitor.setEnabled(true)
        defer { monitor.setEnabled(false) }
        monitor.pollNow()
        #expect(captured.count == 3)
        #expect(ClipboardHistoryPasteboard.write(.text("enabled again"), to: pasteboard))
        monitor.pollNow()
        #expect(captured.last?.sourceApp == Self.firstApp)
    }

    @Test
    func destroyingMonitorRemovesItsApplicationObserver() {
        let pasteboard = NSPasteboard(name: .init("zisla-source-lifetime-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let center = NotificationCenter()
        let probe = ClipboardSourceProviderProbe()
        var monitor: ClipboardHistoryMonitor? = ClipboardHistoryMonitor(
            pasteboard: pasteboard, pollInterval: 3600, workspaceNotificationCenter: center,
            sourceAppProvider: { _ in probe.read() }, sourceAppResolver: { _ in nil }
        )
        monitor?.setEnabled(true)
        monitor = nil
        let reads = probe.readCount
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(probe.readCount == reads, "Destroyed monitors must release their application observer")
    }

    @Test(arguments: ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType", "org.nspasteboard.AutoGeneratedType"])
    func sourceMetadataDoesNotBypassExcludedPasteboardContent(type: String) {
        let pasteboard = NSPasteboard(name: .init("zisla-source-private-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var captures = 0
        let monitor = ClipboardHistoryMonitor(
            pasteboard: pasteboard, pollInterval: 3600, workspaceNotificationCenter: NotificationCenter(),
            sourceAppProvider: { _ in Self.firstApp }, sourceAppResolver: { _ in Self.secondApp }
        ) { _, _ in captures += 1 }
        monitor.setEnabled(true)
        defer { monitor.setEnabled(false) }
        #expect(ClipboardHistoryPasteboard.write(.text("synthetic secret"), to: pasteboard))
        #expect(pasteboard.setData(Data(), forType: .init(type)))
        #expect(pasteboard.setString(Self.secondApp.bundleIdentifier, forType: ClipboardHistoryPasteboard.sourceAppType))
        monitor.pollNow()
        #expect(captures == 0)
    }

    @Test(arguments: ["text", "image", "file"])
    func recopyingHistoryPreservesSourceThroughCaptureAndRestart(kind: String) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(name: .init("zisla-source-roundtrip-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let content = try content(kind, in: directory)
        let storage = directory.appendingPathComponent("history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storage, persistenceDelay: .seconds(60))
        await store.waitUntilLoaded()
        defer { store.flushPendingChanges() }
        let monitor = ClipboardHistoryMonitor(
            pasteboard: pasteboard, pollInterval: 3600, workspaceNotificationCenter: NotificationCenter(),
            sourceAppProvider: { _ in Self.secondApp }, sourceAppResolver: { _ in nil }
        ) { captured, source in #expect(store.record(captured, sourceApp: source)) }
        monitor.setEnabled(true)
        defer { monitor.setEnabled(false) }
        for source in [Self.firstApp, nil] {
            let item = ClipboardHistoryItem(content: content, sourceApp: source)
            #expect(ClipboardHistoryPasteboard.write(item, to: pasteboard))
            monitor.pollNow()
            store.flushPendingChanges()
            let reopened = ClipboardHistoryStore(storageURL: storage)
            await reopened.waitUntilLoaded()
            #expect(reopened.errorDescription == nil)
            #expect(reopened.totalItemCount == 1)
            #expect(reopened.items.first?.content == content)
            #expect(reopened.items.first?.sourceApp == source)
        }
    }

    @Test
    func failedHistoryWriteLeavesThePasteboardAndSourceUntouched() throws {
        let pasteboard = NSPasteboard(name: .init("zisla-source-failed-write-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let original = ClipboardHistoryItem(content: .text("retained"), sourceApp: Self.firstApp)
        #expect(ClipboardHistoryPasteboard.write(original, to: pasteboard))
        let version = pasteboard.changeCount
        let missing = ClipboardHistoryItem(content: .file(.init(
            url: URL(fileURLWithPath: "/nonexistent/zisla-source-\(UUID().uuidString)"), displayName: "Missing", bookmark: Data()
        )), sourceApp: Self.secondApp)
        #expect(!ClipboardHistoryPasteboard.write(missing, to: pasteboard))
        #expect(pasteboard.changeCount == version)
        #expect(ClipboardHistoryPasteboard.readContent(from: pasteboard) == original.content)
        #expect(ClipboardHistoryPasteboard.readSourceApp(from: pasteboard) == original.sourceApp)
    }

    @Test(arguments: ["text", "image", "file"])
    func recopyUpdatesSourceAndKeepsPinnedStatusEvenWhenTheDuplicateIsOnAnotherPage(kind: String) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("history.sqlite")
        let duplicate = ClipboardHistoryItem(content: try content(kind, in: directory), lastCopiedAt: .distantPast,
            isPinned: true, sourceApp: Self.firstApp)
        let recent = ClipboardHistoryItem(content: .text("other pinned item"), lastCopiedAt: .distantFuture, isPinned: true)
        let database = ClipboardHistoryDatabase(storageURL: storage)
        try database.flush([.upsert(duplicate, capacity: nil), .upsert(recent, capacity: nil)])
        let store = ClipboardHistoryStore(storageURL: storage, pageSize: 1, persistenceDelay: .seconds(60))
        await store.waitUntilLoaded()
        defer { store.flushPendingChanges() }
        #expect(store.items == [recent])
        #expect(store.record(duplicate.content, sourceApp: Self.secondApp))
        store.flushPendingChanges()
        let page = try await database.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 10)
        #expect(page.totalCount == 2)
        let updated = try #require(page.items.first { $0.content == duplicate.content })
        #expect(updated.sourceApp == Self.secondApp)
        #expect(updated.isPinned)
    }

    @Test
    func manuallyPinnedCopiesRetainTheirSourceAndMoveAnExistingItemToPinned() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("history.sqlite")
        let store = ClipboardHistoryStore(storageURL: storage, persistenceDelay: .seconds(60))
        await store.waitUntilLoaded()
        defer { store.flushPendingChanges() }
        #expect(store.record(.text("existing value"), sourceApp: Self.firstApp))
        #expect(store.recordPinned(.text("existing value"), sourceApp: Self.secondApp))
        #expect(store.recordPinned(.text("new pinned value"), sourceApp: Self.firstApp))
        store.flushPendingChanges()
        let reopened = ClipboardHistoryStore(storageURL: storage)
        await reopened.waitUntilLoaded()
        #expect(reopened.totalItemCount == 2)
        #expect(reopened.items.allSatisfy { $0.isPinned })
        #expect(reopened.items.first { $0.content == .text("existing value") }?.sourceApp == Self.secondApp)
        #expect(reopened.items.first { $0.content == .text("new pinned value") }?.sourceApp == Self.firstApp)
    }

    @Test(arguments: ["Research Tool", "test.browser"])
    func sourceSearchCoversTheWholeDatabaseAndOptimisticCopies(query: String) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("history.sqlite")
        let database = ClipboardHistoryDatabase(storageURL: storage)
        let matching = (0..<5).map { index in
            ClipboardHistoryItem(content: .text("body \(index)"), lastCopiedAt: Date(timeIntervalSince1970: Double(index)), sourceApp: Self.secondApp)
        }
        let pinned = ClipboardHistoryItem(content: .text("pinned body"), isPinned: true, sourceApp: Self.secondApp)
        let image = ClipboardHistoryItem(content: .image(Data([1])), sourceApp: Self.secondApp)
        let other = ClipboardHistoryItem(content: .text("recent editor"), lastCopiedAt: .distantFuture, sourceApp: Self.firstApp)
        try database.flush((matching + [pinned, image, other]).map { .upsert($0, capacity: nil) })
        let store = ClipboardHistoryStore(storageURL: storage, pageSize: 2, persistenceDelay: .seconds(60),
            now: { Date(timeIntervalSince1970: 100) })
        await store.waitUntilLoaded()
        defer { store.flushPendingChanges() }
        store.updateQuery(scope: .history, searchText: query, category: .text)
        await store.waitUntilLoaded()
        #expect(store.totalItemCount == 5)
        #expect(store.categoryCounts == [.text: 5, .image: 1])
        var ids: [UUID] = []
        for page in 1...store.pageCount {
            store.loadPage(number: page)
            await store.waitUntilLoaded()
            ids += store.items.map(\.id)
        }
        #expect(ids == matching.reversed().map(\.id))
        store.loadPage(number: 1)
        await store.waitUntilLoaded()
        #expect(store.record(.text("optimistic copy"), sourceApp: Self.secondApp))
        #expect(store.items.first?.content == .text("optimistic copy"))
        #expect(store.items.first?.sourceApp == Self.secondApp)
        #expect(store.record(.text("excluded copy"), sourceApp: Self.firstApp))
        #expect(!store.items.contains { $0.content == .text("excluded copy") })
        #expect(store.record(.text("optimistic copy"), sourceApp: Self.firstApp))
        #expect(!store.items.contains { $0.content == .text("optimistic copy") })
    }

    @Test(arguments: ["%", "_", "\\", "' OR 1=1 --"])
    func sourceSearchTreatsExternalAppNamesAsLiteralBoundText(query: String) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ClipboardHistoryDatabase(storageURL: directory.appendingPathComponent("history.sqlite"))
        let nameMatch = ClipboardHistoryItem(content: .text("first value"), sourceApp: .init(bundleIdentifier: "test.literal", name: "Name \(query)"))
        let identifierMatch = ClipboardHistoryItem(content: .text("second value"), sourceApp: .init(bundleIdentifier: "test.\(query)", name: "Other"))
        let unmatched = ClipboardHistoryItem(content: .text("not selected"), sourceApp: Self.firstApp)
        try database.flush([nameMatch, identifierMatch, unmatched].map { .upsert($0, capacity: nil) })
        let page = try await database.loadPage(scope: .all, searchText: query, category: .text, offset: 0, limit: 20)
        #expect(page.totalCount == 2)
        #expect(Set(page.items.map(\.id)) == Set([nameMatch.id, identifierMatch.id]))
        #expect(try await database.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 20).totalCount == 3)
    }

    @Test
    func optionalSourceDecodesOldItemsAndRoundTripsUnicode() throws {
        let oldItem = ClipboardHistoryItem(content: .text("legacy"), lastCopiedAt: Date(timeIntervalSince1970: 2))
        let encoded = try JSONEncoder().encode(oldItem)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "sourceApp")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(ClipboardHistoryItem.self, from: oldData) == oldItem)
        for name in ["编辑器", "Éditeur", "محرر", "👩🏽‍💻\u{0}App"] {
            let item = ClipboardHistoryItem(content: .text("copy"), sourceApp: .init(bundleIdentifier: "test.\(name)", name: name))
            #expect(try JSONDecoder().decode(ClipboardHistoryItem.self, from: JSONEncoder().encode(item)) == item)
        }
    }

    @Test(arguments: ["编辑器", "Éditeur", "محرر", "👩🏽‍💻\u{0}App"])
    func persistedSourceRetainsEveryUnicodeByte(name: String) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("history.sqlite")
        let item = ClipboardHistoryItem(content: .text("source byte round trip"), sourceApp: .init(bundleIdentifier: "test.\(name)", name: name))
        try ClipboardHistoryDatabase(storageURL: storage).flush([.upsert(item, capacity: nil)])
        let reopened = ClipboardHistoryDatabase(storageURL: storage)
        let page = try await reopened.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 20)
        #expect(page.items == [item])
    }

    @Test(arguments: ["source_app_bundle_identifier", "source_app_name"])
    func partialLegacySourceMetadataRemainsUnknown(column: String) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("history.sqlite")
        try createOldDatabase(at: storage, id: UUID(), version: 6)
        try execute("ALTER TABLE clipboard_history ADD COLUMN \(column) TEXT; UPDATE clipboard_history SET \(column) = 'partial source'", at: storage)
        let database = ClipboardHistoryDatabase(storageURL: storage)
        let page = try await database.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 20)
        #expect(page.totalCount == 1)
        #expect(page.items.first?.sourceApp == nil)
    }

    @Test(arguments: ["legacy", "current"])
    func additiveSourceMigrationPreservesUnknownHistoryAndCanBeReopened(version: String) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("history.sqlite")
        let id = UUID()
        try createOldDatabase(at: storage, id: id, version: version == "current" ? 6 : 0)
        let database = ClipboardHistoryDatabase(storageURL: storage)
        let page = try await database.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 20)
        #expect(page.totalCount == 1)
        #expect(page.items.first?.id == id)
        #expect(page.items.first?.sourceApp == nil)
        #expect(page.items.first?.isPinned == true)
        let new = ClipboardHistoryItem(content: .text("new value"), sourceApp: Self.firstApp)
        try database.flush([.upsert(new, capacity: nil)])
        let reopened = ClipboardHistoryDatabase(storageURL: storage)
        #expect(try await reopened.loadPage(scope: .all, searchText: Self.firstApp.name, category: .all, offset: 0, limit: 20).items == [new])
        #expect(try scalar("PRAGMA user_version", at: storage) == 6)
    }

    @Test
    func failedMigrationRollsBackSourceColumnsAndRetainsOldRecords() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("history.sqlite")
        try createOldDatabase(at: storage, id: UUID(), version: 0)
        let database = ClipboardHistoryDatabase(storageURL: storage, connectionObserver: { connection in
            sqlite3_set_authorizer(connection, { _, action, name, _, _, _ in
                action == SQLITE_CREATE_INDEX && name.map { String(cString: $0) } == "clipboard_history_content_lookup"
                    ? SQLITE_DENY : SQLITE_OK
            }, nil)
        })
        await #expect(throws: (any Error).self) {
            try await database.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 20)
        }
        #expect(try scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_history') WHERE name LIKE 'source_app_%'", at: storage) == 0)
        #expect(try scalar("SELECT COUNT(*) FROM clipboard_history", at: storage) == 1)
        #expect(try scalar("PRAGMA user_version", at: storage) == 0)
        let reopened = ClipboardHistoryDatabase(storageURL: storage)
        #expect(try await reopened.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 20).totalCount == 1)
    }

    @Test
    func rejectedSourceUpdateRetainsThePreviousSourceAndPinnedItemUntilRetry() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("history.sqlite")
        let database = ClipboardHistoryDatabase(storageURL: storage)
        let original = ClipboardHistoryItem(content: .text("same value"), isPinned: true, sourceApp: Self.firstApp)
        try database.flush([.upsert(original, capacity: nil)])
        try execute("CREATE TRIGGER reject_source BEFORE UPDATE OF source_app_name ON clipboard_history BEGIN SELECT RAISE(ABORT, 'injected source write failure'); END", at: storage)
        let store = ClipboardHistoryStore(storageURL: storage, persistenceDelay: .seconds(60))
        await store.waitUntilLoaded()
        defer { store.flushPendingChanges() }
        #expect(store.record(original.content, sourceApp: Self.secondApp))
        store.flushPendingChanges()
        #expect(store.errorDescription?.contains("injected source write failure") == true)
        #expect(try await database.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 10).items == [original])
        try execute("DROP TRIGGER reject_source", at: storage)
        store.flushPendingChanges()
        #expect(store.errorDescription == nil)
        let page = try await database.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 10)
        #expect(page.totalCount == 1)
        #expect(page.items.first?.sourceApp == Self.secondApp)
        #expect(page.items.first?.isPinned == true)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-source-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func content(_ kind: String, in directory: URL) throws -> ClipboardHistoryContent {
        switch kind {
        case "image":
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.setColor(.red, atX: 0, y: 0)
            return .image(try #require(bitmap.representation(using: .png, properties: [:])))
        case "file":
            let url = directory.appendingPathComponent("source.txt")
            try Data("synthetic file".utf8).write(to: url)
            return try .file(at: url)
        default: return .text("synthetic text")
        }
    }

    private func createOldDatabase(at url: URL, id: UUID, version: Int) throws {
        let columns = version == 6 ? ", file_url TEXT, file_display_name TEXT, file_bookmark BLOB, content_category TEXT, content_digest BLOB" : ""
        try execute("""
            CREATE TABLE clipboard_history (id TEXT PRIMARY KEY NOT NULL, content_type INTEGER NOT NULL,
                text_value TEXT, image_data BLOB, last_copied_at REAL NOT NULL, is_pinned INTEGER NOT NULL\(columns));
            INSERT INTO clipboard_history(id, content_type, text_value, last_copied_at, is_pinned)
                VALUES('\(id.uuidString)', 0, 'legacy value', 2, 1);
            PRAGMA user_version = \(version);
            """, at: url)
    }

    private func execute(_ sql: String, at url: URL) throws {
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw ClipboardSourceTestError()
        }
        defer { sqlite3_close(connection) }
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw ClipboardSourceTestError() }
    }

    private func scalar(_ sql: String, at url: URL) throws -> Int {
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw ClipboardSourceTestError()
        }
        defer { sqlite3_close(connection) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ClipboardSourceTestError() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw ClipboardSourceTestError() }
        return Int(sqlite3_column_int64(statement, 0))
    }
}

private final class ClipboardSourceProviderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var readCount: Int { lock.withLock { count } }
    func read() -> ClipboardSourceApp? {
        lock.withLock { count += 1 }
        return nil
    }
}

private struct ClipboardSourceTestError: Error {}
