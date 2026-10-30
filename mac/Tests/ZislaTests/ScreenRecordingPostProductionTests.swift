import AVFoundation
import CoreImage
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingPostProductionTests {
    private func project() -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Demo", videoFile: "screen.mp4", duration: 1, width: 64, height: 48)
        project.edits.background = .none
        project.edits.padding = 0
        project.edits.cornerRadius = 0
        project.edits.shadow = 0
        project.edits.showCursor = false
        return project
    }

    @Test(arguments: [true, false], [true, false])
    func audioLevelsFollowTheActualAvailableSources(_ screenAudio: Bool, _ microphone: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createScreenVideo(withAudio: screenAudio)
        var project = self.project()
        if microphone {
            try fixture.createTone(name: "microphone.m4a")
            project.microphoneFile = "microphone.m4a"
        }
        project.edits.screenAudioVolume = 0.25
        project.edits.microphoneVolume = 0.75
        project.edits.segments = [.init(start: 0, end: 1, speed: 2)]
        let media = try await RecordingExportMedia.prepare(project: project, directory: fixture.directory,
            timeline: RecordingExportTimeline(project: project))
        let expected: [Float] = (screenAudio ? [0.25] : []) + (microphone ? [0.75] : [])

        expectVolumes(media.audioMix(for: media.audioTracks), equal: expected)
        let item = try await ScreenRecordingExporter().playbackItem(project: project, directory: fixture.directory)
        if expected.isEmpty {
            #expect(item.audioMix == nil)
            #expect(media.audioTracks.isEmpty)
        } else {
            expectVolumes(try #require(item.audioMix), equal: expected)
        }
        #expect(abs(try await item.asset.load(.duration).seconds - 0.5) < 0.001)
    }

    @Test func mutingEitherSourceKeepsTheOtherSourcesAuthoredLevel() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createScreenVideo(withAudio: true)
        try fixture.createTone(name: "microphone.m4a")
        var project = self.project()
        project.microphoneFile = "microphone.m4a"

        for (screenLevel, microphoneLevel) in [(0.0, 0.75), (0.25, 0.0)] {
            project.edits.screenAudioVolume = screenLevel
            project.edits.microphoneVolume = microphoneLevel
            let media = try await RecordingExportMedia.prepare(project: project, directory: fixture.directory,
                timeline: RecordingExportTimeline(project: project))
            expectVolumes(media.audioMix(for: media.audioTracks), equal: [Float(screenLevel), Float(microphoneLevel)])
        }
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("screen.mp4").path))
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("microphone.m4a").path))
    }

    @Test func hidingCameraRemovesItsPixelsAndShowingItRestoresTheSameMedia() throws {
        var project = self.project()
        project.cameraFile = "camera.mp4"
        project.edits.cameraRound = false
        project.edits.cameraCornerRadius = 0
        project.edits.cameraPosition = .topLeft
        project.edits.cameraSize = 0.5
        let size = CGSize(width: 160, height: 120)
        let screen = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(origin: .zero, size: size))
        let camera = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))
        let visible = try RecordingExportRenderer(project: project, size: size)
            .image(screen: screen, camera: camera, sourceTime: 0)
        project.edits.showCamera = false
        let hidden = try RecordingExportRenderer(project: project, size: size)
            .image(screen: screen, camera: camera, sourceTime: 0)
        let absent = try RecordingExportRenderer(project: project, size: size)
            .image(screen: screen, camera: nil, sourceTime: 0)

        #expect(try pixel(visible, x: 24, y: 20) == [0, 255, 0])
        #expect(try pixel(hidden, x: 24, y: 20) == [0, 0, 255])
        #expect(try pixel(hidden, x: 24, y: 20) == pixel(absent, x: 24, y: 20))
        #expect(project.cameraFile == "camera.mp4")
        project.edits.showCamera = true
        let restored = try RecordingExportRenderer(project: project, size: size)
            .image(screen: screen, camera: camera, sourceTime: 0)
        #expect(try pixel(restored, x: 24, y: 20) == pixel(visible, x: 24, y: 20))
    }

    @Test func editedPlaybackDecodesEveryFrameOfRepeatedStaticCutsAndSourceTimedAnnotations() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createScreenVideo(withAudio: false, colors: [
            .init(red: 1, green: 0, blue: 0), .init(red: 0, green: 0, blue: 1),
        ])
        var project = self.project()
        project.edits.segments = [.init(start: 0.6, end: 0.9, speed: 2),
                                  .init(start: 0.1, end: 0.4, speed: 0.5),
                                  .init(start: 0.6, end: 0.9)]
        project.edits.annotations = [.init(kind: .arrow, start: 0.6, end: 0.9,
            x: 0.1, y: 0.25, endX: 0.4, endY: 0.25, color: .init(red: 0, green: 1, blue: 0), lineWidth: 0.05)]
        let item = try await ScreenRecordingExporter().playbackItem(project: project, directory: fixture.directory)
        let reader = try AVAssetReader(asset: item.asset)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: try await item.asset.loadTracks(withMediaType: .video), videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
        output.videoComposition = try #require(item.videoComposition)
        reader.add(output)
        try #require(reader.startReading(), "Continuous edited playback must start decoding")
        let context = CIContext()
        var frameCount = 0
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            #expect(abs(time - Double(frameCount) / 30) < 0.000_01)
            let buffer = try #require(CMSampleBufferGetImageBuffer(sample))
            let source = CIImage(cvPixelBuffer: buffer)
            let image = try #require(context.createCGImage(source, from: source.extent))
            let center = try pixel(image, x: 32, y: 24)
            let blue = time < 0.15 || time >= 0.75
            #expect(blue ? center[2] > 200 && center[0] < 40 : center[0] > 200 && center[2] < 40,
                    "Repeated sparse cuts must keep the frame spanning each source cut")
            #expect((try pixel(image, x: 16, y: 12)[1] > 200) == blue,
                    "Annotations must follow source time across reordered and repeated cuts")
            frameCount += 1
        }
        #expect(reader.status == .completed, "Every composed frame must decode without a missing-frame failure")
        #expect(reader.error == nil)
        #expect(frameCount == 32, "The complete 1.05-second timeline must contain 32 frames at 30 FPS")
    }

    @Test func anEmptyCameraTrackRejectsPlaybackWithoutChangingTheScreenMedia() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createScreenVideo(withAudio: false)
        let screen = fixture.directory.appendingPathComponent("screen.mp4")
        let original = try Data(contentsOf: screen)
        try Data().write(to: fixture.directory.appendingPathComponent("camera.mp4"))
        var project = self.project()
        project.cameraFile = "camera.mp4"
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted()

        await #expect(throws: ScreenRecordingProjectError.missingMedia) {
            _ = try await ScreenRecordingExporter().playbackItem(project: project, directory: fixture.directory)
        }

        #expect(try Data(contentsOf: screen) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted() == files)
    }

    @Test func cancellingPlaybackPreparationKeepsTheSourceMediaAndAllowsASecondAttempt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createScreenVideo(withAudio: false)
        let screen = fixture.directory.appendingPathComponent("screen.mp4")
        let original = try Data(contentsOf: screen)
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted()
        let project = self.project()
        let exporter = ScreenRecordingExporter()
        let worker = Task { try await exporter.playbackItem(project: project, directory: fixture.directory) }
        worker.cancel()

        await #expect(throws: CancellationError.self) { _ = try await worker.value }
        #expect(try Data(contentsOf: screen) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted() == files)
        let retry = try await exporter.playbackItem(project: project, directory: fixture.directory)
        #expect(try await retry.asset.load(.duration).seconds == 1)
    }

    private func expectVolumes(_ mix: AVAudioMix, equal expected: [Float]) {
        #expect(mix.inputParameters.count == expected.count)
        for (parameters, value) in zip(mix.inputParameters, expected) {
            var start: Float = -1
            var end: Float = -1
            var range = CMTimeRange.invalid
            #expect(parameters.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: &range))
            #expect(abs(start - value) < 0.000_01)
            #expect(abs(end - value) < 0.000_01)
        }
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(data: pointer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (y * image.width + x) * 4
        return Array(bytes[offset..<offset + 3])
    }

    @MainActor
    private final class Fixture {
        let directory: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-recording-levels-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }

        func createTone(name: String) throws {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
            let file = try AVAudioFile(forWriting: directory.appendingPathComponent(name), settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000,
            ])
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
            buffer.frameLength = 48_000
            let channel = try #require(buffer.floatChannelData?[0])
            for index in 0..<48_000 { channel[index] = Float(0.15 * sin(2 * Double.pi * 440 * Double(index) / 48_000)) }
            try file.write(from: buffer)
        }

        func createScreenVideo(withAudio: Bool, colors: [CIColor] = [.black, .black]) async throws {
            let plain = directory.appendingPathComponent(withAudio ? "plain.mp4" : "screen.mp4")
            let writer = try AVAssetWriter(outputURL: plain, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
            ])
            writer.add(input)
            #expect(writer.startWriting())
            writer.startSession(atSourceTime: .zero)
            let context = CIContext()
            for (index, color) in colors.enumerated() {
                while !input.isReadyForMoreMediaData { await Task.yield() }
                var buffer: CVPixelBuffer?
                #expect(CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer) == kCVReturnSuccess)
                context.render(CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48)),
                    to: try #require(buffer))
                #expect(adaptor.append(try #require(buffer), withPresentationTime: CMTime(value: Int64(index), timescale: 2)))
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
            await writer.finishWriting()
            #expect(writer.status == .completed)
            if withAudio {
                try createTone(name: "system.m4a")
                try await NativeMediaMuxer().mux(videoURL: plain, audioURL: directory.appendingPathComponent("system.m4a"),
                    outputURL: directory.appendingPathComponent("screen.mp4"))
            }
        }
    }
}
