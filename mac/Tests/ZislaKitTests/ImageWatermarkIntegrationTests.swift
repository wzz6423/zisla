import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ZislaKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ZISLA_IMAGE_TOOLS_INTEGRATION"] == "1"))
struct ImageWatermarkIntegrationTests {
    #if arch(arm64)
    private let executable = URL(fileURLWithPath: "/opt/homebrew/bin/vips")
    #else
    private let executable = URL(fileURLWithPath: "/usr/local/bin/vips")
    #endif
    private var service: ImageProcessingService { ImageProcessingService(executableURL: executable,
        avifExecutableURL: executable.deletingLastPathComponent().appendingPathComponent("avifenc")) }

    @Test(arguments: ImageWatermarkPosition.allCases)
    func imageWatermarkCompositesAfterTransformAndResizeWithoutChangingTheSource(position: ImageWatermarkPosition) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = fixture.root.appendingPathComponent("input.png")
        let watermark = fixture.root.appendingPathComponent("-[Q=1] $(touch owned).png")
        try ImageTransformTests.Pixels.write(ImageWatermarkTests.Pixels.solid(width: 120, height: 80), to: input)
        try ImageTransformTests.Pixels.write(ImageWatermarkTests.Pixels.solid(width: 20, height: 10, red: 255, alpha: 128), to: watermark)
        let original = try Data(contentsOf: input)
        let originalWatermark = try Data(contentsOf: watermark)
        let options = ImageWatermarkOptions(content: .image(watermark), opacity: 0.5, scale: 0.25, position: position)
        let batch = try await service.process([input], options: .init(quality: 100,
            resize: .init(method: .fit, width: 40, height: 80), transform: .init(rotation: .clockwise90, flipHorizontal: true), watermark: options))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.width == 40 && output.summary.height == 60)
        let image = try ImageWatermarkTests.Pixels.load(output.url)
        let overlay = try ImageWatermarkRenderer(options: options, content: .image(ImageWatermarkTests.Pixels.load(watermark)))
            .render(width: 40, height: 60, to: fixture.root.appendingPathComponent("expected.png"))
        let pixel = try ImageWatermarkTests.Pixels.pixel(image, x: overlay.x + 5, y: overlay.y + 2)
        #expect(abs(Int(pixel[0]) - 64) <= 2 && pixel[1] <= 1 && pixel[2] <= 1 && pixel[3] == 255)
        let outside = try ImageWatermarkTests.Pixels.pixel(image, x: position == .center ? 0 : 20, y: 30)
        #expect(outside == [0, 0, 0, 255])
        #expect(try Data(contentsOf: input) == original)
        #expect(try Data(contentsOf: watermark) == originalWatermark)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("owned").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.url.deletingLastPathComponent().path).sorted() == ["output.png", "source.png"])
    }

    @Test
    func transparentBaseRetainsAlphaAndOrientedWatermarkIsUpright() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = fixture.root.appendingPathComponent("input.png")
        let watermark = fixture.root.appendingPathComponent("oriented.png")
        try ImageTransformTests.Pixels.write(ImageWatermarkTests.Pixels.solid(width: 80, height: 40, alpha: 0), to: input)
        try ImageTransformTests.Pixels.write(ImageWatermarkTests.Pixels.solid(width: 10, height: 20, red: 255, alpha: 128), to: watermark,
            properties: [kCGImagePropertyOrientation: 6])
        let batch = try await service.process([input], options: .init(quality: 100,
            watermark: .init(content: .image(watermark), opacity: 0.5, scale: 0.25, position: .topLeft)))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let image = try ImageWatermarkTests.Pixels.load(try #require(batch.items.first?.outputs.first).url)
        let marked = try ImageWatermarkTests.Pixels.pixel(image, x: 10, y: 5)
        #expect(abs(Int(marked[0]) - 64) <= 2 && abs(Int(marked[3]) - 64) <= 2)
        #expect(try ImageWatermarkTests.Pixels.pixel(image, x: 10, y: 16) == [0, 0, 0, 0])
        #expect(try ImageWatermarkTests.Pixels.pixel(image, x: 70, y: 30) == [0, 0, 0, 0])
    }

    @Test
    func everyAnimationFrameHasTheSameWatermarkPositionDelayLoopAndAlpha() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = try fixture.png(width: 80, height: 40, delays: [0.08, 0.25])
        let watermark = fixture.root.appendingPathComponent("mark.png")
        try ImageTransformTests.Pixels.write(ImageWatermarkTests.Pixels.solid(width: 12, height: 6, red: 255), to: watermark)
        let original = try Data(contentsOf: input)
        let batch = try await service.process([input], options: .init(quality: 100,
            watermark: .init(content: .image(watermark), opacity: 1, scale: 0.25, position: .topLeft)))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.frameCount == 2)
        let decoded = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyProperties(decoded, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyAPNGLoopCount] as? Int == 3)
        for (index, delay) in [0.08, 0.25].enumerated() {
            let frame = try ImageWatermarkTests.Pixels.load(output.url, index: index)
            #expect(try ImageWatermarkTests.Pixels.pixel(frame, x: 6, y: 6) == [255, 0, 0, 255])
            #expect(try ImageWatermarkTests.Pixels.pixel(frame, x: 70, y: 30)[3] == 128)
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, index, nil) as? [CFString: Any])
            let png = try #require(properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])
            #expect(abs(try #require(png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double) - delay) < 0.001)
        }
        #expect(try Data(contentsOf: input) == original)
    }

    @Test(arguments: [ImageOutputFormat.webp, .avif, .jpegXL])
    func animatedWatermarksRoundTripOtherFormatsWithoutLosingFramesOrTiming(format: ImageOutputFormat) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 80, height: 40, delays: [0.08, 0.25])
        let batch = try await service.process([source], options: .init(formats: [format], quality: 100,
            watermark: .init(content: .text("Zisla"), opacity: 1, scale: 0.7, position: .topLeft, color: "#FF0000")))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.frameCount == 2 && output.summary.width == 80 && output.summary.height == 40)
        let restored = try await service.process([output.url], options: .init(formats: [.png], quality: 100))
        defer { try? FileManager.default.removeItem(at: restored.directoryURL) }
        #expect(restored.failures.isEmpty, "\(restored.failures)")
        let decodedURL = try #require(restored.items.first?.outputs.first).url
        let decoded = try #require(CGImageSourceCreateWithURL(decodedURL as CFURL, nil))
        let properties = try #require(CGImageSourceCopyProperties(decoded, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyAPNGLoopCount] as? Int == 3)
        for (index, delay) in [0.08, 0.25].enumerated() {
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, index, nil) as? [CFString: Any])
            let png = try #require(properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])
            #expect(abs(try #require(png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double) - delay) < 0.001)
            let frame = try ImageWatermarkTests.Pixels.load(decodedURL, index: index)
            let bytes = try ImageTransformTests.Pixels.bytes(frame)
            #expect(stride(from: 0, to: min(80 * 20 * 4, bytes.count), by: 4).contains { bytes[$0] > 200 && bytes[$0 + 1] < 40 && bytes[$0 + 2] < 40 })
        }
    }

    @Test(arguments: [false, true])
    func watermarkPreservesOrStripsGPSCopyrightAndCaptureTimeAsSelected(preserve: Bool) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = fixture.root.appendingPathComponent("metadata.jpg")
        try ImageProcessingServiceTests.Fixture.writeImage(to: input, type: .jpeg, width: 100, height: 80, metadata: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCopyright: "Fixture copyright"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.5, kCGImagePropertyGPSLatitudeRef: "N"],
        ])
        let original = try Data(contentsOf: input)
        let batch = try await service.process([input], options: .init(quality: 100, preserveMetadata: preserve,
            watermark: .init(content: .text("© Zisla"), opacity: 1, color: "#FF0000")))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.width == 80 && output.summary.height == 100)
        let decoded = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
        #expect(((properties[kCGImagePropertyGPSDictionary] as? [CFString: Any])?[kCGImagePropertyGPSLatitude] as? Double == 12.5) == preserve)
        #expect(((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCopyright] as? String == "Fixture copyright") == preserve)
        #expect(((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:01:02 03:04:05") == preserve)
        #expect(properties[kCGImagePropertyProfileName] != nil)
        #expect(try Data(contentsOf: input) == original)
    }

    @Test
    func SVGWatermarkDefaultsToPNGAndExplicitVectorOutputFails() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = fixture.root.appendingPathComponent("source.svg")
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='100' height='80'><rect width='100' height='80' fill='black'/></svg>"
        try Data(svg.utf8).write(to: input)
        let watermark = ImageWatermarkOptions(content: .text("Zisla"), opacity: 1, scale: 0.6, position: .center)
        let batch = try await service.process([input], options: .init(quality: 100, watermark: watermark))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.format == .png && output.summary.width == 100 && output.summary.height == 80)
        #expect(try ImageTransformTests.Pixels.bytes(ImageWatermarkTests.Pixels.load(output.url)).contains { $0 > 200 })
        let failed = try await service.process([input], options: .init(formats: [.svg], watermark: watermark))
        defer { try? FileManager.default.removeItem(at: failed.directoryURL) }
        #expect(failed.items.isEmpty && failed.failures.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: failed.directoryURL.path).isEmpty)
        #expect(try String(contentsOf: input, encoding: .utf8) == svg)
    }

    @Test
    func imageWatermarkIsLoadedOnceForTheBatchAndShellLikeNamesAndTextRemainLiteral() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let first = try fixture.png(name: "first.png")
        let second = try fixture.png(name: "second.png")
        let watermark = fixture.root.appendingPathComponent("-[Q=1] $(touch owned).png")
        try ImageTransformTests.Pixels.write(ImageWatermarkTests.Pixels.solid(width: 12, height: 6, red: 255), to: watermark)
        let service = ImageProcessingService(executableURL: executable) { executable, arguments, work, input in
            #expect(!arguments.contains { $0.contains("$(touch") || $0.contains("[Q=1]") || $0.contains("<span") })
            if work.lastPathComponent == "0", arguments[0] == "composite2", FileManager.default.fileExists(atPath: watermark.path) {
                try FileManager.default.removeItem(at: watermark)
            }
            var environment = ProcessInfo.processInfo.environment
            environment["LC_ALL"] = "C"
            return try await AIAgentProcessRunner.run(executableURL: executable, arguments: arguments, standardInput: input,
                environment: environment, workingDirectoryURL: work, timeout: 30)
        }
        let batch = try await service.process([first, second], options: .init(quality: 100,
            watermark: .init(content: .image(watermark), opacity: 1, scale: 0.5, position: .topLeft)))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty && batch.items.count == 2, "\(batch.failures)")
        for item in batch.items {
            let image = try ImageWatermarkTests.Pixels.load(try #require(item.outputs.first).url)
            #expect(try ImageWatermarkTests.Pixels.pixel(image, x: 6, y: 2) == [255, 0, 0, 255])
        }
        let literal = try await service.process([first], options: .init(watermark: .init(content: .text("<span color='red'>$(touch owned)</span>"))))
        defer { try? FileManager.default.removeItem(at: literal.directoryURL) }
        #expect(literal.failures.isEmpty && literal.items.count == 1, "\(literal.failures)")
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("owned").path))
    }
}
