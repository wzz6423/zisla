import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import zlib
import Testing

@testable import ZislaKit

@MainActor
struct FileShelfContentTests {
    @Test
    func mixedContentSurvivesRestartAndKeepsOriginalText() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("local.txt")
        try Data("original file".utf8).write(to: file)
        let storage = directory.appendingPathComponent("shelf.json")
        let text = "  first line\nsecond line  "
        let link = "https://example.invalid/document.pdf?name=网页"
        let payloads: [TransferPasteboardPayload] = [.file(file), .text(text), .text(link)]
        let store = FileShelfStore(storageURL: storage)

        #expect(store.add(payloads: payloads) == 3)
        #expect(store.items.map(\.payload) == payloads)
        #expect(store.items.map(\.category) == [.document, .text, .url])
        #expect(try String(contentsOf: store.items[1].url, encoding: .utf8) == text)
        let webloc = try PropertyListSerialization.propertyList(from: Data(contentsOf: store.items[2].url), format: nil) as? [String: String]
        #expect(webloc?["URL"] == TransferPasteboard.webURL(from: link)?.absoluteString)
        let restored = FileShelfStore(storageURL: storage)
        #expect(restored.items == store.items)
        #expect(restored.add(payloads: payloads) == 0)
        let managed = restored.items.filter(\.isManaged).map(\.url)
        restored.removeAll()
        #expect(managed.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(try String(contentsOf: file, encoding: .utf8) == "original file")
    }

    @Test
    func failedPersistencePreservesPreviousItemsAndCleansNewManagedFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let store = FileShelfStore(storageURL: storage)
        #expect(store.add(payloads: [.text("keep me")]) == 1)
        let original = store.items
        try FileManager.default.removeItem(at: storage)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)

        #expect(store.add(payloads: [.text("cannot commit")]) == 0)
        #expect(store.items == original)
        #expect(store.errorDescription != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.managedDirectory.path) == [original[0].id.uuidString])
        store.removeAll()
        #expect(store.items == original)
        #expect(FileManager.default.fileExists(atPath: original[0].url.path))
    }

    @Test
    func forgedManagedFlagCannotDeleteExternalFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let external = directory.appendingPathComponent("user-file.txt")
        try Data("do not delete".utf8).write(to: external)
        let storage = directory.appendingPathComponent("shelf.json")
        let store = FileShelfStore(storageURL: storage)
        #expect(store.add([external]) == 1)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: storage)) as? [[String: Any]])
        json[0]["isManaged"] = true
        let unrelatedDirectory = store.managedDirectory.appendingPathComponent(store.items[0].id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unrelatedDirectory, withIntermediateDirectories: true)
        let unrelatedFile = unrelatedDirectory.appendingPathComponent("unrelated.txt")
        try Data("keep unrelated".utf8).write(to: unrelatedFile)
        try JSONSerialization.data(withJSONObject: json).write(to: storage)
        let restored = FileShelfStore(storageURL: storage)
        restored.removeAll()
        #expect(try String(contentsOf: external, encoding: .utf8) == "do not delete")
        #expect(try String(contentsOf: unrelatedFile, encoding: .utf8) == "keep unrelated")
    }

    @Test
    func legacyBookmarkRecordLoadsWithoutNewFields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("existing.txt")
        try Data().write(to: file)
        let storage = directory.appendingPathComponent("shelf.json")
        let id = UUID()
        let oldRecord: [String: Any] = ["id": id.uuidString, "url": file.absoluteString, "bookmarkData": "", "addedAt": 0]
        try JSONSerialization.data(withJSONObject: [oldRecord]).write(to: storage)
        let restored = FileShelfStore(storageURL: storage)
        #expect(restored.items.count == 1)
        #expect(restored.items[0].id == id)
        #expect(restored.items[0].payload == .file(file))
        #expect(!restored.items[0].isManaged)
        #expect(restored.errorDescription == nil)
    }

    @Test
    func emptyMissingAndRemoteFileInputsDoNotCreateManagedFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        #expect(store.add(payloads: [.text(" \n\t"), .file(URL(string: "https://example.invalid/file")!), .file(directory.appendingPathComponent("missing"))]) == 0)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.managedDirectory.path))
    }

    @Test
    func mixedPasteboardItemsPreserveOrderAndCopyOriginalPayloads() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file.txt")
        try Data().write(to: file)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let fileItem = NSPasteboardItem()
        fileItem.setString(file.absoluteString, forType: .fileURL)
        fileItem.setString("alternative file title", forType: .string)
        let textItem = NSPasteboardItem()
        textItem.setString("  selected text\n ", forType: .string)
        let linkItem = NSPasteboardItem()
        linkItem.setString("https://example.invalid/page", forType: .URL)
        linkItem.setString("Page title", forType: .string)
        #expect(pasteboard.writeObjects([fileItem, textItem, linkItem]))
        let expected: [TransferPasteboardPayload] = [.file(file), .text("  selected text\n "), .text("https://example.invalid/page")]
        #expect(TransferPasteboard.readShelfItems(from: pasteboard) == expected)
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        var added = 0
        store.receive(TransferPasteboard.readShelfDropItems(from: pasteboard)) { added = $0 }
        #expect(added == 3)
        #expect(FileShelfPasteboard.writeItems(store.items, to: pasteboard))
        #expect(TransferPasteboard.readShelfItems(from: pasteboard) == expected)
        #expect(pasteboard.pasteboardItems?[1].string(forType: .fileURL) == nil)
        #expect(pasteboard.pasteboardItems?[2].string(forType: .URL) == "https://example.invalid/page")
    }

    @Test
    func unsafeURLsRemainInertTextAndDoNotCreateWeblocFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let values = ["javascript:alert(1)", "file:///etc/passwd", "file://localhost/etc/passwd", "ftp://example.invalid/file", "data:text/html,<script>alert(1)</script>", "https://", "https://example.invalid/page extra"]
        #expect(store.add(payloads: values.map(TransferPasteboardPayload.text)) == values.count)
        #expect(store.items.allSatisfy { $0.category == .text && $0.linkURL == nil && $0.url.pathExtension == "txt" })
        #expect(store.items.map(\.text) == values.map(Optional.some))
    }

    @Test
    func seededUnicodePayloadsRoundTripWithinFixedBudget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        var seed: UInt64 = 0x51E1F
        let alphabet = Array("ab字链接🙂/\\<>$%\n\t ")
        let values = (0..<64).map { index in
            "\(index):" + String((0..<48).map { _ in
                seed = seed &* 6364136223846793005 &+ 1
                return alphabet[Int(seed % UInt64(alphabet.count))]
            })
        }
        let payloads = values.map(TransferPasteboardPayload.text)
        #expect(store.add(payloads: payloads) == 64)
        let restored = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        #expect(restored.items.map(\.payload) == payloads)
        #expect(restored.items.allSatisfy { $0.url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == store.managedDirectory.standardizedFileURL.path })
    }

    @Test
    func promisedFilesCompleteOutOfOrderWithoutDroppingMixedItems() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let first = ControlledFilePromiseReceiver(names: ["first.png", "extra.png"])
        let last = ControlledFilePromiseReceiver(names: ["last.txt"])
        var counts: [Int] = []
        let session = try FileShelfPromiseSession(store: store, items: [.promise(first), .content(.text("between")), .promise(last)], completion: { counts.append($0) })
        session.start()
        #expect(first.destination == last.destination)
        try last.deliver(name: "last.txt", data: Data("last".utf8))
        try first.deliver(name: "extra.png", data: Data([4, 5]))
        #expect(store.items.isEmpty)
        try first.deliver(name: "first.png", data: Data([1, 2, 3]))

        #expect(counts == [4])
        #expect(store.items.map(\.displayName) == ["first.png", "extra.png", "between", "last.txt"])
        #expect(store.items.allSatisfy { $0.isManaged })
        #expect(!FileManager.default.fileExists(atPath: session.stagingDirectory.path))
        #expect(try Data(contentsOf: store.items[0].url) == Data([1, 2, 3]))
        let restored = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        #expect(restored.items == store.items)
        let files = store.items.map(\.url)
        store.removeAll()
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test
    func synchronousPromiseCallbacksWaitUntilEveryReceiverHasStarted() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let first = ControlledFilePromiseReceiver(names: ["first.txt"])
        first.synchronousData = Data("first".utf8)
        let second = ControlledFilePromiseReceiver(names: ["second.txt"])
        var counts: [Int] = []
        let session = try FileShelfPromiseSession(store: store, items: [.promise(first), .promise(second)], completion: { counts.append($0) })
        session.start()
        #expect(counts.isEmpty)
        try second.deliver(name: "second.txt", data: Data("second".utf8))
        #expect(counts == [2])
        #expect(store.items.map(\.displayName) == ["first.txt", "second.txt"])
        #expect(!FileManager.default.fileExists(atPath: session.stagingDirectory.path))
    }

    @Test
    func synchronousCallbackAfterPendingReceiverCannotFinishTheWholeDropEarly() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let first = ControlledFilePromiseReceiver(names: ["first.txt"])
        let second = ControlledFilePromiseReceiver(names: ["second.txt"])
        second.synchronousData = Data("second".utf8)
        let third = ControlledFilePromiseReceiver(names: ["third.txt"])
        var counts: [Int] = []
        let session = try FileShelfPromiseSession(store: store, items: [.promise(first), .promise(second), .promise(third)], completion: { counts.append($0) })
        session.start()
        #expect(counts.isEmpty)
        try first.deliver(name: "first.txt", data: Data("first".utf8))
        #expect(counts.isEmpty)
        try third.deliver(name: "third.txt", data: Data("third".utf8))
        #expect(counts == [3])
        #expect(store.items.map(\.displayName) == ["first.txt", "second.txt", "third.txt"])
        #expect(!FileManager.default.fileExists(atPath: session.stagingDirectory.path))
    }

    @Test
    func allSynchronousPromiseCallbacksFinishWithoutWaitingForTimeout() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let receiver = ControlledFilePromiseReceiver(names: ["instant.txt"])
        receiver.synchronousData = Data("instant".utf8)
        var count = -1
        store.receive([.promise(receiver)]) { count = $0 }
        #expect(count == 1)
        #expect(store.items.first?.displayName == "instant.txt")
        let destination = try #require(receiver.destination)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func promiseFailureRetainsSuccessfulItemsAndCleansStaging() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let promise = ControlledFilePromiseReceiver(names: ["failed.txt"])
        var count = -1
        let session = try FileShelfPromiseSession(store: store, items: [.content(.text("keep")), .promise(promise)], completion: { count = $0 })
        session.start()
        promise.deliverError(CocoaError(.fileWriteOutOfSpace))
        #expect(count == 1)
        #expect(store.items.map(\.payload) == [.text("keep")])
        #expect(store.errorDescription != nil)
        #expect(!FileManager.default.fileExists(atPath: session.stagingDirectory.path))
    }

    @Test
    func promiseEscapesAndSymlinksCannotImportExternalFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let external = directory.appendingPathComponent("external.txt")
        try Data("private".utf8).write(to: external)
        for symlink in [false, true] {
            let receiver = ControlledFilePromiseReceiver(names: ["unsafe.txt"])
            var count = -1
            let session = try FileShelfPromiseSession(store: store, items: [.promise(receiver)], completion: { count = $0 })
            session.start()
            let input: URL
            if symlink {
                input = session.stagingDirectory.appendingPathComponent("escape.txt")
                try FileManager.default.createSymbolicLink(at: input, withDestinationURL: external)
            } else { input = external }
            receiver.deliverURL(input)
            #expect(count == 0)
            #expect(store.items.isEmpty)
            #expect(store.errorDescription != nil)
            #expect(!FileManager.default.fileExists(atPath: session.stagingDirectory.path))
        }
        #expect(try String(contentsOf: external, encoding: .utf8) == "private")
    }

    @Test
    func unfinishedPromiseCanFinishOnceWithoutLeakingOrAddingLateCallbacks() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let promise = ControlledFilePromiseReceiver(names: ["late.txt"])
        var counts: [Int] = []
        let session = try FileShelfPromiseSession(store: store, items: [.promise(promise)], completion: { counts.append($0) })
        session.start()
        session.expire()
        session.expire()
        try FileManager.default.createDirectory(at: session.stagingDirectory, withIntermediateDirectories: false)
        try promise.deliver(name: "late.txt", data: Data("late".utf8))
        #expect(counts == [0])
        #expect(store.items.isEmpty)
        #expect(store.errorDescription != nil)
        #expect(!FileManager.default.fileExists(atPath: session.stagingDirectory.path))
    }

    @Test(arguments: [NSBitmapImageRep.FileType.png, .tiff])
    func rawBrowserImageBecomesAnOwnedFileAndSurvivesRestart(type: NSBitmapImageRep.FileType) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let store = FileShelfStore(storageURL: storage)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let data = try encodedImage(type: type)
        let item = NSPasteboardItem()
        item.setData(data, forType: type == .png ? .png : .tiff)
        #expect(pasteboard.writeObjects([item]))
        var added = 0
        store.receive(TransferPasteboard.readShelfDropItems(from: pasteboard)) { added = $0 }
        #expect(added == 1)
        let image = try #require(store.items.first)
        #expect(image.category == .image)
        #expect(image.isManaged)
        #expect(image.url.pathExtension == (type == .png ? "png" : "tiff"))
        #expect(try Data(contentsOf: image.url) == data)
        #expect(image.payload == .file(image.url))
        #expect(FileShelfStore(storageURL: storage).items == store.items)
        store.remove(id: image.id)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: image.url.path))
    }

    @Test
    func fileLinkTextAndPromiseRepresentationsTakePriorityOverRawImages() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: file)
        let data = try encodedImage(type: .png)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let fileItem = NSPasteboardItem()
        fileItem.setString(file.absoluteString, forType: .fileURL)
        fileItem.setData(data, forType: .png)
        let textItem = NSPasteboardItem()
        textItem.setString("selected text", forType: .string)
        textItem.setData(data, forType: .tiff)
        let linkItem = NSPasteboardItem()
        linkItem.setString("https://example.invalid/image.png", forType: .URL)
        linkItem.setData(data, forType: .png)
        #expect(pasteboard.writeObjects([fileItem, textItem, linkItem]))
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        var count = 0
        store.receive(TransferPasteboard.readShelfDropItems(from: pasteboard)) { count = $0 }
        #expect(count == 3)
        #expect(store.items.map(\.payload) == [.file(file), .text("selected text"), .text("https://example.invalid/image.png")])
        let promised = NSPasteboardItem()
        promised.setString("public.png", forType: .init("com.apple.pasteboard.promised-file-content-type"))
        promised.setData(data, forType: .png)
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([promised]))
        let promises = TransferPasteboard.readShelfDropItems(from: pasteboard)
        #expect(!promises.contains { if case .image = $0 { true } else { false } })
    }

    @Test
    func rawImagesPreserveMixedOrderWhilePromisesFinishAsynchronously() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let promise = ControlledFilePromiseReceiver(names: ["promised.txt"])
        let png = try encodedImage(type: .png)
        let tiff = try encodedImage(type: .tiff)
        var count = -1
        store.receive([.image(png), .content(.text("between")), .promise(promise), .image(tiff)]) { count = $0 }
        #expect(store.items.isEmpty)
        try promise.deliver(name: "promised.txt", data: Data("promise".utf8))
        #expect(count == 4)
        #expect(store.items.map(\.displayName) == ["image.png", "between", "promised.txt", "image.tiff"])
        #expect(try Data(contentsOf: store.items[0].url) == png)
        #expect(try Data(contentsOf: store.items[3].url) == tiff)
        #expect(store.errorDescription == nil)
    }

    @Test
    func invalidImagesFailWithoutFilesAndPreserveOtherItems() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let png = try encodedImage(type: .png)
        var invalidChecksum = png
        invalidChecksum[invalidChecksum.count - 1] ^= 1
        let invalid = [Data(), Data("<svg><script>alert(1)</script></svg>".utf8), Data(png.prefix(24)), Data(png.dropLast(12)), invalidChecksum, try pngWithCorruptPixels(), try encodedImage(type: .jpeg), try multipageTIFF()]
        for data in invalid {
            #expect(store.importImage(data) == 0)
            #expect(store.items.isEmpty)
            #expect(store.errorDescription != nil)
            #expect(!FileManager.default.fileExists(atPath: store.managedDirectory.path))
        }
        var count = -1
        store.receive([.image(Data([0x00, 0xFF])), .content(.text("keep"))]) { count = $0 }
        #expect(count == 1)
        #expect(store.items.map(\.payload) == [.text("keep")])
        #expect(store.errorDescription != nil)
    }

    @Test
    func seededMalformedPNGChunksFailWithoutWritingFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let png = try encodedImage(type: .png)
        var seed: UInt32 = 0x51E1F
        for _ in 0..<64 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let length = seed | 0x80000000
            var data = png
            let chunk = (0..<4).map { UInt8(truncatingIfNeeded: length >> ((3 - $0) * 8)) }
                + Array("tEXt".utf8) + [0, 0, 0, 0]
            data.insert(contentsOf: chunk, at: data.count - 12)
            #expect(store.importImage(data) == 0)
            #expect(store.items.isEmpty)
        }
        #expect(!FileManager.default.fileExists(atPath: store.managedDirectory.path))
    }

    @Test
    func oversizedEncodedImagesAreRejectedBeforeImport() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        var data = try encodedImage(type: .png)
        data.append(Data(count: FileShelfStore.maximumImageBytes + 1 - data.count))
        #expect(store.importImage(data) == 0)
        #expect(store.errorDescription == CocoaError(.fileReadTooLarge).localizedDescription)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.managedDirectory.path))
    }

    @Test
    func compressedImagesOverPixelBudgetAreRejectedBeforeDecoding() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let data = try encodedImage(type: .png, width: 4_001, height: 4_000)
        #expect(data.count < FileShelfStore.maximumImageBytes)
        #expect(store.importImage(data) == 0)
        #expect(store.errorDescription == CocoaError(.fileReadTooLarge).localizedDescription)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.managedDirectory.path))
    }

    @Test(arguments: [55, 4_096])
    func oversizedPNGPixelStreamCannotBypassItsDeclaredDimensions(byteCount: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        var data = try encodedImage(type: .png)
        let input = Data(count: byteCount)
        var compressed = Data(count: Int(compressBound(uLong(input.count))))
        var compressedCount = uLongf(compressed.count)
        let status = compressed.withUnsafeMutableBytes { output in
            input.withUnsafeBytes { source in
                compress2(output.bindMemory(to: Bytef.self).baseAddress, &compressedCount, source.bindMemory(to: Bytef.self).baseAddress, uLong(input.count), Z_DEFAULT_COMPRESSION)
            }
        }
        #expect(status == Z_OK)
        compressed.count = Int(compressedCount)
        let body = Data("IDAT".utf8) + compressed
        let checksum = body.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }
        let chunk = Data((0..<4).map { UInt8(truncatingIfNeeded: compressed.count >> ((3 - $0) * 8)) })
            + body + Data((0..<4).map { UInt8(truncatingIfNeeded: checksum >> ((3 - $0) * 8)) })
        var offset = 8
        while offset + 12 <= data.count {
            let length = data[offset..<(offset + 4)].reduce(0) { $0 << 8 | Int($1) }
            if String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self) == "IDAT" {
                data.replaceSubrange(offset..<(offset + length + 12), with: chunk)
                break
            }
            offset += length + 12
        }
        #expect(store.importImage(data) == 0)
        #expect(store.errorDescription != nil)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.managedDirectory.path))
    }

    @Test
    func failedImagePersistenceCleansOnlyItsOwnFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let store = FileShelfStore(storageURL: storage)
        #expect(store.add(payloads: [.text("existing")]) == 1)
        let existing = store.items
        try FileManager.default.removeItem(at: storage)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
        #expect(store.importImage(try encodedImage(type: .png)) == 0)
        #expect(store.items == existing)
        #expect(store.errorDescription != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.managedDirectory.path) == [existing[0].id.uuidString])
        #expect(FileManager.default.fileExists(atPath: existing[0].url.path))
    }

    private func pngWithCorruptPixels() throws -> Data {
        var data = try encodedImage(type: .png)
        var offset = 8
        while offset + 12 <= data.count {
            let length = data[offset..<(offset + 4)].reduce(0) { $0 << 8 | Int($1) }
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if type == "IDAT" {
                data.replaceSubrange((offset + 8)..<(offset + 8 + length), with: repeatElement(UInt8(0xFF), count: length))
                var crc: UInt32 = 0xFFFFFFFF
                for byte in data[(offset + 4)..<(offset + 8 + length)] {
                    crc ^= UInt32(byte)
                    for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0) }
                }
                crc ^= 0xFFFFFFFF
                let bytes = (0..<4).map { UInt8(truncatingIfNeeded: crc >> ((3 - $0) * 8)) }
                data.replaceSubrange((offset + 8 + length)..<(offset + 12 + length), with: bytes)
                return data
            }
            offset += length + 12
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    private func multipageTIFF() throws -> Data {
        let data = try encodedImage(type: .png)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.tiff.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func encodedImage(type: NSBitmapImageRep.FileType, width: Int = 2, height: Int = 3) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try #require(bitmap.bitmapData)
        pixels.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        return try #require(bitmap.representation(using: type, properties: [:]))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-shelf-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

private final class ControlledFilePromiseReceiver: NSFilePromiseReceiver, @unchecked Sendable {
    private let names: [String]
    private var reader: ((URL, Error?) -> Void)?
    private(set) var destination: URL?
    var synchronousData: Data?

    init(names: [String]) {
        self.names = names
        super.init()
    }

    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { nil }

    override var fileNames: [String] { names }

    override func receivePromisedFiles(atDestination destinationDir: URL, options: [AnyHashable: Any] = [:], operationQueue: OperationQueue, reader: @escaping (URL, Error?) -> Void) {
        destination = destinationDir
        self.reader = reader
        if let synchronousData, let name = names.first {
            do { try deliver(name: name, data: synchronousData) }
            catch { reader(destinationDir, error) }
        }
    }

    func deliver(name: String, data: Data) throws {
        let url = try #require(destination).appendingPathComponent(name)
        try data.write(to: url)
        reader?(url, nil)
    }

    func deliverURL(_ url: URL) { reader?(url, nil) }

    func deliverError(_ error: Error) { reader?(URL(fileURLWithPath: "/ignored"), error) }
}
