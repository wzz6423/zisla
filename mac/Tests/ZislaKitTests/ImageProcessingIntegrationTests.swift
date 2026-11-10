import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ZislaKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ZISLA_IMAGE_TOOLS_INTEGRATION"] == "1"))
struct ImageProcessingIntegrationTests {
    #if arch(arm64)
    private let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/vips"),
                                                avifExecutableURL: URL(fileURLWithPath: "/opt/homebrew/bin/avifenc"))
    #else
    private let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/local/bin/vips"),
                                                avifExecutableURL: URL(fileURLWithPath: "/usr/local/bin/avifenc"))
    #endif

    @Test
    func convertsAllFiveFormatsAndKeepsOriginalBytes() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 128, height: 96)
        let original = try Data(contentsOf: source)
        let batch = try await service.process([source], options: .init(formats: ImageOutputFormat.conversionFormats))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let item = try #require(batch.items.first)
        #expect(Set(item.outputs.map(\.format)) == Set(ImageOutputFormat.conversionFormats))
        for output in item.outputs {
            #expect(FileManager.default.fileExists(atPath: output.url.path))
            #expect(output.summary.width == 128)
            #expect(output.summary.height == 96)
            #expect(output.summary.frameCount == 1)
            #expect(output.summary.fileSize > 0)
            #expect(try await service.preview(output.url).count > 0)
        }
        #expect(try Data(contentsOf: source) == original)
    }

    @Test(arguments: [ImageResizeMethod.fit, .scale, .cover, .thumb])
    func resizeProducesExpectedDimensionsWithoutUpscaling(method: ImageResizeMethod) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 100, height: 50)
        let resize = ImageResizeOptions(method: method, width: 40, height: method == .scale ? nil : 40)
        let batch = try await service.process([source], options: .init(resize: resize))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.width == 40)
        #expect(output.summary.height == (method == .fit || method == .scale ? 20 : 40))
    }

    @Test
    func largerFitKeepsOriginalDimensionsAndThumbAddsBackground() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 40, height: 20)
        for method in [ImageResizeMethod.fit, .thumb] {
            let batch = try await service.process([source], options: .init(resize: .init(method: method, width: 80, height: 80), background: "#000000"))
            defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
            #expect(batch.failures.isEmpty, "\(batch.failures)")
            let output = try #require(batch.items.first?.outputs.first)
            #expect(output.summary.width == (method == .fit ? 40 : 80))
            #expect(output.summary.height == (method == .fit ? 20 : 80))
        }
    }

    @Test
    func animatedPNGPreservesLoopDelaysDimensionsAndTransparency() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 80, height: 40, delays: [0.08, 0.25])
        let batch = try await service.process([source], options: .init(resize: .init(method: .fit, width: 40, height: 40)))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.frameCount == 2)
        #expect(output.summary.width == 40)
        #expect(output.summary.height == 20)
        let imageSource = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyProperties(imageSource, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyAPNGLoopCount] as? Int == 3)
        for (index, delay) in [0.08, 0.25].enumerated() {
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any])
            let png = try #require(properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])
            let savedDelay = try #require(png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
            #expect(abs(savedDelay - delay) < 0.001)
            #expect(properties[kCGImagePropertyHasAlpha] as? Bool == true)
        }
    }

    @Test
    func animationRoundTripsAcrossPNGWebPJPEGXLAndAVIFWithoutLosingFrames() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let original = try fixture.png(width: 80, height: 40, delays: [0.08, 0.25])
        var source = original
        for format in [ImageOutputFormat.webp, .jpegXL, .avif, .png] {
            let batch = try await service.process([source], options: .init(formats: [format], resize: .init(method: .thumb, width: 40, height: 40)))
            defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
            #expect(batch.failures.isEmpty, "\(batch.failures)")
            let output = try #require(batch.items.first?.outputs.first)
            #expect(output.summary.width == 40)
            #expect(output.summary.height == 40)
            #expect(output.summary.frameCount == 2)
            let copy = fixture.root.appendingPathComponent("converted.\(format.fileExtension)")
            try FileManager.default.copyItem(at: output.url, to: copy)
            source = copy
        }
        let imageSource = try #require(CGImageSourceCreateWithURL(source as CFURL, nil))
        let properties = try #require(CGImageSourceCopyProperties(imageSource, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyAPNGLoopCount] as? Int == 3)
        for (index, delay) in [0.08, 0.25].enumerated() {
            let frame = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any])
            let timing = try #require(frame[kCGImagePropertyPNGDictionary] as? [CFString: Any])
            let actual = try #require(timing[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
            #expect(abs(actual - delay) < 0.001)
        }
    }

    @Test
    func unsupportedAnimationTargetsFailInsteadOfReturningAStillFrame() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(delays: [0.1, 0.2])
        let batch = try await service.process([source], options: .init(formats: [.jpeg, .avif, .png]))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(Set(batch.items.first?.outputs.map(\.format) ?? []) == [.png, .avif])
        #expect(batch.failures.compactMap(\.format) == [.jpeg])
        #expect(try FileManager.default.contentsOfDirectory(atPath: batch.directoryURL.appendingPathComponent("0").path).sorted() == ["output.avif", "output.png", "source.png"])
    }

    @Test
    func heicInputConvertsToJPEG() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("source.heic")
        try ImageProcessingServiceTests.Fixture.writeImage(to: source, type: .heic, width: 80, height: 40)
        let bytes = try Data(contentsOf: source)
        let batch = try await service.process([source], options: .init())
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.format == .jpeg)
        #expect(output.summary.width == 80)
        #expect(output.summary.height == 40)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test(arguments: [false, true])
    func metadataChoiceProtectsGPSAndCopyrightWhileApplyingOrientation(preserve: Bool) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("metadata.jpg")
        try ImageProcessingServiceTests.Fixture.writeImage(to: source, type: .jpeg, width: 80, height: 40, metadata: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCopyright: "Fixture copyright"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.5, kCGImagePropertyGPSLatitudeRef: "N",
                                           kCGImagePropertyGPSLongitude: 22.5, kCGImagePropertyGPSLongitudeRef: "E"],
        ])
        let batch = try await service.process([source], options: .init(formats: [.png, .jpeg, .webp, .avif, .jpegXL], preserveMetadata: preserve))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        for output in try #require(batch.items.first).outputs {
            #expect(output.summary.width == 40)
            #expect(output.summary.height == 80)
            let imageSource = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
            let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            #expect((gps?[kCGImagePropertyGPSLatitude] as? Double == 12.5) == preserve)
            #expect(((tiff?[kCGImagePropertyTIFFCopyright] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == "Fixture copyright") == preserve)
            #expect((exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:01:02 03:04:05") == preserve)
            #expect(properties[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
        }
    }

    @Test(arguments: [false, true])
    func svgOptimizationKeepsVectorContentAndMetadataChoice(preserve: Bool) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("source.svg")
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="80" height="40" viewBox="0 0 80 40">
          <!-- \(String(repeating: "editor comment ", count: 40)) -->
          <metadata>Fixture copyright</metadata>
          <defs><linearGradient id="color"><stop stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs>
          <rect width="80" height="40" fill="url(#color)"/>
        </svg>
        """
        try Data(svg.utf8).write(to: source)
        let batch = try await service.process([source], options: .init(preserveMetadata: preserve))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.format == .svg)
        #expect(output.summary.width == 80 && output.summary.height == 40)
        #expect(output.summary.fileSize < batch.items.first!.summary.fileSize)
        let text = try String(contentsOf: output.url, encoding: .utf8)
        #expect(text.contains("<rect"))
        #expect(text.contains("url(#color)"))
        #expect(!text.contains("editor comment"))
        #expect(text.contains("Fixture copyright") == preserve)
        #expect(try await service.preview(output.url).count > 0)
        let converted = try await service.process([source], options: .init(formats: [.png], resize: .init(method: .fit, width: 40, height: 40)))
        defer { try? FileManager.default.removeItem(at: converted.directoryURL) }
        #expect(converted.failures.isEmpty, "\(converted.failures)")
        #expect(converted.items.first?.outputs.first?.summary.width == 40)
        #expect(converted.items.first?.outputs.first?.summary.height == 20)
        #expect(try String(contentsOf: source, encoding: .utf8) == svg)
    }

    @Test
    func truncatedInputCannotFallBackToTheOriginalAfterEncoding() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png()
        let original = try Data(contentsOf: source)
        try original.dropLast(18).write(to: source)
        let batch = try await service.process([source], options: .init())
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.items.isEmpty)
        #expect(batch.failures.count == 1)
        #expect(try Data(contentsOf: source) == original.dropLast(18))
    }

    @Test(arguments: [false, true])
    func compressionNeverEnlargesAnAlreadyOptimizedPNGUnlessRemovingMetadata(preserve: Bool) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 128, height: 96)
        let first = try await service.process([source], options: .init(preserveMetadata: preserve))
        defer { try? FileManager.default.removeItem(at: first.directoryURL) }
        let output = try #require(first.items.first?.outputs.first)
        let second = try await service.process([output.url], options: .init(preserveMetadata: preserve))
        defer { try? FileManager.default.removeItem(at: second.directoryURL) }
        #expect(second.failures.isEmpty, "\(second.failures)")
        let recompressed = try #require(second.items.first?.outputs.first)
        #expect(recompressed.summary.fileSize <= output.summary.fileSize)
    }

    @Test
    func smallestUsesTheMeasuredSizeAndDeletesOtherFormats() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 120, height: 80)
        let all = try await service.process([source], options: .init(formats: ImageOutputFormat.conversionFormats))
        defer { try? FileManager.default.removeItem(at: all.directoryURL) }
        let smallest = try await service.process([source], options: .init(formats: ImageOutputFormat.conversionFormats, smallestOnly: true))
        defer { try? FileManager.default.removeItem(at: smallest.directoryURL) }
        #expect(all.failures.isEmpty)
        #expect(smallest.failures.isEmpty)
        let output = try #require(smallest.items.first?.outputs.first)
        #expect(smallest.items.first?.outputs.count == 1)
        #expect(output.summary.fileSize == all.items.first?.smallest?.summary.fileSize)
        #expect(output.format == all.items.first?.smallest?.format)
    }

    @Test
    func jpegFillsTransparentPixelsWithTheChosenBackground() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 80, height: 40)
        let batch = try await service.process([source], options: .init(formats: [.jpeg], background: "#FF0000"))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        let output = try #require(batch.items.first?.outputs.first)
        let imageSource = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        #expect(pixels[0] > 220)
        #expect(pixels[1] < 40)
        #expect(pixels[2] < 40)
    }
}
