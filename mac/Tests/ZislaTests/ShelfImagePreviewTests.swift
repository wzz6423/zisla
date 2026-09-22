import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Zisla
@testable import ZislaKit

@MainActor
struct ShelfImagePreviewTests {
    @Test(arguments: [UTType.jpeg, .png, .tiff])
    func imageFilesDisplayTheirPixelsAtThumbnailSize(type: UTType) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("browser-image." + type.preferredFilenameExtension!)
        let original = try encodedImage(type: type)
        try original.write(to: url)

        let image = FileIconCache().icon(for: url.path)

        #expect(image.size == NSSize(width: 84, height: 42))
        let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(pixels.width <= 84 && pixels.height <= 84)
        try expectRedPixels(in: image)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test
    func thumbnailRespectsImageOrientation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("portrait.jpg")
        try encodedImage(type: .jpeg, orientation: 6).write(to: url)

        let image = FileIconCache().icon(for: url.path)

        #expect(image.size == NSSize(width: 42, height: 84))
        try expectRedPixels(in: image)
    }

    @Test
    func previewUsesOriginalPixelsInsteadOfAnEmbeddedThumbnail() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let red = try encodedImage(type: .jpeg, width: 600, height: 400)
        let blue = try encodedImage(type: .jpeg, width: 600, height: 400, color: .blue, embedThumbnail: true)
        let previews = jpegSegments(blue).filter { $0.0 == 0xe1 }
        #expect(!previews.isEmpty)
        var data = Data(red.prefix(2))
        for segment in previews + jpegSegments(red).filter({ $0.0 != 0xe1 }) { data.append(segment.1) }
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let embedded = try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceThumbnailMaxPixelSize: 84,
        ] as CFDictionary))
        let embeddedImage = NSImage(cgImage: embedded, size: NSSize(width: embedded.width, height: embedded.height))
        let embeddedColor = try centerColor(in: embeddedImage)
        #expect(embeddedColor.blueComponent > 0.9)
        let url = directory.appendingPathComponent("edited-photo.jpg")
        try data.write(to: url)

        let image = FileIconCache().icon(for: url.path)

        #expect(image.size == NSSize(width: 84, height: 56))
        try expectRedPixels(in: image)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test
    func promisedImagePreviewKeepsOriginalFileAcrossRestartCopyAndRemoval() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let staging = directory.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let url = staging.appendingPathComponent("browser-photo.jpg")
        let original = try encodedImage(type: .jpeg)
        try original.write(to: url)
        let storage = directory.appendingPathComponent("shelf.json")
        let store = FileShelfStore(storageURL: storage)
        #expect(store.importPromisedFile(at: url, from: staging) == 1)
        let restored = FileShelfStore(storageURL: storage)
        let item = try #require(restored.items.first)

        try expectRedPixels(in: FileIconCache().icon(for: item.url.path))
        #expect(item.category == .image)
        #expect(item.payload == .file(item.url))
        #expect(try Data(contentsOf: item.url) == original)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects([FileShelfPasteboard.pasteboardWriter(for: item.payload)]))
        #expect(FileShelfPasteboard.readFileURLs(from: pasteboard) == [item.url])
        restored.remove(id: item.id)
        #expect(restored.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: item.url.path))
        #expect(try Data(contentsOf: url) == original)
    }

    @Test
    func smallImageDoesNotAllocateAnUpscaledBitmap() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("small.png")
        try encodedImage(type: .png, width: 12, height: 6).write(to: url)

        let image = FileIconCache().icon(for: url.path)

        #expect(image.size == NSSize(width: 12, height: 6))
        try expectRedPixels(in: image)
    }

    @Test
    func linksKeepTheirOriginalPayloadAndUseAFileIcon() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = "https://example.invalid/image.jpg"
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        #expect(store.add(payloads: [.text(link)]) == 1)
        let item = try #require(store.items.first)
        let original = try Data(contentsOf: item.url)

        let image = FileIconCache().icon(for: item.url.path)

        #expect(image.size == NSWorkspace.shared.icon(forFile: item.url.path).size)
        #expect(item.payload == .text(link))
        #expect(item.category == .url)
        #expect(try Data(contentsOf: item.url) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: item.url.deletingLastPathComponent().path) == ["link.webloc"])
    }

    @Test
    func corruptFilesDirectoriesAndMissingFilesKeepUsableFallbackIcons() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileIconCache()
        let invalid = [Data(), Data([0x89, 0x50, 0x4e, 0x47]), Data("<svg><script>alert(1)</script></svg>".utf8)]
        for (index, data) in invalid.enumerated() {
            let url = directory.appendingPathComponent("invalid-\(index).png")
            try data.write(to: url)
            let image = cache.icon(for: url.path)
            #expect(image.size == NSWorkspace.shared.icon(forFile: url.path).size)
            #expect(try Data(contentsOf: url) == data)
        }
        for url in [directory, directory.appendingPathComponent("missing.jpg")] {
            #expect(cache.icon(for: url.path).size == NSWorkspace.shared.icon(forFile: url.path).size)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == invalid.count)
    }

    @Test
    func symbolicLinksKeepTheirIconWithoutDecodingTheTarget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.png")
        let original = try encodedImage(type: .png)
        try original.write(to: target)
        let link = directory.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(FileIconCache().icon(for: link.path).size == NSWorkspace.shared.icon(forFile: link.path).size)
        #expect(try Data(contentsOf: target) == original)
    }

    @Test
    func oversizedFileFallsBackBeforeReadingTheImage() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("oversized.png")
        let original = try encodedImage(type: .png)
        try original.write(to: url)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.truncate(atOffset: 32 * 1_024 * 1_024 + 1)

        #expect(FileIconCache().icon(for: url.path).size == NSWorkspace.shared.icon(forFile: url.path).size)
        #expect(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == 32 * 1_024 * 1_024 + 1)
    }

    @Test(arguments: [4_000, 4_001])
    func thumbnailChecksSourcePixelBudgetBeforeDecoding(width: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("compressed.png")
        let original = try encodedImage(type: .png, width: width, height: 4_000)
        try original.write(to: url)
        let image = FileIconCache().icon(for: url.path)

        if width == 4_000 {
            #expect(image.size == NSSize(width: 84, height: 84))
            try expectRedPixels(in: image)
        } else {
            #expect(image.size == NSWorkspace.shared.icon(forFile: url.path).size)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test
    func changedFileSizeInvalidatesAFailedPreviewEvenWithTheSameTimestamp() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("repaired.png")
        let timestamp = Date(timeIntervalSince1970: 1_000)
        try Data("corrupt".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: url.path)
        let cache = FileIconCache()
        #expect(cache.icon(for: url.path).size == NSWorkspace.shared.icon(forFile: url.path).size)

        try encodedImage(type: .png).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: url.path)

        try expectRedPixels(in: cache.icon(for: url.path))
    }

    @Test
    func changedTimestampInvalidatesASameSizeImage() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("updated.jpg")
        var red = try encodedImage(type: .jpeg)
        var blue = try encodedImage(type: .jpeg, color: .blue)
        let size = max(red.count, blue.count)
        red.append(Data(count: size - red.count))
        blue.append(Data(count: size - blue.count))
        try red.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: url.path)
        let cache = FileIconCache()
        try expectRedPixels(in: cache.icon(for: url.path))

        try blue.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: url.path)

        let color = try centerColor(in: cache.icon(for: url.path))
        #expect(color.blueComponent > 0.9)
        #expect(color.redComponent < 0.1)
        #expect(try Data(contentsOf: url) == blue)
    }

    @Test
    func removingAFileDoesNotKeepItsThumbnailInTheFallback() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("removed.png")
        try encodedImage(type: .png).write(to: url)
        let cache = FileIconCache()
        try expectRedPixels(in: cache.icon(for: url.path))

        try FileManager.default.removeItem(at: url)

        #expect(cache.icon(for: url.path).size == NSWorkspace.shared.icon(forFile: url.path).size)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    private func expectRedPixels(in image: NSImage) throws {
        let color = try centerColor(in: image)
        #expect(color.redComponent > 0.9)
        #expect(color.greenComponent < 0.1)
        #expect(color.blueComponent < 0.1)
    }

    private func centerColor(in image: NSImage) throws -> NSColor {
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
    }

    private func encodedImage(type: UTType, orientation: Int = 1, width: Int = 200, height: Int = 100, color: NSColor = .red, embedThumbnail: Bool = false) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmap = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(bitmap.makeImage()), [kCGImagePropertyOrientation: orientation, kCGImageDestinationEmbedThumbnail: embedThumbnail] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func jpegSegments(_ data: Data) -> [(UInt8, Data)] {
        var segments: [(UInt8, Data)] = []
        var offset = 2
        while offset + 4 <= data.count {
            let marker = data[offset + 1]
            if marker == 0xda {
                segments.append((marker, Data(data[offset...])))
                break
            }
            let length = Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            let end = offset + 2 + length
            segments.append((marker, Data(data[offset..<end])))
            offset = end
        }
        return segments
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-shelf-preview-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
