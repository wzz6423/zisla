import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct FileShelfStoreTests {
    @Test
    func addMultipleFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = try (0..<10).map { index in
            let url = directory.appendingPathComponent("file-\(index).txt")
            try Data().write(to: url)
            return url
        }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))

        #expect(store.add(urls) == 10)
        #expect(store.items.count == 10)
        #expect(store.items.map(\.url) == urls)
    }

    @Test
    func loadKeepsAnItemWhoseVolumeIsTemporarilyUnavailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-file-shelf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("temporarily-unavailable.txt")
        let storageURL = directory.appendingPathComponent("file-shelf.json")
        try Data("shelf item".utf8).write(to: fileURL)

        let original = FileShelfStore(storageURL: storageURL)
        #expect(original.add([fileURL]) == 1)
        let originalID = try #require(original.items.first?.id)

        try FileManager.default.removeItem(at: fileURL)

        let restored = FileShelfStore(storageURL: storageURL)
        let item = try #require(restored.items.first)
        #expect(restored.items.count == 1)
        #expect(item.id == originalID)
        #expect(item.url.standardizedFileURL == fileURL.standardizedFileURL)
    }
}
