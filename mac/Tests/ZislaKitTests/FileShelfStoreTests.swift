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

    @Test(arguments: [false, true])
    func failedIndexDecodingRejectsWritesAndPreservesManagedFiles(incompatibleFormat: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let original = FileShelfStore(storageURL: storage)
        try #require(original.add(payloads: [.text("keep the saved text")]) == 1)
        let savedItems = original.items
        let savedJSON = try Data(contentsOf: storage)
        let unreadableJSON = try incompatibleFormat
            ? JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "items": JSONSerialization.jsonObject(with: savedJSON)])
            : Data(savedJSON.dropLast())
        try unreadableJSON.write(to: storage)

        let store = FileShelfStore(storageURL: storage)
        #expect(store.items.isEmpty)
        #expect(store.errorDescription != nil)
        let external = directory.appendingPathComponent("external.txt")
        try Data("keep the external file".utf8).write(to: external)
        #expect(store.add([external]) == 0)
        #expect(store.errorDescription != nil)
        #expect(try Data(contentsOf: storage) == unreadableJSON)
        #expect(store.add(payloads: [.text("cannot replace old entries")]) == 0)
        #expect(store.addContextNote("cannot save a note", location: .desktop(displayID: "test", displayName: "Test")) == nil)
        #expect(store.errorDescription != nil)
        #expect(store.items.isEmpty)
        #expect(try Data(contentsOf: storage) == unreadableJSON)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.managedDirectory.path) == savedItems.map { $0.id.uuidString })
        #expect(try String(contentsOf: savedItems[0].url, encoding: .utf8) == "keep the saved text")

        store.remove(id: savedItems[0].id)
        #expect(store.errorDescription != nil)
        #expect(try Data(contentsOf: storage) == unreadableJSON)
        store.removeAll()
        #expect(store.errorDescription != nil)
        #expect(try Data(contentsOf: storage) == unreadableJSON)
        #expect(FileManager.default.fileExists(atPath: savedItems[0].url.path))

        try savedJSON.write(to: storage)
        #expect(store.add([external]) == 0)
        #expect(store.errorDescription != nil)
        #expect(try Data(contentsOf: storage) == savedJSON)
        let recovered = FileShelfStore(storageURL: storage)
        #expect(recovered.errorDescription == nil)
        #expect(recovered.items == savedItems)
        #expect(recovered.add([external]) == 1)
        #expect(FileShelfStore(storageURL: storage).items == recovered.items)
        recovered.removeAll()
        #expect(!FileManager.default.fileExists(atPath: savedItems[0].url.path))
        #expect(try String(contentsOf: external, encoding: .utf8) == "keep the external file")
    }

    @Test
    func indexReadFailureIsReportedAndCannotWriteAfterThePathBecomesReadable() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let original = FileShelfStore(storageURL: storage)
        try #require(original.add(payloads: [.text("saved before read failure")]) == 1)
        let savedItems = original.items
        let savedJSON = try Data(contentsOf: storage)
        try FileManager.default.removeItem(at: storage)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
        let retained = storage.appendingPathComponent("retained.json")
        try savedJSON.write(to: retained)

        let store = FileShelfStore(storageURL: storage)
        #expect(store.errorDescription != nil)
        #expect(store.items.isEmpty)
        #expect(store.add(payloads: [.text("cannot commit")]) == 0)
        #expect(try Data(contentsOf: retained) == savedJSON)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.managedDirectory.path) == savedItems.map { $0.id.uuidString })

        try FileManager.default.removeItem(at: storage)
        try savedJSON.write(to: storage)
        #expect(store.add(payloads: [.text("must reload before writing")]) == 0)
        store.removeAll()
        #expect(store.errorDescription != nil)
        #expect(try Data(contentsOf: storage) == savedJSON)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.managedDirectory.path) == savedItems.map { $0.id.uuidString })
        let recovered = FileShelfStore(storageURL: storage)
        #expect(recovered.items == savedItems)
        #expect(recovered.errorDescription == nil)
        #expect(recovered.add(payloads: [.text("saved after reopening")]) == 1)
        #expect(FileShelfStore(storageURL: storage).items == recovered.items)
    }

    @Test
    func missingAndEmptyIndexesRemainWritable() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let fresh = FileShelfStore(storageURL: storage)
        #expect(fresh.items.isEmpty)
        #expect(fresh.errorDescription == nil)
        fresh.removeAll()
        #expect(fresh.errorDescription == nil)
        #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: storage)) as? [String] == [])
        let empty = FileShelfStore(storageURL: storage)
        #expect(empty.errorDescription == nil)
        #expect(empty.add(payloads: [.text("first entry")]) == 1)
        #expect(FileShelfStore(storageURL: storage).items == empty.items)
    }

    @Test
    func truncatedIndexCorpusPreservesBytesAndCreatesNoNewManagedFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let original = FileShelfStore(storageURL: storage)
        try #require(original.add(payloads: [.text("recoverable original")]) == 1)
        let savedJSON = try Data(contentsOf: storage)
        for length in [0, 1, savedJSON.count / 2, savedJSON.count - 1] {
            let truncated = Data(savedJSON.prefix(length))
            try truncated.write(to: storage)
            let store = FileShelfStore(storageURL: storage)
            #expect(store.errorDescription != nil)
            #expect(store.add(payloads: [.text("must not erase a truncated index")]) == 0)
            store.removeAll()
            #expect(try Data(contentsOf: storage) == truncated)
            #expect(store.items.isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: store.managedDirectory.path) == original.items.map { $0.id.uuidString })
        }
    }

    @Test
    func unchangedIndexKeepsBytesModificationTimeAndRecordOrder() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let ids = (0..<3).map { _ in UUID() }
        let records = ids.enumerated().map { index, id in
            ["id": id.uuidString, "bookmarkData": "", "addedAt": index,
             "url": directory.appendingPathComponent("file-\(index).txt").absoluteString] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: records, options: .prettyPrinted)
        try data.write(to: storage)
        let modifiedAt = Date(timeIntervalSince1970: 1234)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: storage.path)

        let store = FileShelfStore(storageURL: storage)
        #expect(store.items.map(\.id) == ids)
        #expect(store.errorDescription == nil)
        #expect(try Data(contentsOf: storage) == data)
        #expect(try FileManager.default.attributesOfItem(atPath: storage.path)[.modificationDate] as? Date == modifiedAt)
    }

    @Test(arguments: [false, true])
    func changedIndexRewritesOnlyRetainedRecordsAndKeepsTheirOrder(discardUnresolvableRecord: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let ids = (0..<3).map { _ in UUID() }
        let urls = (0..<3).map { directory.appendingPathComponent("file-\($0).txt") }
        var records = ids.enumerated().map { index, id in
            ["id": id.uuidString, "bookmarkData": "", "addedAt": index, "url": urls[index].absoluteString] as [String: Any]
        }
        if discardUnresolvableRecord {
            records[1].removeValue(forKey: "url")
        } else {
            records[1]["url"] = directory.appendingPathComponent("nested/../file-1.txt").absoluteString
        }
        let data = try JSONSerialization.data(withJSONObject: records)
        try data.write(to: storage)

        let store = FileShelfStore(storageURL: storage)
        let retained = discardUnresolvableRecord ? [0, 2] : [0, 1, 2]
        #expect(store.items.map(\.id) == retained.map { ids[$0] })
        #expect(store.items.map(\.url) == retained.map { urls[$0].standardizedFileURL })
        #expect(store.errorDescription == nil)
        let rewritten = try Data(contentsOf: storage)
        #expect(rewritten != data)
        let saved = try #require(JSONSerialization.jsonObject(with: rewritten) as? [[String: Any]])
        #expect(saved.compactMap { $0["id"] as? String } == retained.map { ids[$0].uuidString })
        #expect(FileShelfStore(storageURL: storage).items == store.items)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZISLA_FILE_SHELF_PERFORMANCE"] == "1"))
    func largeIndexLoadAndWriteMeasurements() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let file = directory.appendingPathComponent("existing.txt")
        try Data("fixture".utf8).write(to: file)
        let original = FileShelfStore(storageURL: storage)
        try #require(original.add([file]) == 1)
        let template = try #require((JSONSerialization.jsonObject(with: Data(contentsOf: storage)) as? [[String: Any]])?.first)
        let clock = ContinuousClock()
        for count in [1_000, 2_000, 4_000, 8_000] {
            let records = (0..<count).map { index in
                var record = template
                record["id"] = UUID().uuidString
                record["shelfOrder"] = index
                return record
            }
            let data = try JSONSerialization.data(withJSONObject: records)
            try data.write(to: storage)
            let start = clock.now
            let store = FileShelfStore(storageURL: storage)
            let loadDuration = start.duration(to: clock.now)
            #expect(store.items.count == count)
            #expect(store.errorDescription == nil)
            #expect(try Data(contentsOf: storage) == data)
            let writeStart = clock.now
            store.remove(id: UUID())
            let writeDuration = writeStart.duration(to: clock.now)
            #expect(store.items.count == count)
            #expect(store.errorDescription == nil)
            let savedRecords = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: storage)) as? [[String: Any]])
            #expect(savedRecords.compactMap { $0["id"] as? String } == records.compactMap { $0["id"] as? String })
            print("FileShelf performance: count=\(count), bytes=\(data.count), load=\(loadDuration), write=\(writeDuration)")
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-file-shelf-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
