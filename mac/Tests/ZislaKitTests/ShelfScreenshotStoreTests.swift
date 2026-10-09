import AppKit
import Foundation
import SQLite3
import Testing
import zlib

@testable import ZislaKit

@MainActor
struct ShelfScreenshotStoreTests {
    @Test
    func databaseReopenRestoresPNGOriginalMetadataAndMixedOrderWithoutJSONDuplication() throws {
        try withDirectory { directory in
            let storage = directory.appendingPathComponent("shelf.json")
            let png = try imageData()
            let metadata = Self.metadata(width: 80, height: 40)
            let ids: [UUID] = try {
                let store = FileShelfStore(storageURL: storage)
                #expect(store.add(payloads: [.text("before")]) == 1)
                let screenshot = try store.stashScreenshot(png: png, metadata: metadata)
                #expect(store.add(payloads: [.text("after")]) == 1)
                _ = try #require(store.addContextNote("backdated note",
                    location: .desktop(displayID: "test", displayName: "Test"), addedAt: .distantPast))
                let json = try String(contentsOf: storage, encoding: .utf8)
                #expect(!json.contains(screenshot.id.uuidString))
                #expect(!json.contains("capturedAt"))
                let db = ShelfScreenshotDatabase(directory: storage.deletingPathExtension().appendingPathExtension("screenshots"))
                let record = try db.record(id: screenshot.id)
                #expect(record.metadata == metadata)
                #expect(record.png == png)
                return store.items.map(\.id)
            }()
            let restored = FileShelfStore(storageURL: storage)
            #expect(restored.items.map(\.id) == ids)
            #expect(restored.items[1].screenshotMetadata == metadata)
            #expect(try restored.screenshotData(id: ids[1]) == png)
            #expect(restored.items[1].category == .screenshot)
        }
    }

    @Test(arguments: [false, true])
    func missingOrCorruptJSONAndDeletedCachesCannotHideDatabaseScreenshots(corruptJSON: Bool) throws {
        try withDirectory { directory in
            let storage = directory.appendingPathComponent("shelf.json")
            let png = try imageData()
            let screenshot = try {
                let store = FileShelfStore(storageURL: storage)
                return try store.stashScreenshot(png: png, metadata: Self.metadata(width: 80, height: 40))
            }()
            try FileManager.default.removeItem(at: screenshot.url.deletingLastPathComponent())
            if corruptJSON { try Data("invalid JSON".utf8).write(to: storage) }
            let restored = FileShelfStore(storageURL: storage)
            #expect(restored.items.map(\.id) == [screenshot.id])
            #expect(restored.items.first?.screenshotMetadata == screenshot.screenshotMetadata)
            #expect(try restored.screenshotData(id: screenshot.id) == png)
            #expect(try Data(contentsOf: screenshot.url) == png)
            if corruptJSON { #expect(restored.errorDescription != nil) }
            #expect(permissions(screenshot.url) == 0o600)
            #expect(permissions(screenshot.url.deletingLastPathComponent()) == 0o700)
            let db = screenshot.url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("screenshots.sqlite")
            #expect(permissions(db) == 0o600)
            #expect(permissions(db.deletingLastPathComponent()) == 0o700)
        }
    }

    @Test
    func failedDatabaseOpenDoesNotDamageLegacyShelfAndCreatesNoCard() throws {
        try withDirectory { directory in
            let storage = directory.appendingPathComponent("shelf.json")
            let store = FileShelfStore(storageURL: storage)
            #expect(store.add(payloads: [.text("keep")]) == 1)
            let originalJSON = try Data(contentsOf: storage)
            let dbDirectory = storage.deletingPathExtension().appendingPathExtension("screenshots")
            try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
            try Data("invalid SQLite database".utf8).write(to: dbDirectory.appendingPathComponent("screenshots.sqlite"))
            #expect(throws: (any Error).self) {
                try store.stashScreenshot(png: imageData(), metadata: Self.metadata(width: 80, height: 40))
            }
            #expect(store.items.count == 1)
            #expect(store.errorDescription != nil)
            #expect(try Data(contentsOf: storage) == originalJSON)
            let restored = FileShelfStore(storageURL: storage)
            #expect(restored.items.count == 1)
            #expect(restored.items.first?.text == "keep")
            #expect(restored.errorDescription != nil)
        }
    }

    @Test
    func cacheRestorationFailureStillRestoresTheCardAndDatabaseContents() throws {
        try withDirectory { directory in
            let storage = directory.appendingPathComponent("shelf.json")
            let png = try imageData()
            let screenshot = try {
                let store = FileShelfStore(storageURL: storage)
                return try store.stashScreenshot(png: png, metadata: Self.metadata(width: 80, height: 40))
            }()
            let cache = screenshot.url.deletingLastPathComponent()
            try FileManager.default.removeItem(at: cache)
            try Data("blocked cache".utf8).write(to: cache)
            let restored = FileShelfStore(storageURL: storage)
            #expect(restored.items.map(\.id) == [screenshot.id])
            #expect(restored.errorDescription != nil)
            #expect(try restored.screenshotData(id: screenshot.id) == png)
            #expect(restored.items.first?.screenshotMetadata == screenshot.screenshotMetadata)
            #expect(throws: (any Error).self) { try restored.screenshotFileURL(id: screenshot.id) }
            try FileManager.default.removeItem(at: cache)
            #expect(try Data(contentsOf: restored.screenshotFileURL(id: screenshot.id)) == png)
        }
    }

    @Test
    func blockedCacheStillCommitsScreenshotAndRecoversAfterReopen() throws {
        try withDirectory { directory in
            let storage = directory.appendingPathComponent("shelf.json")
            let png = try imageData()
            let metadata = Self.metadata(width: 80, height: 40)
            let screenshots = try {
                let store = FileShelfStore(storageURL: storage)
                let first = try store.stashScreenshot(png: png, metadata: metadata)
                let cache = first.url.deletingLastPathComponent()
                try FileManager.default.removeItem(at: cache)
                try Data("blocked cache".utf8).write(to: cache)
                let second = try store.stashScreenshot(png: png, metadata: metadata)
                #expect(store.items.map(\.id) == [first.id, second.id])
                #expect(second.screenshotMetadata == metadata)
                #expect(second.category == .screenshot)
                #expect(store.errorDescription != nil)
                #expect(!FileManager.default.fileExists(atPath: second.url.path))
                #expect(try store.screenshotData(id: second.id) == png)
                #expect(throws: (any Error).self) { try store.screenshotFileURL(id: second.id) }
                return [first, second]
            }()
            let restored = FileShelfStore(storageURL: storage)
            #expect(restored.items.map(\.id) == screenshots.map(\.id))
            #expect(restored.items.map(\.screenshotMetadata) == [metadata, metadata])
            #expect(restored.errorDescription != nil)
            #expect(try restored.screenshotData(id: screenshots[1].id) == png)
            try FileManager.default.removeItem(at: screenshots[0].url.deletingLastPathComponent())
            for screenshot in screenshots {
                #expect(try Data(contentsOf: restored.screenshotFileURL(id: screenshot.id)) == png)
            }
            #expect(FileShelfStore(storageURL: storage).items == restored.items)
        }
    }

    @Test
    func metadataListingRestoresOrderWithoutReadingUnreadablePNG() throws {
        try withDirectory { directory in
            let png = try imageData()
            let metadata = Self.metadata(width: 80, height: 40)
            let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
            let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
            try {
                let database = ShelfScreenshotDatabase(directory: directory)
                try database.insert(ShelfScreenshotRecord(id: secondID, addedAt: .distantPast,
                    shelfOrder: 7, metadata: metadata, png: png))
                try database.insert(ShelfScreenshotRecord(id: firstID, addedAt: .distantFuture,
                    shelfOrder: 7, metadata: metadata, png: png))
            }()
            var connection: OpaquePointer?
            #expect(sqlite3_open(directory.appendingPathComponent("screenshots.sqlite").path, &connection) == SQLITE_OK)
            defer { sqlite3_close(connection) }
            #expect(sqlite3_exec(connection,
                "UPDATE screenshots SET png = X'' WHERE id = '\(firstID.uuidString)'", nil, nil, nil) == SQLITE_OK)
            let database = ShelfScreenshotDatabase(directory: directory)
            let records = try database.records()
            #expect(records.map(\.id) == [firstID, secondID])
            #expect(records.map(\.addedAt) == [.distantFuture, .distantPast])
            #expect(records.map(\.shelfOrder) == [7, 7])
            #expect(records.map(\.metadata) == [metadata, metadata])
            #expect(try database.record(id: secondID).png == png)
            #expect(throws: (any Error).self) { try database.record(id: firstID) }
            #expect(throws: CocoaError(.fileReadNoSuchFile)) { try database.record(id: UUID()) }
        }
    }

    @Test
    func reopeningPreservesExistingCacheContentsAndModificationDates() throws {
        try withDirectory { directory in
            let storage = directory.appendingPathComponent("shelf.json")
            let png = try imageData()
            let cachedAt = Date(timeIntervalSince1970: 1234)
            let screenshots = try {
                let store = FileShelfStore(storageURL: storage)
                return try (0..<2).map { _ in
                    let item = try store.stashScreenshot(png: png, metadata: Self.metadata(width: 80, height: 40))
                    try FileManager.default.setAttributes([.modificationDate: cachedAt], ofItemAtPath: item.url.path)
                    return item
                }
            }()
            do {
                var connection: OpaquePointer?
                let databaseURL = screenshots[0].url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("screenshots.sqlite")
                #expect(sqlite3_open(databaseURL.path, &connection) == SQLITE_OK)
                defer { sqlite3_close(connection) }
                #expect(sqlite3_exec(connection,
                    "UPDATE screenshots SET png = X'' WHERE id = '\(screenshots[0].id.uuidString)'", nil, nil, nil) == SQLITE_OK)
                #expect(sqlite3_changes(connection) == 1)
            }
            let restored = FileShelfStore(storageURL: storage)
            #expect(restored.items.map(\.id) == screenshots.map(\.id))
            #expect(restored.errorDescription == nil)
            #expect(throws: (any Error).self) { try restored.screenshotData(id: screenshots[0].id) }
            for (screenshot, item) in zip(screenshots, restored.items) {
                #expect(item.url == screenshot.url)
                #expect(item.screenshotMetadata == screenshot.screenshotMetadata)
                #expect(abs(item.addedAt.timeIntervalSince(screenshot.addedAt)) < 0.000_001)
                #expect(try Data(contentsOf: screenshot.url) == png)
                #expect(try FileManager.default.attributesOfItem(atPath: screenshot.url.path)[.modificationDate] as? Date == cachedAt)
            }
        }
    }

    @Test
    func databaseReopenAddsOrderingIndexToExistingScreenshots() throws {
        try withDirectory { directory in
            let id = UUID()
            try {
                let database = ShelfScreenshotDatabase(directory: directory)
                try database.insert(ShelfScreenshotRecord(id: id, addedAt: .distantPast, shelfOrder: 0,
                    metadata: Self.metadata(width: 80, height: 40), png: imageData()))
            }()
            do {
                var connection: OpaquePointer?
                #expect(sqlite3_open(directory.appendingPathComponent("screenshots.sqlite").path, &connection) == SQLITE_OK)
                defer { sqlite3_close(connection) }
                #expect(sqlite3_exec(connection, "DROP INDEX IF EXISTS screenshots_shelf_order", nil, nil, nil) == SQLITE_OK)
            }
            let reopened = ShelfScreenshotDatabase(directory: directory)
            #expect(try reopened.records().map(\.id) == [id])
            var connection: OpaquePointer?
            #expect(sqlite3_open(directory.appendingPathComponent("screenshots.sqlite").path, &connection) == SQLITE_OK)
            defer { sqlite3_close(connection) }
            var query: OpaquePointer?
            #expect(sqlite3_prepare_v2(connection,
                "EXPLAIN QUERY PLAN SELECT id, added_at, shelf_order, metadata FROM screenshots ORDER BY shelf_order, id",
                -1, &query, nil) == SQLITE_OK)
            defer { sqlite3_finalize(query) }
            var details: [String] = []
            var result = sqlite3_step(query)
            while result == SQLITE_ROW {
                details.append(String(cString: try #require(sqlite3_column_text(query, 3))))
                result = sqlite3_step(query)
            }
            #expect(result == SQLITE_DONE)
            #expect(details.contains { $0.contains("USING INDEX screenshots_shelf_order") })
            #expect(!details.contains { $0.contains("TEMP B-TREE") })
        }
    }

    @Test
    func sqliteWriteAndDeleteFailuresKeepCommittedStateAndRecover() throws {
        try withDirectory { directory in
            let storage = directory.appendingPathComponent("shelf.json")
            let store = FileShelfStore(storageURL: storage)
            let png = try imageData()
            let metadata = Self.metadata(width: 80, height: 40)
            let first = try store.stashScreenshot(png: png, metadata: metadata)
            let databaseURL = first.url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("screenshots.sqlite")
            var database: OpaquePointer?
            #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
            defer { sqlite3_close(database) }
            #expect(sqlite3_exec(database, """
                CREATE TRIGGER reject_insert BEFORE INSERT ON screenshots BEGIN SELECT RAISE(ABORT, 'test insert denied'); END;
                CREATE TRIGGER reject_delete BEFORE DELETE ON screenshots BEGIN SELECT RAISE(ABORT, 'test delete denied'); END;
                """, nil, nil, nil) == SQLITE_OK)
            #expect(throws: (any Error).self) { try store.stashScreenshot(png: png, metadata: metadata) }
            #expect(store.items.map(\.id) == [first.id])
            #expect(store.errorDescription?.contains("test insert denied") == true)
            #expect(try FileManager.default.contentsOfDirectory(atPath: first.url.deletingLastPathComponent().path) == [first.url.lastPathComponent])
            store.remove(id: first.id)
            #expect(store.items.map(\.id) == [first.id])
            #expect(store.errorDescription?.contains("test delete denied") == true)
            #expect(try store.screenshotData(id: first.id) == png)
            #expect(sqlite3_exec(database, "DROP TRIGGER reject_insert; DROP TRIGGER reject_delete;", nil, nil, nil) == SQLITE_OK)
            let second = try store.stashScreenshot(png: png, metadata: metadata)
            store.remove(id: first.id)
            #expect(store.items.map(\.id) == [second.id])
            #expect(!FileManager.default.fileExists(atPath: first.url.path))
            let restored = FileShelfStore(storageURL: storage)
            #expect(restored.items.map(\.id) == [second.id])
            restored.removeAll()
            #expect(restored.items.isEmpty)
            #expect(FileShelfStore(storageURL: storage).items.isEmpty)
        }
    }

    @Test
    func copiedScreenshotsUseDatabasePNGAndTIFFWhileMixedFilesAndTextKeepTheirTypes() throws {
        try withDirectory { directory in
            let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
            let png = try imageData()
            let screenshot = try store.stashScreenshot(png: png, metadata: Self.metadata(width: 80, height: 40))
            let file = directory.appendingPathComponent("ordinary.png")
            try png.write(to: file)
            #expect(store.add([file]) == 1)
            #expect(store.add(payloads: [.text("plain text")]) == 1)
            try FileManager.default.removeItem(at: screenshot.url)
            let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            #expect(FileShelfPasteboard.writeItems(store.items, screenshotData: [screenshot.id: try store.screenshotData(id: screenshot.id)], to: pasteboard))
            let values = try #require(pasteboard.pasteboardItems)
            #expect(values.count == 3)
            #expect(values[0].data(forType: .png) == png)
            #expect(values[0].data(forType: .tiff) != nil)
            #expect(values[0].string(forType: .fileURL) == nil)
            #expect(values[1].string(forType: .fileURL) == file.absoluteString)
            #expect(values[2].string(forType: .string) == "plain text")
            #expect(NSImage(pasteboard: pasteboard) != nil)
            #expect(try Data(contentsOf: store.screenshotFileURL(id: screenshot.id)) == png)
        }
    }

    @Test
    func cacheCleanupFailuresAreVisibleAndOrphansAreRetriedOnReopen() throws {
        try withDirectory { directory in
            let storage = directory.appendingPathComponent("shelf.json")
            let store = FileShelfStore(storageURL: storage)
            let screenshot = try store.stashScreenshot(png: imageData(), metadata: Self.metadata(width: 80, height: 40))
            let cache = screenshot.url.deletingLastPathComponent()
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: cache.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.path) }
            store.remove(id: screenshot.id)
            #expect(store.items.isEmpty)
            #expect(store.errorDescription != nil)
            #expect(FileManager.default.fileExists(atPath: screenshot.url.path))
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.path)
            let restored = FileShelfStore(storageURL: storage)
            #expect(restored.items.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: screenshot.url.path))
        }
    }

    @Test
    func screenshotValidationAcceptsEditorSizedImagesBeyondDropPixelLimitButRejectsCorruption() throws {
        try withDirectory { directory in
            let png = try imageData(width: 4001, height: 4000, noisy: true)
            #expect(png.count > FileShelfStore.maximumImageBytes)
            #expect(throws: (any Error).self) { try FileShelfStore.imageFormat(for: png) }
            let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
            let item = try store.stashScreenshot(png: png, metadata: Self.metadata(width: 4001, height: 4000))
            #expect(try store.screenshotData(id: item.id) == png)
            #expect(throws: (any Error).self) {
                try store.stashScreenshot(png: Data(png.dropLast(8)), metadata: Self.metadata(width: 4001, height: 4000))
            }
            #expect(throws: (any Error).self) {
                try store.stashScreenshot(png: png, metadata: Self.metadata(width: 1, height: 1))
            }
            #expect(store.items.count == 1)
        }
    }

    @Test
    func forgedLargeDimensionsWithAValidChunkChecksumDoNotReachImageDecoding() throws {
        var png = try imageData()
        let width: UInt32 = 6000
        let height: UInt32 = 6000
        png.replaceSubrange(16..<20, with: withUnsafeBytes(of: width.bigEndian, Array.init))
        png.replaceSubrange(20..<24, with: withUnsafeBytes(of: height.bigEndian, Array.init))
        let checksum = png.withUnsafeBytes { bytes in
            crc32(0, bytes.bindMemory(to: Bytef.self).baseAddress! + 12, 17)
        }
        png.replaceSubrange(29..<33, with: withUnsafeBytes(of: UInt32(checksum).bigEndian, Array.init))
        #expect(throws: (any Error).self) { try FileShelfStore.screenshotDimensions(png) }
    }

    private static func metadata(width: Int, height: Int) -> ShelfScreenshotMetadata {
        ShelfScreenshotMetadata(source: ScreenshotSourceSnapshot(applicationName: "Original App",
            bundleIdentifier: "test.original", processIdentifier: 12345, capturedAt: Date(timeIntervalSince1970: 1234)),
            isLongScreenshot: true, initialCaptureRect: CGRect(x: 20, y: 30, width: 40, height: 20),
            captureRect: CGRect(x: 25, y: 35, width: 40, height: 20),
            screenFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            displayIdentifier: 42, pixelWidth: width, pixelHeight: height)
    }

    private func imageData(width: Int = 80, height: Int = 40, noisy: Bool = false) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(bitmap.bitmapData)
        var random: UInt32 = 1
        func nextByte() -> UInt8 {
            random = random &* 1_664_525 &+ 1_013_904_223
            return UInt8(random >> 24)
        }
        for index in stride(from: 0, to: bitmap.bytesPerRow * height, by: 4) {
            bytes[index] = noisy ? nextByte() : 200
            bytes[index + 1] = noisy ? nextByte() : 20
            bytes[index + 2] = noisy ? nextByte() : 50
            bytes[index + 3] = 255
        }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func permissions(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? Int
    }

    private func withDirectory(_ action: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-screenshot-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try action(directory)
    }
}
