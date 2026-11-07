import AVFoundation
import CoreImage
import Foundation
import Testing
import ZislaCore
@testable import Zisla

@MainActor
struct ScreenRecordingPortraitCaptureTests {
    @Test func nativeCapturePublishesEnhancedAndOriginalMediaThatReopensWithItsEffects() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: fixture.directory)
        let configuration = RecordingCaptureConfiguration(systemAudio: false, microphone: true, camera: true,
            portraitEffects: .init(brightening: 1), voiceEffects: .init(preset: .broadcast, amount: 0.8))
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: configuration, width: 64, height: 48,
            onFailure: { Issue.record("Native synthetic capture must encode: \($0)") },
            portraitProcessor: RecordingPortraitProcessor { _, _, _ in .init(faces: [.init(x: 0.1, y: 0.1, width: 0.8, height: 0.8)]) })
        writer.receive(try video(time: 100, kind: .screen))
        for index in 0..<10 {
            writer.receive(try audio(time: 100.125 + Double(index) / 100))
            if index % 3 == 0 { writer.receive(try video(time: 100.125 + Double(index) / 100, kind: .camera)) }
            await writer.flush()
        }
        await writer.seal(at: 100.5)
        let duration = try await writer.finish()
        let result = ScreenRecordingResult(videoFile: files.screenName, cameraFile: files.cameraName, microphoneFile: files.microphoneName,
            duration: duration, width: 64, height: 48, rawCameraFile: files.rawCameraName, rawMicrophoneFile: files.rawMicrophoneName,
            portraitEffects: configuration.portraitEffects, voiceEffects: configuration.voiceEffects)
        var project = ScreenRecordingProject(result: result, name: "Native portrait capture")
        try files.publish(project.mediaFiles)
        defer { _ = files.discard() }
        try fixture.store.save(project, in: fixture.directory)
        #expect(try fixture.store.load(from: fixture.directory) == project)
        let enhancedCamera = try await RecordingMultitrackTestFixture.decode(AVURLAsset(url: fixture.directory.appendingPathComponent(files.cameraName)))
        let rawCamera = try await RecordingMultitrackTestFixture.decode(AVURLAsset(url: fixture.directory.appendingPathComponent(files.rawCameraName)))
        let enhanced = try #require(enhancedCamera.first { $0.0 >= 0.125 })
        let raw = try #require(rawCamera.first { $0.0 >= 0.125 })
        #expect(enhancedCamera.map(\.0) == rawCamera.map(\.0))
        #expect(enhanced.0 == 0.125 && raw.0 == 0.125)
        #expect(try RecordingMultitrackTestFixture.pixel(enhanced.1, x: 32, y: 24)
            != RecordingMultitrackTestFixture.pixel(raw.1, x: 32, y: 24))
        for name in [files.microphoneName, files.rawMicrophoneName] {
            let asset = AVURLAsset(url: fixture.directory.appendingPathComponent(name))
            let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
            let segments = try await track.load(.segments).filter { !$0.isEmpty }
            let range = CMTimeRange(start: try #require(segments.first?.timeMapping.target.start),
                end: try #require(segments.last?.timeMapping.target.end))
            #expect(abs(range.start.seconds - 0.125) < 0.001 && range.end.seconds > 0.2)
        }
        project.edits.portraitEffects = .init()
        project.edits.voiceEffects = .init()
        let playback = try await ScreenRecordingExporter().playbackItem(project: project, directory: fixture.directory)
        #expect(try await playback.asset.load(.duration).seconds > 0.4)
        #expect(try fixture.files() == (project.mediaFiles + ["project.json"]).sorted())
    }

    @Test func liveCaptureWritesEnhancedAndOriginalTracksWithMatchingTimestampsAndCleansAllWriters() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: fixture.directory)
        let outputs = Outputs()
        let portrait = RecordingPortraitProcessor { _, _, _ in .init(faces: [.init(x: 0.15, y: 0.15, width: 0.7, height: 0.7)]) }
        let writer = ScreenRecordingCaptureWriter(files: files,
            configuration: .init(microphone: true, camera: true, portraitEffects: .init(brightening: 1),
                voiceEffects: .init(preset: .broadcast, amount: 0.8)), width: 64, height: 48,
            onFailure: { Issue.record("Synthetic capture must not fail: \($0)") }, factory: outputs.make,
            portraitProcessor: portrait)
        writer.receive(try video(time: 100, kind: .screen))
        writer.receive(try video(time: 100.125, kind: .camera))
        writer.receive(try audio(time: 100.25))
        await writer.flush()
        #expect(try await writer.waitForFirstFrame() == 100)
        let camera = try #require(outputs.items[files.cameraName]?.samples.first)
        let cameraRaw = try #require(outputs.items[files.rawCameraName]?.samples.first)
        let microphone = try #require(outputs.items[files.microphoneName]?.samples.first)
        let microphoneRaw = try #require(outputs.items[files.rawMicrophoneName]?.samples.first)
        #expect(camera.presentationTimeStamp == cameraRaw.presentationTimeStamp && camera.presentationTimeStamp.seconds == 0.125)
        #expect(microphone.presentationTimeStamp == microphoneRaw.presentationTimeStamp && microphone.presentationTimeStamp.seconds == 0.25)
        #expect(try pixel(camera) != pixel(cameraRaw), "Real-time portrait processing must change the written camera pixels")
        #expect(try bytes(microphone) != bytes(microphoneRaw), "Real-time voice processing must change the written PCM")
        #expect(camera.duration == cameraRaw.duration && microphone.duration == microphoneRaw.duration)
        await writer.seal(at: 101)
        #expect(try await writer.finish() == 1)
        #expect(outputs.items.count == 5 && outputs.items.values.allSatisfy { $0.finished })
        await writer.cancel()
        #expect(outputs.items.values.allSatisfy { $0.cancelled })
        #expect(files.discard() == nil)
        #expect(try fixture.files().isEmpty)
    }

    @Test func originalCameraBackpressureDropsOnlyItsFrameAndAllowsCaptureToRecover() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: fixture.directory)
        let outputs = Outputs()
        outputs.blockedName = files.rawCameraName
        let writer = ScreenRecordingCaptureWriter(files: files,
            configuration: .init(camera: true, portraitEffects: .init(smoothing: 0.5)), width: 64, height: 48,
            onFailure: { Issue.record("Video backpressure must not stop capture: \($0)") }, factory: outputs.make)
        writer.receive(try video(time: 100, kind: .screen))
        writer.receive(try video(time: 100.1, kind: .camera))
        await writer.flush()
        #expect(outputs.items[files.cameraName]?.samples.isEmpty == true)
        #expect(outputs.items[files.rawCameraName]?.samples.isEmpty == true)
        outputs.items[files.rawCameraName]?.accepts = true
        writer.receive(try video(time: 100.2, kind: .camera))
        await writer.flush()
        await writer.seal(at: 101)
        #expect(try await writer.finish() == 1)
        #expect(outputs.items[files.cameraName]?.samples.count == 1 && outputs.items[files.rawCameraName]?.samples.count == 1)
        #expect(files.discard() == nil)
    }

    @Test func microphoneMonitorFailureClosesMonitoringAndKeepsBothRecordingTracksWritable() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: fixture.directory)
        let outputs = Outputs()
        let monitor = RecordingVoiceMonitor(makeOutput: { FailingMonitor() })
        let failures = Failures()
        let writer = ScreenRecordingCaptureWriter(files: files,
            configuration: .init(microphone: true, voiceEffects: .init(preset: .natural, amount: 0.8), monitorMicrophone: true),
            width: 64, height: 48, onFailure: { Issue.record("A failed optional monitor must not cancel recording: \($0)") },
            factory: outputs.make, monitor: monitor, onMonitoringFailure: failures.append)
        writer.receive(try video(time: 100, kind: .screen))
        writer.receive(try audio(time: 100.1))
        writer.receive(try audio(time: 100.2))
        await writer.flush()
        #expect(!monitor.isEnabled && failures.count == 1)
        #expect(outputs.items[files.microphoneName]?.samples.count == 2 && outputs.items[files.rawMicrophoneName]?.samples.count == 2)
        await writer.setPaused(true, at: 100.3)
        await writer.setPaused(false, at: 100.4)
        writer.receive(try audio(time: 100.5))
        await writer.flush()
        #expect(failures.count == 1, "Resume must keep a failed monitor disabled")
        await writer.seal(at: 101)
        #expect(try await writer.finish() > 0)
        #expect(outputs.items.values.allSatisfy { $0.finished })
        #expect(files.discard() == nil)
    }

    @Test func originalAudioRejectionFailsCaptureAndCancelsEveryAllocatedTrack() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: fixture.directory)
        let outputs = Outputs()
        outputs.blockedName = files.rawMicrophoneName
        let failures = Failures()
        let writer = ScreenRecordingCaptureWriter(files: files,
            configuration: .init(microphone: true, voiceEffects: .init(preset: .warm)), width: 64, height: 48,
            onFailure: failures.append, factory: outputs.make)
        writer.receive(try video(time: 100, kind: .screen))
        writer.receive(try audio(time: 100.125))
        await writer.flush()
        #expect(failures.count == 1)
        #expect(outputs.items.count == 3 && outputs.items.values.allSatisfy { $0.cancelled })
        await writer.seal(at: 101)
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try await writer.finish() }
        #expect(files.discard() == nil)
    }

    @Test func originalFinishFailureCancelsAllTracksAndReleasesOnCancellation() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: fixture.directory)
        let outputs = Outputs()
        outputs.heldName = files.rawCameraName
        let failures = Failures()
        let writer = ScreenRecordingCaptureWriter(files: files,
            configuration: .init(camera: true, portraitEffects: .init(brightening: 1)), width: 64, height: 48,
            onFailure: failures.append, factory: outputs.make,
            portraitProcessor: RecordingPortraitProcessor { _, _, _ in .init(faces: [.init(x: 0, y: 0, width: 1, height: 1)]) })
        writer.receive(try video(time: 100, kind: .screen))
        writer.receive(try video(time: 100.125, kind: .camera))
        await writer.flush()
        var original: Output? = try #require(outputs.items[files.rawCameraName])
        weak var retained = original
        await writer.seal(at: 101)
        let task = Task { try await writer.finish() }
        _ = try await original!.finishStarted.wait(timeout: 2)
        await writer.flush()
        #expect(original?.finished == false && outputs.items[files.cameraName]?.finished == true)
        original?.completeFinish(.failure(ScreenRecordingCaptureError.writerUnavailable))
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try await task.value }
        #expect(original?.finished == true)
        #expect(failures.count == 1 && outputs.items.values.allSatisfy { $0.cancelled })
        await writer.cancel()
        #expect(original?.cancelled == true)
        outputs.items.removeAll()
        original = nil
        #expect(retained == nil, "Cancellation must release the original writer")
        #expect(files.discard() == nil)
    }

    @Test func portraitCapturePreservesResizingTimingAndAttachments() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: fixture.directory)
        let outputs = Outputs()
        let writer = ScreenRecordingCaptureWriter(files: files,
            configuration: .init(camera: true, portraitEffects: .init(brightening: 0.5)), width: 64, height: 48,
            onFailure: { Issue.record("Resized camera capture must not fail: \($0)") }, factory: outputs.make,
            portraitProcessor: RecordingPortraitProcessor { _, _, _ in .init(faces: [.init(x: 0, y: 0, width: 1, height: 1)]) })
        writer.receive(try video(time: 100, kind: .screen))
        for (index, size) in [CGSize(width: 64, height: 48), CGSize(width: 32, height: 24)].enumerated() {
            let sample = try video(time: 100.125 + Double(index) * 0.125, kind: .camera, size: size)
            let source = try #require(sample.buffer.imageBuffer)
            CVBufferSetAttachment(source, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CMSetAttachment(sample.buffer, key: kCMSampleBufferAttachmentKey_DisplayEmptyMediaImmediately,
                value: kCFBooleanTrue, attachmentMode: kCMAttachmentMode_ShouldPropagate)
            writer.receive(sample)
            await writer.flush()
            let enhanced = try #require(outputs.items[files.cameraName]?.samples.last)
            let original = try #require(outputs.items[files.rawCameraName]?.samples.last)
            let image = try #require(enhanced.imageBuffer)
            #expect(CVPixelBufferGetWidth(image) == Int(size.width) && CVPixelBufferGetHeight(image) == Int(size.height))
            #expect(enhanced.presentationTimeStamp == original.presentationTimeStamp && enhanced.duration == original.duration)
            #expect(enhanced.decodeTimeStamp == original.decodeTimeStamp)
            #expect(CVBufferCopyAttachment(image, kCVImageBufferColorPrimariesKey, nil) as? String == kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
            #expect(CMGetAttachment(enhanced, key: kCMSampleBufferAttachmentKey_DisplayEmptyMediaImmediately, attachmentModeOut: nil) as? Bool == true)
        }
        await writer.cancel()
        #expect(files.discard() == nil)
    }

    private func video(time: Double, kind: ScreenRecordingSampleKind, size: CGSize = .init(width: 64, height: 48)) throws -> ScreenRecordingCaptureSample {
        var pixel: CVPixelBuffer?
        try #require(CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &pixel) == kCVReturnSuccess)
        let buffer = try #require(pixel)
        CIContext().render(CIImage(color: .init(red: 0.3, green: 0.25, blue: 0.2)).cropped(to: CGRect(origin: .zero, size: size)),
            to: buffer, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var format: CMVideoFormatDescription?
        try #require(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 30),
            presentationTimeStamp: .init(seconds: time, preferredTimescale: 1_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        try #require(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: try #require(format),
            sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return .init(buffer: try #require(sample), kind: kind, hostTime: time)
    }

    private func audio(time: Double) throws -> ScreenRecordingCaptureSample {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: true))
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        pcm.frameLength = 480
        for index in 0..<480 { pcm.floatChannelData![0][index] = Float(0.15 * sin(Double(index) * 2 * .pi * 440 / 48_000)) }
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 48_000),
            presentationTimeStamp: .init(seconds: time, preferredTimescale: 1_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        var size = 4
        try #require(CMSampleBufferCreateReady(allocator: nil, dataBuffer: nil, formatDescription: format.formatDescription,
            sampleCount: 480, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
            sampleSizeArray: &size, sampleBufferOut: &sample) == noErr)
        let result = try #require(sample)
        try #require(CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, bufferList: pcm.audioBufferList) == noErr)
        return .init(buffer: result, kind: .microphone, hostTime: time)
    }

    private func pixel(_ sample: CMSampleBuffer) throws -> [UInt8] {
        let image = CIImage(cvPixelBuffer: try #require(sample.imageBuffer))
        let cg = try #require(CIContext().createCGImage(image, from: image.extent))
        return try RecordingMultitrackTestFixture.pixel(cg, x: 32, y: 24)
    }

    private func bytes(_ sample: CMSampleBuffer) throws -> Data {
        let block = try #require(sample.dataBuffer)
        var data = Data(count: block.dataLength)
        let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: block.dataLength, destination: $0.baseAddress!) }
        try #require(status == noErr)
        return data
    }
}

private final class Outputs: @unchecked Sendable {
    var items: [String: Output] = [:]
    var blockedName: String?
    var heldName: String?
    func make(_ url: URL, _ kind: ScreenRecordingSampleKind, _ sample: CMSampleBuffer) throws -> any ScreenRecordingCaptureAssetWriter {
        let output = Output()
        output.accepts = blockedName != url.lastPathComponent
        output.holdsFinish = heldName == url.lastPathComponent
        items[url.lastPathComponent] = output
        return output
    }
}

private final class Output: ScreenRecordingCaptureAssetWriter {
    var samples: [CMSampleBuffer] = []
    var accepts = true
    var finished = false
    var cancelled = false
    var holdsFinish = false
    let finishStarted = ScreenRecordingCaptureStartGate()
    private var finishCompletion: (@Sendable (Result<Void, Error>) -> Void)?
    func append(_ sample: CMSampleBuffer, kind: ScreenRecordingSampleKind) throws -> Bool {
        if accepts { samples.append(sample) }
        return accepts
    }
    func finish(at time: Double, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        finishStarted.resolve(.success(time))
        if holdsFinish { finishCompletion = completion }
        else { finished = true; completion(.success(())) }
    }
    func completeFinish(_ result: Result<Void, Error>) { finished = true; finishCompletion?(result); finishCompletion = nil }
    func cancel() { cancelled = true; finishCompletion = nil }
}

private final class Failures: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func append(_ error: Error) { lock.withLock { value += 1 } }
}

private final class FailingMonitor: RecordingVoiceMonitorOutput {
    func start(format: AVAudioFormat) throws { throw ScreenRecordingCaptureError.deviceUnavailable }
    func append(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void) throws {}
    func stop() {}
}
