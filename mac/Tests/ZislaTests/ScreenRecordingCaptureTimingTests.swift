import AVFoundation
import CoreMedia
import CoreVideo
import Testing
import ZislaCore
@testable import Zisla

@Suite(.serialized)
@MainActor
struct ScreenRecordingCaptureTimingTests {
    @Test(arguments: [8_000.0, 16_000.0, 24_000.0, 44_100.0, 48_000.0, 96_000.0], [UInt32(1), UInt32(2)])
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
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(tracks.count == 1)
        let track = try #require(tracks.first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let description = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format)).pointee
        #expect(description.mSampleRate == (sampleRate == 96_000 ? 48_000 : sampleRate))
        #expect(description.mChannelsPerFrame == channels)
        #expect(try await asset.load(.duration).seconds > 0)
    }

    @Test(arguments: [UInt32(1), UInt32(2)])
    func highSampleRateMicrophoneIsResampledWithoutChangingTheRecordedDuration(channels: UInt32) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, microphone: true),
                                                  width: 16, height: 16, onFailure: { _ in })
        writer.receive(try video(at: 100))
        await writer.flush()
        for index in 0..<100 {
            writer.receive(try audio(at: 100 + Double(index) / 200, sampleRate: 96_000, channels: channels,
                                     floatingPoint: true, kind: .microphone))
            await writer.flush()
        }
        await writer.seal(at: 100.5)
        #expect(abs(try await writer.finish() - 0.5) < 0.000_001)
        try files.publish([files.screenName, files.microphoneName])
        let asset = AVURLAsset(url: directory.appendingPathComponent(files.microphoneName))
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let description = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format)).pointee
        #expect(description.mSampleRate == 48_000)
        #expect(description.mChannelsPerFrame == channels)
        #expect(abs(try await asset.load(.duration).seconds - 0.5) < 0.03)
    }

    @Test(arguments: [UInt32(1), UInt32(2)])
    func microphoneKeepsTheExistingEncodedBitrateBudget(channels: UInt32) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, microphone: true),
                                                  width: 16, height: 16, onFailure: { _ in })
        writer.receive(try video(at: 100))
        await writer.flush()
        var seed: UInt64 = 0x19A8
        for index in 0..<100 {
            let sample = try audio(at: 100 + Double(index) / 100, sampleRate: 48_000, channels: channels,
                                   floatingPoint: true, kind: .microphone)
            let block = try #require(CMSampleBufferGetDataBuffer(sample.buffer))
            let noise: [Float] = (0..<(480 * Int(channels))).map { _ in
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
        let budget = 96_000 * Float(channels)
        #expect(bitrate > budget * 2 / 3 && bitrate < budget * 1.31,
                "Microphone output must retain its existing \(budget) bps budget: \(bitrate)")
    }

    @Test(arguments: [UInt32(4), UInt32(8), UInt32(16)], [false, true])
    func multichannelMicrophoneAACMixesTheLastInputChannelIntoStereo(channels: UInt32, includesLayout: Bool) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, microphone: true),
                                                  width: 16, height: 16, onFailure: { _ in })
        writer.receive(try video(at: 100))
        await writer.flush()
        let frames = 24_000
        let sample = try audio(at: 100, channels: channels, floatingPoint: true, kind: .microphone,
                               frameCount: frames, channelLayout: includesLayout ? kAudioChannelLayoutTag_DiscreteInOrder | channels : nil)
        let block = try #require(CMSampleBufferGetDataBuffer(sample.buffer))
        let values: [Float] = (0..<(frames * Int(channels))).map { index in
            index % Int(channels) == Int(channels) - 1
                ? Float(0.5 * sin(2 * Double.pi * 440 * Double(index / Int(channels)) / 48_000)) : 0
        }
        #expect(values.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: $0.count)
        } == noErr)
        writer.receive(sample)
        await writer.flush()
        await writer.seal(at: 100.5)
        #expect(abs(try await writer.finish() - 0.5) < 0.000_001)
        try files.publish([files.screenName, files.microphoneName])
        let asset = AVURLAsset(url: directory.appendingPathComponent(files.microphoneName))
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let description = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format)).pointee
        #expect(description.mFormatID == kAudioFormatMPEG4AAC)
        #expect(description.mChannelsPerFrame == 2)
        #expect(description.mSampleRate == 48_000)
        #expect(abs(try await asset.load(.duration).seconds - 0.5) < 0.03)
        let decoded = try await decodedAudio(asset)
        let window = decoded.dropFirst(4_800).prefix(14_400)
        var real = 0.0
        var imaginary = 0.0
        for (index, value) in window.enumerated() {
            let phase = 2 * Double.pi * 440 * Double(index) / 48_000
            real += Double(value) * cos(phase)
            imaginary += Double(value) * sin(phase)
        }
        let energy = (real * real + imaginary * imaginary) / Double(max(1, window.count * window.count))
        #expect(energy > 0.000_001, "The last of \(channels) input channels must remain audible after stereo mixing: \(energy)")
        #expect(!FileManager.default.fileExists(atPath: files.staging.path))
    }

    @Test(arguments: [UInt32(3), UInt32(4), UInt32(8), UInt32(16)], [(false, false), (false, true), (true, false), (true, true)])
    func microphoneStereoMixPreservesEveryInputAndNormalizesBothSides(channels: UInt32, pcmFormat: (Bool, Bool)) throws {
        let (floatingPoint, planar) = pcmFormat
        let frames = Int(channels) + 1
        let source = try audio(at: 100, channels: channels, floatingPoint: floatingPoint, kind: .microphone,
                               frameCount: frames, planar: planar)
        let block = try #require(source.buffer.dataBuffer)
        let values: [Float] = (0..<(frames * Int(channels))).map { index in
            let frame = planar ? index % frames : index / Int(channels)
            let channel = planar ? index / frames : index % Int(channels)
            return frame == Int(channels) || frame == channel ? 0.5 : 0
        }
        if floatingPoint {
            #expect(values.withUnsafeBytes {
                CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                              offsetIntoDestination: 0, dataLength: $0.count)
            } == noErr)
        } else {
            let integers = values.map { Int16($0 * 32_768) }
            #expect(integers.withUnsafeBytes {
                CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                              offsetIntoDestination: 0, dataLength: $0.count)
            } == noErr)
        }
        let format = try #require(source.buffer.formatDescription)
        let description = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format)).pointee
        var original = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(block))
        #expect(original.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        } == noErr)
        var mixer: ScreenRecordingCaptureAudioMixer? = try ScreenRecordingCaptureAudioMixer(description: description)
        weak var retainedMixer = mixer
        let output = try #require(mixer).mix(source.buffer)
        mixer = nil
        #expect(retainedMixer == nil, "The mixer must release its native converter with its owner")
        #expect(output.presentationTimeStamp == source.buffer.presentationTimeStamp)
        #expect(output.duration == source.buffer.duration)
        #expect(output.numSamples == frames)
        var unchanged = [UInt8](repeating: 0, count: original.count)
        #expect(unchanged.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        } == noErr)
        #expect(unchanged == original, "Mixing must not modify the captured PCM buffer")
        let data = try #require(output.dataBuffer)
        var decoded = [Float](repeating: 0, count: frames * 2)
        #expect(decoded.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        } == noErr)
        for channel in 0..<Int(channels) {
            let side = channel % 2
            let expected = 0.5 / Float((Int(channels) + 1 - side) / 2)
            #expect(abs(decoded[channel * 2 + side] - expected) < 0.000_001,
                    "Every input channel must reach its stereo side with normalized gain: \(channel)")
            #expect(abs(decoded[channel * 2 + 1 - side]) < 0.000_001)
        }
        #expect(abs(decoded[Int(channels) * 2] - 0.5) < 0.000_001)
        #expect(abs(decoded[Int(channels) * 2 + 1] - 0.5) < 0.000_001)
    }

    @Test
    func microphoneStereoMixRejectsCompressedInputBeforeAllocatingPCMStorage() throws {
        var description = AudioStreamBasicDescription()
        description.mFormatID = kAudioFormatMPEG4AAC
        description.mSampleRate = 48_000
        description.mChannelsPerFrame = 4
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) {
            try ScreenRecordingCaptureAudioMixer(description: description)
        }
    }

    @Test
    func microphoneStereoMixLeavesEmptyPacketsUnchangedAndRemainsUsable() throws {
        let source = try audio(at: 100, channels: 4, floatingPoint: true, kind: .microphone)
        let description = try #require(source.buffer.formatDescription.flatMap(CMAudioFormatDescriptionGetStreamBasicDescription)).pointee
        let mixer = try ScreenRecordingCaptureAudioMixer(description: description)
        var empty: CMSampleBuffer?
        #expect(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
                                          formatDescription: source.buffer.formatDescription, sampleCount: 0,
                                          sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                          sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &empty) == noErr)
        let packet = try #require(empty)
        #expect(try mixer.mix(packet) === packet)
        #expect(try mixer.mix(source.buffer).numSamples == source.buffer.numSamples)
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
                       floatingPoint: Bool = false, kind: ScreenRecordingSampleKind = .systemAudio,
                       frameCount: Int = 480, channelLayout: AudioChannelLayoutTag? = nil,
                       planar: Bool = false) throws -> ScreenRecordingCaptureSample {
        let bytesPerChannel: UInt32 = floatingPoint ? 4 : 2
        let bytesPerFrame = bytesPerChannel * (planar ? 1 : channels)
        let length = Int(bytesPerChannel * channels) * frameCount
        var description = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                                                      mFormatFlags: (floatingPoint ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger)
                                                          | kAudioFormatFlagIsPacked | (planar ? kAudioFormatFlagIsNonInterleaved : 0),
                                                      mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
                                                      mChannelsPerFrame: channels, mBitsPerChannel: bytesPerChannel * 8, mReserved: 0)
        var format: CMAudioFormatDescription?
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channelLayout ?? kAudioChannelLayoutTag_Unknown
        #expect(withUnsafePointer(to: &layout) { pointer in
            CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
                                           layoutSize: channelLayout == nil ? 0 : MemoryLayout<AudioChannelLayout>.size,
                                           layout: channelLayout == nil ? nil : pointer, magicCookieSize: 0, magicCookie: nil,
                                           extensions: nil, formatDescriptionOut: &format)
        } == noErr)
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
                                                  blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                  offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block) == noErr)
        let data = try #require(block)
        #expect(CMBlockBufferFillDataBytes(with: 0, blockBuffer: data, offsetIntoDestination: 0, dataLength: length) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(sampleRate)),
                                        presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 1_000_000_000),
                                        decodeTimeStamp: .invalid)
        var sampleSize = Int(bytesPerChannel * channels)
        var sample: CMSampleBuffer?
        #expect(withUnsafePointer(to: &sampleSize) { pointer in
            CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data, formatDescription: format,
                                      sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                      sampleSizeEntryCount: planar ? 0 : 1, sampleSizeArray: planar ? nil : pointer,
                                      sampleBufferOut: &sample)
        } == noErr)
        return ScreenRecordingCaptureSample(buffer: try #require(sample), kind: kind, hostTime: time)
    }

    nonisolated private func decodedAudio(_ asset: AVAsset) async throws -> [Float] {
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "zisla-test-microphone-decode").async(execute: DispatchWorkItem {
                do {
                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
                        AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
                        AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
                    ])
                    reader.add(output)
                    #expect(reader.startReading())
                    defer { reader.cancelReading() }
                    var decoded: [Float] = []
                    while let sample = output.copyNextSampleBuffer() {
                        let block = try #require(sample.dataBuffer)
                        let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
                        var values = [Float](repeating: 0, count: count)
                        #expect(values.withUnsafeMutableBytes {
                            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
                        } == noErr)
                        for frame in 0..<(count / 2) { decoded.append((values[frame * 2] + values[frame * 2 + 1]) / 2) }
                    }
                    #expect(reader.status == .completed)
                    continuation.resume(returning: decoded)
                } catch { continuation.resume(throwing: error) }
            })
        }
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
