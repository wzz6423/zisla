import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit

struct ImageTransformTests {
    @Test
    func existingOptionsKeepIdentityTransformAndRasterOperationsAreExplicit() {
        #expect(ImageProcessingOptions().transform.isIdentity)
        #expect(ImageTransformOptions.identity.rotation == .none)
        #expect(!ImageTransformOptions.identity.flipHorizontal)
        #expect(!ImageTransformOptions.identity.flipVertical)
        #expect(ImageRotation.allCases.map(\.rawValue) == [0, 90, 180, 270])
        #expect(ImageToolOperation.allCases.filter(\.requiresRasterEditing) == [.obscure, .extract])
    }

    @Test
    func rotationDimensionsFeedResizeAfterTheAxesAreSwapped() {
        let source = ImageFileSummary(width: 100, height: 40, frameCount: 2, fileSize: 1, format: .png, hasMetadata: false)
        for rotation in ImageRotation.allCases {
            let transform = ImageTransformOptions(rotation: rotation, flipHorizontal: true, flipVertical: true)
            let swapped = rotation == .clockwise90 || rotation == .clockwise270
            let options = ImageProcessingOptions(resize: .init(method: .fit, width: 30, height: 50), transform: transform)
            let size = options.dimensions(for: source)
            #expect(size.width == (swapped ? 20 : 30))
            #expect(size.height == (swapped ? 50 : 12))
        }
    }

    @Test
    func nativeRasterLoaderPreservesFullResolutionAndTransparentPixelsWithoutAnEngine() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("-[options] source.png")
        let image = try Pixels.image(width: 1600, height: 3)
        try Pixels.write(image, to: source)
        let original = try Data(contentsOf: source)
        let loaded = try await ImageProcessingService(executableURL: nil).loadRasterImage(source)
        #expect(loaded.width == 1600 && loaded.height == 3)
        #expect(try Data(contentsOf: source) == original)
        try FileManager.default.removeItem(at: source)
        #expect(try Pixels.bytes(loaded) == Pixels.bytes(image))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8])
    func nativeRasterLoaderAppliesAllEXIFOrientations(orientation: Int) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("orientation.png")
        let image = try Pixels.image(width: 6, height: 4)
        try Pixels.write(image, to: source, properties: [kCGImagePropertyOrientation: orientation])
        let loaded = try await ImageProcessingService(executableURL: nil).loadRasterImage(source)
        let expected = try Pixels.oriented(image, exif: orientation)
        #expect(loaded.width == expected.width && loaded.height == expected.height)
        #expect(try Pixels.bytes(loaded) == Pixels.bytes(expected), "EXIF orientation \(orientation) must transform the pixels")
    }

    @Test
    func nativeExternalEditProcessesEveryInputOnceAndPreservesTheOriginalForComparison() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let inputs = try [fixture.png(name: "one.png"), fixture.png(name: "two.png")]
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let replacement = try Pixels.image(width: 12, height: 8)
        let calls = CallbackCalls()
        let batch = try await ImageProcessingService(executableURL: nil).process(inputs, options: .init(), rasterTransform: { image, input in
            #expect(image.width == 40 && image.height == 20)
            await calls.record(input)
            return replacement
        })
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        #expect(batch.items.count == 2)
        #expect(await calls.inputs == inputs)
        for (index, item) in batch.items.enumerated() {
            #expect(item.inputURL == inputs[index])
            #expect(item.summary.width == 40 && item.summary.height == 20)
            #expect(try Data(contentsOf: item.sourceURL) == originals[index])
            let output = try #require(item.outputs.first)
            #expect(output.format == .png && output.summary.width == 12 && output.summary.height == 8)
            #expect(output.summary.frameCount == 1)
            let loaded = try await ImageProcessingService(executableURL: nil).loadRasterImage(output.url)
            #expect(try Pixels.bytes(loaded) == Pixels.bytes(replacement))
            #expect(try Data(contentsOf: inputs[index]) == originals[index])
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: output.url.deletingLastPathComponent().path)) == ["source.png", "output.png"])
        }
    }

    @Test(arguments: [[ImageOutputFormat](), [.png], [.png, .png]])
    func nativeExternalEditDefaultsToPNGForJPEGInputAndDeduplicatesPNGTargets(formats: [ImageOutputFormat]) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = fixture.root.appendingPathComponent("source.jpg")
        try ImageProcessingServiceTests.Fixture.writeImage(to: input, type: .jpeg)
        let original = try Data(contentsOf: input)
        let replacement = try Pixels.image(width: 12, height: 8)
        let batch = try await ImageProcessingService(executableURL: nil).process([input], options: .init(formats: formats),
            rasterTransform: { _, _ in replacement })
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let item = try #require(batch.items.first)
        #expect(item.summary.format == .jpeg)
        #expect(item.outputs.count == 1)
        let output = try #require(item.outputs.first)
        #expect(output.format == .png && output.summary.format == .png)
        #expect(output.url.lastPathComponent == "output.png")
        let loaded = try await ImageProcessingService(executableURL: nil).loadRasterImage(output.url)
        #expect(try Pixels.bytes(loaded) == Pixels.bytes(replacement))
        #expect(try Data(contentsOf: input) == original)
        #expect(try Data(contentsOf: item.sourceURL) == original)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: output.url.deletingLastPathComponent().path)) == ["source.jpg", "output.png"])
    }

    @Test(arguments: ["partial-write", "wrong-format"])
    func explicitRasterFormatFailureDoesNotReturnUnexpectedPNGOrRetainPartialFiles(fault: String) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = try fixture.png()
        let original = try Data(contentsOf: input)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, _, _ in
            let source = URL(fileURLWithPath: arguments[1].replacingOccurrences(of: "[fail-on=error]", with: ""))
            let output = URL(fileURLWithPath: arguments[2])
            if arguments[0] == "autorot" {
                try FileManager.default.copyItem(at: source, to: output)
            } else if arguments[0] == "jpegsave" {
                if fault == "partial-write" {
                    try Data([0xff, 0xd8, 0xff]).write(to: output)
                    return .init(status: 1, standardOutput: Data(), standardError: "disk full", didTimeout: false)
                }
                try FileManager.default.copyItem(at: source, to: output)
            } else {
                throw ImageProcessingError.processingFailed("Unexpected raster output format")
            }
            return .init(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        let batch = try await service.process([input], options: .init(formats: [.jpeg]), rasterTransform: { image, _ in image })
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.items.isEmpty)
        #expect(batch.failures.count == 1)
        let failure = try #require(batch.failures.first)
        #expect(failure.format == .jpeg)
        #expect(failure.message == (fault == "partial-write" ? ImageProcessingError.processingFailed("disk full") : .invalidOutput).localizedDescription)
        #expect(try FileManager.default.contentsOfDirectory(atPath: batch.directoryURL.path).isEmpty)
        #expect(try Data(contentsOf: input) == original)
    }

    @Test(arguments: [[ImageOutputFormat](), [.png], [.jpeg], [.svg], [.png, .jpeg]])
    func rasterMetadataRetentionIsRejectedBeforeEditingRegardlessOfOutputFormats(formats: [ImageOutputFormat]) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = try fixture.png()
        let original = try Data(contentsOf: input)
        await #expect(throws: ImageProcessingError.rasterEditingMetadataUnsupported) {
            try await ImageProcessingService(executableURL: nil).process([input], options: .init(formats: formats, preserveMetadata: true),
                rasterTransform: { image, _ in
                    Issue.record("Unsupported metadata retention must fail before editing")
                    return image
                })
        }
        #expect(try Data(contentsOf: input) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == ["source.png"])
    }

    @Test
    func externalEditReceivesAnUprightImageAndCannotRetainGPSMetadata() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = fixture.root.appendingPathComponent("rotated.png")
        let image = try Pixels.image(width: 6, height: 4)
        try Pixels.write(image, to: input, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.5, kCGImagePropertyGPSLatitudeRef: "N"],
        ])
        let original = try Data(contentsOf: input)
        let expectedBytes = try Pixels.bytes(Pixels.oriented(image, exif: 6))
        let originalLoaded = try await ImageProcessingService(executableURL: nil).loadRasterImage(input)
        #expect(originalLoaded.width == 4 && originalLoaded.height == 6)
        let batch = try await ImageProcessingService(executableURL: nil).process([input], options: .init(formats: [.png]), rasterTransform: { upright, url in
            #expect(url == input)
            #expect(upright.width == 4 && upright.height == 6)
            let actualBytes = try Pixels.bytes(upright)
            #expect(actualBytes == expectedBytes)
            return upright
        })
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        let decoded = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
        #expect(try Data(contentsOf: input) == original)
        await #expect(throws: ImageProcessingError.rasterEditingMetadataUnsupported) {
            try await ImageProcessingService(executableURL: nil).process([input], options: .init(preserveMetadata: true), rasterTransform: { image, _ in image })
        }
    }

    @Test
    func nativeExternalEditNeverCopiesBackAnUneditedSmallerOriginal() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = try fixture.png(width: 40, height: 20)
        let replacement = try Pixels.image(width: 40, height: 20)
        let original = try Data(contentsOf: input)
        let batch = try await ImageProcessingService(executableURL: nil).process([input], options: .init(), rasterTransform: { _, _ in replacement })
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.fileSize > original.count)
        let loaded = try await ImageProcessingService(executableURL: nil).loadRasterImage(output.url)
        #expect(try Pixels.bytes(loaded) == Pixels.bytes(replacement))
        #expect(try Data(contentsOf: input) == original)
    }

    @Test
    func largerRotatedOutputNeverFallsBackToOriginalPixels() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("source.png")
        let image = try Pixels.image(width: 6, height: 4)
        let transformed = try Pixels.oriented(image, exif: 3)
        try Pixels.write(image, to: source)
        let original = try Data(contentsOf: source)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, _, _ in
            let input = URL(fileURLWithPath: arguments[1].replacingOccurrences(of: "[fail-on=error]", with: ""))
            let output = URL(fileURLWithPath: arguments[2])
            if arguments[0] == "rot" { try Pixels.write(transformed, to: output) }
            else { try FileManager.default.copyItem(at: input, to: output) }
            if arguments[0] == "pngsave" {
                let handle = try FileHandle(forWritingTo: output)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(repeating: 0, count: 4096))
            }
            return .init(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        let batch = try await service.process([source], options: .init(preserveMetadata: true, transform: .init(rotation: .halfTurn)))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.isEmpty, "\(batch.failures)")
        let output = try #require(batch.items.first?.outputs.first)
        #expect(output.summary.fileSize > original.count)
        let decoded = try await ImageProcessingService(executableURL: nil).loadRasterImage(output.url)
        #expect(try Pixels.bytes(decoded) == Pixels.bytes(transformed))
        #expect(try Data(contentsOf: source) == original)
    }

    @Test(arguments: [[ImageOutputFormat](), [.png], [.jpeg, .png], [.svg]])
    func rasterLoaderAndExternalEditorRejectAnimationsBeforeReturningASingleFrame(formats: [ImageOutputFormat]) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = try fixture.png(delays: [0.1, 0.25])
        let original = try Data(contentsOf: input)
        let service = ImageProcessingService(executableURL: nil)
        await #expect(throws: ImageProcessingError.rasterEditingAnimationUnsupported) { try await service.loadRasterImage(input) }
        let processor = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, _, _, _ in
            Issue.record("Animated input must not reach a raster encoder")
            throw ImageProcessingError.invalidOutput
        }
        let batch = try await processor.process([input], options: .init(formats: formats), rasterTransform: { image, _ in
            Issue.record("Animated input must not invoke a single-frame editor")
            return image
        })
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.items.isEmpty)
        #expect(batch.failures.count == 1)
        #expect(batch.failures.first?.message == ImageProcessingError.rasterEditingAnimationUnsupported.localizedDescription)
        #expect(try FileManager.default.contentsOfDirectory(atPath: batch.directoryURL.path).isEmpty)
        #expect(try Data(contentsOf: input) == original)
    }

    @Test(arguments: ["remote", "link", "directory", "unsupported", "disguised", "truncated", "oversized-svg"])
    func rasterLoaderRejectsUnsafeInputWithoutStartingARenderer(fault: String) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let original = try fixture.png()
        let input: URL
        switch fault {
        case "remote": input = URL(string: "https://example.com/image.png")!
        case "link":
            input = fixture.root.appendingPathComponent("link.png")
            try FileManager.default.createSymbolicLink(at: input, withDestinationURL: original)
        case "directory": input = fixture.root
        case "unsupported":
            input = fixture.root.appendingPathComponent("source.txt")
            try FileManager.default.copyItem(at: original, to: input)
        case "disguised":
            input = fixture.root.appendingPathComponent("disguised.png")
            try Data("<svg><image href='https://example.com/private'/></svg>".utf8).write(to: input)
        case "truncated":
            input = fixture.root.appendingPathComponent("truncated.png")
            try Data(contentsOf: original).dropLast(18).write(to: input)
        default:
            input = fixture.root.appendingPathComponent("oversized.svg")
            try Data("<svg/>".utf8).write(to: input)
            let handle = try FileHandle(forWritingTo: input)
            try handle.truncate(atOffset: 20 * 1_024 * 1_024 + 1)
            try handle.close()
        }
        let bytes = try Data(contentsOf: original)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, _, _, _ in
            Issue.record("Rejected input must never reach a renderer")
            return .init(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        await #expect(throws: (any Error).self) { try await service.loadRasterImage(input) }
        #expect(try Data(contentsOf: original) == bytes)
    }

    @Test(arguments: ["unsafe-svg", "unsupported-animation", "too-many-pixels"])
    func rasterFallbackInspectionRejectsUnsafeOrExcessiveInputBeforeDecoding(fault: String) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = fixture.root.appendingPathComponent(fault == "unsafe-svg" ? "source.svg" : "source.jxl")
        try (fault == "unsafe-svg" ? Data("<svg><image href='file:///private'/></svg>".utf8) : Data([0xff, 0x0a])).write(to: input)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { executable, _, _, _ in
            #expect(executable.lastPathComponent == "vipsheader")
            let fields = fault == "too-many-pixels" ? "width: 16001\nheight: 16001\n" : "width: 6\nheight: 4\nn-pages: 2\nvips-loader: jxlload\n"
            return .init(status: 0, standardOutput: Data(fields.utf8), standardError: "", didTimeout: false)
        }
        await #expect(throws: (any Error).self) { try await service.loadRasterImage(input) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == [input.lastPathComponent])
    }

    @Test(arguments: ["success", "wrong-size", "wrong-type", "wrong-frames", "missing", "cancel"])
    func fullResolutionFallbackUsesOnlyGeneratedPathsAndCleansTemporaryFiles(fault: String) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = fixture.root.appendingPathComponent("-[Q=1] $(touch owned).svg")
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='6' height='4'><rect width='6' height='4' fill='red'/></svg>"
        try Data(svg.utf8).write(to: input)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { executable, arguments, directory, _ in
            #expect(!arguments.contains { $0.contains("$(touch") || $0.contains("[Q=1]") })
            #expect(arguments[1].hasPrefix(directory.path + "/source.svg") || arguments[0] != "-a")
            #expect((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int) == 0o700)
            if executable.lastPathComponent == "vipsheader" {
                return .init(status: 0, standardOutput: Data("width: 6\nheight: 4\nvips-loader: svgload\n".utf8), standardError: "", didTimeout: false)
            }
            try directory.path.write(to: fixture.root.appendingPathComponent("fallback-path"), atomically: true, encoding: .utf8)
            if fault == "cancel" { throw CancellationError() }
            if arguments[0] == "pngsave", fault != "missing" {
                let output = URL(fileURLWithPath: arguments[2])
                if fault == "wrong-type" { try ImageProcessingServiceTests.Fixture.writeImage(to: output, type: .jpeg, width: 6, height: 4) }
                else if fault == "wrong-frames" { try ImageProcessingServiceTests.Fixture.writeImage(to: output, width: 6, height: 4, delays: [0.1, 0.2]) }
                else { try Pixels.write(Pixels.image(width: fault == "wrong-size" ? 3 : 6, height: 4), to: output) }
            }
            return .init(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        if fault == "success" {
            let image = try await service.loadRasterImage(input)
            #expect(image.width == 6 && image.height == 4)
        } else if fault == "cancel" {
            await #expect(throws: CancellationError.self) { try await service.loadRasterImage(input) }
        } else {
            await #expect(throws: (any Error).self) { try await service.loadRasterImage(input) }
        }
        let path = try String(contentsOf: fixture.root.appendingPathComponent("fallback-path"), encoding: .utf8)
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(try String(contentsOf: input, encoding: .utf8) == svg)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("owned").path))
    }

    @Test
    func nativeExternalEditCancellationPreservesTheOriginalAndAllowsRetry() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = try fixture.png()
        let original = try Data(contentsOf: input)
        let service = ImageProcessingService(executableURL: nil)
        do {
            _ = try await service.process([input], options: .init(), rasterTransform: { _, _ in throw CancellationError() }, progress: { _, _ in
                Issue.record("Cancellation must not return completed progress")
            })
            Issue.record("Cancellation must propagate")
        } catch is CancellationError {}
        #expect(try Data(contentsOf: input) == original)
        let successful = try await service.process([input], options: .init(), rasterTransform: { image, _ in image })
        #expect(successful.items.count == 1)
        try FileManager.default.removeItem(at: successful.directoryURL)
    }

    @Test
    func cancelledRasterLoadStopsBeforeTouchingInvalidInput() async throws {
        let service = ImageProcessingService(executableURL: nil)
        let started = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in started.stream { break }
            return try await service.loadRasterImage(URL(string: "https://example.com/private.png")!)
        }
        task.cancel()
        started.continuation.yield(())
        started.continuation.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func failedExternalEditReturnsNoOutputsAndCanProcessTheNextImage() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let inputs = try [fixture.png(name: "broken-edit.png"), fixture.png(name: "valid-edit.png")]
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let batch = try await ImageProcessingService(executableURL: nil).process(inputs, options: .init(), rasterTransform: { image, input in
            if input == inputs[0] { throw ImageProcessingError.invalidOutput }
            return image
        })
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.failures.count == 1 && batch.failures.first?.inputURL == inputs[0])
        #expect(batch.items.count == 1 && batch.items.first?.inputURL == inputs[1])
        #expect(!FileManager.default.fileExists(atPath: batch.directoryURL.appendingPathComponent("0").path))
        #expect(try inputs.map { try Data(contentsOf: $0) } == originals)
    }

    @Test(arguments: [ImageProcessingOptions(formats: [.jpeg]), .init(formats: [.webp]), .init(formats: [.avif]),
                     .init(formats: [.jpegXL]), .init(formats: [.svg]), .init(formats: [.png, .jpeg, .png]),
                     .init(resize: .init(method: .fit, width: 20, height: 20)),
                      .init(transform: .init(rotation: .clockwise90))])
    func additionalEncodingOptionsStillRequireAnEngine(options: ImageProcessingOptions) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = try fixture.png()
        await #expect(throws: ImageProcessingError.engineUnavailable) {
            try await ImageProcessingService(executableURL: nil).process([input], options: options, rasterTransform: { image, _ in image })
        }
    }

    @Test(arguments: [(150_001, 1), (1, 150_001), (16_001, 16_001)])
    func excessiveEditorOutputIsRejectedBeforeWritingAndKeepsTheOriginal(size: (Int, Int)) async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = try fixture.png()
        let original = try Data(contentsOf: input)
        var callbacks = CGDataProviderDirectCallbacks(version: 0, getBytePointer: nil, releaseBytePointer: nil,
            getBytesAtPosition: { _, buffer, _, count in
                Issue.record("Excessive edited dimensions must be rejected before the pixel provider is read")
                buffer.initializeMemory(as: UInt8.self, repeating: 0, count: count)
                return count
            }, releaseInfo: nil)
        let provider = try #require(CGDataProvider(directInfo: nil, size: Int64(size.0 * size.1 * 4), callbacks: &callbacks))
        let excessive = try #require(CGImage(width: size.0, height: size.1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size.0 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let batch = try await ImageProcessingService(executableURL: nil).process([input], options: .init(), rasterTransform: { _, _ in excessive })
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.items.isEmpty && batch.failures.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: batch.directoryURL.path).isEmpty)
        #expect(try Data(contentsOf: input) == original)
    }

    @Test
    func pngChunkValidationAcceptsTrailingPaddingAndRejectsTruncatedPayloads() async throws {
        let fixture = try ImageProcessingServiceTests.Fixture()
        defer { fixture.remove() }
        let input = try fixture.png()
        let original = try Data(contentsOf: input)
        try (original + Data(repeating: 0, count: 128)).write(to: input)
        let loaded = try await ImageProcessingService(executableURL: nil).loadRasterImage(input)
        #expect(loaded.width == 40 && loaded.height == 20)
        try original.prefix(33).write(to: input)
        await #expect(throws: (any Error).self) { try await ImageProcessingService(executableURL: nil).loadRasterImage(input) }
        var oversizedChunk = original
        oversizedChunk.replaceSubrange(8..<12, with: [255, 255, 255, 255])
        try oversizedChunk.write(to: input)
        await #expect(throws: (any Error).self) { try await ImageProcessingService(executableURL: nil).loadRasterImage(input) }
    }

    private actor CallbackCalls {
        var inputs: [URL] = []
        func record(_ url: URL) { inputs.append(url) }
    }

    struct Pixels {
        static func image(width: Int, height: Int) throws -> CGImage {
            var data: [UInt8] = []
            for y in 0..<height {
                for x in 0..<width {
                    let alpha = UInt8((x + y).isMultiple(of: 3) ? 128 : 255)
                    data += [UInt8((x * 17 + y * 23) % Int(alpha)),
                             UInt8((x * 31 + y * 7) % Int(alpha)), UInt8((x * 13 + y * 41) % Int(alpha)), alpha]
                }
            }
            return try make(width: width, height: height, bytes: data)
        }

        static func make(width: Int, height: Int, bytes: [UInt8]) throws -> CGImage {
            let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
            return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }

        static func write(_ image: CGImage, to url: URL, properties: [CFString: Any] = [:]) throws {
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
        }

        static func bytes(_ image: CGImage) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try bytes.withUnsafeMutableBytes { data in
                let context = try #require(CGContext(data: data.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }

        static func oriented(_ image: CGImage, exif: Int) throws -> CGImage {
            let input = try bytes(image)
            let swapped = exif >= 5
            let width = swapped ? image.height : image.width
            let height = swapped ? image.width : image.height
            var output = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let destination: (Int, Int)
                    switch exif {
                    case 2: destination = (image.width - 1 - x, y)
                    case 3: destination = (image.width - 1 - x, image.height - 1 - y)
                    case 4: destination = (x, image.height - 1 - y)
                    case 5: destination = (y, x)
                    case 6: destination = (image.height - 1 - y, x)
                    case 7: destination = (image.height - 1 - y, image.width - 1 - x)
                    case 8: destination = (y, image.width - 1 - x)
                    default: destination = (x, y)
                    }
                    let start = (destination.1 * width + destination.0) * 4
                    output.replaceSubrange(start..<start + 4, with: input[(y * image.width + x) * 4..<(y * image.width + x + 1) * 4])
                }
            }
            return try make(width: width, height: height, bytes: output)
        }
    }
}
