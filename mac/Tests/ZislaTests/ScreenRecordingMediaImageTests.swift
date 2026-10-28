import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized)
struct ScreenRecordingMediaImageTests {
    @Test
    func pngDecodingPreservesRealPixelsAndTransparencyWithinTheRequestedSize() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let asset = try fixture.addImage(width: 48, height: 24, transparent: true)
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
        #expect(try RecordingMediaImageStore.dimensions(of: fixture.url(asset)) == CGSize(width: 48, height: 24))
        let image = try store.image(for: asset.id, maximumSize: CGSize(width: 100, height: 100))
        #expect(image.width == 48 && image.height == 24, "Small images must not be enlarged during decoding")
        let pixels = try RecordingImageFixture.pixels(image)
        #expect(pixels.pixel(x: 4, y: 12) == [0, 0, 0, 0])
        #expect(pixels.pixel(x: 24, y: 12) == [128, 0, 0, 128])
        #expect(pixels.pixel(x: 44, y: 12) == [0, 255, 0, 255])
        let thumbnail = try store.image(for: asset.id, maximumSize: CGSize(width: 16, height: 12))
        #expect(thumbnail.width == 16 && thumbnail.height == 8)
        #expect(try RecordingImageFixture.pixels(thumbnail).pixel(x: 1, y: 4)[3] == 0)
    }

    @Test(arguments: Array(1...8))
    func jpegDimensionsAndPixelsFollowEveryExifOrientation(_ orientation: Int) throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let asset = try fixture.addImage(width: 60, height: 36, orientation: orientation)
        let url = fixture.url(asset)
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
        let image = try store.image(for: asset.id, maximumSize: CGSize(width: 100, height: 100))
        let size = try RecordingMediaImageStore.dimensions(of: url)
        #expect(size == CGSize(width: orientation >= 5 ? 36 : 60, height: orientation >= 5 ? 60 : 36))
        #expect(CGSize(width: image.width, height: image.height) == size)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let raw = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let expected = CIImage(cgImage: raw).oriented(CGImagePropertyOrientation(rawValue: UInt32(orientation))!)
        let expectedImage = try #require(CIContext().createCGImage(expected, from: expected.extent))
        let expectedPixels = try RecordingImageFixture.pixels(expectedImage)
        let pixels = try RecordingImageFixture.pixels(image)
        for x in [image.width / 5, image.width / 2, image.width * 4 / 5] {
            for y in [image.height / 4, image.height * 3 / 4] {
                #expect(zip(pixels.pixel(x: x, y: y), expectedPixels.pixel(x: x, y: y)).allSatisfy {
                    abs(Int($0) - Int($1)) <= 3
                }, "EXIF orientation must transform image pixels, including mirrored orientations")
            }
        }
    }

    @Test
    func cacheReusesImagesAndEvictsTheLeastRecentlyUsedPixelsAtItsByteLimit() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let assets = try (0..<3).map { _ in try fixture.addImage(width: 32, height: 32) }
        let size = CGSize(width: 32, height: 32)
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory, cacheByteLimit: 8_192)
        let first = try store.image(for: assets[0].id, maximumSize: size)
        let second = try store.image(for: assets[1].id, maximumSize: size)
        #expect(try store.image(for: assets[0].id, maximumSize: size) === first)
        _ = try store.image(for: assets[2].id, maximumSize: size)
        #expect(try store.image(for: assets[0].id, maximumSize: size) === first)
        #expect(try store.image(for: assets[1].id, maximumSize: size) !== second,
                "The oldest unused image must be decoded again after the cache reaches its byte budget")
        let noRoom = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory, cacheByteLimit: 1)
        let uncached = try noRoom.image(for: assets[0].id, maximumSize: size)
        #expect(try noRoom.image(for: assets[0].id, maximumSize: size) !== uncached)
    }

    @Test
    func tinyImagesAlsoHaveABoundedCacheEntryCount() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let assets = try (0..<65).map { _ in try fixture.addImage(width: 1, height: 1) }
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
        let first = try store.image(for: assets[0].id, maximumSize: CGSize(width: 1, height: 1))
        for asset in assets.dropFirst() { _ = try store.image(for: asset.id, maximumSize: CGSize(width: 1, height: 1)) }
        #expect(try store.image(for: assets[0].id, maximumSize: CGSize(width: 1, height: 1)) !== first)
    }

    @Test
    func changedAndRemovedFilesNeverReturnAnOlderCachedImage() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let asset = try fixture.addImage(width: 32, height: 32)
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
        let first = try store.image(for: asset.id, maximumSize: CGSize(width: 32, height: 32))
        let url = fixture.url(asset)
        try RecordingImageFixture.writeImage(to: url, width: 24, height: 16)
        let updated = try store.image(for: asset.id, maximumSize: CGSize(width: 32, height: 32))
        #expect(updated !== first && updated.width == 24 && updated.height == 16)
        try Data([1, 2, 3]).write(to: url)
        #expect(throws: ScreenRecordingExportError.unavailableMedia) {
            try store.image(for: asset.id, maximumSize: CGSize(width: 32, height: 32))
        }
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try store.image(for: asset.id, maximumSize: CGSize(width: 32, height: 32)) }
    }

    @Test
    func imagesRejectUnknownAssetsUnsafePathsAndSymlinksEvenAfterCaching() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let asset = try fixture.addImage(width: 12, height: 8)
        let size = CGSize(width: 12, height: 8)
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
        #expect(throws: ScreenRecordingExportError.unavailableMedia) { try store.image(for: UUID(), maximumSize: size) }
        for name in ["../outside.png", "/outside.png", "sub/image.png"] {
            var project = fixture.project
            project.timeline?.assets[0].file = name
            let unsafe = RecordingMediaImageStore(project: project, directory: fixture.directory)
            #expect(throws: ScreenRecordingProjectError.unsafeMediaPath) { try unsafe.image(for: asset.id, maximumSize: size) }
        }
        var video = fixture.project
        video.timeline?.assets[0].kind = .video
        #expect(throws: ScreenRecordingExportError.unavailableMedia) {
            try RecordingMediaImageStore(project: video, directory: fixture.directory).image(for: asset.id, maximumSize: size)
        }
        _ = try store.image(for: asset.id, maximumSize: size)
        let outside = fixture.root.appendingPathComponent("outside.png")
        try FileManager.default.copyItem(at: fixture.url(asset), to: outside)
        let original = try Data(contentsOf: outside)
        try FileManager.default.removeItem(at: fixture.url(asset))
        try FileManager.default.createSymbolicLink(at: fixture.url(asset), withDestinationURL: outside)
        #expect(throws: ScreenRecordingProjectError.unsafeMediaPath) { try store.image(for: asset.id, maximumSize: size) }
        #expect(try Data(contentsOf: outside) == original)
    }

    @Test
    func invalidThumbnailSizesAndTruncatedImagesFailWithoutChangingTheMedia() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let asset = try fixture.addImage(width: 32, height: 32)
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
        for size in [CGSize.zero, CGSize(width: -1, height: 2), CGSize(width: CGFloat.infinity, height: 10),
                     CGSize(width: 10, height: CGFloat.nan), CGSize(width: 0.5, height: 4)] {
            #expect(throws: ScreenRecordingExportError.invalidConfiguration) { try store.image(for: asset.id, maximumSize: size) }
        }
        let data = try Data(contentsOf: fixture.url(asset)).prefix(24)
        try data.write(to: fixture.url(asset))
        #expect(throws: ScreenRecordingExportError.unavailableMedia) { try RecordingMediaImageStore.dimensions(of: fixture.url(asset)) }
        #expect(throws: ScreenRecordingExportError.unavailableMedia) {
            try store.image(for: asset.id, maximumSize: CGSize(width: 32, height: 32))
        }
        #expect(try Data(contentsOf: fixture.url(asset)) == data)
    }

    @Test
    func sourceDimensionsEncodedSizeAndDecodedPixelMemoryHaveExplicitBounds() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let oversized = try fixture.addImage(width: 16_385, height: 1, readDimensions: false)
        #expect(throws: ScreenRecordingExportError.unavailableMedia) { try RecordingMediaImageStore.dimensions(of: fixture.url(oversized)) }
        let sparse = fixture.directory.appendingPathComponent("oversized.png")
        let small = try fixture.addImage(width: 8, height: 8)
        #expect(FileManager.default.createFile(atPath: sparse.path, contents: try Data(contentsOf: fixture.url(small))))
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 256 * 1_024 * 1_024 + 1)
        try handle.close()
        #expect(throws: ScreenRecordingExportError.unavailableMedia) { try RecordingMediaImageStore.dimensions(of: sparse) }
        let large = try fixture.addImage(width: 4_200, height: 4_200)
        let image = try RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
            .image(for: large.id, maximumSize: CGSize(width: 10_000, height: 10_000))
        #expect(image.width * image.height <= 4_096 * 4_096)
        #expect(image.width == image.height && image.width >= 4_000)
    }

    @Test
    func boundedCorruptImageCorpusFailsWithoutWritingDecodedArtifacts() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let asset = try fixture.addImage(width: 8, height: 8)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted()
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
        var seed: UInt64 = 0x494d_4147_45
        for length in 1...32 {
            let bytes = (0..<length).map { _ -> UInt8 in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                return UInt8(truncatingIfNeeded: seed >> 32)
            }
            try Data(bytes).write(to: fixture.url(asset))
            #expect(throws: ScreenRecordingExportError.unavailableMedia) {
                try store.image(for: asset.id, maximumSize: CGSize(width: 8, height: 8))
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted() == names)
    }

    @Test
    func savedAndCopiedProjectsKeepEveryImageAndIndependentClipLayout() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let first = try fixture.addImage(width: 40, height: 20, transparent: true)
        let second = try fixture.addImage(width: 20, height: 40)
        let track = RecordingTimelineTrack(kind: .image)
        fixture.project.timeline?.tracks = [track]
        fixture.project.timeline?.clips = [
            .init(trackID: track.id, content: .image(first.id), start: 0, sourceEnd: 1,
                  layout: .init(x: 0, y: 0, width: 0.4, height: 0.2)),
            .init(trackID: track.id, content: .image(first.id), start: 1, sourceEnd: 1,
                  layout: .init(x: 0.5, y: 0.5, width: 0.4, height: 0.2)),
        ]
        let store = ScreenRecordingProjectStore(root: fixture.root)
        try store.save(fixture.project, in: fixture.directory)
        #expect(try store.load(from: fixture.directory) == fixture.project)
        let destination = fixture.root.appendingPathComponent("copied.zisla-recording")
        try store.copy(fixture.project, from: fixture.directory, to: destination)
        let copied = try store.load(from: destination)
        #expect(copied == fixture.project)
        let images = RecordingMediaImageStore(project: copied, directory: destination)
        for asset in [first, second] {
            #expect(try Data(contentsOf: destination.appendingPathComponent(asset.file)) == Data(contentsOf: fixture.url(asset)))
            let image = try images.image(for: asset.id, maximumSize: CGSize(width: 100, height: 100))
            #expect(image.width == asset.width && image.height == asset.height)
        }
        #expect(copied.timeline?.clips[0].layout != copied.timeline?.clips[1].layout)
    }

    @Test
    func cancellingAnImageProjectCopyRemovesStagingAndKeepsTheOriginalMedia() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let asset = try fixture.addImage(width: 20, height: 10)
        let before = try Data(contentsOf: fixture.url(asset))
        let destination = fixture.root.appendingPathComponent("cancelled.zisla-recording")
        let store = ScreenRecordingProjectStore(root: fixture.root)
        var checkpoints = 0
        #expect(throws: CancellationError.self) {
            try store.copy(fixture.project, from: fixture.directory, to: destination, checkCancellation: {
                checkpoints += 1
                if checkpoints == 2 { throw CancellationError() }
            })
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == [fixture.directory.lastPathComponent])
        #expect(try Data(contentsOf: fixture.url(asset)) == before)
    }

    @Test
    func orientationChangesWithTheSameFileSizeInvalidateTheCachedPixels() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let asset = try fixture.addImage(width: 60, height: 36, orientation: 1)
        let url = fixture.url(asset)
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
        let original = try store.image(for: asset.id, maximumSize: CGSize(width: 100, height: 100))
        let replacement = fixture.root.appendingPathComponent("updated.jpg")
        try RecordingImageFixture.writeImage(to: replacement, width: 60, height: 36, orientation: 6)
        let data = try Data(contentsOf: replacement)
        #expect(data.count == bytes)
        let identifier = try url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? AnyHashable
        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: data)
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)], ofItemAtPath: url.path)
        #expect(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == bytes)
        #expect(try url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? AnyHashable == identifier)
        let image = try store.image(for: asset.id, maximumSize: CGSize(width: 100, height: 100))
        #expect(image !== original && image.width == 36 && image.height == 60)
    }

    @Test
    func replacingAnImageWithMatchingSizeAndModificationDateInvalidatesTheCachedPixels() throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let asset = try fixture.addImage(width: 60, height: 36, orientation: 1)
        let url = fixture.url(asset)
        let fixedModified = Date(timeIntervalSince1970: 1_900_000_000)
        try FileManager.default.setAttributes([.modificationDate: fixedModified], ofItemAtPath: url.path)
        let before = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let modified = try #require(before.contentModificationDate)
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
        let original = try store.image(for: asset.id, maximumSize: CGSize(width: 100, height: 100))
        let replacement = fixture.root.appendingPathComponent("replacement.jpg")
        try RecordingImageFixture.writeImage(to: replacement, width: 60, height: 36, orientation: 6)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: replacement.path)
        #expect(try replacement.resourceValues(forKeys: [.fileSizeKey]).fileSize == before.fileSize)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == modified)
        let image = try store.image(for: asset.id, maximumSize: CGSize(width: 100, height: 100))
        #expect(image !== original && image.width == 36 && image.height == 60,
                "A replacement file must not reuse pixels from the previous file at the same path")
    }

    @Test
    func concurrentRequestsShareOneDecodedImageWithoutCorruptingTheCache() async throws {
        let fixture = try RecordingImageFixture()
        defer { fixture.close() }
        let asset = try fixture.addImage(width: 256, height: 128)
        let store = RecordingMediaImageStore(project: fixture.project, directory: fixture.directory)
        let images = try await withThrowingTaskGroup(of: CGImage.self) { group in
            for _ in 0..<12 {
                group.addTask { try store.image(for: asset.id, maximumSize: CGSize(width: 128, height: 128)) }
            }
            var images: [CGImage] = []
            for try await image in group { images.append(image) }
            return images
        }
        let first = try #require(images.first)
        #expect(images.count == 12 && images.allSatisfy { $0 === first })
        #expect(first.width == 128 && first.height == 64)
    }
}

final class RecordingImageFixture {
    let root: URL
    let directory: URL
    var project: ScreenRecordingProject

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-test-\(UUID())")
        directory = try ScreenRecordingProjectStore(root: root).createDirectory()
        try Data([1]).write(to: directory.appendingPathComponent("screen.mp4"))
        project = ScreenRecordingProject(name: "Synthetic images", videoFile: "screen.mp4", duration: 3,
                                        width: 400, height: 300, timeline: .init())
        project.version = 2
        project.edits.background = .none
        project.edits.padding = 0
        project.edits.cornerRadius = 0
        project.edits.shadow = 0
        project.edits.showCursor = false
        project.edits.clickEffects = false
    }

    func close() { try? FileManager.default.removeItem(at: root) }
    func url(_ asset: RecordingMediaAsset) -> URL { directory.appendingPathComponent(asset.file) }

    func addImage(width: Int, height: Int, transparent: Bool = false, orientation: Int? = nil,
                  readDimensions: Bool = true) throws -> RecordingMediaAsset {
        let file = UUID().uuidString + (orientation == nil ? ".png" : ".jpg")
        let url = directory.appendingPathComponent(file)
        try Self.writeImage(to: url, width: width, height: height, transparent: transparent, orientation: orientation)
        let size = readDimensions ? try RecordingMediaImageStore.dimensions(of: url) : CGSize(width: width, height: height)
        let asset = RecordingMediaAsset(name: file, file: file, kind: .image, duration: 2,
                                       width: Int(size.width), height: Int(size.height))
        project.timeline?.assets.append(asset)
        return asset
    }

    static func writeImage(to url: URL, width: Int, height: Int, transparent: Bool = false,
                           orientation: Int? = nil) throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(bounds)
        if transparent {
            context.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 0, 0, 0.5])!)
            context.fill(CGRect(x: width / 3, y: 0, width: width / 3, height: height))
            context.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 1, 0, 1])!)
            context.fill(CGRect(x: width * 2 / 3, y: 0, width: width - width * 2 / 3, height: height))
        } else {
            context.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 0, 0, 1])!)
            context.fill(bounds)
            context.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 1, 0, 1])!)
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
            context.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 0, 1, 1])!)
            context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height - height / 2))
        }
        let image = try #require(context.makeImage())
        let type = orientation == nil ? UTType.png.identifier : UTType.jpeg.identifier
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        let properties: [CFString: Any] = orientation.map {
            [kCGImagePropertyOrientation: $0, kCGImageDestinationLossyCompressionQuality: 1.0]
        } ?? [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    struct Pixels {
        let width: Int
        let bytes: [UInt8]
        func pixel(x: Int, y: Int) -> [UInt8] { Array(bytes[((y * width + x) * 4)..<((y * width + x) * 4 + 4)]) }
    }

    static func pixels(_ image: CGImage) throws -> Pixels {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(data: pointer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Pixels(width: image.width, bytes: bytes)
    }
}
