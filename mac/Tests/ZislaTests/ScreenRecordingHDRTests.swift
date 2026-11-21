import AppKit
import AVFoundation
import CoreImage
import ScreenCaptureKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingHDRTests {
    @Test(arguments: [false, true])
    func captureDefaultsToSDRAndHDRRequestsKeepGeometryAndAudio(includeHDR: Bool) {
        #expect(!RecordingCaptureConfiguration().preservesHDR)
        let config = ScreenRecordingNativeCapture.streamConfiguration(width: 640, height: 480, frameRate: 60,
                                                                      includeHDR: includeHDR)
        #expect(config.width == 640 && config.height == 480 && config.minimumFrameInterval == .init(value: 1, timescale: 60))
        #expect(!config.showsCursor && config.sampleRate == 48_000 && config.channelCount == 2 && config.excludesCurrentProcessAudio)
        if #available(macOS 15.0, *), includeHDR && ScreenshotCaptureService.supportsHDRCapture {
            #expect(config.captureDynamicRange == .hdrLocalDisplay)
            #expect(config.pixelFormat == SCStreamConfiguration(preset: .captureHDRStreamLocalDisplay).pixelFormat)
        } else {
            #expect(config.pixelFormat == kCVPixelFormatType_32BGRA && config.colorSpaceName == CGColorSpace.sRGB)
        }
    }

    @Test
    func editedPreviewAndAnnotationsKeepDistinctHDRHighlights() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let project = fixture.project()
        let source = try Self.image()
        let renderer = try RecordingExportRenderer(project: project, size: .init(width: 64, height: 48), preservesHDR: true)
        let preview = try renderer.image(screen: CIImage(cgImage: source), camera: nil, sourceTime: 0)
        #expect(ScreenshotImageRendering.isHDR(preview), "The edited preview must retain the capture's dynamic range")
        #expect(Self.highlight(preview) > 3.8, "HDR highlights must survive the recording renderer")
        if #available(macOS 26.0, *) { #expect(preview.contentHeadroom > 3.8 && preview.contentAverageLightLevel > 0) }
        let composed = try RecordingExportRenderer.composedPreview(base: source, project: project, sourceTime: 0,
                                                                   context: CIContext())
        #expect(ScreenshotImageRendering.isHDR(composed))
        #expect(Self.highlight(composed) > 3.8, "Editable overlays must not flatten the HDR background")
    }

    @Test
    func multitrackPreviewKeepsHDRWhenRecordingLayersAreFlattened() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        var project = fixture.project()
        project.timeline = .migrating(project)
        let clip = try #require(project.timeline?.clips.first { $0.content.trackKind == .video })
        let scene = RecordingMultitrackPreviewScene(project: project, directory: fixture.directory, time: 0,
                                                    size: .init(width: 64, height: 48), frames: [clip.id: try Self.image()], preservesHDR: true)
        let preview = try scene.image(project: project)
        #expect(ScreenshotImageRendering.isHDR(preview))
        #expect(Self.highlight(preview) > 3.8, "Flattening a timeline layer must preserve HDR highlights")
    }

    @Test(arguments: [false, true])
    func nativeCaptureWriterPublishesTenBitHDRWithColorMetadata(localDisplay: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let url = try await Self.record(in: fixture, localDisplay: localDisplay)
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC,
                "HDR capture requires HEVC Main 10 even below 4K")
        try Self.requireMain10(format)
        #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
            == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
        #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String
            == kCVImageBufferColorPrimaries_ITU_R_2020 as String)
        #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String
            == kCVImageBufferYCbCrMatrix_ITU_R_2020 as String)
        let pixels = try await Self.decode(asset)
        #expect(pixels.count == 2 && pixels.allSatisfy { $0 > 3.7 }, "The saved capture must retain HDR luminance: \(pixels)")
        let color = try await Self.decode(asset, point: .init(x: 8, y: 8))
        #expect(color.allSatisfy { abs($0 - 3) < 0.1 }, "The capture must convert source primaries and YCbCr matrices correctly: \(color)")
    }

    @Test(arguments: [false, true], [false, true])
    func captureNormalizesHDRBeforeCreatingTheEncoderAndPreservesFrameTiming(localDisplay: Bool, hlg: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: fixture.directory)
        let output = HDRCaptureTestAsset()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, preservesHDR: true),
                                                  width: 64, height: 48, onFailure: { Issue.record("HDR conversion must not fail: \($0)") },
                                                  factory: { _, _, first in output.first = first; return output })
        let first = try Self.sample(time: 100, localDisplay: localDisplay, hlg: hlg)
        writer.receive(first)
        writer.receive(try Self.sample(time: 100.125, localDisplay: localDisplay, hlg: hlg))
        await writer.flush()
        #expect(try await writer.waitForFirstFrame() == 100)
        let hinted = try #require(output.first)
        let written = try #require(output.samples.first)
        let pixels = try #require(written.imageBuffer)
        #expect(CVPixelBufferGetPixelFormatType(pixels) == RecordingHDR.pixelFormat,
                "The encoder must receive canonical ten-bit pixels without a driver color conversion")
        let format = try #require(hinted.formatDescription)
        #expect(CMFormatDescriptionGetMediaSubType(format) == RecordingHDR.pixelFormat)
        #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String
            == kCVImageBufferColorPrimaries_ITU_R_2020 as String)
        #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String
            == kCVImageBufferYCbCrMatrix_ITU_R_2020 as String)
        #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
            == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
        #expect(output.samples.map(\.presentationTimeStamp.seconds) == [0, 0.125])
        #expect(output.samples.allSatisfy { $0.duration == first.buffer.duration })
        #expect(hinted.imageBuffer === written.imageBuffer, "The format hint and first encoded frame must describe the same pixels")
        if !localDisplay && !hlg { #expect(pixels === first.buffer.imageBuffer, "Canonical HDR input must keep its existing pixel storage") }
        var values = [Float](repeating: 0, count: 8)
        values.withUnsafeMutableBytes { bytes in
            for (index, point) in [CGPoint(x: 32, y: 24), CGPoint(x: 8, y: 8)].enumerated() {
                CIContext().render(CIImage(cvPixelBuffer: pixels), toBitmap: bytes.baseAddress!.advanced(by: index * 16), rowBytes: 16,
                                   bounds: .init(x: point.x, y: point.y, width: 1, height: 1), format: .RGBAf,
                                   colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
            }
        }
        var original = [Float](repeating: 0, count: 8)
        original.withUnsafeMutableBytes { bytes in
            for (index, point) in [CGPoint(x: 32, y: 24), CGPoint(x: 8, y: 8)].enumerated() {
                CIContext().render(CIImage(cvPixelBuffer: first.buffer.imageBuffer!), toBitmap: bytes.baseAddress!.advanced(by: index * 16), rowBytes: 16,
                                   bounds: .init(x: point.x, y: point.y, width: 1, height: 1), format: .RGBAf,
                                   colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
            }
        }
        #expect(values[0] > 3.8 && abs(values[4] - 3) < 0.1, "Canonicalization must preserve linear HDR luminance and saturated colors: \(values)")
        #expect(zip(values, original).allSatisfy { abs($0 - $1) < 0.1 }, "PQ and HLG color conversion must retain the source's linear samples")
        await writer.seal(at: 100.25)
        #expect(try await writer.finish() == 0.25)
        await writer.cancel()
        #expect(files.discard() == nil)
    }

    @Test
    func HDRFramesWithoutImageDataFailBeforeAllocatingAnEncoder() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: fixture.directory)
        let output = HDRCaptureTestAsset()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false), width: 64, height: 48,
                                                  onFailure: { _ in }, factory: { _, _, first in output.first = first; return output })
        var format: CMVideoFormatDescription?
        try #require(CMVideoFormatDescriptionCreate(allocator: nil, codecType: RecordingHDR.pixelFormat, width: 64, height: 48,
                                                    extensions: [kCMFormatDescriptionExtension_TransferFunction: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ] as CFDictionary,
                                                    formatDescriptionOut: &format) == noErr)
        var buffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 30), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        try #require(CMSampleBufferCreateReady(allocator: nil, dataBuffer: nil, formatDescription: try #require(format), sampleCount: 1,
                                               sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                               sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &buffer) == noErr)
        writer.receive(.init(buffer: try #require(buffer), kind: .screen, hostTime: 100))
        await writer.flush()
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try await writer.waitForFirstFrame() }
        #expect(output.first == nil && output.samples.isEmpty)
        await writer.cancel()
        #expect(files.discard() == nil)
    }

    @available(macOS 15.0, *)
    @Test(arguments: [false, true])
    func pausedAndPlayingPreviewsKeepHDRAndDoNotChangeSourceMedia(multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let url = try await Self.record(in: fixture)
        var project = Self.project(url)
        if multitrack { project.timeline = .migrating(project) }
        let files = try fixture.files()
        let exporter = ScreenRecordingExporter()
        let preview = try await exporter.preview(project: project, directory: fixture.directory, sourceTime: 0,
                                                 maximumSize: .init(width: 64, height: 48))
        #expect(ScreenshotImageRendering.isHDR(preview) && Self.highlight(preview) > 3.7)
        let item = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let composition = try #require(item.videoComposition)
        #expect(composition.colorTransferFunction == AVVideoTransferFunction_SMPTE_ST_2084_PQ)
        let pixels = try await Self.decode(item.asset, composition: composition)
        #expect(!pixels.isEmpty && pixels.allSatisfy { abs($0 - 4) < 0.1 },
                "Playback must preserve source luminance without a second transfer function")
        let color = try await Self.decode(item.asset, composition: composition, point: .init(x: 8, y: 8))
        #expect(color.allSatisfy { abs($0 - 3) < 0.1 }, "Playback must preserve saturated HDR colors")
        #expect(try fixture.files() == files)
    }

    @Test(arguments: [false, true], [RecordingExportFormat.mp4, .mov, .m4v])
    func videoExportsRetainTenBitHDRAndRemoveStaging(multitrack: Bool, format: RecordingExportFormat) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let url = try await Self.record(in: fixture)
        var project = Self.project(url)
        if multitrack { project.timeline = .migrating(project) }
        let destination = fixture.root.appendingPathComponent("output." + format.fileExtension)
        let exporter = ScreenRecordingExporter()
        try await exporter.export(project: project, directory: fixture.directory, to: destination,
                                  configuration: .init(format: format, resolution: .source, frameRate: 8))
        let asset = AVURLAsset(url: destination)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let formats = try await track.load(.formatDescriptions)
        #expect(formats.contains(where: RecordingHDR.isHDR))
        try Self.requireMain10(try #require(formats.first))
        let pixels = try await Self.decode(asset)
        #expect(pixels.count == 2 && pixels.allSatisfy { $0 > 3.7 }, "Export must preserve the encoded capture's highlights")
        let color = try await Self.decode(asset, point: .init(x: 8, y: 8))
        #expect(color.allSatisfy { abs($0 - 3) < 0.1 }, "Export must keep saturated HDR colors in the encoded color space")
        #expect(exporter.progress == 1 && !exporter.isExporting)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
            == [fixture.directory.lastPathComponent, destination.lastPathComponent].sorted())
    }

    @Test(arguments: [false, true])
    func cancelledHDRExportsPreserveTheDestinationAndCleanStaging(multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let url = try await Self.record(in: fixture)
        var project = Self.project(url)
        if multitrack { project.timeline = .migrating(project) }
        let destination = fixture.root.appendingPathComponent("existing.mp4")
        try Data([7, 8]).write(to: destination)
        let exporter = ScreenRecordingExporter(checkpoint: { step in
            if step == .frame(1) { throw CancellationError() }
        })
        await #expect(throws: CancellationError.self) {
            try await exporter.export(project: project, directory: fixture.directory, to: destination,
                                      configuration: .init(resolution: .source, frameRate: 8))
        }
        #expect(try Data(contentsOf: destination) == Data([7, 8]) && !exporter.isExporting)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
            == [fixture.directory.lastPathComponent, destination.lastPathComponent].sorted())
    }

    @Test
    func canvasUsesTheScreenshotHDRLayerAndClearsItWhenChangingMedia() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let canvas = RecordingCanvasEditorView(frame: .init(x: 0, y: 0, width: 128, height: 96))
        let project = fixture.project()
        canvas.configure(project: project, sourceTime: 0, baseImage: try Self.image(), selection: nil, editable: true)
        canvas.layoutSubtreeIfNeeded()
        let image = try #require(canvas.renderedImage)
        #expect(ScreenshotImageRendering.isHDR(image))
        #expect(canvas.backingImageView.hdrLayer.contents != nil && !canvas.backingImageView.hdrLayer.isHidden)
        #expect(canvas.backingImageView.frame == canvas.canvasRect)
        #expect(canvas.hitTest(.init(x: 64, y: 48)) === canvas, "The HDR surface must not consume editing gestures")
        canvas.configure(project: nil, sourceTime: 0, baseImage: nil, selection: nil, editable: false)
        #expect(canvas.renderedImage == nil && canvas.backingImageView.hdrLayer.contents == nil)
    }

    @Test
    func HDRCanvasKeepsSelectionHandlesAndInlineTextAboveTheImage() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        var project = fixture.project()
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 2, x: 0.1, y: 0.1,
                                             endX: 0.5, endY: 0.3, text: "Edit")
        project.edits.annotations = [annotation]
        let canvas = RecordingCanvasEditorView(frame: .init(x: 0, y: 0, width: 640, height: 480))
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let base = try Self.image()
        canvas.configure(project: project, sourceTime: 0, baseImage: base, selection: .annotation(annotation.id), editable: true)
        canvas.layoutSubtreeIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 480,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        func draw() {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            canvas.draw(canvas.bounds)
            NSGraphicsContext.restoreGraphicsState()
        }
        draw()
        let shapes = try #require(canvas.backingImageView.layer?.sublayers?.compactMap { $0 as? CAShapeLayer })
        let outline = try #require(shapes.first { $0.fillColor == nil })
        let handles = try #require(shapes.first { $0.fillColor != nil })
        let imageBounds = RecordingCanvasElement.annotation(annotation).bounds(canvas: canvas.canvasSize)
        let expected = CGRect(x: imageBounds.minX * 10, y: (48 - imageBounds.maxY) * 10,
                              width: imageBounds.width * 10, height: imageBounds.height * 10)
        #expect(outline.path?.boundingBoxOfPath == expected && handles.path?.isEmpty == false,
                "The upper-left selection must remain above the HDR image in the correct flipped coordinates")
        let point = CGPoint(x: imageBounds.midX * 10, y: imageBounds.midY * 10)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(point, to: nil),
                                                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                    eventNumber: 0, clickCount: 2, pressure: 1))
        canvas.mouseDown(with: event)
        let editor = try #require(canvas.textEditor)
        let hitPoint = canvas.convert(point, to: canvas.superview)
        #expect(canvas.hitTest(hitPoint) === editor && canvas.subviews.last === editor)
        editor.insertText("Changed", replacementRange: editor.selectedRange())
        draw()
        let editedImage = try #require(canvas.renderedImage)
        #expect(handles.path?.isEmpty == true && ScreenshotImageRendering.isHDR(editedImage))
        var replacement: RecordingCanvasElement?
        canvas.onCommit = { _, value in replacement = value }
        canvas.finishTextEditing(commit: true)
        #expect(replacement?.text == "Changed" && canvas.textEditor == nil)
        #expect(canvas.hitTest(hitPoint) === canvas && !window.isVisible)
        canvas.configure(project: project, sourceTime: 0, baseImage: try #require(ScreenshotImageRendering.sdrImage(from: base)),
                         selection: .annotation(annotation.id), editable: true)
        #expect(canvas.backingImageView.isHidden, "SDR media must use the existing canvas drawing above its selection")
    }

    @Test(arguments: [false, true])
    func captureHDRControlIsVisibleAndTogglesOnlyTheRecordingConfiguration(darkMode: Bool) async throws {
        let release = EnhancedAccessibilityTestScope.acquire()
        defer { release() }
        let defaultsName = "zisla-recording-hdr-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        var dependencies = ScreenRecordingCaptureDependencies.live
        dependencies.loadSources = { [.init(id: 1, name: "Display", mode: .display,
                                            frame: .init(x: 0, y: 0, width: 640, height: 480))] }
        dependencies.loadDevices = { .init() }
        let model = ScreenRecordingStudioModel(capture: .init(dependencies: dependencies))
        defer { model.shutdown() }
        await model.loadSources()
        let controller = ScreenRecordingCaptureBarController(model: model, languageStore: AppLanguageStore(defaults: defaults),
                                                             selectRegion: {}, start: {}, openStudio: {}, cancel: {})
        defer { controller.shutdown() }
        let window = try #require(controller.hostingView.window)
        window.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
        window.setContentSize(controller.preferredSize)
        for _ in 0..<4 {
            controller.hostingView.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        func control(in object: NSObject) -> NSObject? {
            if let element = object as? any NSAccessibilityElementProtocol,
               element.accessibilityIdentifier?() == "screenRecording.input.hdr" { return object }
            guard object.responds(to: NSSelectorFromString("accessibilityChildren")) else { return nil }
            return (object.value(forKey: "accessibilityChildren") as? [NSObject] ?? []).lazy.compactMap { control(in: $0) }.first
        }
        let button = control(in: controller.hostingView)
        #expect((button != nil) == ScreenshotCaptureService.supportsHDRCapture)
        if let button {
            let original = model.configuration
            #expect(!original.preservesHDR)
            func expectVisibleLabel() throws {
                controller.hostingView.layoutSubtreeIfNeeded()
                let element = try #require(button as? any NSAccessibilityElementProtocol)
                let frame = controller.hostingView.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
                #expect(controller.hostingView.bounds.contains(frame), "The HDR control must fit inside the capture bar")
                let interior = frame.insetBy(dx: 4, dy: 4)
                let bitmap = try #require(controller.hostingView.bitmapImageRepForCachingDisplay(in: interior))
                controller.hostingView.cacheDisplay(in: interior, to: bitmap)
                let colors = (0..<bitmap.pixelsHigh).flatMap { y in
                    (0..<bitmap.pixelsWide).compactMap { x in
                        bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                    }
                }
                let contrasts = try [\NSColor.redComponent, \.greenComponent, \.blueComponent].map { channel in
                    let values = colors.map { $0[keyPath: channel] }
                    return try #require(values.max()) - #require(values.min())
                }
                let contrast = try #require(contrasts.max())
                #expect(contrast > 0.2,
                        "The HDR label must draw visible foreground pixels while the control is \(model.configuration.preservesHDR ? "on" : "off")")
            }
            try expectVisibleLabel()
            Self.press(button)
            #expect(model.configuration.preservesHDR)
            for _ in 0..<4 {
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
            try expectVisibleLabel()
            Self.press(button)
            #expect(model.configuration == original && model.capture.phase == .idle)
        }
        #expect(controller.hostingView.window?.isVisible == false)
    }

    @Test(arguments: RecordingExportFormat.allCases)
    func exportFormatsDeclareHDRSupport(format: RecordingExportFormat) {
        #expect(format.supportsHDR == [RecordingExportFormat.mp4, .mov, .m4v, .mkv, .webm, .ts].contains(format))
    }

    @Test(arguments: [false, true])
    func GIFExportsConvertHDRToSDRAndLeaveTheSourceUnchanged(multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let url = try await Self.record(in: fixture)
        let original = try Data(contentsOf: url)
        var project = Self.project(url)
        if multitrack { project.timeline = .migrating(project) }
        let destination = fixture.root.appendingPathComponent("output.gif")
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory, to: destination,
                                                   configuration: .init(format: .gif, resolution: .source, frameRate: 8))
        let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 64 && image.height == 48 && !ScreenshotImageRendering.isHDR(image))
        #expect(try Data(contentsOf: url) == original)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZISLA_RUN_FFMPEG_EXPORT_TESTS"] == "1"),
          arguments: [RecordingExportFormat.mkv, .webm, .ts], [false, true])
    func externalVideoExportsKeepTenBitPQAndSourceHighlights(format: RecordingExportFormat, multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let source = try await Self.record(in: fixture)
        let original = try Data(contentsOf: source)
        var project = Self.project(source)
        if multitrack { project.timeline = .migrating(project) }
        let destination = fixture.root.appendingPathComponent("output." + format.fileExtension)
        let executable = try ScreenRecordingFFmpegTranscoder.resolveExecutable()
        let probe = executable.deletingLastPathComponent().appendingPathComponent("ffprobe")
        try #require(YTDLPResolver.isTrustedExecutable(probe))
        let demuxer = format == .ts ? ["-f", "mpegts"] : []
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory, to: destination,
                                                   configuration: .init(format: format, resolution: .source, frameRate: 8))
        let result = try await AIAgentProcessRunner.run(executableURL: probe,
                                                        arguments: ["-v", "error", "-protocol_whitelist", "file"] + demuxer + ["-show_streams", "-of", "json", destination.path],
                                                        timeout: 15, maximumOutputBytes: 32_768, maximumErrorBytes: 8_192)
        #expect(result.status == 0 && !result.didTimeout, Comment(rawValue: result.standardError))
        let json = try #require(JSONSerialization.jsonObject(with: result.standardOutput) as? [String: Any])
        let streams = try #require(json["streams"] as? [[String: Any]])
        let video = try #require(streams.first { $0["codec_type"] as? String == "video" })
        #expect(video["codec_name"] as? String == (format == .webm ? "vp9" : "hevc"))
        #expect(video["pix_fmt"] as? String == "yuv420p10le" && video["color_transfer"] as? String == "smpte2084")
        #expect(video["color_primaries"] as? String == "bt2020" && video["color_space"] as? String == "bt2020nc")
        var luma: [UInt16] = []
        for url in [source, destination] {
            let decoded = try await AIAgentProcessRunner.run(executableURL: executable,
                                                             arguments: ["-v", "error", "-protocol_whitelist", "file,pipe"] + (url == destination ? demuxer : [])
                                                                 + ["-i", url.path, "-map", "0:v:0",
                                                                    "-frames:v", "1", "-pix_fmt", "yuv420p10le", "-f", "rawvideo", "pipe:1"],
                                                             timeout: 15, maximumOutputBytes: 64 * 48 * 3 + 1, maximumErrorBytes: 8_192)
            #expect(decoded.status == 0 && !decoded.didTimeout)
            let bytes = decoded.standardOutput
            try #require(bytes.count == 64 * 48 * 3)
            let offset = (24 * 64 + 32) * 2
            luma.append(UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
        }
        #expect(luma[0] > 512 && abs(Int(luma[0]) - Int(luma[1])) < 16,
                "Transcoding must preserve the source's PQ highlight code values")
        #expect(try Data(contentsOf: source) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
            == [fixture.directory.lastPathComponent, destination.lastPathComponent].sorted())
    }

    @Test
    func pausedHDROverlaysMatchTheExportCompositingBrightness() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        var project = fixture.project()
        project.captions = [.init(start: 0, end: 2, text: "", layout: .init(x: 0, y: 0, width: 1, height: 1))]
        let base = try Self.image()
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let paused = try RecordingExportRenderer.composedPreview(base: base, project: project, sourceTime: 0,
                                                                 context: context, editingText: .caption(project.captions[0].id))
        let linear = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
        let image = try RecordingExportRenderer.overlays(project: project, sourceTime: 0,
                                                         canvas: .init(x: 0, y: 0, width: 64, height: 48), editingText: .caption(project.captions[0].id))
            .composited(over: CIImage(cgImage: base))
        let exported = try RecordingHDR.image(image, in: image.extent, context: linear, preservesHDR: true)
        #expect(abs(Self.highlight(paused) - Self.highlight(exported)) < 0.01,
                "Paused editing must use the same linear light compositing as HDR playback and export")
    }

    @Test(arguments: [false, true])
    func translucentCaptionsKeepLinearBrightnessInPreviewPlaybackAndExport(multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let source = try await Self.record(in: fixture)
        var project = Self.project(source)
        project.captions = [.init(start: 0, end: 0.25, text: " ", layout: .init(x: 0, y: 0, width: 1, height: 1))]
        if multitrack { project.timeline = .migrating(project) }
        let exporter = ScreenRecordingExporter()
        let preview = try await exporter.preview(project: project, directory: fixture.directory, sourceTime: 0,
                                                 maximumSize: .init(width: 64, height: 48))
        let item = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let played = try await Self.decode(item.asset, composition: try #require(item.videoComposition))
        let destination = fixture.root.appendingPathComponent("caption.mp4")
        try await exporter.export(project: project, directory: fixture.directory, to: destination,
                                  configuration: .init(resolution: .source, frameRate: 8))
        let exported = try await Self.decode(AVURLAsset(url: destination))
        #expect(abs(Self.highlight(preview) - 0.88) < 0.05)
        #expect(!played.isEmpty && played.allSatisfy { abs($0 - 0.88) < 0.05 }, Comment(rawValue: "Decoded playback: \(played)"))
        #expect(!exported.isEmpty && exported.allSatisfy { abs($0 - 0.88) < 0.05 },
                "The 78% black caption background must blend in linear light throughout the HDR pipeline")
    }

    @Test(arguments: [false, true])
    func HDRPlaybackPreservesSmoothHighlightGradients(multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let source = try await Self.record(in: fixture)
        var project = Self.project(source)
        if multitrack { project.timeline = .migrating(project) }
        let item = try await ScreenRecordingExporter().playbackItem(project: project, directory: fixture.directory)
        let played = try await Self.decode(item.asset, composition: try #require(item.videoComposition),
                                           point: .init(x: 0, y: 40), width: 64)
        let steps = zip(played, played.dropFirst()).enumerated().filter { ($0.offset + 1) % 64 != 0 }
            .map { abs($0.element.0 - $0.element.1) }
        #expect(played.count >= 64 && steps.allSatisfy { $0 < 0.09 },
                Comment(rawValue: "Smooth HDR highlights must not become visible quantization steps; largest step: \(steps.max() ?? 0)"))
    }

    @Test(arguments: [false, true])
    func SDRSectionsOfMixedTimelinesUseTheSameCompositingAsHDRPlaybackAndExport(reverseStorage: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let hdr = try await Self.record(in: fixture)
        _ = try await fixture.createVideo("sdr.mp4", duration: 0.25, colors: [.white])
        var project = Self.project(hdr)
        project.captions = [.init(start: 0, end: 0.25, text: "HDR", layout: .init(x: 0, y: 0, width: 1, height: 1))]
        project.timeline = .migrating(project)
        var timeline = try #require(project.timeline)
        var sdr = try #require(timeline.clips.first { $0.content.trackKind == .video })
        let asset = RecordingMediaAsset(name: "SDR", file: "sdr.mp4", kind: .video, duration: 0.25, width: 64, height: 48)
        timeline.assets.append(asset)
        sdr.id = "sdr"
        sdr.content = .video(asset.id)
        timeline.clips = [sdr] + timeline.clips.map { clip in
            var clip = clip
            if clip.content.trackKind == .video { clip.start += 0.25 }
            return clip
        }
        if reverseStorage { timeline.clips.reverse() }
        project.timeline = timeline
        let exporter = ScreenRecordingExporter()
        let scene = try await exporter.multitrackPreview(project: project, directory: fixture.directory, time: 0,
                                                         maximumSize: .init(width: 64, height: 48))
        let selection = RecordingCanvasSelection.caption(project.captions[0].id)
        let paused = try scene.image(project: project, editingText: selection)
        let media = try await RecordingMultitrackMedia.prepare(project: project, directory: fixture.directory)
        #expect(scene.preservesHDR && media.preservesHDR, "HDR compositing must be independent of clip storage order")
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: scene.size,
                                                       preservesHDR: media.preservesHDR)
        let played = try renderer.image(frames: scene.frames.mapValues(CIImage.init(cgImage:)), at: 0, editingText: selection)
        #expect(abs(Self.highlight(paused) - Self.highlight(played)) < 0.01,
                "SDR sections must use the timeline's HDR compositing space, including translucent overlays")
    }

    @Test
    func HLGSourceFramesSelectHDRWhileSDRAndMissingTagsDoNot() throws {
        for (transfer, expected) in [(kCVImageBufferTransferFunction_ITU_R_2100_HLG, true),
                                     (kCVImageBufferTransferFunction_ITU_R_709_2, false)] {
            var format: CMVideoFormatDescription?
            try #require(CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_HEVC, width: 64, height: 48,
                                                        extensions: [kCMFormatDescriptionExtension_TransferFunction: transfer] as CFDictionary,
                                                        formatDescriptionOut: &format) == noErr)
            #expect(RecordingHDR.isHDR(try #require(format)) == expected)
        }
        var untagged: CMVideoFormatDescription?
        try #require(CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_HEVC, width: 64, height: 48,
                                                    extensions: nil, formatDescriptionOut: &untagged) == noErr)
        #expect(!RecordingHDR.isHDR(try #require(untagged)))
    }

    private static func record(in fixture: RecordingMultitrackTestFixture, localDisplay: Bool = false) async throws -> URL {
        let files = try ScreenRecordingCaptureFiles(directory: fixture.directory)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, preservesHDR: true),
                                                  width: 64, height: 48, onFailure: { _ in })
        let sample = try Self.sample(time: 100, localDisplay: localDisplay)
        let source = CIImage(cvPixelBuffer: try #require(sample.buffer.imageBuffer))
        var sourcePixels = [Float](repeating: 0, count: 8)
        sourcePixels.withUnsafeMutableBytes { bytes in
            let context = CIContext()
            for (index, point) in [CGPoint(x: 32, y: 24), CGPoint(x: 8, y: 8)].enumerated() {
                context.render(source, toBitmap: bytes.baseAddress!.advanced(by: index * 16), rowBytes: 16,
                               bounds: .init(x: point.x, y: point.y, width: 1, height: 1), format: .RGBAf,
                               colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
            }
        }
        try #require(sourcePixels[0] > 3.8 && abs(sourcePixels[4] - 3) < 0.1,
                     "The HDR source must contain the authored luminance and color before encoding (localDisplay=\(localDisplay)): \(sourcePixels)")
        writer.receive(sample)
        await writer.flush()
        _ = try await writer.waitForFirstFrame()
        await writer.seal(at: 100.25)
        _ = try await writer.finish()
        try files.publish([files.screenName])
        #expect(!FileManager.default.fileExists(atPath: files.staging.path))
        return fixture.directory.appendingPathComponent(files.screenName)
    }

    private static func project(_ url: URL) -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "HDR recording", videoFile: url.lastPathComponent, duration: 0.25, width: 64, height: 48)
        project.edits.background = .none
        project.edits.showCursor = false
        project.edits.clickEffects = false
        return project
    }

    private static func press(_ control: NSObject) {
        control.performSelector(onMainThread: NSSelectorFromString("accessibilityPerformPress"), with: nil, waitUntilDone: true)
    }

    private static func requireMain10(_ format: CMFormatDescription) throws {
        let atoms = try #require(CMFormatDescriptionGetExtension(format,
                                                                 extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Data])
        let configuration = try #require(atoms["hvcC"])
        try #require(configuration.count >= 19)
        #expect(configuration[1] & 31 == 2 && configuration[17] & 7 == 2 && configuration[18] & 7 == 2,
                "The HEVC configuration must declare Main 10 with ten-bit luma and chroma")
    }

    private static func image() throws -> CGImage {
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let background = CIImage(color: try #require(CIColor(red: 4, green: 4, blue: 4, colorSpace: linear)))
            .cropped(to: .init(x: 0, y: 0, width: 64, height: 48))
        let image = CIImage(color: try #require(CIColor(red: 3, green: 0.5, blue: 0.6, colorSpace: linear)))
            .cropped(to: .init(x: 0, y: 0, width: 16, height: 16)).composited(over: background)
        var gradient = image
        for x in 0..<64 {
            let level = 1.2 + CGFloat(x) / 63 * 2.8
            let column = CIImage(color: try #require(CIColor(red: level, green: level, blue: level, colorSpace: linear)))
                .cropped(to: .init(x: x, y: 32, width: 1, height: 16))
            gradient = column.composited(over: gradient)
        }
        return try #require(CIContext().createCGImage(gradient, from: image.extent, format: .RGBAh, colorSpace: linear))
    }

    private static func highlight(_ image: CGImage) -> Float {
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes {
            CIContext().render(CIImage(cgImage: image), toBitmap: $0.baseAddress!, rowBytes: 16,
                               bounds: .init(x: 32, y: 24, width: 1, height: 1), format: .RGBAf,
                               colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        }
        return pixel[0]
    }

    nonisolated private static func decode(_ asset: AVAsset, composition: AVVideoComposition? = nil,
                                           point: CGPoint = .init(x: 32, y: 24), width: Int = 1) async throws -> [Float] {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "zisla-hdr-test-decode").async(execute: DispatchWorkItem {
                do {
                    let reader = try AVAssetReader(asset: asset)
                    let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf,
                                                   AVVideoAllowWideColorKey: true]
                    let output: AVAssetReaderOutput
                    if let composition {
                        let composed = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: settings)
                        composed.videoComposition = composition
                        output = composed
                    } else { output = AVAssetReaderTrackOutput(track: try #require(tracks.first), outputSettings: settings) }
                    reader.add(output)
                    try #require(reader.startReading())
                    defer { reader.cancelReading() }
                    let context = CIContext()
                    var pixels: [Float] = []
                    while let sample = output.copyNextSampleBuffer() {
                        let image = CIImage(cvPixelBuffer: try #require(sample.imageBuffer))
                        var pixel = [Float](repeating: 0, count: width * 4)
                        pixel.withUnsafeMutableBytes {
                            context.render(image, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                                           bounds: .init(x: point.x, y: point.y, width: CGFloat(width), height: 1), format: .RGBAf,
                                           colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
                        }
                        for x in 0..<width { pixels.append(pixel[x * 4]) }
                    }
                    #expect(reader.status == .completed, "HDR frames must decode to completion")
                    continuation.resume(returning: pixels)
                } catch { continuation.resume(throwing: error) }
            })
        }
    }

    private static func sample(time: Double, localDisplay: Bool, hlg: Bool = false) throws -> ScreenRecordingCaptureSample {
        var buffer: CVPixelBuffer?
        try #require(CVPixelBufferCreate(nil, 64, 48,
                                         localDisplay ? kCVPixelFormatType_444YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                         [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer) == kCVReturnSuccess)
        let pixels = try #require(buffer)
        CVBufferSetAttachment(pixels, kCVImageBufferColorPrimariesKey,
                              localDisplay ? kCVImageBufferColorPrimaries_P3_D65 : kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
        CVBufferSetAttachment(pixels, kCVImageBufferTransferFunctionKey,
                              hlg ? kCVImageBufferTransferFunction_ITU_R_2100_HLG : kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, .shouldPropagate)
        CVBufferSetAttachment(pixels, kCVImageBufferYCbCrMatrixKey,
                              localDisplay ? kCVImageBufferYCbCrMatrix_ITU_R_709_2 : kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
        CIContext().render(CIImage(cgImage: try image()), to: pixels, bounds: .init(x: 0, y: 0, width: 64, height: 48),
                           colorSpace: CGColorSpace(name: hlg
                               ? (localDisplay ? CGColorSpace.displayP3_HLG : CGColorSpace.itur_2100_HLG)
                               : (localDisplay ? CGColorSpace.displayP3_PQ : CGColorSpace.itur_2100_PQ)))
        var format: CMVideoFormatDescription?
        try #require(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels,
                                                                  formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 30),
                                        presentationTimeStamp: .init(seconds: time, preferredTimescale: 60_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        try #require(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels,
                                                              formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return .init(buffer: try #require(sample), kind: .screen, hostTime: time)
    }
}

private final class HDRCaptureTestAsset: ScreenRecordingCaptureAssetWriter {
    var first: CMSampleBuffer?
    var samples: [CMSampleBuffer] = []

    func append(_ sample: CMSampleBuffer, kind: ScreenRecordingSampleKind) throws -> Bool { samples.append(sample); return true }
    func finish(at time: Double, completion: @escaping @Sendable (Result<Void, Error>) -> Void) { completion(.success(())) }
    func cancel() {}
}
