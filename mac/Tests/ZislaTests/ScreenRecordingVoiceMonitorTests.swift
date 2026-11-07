import AVFoundation
import CoreMedia
import Testing
@testable import Zisla

struct ScreenRecordingVoiceMonitorTests {
    @Test func microphoneMonitoringDefaultsOffAndStopsUntilExplicitlyReenabled() throws {
        let output = Output()
        let monitor = RecordingVoiceMonitor(makeOutput: { output })
        let sample = try Self.sample()
        try monitor.append(sample)
        #expect(output.starts == 0 && output.buffers.isEmpty)
        monitor.isEnabled = true
        try monitor.append(sample)
        #expect(output.starts == 1 && output.buffers.count == 1)
        monitor.stop()
        #expect(!monitor.isEnabled && output.stops == 1)
        try monitor.append(sample)
        #expect(output.buffers.count == 1)
        monitor.isEnabled = true
        try monitor.append(sample)
        #expect(output.starts == 2 && output.buffers.count == 2)
    }

    @Test func onlyFourPacketsCanWaitForPlaybackAndOneCompletionAllowsOneMore() throws {
        let output = Output()
        let monitor = RecordingVoiceMonitor(makeOutput: { output })
        monitor.isEnabled = true
        let sample = try Self.sample()
        for _ in 0..<100 { try monitor.append(sample) }
        #expect(output.buffers.count == 4, "An unavailable speaker must not accumulate microphone packets")
        output.completions[0]()
        output.completions[0]()
        for _ in 0..<10 { try monitor.append(sample) }
        #expect(output.buffers.count == 5, "Duplicate completions must not create extra backlog capacity")
    }

    @Test func changingPCMFormatReleasesOutputAndOldCompletionsCannotChangeTheNewBacklog() throws {
        let first = Output()
        let second = Output()
        var outputs = [first, second]
        let monitor = RecordingVoiceMonitor(makeOutput: { outputs.removeFirst() })
        monitor.isEnabled = true
        for _ in 0..<4 { try monitor.append(Self.sample()) }
        let stereo = try Self.sample(channelCount: 2, rate: 44_100)
        try monitor.append(stereo)
        #expect(first.starts == 1 && first.stops == 1 && second.starts == 1)
        #expect(second.buffers[0].format.sampleRate == 44_100 && second.buffers[0].format.channelCount == 2)
        for completion in first.completions { completion() }
        for _ in 0..<10 { try monitor.append(stereo) }
        #expect(second.buffers.count == 4)
        monitor.stop()
        #expect(second.stops == 1)
    }

    @Test(arguments: [true, false])
    func monitoringCopiesPCMIntoStandardFloatWithoutChangingTheSource(_ interleaved: Bool) throws {
        let output = Output()
        let monitor = RecordingVoiceMonitor(makeOutput: { output })
        monitor.isEnabled = true
        let source = try Self.sample(channelCount: 2, interleaved: interleaved, integer: true)
        let bytes = try Self.bytes(source)
        try monitor.append(source)
        let result = try #require(output.buffers.first)
        #expect(result.frameLength == source.numSamples)
        #expect(result.format.commonFormat == .pcmFormatFloat32 && !result.format.isInterleaved)
        #expect(result.format.channelCount == 2 && result.format.sampleRate == 48_000)
        let data = try #require(result.floatChannelData)
        #expect(abs(data[0][0] - 0.25) < 0.000_1 && abs(data[1][0] + 0.5) < 0.000_1)
        #expect(try Self.bytes(source) == bytes)
    }

    @Test func outputStartupFailureReleasesTheSinkAndCanRetryWithANewOutput() throws {
        let failed = Output()
        failed.startError = MonitorError.unavailable
        let working = Output()
        var outputs = [failed, working]
        let monitor = RecordingVoiceMonitor(makeOutput: { outputs.removeFirst() })
        monitor.isEnabled = true
        #expect(throws: MonitorError.unavailable) { try monitor.append(Self.sample()) }
        #expect(failed.stops == 1 && failed.buffers.isEmpty)
        try monitor.append(Self.sample())
        #expect(working.starts == 1 && working.buffers.count == 1)
    }

    @Test func outputAppendFailureDoesNotConsumeTheBacklogCapacity() throws {
        let output = Output()
        output.appendError = MonitorError.unavailable
        let monitor = RecordingVoiceMonitor(makeOutput: { output })
        monitor.isEnabled = true
        let sample = try Self.sample()
        for _ in 0..<5 { #expect(throws: MonitorError.unavailable) { try monitor.append(sample) } }
        output.appendError = nil
        for _ in 0..<10 { try monitor.append(sample) }
        #expect(output.buffers.count == 4)
    }

    @Test func shutdownReleasesOutputWithoutWaitingForPlaybackCompletions() throws {
        let output = Output()
        var monitor: RecordingVoiceMonitor? = RecordingVoiceMonitor(makeOutput: { output })
        monitor!.isEnabled = true
        try monitor!.append(Self.sample())
        monitor = nil
        #expect(output.stops == 1)
        output.completions[0]()
    }

    @Test func malformedPCMThrowsWithoutConsumingTheBacklog() throws {
        let output = Output()
        let monitor = RecordingVoiceMonitor(makeOutput: { output })
        monitor.isEnabled = true
        let source = try Self.sample()
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 48_000),
            presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var size = 4
        var missing: CMSampleBuffer?
        try #require(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
            formatDescription: source.formatDescription, sampleCount: 64, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &missing) == noErr)
        for _ in 0..<10 {
            #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try monitor.append(try #require(missing)) }
        }
        for _ in 0..<10 { try monitor.append(source) }
        #expect(output.buffers.count == 4)
    }

    @Test func emptyPacketsDoNotStartOutputOrConsumeBacklog() throws {
        let output = Output()
        let monitor = RecordingVoiceMonitor(makeOutput: { output })
        monitor.isEnabled = true
        let source = try Self.sample()
        var empty: CMSampleBuffer?
        try #require(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
            formatDescription: source.formatDescription, sampleCount: 0, sampleTimingEntryCount: 0,
            sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &empty) == noErr)
        try monitor.append(try #require(empty))
        #expect(output.starts == 0 && output.buffers.isEmpty)
        for _ in 0..<10 { try monitor.append(source) }
        #expect(output.buffers.count == 4)
    }

    @Test func stoppingResetsBacklogAndIgnoresPendingCompletionsAfterRestart() throws {
        let output = Output()
        let monitor = RecordingVoiceMonitor(makeOutput: { output })
        monitor.isEnabled = true
        for _ in 0..<4 { try monitor.append(Self.sample()) }
        let previous = output.completions
        monitor.stop()
        monitor.isEnabled = true
        try monitor.append(Self.sample())
        #expect(output.buffers.count == 5, "Restart must immediately accept audio even if old playback never completed")
        for completion in previous { completion() }
        for _ in 0..<10 { try monitor.append(Self.sample()) }
        #expect(output.buffers.count == 8)
    }

    private enum MonitorError: Error { case unavailable }

    private final class Output: RecordingVoiceMonitorOutput {
        var starts = 0
        var stops = 0
        var buffers: [AVAudioPCMBuffer] = []
        var completions: [@Sendable () -> Void] = []
        var startError: Error?
        var appendError: Error?

        func start(format: AVAudioFormat) throws {
            starts += 1
            if let startError { throw startError }
        }

        func append(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void) throws {
            if let appendError { throw appendError }
            buffers.append(buffer)
            completions.append(completion)
        }

        func stop() { stops += 1 }
    }

    private static func sample(channelCount: UInt32 = 1, interleaved: Bool = true, integer: Bool = false,
                               rate: Double = 48_000) throws -> CMSampleBuffer {
        let format = try #require(AVAudioFormat(commonFormat: integer ? .pcmFormatInt16 : .pcmFormatFloat32,
            sampleRate: rate, channels: channelCount, interleaved: interleaved))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        buffer.frameLength = 64
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for channel in 0..<Int(channelCount) {
            let data = try #require(list[interleaved ? 0 : channel].mData)
            for frame in 0..<64 {
                let index = frame * buffer.stride + (interleaved ? channel : 0)
                let value: Float = channel == 0 ? 0.25 : -0.5
                if integer { data.assumingMemoryBound(to: Int16.self)[index] = Int16(value * 32_768) }
                else { data.assumingMemoryBound(to: Float.self)[index] = value }
            }
        }
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: CMTimeScale(rate)),
            presentationTimeStamp: .init(seconds: 12, preferredTimescale: 48_000), decodeTimeStamp: .invalid)
        var size = Int(format.streamDescription.pointee.mBytesPerFrame)
        var result: CMSampleBuffer?
        try #require(withUnsafePointer(to: &size) { pointer in
            CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
                formatDescription: format.formatDescription, sampleCount: 64, sampleTimingEntryCount: 1,
                sampleTimingArray: &timing, sampleSizeEntryCount: interleaved ? 1 : 0,
                sampleSizeArray: interleaved ? pointer : nil, sampleBufferOut: &result)
        } == noErr)
        let sample = try #require(result)
        try #require(CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList) == noErr)
        return sample
    }

    private static func bytes(_ sample: CMSampleBuffer) throws -> Data {
        let block = try #require(sample.dataBuffer)
        var data = Data(count: CMBlockBufferGetDataLength(block))
        try #require(data.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        } == noErr)
        return data
    }
}
