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
}
