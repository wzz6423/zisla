import AVFoundation
import CoreMedia
import ZislaCore

final class RecordingVoiceProcessor {
    private struct Channel {
        var previousInput = 0.0
        var highPass = 0.0
        var low = 0.0
        var presence = 0.0
        var envelope = 0.0
    }

    private var channels: [Channel] = []
    private var format: AVAudioFormat?
    private var preset: RecordingVoicePreset?

    func process(_ sample: CMSampleBuffer, effects: RecordingVoiceEffects) throws -> CMSampleBuffer {
        guard effects.isValid else { throw ScreenRecordingExportError.invalidConfiguration }
        guard effects.isEnabled else {
            channels.removeAll(keepingCapacity: true)
            format = nil
            preset = nil
            return sample
        }
        guard sample.numSamples > 0 else { return sample }
        guard let description = sample.formatDescription,
              sample.numSamples <= Int(Int32.max) else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: description)
        guard [.pcmFormatFloat32, .pcmFormatFloat64, .pcmFormatInt16, .pcmFormatInt32].contains(sourceFormat.commonFormat),
              let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(sample.numSamples)) else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        buffer.frameLength = buffer.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(sample.numSamples),
                                                          into: buffer.mutableAudioBufferList) == noErr else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        if format?.isEqual(sourceFormat) != true || preset != effects.preset {
            channels = Array(repeating: Channel(), count: Int(sourceFormat.channelCount))
            format = sourceFormat
            preset = effects.preset
        }

        let rate = sourceFormat.sampleRate
        let highPass = exp(-2 * .pi * 75 / rate)
        let lowPass = 1 - exp(-2 * .pi * 250 / rate)
        let presence = 1 - exp(-2 * .pi * 3_000 / rate)
        let attack = 1 - exp(-1 / (rate * 0.005))
        let release = 1 - exp(-1 / (rate * 0.08))
        let lowGain: Double
        let highGain: Double
        let threshold: Double
        let ratio: Double
        let makeup: Double
        switch effects.preset {
        case .original, .natural: lowGain = 0; highGain = 0.1; threshold = 0.4; ratio = 2; makeup = 1.08
        case .warm: lowGain = 0.55; highGain = -0.2; threshold = 0.35; ratio = 2.5; makeup = 1.1
        case .bright: lowGain = -0.12; highGain = 0.55; threshold = 0.35; ratio = 2.5; makeup = 1.07
        case .broadcast: lowGain = 0.2; highGain = 0.3; threshold = 0.2; ratio = 3.5; makeup = 1.55
        }

        let stride = buffer.stride
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for channelIndex in channels.indices {
            var state = channels[channelIndex]
            let data = buffers[sourceFormat.isInterleaved ? 0 : channelIndex].mData!
            for frame in 0..<sample.numSamples {
                let index = frame * stride + (sourceFormat.isInterleaved ? channelIndex : 0)
                let decoded: Double
                switch sourceFormat.commonFormat {
                case .pcmFormatFloat32: decoded = Double(data.assumingMemoryBound(to: Float.self)[index])
                case .pcmFormatFloat64: decoded = data.assumingMemoryBound(to: Double.self)[index]
                case .pcmFormatInt16: decoded = Double(data.assumingMemoryBound(to: Int16.self)[index]) / 32_768
                case .pcmFormatInt32: decoded = Double(data.assumingMemoryBound(to: Int32.self)[index]) / 2_147_483_648
                default: preconditionFailure("Unsupported formats return before PCM processing")
                }
                guard decoded.isFinite else {
                    channels.removeAll(keepingCapacity: true)
                    format = nil
                    preset = nil
                    throw ScreenRecordingCaptureError.writerUnavailable
                }
                let input = min(8, max(-8, decoded))
                state.highPass = highPass * (state.highPass + input - state.previousInput)
                state.previousInput = input
                state.low += lowPass * (state.highPass - state.low)
                state.presence += presence * (state.highPass - state.presence)
                var wet = state.highPass + lowGain * state.low + highGain * (state.highPass - state.presence)
                let magnitude = abs(wet)
                state.envelope += (magnitude > state.envelope ? attack : release) * (magnitude - state.envelope)
                let gate = min(1, state.envelope / 0.004)
                let compression = state.envelope > threshold
                    ? pow(threshold / state.envelope, 1 - 1 / ratio) : 1
                wet *= gate * compression * makeup
                if abs(wet) > 0.8 {
                    wet = copysign(0.8 + 0.2 * tanh((abs(wet) - 0.8) / 0.2), wet)
                }
                let output = min(1, max(-1, input + (wet - input) * effects.amount))
                switch sourceFormat.commonFormat {
                case .pcmFormatFloat32: data.assumingMemoryBound(to: Float.self)[index] = Float(output)
                case .pcmFormatFloat64: data.assumingMemoryBound(to: Double.self)[index] = output
                case .pcmFormatInt16: data.assumingMemoryBound(to: Int16.self)[index] = Int16(clamping: Int64((output * 32_768).rounded()))
                case .pcmFormatInt32: data.assumingMemoryBound(to: Int32.self)[index] = Int32(clamping: Int64((output * 2_147_483_648).rounded()))
                default: preconditionFailure("Unsupported formats return before PCM processing")
                }
            }
            channels[channelIndex] = state
        }

        var timingCount = 0
        var sizeCount = 0
        let sizeStatus = CMSampleBufferGetSampleSizeArray(sample, entryCount: 0, arrayToFill: nil,
                                                        entriesNeededOut: &sizeCount)
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil,
                                                    entriesNeededOut: &timingCount) == noErr,
              sizeStatus == noErr || sizeStatus == kCMSampleBufferError_BufferHasNoSampleSizes else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        var timings = Array(repeating: CMSampleTimingInfo(), count: timingCount)
        var sizes = Array(repeating: 0, count: sizeCount)
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: timings.count, arrayToFill: &timings,
                                                    entriesNeededOut: nil) == noErr else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        if !sizes.isEmpty {
            guard CMSampleBufferGetSampleSizeArray(sample, entryCount: sizes.count, arrayToFill: &sizes,
                                                  entriesNeededOut: nil) == noErr else {
                throw ScreenRecordingCaptureError.writerUnavailable
            }
        }
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil, formatDescription: description,
                                        sampleCount: sample.numSamples, sampleTimingEntryCount: timings.count,
                                        sampleTimingArray: &timings, sampleSizeEntryCount: sizes.count,
                                        sampleSizeArray: &sizes, sampleBufferOut: &result) == noErr,
              let result,
              CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: kCFAllocatorDefault,
                                                            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
                                                            bufferList: buffer.audioBufferList) == noErr else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        CMPropagateAttachments(sample, destination: result)
        CMSampleBufferSetOutputPresentationTimeStamp(result, newValue: sample.outputPresentationTimeStamp)
        return result
    }
}
