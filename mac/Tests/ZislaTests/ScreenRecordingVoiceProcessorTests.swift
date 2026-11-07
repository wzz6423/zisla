import AVFoundation
import CoreMedia
import Testing
import ZislaCore
@testable import Zisla

struct ScreenRecordingVoiceProcessorTests {
    @Test func originalAndZeroStrengthReturnTheUntouchedSample() throws {
        let sample = try Self.sample([Self.tone(440, frames: 512)])
        CMSetAttachment(sample, key: "voice-fixture" as CFString, value: "preserved" as CFString, attachmentMode: kCMAttachmentMode_ShouldPropagate)
        let processor = RecordingVoiceProcessor()
        #expect(try processor.process(sample, effects: .init()) === sample)
        #expect(try processor.process(sample, effects: .init(preset: .warm, amount: 0)) === sample)
        #expect(try Self.samples(sample)[0] == Self.tone(440, frames: 512))
    }

    @Test func emptyPacketsDoNotAllocateOrAdvanceTheStream() throws {
        let valid = try Self.sample([Self.tone(440, frames: 512)])
        var empty: CMSampleBuffer?
        try #require(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
            formatDescription: valid.formatDescription, sampleCount: 0, sampleTimingEntryCount: 0,
            sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &empty) == noErr)
        let packet = try #require(empty)
        let effects = RecordingVoiceEffects(preset: .natural, amount: 1)
        let processor = RecordingVoiceProcessor()
        #expect(try processor.process(packet, effects: effects) === packet)
        #expect(try Self.samples(processor.process(valid, effects: effects)) == Self.samples(RecordingVoiceProcessor().process(valid, effects: effects)))
    }

    @Test func presetsChangeActualSpectralBalance() throws {
        let low = Self.tone(180, frames: 24_000, amplitude: 0.08)
        let high = Self.tone(6_000, frames: 24_000, amplitude: 0.08)
        let source = try Self.sample([zip(low, high).map { $0 + $1 }])
        var outputs: [RecordingVoicePreset: [Float]] = [:]
        for preset in [RecordingVoicePreset.natural, .warm, .bright, .broadcast] {
            let output = try RecordingVoiceProcessor().process(source, effects: .init(preset: preset, amount: 1))
            outputs[preset] = try Self.samples(output)[0]
        }
        let warm = try #require(outputs[.warm])
        let bright = try #require(outputs[.bright])
        #expect(Self.amplitude(warm, frequency: 180) > Self.amplitude(bright, frequency: 180) * 1.25)
        #expect(Self.amplitude(bright, frequency: 6_000) > Self.amplitude(warm, frequency: 6_000) * 1.4)
        for preset in outputs.keys {
            #expect(try outputs[preset] != Self.samples(source)[0], "Every voice preset must change PCM samples")
        }
    }

    @Test func strengthBlendsTheOriginalWithTheProcessedSignal() throws {
        let sample = try Self.sample([Self.tone(220, frames: 4_800)])
        let source = try Self.samples(sample)[0]
        let half = try Self.samples(RecordingVoiceProcessor().process(sample, effects: .init(preset: .warm, amount: 0.5)))[0]
        let full = try Self.samples(RecordingVoiceProcessor().process(sample, effects: .init(preset: .warm, amount: 1)))[0]
        #expect(zip(zip(source, half), full).allSatisfy { pair, wet in
            abs(Double(pair.1) - (Double(pair.0) + Double(wet)) / 2) < 0.000_001
        })
    }

    @Test func rumbleAndQuietNoiseDecreaseWhileBroadcastRaisesSpeechLevel() throws {
        let rumble = try Self.sample([Self.tone(20, frames: 24_000, amplitude: 0.1)])
        let speech = try Self.sample([Self.tone(440, frames: 24_000, amplitude: 0.06)])
        let quiet = try Self.sample([Self.tone(6_000, frames: 24_000, amplitude: 0.000_5)])
        let natural = RecordingVoiceEffects(preset: .natural, amount: 1)
        #expect(try Self.rms(Self.samples(RecordingVoiceProcessor().process(rumble, effects: natural))[0]) < Self.rms(Self.samples(rumble)[0]) * 0.4)
        #expect(try Self.rms(Self.samples(RecordingVoiceProcessor().process(quiet, effects: natural))[0]) < Self.rms(Self.samples(quiet)[0]) * 0.25)
        #expect(try Self.rms(Self.samples(RecordingVoiceProcessor().process(speech, effects: .init(preset: .broadcast, amount: 1)))[0]) > Self.rms(Self.samples(speech)[0]) * 1.35)
    }

    @Test(arguments: [AVAudioCommonFormat.pcmFormatFloat32, .pcmFormatFloat64, .pcmFormatInt16, .pcmFormatInt32], [true, false])
    func PCMFormatsPreserveChannelsLayoutAndTiming(_ commonFormat: AVAudioCommonFormat, _ interleaved: Bool) throws {
        let source = try Self.sample([Self.tone(180, frames: 2_048), Self.tone(2_000, frames: 2_048),
                                     [Float](repeating: 0, count: 2_048)], commonFormat: commonFormat, interleaved: interleaved)
        CMSetAttachment(source, key: "voice-fixture" as CFString, value: "preserved" as CFString, attachmentMode: kCMAttachmentMode_ShouldPropagate)
        let original = try Self.samples(source)
        let presentationTime = CMTime(seconds: 24, preferredTimescale: 48_000)
        try #require(CMSampleBufferSetOutputPresentationTimeStamp(source, newValue: presentationTime) == noErr)
        let output = try RecordingVoiceProcessor().process(source, effects: .init(preset: .broadcast, amount: 1))
        let actual = try Self.samples(output)
        #expect(output.numSamples == source.numSamples)
        #expect(output.duration == source.duration && output.presentationTimeStamp == source.presentationTimeStamp)
        #expect(output.decodeTimeStamp == source.decodeTimeStamp)
        #expect(output.outputPresentationTimeStamp == presentationTime)
        let outputDescription = try #require(output.formatDescription)
        let sourceDescription = try #require(source.formatDescription)
        #expect(CMFormatDescriptionEqual(outputDescription, otherFormatDescription: sourceDescription))
        #expect(CMGetAttachment(output, key: "voice-fixture" as CFString, attachmentModeOut: nil) as? String == "preserved")
        #expect(actual[0] != original[0] && actual[1] != original[1])
        #expect(actual[2].allSatisfy { $0 == 0 }, "A silent channel must not receive audio from adjacent channels")
        #expect(try Self.samples(source) == original, "Processing must not mutate captured source storage")
    }

    @Test func chunkBoundariesPreserveTheSameSignalAsOnePacket() throws {
        let source = Self.tone(440, frames: 8_192)
        let effects = RecordingVoiceEffects(preset: .broadcast, amount: 0.75)
        let expected = try Self.samples(RecordingVoiceProcessor().process(Self.sample([source]), effects: effects))[0]
        let processor = RecordingVoiceProcessor()
        var actual: [Float] = []
        for start in stride(from: 0, to: source.count, by: 256) {
            let sample = try Self.sample([Array(source[start..<start + 256])], time: 12 + Double(start) / 48_000)
            actual += try Self.samples(processor.process(sample, effects: effects))[0]
        }
        #expect(actual == expected, "Splitting microphone packets must not create clicks or change filter history")
    }

    @Test func presetFormatAndDisableTransitionsDiscardPriorAudioState() throws {
        let sample = try Self.sample([Self.tone(440, frames: 1_024)])
        let silent = try Self.sample([[Float](repeating: 0, count: 1_024)])
        let processor = RecordingVoiceProcessor()
        _ = try processor.process(sample, effects: .init(preset: .warm, amount: 1))
        #expect(try Self.samples(processor.process(silent, effects: .init(preset: .bright, amount: 1)))[0].allSatisfy { $0 == 0 })
        _ = try processor.process(sample, effects: .init(preset: .bright, amount: 1))
        let stereoSilence = try Self.sample([[Float](repeating: 0, count: 1_024), [Float](repeating: 0, count: 1_024)], rate: 44_100)
        #expect(try Self.samples(processor.process(stereoSilence, effects: .init(preset: .bright, amount: 1))).allSatisfy { $0.allSatisfy { $0 == 0 } })
        _ = try processor.process(sample, effects: .init(preset: .bright, amount: 1))
        _ = try processor.process(sample, effects: .init())
        #expect(try Self.samples(processor.process(silent, effects: .init(preset: .bright, amount: 1)))[0].allSatisfy { $0 == 0 })
    }

    @Test func loudSignalsRemainFiniteAndBelowFullScale() throws {
        let sample = try Self.sample([Self.tone(220, frames: 24_000, amplitude: 1.5)])
        let output = try Self.samples(RecordingVoiceProcessor().process(sample, effects: .init(preset: .broadcast, amount: 1)))[0]
        #expect(output.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect(output.allSatisfy { abs($0) < 1 }, "Soft limiting must avoid hard-clipped plateaus at full strength")
        #expect(Self.rms(output) < 0.6, "Broadcast dynamics must compress loud signals before limiting")
    }

    @Test func partialStrengthAlsoLimitsOversizedPCM() throws {
        let source = try Self.sample([[Float](repeating: 4, count: 512)])
        let result = try Self.samples(RecordingVoiceProcessor().process(source, effects: .init(preset: .broadcast, amount: 0.25)))[0]
        #expect(result.allSatisfy { $0.isFinite && abs($0) <= 1 })
    }

    @Test(arguments: [AVAudioCommonFormat.pcmFormatInt16, .pcmFormatInt32])
    func integerFullScaleSurvivesConversionWithoutOverflow(_ format: AVAudioCommonFormat) throws {
        let values = (0..<64).map { $0 % 2 == 0 ? Float(0.9) : Float(-1) }
        let source = try Self.sample([values], commonFormat: format)
        let output = try Self.samples(RecordingVoiceProcessor().process(source, effects: .init(preset: .broadcast, amount: 1)))[0]
        #expect(output.allSatisfy { $0.isFinite && abs($0) <= 1 })
    }

    @Test(arguments: [AVAudioCommonFormat.pcmFormatInt16, .pcmFormatInt32])
    func positiveIntegerFullScaleSaturatesAtTheRepresentableMaximum(_ format: AVAudioCommonFormat) throws {
        func check<T: FixedWidthInteger>(_ maximum: T) throws {
            let source = try Self.sample([[0]], commonFormat: format, interleaved: true, time: 12.5)
            let block = try #require(source.dataBuffer)
            var maximum = maximum
            try #require(withUnsafeBytes(of: &maximum) {
                CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                    dataLength: $0.count)
            } == noErr)
            let processor = RecordingVoiceProcessor()
            let effects = RecordingVoiceEffects(preset: .broadcast, amount: 1)
            _ = try processor.process(Self.sample([[Float](repeating: -1, count: 24_000)], commonFormat: format,
                interleaved: true), effects: effects)
            let output = try processor.process(source, effects: effects)
            var actual = T.zero
            try #require(withUnsafeMutableBytes(of: &actual) {
                CMBlockBufferCopyDataBytes(try #require(output.dataBuffer), atOffset: 0, dataLength: $0.count,
                    destination: $0.baseAddress!)
            } == noErr)
            #expect(actual == maximum, "Positive full-scale PCM must saturate instead of overflowing after rounding")
            try #require(withUnsafeMutableBytes(of: &actual) {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
            } == noErr)
            #expect(actual == maximum, "Saturation must leave the source PCM untouched")
        }
        if format == .pcmFormatInt16 { try check(Int16.max) }
        else { try check(Int32.max) }
    }

    @Test func extremeFiniteFloat64SamplesDoNotPoisonFollowingPCM() throws {
        let extreme = try Self.sample([[Float](repeating: 0, count: 32)], commonFormat: .pcmFormatFloat64)
        let format = AVAudioFormat(cmAudioFormatDescription: try #require(extreme.formatDescription))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32))
        buffer.frameLength = 32
        let data = try #require(buffer.mutableAudioBufferList.pointee.mBuffers.mData).assumingMemoryBound(to: Double.self)
        for index in 0..<32 { data[index] = index % 2 == 0 ? Double.greatestFiniteMagnitude : -Double.greatestFiniteMagnitude }
        var replacement: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 48_000),
            presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        try #require(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
            formatDescription: extreme.formatDescription, sampleCount: 32, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &replacement) == noErr)
        let sample = try #require(replacement)
        try #require(CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList) == noErr)
        let processor = RecordingVoiceProcessor()
        let effects = RecordingVoiceEffects(preset: .broadcast, amount: 1)
        #expect(try Self.samples(processor.process(sample, effects: effects))[0].allSatisfy { $0.isFinite && abs($0) <= 1 })
        let silent = try Self.sample([[Float](repeating: 0, count: 512)], commonFormat: .pcmFormatFloat64)
        #expect(try Self.samples(processor.process(silent, effects: effects))[0].allSatisfy { $0.isFinite && abs($0) <= 1 })
        let speech = try Self.sample([Self.tone(440, frames: 24_000)], commonFormat: .pcmFormatFloat64)
        let recovered = try Self.samples(processor.process(speech, effects: effects))[0]
        #expect((0.08...0.3).contains(Self.rms(recovered)),
            "Oversized source samples must not leave the next speech packet permanently compressed or clipped")
    }

    @Test func missingPCMStorageFailsWithoutPublishingAnOutput() throws {
        let source = try Self.sample([Self.tone(440, frames: 32)])
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 48_000),
            presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var size = 4
        var missing: CMSampleBuffer?
        try #require(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
            formatDescription: source.formatDescription, sampleCount: 32, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &missing) == noErr)
        let packet = try #require(missing)
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) {
            try RecordingVoiceProcessor().process(packet, effects: .init(preset: .natural, amount: 1))
        }
        #expect(packet.dataBuffer == nil)
    }

    @Test func formatlessPacketIsRejectedBeforePCMAllocation() throws {
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 48_000),
            presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var size = 4
        var missing: CMSampleBuffer?
        try #require(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
            formatDescription: nil, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &missing) == noErr)
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) {
            try RecordingVoiceProcessor().process(try #require(missing), effects: .init(preset: .natural, amount: 1))
        }
    }

    @Test func compressedPacketIsRejectedBeforePCMAllocation() throws {
        var description = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: 1_024, mBytesPerFrame: 0,
            mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        var format: CMAudioFormatDescription?
        try #require(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: .init(value: 1_024, timescale: 48_000),
            presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var size = 4
        var result: CMSampleBuffer?
        try #require(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
            formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &result) == noErr)
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) {
            try RecordingVoiceProcessor().process(try #require(result), effects: .init(preset: .natural, amount: 1))
        }
    }

    @Test func oversizedPacketIsRejectedBeforePCMAllocation() throws {
        let source = try Self.sample([Self.tone(440, frames: 32)])
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 48_000),
            presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var size = 4
        var result: CMSampleBuffer?
        try #require(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
            formatDescription: source.formatDescription, sampleCount: Int(Int32.max) + 1, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &result) == noErr)
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) {
            try RecordingVoiceProcessor().process(try #require(result), effects: .init(preset: .natural, amount: 1))
        }
    }

    @Test(arguments: [Double.nan, .infinity, -0.1, 1.1])
    func invalidStrengthFailsWithoutChangingSource(_ amount: Double) throws {
        let sample = try Self.sample([Self.tone(440, frames: 512)])
        let original = try Self.samples(sample)
        #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
            try RecordingVoiceProcessor().process(sample, effects: .init(preset: .natural, amount: amount))
        }
        #expect(try Self.samples(sample) == original)
    }

    @Test(arguments: [Float.nan, .infinity, -.infinity])
    func nonfinitePCMIsRejectedAndTheNextPacketHasCleanState(_ value: Float) throws {
        let broken = try Self.sample([[0.2, value]])
        let silent = try Self.sample([[Float](repeating: 0, count: 512)])
        let effects = RecordingVoiceEffects(preset: .warm, amount: 1)
        let processor = RecordingVoiceProcessor()
        _ = try processor.process(Self.sample([Self.tone(440, frames: 512)]), effects: effects)
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try processor.process(broken, effects: effects) }
        #expect(try Self.samples(processor.process(silent, effects: effects))[0].allSatisfy { $0 == 0 })
        #expect(try Self.samples(broken)[0][1].isFinite == false)
    }

    private static func tone(_ frequency: Double, frames: Int, amplitude: Double = 0.1) -> [Float] {
        (0..<frames).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / 48_000)) }
    }

    private static func rms(_ samples: [Float]) -> Double {
        let steady = samples.dropFirst(min(2_048, samples.count / 4))
        return sqrt(steady.reduce(0) { $0 + Double($1) * Double($1) } / Double(steady.count))
    }

    private static func amplitude(_ samples: [Float], frequency: Double) -> Double {
        let start = 4_000
        let end = 24_000
        let sine = (start..<end).reduce(0.0) { $0 + Double(samples[$1]) * sin(2 * .pi * frequency * Double($1) / 48_000) }
        let cosine = (start..<end).reduce(0.0) { $0 + Double(samples[$1]) * cos(2 * .pi * frequency * Double($1) / 48_000) }
        return 2 * hypot(sine, cosine) / Double(end - start)
    }

    private static func sample(_ channels: [[Float]], commonFormat: AVAudioCommonFormat = .pcmFormatFloat32,
                               interleaved: Bool = false, rate: Double = 48_000, time: Double = 12) throws -> CMSampleBuffer {
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels.count)))
        let format = AVAudioFormat(commonFormat: commonFormat, sampleRate: rate, interleaved: interleaved, channelLayout: layout)
        let count = try #require(channels.first?.count)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
        buffer.frameLength = buffer.frameCapacity
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for channel in channels.indices {
            let data = try #require(list[interleaved ? 0 : channel].mData)
            for frame in 0..<count {
                let index = frame * buffer.stride + (interleaved ? channel : 0)
                let value = channels[channel][frame]
                switch commonFormat {
                case .pcmFormatFloat32: data.assumingMemoryBound(to: Float.self)[index] = value
                case .pcmFormatFloat64: data.assumingMemoryBound(to: Double.self)[index] = Double(value)
                case .pcmFormatInt16: data.assumingMemoryBound(to: Int16.self)[index] = Int16((value * 32_768).rounded())
                case .pcmFormatInt32: data.assumingMemoryBound(to: Int32.self)[index] = Int32((Double(value) * 2_147_483_648).rounded())
                default: Issue.record("Unsupported test PCM format")
                }
            }
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(rate)),
            presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 48_000), decodeTimeStamp: .invalid)
        var size = Int(format.streamDescription.pointee.mBytesPerFrame)
        var result: CMSampleBuffer?
        try #require(withUnsafePointer(to: &size) { pointer in
            CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil, formatDescription: format.formatDescription,
                sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: interleaved ? 1 : 0, sampleSizeArray: interleaved ? pointer : nil, sampleBufferOut: &result)
        } == noErr)
        let sample = try #require(result)
        try #require(CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList) == noErr)
        return sample
    }

    private static func samples(_ sample: CMSampleBuffer) throws -> [[Float]] {
        let format = AVAudioFormat(cmAudioFormatDescription: try #require(sample.formatDescription))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sample.numSamples)))
        buffer.frameLength = buffer.frameCapacity
        try #require(CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(sample.numSamples),
            into: buffer.mutableAudioBufferList) == noErr)
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        return try (0..<Int(format.channelCount)).map { channel in
            let data = try #require(list[format.isInterleaved ? 0 : channel].mData)
            return (0..<sample.numSamples).map { frame in
                let index = frame * buffer.stride + (format.isInterleaved ? channel : 0)
                switch format.commonFormat {
                case .pcmFormatFloat32: return data.assumingMemoryBound(to: Float.self)[index]
                case .pcmFormatFloat64: return Float(data.assumingMemoryBound(to: Double.self)[index])
                case .pcmFormatInt16: return Float(data.assumingMemoryBound(to: Int16.self)[index]) / 32_768
                case .pcmFormatInt32: return Float(Double(data.assumingMemoryBound(to: Int32.self)[index]) / 2_147_483_648)
                default: return .nan
                }
            }
        }
    }
}
