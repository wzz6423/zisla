import Foundation
import Testing
@testable import ZislaKit

@MainActor
struct FileShelfGeneratedFileTests {
    @Test func importedOutputIsManagedDurableAndIndependentFromStaging() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stage = root.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let output = stage.appendingPathComponent("images.pdf")
        let bytes = Data("synthetic generated PDF".utf8)
        try bytes.write(to: output)
        let storage = root.appendingPathComponent("shelf.json")
        let store = FileShelfStore(storageURL: storage)
        #expect(store.importPromisedFile(at: output, from: stage) == 1)
        let item = try #require(store.items.first)
        #expect(item.isManaged && item.url != output && item.text == nil)
        #expect(item.url.lastPathComponent == "images.pdf")
        try FileManager.default.removeItem(at: stage)
        #expect(try Data(contentsOf: item.url) == bytes)
        #expect(FileShelfStore(storageURL: storage).items == [item])
        store.remove(id: item.id)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: item.url.path))
    }

    @Test(arguments: ["outside", "symlink", "remote", "missing"])
    func rejectsInvalidGeneratedSourcesWithoutChangingShelf(_ kind: String) throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stage = root.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let original = root.appendingPathComponent("original.pdf")
        try Data([1, 2, 3]).write(to: original)
        let store = FileShelfStore(storageURL: root.appendingPathComponent("shelf.json"))
        #expect(store.add([original]) == 1)
        let before = store.items
        let source: URL
        switch kind {
        case "symlink":
            source = stage.appendingPathComponent("linked.pdf")
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: original)
        case "remote": source = URL(string: "https://example.invalid/images.pdf")!
        case "missing": source = stage.appendingPathComponent("missing.pdf")
        default: source = original
        }
        #expect(store.importPromisedFile(at: source, from: stage) == 0)
        #expect(store.items == before)
        #expect(store.errorDescription != nil)
        #expect(try Data(contentsOf: original) == Data([1, 2, 3]))
    }

    @Test func failedIndexWriteRemovesItsManagedCopyAndRetainsOriginals() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stage = root.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let output = stage.appendingPathComponent("images.pdf")
        try Data([4, 5, 6]).write(to: output)
        let storage = root.appendingPathComponent("shelf.json")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
        let store = FileShelfStore(storageURL: storage)
        #expect(store.importPromisedFile(at: output, from: stage) == 0)
        #expect(store.items.isEmpty && store.errorDescription != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.managedDirectory.path).isEmpty)
        #expect(try Data(contentsOf: output) == Data([4, 5, 6]))
    }

    @Test(arguments: ["corrupt", "incompatible", "unreadable"])
    func failedIndexLoadBlocksGeneratedImportsUntilReopened(_ failure: String) throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("shelf.json")
        let original = FileShelfStore(storageURL: storage)
        try #require(original.add(payloads: [.text("saved before generated import")]) == 1)
        let savedItems = original.items
        let savedJSON = try Data(contentsOf: storage)
        let savedBytes = try savedItems.map { try Data(contentsOf: $0.url) }
        let stage = root.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let output = stage.appendingPathComponent("images.pdf")
        let outputBytes = Data("synthetic generated PDF".utf8)
        try outputBytes.write(to: output)
        let protectedURL: URL
        let protectedBytes: Data
        if failure == "unreadable" {
            try FileManager.default.removeItem(at: storage)
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
            protectedURL = storage.appendingPathComponent("retained.json")
            protectedBytes = savedJSON
        } else {
            protectedURL = storage
            protectedBytes = try failure == "corrupt" ? Data(savedJSON.dropLast())
                : JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "items": JSONSerialization.jsonObject(with: savedJSON)])
        }
        try protectedBytes.write(to: protectedURL)
        let blocked = FileShelfStore(storageURL: storage)
        let loadError = try #require(blocked.errorDescription)
        #expect(blocked.importPromisedFile(at: output, from: stage) == 0)
        #expect(blocked.items.isEmpty && blocked.errorDescription == loadError)
        #expect(try Data(contentsOf: protectedURL) == protectedBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: blocked.managedDirectory.path).sorted()
            == savedItems.map { $0.id.uuidString }.sorted())
        #expect(try savedItems.map { try Data(contentsOf: $0.url) } == savedBytes)
        #expect(try Data(contentsOf: output) == outputBytes)

        if failure == "unreadable" { try FileManager.default.removeItem(at: storage) }
        try savedJSON.write(to: storage)
        #expect(blocked.importPromisedFile(at: output, from: stage) == 0)
        #expect(blocked.items.isEmpty && blocked.errorDescription == loadError)
        #expect(try Data(contentsOf: storage) == savedJSON)
        #expect(try FileManager.default.contentsOfDirectory(atPath: blocked.managedDirectory.path).sorted()
            == savedItems.map { $0.id.uuidString }.sorted())

        let recovered = FileShelfStore(storageURL: storage)
        #expect(recovered.items == savedItems && recovered.errorDescription == nil)
        #expect(recovered.importPromisedFile(at: output, from: stage) == 1)
        let imported = try #require(recovered.items.last)
        #expect(imported.isManaged && imported.url != output && imported.url.lastPathComponent == "images.pdf")
        #expect(recovered.items.dropLast() == savedItems)
        #expect(FileShelfStore(storageURL: storage).items == recovered.items)
        try FileManager.default.removeItem(at: stage)
        #expect(try Data(contentsOf: imported.url) == outputBytes)
        #expect(try savedItems.map { try Data(contentsOf: $0.url) } == savedBytes)
    }

    @Test func accessingBookmarksResolvesRenamedFilesAndKeepsUnavailableEntries() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.png")
        try Data([7]).write(to: original)
        let store = FileShelfStore(storageURL: root.appendingPathComponent("shelf.json"))
        #expect(store.add([original]) == 1)
        let item = try #require(store.items.first)
        let renamed = root.appendingPathComponent("renamed.png")
        try FileManager.default.moveItem(at: original, to: renamed)
        let accessed = store.beginAccessing(item)
        defer { accessed.stopAccessingSecurityScopedResource() }
        #expect(accessed.standardizedFileURL == renamed.standardizedFileURL)
        #expect(try Data(contentsOf: accessed) == Data([7]))
        #expect(store.items == [item])
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-generated-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
