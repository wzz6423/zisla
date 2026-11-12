import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit

struct ImageWatermarkTests {
    @Test
    func defaultsLeaveExistingProcessingUnchangedAndRequireWatermarkContent() {
        #expect(ImageProcessingOptions().watermark == nil)
        #expect(ImageProcessingOptions().isValid)
        #expect(!ImageWatermarkOptions(content: .text("")).isValid)
        #expect(ImageWatermarkOptions(content: .text("Zisla")).isValid)
        #expect(ImageWatermarkOptions(content: .text("Zisla"), opacity: 0, scale: 1).isValid)
        #expect(ImageWatermarkOptions(content: .text("Zisla"), opacity: 1, scale: 0.01).isValid)
    }

    @Test(arguments: ["empty", "whitespace", "overlength", "control", "invalid-color", "invalid-opacity", "nan-opacity", "invalid-scale", "infinite-scale", "remote"])
    func invalidOptionsAreRejectedBeforeCallingAnyExternalTool(fault: String) async throws {
        var options = ImageWatermarkOptions(content: .text("Zisla"))
        switch fault {
        case "empty": options.content = .text("")
        case "whitespace": options.content = .text(" \t\n")
        case "overlength": options.content = .text(String(repeating: "a", count: ImageWatermarkOptions.maximumTextLength + 1))
        case "control": options.content = .text("secret\u{0}text")
        case "invalid-color": options.color = "#00FF00[Q=1]"
        case "invalid-opacity": options.opacity = -0.01
        case "nan-opacity": options.opacity = .nan
        case "invalid-scale": options.scale = 1.01
        case "infinite-scale": options.scale = .infinity
        default: options.content = .image(URL(string: "https://example.com/private.png")!)
        }
        #expect(!options.isValid)
        let processing = ImageProcessingOptions(watermark: options)
        #expect(!processing.isValid)
        await #expect(throws: ImageProcessingError.invalidOptions) {
            try await ImageProcessingService(executableURL: nil).process([URL(fileURLWithPath: "/missing.png")], options: processing)
        }
    }

    @Test(arguments: ["latin-cjk", "rtl-indic", "multiline", "maximum"])
    func multilingualAndMaximumLengthTextFitsInsideTheImage(sample: String) throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let text: String
        switch sample {
        case "latin-cjk": text = "Hello 水印"
        case "rtl-indic": text = "水印 שלום مرحبا Καλημέρα हिंदी"
        case "multiline": text = "first\nsecond\tthird"
        default: text = "© " + String(repeating: "W", count: ImageWatermarkOptions.maximumTextLength - 2)
        }
        let options = ImageWatermarkOptions(content: .text(text), opacity: 0.6, scale: 0.4, color: "#FF0000")
        #expect(options.isValid)
        let overlay = try ImageWatermarkRenderer(options: options, content: .text(text)).render(width: 360, height: 120,
            to: fixture.root.appendingPathComponent("overlay.png"))
        let image = try Pixels.load(overlay.url)
        #expect(image.width <= 144 && image.height <= 120)
        #expect(overlay.x >= 0 && overlay.y >= 0 && overlay.x + image.width <= 360 && overlay.y + image.height <= 120)
        let bytes = try ImageTransformTests.Pixels.bytes(image)
        let alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        #expect(alpha.contains { $0 > 0 })
        #expect(alpha.max() ?? 255 <= 154)
        #expect(stride(from: 0, to: bytes.count, by: 4).allSatisfy { bytes[$0 + 1] <= 1 && bytes[$0 + 2] <= 1 })
    }

    @Test
    func nativeColorEmojiKeepsItsGlyphAndRequestedOpacity() throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let text = "👨‍👩‍👧‍👦"
        let options = ImageWatermarkOptions(content: .text(text), opacity: 0.6, scale: 0.4, color: "#FF0000")
        #expect(options.isValid)
        let overlay = try ImageWatermarkRenderer(options: options, content: .text(text)).render(width: 360, height: 120,
            to: fixture.root.appendingPathComponent("overlay.png"))
        let bytes = try ImageTransformTests.Pixels.bytes(Pixels.load(overlay.url))
        #expect(stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 })
        #expect(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] <= 154 })
        #expect(stride(from: 0, to: bytes.count, by: 4).contains { bytes[$0 + 1] > 1 || bytes[$0 + 2] > 1 })
    }

    @Test
    func rendererCancellationAndUnavailableOutputNeverLeaveAFile() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let renderer = ImageWatermarkRenderer(options: .init(content: .text("Zisla")), content: .text("Zisla"))
        let missingParent = fixture.root.appendingPathComponent("missing/overlay.png")
        #expect(throws: ImageProcessingError.invalidOutput) { try renderer.render(width: 100, height: 80, to: missingParent) }
        #expect(!FileManager.default.fileExists(atPath: missingParent.path))
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try renderer.render(width: 100, height: 80, to: fixture.root.appendingPathComponent("cancel.png"))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("cancel.png").path))
    }

    @Test
    func imageDestinationFailureCannotReturnAnUnfinishedOverlay() throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let renderer = ImageWatermarkRenderer(options: .init(content: .text("Zisla")), content: .text("Zisla"))
        let output = fixture.root.appendingPathComponent("overlay.png")
        var callbacks = CGDataConsumerCallbacks(putBytes: { _, _, _ in 0 }, releaseConsumer: nil)
        let consumer = try #require(CGDataConsumer(info: nil, cbks: &callbacks))
        #expect(throws: ImageProcessingError.invalidOutput) {
            try renderer.render(width: 100, height: 80, to: output, createDestination: { _ in
                CGImageDestinationCreateWithDataConsumer(consumer, UTType.png.identifier as CFString, 1, nil)
            })
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(arguments: ImageWatermarkPosition.allCases)
    func imageWatermarkHasTheRequestedPhysicalPositionAndOpacity(position: ImageWatermarkPosition) throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let image = try Pixels.solid(width: 20, height: 10, red: 255, alpha: 128)
        let options = ImageWatermarkOptions(content: .image(fixture.root.appendingPathComponent("mark.png")), opacity: 0.5, scale: 0.25, position: position)
        let overlay = try ImageWatermarkRenderer(options: options, content: .image(image)).render(width: 100, height: 60,
            to: fixture.root.appendingPathComponent("overlay.png"))
        let rendered = try Pixels.load(overlay.url)
        #expect(rendered.width == 25 && rendered.height == 13)
        let origin: (Int, Int)
        switch position {
        case .center: origin = (37, 23)
        case .topLeft: origin = (1, 1)
        case .topRight: origin = (74, 1)
        case .bottomLeft: origin = (1, 46)
        case .bottomRight: origin = (74, 46)
        }
        #expect(overlay.x == origin.0 && overlay.y == origin.1)
        let pixel = try Pixels.pixel(rendered, x: 12, y: 6)
        #expect(abs(Int(pixel[0]) - 64) <= 1 && abs(Int(pixel[3]) - 64) <= 1)
    }

    @Test(arguments: [(1, 1), (3, 100), (100, 3)])
    func extremeAspectRatioWatermarkNeverOverflowsTheCanvas(dimensions: (Int, Int)) throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let image = try Pixels.solid(width: 2, height: 100, red: 255)
        let options = ImageWatermarkOptions(content: .image(fixture.root.appendingPathComponent("mark.png")), opacity: 1, scale: 1, position: .bottomRight)
        let overlay = try ImageWatermarkRenderer(options: options, content: .image(image)).render(width: dimensions.0, height: dimensions.1,
            to: fixture.root.appendingPathComponent("overlay.png"))
        let rendered = try Pixels.load(overlay.url)
        #expect(overlay.x >= 0 && overlay.y >= 0)
        #expect(rendered.width + overlay.x <= dimensions.0 && rendered.height + overlay.y <= dimensions.1)
    }

    @Test(arguments: ["link", "directory", "unsupported", "malformed", "disguised", "animated", "too-large"])
    func unsafeImageWatermarksFailBeforeProcessingInputs(fault: String) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png()
        let original = try Data(contentsOf: source)
        var watermark = fixture.root.appendingPathComponent("mark.png")
        switch fault {
        case "link": try FileManager.default.createSymbolicLink(at: watermark, withDestinationURL: source)
        case "directory": watermark = fixture.root
        case "unsupported":
            watermark = fixture.root.appendingPathComponent("mark.txt")
            try original.write(to: watermark)
        case "malformed": try Data("broken png".utf8).write(to: watermark)
        case "disguised": try Data("<svg><image href='https://example.com/private'/></svg>".utf8).write(to: watermark)
        case "animated": try ImageProcessingServiceTests.Fixture.writeImage(to: watermark, delays: [0.1, 0.2])
        default:
            try Data([1]).write(to: watermark)
            let handle = try FileHandle(forWritingTo: watermark)
            try handle.truncate(atOffset: 500 * 1_024 * 1_024 + 1)
            try handle.close()
        }
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, _, _, _ in
            Issue.record("Unsafe watermark must not start an encoder")
            return .init(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        await #expect(throws: (any Error).self) { try await service.process([source], options: .init(watermark: .init(content: .image(watermark)))) }
        #expect(try Data(contentsOf: source) == original)
    }

    @Test
    func watermarkPreventsTheNativeRasterShortcutWithoutItsRequiredEngine() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png()
        do {
            let batch = try await ImageProcessingService(executableURL: nil).process([source], options: .init(watermark: .init(content: .text("Zisla"))),
                rasterTransform: { image, _ in image })
            defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
            Issue.record("Watermarked raster edits require the composition engine")
        } catch {
            #expect(error as? ImageProcessingError == .engineUnavailable)
        }
    }

    @Test
    func largerWatermarkedOutputNeverCopiesBackTheUneditedOriginal() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png()
        let original = try Data(contentsOf: source)
        let expected = try Pixels.solid(width: 40, height: 20, red: 255)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, _, _ in
            if arguments[0] == "composite2" { try ImageTransformTests.Pixels.write(expected, to: URL(fileURLWithPath: arguments[3])) }
            else {
                try FileManager.default.copyItem(atPath: arguments[1].replacingOccurrences(of: "[fail-on=error]", with: ""), toPath: arguments[2])
                if arguments[0] == "pngsave" {
                    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: arguments[2]))
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(repeating: 0, count: 4_096))
                    try handle.close()
                }
            }
            return .init(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        let batch = try await service.process([source], options: .init(preserveMetadata: true, watermark: .init(content: .text("Zisla"))))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.fileSize > original.count)
        #expect(try ImageTransformTests.Pixels.bytes(Pixels.load(output.url)) == ImageTransformTests.Pixels.bytes(expected))
        #expect(try Data(contentsOf: source) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.url.deletingLastPathComponent().path).sorted() == ["output.png", "source.png"])
    }

    @Test(arguments: ["failure", "timeout", "cancel"])
    func watermarkCompositionFailuresCleanEveryOwnedIntermediate(fault: String) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png()
        let original = try Data(contentsOf: source)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, work, _ in
            if arguments[0] == "composite2" {
                try work.deletingLastPathComponent().path.write(to: fixture.root.appendingPathComponent("batch-path"), atomically: true, encoding: .utf8)
                if fault == "cancel" { throw CancellationError() }
                return .init(status: 1, standardOutput: Data(), standardError: "disk full", didTimeout: fault == "timeout")
            }
            try FileManager.default.copyItem(atPath: arguments[1].replacingOccurrences(of: "[fail-on=error]", with: ""), toPath: arguments[2])
            return .init(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        if fault == "cancel" {
            await #expect(throws: CancellationError.self) { try await service.process([source], options: .init(watermark: .init(content: .text("Zisla")))) }
            let path = try String(contentsOf: fixture.root.appendingPathComponent("batch-path"), encoding: .utf8)
            #expect(!FileManager.default.fileExists(atPath: path))
        } else {
            let batch = try await service.process([source], options: .init(watermark: .init(content: .text("Zisla"))))
            defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
            #expect(batch.items.isEmpty && batch.failures.count == 1)
            #expect(try FileManager.default.contentsOfDirectory(atPath: batch.directoryURL.path).isEmpty)
            #expect(batch.failures[0].message == ImageProcessingError.processingFailed(fault == "timeout" ? AppLocalization.text("转换超时") : "disk full").localizedDescription)
        }
        #expect(try Data(contentsOf: source) == original)
    }

    struct Pixels {
        static func solid(width: Int, height: Int, red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0, alpha: UInt8 = 255) throws -> CGImage {
            let bytes = [red, green, blue].map { UInt8(Int($0) * Int(alpha) / 255) } + [alpha]
            return try ImageTransformTests.Pixels.make(width: width, height: height,
                bytes: Array(repeating: bytes, count: width * height).flatMap { $0 })
        }

        static func load(_ url: URL, index: Int = 0) throws -> CGImage {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            return try #require(CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary))
        }

        static func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
            let bytes = try ImageTransformTests.Pixels.bytes(image)
            let offset = (y * image.width + x) * 4
            return Array(bytes[offset..<offset + 4])
        }
    }
}
