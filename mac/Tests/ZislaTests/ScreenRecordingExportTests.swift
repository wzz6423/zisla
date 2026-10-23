import AVFoundation
import CoreImage
import ImageIO
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingExportTests {
    @Test
    func timelinePreservesAuthoredOrderRepetitionAndSpeed() throws {
        var project = Self.project(duration: 10)
        project.edits.segments = [
            .init(start: 7, end: 9, speed: 2),
            .init(start: 1, end: 3, speed: 0.5),
            .init(start: 7, end: 9),
        ]
        let timeline = try RecordingExportTimeline(project: project)
        #expect(timeline.duration == 7)
        #expect(timeline.slice(at: 0)?.sourceTime(at: 0) == 7)
        #expect(timeline.slice(at: 1)?.sourceTime(at: 1) == 1)
        #expect(timeline.slice(at: 3)?.sourceTime(at: 3) == 2)
        #expect(timeline.slice(at: 5)?.sourceTime(at: 5) == 7)
        #expect(timeline.slice(at: 7) == nil)
        #expect(timeline.slice(at: -0.01) == nil)
        project.edits.segments = []
        #expect(throws: ScreenRecordingExportError.emptyTimeline) { try RecordingExportTimeline(project: project) }
    }

    @Test
    func frameScheduleUsesGlobalGridWithExactAndPartialTail() throws {
        let config = RecordingExportConfiguration(frameRate: 30)
        #expect(try RecordingExportFrameSchedule(duration: 1, configuration: config).frameCount == 30)
        #expect(try RecordingExportFrameSchedule(duration: 1 + 1.0 / 60_000, configuration: config).frameCount == 31)
        #expect(try RecordingExportFrameSchedule(duration: 0.2, configuration: config).time(at: 4).seconds == 4.0 / 30)
        for rate in [0, -1, 61, Int.max] {
            #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
                try RecordingExportFrameSchedule(duration: 1, configuration: .init(frameRate: rate))
            }
        }
        #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
            try RecordingExportFrameSchedule(duration: 1, configuration: .init(format: .gif, frameRate: 60))
        }
    }

    @Test
    func resolutionsMaintainCroppedAspectAndEvenPixels() throws {
        var edits = RecordingEdits()
        edits.crop = .init(x: 0, y: 0, width: 0.5, height: 1)
        let source = CGSize(width: 2_560, height: 1_440)
        #expect(try RecordingExportRenderer.outputSize(source: source, edits: edits, resolution: .source)
                == CGSize(width: 1_280, height: 1_440))
        let fullHD = try RecordingExportRenderer.outputSize(source: source, edits: edits, resolution: .fullHD)
        #expect(fullHD.height == 1_920)
        #expect(Int(fullHD.width).isMultiple(of: 2))
        #expect(abs(fullHD.width / fullHD.height - 1_280.0 / 1_440) < 0.001)
        #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
            try RecordingExportRenderer.outputSize(source: .init(width: 0, height: 10), edits: edits, resolution: .source)
        }
        for source in [CGSize(width: CGFloat.nan, height: 100), CGSize(width: 20_000, height: 20_000),
                       CGSize(width: 100_000, height: 100)] {
            #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
                try RecordingExportRenderer.outputSize(source: source, edits: edits, resolution: .source)
            }
        }
    }

    @Test
    func cropUsesTopLeftCoordinatesAndZoomKeepsViewportInBounds() throws {
        var project = Self.project()
        project.edits.crop = .init(x: 0, y: 0, width: 0.5, height: 0.5)
        let renderer = try RecordingExportRenderer(project: project, size: CGSize(width: 80, height: 60))
        let source = Self.quadrants(size: CGSize(width: 160, height: 120))
        let image = try renderer.image(screen: source, camera: nil, sourceTime: 0)
        let pixel = try Self.pixel(image, x: 40, y: 30)
        #expect(pixel.red > 0.85 && pixel.green < 0.1 && pixel.blue < 0.1,
                "Top-left crop must show the red source quadrant")
        let crop = CGRect(x: 40, y: 20, width: 80, height: 60)
        for (x, y) in [0.0, 0.5, 1].flatMap({ x in [0.0, 0.5, 1].map { (x, $0) } }) {
            let viewport = RecordingExportRenderer.viewport(crop: crop, zoom: .init(scale: 5, x: x, y: y),
                                                            source: .init(width: 160, height: 120))
            #expect(crop.contains(viewport))
            #expect(viewport.width == 16)
            #expect(viewport.height == 12)
        }
    }

    @Test
    func cameraMirrorAndAllAnchorsProduceVisiblePictureInPicture() throws {
        let size = CGSize(width: 200, height: 160)
        var project = Self.project()
        project.edits.cameraRound = false
        project.edits.cameraSize = 0.5
        project.edits.cameraPosition = .topLeft
        let screen = Self.solid(red: 0, green: 0, blue: 0, size: size)
        let camera = Self.quadrants(size: CGSize(width: 100, height: 100))
        project.edits.cameraMirrored = false
        let plain = try RecordingExportRenderer(project: project, size: size)
            .image(screen: screen, camera: camera, sourceTime: 0)
        project.edits.cameraMirrored = true
        let mirrored = try RecordingExportRenderer(project: project, size: size)
            .image(screen: screen, camera: camera, sourceTime: 0)
        let left = try Self.pixel(plain, x: 24, y: 20)
        let right = try Self.pixel(mirrored, x: 24, y: 20)
        #expect(left.red > 0.8 && left.green < 0.1)
        #expect(right.green > 0.8 && right.red < 0.1)
        for position in RecordingCameraPosition.allCases {
            project.edits.cameraPosition = position
            let image = try RecordingExportRenderer(project: project, size: size)
                .image(screen: screen, camera: Self.solid(red: 1, green: 1, blue: 1, size: size), sourceTime: 0)
            let point: CGPoint
            switch position {
            case .topLeft: point = .init(x: 44, y: 44)
            case .topRight: point = .init(x: 156, y: 44)
            case .bottomLeft: point = .init(x: 44, y: 116)
            case .bottomRight: point = .init(x: 156, y: 116)
            }
            #expect(try Self.pixel(image, x: Int(point.x), y: Int(point.y)).red > 0.9)
        }
    }

    @Test
    func backgroundsRoundedCornersAndShadowChangePixels() throws {
        let size = CGSize(width: 200, height: 160)
        let screen = Self.solid(red: 1, green: 0, blue: 0, size: size)
        var project = Self.project()
        project.edits.background = .white
        project.edits.padding = 0.15
        project.edits.cornerRadius = 0.12
        let base = try RecordingExportRenderer(project: project, size: size)
            .image(screen: screen, camera: nil, sourceTime: 0)
        #expect(try Self.pixel(base, x: 3, y: 3).green > 0.9)
        #expect(try Self.pixel(base, x: 27, y: 27).green > 0.9,
                "Rounded screen corner must reveal the background")
        project.edits.shadow = 0.8
        let shadow = try RecordingExportRenderer(project: project, size: size)
            .image(screen: screen, camera: nil, sourceTime: 0)
        #expect(try Self.pixel(shadow, x: 100, y: 21).green < Self.pixel(base, x: 100, y: 21).green)
        project.edits.background = .midnight
        #expect(try Self.pixel(RecordingExportRenderer(project: project, size: size)
            .image(screen: screen, camera: nil, sourceTime: 0), x: 3, y: 3).red < 0.1)
        project.edits.background = .gradient
        let gradient = try RecordingExportRenderer(project: project, size: size)
            .image(screen: screen, camera: nil, sourceTime: 0)
        #expect(try Self.pixel(gradient, x: 3, y: 3) != Self.pixel(gradient, x: 197, y: 157))
    }

    @Test
    func manualAndAutomaticZoomAndPointerRespectSourceClockAndCuts() throws {
        var project = Self.project(duration: 4)
        project.edits.autoZoom = true
        project.edits.zoomClips = [.init(time: 0.2, duration: 1.5, scale: 3, x: 0.3, y: 0.4)]
        project.pointers = [.init(time: 0, x: 0.2, y: 0.3), .init(time: 1, x: 0.8, y: 0.9, kind: .leftClick),
                            .init(time: 3, x: 0.4, y: 0.5, kind: .rightClick)]
        let track = RecordingExportEffectTrack(project: project)
        #expect(track.zoom(at: 0).scale == 1)
        #expect(track.zoom(at: 0.7).scale == 3)
        #expect(track.zoom(at: 2.99).scale > 1)
        #expect(track.zoom(at: 4).scale == 1)
        let pointer = try #require(track.pointer(at: 0.5, slice: nil))
        #expect(abs(pointer.x - 0.5) < 0.000_000_001 && abs(pointer.y - 0.6) < 0.000_000_001)
        let slice = RecordingExportSlice(index: 0, sourceStart: 0, sourceEnd: 0.75, speed: 1,
                                         outputStart: 0, outputEnd: 0.75)
        #expect(track.pointer(at: 0.5, slice: slice) == CGPoint(x: 0.2, y: 0.3))
        #expect(track.recentClicks(at: 1.2, slice: nil).count == 1)
        let second = RecordingExportSlice(index: 1, sourceStart: 1.1, sourceEnd: 2, speed: 1,
                                          outputStart: 0, outputEnd: 0.9)
        #expect(track.recentClicks(at: 1.2, slice: second).isEmpty)
        project.edits.autoZoom = false
        project.edits.zoomClips = []
        #expect(RecordingExportEffectTrack(project: project).zoom(at: 2.99).scale == 1)
    }

    @Test
    func captionCursorClickAndCameraMaskTogglesChangeRenderedPixels() throws {
        let size = CGSize(width: 240, height: 180)
        var project = Self.project()
        project.captions = [.init(start: 0, end: 1, text: "字幕 Caption العربية")]
        project.pointers = [.init(time: 0.1, x: 0.5, y: 0.5, kind: .leftClick)]
        let source = Self.solid(red: 0.25, green: 0.25, blue: 0.25, size: size)
        let plain = try RecordingExportRenderer(project: project, size: size)
            .image(screen: source, camera: nil, sourceTime: 0.2)
        #expect(try Self.pixel(plain, x: 20, y: 160).red < 0.2)
        project.edits.showCaptions = false
        let withoutCaptions = try RecordingExportRenderer(project: project, size: size)
            .image(screen: source, camera: nil, sourceTime: 0.2)
        #expect(try Self.pixel(withoutCaptions, x: 20, y: 160).red > 0.2)
        project.edits.showCursor = true
        let withCursor = try RecordingExportRenderer(project: project, size: size)
            .image(screen: source, camera: nil, sourceTime: 0.2)
        project.edits.showCursor = false
        let withoutCursor = try RecordingExportRenderer(project: project, size: size)
            .image(screen: source, camera: nil, sourceTime: 0.2)
        #expect(try Self.digest(withCursor) != Self.digest(withoutCursor))
        project.edits.clickEffects = true
        let withClick = try RecordingExportRenderer(project: project, size: size)
            .image(screen: source, camera: nil, sourceTime: 0.2)
        project.edits.clickEffects = false
        let withoutClick = try RecordingExportRenderer(project: project, size: size)
            .image(screen: source, camera: nil, sourceTime: 0.2)
        #expect(try Self.digest(withClick) != Self.digest(withoutClick))
        project.edits.cameraRound = true
        let camera = Self.solid(red: 1, green: 1, blue: 1, size: size)
        let round = try RecordingExportRenderer(project: project, size: size)
            .image(screen: source, camera: camera, sourceTime: 0.2)
        project.edits.cameraRound = false
        let square = try RecordingExportRenderer(project: project, size: size)
            .image(screen: source, camera: camera, sourceTime: 0.2)
        #expect(try Self.digest(round) != Self.digest(square))
    }

    @Test
    func realMP4PreservesReorderedCutsSpeedCropAndAudioMix() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(withAudio: true)
        try fixture.createTone(name: "microphone.wav", frequency: 880)
        var project = Self.project()
        project.microphoneFile = "microphone.wav"
        project.edits.segments = [.init(start: 1, end: 2, speed: 2), .init(start: 0, end: 0.5, speed: 0.5)]
        project.edits.crop = .init(x: 0, y: 0, width: 0.5, height: 1)
        let exporter = ScreenRecordingExporter()
        let destination = fixture.root.appendingPathComponent("result.mp4")
        try await exporter.export(project: project, directory: fixture.directory, to: destination,
                                  configuration: .init(resolution: .source, frameRate: 12))
        #expect(!exporter.isExporting)
        #expect(exporter.progress == 1)
        let asset = AVURLAsset(url: destination)
        #expect(abs(try await asset.load(.duration).seconds - 1.5) < 0.03)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await video.load(.naturalSize) == CGSize(width: 80, height: 120))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let first = try Self.pixel(try await generator.image(at: .zero).image, x: 40, y: 60)
        let later = try Self.pixel(try await generator.image(at: .init(seconds: 0.8, preferredTimescale: 600)).image,
                                   x: 40, y: 60)
        #expect(first.blue > 0.7 && first.red < 0.2)
        #expect(later.red > 0.7 && later.blue < 0.2)
        let samples = try await Self.audioSamples(asset)
        #expect(Self.toneEnergy(samples, frequency: 440) > 0.000_05,
                "Export must preserve the system audio tone")
        #expect(Self.toneEnergy(samples, frequency: 880) > 0.000_03,
                "Export must mix the independent microphone tone")
        #expect(try fixture.stagingFiles().isEmpty)
    }

    @Test
    func realGIFHasCorrectFrameCountDurationAndCompositedCameraCaptions() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        try await fixture.createVideo(name: "camera.mp4", camera: true)
        var project = Self.project()
        project.cameraFile = "camera.mp4"
        project.edits.cameraSize = 0.4
        project.edits.cameraPosition = .topLeft
        project.edits.segments = [.init(start: 0, end: 0.5, speed: 1)]
        project.captions = [.init(start: 0, end: 0.5, text: "Caption")]
        let exporter = ScreenRecordingExporter()
        let destination = fixture.root.appendingPathComponent("result.gif")
        try await exporter.export(project: project, directory: fixture.directory, to: destination,
                                  configuration: .init(format: .gif, resolution: .source, frameRate: 12))
        let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 6)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.width == 160 && first.height == 120)
        let camera = try Self.pixel(first, x: 27, y: 27)
        #expect(camera.green > 0.7 && camera.red < 0.3)
        let caption = try Self.pixel(first, x: 20, y: 108)
        #expect(caption.red < 0.5, "Caption box must be encoded into GIF pixels")
        let duration = (0..<CGImageSourceGetCount(source)).reduce(0.0) { value, index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return value + (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0)
        }
        #expect(abs(duration - 0.5) < 0.011)
        #expect(try fixture.stagingFiles().isEmpty)

        project.edits.segments = [.init(start: 0, end: 0.2)]
        let partialOutput = fixture.root.appendingPathComponent("partial.gif")
        try await exporter.export(project: project, directory: fixture.directory, to: partialOutput,
                                  configuration: .init(format: .gif, resolution: .source, frameRate: 12))
        let partial = try #require(CGImageSourceCreateWithURL(partialOutput as CFURL, nil))
        #expect(CGImageSourceGetCount(partial) == 3)
        let partialDuration = (0..<CGImageSourceGetCount(partial)).reduce(0.0) { value, index in
            let properties = CGImageSourceCopyPropertiesAtIndex(partial, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return value + (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0)
        }
        #expect(abs(partialDuration - 0.2) < 0.005)
    }

    @Test
    func realMP4BurnsCameraCaptionsAndClickIntoEncodedPixels() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        try await fixture.createVideo(name: "camera.mp4", camera: true)
        var project = Self.project()
        project.cameraFile = "camera.mp4"
        project.edits.cameraSize = 0.4
        project.edits.cameraPosition = .topLeft
        project.edits.segments = [.init(start: 0, end: 0.5)]
        project.edits.showCursor = true
        project.edits.clickEffects = true
        project.pointers = [.init(time: 0.1, x: 0.5, y: 0.5, kind: .leftClick)]
        project.captions = [.init(start: 0, end: 0.5, text: "Caption")]
        let output = fixture.root.appendingPathComponent("effects.mp4")
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory, to: output,
                                                   configuration: .init(resolution: .source, frameRate: 12))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: .init(seconds: 0.25, preferredTimescale: 600)).image
        #expect(try Self.pixel(image, x: 27, y: 27).green > 0.7)
        #expect(try Self.pixel(image, x: 20, y: 108).red < 0.5)
        var hasCursorOrClick = false
        for y in 45..<65 {
            for x in 70..<90 where try Self.pixel(image, x: x, y: y).green > 0.3 { hasCursorOrClick = true }
        }
        #expect(hasCursorOrClick, "Cursor and click overlay must survive the MP4 encoder")
    }

    @Test
    func gifDictionaryResetAndBitWidthTransitionsDecodeWithoutCorruption() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let width = 160
        let height = 120
        var state: UInt32 = 17
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<width * height {
            state = state &* 1_664_525 &+ 1_013_904_223
            let index = Int((state >> 16) & 0xFF)
            bytes[pixel * 4] = UInt8(((index >> 5) & 7) * 255 / 7)
            bytes[pixel * 4 + 1] = UInt8(((index >> 2) & 7) * 255 / 7)
            bytes[pixel * 4 + 2] = UInt8((index & 3) * 255 / 3)
            bytes[pixel * 4 + 3] = 255
        }
        let image = try bytes.withUnsafeBytes { pointer in
            let context = try #require(CGContext(data: UnsafeMutableRawPointer(mutating: pointer.baseAddress!),
                                                 width: width, height: height, bitsPerComponent: 8,
                                                 bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try #require(context.makeImage())
        }
        let output = fixture.root.appendingPathComponent("random.gif")
        let writer = try RecordingExportGIFWriter(url: output, size: .init(width: width, height: height), frameRate: 30)
        try writer.append(image)
        try writer.append(image)
        try writer.finish()
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 1, nil))
        let decodedPixels = try Self.digest(decoded)
        let sourcePixels = try Self.digest(image)
        #expect(decodedPixels == sourcePixels)
    }

    @Test
    func gifPixelLoopHonorsCancellationBeforeWritingFrame() async throws {
        let gate = ExportGate()
        let worker = Task.detached {
            gate.pause()
            return try RecordingExportGIFWriter.lzw([UInt8](repeating: 123, count: 70_000))
        }
        await gate.waitUntilPaused()
        worker.cancel()
        gate.resume()
        await #expect(throws: CancellationError.self) { _ = try await worker.value }
    }

    @Test(arguments: [RecordingExportFormat.mp4, .gif])
    func cancellationAndDiskFailurePreserveExistingDestinationAndRemoveOnlyOwnFiles(format: RecordingExportFormat) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        let destination = fixture.root.appendingPathComponent("existing.\(format.rawValue)")
        let original = Data("existing destination".utf8)
        try original.write(to: destination)
        let unrelated = fixture.root.appendingPathComponent(".zisla-recording-export-unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        for cancellation in [false, true] {
            let exporter = ScreenRecordingExporter { checkpoint in
                if checkpoint == .frame(2) {
                    if cancellation { throw CancellationError() }
                    throw CocoaError(.fileWriteOutOfSpace)
                }
            }
            do {
                try await exporter.export(project: Self.project(), directory: fixture.directory, to: destination,
                                          configuration: .init(format: format, resolution: .source, frameRate: 12))
                Issue.record("Injected cancellation or disk failure must abort export")
            } catch {
                #expect(cancellation ? error is CancellationError : (error as NSError).code == CocoaError.fileWriteOutOfSpace.rawValue)
            }
            #expect(!exporter.isExporting)
            #expect(exporter.progress < 1)
            #expect(try Data(contentsOf: destination) == original)
            #expect(try fixture.stagingFiles() == [unrelated.lastPathComponent])
            #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("screen.mp4").path))
        }
    }

    @Test
    func failureBeforeCommitKeepsExistingFileAndSuccessReplacesIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        let destination = fixture.root.appendingPathComponent("result.gif")
        let original = Data("old result".utf8)
        try original.write(to: destination)
        let exporter = ScreenRecordingExporter { checkpoint in
            if checkpoint == .beforeCommit { throw CocoaError(.fileWriteNoPermission) }
        }
        var project = Self.project()
        project.edits.segments = [.init(start: 0, end: 0.2)]
        let config = RecordingExportConfiguration(format: .gif, resolution: .source, frameRate: 12)
        await #expect(throws: CocoaError.self) {
            try await exporter.export(project: project, directory: fixture.directory, to: destination, configuration: config)
        }
        #expect(try Data(contentsOf: destination) == original)
        #expect(try fixture.stagingFiles().isEmpty)
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory,
                                                   to: destination, configuration: config)
        #expect(try Data(contentsOf: destination).prefix(6) == Data("GIF89a".utf8))
        #expect(try fixture.stagingFiles().isEmpty)
    }

    @Test(arguments: [RecordingExportFormat.mp4, .gif])
    func realTaskCancellationAndExporterCancelResetStateAndPreserveTarget(format: RecordingExportFormat) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        let destination = fixture.root.appendingPathComponent("result.\(format.rawValue)")
        let original = Data("existing destination".utf8)
        try original.write(to: destination)
        for useExporterCancel in [false, true] {
            let gate = ExportGate()
            let exporter = ScreenRecordingExporter { checkpoint in
                if checkpoint == .frame(2) { gate.pause() }
            }
            let task = Task {
                try await exporter.export(project: Self.project(), directory: fixture.directory, to: destination,
                                          configuration: .init(format: format, resolution: .source, frameRate: 12))
            }
            await gate.waitUntilPaused()
            #expect(exporter.isExporting)
            await #expect(throws: ScreenRecordingExportError.exportInProgress) {
                try await exporter.export(project: Self.project(), directory: fixture.directory, to: destination,
                                          configuration: .init(format: format, resolution: .source, frameRate: 12))
            }
            if useExporterCancel { exporter.cancel() } else { task.cancel() }
            gate.resume()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(!exporter.isExporting)
            #expect(try Data(contentsOf: destination) == original)
            #expect(try fixture.stagingFiles().isEmpty)
        }
    }

    @Test
    func injectedAudioWriteFailureCancelsVideoAndLeavesNoPartialFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(withAudio: true)
        let destination = fixture.root.appendingPathComponent("audio.mp4")
        let original = Data("existing output".utf8)
        try original.write(to: destination)
        let exporter = ScreenRecordingExporter { checkpoint in
            if checkpoint == .audioSample(0) { throw CocoaError(.fileWriteOutOfSpace) }
        }
        await #expect(throws: CocoaError.self) {
            try await exporter.export(project: Self.project(), directory: fixture.directory, to: destination,
                                      configuration: .init(resolution: .source, frameRate: 12))
        }
        #expect(!exporter.isExporting)
        #expect(try Data(contentsOf: destination) == original)
        #expect(try fixture.stagingFiles().isEmpty)
    }

    @Test
    func rejectsUnsafeDestinationMissingOrCorruptMediaAndOutOfRangeEdits() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        let exporter = ScreenRecordingExporter()
        let outside = fixture.root.appendingPathComponent("result.gif")
        let configuration = RecordingExportConfiguration(format: .gif, resolution: .source, frameRate: 12)
        for destination in [fixture.directory.appendingPathComponent("screen.mp4"),
                            fixture.directory.appendingPathComponent("project.json"), fixture.root] {
            await #expect(throws: ScreenRecordingExportError.invalidDestination) {
                try await exporter.export(project: Self.project(), directory: fixture.directory,
                                          to: destination, configuration: configuration)
            }
        }
        let link = fixture.root.appendingPathComponent("symlink.gif")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await #expect(throws: ScreenRecordingExportError.invalidDestination) {
            try await exporter.export(project: Self.project(), directory: fixture.directory,
                                      to: link, configuration: configuration)
        }
        var project = Self.project()
        project.videoFile = "missing.mp4"
        await #expect(throws: (any Error).self) {
            try await exporter.export(project: project, directory: fixture.directory, to: outside, configuration: configuration)
        }
        try Data("invalid mp4".utf8).write(to: fixture.directory.appendingPathComponent("corrupt.mp4"))
        project.videoFile = "corrupt.mp4"
        await #expect(throws: (any Error).self) {
            try await exporter.export(project: project, directory: fixture.directory, to: outside, configuration: configuration)
        }
        project = Self.project(duration: 4)
        await #expect(throws: ScreenRecordingExportError.timelineOutsideMedia) {
            try await exporter.export(project: project, directory: fixture.directory, to: outside, configuration: configuration)
        }
        #expect(!FileManager.default.fileExists(atPath: outside.path))
        #expect(!exporter.isExporting)
        #expect(try fixture.stagingFiles().isEmpty)
    }

    @Test
    func previewUsesSharedRendererAndBoundsItsSize() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        var project = Self.project()
        project.edits.crop = .init(x: 0, y: 0, width: 0.5, height: 1)
        let image = try await ScreenRecordingExporter().preview(project: project, directory: fixture.directory,
                                                               sourceTime: 1.5, maximumSize: .init(width: 100, height: 80))
        #expect(image.height == 80 && image.width == 52)
        #expect(try Self.pixel(image, x: 26, y: 40).blue > 0.7)
        let oddLimit = try await ScreenRecordingExporter().preview(project: Self.project(), directory: fixture.directory,
                                                                  sourceTime: 0.137, maximumSize: .init(width: 100, height: 75))
        #expect(oddLimit.width == 100 && oddLimit.height == 74)
    }

    @Test
    func previewAtArbitrarySeekAndStaticTailUsesTheCurrentFrame() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(frames: [0, 12])
        let exporter = ScreenRecordingExporter()
        for time in [0.137, 0.999_9, 1.000_1, 1.937, 2] {
            let image = try await exporter.preview(project: Self.project(), directory: fixture.directory,
                                                   sourceTime: time, maximumSize: .init(width: 160, height: 120))
            let center = try Self.pixel(image, x: 80, y: 60)
            #expect(time < 1 ? center.red > 0.7 && center.blue < 0.2
                            : center.blue > 0.7 && center.red < 0.2)
        }
    }

    @Test
    func playbackItemPreservesTheCutSequenceSpeedAndMixedAudio() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(withAudio: true)
        try fixture.createTone(name: "microphone.wav", frequency: 880)
        var project = Self.project()
        project.microphoneFile = "microphone.wav"
        project.edits.segments = [.init(start: 1, end: 2, speed: 2), .init(start: 0, end: 0.5, speed: 0.5)]
        let item = try await ScreenRecordingExporter().playbackItem(project: project, directory: fixture.directory)
        #expect(abs(try await item.asset.load(.duration).seconds - 1.5) < 0.001)
        #expect(try await item.asset.loadTracks(withMediaType: .audio).count == 2)
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        #expect(try Self.pixel(try await generator.image(at: .zero).image, x: 80, y: 60).blue > 0.7)
        #expect(try Self.pixel(try await generator.image(at: .init(seconds: 0.8, preferredTimescale: 600)).image,
                               x: 80, y: 60).red > 0.7)
        let mix = try #require(item.audioMix)
        let samples = try await Self.audioSamples(item.asset, mix: mix)
        #expect(Self.toneEnergy(samples, frequency: 440) > 0.000_05)
        #expect(Self.toneEnergy(samples, frequency: 880) > 0.000_03)
        #expect(try fixture.stagingFiles().isEmpty)
    }

    @Test
    func lateCameraDoesNotAppearBeforeItsFirstRecordedFrame() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        try await fixture.createVideo(name: "camera.mp4", camera: true, frames: [6, 12, 18])
        var project = Self.project()
        project.cameraFile = "camera.mp4"
        project.edits.cameraPosition = .topLeft
        project.edits.cameraSize = 0.4
        let timeline = try RecordingExportTimeline(project: project)
        let media = try await RecordingExportMedia.prepare(project: project, directory: fixture.directory,
                                                           timeline: timeline)
        #expect(media.camera?.availableRanges.first??.start.seconds == 0.5)
        let output = fixture.root.appendingPathComponent("late-camera.gif")
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory, to: output,
                                                   configuration: .init(format: .gif, resolution: .source, frameRate: 12))
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let later = try #require(CGImageSourceCreateImageAtIndex(source, 6, nil))
        #expect(try Self.pixel(first, x: 27, y: 27).green < 0.2)
        #expect(try Self.pixel(later, x: 27, y: 27).green > 0.7)
        let preview = try await ScreenRecordingExporter().preview(project: project, directory: fixture.directory,
                                                                  sourceTime: 0.137, maximumSize: .init(width: 160, height: 120))
        #expect(try Self.pixel(preview, x: 27, y: 27).green < 0.2)
    }

    @Test
    func repeatedVFRCutsConsumeTheirFirstAvailableFrameWithoutReusingThePreviousSlice() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(frames: [0, 6, 12, 18])
        var project = Self.project()
        project.edits.segments = [.init(start: 0.4, end: 0.8), .init(start: 1.4, end: 1.8),
                                  .init(start: 0.4, end: 0.8)]
        let output = fixture.root.appendingPathComponent("vfr.gif")
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory, to: output,
                                                   configuration: .init(format: .gif, resolution: .source, frameRate: 10))
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 12)
        for index in 0..<12 {
            let image = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
            let center = try Self.pixel(image, x: 80, y: 60)
            #expect((4..<8).contains(index) ? center.blue > 0.7 && center.red < 0.2
                                          : center.red > 0.7 && center.blue < 0.2)
        }
    }

    @Test(arguments: RecordingExportFormat.allCases)
    func staticVFRCutsKeepTheFrameSpanningEachCut(format: RecordingExportFormat) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(frames: [0, 12])
        var project = Self.project()
        project.edits.segments = [.init(start: 0.2, end: 0.3), .init(start: 1.2, end: 1.3),
                                  .init(start: 0.7, end: 0.8)]
        let output = fixture.root.appendingPathComponent("static-cuts.\(format.rawValue)")
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory, to: output,
                                                   configuration: .init(format: format, resolution: .source, frameRate: 10))
        let images: [CGImage]
        if format == .gif {
            let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            #expect(CGImageSourceGetCount(source) == 3)
            images = try (0..<3).map { try #require(CGImageSourceCreateImageAtIndex(source, $0, nil)) }
        } else {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            var frames: [CGImage] = []
            for index in 0..<3 {
                frames.append(try await generator.image(at: .init(value: Int64(index), timescale: 10)).image)
            }
            images = frames
        }
        for (index, image) in images.enumerated() {
            let center = try Self.pixel(image, x: 80, y: 60)
            #expect(index == 1 ? center.blue > 0.7 && center.red < 0.2
                              : center.red > 0.7 && center.blue < 0.2)
        }
        #expect(try fixture.stagingFiles().isEmpty)
    }

    private static func project(duration: Double = 2) -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Fixture", createdAt: Date(timeIntervalSince1970: 0),
                                              videoFile: "screen.mp4", duration: duration, width: 160, height: 120)
        project.edits.background = .none
        project.edits.padding = 0
        project.edits.cornerRadius = 0
        project.edits.shadow = 0
        project.edits.showCursor = false
        project.edits.clickEffects = false
        return project
    }

    private static func solid(red: Double, green: Double, blue: Double, size: CGSize) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue)).cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func quadrants(size: CGSize) -> CIImage {
        let half = CGSize(width: size.width / 2, height: size.height / 2)
        let red = solid(red: 1, green: 0, blue: 0, size: half)
            .transformed(by: .init(translationX: 0, y: half.height))
        let green = solid(red: 0, green: 1, blue: 0, size: half)
            .transformed(by: .init(translationX: half.width, y: half.height))
        let blue = solid(red: 0, green: 0, blue: 1, size: half)
        let yellow = solid(red: 1, green: 1, blue: 0, size: half)
            .transformed(by: .init(translationX: half.width, y: 0))
        return red.composited(over: green).composited(over: blue).composited(over: yellow)
    }

    private struct Pixel: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) throws -> Pixel {
        let pixels = try digest(image)
        let offset = (y * image.width + x) * 4
        return Pixel(red: Double(pixels[offset]) / 255, green: Double(pixels[offset + 1]) / 255,
                     blue: Double(pixels[offset + 2]) / 255)
    }

    private static func digest(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(data: pointer.baseAddress, width: image.width, height: image.height,
                                                 bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    private static func audioSamples(_ asset: AVAsset, mix: AVAudioMix? = nil) async throws -> [Float] {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try #require(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ]
        let output: AVAssetReaderOutput
        if let mix {
            let mixed = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
            mixed.audioMix = mix
            mixed.audioTimePitchAlgorithm = .spectral
            output = mixed
        } else { output = AVAssetReaderTrackOutput(track: track, outputSettings: settings) }
        reader.add(output)
        #expect(reader.startReading())
        defer { reader.cancelReading() }
        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer(), let block = sample.dataBuffer {
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            var values = [Float](repeating: 0, count: count)
            let status = values.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 4, destination: $0.baseAddress!)
            }
            #expect(status == kCMBlockBufferNoErr)
            let channels = Int(sample.formatDescription.flatMap(CMAudioFormatDescriptionGetStreamBasicDescription)?.pointee.mChannelsPerFrame ?? 1)
            for offset in stride(from: 0, to: values.count, by: channels) {
                samples.append(values[offset..<min(offset + channels, values.count)].reduce(0, +) / Float(channels))
            }
        }
        #expect(reader.status == .completed)
        return samples
    }

    private static func toneEnergy(_ samples: [Float], frequency: Double) -> Double {
        let window = samples.dropFirst(min(4_800, samples.count)).prefix(9_600)
        var real = 0.0
        var imaginary = 0.0
        for (index, sample) in window.enumerated() {
            let phase = 2 * Double.pi * frequency * Double(index) / 48_000
            real += Double(sample) * cos(phase)
            imaginary += Double(sample) * sin(phase)
        }
        return (real * real + imaginary * imaginary) / Double(max(1, window.count * window.count))
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let directory: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-recording-export-tests-\(UUID())")
            directory = root.appendingPathComponent("fixture.zisla-recording", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        func stagingFiles() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.hasPrefix(".zisla-recording-export-") }.sorted()
        }

        func createTone(name: String, frequency: Double) throws {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
            let settings: [String: Any] = name.hasSuffix(".m4a") ? [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000,
            ] : format.settings
            let file = try AVAudioFile(forWriting: directory.appendingPathComponent(name), settings: settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
            buffer.frameLength = 96_000
            let channel = try #require(buffer.floatChannelData?[0])
            for index in 0..<96_000 { channel[index] = Float(0.15 * sin(2 * Double.pi * frequency * Double(index) / 48_000)) }
            try file.write(from: buffer)
        }

        func createVideo(name: String = "screen.mp4", camera: Bool = false, withAudio: Bool = false,
                         frames: [Int] = Array(0..<24)) async throws {
            let plainURL = directory.appendingPathComponent(withAudio ? "plain.mp4" : name)
            let writer = try AVAssetWriter(outputURL: plainURL, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 120,
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 120,
            ])
            writer.add(input)
            #expect(writer.startWriting())
            writer.startSession(atSourceTime: .zero)
            let context = CIContext()
            for index in frames {
                while !input.isReadyForMoreMediaData { await Task.yield() }
                var buffer: CVPixelBuffer?
                #expect(CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer) == kCVReturnSuccess)
                let image = camera ? SelfSource.solid(red: 0, green: 0.9, blue: 0) : index < 12
                    ? SelfSource.solid(red: 0.9, green: 0, blue: 0) : SelfSource.solid(red: 0, green: 0, blue: 0.9)
                context.render(image, to: try #require(buffer))
                #expect(adaptor.append(try #require(buffer), withPresentationTime: CMTime(value: Int64(index), timescale: 12)))
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: .init(seconds: 2, preferredTimescale: 600))
            await writer.finishWriting()
            #expect(writer.status == .completed)
            if withAudio {
                try createTone(name: "system.m4a", frequency: 440)
                try await NativeMediaMuxer().mux(videoURL: plainURL, audioURL: directory.appendingPathComponent("system.m4a"),
                                                outputURL: directory.appendingPathComponent(name))
            }
        }
    }

    private enum SelfSource {
        static func solid(red: Double, green: Double, blue: Double) -> CIImage {
            CIImage(color: CIColor(red: red, green: green, blue: blue)).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 120))
        }
    }

    private final class ExportGate: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var paused = false
        private var waiting: CheckedContinuation<Void, Never>?

        func pause() {
            let continuation = lock.withLock {
                paused = true
                let value = waiting
                waiting = nil
                return value
            }
            continuation?.resume()
            semaphore.wait()
        }

        func waitUntilPaused() async {
            await withCheckedContinuation { continuation in
                let complete = lock.withLock {
                    if paused { return true }
                    waiting = continuation
                    return false
                }
                if complete { continuation.resume() }
            }
        }

        func resume() { semaphore.signal() }
    }
}
