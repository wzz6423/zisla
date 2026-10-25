import AVFoundation
import CoreMedia
import CoreVideo
import Testing
import ZislaCore
@testable import Zisla

@Suite(.serialized)
@MainActor
struct ScreenRecordingCaptureTimingTests {
    @Test(arguments: [8_000.0, 16_000.0, 24_000.0, 44_100.0, 48_000.0], [UInt32(1), UInt32(2)])
    func microphoneAACSupportsLowSampleRatesAndBothChannelLayouts(sampleRate: Double, channels: UInt32) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, microphone: true),
                                                  width: 16, height: 16, onFailure: { _ in })
        writer.receive(try video(at: 100))
        await writer.flush()
        #expect(try await writer.waitForFirstFrame() == 100)
        writer.receive(try audio(at: 100.01, sampleRate: sampleRate, channels: channels, floatingPoint: true, kind: .microphone))
        await writer.flush()
        await writer.seal(at: 101)
        #expect(try await writer.finish() == 1)
        try files.publish([files.screenName, files.microphoneName])
        let asset = AVURLAsset(url: directory.appendingPathComponent(files.microphoneName))
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.load(.duration).seconds > 0)
    }

    @Test
    func stereoMicrophoneKeepsTheExistingEncodedBitrateBudget() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, microphone: true),
                                                  width: 16, height: 16, onFailure: { _ in })
        writer.receive(try video(at: 100))
        await writer.flush()
        var seed: UInt64 = 0x19A8
        for index in 0..<100 {
            let sample = try audio(at: 100 + Double(index) / 100, sampleRate: 48_000, channels: 2,
                                   floatingPoint: true, kind: .microphone)
            let block = try #require(CMSampleBufferGetDataBuffer(sample.buffer))
            let noise: [Float] = (0..<960).map { _ in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                return Float(Int32(truncatingIfNeeded: seed >> 32)) / Float(Int32.max)
            }
            #expect(noise.withUnsafeBytes {
                CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                              offsetIntoDestination: 0, dataLength: $0.count)
            } == noErr)
            writer.receive(sample)
            await writer.flush()
        }
        await writer.seal(at: 101)
        _ = try await writer.finish()
        try files.publish([files.screenName, files.microphoneName])
        let asset = AVURLAsset(url: directory.appendingPathComponent(files.microphoneName))
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let bitrate = try await track.load(.estimatedDataRate)
        #expect(bitrate > 128_000 && bitrate < 250_000, "Stereo microphone output must retain its existing 192 kbps budget: \(bitrate)")
    }

    @Test(arguments: [0.0, 20.0])
    func timestampsThatBecomeEqualAtTheWriterTimescaleAreNotAppended(pause: Double) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        let asset = CaptureTimingTestAsset()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false),
                                                  width: 16, height: 16, onFailure: { _ in }, factory: { _, _, _ in asset })
        writer.receive(try video(at: 100))
        writer.receive(try video(at: 100.1000001))
        await writer.flush()
        await writer.setPaused(true, at: 100.1000002)
        await writer.setPaused(false, at: 100.1000002 + pause)
        writer.receive(try video(at: 100.1000004 + pause))
        writer.receive(try video(at: 100.1333337 + pause))
        await writer.seal(at: 101 + pause)
        _ = try await writer.finish()
        #expect(asset.times == [0, 0.1, 0.133333])
    }

    @Test(arguments: [0.1234564, 0.1234566])
    func finalScreenFrameDoesNotBecomeItsOwnDuplicateTail(lastTime: Double) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false),
                                                  width: 16, height: 16, onFailure: { _ in })
        writer.receive(try video(at: 100))
        await writer.flush()
        try await Task.sleep(for: .milliseconds(20))
        writer.receive(try video(at: 100 + lastTime))
        await writer.flush()
        try await Task.sleep(for: .milliseconds(20))
        await writer.seal(at: 100 + lastTime + 0.001)
        let duration = try await writer.finish()
        #expect(abs(duration - (lastTime + 1.0 / 30)) < 0.000_001)
        try files.publish([files.screenName])
        let asset = AVURLAsset(url: directory.appendingPathComponent(files.screenName))
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.load(.duration).seconds > lastTime)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        #expect(reader.startReading())
        var times: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0, CMSampleBufferGetPresentationTimeStamp(sample).isNumeric {
                times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            }
        }
        #expect(reader.status == .completed)
        #expect(times.count == 2, "Recorded times: \(times)")
    }

    @Test(arguments: [0.0, 3.0, 20.0])
    func pausedAudioPacketsThatStraddleTheBoundaryFinishAReadableVideo(pause: Double) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: true),
                                                  width: 16, height: 16, onFailure: { _ in })
        for frame in 0..<30 {
            writer.receive(try video(at: 100 + Double(frame) / 30))
            await writer.flush()
            writer.receive(try audio(at: 100 + Double(frame) / 30))
            await writer.flush()
        }
        // The last packet starts before pause, but ends five milliseconds into it.
        writer.receive(try audio(at: 100.995))
        await writer.flush()
        await writer.setPaused(true, at: 101)
        await writer.setPaused(false, at: 101 + pause)
        for frame in 0..<30 {
            let time = 101 + pause + Double(frame) / 30
            writer.receive(try video(at: time))
            await writer.flush()
            writer.receive(try audio(at: time))
            await writer.flush()
        }
        await writer.seal(at: 102 + pause)
        #expect(abs(try await writer.finish() - 2) < 0.000_001)
        try files.publish([files.screenName])
        let asset = AVURLAsset(url: directory.appendingPathComponent(files.screenName))
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.05)
    }

    @Test(arguments: [0.0, 20.0])
    func longScreenAndAudioRecordingFinalizesAfterResume(pause: Double) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: true),
                                                  width: 16, height: 16, onFailure: { _ in })
        for frame in 0..<1_050 {
            if frame == 300 {
                await writer.setPaused(true, at: 110)
                await writer.setPaused(false, at: 110 + pause)
            }
            let time = 100 + Double(frame) / 30 + (frame >= 300 ? pause : 0)
            writer.receive(try video(at: time))
            for packet in 0..<3 { writer.receive(try audio(at: time + Double(packet) / 100)) }
            await writer.flush()
            try await Task.sleep(for: .milliseconds(1))
        }
        try await Task.sleep(for: .milliseconds(20))
        writer.receive(try video(at: 135.1234564 + pause))
        await writer.flush()
        try await Task.sleep(for: .milliseconds(20))
        await writer.seal(at: 135.124 + pause)
        let duration = try await writer.finish()
        #expect(abs(duration - (35.1234564 + 1.0 / 30)) < 0.000_001)
        try files.publish([files.screenName])
        let asset = AVURLAsset(url: directory.appendingPathComponent(files.screenName))
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - duration) < 0.05)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        #expect(reader.startReading())
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetImageBuffer(sample) != nil { frames += 1 }
        }
        #expect(reader.status == .completed)
        #expect(frames >= 900, "Backpressure must not reduce the long recording fixture to a few samples: \(frames)")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-capture-timing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func video(at time: Double) throws -> ScreenRecordingCaptureSample {
        var pixel: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA,
                                   [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == kCVReturnSuccess)
        let image = try #require(pixel)
        CVPixelBufferLockBaseAddress(image, [])
        if let base = CVPixelBufferGetBaseAddress(image) { memset(base, 127, CVPixelBufferGetBytesPerRow(image) * 16) }
        CVPixelBufferUnlockBaseAddress(image, [])
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
                                                            formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 1_000_000_000),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
                                                        formatDescription: try #require(format), sampleTiming: &timing,
                                                        sampleBufferOut: &sample) == noErr)
        return ScreenRecordingCaptureSample(buffer: try #require(sample), kind: .screen, hostTime: time)
    }

    private func audio(at time: Double, sampleRate: Double = 48_000, channels: UInt32 = 2,
                       floatingPoint: Bool = false, kind: ScreenRecordingSampleKind = .systemAudio) throws -> ScreenRecordingCaptureSample {
        let bytesPerChannel: UInt32 = floatingPoint ? 4 : 2
        let bytesPerFrame = bytesPerChannel * channels
        let length = Int(bytesPerFrame) * 480
        var description = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                                                      mFormatFlags: (floatingPoint ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger) | kAudioFormatFlagIsPacked,
                                                      mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
                                                      mChannelsPerFrame: channels, mBitsPerChannel: bytesPerChannel * 8, mReserved: 0)
        var format: CMAudioFormatDescription?
        #expect(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0,
                                              layout: nil, magicCookieSize: 0, magicCookie: nil,
                                              extensions: nil, formatDescriptionOut: &format) == noErr)
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
                                                  blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                  offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block) == noErr)
        let data = try #require(block)
        #expect(CMBlockBufferFillDataBytes(with: 0, blockBuffer: data, offsetIntoDestination: 0, dataLength: length) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(sampleRate)),
                                        presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 1_000_000_000),
                                        decodeTimeStamp: .invalid)
        var sampleSize = Int(bytesPerFrame)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data, formatDescription: format,
                                          sampleCount: 480, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                          sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample) == noErr)
        return ScreenRecordingCaptureSample(buffer: try #require(sample), kind: kind, hostTime: time)
    }
}

private final class CaptureTimingTestAsset: ScreenRecordingCaptureAssetWriter {
    private(set) var times: [Double] = []

    func append(_ sample: CMSampleBuffer, kind: ScreenRecordingSampleKind) throws -> Bool {
        times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        return true
    }

    func finish(at time: Double, completion: @escaping @Sendable (Result<Void, Error>) -> Void) { completion(.success(())) }
    func cancel() {}
}
