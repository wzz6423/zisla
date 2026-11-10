import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit

struct ImageProcessingServiceTests {
    @Test(arguments: ["", "#FFF", "red", "#FF0000[Q=0]", "$(touch test)", "#GG0000"])
    func invalidBackgroundCannotBecomeAnEncoderArgument(background: String) {
        #expect(!ImageProcessingOptions(background: background).isValid)
    }

    @Test
    func resizeRejectsAmbiguousMissingAndExcessiveDimensions() {
        #expect(ImageResizeOptions(method: .scale, width: 120, height: nil).isValid)
        #expect(ImageResizeOptions(method: .scale, width: nil, height: 120).isValid)
        #expect(!ImageResizeOptions(method: .scale, width: 120, height: 120).isValid)
        #expect(!ImageResizeOptions(method: .scale, width: nil, height: nil).isValid)
        #expect(!ImageResizeOptions(method: .fit, width: 120, height: nil).isValid)
        #expect(!ImageResizeOptions(method: .thumb, width: 0, height: 100).isValid)
        #expect(!ImageResizeOptions(method: .cover, width: 150_000, height: 150_000).isValid)
        #expect(!ImageResizeOptions(method: .fit, width: Int.max, height: 100).isValid)
    }

    @Test
    func emptyInputsAndUnavailableEngineFailBeforeCreatingResults() async throws {
        await #expect(throws: ImageProcessingError.emptyInput) {
            try await ImageProcessingService(executableURL: nil).process([], options: .init())
        }
        await #expect(throws: ImageProcessingError.engineUnavailable) {
            try await ImageProcessingService(executableURL: nil).process([URL(fileURLWithPath: "/missing.png")], options: .init())
        }
        await #expect(throws: ImageProcessingError.invalidOptions) {
            try await ImageProcessingService(executableURL: nil).process([URL(fileURLWithPath: "/missing.png")], options: .init(quality: 0))
        }
    }

    @Test
    func unavailableAVIFEncoderReportsAnInstallableDependencyFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            avifExecutableURL: fixture.root.appendingPathComponent("missing-avifenc"))
        await #expect(throws: ImageProcessingError.avifEngineUnavailable) {
            try await service.run([], in: fixture.root, tool: "avifenc")
        }
    }

    @Test
    func collectsNestedFoldersDeduplicatesAndSkipsLinks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.png(name: "a.png")
        let nested = fixture.root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let second = nested.appendingPathComponent("b.HEIC")
        try Data([1]).write(to: second)
        try Data([1]).write(to: nested.appendingPathComponent("notes.txt"))
        let link = fixture.root.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        #expect(try ImageProcessingService.collectInputs([fixture.root, first]) == [first, second])
        #expect(throws: ImageProcessingError.invalidInput(link)) { try ImageProcessingService.collectInputs([link]) }
        let remote = URL(string: "https://example.com/photo.png")!
        #expect(throws: ImageProcessingError.invalidInput(remote)) { try ImageProcessingService.collectInputs([remote]) }
    }

    @Test
    func timeoutAndDependencyFailureAreReportedWithoutTouchingTheSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let input = try fixture.png()
        let original = try Data(contentsOf: input)
        for timedOut in [false, true] {
            let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, _, _, _ in
                AIAgentProcessOutput(status: timedOut ? 0 : 1, standardOutput: Data(), standardError: "disk full", didTimeout: timedOut)
            }
            let batch = try await service.process([input], options: .init(formats: [.png]))
            defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
            #expect(batch.items.isEmpty)
            #expect(batch.failures.count == 1)
            #expect(batch.failures[0].message == ImageProcessingError.processingFailed(timedOut ? AppLocalization.text("转换超时") : "disk full").localizedDescription)
            #expect(try Data(contentsOf: input) == original)
        }
    }

    @Test
    func cancellationRemovesAllOwnedIntermediateFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let input = try fixture.png()
        let original = try Data(contentsOf: input)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, _, work, _ in
            let batchDirectory = work.deletingLastPathComponent()
            try batchDirectory.path.write(to: fixture.root.appendingPathComponent("batch-path"), atomically: true, encoding: .utf8)
            throw CancellationError()
        }
        await #expect(throws: CancellationError.self) { try await service.process([input], options: .init()) }
        let path = try String(contentsOf: fixture.root.appendingPathComponent("batch-path"), encoding: .utf8)
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(try Data(contentsOf: input) == original)
    }

    @Test
    func enlargedCompressionKeepsTheOriginalOnlyWhenMetadataCanBeRetained() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("metadata.png")
        try Fixture.writeImage(to: source, metadata: [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCopyright: "Fixture copyright"]])
        let original = try Data(contentsOf: source)
        for preserve in [false, true] {
            let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, _, _ in
                if arguments[0] == "autorot" { try FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: arguments[2])) }
                else if arguments[0] == "pngsave" {
                    let output = URL(fileURLWithPath: arguments[2])
                    try Fixture.writeImage(to: output)
                    let handle = try FileHandle(forWritingTo: output)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(repeating: 0, count: 4_096))
                }
                return AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
            }
            let batch = try await service.process([source], options: .init(preserveMetadata: preserve))
            defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
            #expect(batch.failures.isEmpty)
            let output = try #require(batch.items.first?.outputs.first)
            #expect((try Data(contentsOf: output.url) == original) == preserve)
            let image = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any])
            #expect(((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCopyright] as? String == "Fixture copyright") == preserve)
        }
        #expect(try Data(contentsOf: source) == original)
    }

    @Test
    func safePathsAndSmallestSelectionAreObservableInTheOutputs() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let input = try fixture.png(name: "-[Q=1] $(touch owned).png")
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, work, _ in
            #expect(!arguments.contains { $0.contains("$(touch") || $0.contains("[Q=1]") })
            let operation = arguments[0]
            if operation == "autorot" {
                if FileManager.default.fileExists(atPath: arguments[2]) { try FileManager.default.removeItem(atPath: arguments[2]) }
                try FileManager.default.copyItem(atPath: arguments[1].replacingOccurrences(of: "[fail-on=error]", with: ""), toPath: arguments[2])
            } else if operation == "pngsave" {
                try FileManager.default.copyItem(atPath: arguments[1].replacingOccurrences(of: "[fail-on=error]", with: ""), toPath: arguments[2])
            } else if operation == "jpegsave" {
                try Fixture.writeImage(to: URL(fileURLWithPath: arguments[2]), type: .jpeg)
            }
            #expect(arguments.contains("--vips-concurrency=2"))
            #expect(arguments.contains("--vips-cache-max=0"))
            return AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        let batch = try await service.process([input], options: .init(formats: [.png, .jpeg], smallestOnly: true))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        let item = try #require(batch.items.first)
        #expect((try FileManager.default.attributesOfItem(atPath: batch.directoryURL.path)[.posixPermissions] as? Int) == 0o700)
        #expect(item.outputs.count == 1)
        #expect(item.outputs[0].format == .png)
        #expect(!FileManager.default.fileExists(atPath: item.sourceURL.deletingLastPathComponent().appendingPathComponent("output.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("owned").path))
        #expect(batch.failures.isEmpty)
    }

    @Test
    func exportDeduplicatesNamesAndPreflightsCollisions() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let output = try fixture.png()
        let summary = ImageFileSummary(width: 40, height: 20, frameCount: 1, fileSize: 100, format: .png, hasMetadata: false)
        let processed = ImageProcessedOutput(url: output, format: .png, summary: summary)
        let items = ["one", "two"].map {
            ImageProcessedItem(inputURL: fixture.root.appendingPathComponent("\($0)/same.png"), sourceURL: output,
                summary: summary, outputs: [processed])
        }
        let directory = fixture.root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = directory.appendingPathComponent("same-png-2.png")
        try Data([1, 2, 3]).write(to: existing)
        #expect(throws: ImageProcessingError.outputAlreadyExists(existing)) {
            try ImageProcessingService.export(items, to: directory, smallestOnly: false)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [existing.lastPathComponent])
        #expect(try Data(contentsOf: existing) == Data([1, 2, 3]))
        try FileManager.default.removeItem(at: existing)
        let exported = try ImageProcessingService.export(items, to: directory, smallestOnly: true)
        #expect(exported.map(\.lastPathComponent) == ["same-png.png", "same-png-2.png"])
        #expect(try Data(contentsOf: output) == Data(contentsOf: exported[0]))
    }

    @Test
    func failedExportRollsBackOnlyFilesFromThisExport() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.png()
        let summary = ImageFileSummary(width: 40, height: 20, frameCount: 1, fileSize: 100, format: .png, hasMetadata: false)
        let outputs = [source, fixture.root.appendingPathComponent("missing.jpg")].enumerated().map { index, url in
            ImageProcessedOutput(url: url, format: index == 0 ? .png : .jpeg, summary: summary)
        }
        let item = ImageProcessedItem(inputURL: source, sourceURL: source, summary: summary, outputs: outputs)
        let directory = fixture.root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let retained = directory.appendingPathComponent("retained.txt")
        try Data([1]).write(to: retained)
        #expect(throws: (any Error).self) { try ImageProcessingService.export([item], to: directory, smallestOnly: false) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [retained.lastPathComponent])
    }

    @Test
    func malformedImagesDoNotProduceSuccessfulResults() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let input = fixture.root.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: input)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, _, _, _ in
            AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        let batch = try await service.process([input], options: .init())
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.items.isEmpty)
        #expect(batch.failures.count == 1)
    }

    @Test(arguments: ["wrong-size", "wrong-type", "wrong-frames", "truncated", "missing"])
    func invalidEncoderOutputsAreRemovedAndNeverReturned(fault: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.png()
        let original = try Data(contentsOf: source)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, _, _ in
            if arguments[0] == "autorot" {
                try FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: arguments[2]))
            } else if arguments[0] == "pngsave" {
                let output = URL(fileURLWithPath: arguments[2])
                switch fault {
                case "wrong-size": try Fixture.writeImage(to: output, width: 20, height: 20)
                case "wrong-type": try Fixture.writeImage(to: output, type: .jpeg)
                case "wrong-frames": try Fixture.writeImage(to: output, delays: [0.1, 0.2])
                case "truncated": try original.prefix(33).write(to: output)
                default: break
                }
            }
            return AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        let batch = try await service.process([source], options: .init())
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.items.isEmpty)
        #expect(batch.failures.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: batch.directoryURL.path).isEmpty)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test
    func resourceLimitsRejectEncodedBombsBeforeStartingAnEncoder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("huge.jxl")
        try Data([0xff, 0x0a]).write(to: source)
        for fields in ["width: 2147483647\nheight: 1\n", "width: 16001\nheight: 16001\n", "width: 1\nheight: 1\nn-pages: 1001\n"] {
            let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { executable, _, _, _ in
                #expect(executable.lastPathComponent == "vipsheader")
                return AIAgentProcessOutput(status: 0, standardOutput: Data(fields.utf8), standardError: "", didTimeout: false)
            }
            await #expect(throws: ImageProcessingError.resourceLimit) { try await service.inspect(source) }
        }
        let input = try fixture.png(delays: [0.1, 0.2])
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, _, _, _ in
            Issue.record("An oversized animation canvas must be rejected before launching libvips")
            return AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        let batch = try await service.process([input], options: .init(resize: .init(method: .thumb, width: 16000, height: 16000)))
        defer { try? FileManager.default.removeItem(at: batch.directoryURL) }
        #expect(batch.items.isEmpty)
        #expect(batch.failures.count == 1)
    }

    @Test
    func exportRejectsDanglingLinksAndEmptyResultsWithoutSideEffects() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.png()
        let summary = ImageFileSummary(width: 40, height: 20, frameCount: 1, fileSize: 100, format: .png, hasMetadata: false)
        let item = ImageProcessedItem(inputURL: source, sourceURL: source, summary: summary,
            outputs: [ImageProcessedOutput(url: source, format: .png, summary: summary)])
        let folder = fixture.root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent("source-png.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.root.appendingPathComponent("missing"))
        #expect(throws: ImageProcessingError.outputAlreadyExists(link)) { try ImageProcessingService.export([item], to: folder, smallestOnly: false) }
        #expect(throws: ImageProcessingError.emptyInput) { try ImageProcessingService.export([], to: folder, smallestOnly: false) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [link.lastPathComponent])
    }

    @Test(arguments: ["<!DOCTYPE svg [<!ENTITY x SYSTEM 'file:///no-access'>]><svg>&x;</svg>",
                      "<svg><image href='https://example.com/private.png'/></svg>",
                      "<svg><style>@import 'https://example.com/a.css';</style></svg>",
                      "<svg><rect fill='url(file:///no-access)'/></svg>", "<svg onload='alert(1)'/>",
                      "<svg><script>secret()</script></svg>", "<?xml-stylesheet href='file:///no-access'?><svg/>",
                      "<svg><foreignObject/></svg>", "<svg><style>rect{fill:u\\72l(file:///no-access)}</style></svg>",
                      "<svg xml:base='https://example.com/'><use href='#shape'/></svg>"])
    func unsafeSVGIsRejectedBeforeAnyExternalToolCanReadIt(svg: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("source.svg")
        try Data(svg.utf8).write(to: source)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, _, _, _ in
            Issue.record("Unsafe SVG must not reach a renderer")
            return AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        await #expect(throws: ImageProcessingError.invalidInput(source)) { try await service.inspect(source) }
    }

    @Test
    func disguisedSVGNeverReachesTheRasterDecoder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("image.png")
        try Data("<svg><image href='https://example.com/private.png'/></svg>".utf8).write(to: source)
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, _, _, _ in
            Issue.record("Disguised SVG must be rejected before decoding")
            return AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        await #expect(throws: ImageProcessingError.invalidInput(source)) { try await service.inspect(source) }
    }

    @Test
    func resizeDimensionsRemainWithinBoundsForFixedInputCorpus() {
        for width in [1, 3, 79, 16000, 150000] {
            for height in [1, 8, 63, 2000] {
                let input = ImageFileSummary(width: width, height: height, frameCount: 1, fileSize: 1, format: .png, hasMetadata: false)
                for method in [ImageResizeMethod.scale, .fit, .cover, .thumb] {
                    let options = ImageResizeOptions(method: method, width: 100, height: method == .scale ? nil : 80)
                    let output = options.dimensions(for: input)
                    #expect(output.width > 0 && output.height > 0)
                    if method == .thumb { #expect(output.width == 100 && output.height == 80) }
                    else { #expect(output.width <= width && output.height <= height) }
                    if method != .scale { #expect(output.width <= 100 && output.height <= 80) }
                }
            }
        }
    }

    struct Fixture: Sendable {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-test-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
        func png(name: String = "source.png", width: Int = 40, height: Int = 20, delays: [Double] = []) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Self.writeImage(to: url, width: width, height: height, delays: delays)
            return url
        }
        static func writeImage(to url: URL, type: UTType = .png, width: Int = 40, height: Int = 20, delays: [Double] = [], metadata: [CFString: Any] = [:]) throws {
            let count = max(1, delays.count)
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, count, nil))
            if !delays.isEmpty {
                CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 3]] as CFDictionary)
            }
            for index in 0..<count {
                let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(CGColor(red: CGFloat(index % 2), green: 0.25, blue: 0.8, alpha: 0.5))
                context.fill(CGRect(x: 4, y: 4, width: width - 8, height: height - 8))
                var properties = metadata
                if !delays.isEmpty { properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyAPNGDelayTime: delays[index]] }
                CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties as CFDictionary)
            }
            #expect(CGImageDestinationFinalize(destination))
        }
    }
}
