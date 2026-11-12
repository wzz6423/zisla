import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ZislaKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ZISLA_IMAGE_TOOLS_INTEGRATION"] == "1"))
struct ImageTransformIntegrationTests {
    #if arch(arm64)
    private let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/vips"),
                                                avifExecutableURL: URL(fileURLWithPath: "/opt/homebrew/bin/avifenc"))
    #else
    private let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/local/bin/vips"),
                                                avifExecutableURL: URL(fileURLWithPath: "/usr/local/bin/avifenc"))
    #endif

    @Test(arguments: Array(0..<16))
    func rotationsAndBothMirrorsMovePixelsInTheDeclaredOrder(combination: Int) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("source.png")
        let image = try ImageTransformTests.Pixels.image(width: 6, height: 4)
        try ImageTransformTests.Pixels.write(image, to: source)
        let original = try Data(contentsOf: source)
        let options = transform(combination)
        let expected = try transformed(image, options: options)
        let batch = try await service.process([source], options: .init(quality: 100, transform: options))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let item = try #require(batch.items.first)
        #expect(item.summary.width == 6 && item.summary.height == 4)
        let output = try #require(item.outputs.first)
        #expect(output.summary.width == expected.width && output.summary.height == expected.height)
        let loaded = try await service.loadRasterImage(output.url)
        try expectPixels(loaded, expected: expected)
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: item.sourceURL) == original)
    }

    @Test(arguments: [2, 6, 8])
    func appliesEXIFOrientationBeforeUserRotationAndMirror(orientation: Int) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("orientation.png")
        let image = try ImageTransformTests.Pixels.image(width: 6, height: 4)
        try ImageTransformTests.Pixels.write(image, to: source, properties: [kCGImagePropertyOrientation: orientation])
        let original = try Data(contentsOf: source)
        let options = ImageTransformOptions(rotation: .clockwise90, flipHorizontal: true)
        let expected = try transformed(ImageTransformTests.Pixels.oriented(image, exif: orientation), options: options)
        let batch = try await service.process([source], options: .init(quality: 100, transform: options))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.width == expected.width && output.summary.height == expected.height)
        let loaded = try await service.loadRasterImage(output.url)
        try expectPixels(loaded, expected: expected)
        let decoded = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test(arguments: [ImageRotation.clockwise90, .clockwise270])
    func rotationPrecedesResizeForStaticAndAnimatedImages(rotation: ImageRotation) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        for delays in [[], [0.08, 0.25]] {
            let source = try fixture.png(name: delays.isEmpty ? "static.png" : "animated.png", width: 100, height: 40, delays: delays)
            let batch = try await service.process([source], options: .init(resize: .init(method: .fit, width: 30, height: 50), transform: .init(rotation: rotation)))
            defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
            #expect(batch.failures.isEmpty, "\(batch.failures)")
            let output = try #require(batch.items.first?.outputs.first)
            #expect(output.summary.width == 20 && output.summary.height == 50)
            #expect(output.summary.frameCount == max(1, delays.count))
        }
    }

    @Test
    func rotationAndMirrorsPreserveEveryAnimatedPNGFrameDelayLoopAndAlpha() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 40, height: 20, delays: [0.08, 0.25])
        let original = try Data(contentsOf: source)
        let options = ImageTransformOptions(rotation: .clockwise90, flipHorizontal: true, flipVertical: true)
        let batch = try await service.process([source], options: .init(quality: 100, transform: options))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.width == 20 && output.summary.height == 40 && output.summary.frameCount == 2)
        let decoded = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        let sourceFrames = try #require(CGImageSourceCreateWithURL(source as CFURL, nil))
        let properties = try #require(CGImageSourceCopyProperties(decoded, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyAPNGLoopCount] as? Int == 3)
        for (index, delay) in [0.08, 0.25].enumerated() {
            let saved = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, index, nil) as? [CFString: Any])
            let png = try #require(saved[kCGImagePropertyPNGDictionary] as? [CFString: Any])
            #expect(abs(try #require(png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double) - delay) < 0.001)
            #expect(saved[kCGImagePropertyHasAlpha] as? Bool == true)
            let frame = try #require(CGImageSourceCreateImageAtIndex(decoded, index, nil))
            let sourceFrame = try #require(CGImageSourceCreateImageAtIndex(sourceFrames, index, nil))
            try expectPixels(frame, expected: transformed(sourceFrame, options: options))
        }
        #expect(try Data(contentsOf: source) == original)
    }

    @Test(arguments: [ImageOutputFormat.webp, .avif, .jpegXL])
    func transformedAnimationsRoundTripOtherFormatsWithoutLosingFramesOrTiming(format: ImageOutputFormat) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 40, height: 20, delays: [0.08, 0.25])
        let batch = try await service.process([source], options: .init(formats: [format], quality: 100,
            transform: .init(rotation: .clockwise270, flipVertical: true)))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.width == 20 && output.summary.height == 40 && output.summary.frameCount == 2)
        let restored = try await service.process([output.url], options: .init(formats: [.png], quality: 100,
            transform: .init(rotation: .halfTurn, flipHorizontal: true)))
        defer { try? FileManager.default.removeItem(at: restored.directoryURL) }
        #expect(restored.failures.isEmpty, "\(restored.failures)")
        let restoredOutput = try #require(restored.items.first?.outputs.first)
        #expect(restoredOutput.summary.width == 20 && restoredOutput.summary.height == 40 && restoredOutput.summary.frameCount == 2)
        let decoded = try #require(CGImageSourceCreateWithURL(restoredOutput.url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyProperties(decoded, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyAPNGLoopCount] as? Int == 3)
        for (index, delay) in [0.08, 0.25].enumerated() {
            let saved = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, index, nil) as? [CFString: Any])
            let png = try #require(saved[kCGImagePropertyPNGDictionary] as? [CFString: Any])
            #expect(abs(try #require(png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double) - delay) < 0.001)
            #expect(saved[kCGImagePropertyHasAlpha] as? Bool == true)
        }
    }

    @Test
    func transformedSVGDefaultsToRasterPNGAndRejectsVectorOutput() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("source.svg")
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='30' height='20'><rect x='1' y='2' width='8' height='9' fill='red'/></svg>"
        try Data(svg.utf8).write(to: source)
        let loaded = try await service.loadRasterImage(source)
        #expect(loaded.width == 30 && loaded.height == 20)
        let options = ImageTransformOptions(rotation: .clockwise90, flipHorizontal: true)
        let batch = try await service.process([source], options: .init(quality: 100, transform: options))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.format == .png && output.summary.width == 20 && output.summary.height == 30)
        try expectPixels(try await service.loadRasterImage(output.url), expected: transformed(loaded, options: options))
        let invalid = try await service.process([source], options: .init(formats: [.svg], transform: options))
        defer { try? FileManager.default.removeItem(at: invalid.directoryURL) }
        #expect(invalid.items.isEmpty && invalid.failures.count == 1)
        #expect(try String(contentsOf: source, encoding: .utf8) == svg)
    }

    @Test
    func fullResolutionLoadSupportsAllConvertedFormatsAndHEIC() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = try fixture.png(width: 1600, height: 8)
        let batch = try await service.process([source], options: .init(formats: ImageOutputFormat.conversionFormats))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        for output in try #require(batch.items.first).outputs {
            let loaded = try await service.loadRasterImage(output.url)
            #expect(loaded.width == 1600 && loaded.height == 8)
        }
        let heic = fixture.root.appendingPathComponent("source.heic")
        try ImageProcessingServiceTests.Fixture.writeImage(to: heic, type: .heic, width: 1600, height: 8)
        let loaded = try await ImageProcessingService(executableURL: nil).loadRasterImage(heic)
        #expect(loaded.width == 1600 && loaded.height == 8)
    }

    @Test(arguments: [[ImageOutputFormat](), [.jpeg], [.png, .jpeg, .png, .webp], ImageOutputFormat.conversionFormats],
        [ImageTransformOptions.identity, .init(rotation: .clockwise90, flipHorizontal: true)])
    func rasterEditsHonorExplicitFormatsAndPreserveTransparencyOrJPEGBackground(formats: [ImageOutputFormat], transformation: ImageTransformOptions) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("source.jpg")
        try ImageProcessingServiceTests.Fixture.writeImage(to: source, type: .jpeg)
        let original = try Data(contentsOf: source)
        let replacement = try await service.loadRasterImage(fixture.png(name: "replacement.png", width: 80, height: 40))
        let expected = try transformed(replacement, options: transformation)
        let batch = try await service.process([source], options: .init(formats: formats, quality: 100,
            background: "#FF0000", transform: transformation), rasterTransform: { _, url in
                #expect(url == source)
                return replacement
            })
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let item = try #require(batch.items.first)
        let targets = formats.isEmpty ? [ImageOutputFormat.png] : Array(Set(formats)).sorted { $0.rawValue < $1.rawValue }
        #expect(item.outputs.map(\.format) == targets)
        #expect(item.summary.format == .jpeg && item.summary.width == 40 && item.summary.height == 20)
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: item.sourceURL) == original)
        for output in item.outputs {
            #expect(output.summary.format == output.format)
            #expect(output.summary.width == expected.width && output.summary.height == expected.height && output.summary.frameCount == 1)
            #expect(output.url.pathExtension == output.format.fileExtension)
            let loaded = try await service.loadRasterImage(output.url)
            let bytes = try ImageTransformTests.Pixels.bytes(loaded)
            if output.format == .jpeg {
                #expect(bytes[0] > 220 && bytes[1] < 40 && bytes[2] < 40 && bytes[3] == 255,
                    "JPEG must composite edited transparency against the selected red background")
            } else {
                #expect(bytes[3] == 0, "\(output.format.displayName) must retain the transparent edited border")
                if output.format == .png { try expectPixels(loaded, expected: expected) }
            }
        }
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: item.sourceURL.deletingLastPathComponent().path))
        #expect(files == Set(targets.map { "output.\($0.fileExtension)" } + ["source.jpg"]))
    }

    @Test(arguments: [[ImageOutputFormat](), [.jpeg], [.svg], [.png, .svg, .jpeg]])
    func rasterEditsOfSVGUseRequestedRasterTargetsAndReportVectorFailure(formats: [ImageOutputFormat]) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("source.svg")
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='30' height='20'><rect x='1' y='2' width='8' height='9' fill='red'/></svg>"
        try Data(svg.utf8).write(to: source)
        let batch = try await service.process([source], options: .init(formats: formats, quality: 100),
            rasterTransform: { image, _ in image })
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        let targets = formats.isEmpty ? [ImageOutputFormat.png] : Array(Set(formats)).filter { $0 != .svg }.sorted { $0.rawValue < $1.rawValue }
        #expect((batch.items.first?.outputs.map(\.format) ?? []) == targets)
        #expect(batch.failures.count == (formats.contains(.svg) ? 1 : 0))
        if formats.contains(.svg) {
            let failure = try #require(batch.failures.first)
            #expect(failure.format == .svg && failure.message == ImageProcessingError.invalidOptions.localizedDescription)
        }
        if targets.isEmpty {
            #expect(try FileManager.default.contentsOfDirectory(atPath: batch.directoryURL.path).isEmpty)
        } else {
            let item = try #require(batch.items.first)
            #expect(item.summary.format == .svg)
            #expect(try String(contentsOf: item.sourceURL, encoding: .utf8) == svg)
            for output in item.outputs {
                #expect(output.summary.format == output.format && output.summary.width == 30 && output.summary.height == 20)
            }
            let files = Set(try FileManager.default.contentsOfDirectory(atPath: item.sourceURL.deletingLastPathComponent().path))
            #expect(files == Set(targets.map { "output.\($0.fileExtension)" } + ["source.svg"]))
        }
        #expect(try String(contentsOf: source, encoding: .utf8) == svg)
    }

    private func transform(_ combination: Int) -> ImageTransformOptions {
        .init(rotation: ImageRotation.allCases[combination % 4], flipHorizontal: combination & 4 != 0, flipVertical: combination & 8 != 0)
    }

    private func transformed(_ image: CGImage, options: ImageTransformOptions) throws -> CGImage {
        let orientation: Int
        switch options.rotation {
        case .none: orientation = 1
        case .clockwise90: orientation = 6
        case .halfTurn: orientation = 3
        case .clockwise270: orientation = 8
        }
        var result = try ImageTransformTests.Pixels.oriented(image, exif: orientation)
        if options.flipHorizontal { result = try ImageTransformTests.Pixels.oriented(result, exif: 2) }
        if options.flipVertical { result = try ImageTransformTests.Pixels.oriented(result, exif: 4) }
        return result
    }

    private func expectPixels(_ actual: CGImage, expected: CGImage) throws {
        #expect(actual.width == expected.width && actual.height == expected.height)
        let output = try ImageTransformTests.Pixels.bytes(actual)
        let input = try ImageTransformTests.Pixels.bytes(expected)
        #expect(output.count == input.count)
        let maximumDifference = zip(output, input).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(maximumDifference <= 2, "Rotations and mirrors must preserve colors and transparency (largest channel difference: \(maximumDifference))")
    }
}
