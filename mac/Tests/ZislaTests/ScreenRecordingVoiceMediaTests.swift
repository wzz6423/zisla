import AVFoundation
import CoreImage
import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingVoiceMediaTests {
    @Test func processingWritesActualPCMAndReusesOnlyMatchingEffectsWithoutTouchingSource() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let sourceURL = try fixture.createTone()
        let original = try Data(contentsOf: sourceURL)
        let source = AVURLAsset(url: sourceURL)
        var media: RecordingVoiceMedia? = RecordingVoiceMedia()
        #expect(try await media!.asset(from: source, effects: .init()) === source)
        let warm = try await media!.asset(from: source, effects: .init(preset: .warm, amount: 0.8))
        let warmSamples = try await samples(warm)
        let cached = try await media!.asset(from: source, effects: .init(preset: .warm, amount: 0.8))
        #expect(cached.url == warm.url)
        let lighter = try await media!.asset(from: source, effects: .init(preset: .warm, amount: 0.4))
        let lighterSamples = try await samples(lighter)
        #expect(lighter.url != warm.url && lighterSamples != warmSamples)
        let secondURL = try fixture.createTone("second.wav")
        let second = try await media!.asset(from: AVURLAsset(url: secondURL), effects: .init(preset: .warm, amount: 0.8))
        #expect(second.url != warm.url, "A different source must own a different processed asset")
        let bright = try await media!.asset(from: source, effects: .init(preset: .bright, amount: 0.8))
        let brightSamples = try await samples(bright)
        let sourceSamples = try await samples(source)
        #expect(warm.url != bright.url && warmSamples != brightSamples && warmSamples != sourceSamples)
        #expect(warmSamples.count == sourceSamples.count && brightSamples.count == sourceSamples.count)
        #expect(abs(try await warm.load(.duration).seconds - 2) < 0.0001)
        #expect(try Data(contentsOf: sourceURL) == original)
        #expect(try fixture.files() == ["second.wav", "tone.wav"])
        let folder = warm.url.deletingLastPathComponent()
        #expect(try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        media = nil
        #expect(!FileManager.default.fileExists(atPath: folder.path), "Processed PCM must be released with its media owner")
    }

    @Test func cancelledInvalidAndMissingAudioPreparationLeavesSourceFilesUntouched() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let url = try fixture.createTone()
        let source = AVURLAsset(url: url)
        let before = try Data(contentsOf: url)
        let media = RecordingVoiceMedia()
        await #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
            _ = try await media.asset(from: source, effects: .init(preset: .natural, amount: .nan))
        }
        let task = Task { try await media.asset(from: source, effects: .init(preset: .warm, amount: 1)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        _ = try await fixture.createVideo()
        await #expect(throws: ScreenRecordingExportError.unavailableMedia) {
            _ = try await media.asset(from: AVURLAsset(url: fixture.directory.appendingPathComponent("screen.mp4")),
                effects: .init(preset: .natural, amount: 1))
        }
        #expect(try Data(contentsOf: url) == before)
        #expect(try fixture.files() == ["screen.mp4", "tone.wav"])
        let retry = try await media.asset(from: source, effects: .init(preset: .warm, amount: 1))
        #expect(try await samples(retry).count == 96_000)
    }

    @Test(arguments: [4, 6])
    func multichannelPCMProcessingPreservesLayoutTimingAndSource(_ channelCount: Int) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let sourceURL = fixture.directory.appendingPathComponent("multichannel.mov")
        try await createMultichannelMovie(at: sourceURL, channels: channelCount)
        let originalFile = try Data(contentsOf: sourceURL)
        let source = AVURLAsset(url: sourceURL)
        let before = try await channelSamples(source)
        let media = RecordingVoiceMedia()
        let processed = try await media.asset(from: source, effects: .init(preset: .broadcast, amount: 0.8))
        let after = try await channelSamples(processed)
        #expect(Int(before.format.channelCount) == channelCount && Int(after.format.channelCount) == channelCount)
        #expect(after.format.channelLayout == before.format.channelLayout)
        #expect(before.start == CMTime(value: 12_000, timescale: 48_000) && after.start == before.start)
        #expect(before.end == CMTime(value: 36_000, timescale: 48_000) && after.end == before.end)
        let sourceDuration = try await source.load(.duration)
        #expect(try await processed.load(.duration) == sourceDuration)
        for channel in 0..<channelCount {
            #expect(before.channels[channel].count == 24_000 && after.channels[channel].count == 24_000)
            #expect(after.channels[channel].allSatisfy { $0.isFinite && abs($0) <= 1 })
            if channel == channelCount - 1 {
                #expect(after.channels[channel].allSatisfy { $0 == 0 }, "Silent source channels must remain silent")
            } else {
                #expect(after.channels[channel] != before.channels[channel], "Every audible source channel must receive the effect")
                #expect(after.channels[channel].contains { abs($0) > 0.01 })
            }
        }
        #expect(try Data(contentsOf: sourceURL) == originalFile)
        #expect(try fixture.files() == ["multichannel.mov"])
    }

    @Test(arguments: [false, true])
    func playbackAndVideoAudioOnlyExportsApplyMicrophoneEffectsFromTheRawSource(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        _ = try fixture.createTone("mic-raw.wav")
        let recordedURL = try fixture.createTone("mic-recorded.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let recorded = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
        recorded.frameLength = 96_000
        memset(try #require(recorded.floatChannelData?[0]), 0, 96_000 * MemoryLayout<Float>.size)
        try AVAudioFile(forWriting: recordedURL, settings: format.settings).write(from: recorded)
        var project = fixture.project()
        project.microphoneFile = "mic-recorded.wav"
        project.rawMicrophoneFile = "mic-raw.wav"
        project.edits.voiceEffects = .init(preset: .broadcast, amount: 0.7)
        project.edits.segments = [.init(start: 0.25, end: 1.25, speed: 2)]
        if multitrack { project.timeline = .migrating(project) }
        let exporter = ScreenRecordingExporter()
        let playback = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let preview = try await samples(playback.asset, mix: playback.audioMix)
        let wav = fixture.root.appendingPathComponent("voice.wav")
        try await exporter.export(project: project, directory: fixture.directory, to: wav,
            configuration: .init(format: .wav, resolution: .source, frameRate: 8))
        let audio = try await samples(AVURLAsset(url: wav))
        let mp4 = fixture.root.appendingPathComponent("voice.mp4")
        try await exporter.export(project: project, directory: fixture.directory, to: mp4,
            configuration: .init(format: .mp4, resolution: .source, frameRate: 8))
        let video = try await samples(AVURLAsset(url: mp4))
        #expect(abs(try await playback.asset.load(.duration).seconds - 0.5) < 0.001)
        #expect(preview.count == 24_000 && audio.count == 24_000, "Energy comparisons must cover the same edited half-second")
        #expect(!preview.isEmpty && !audio.isEmpty && !video.isEmpty)
        #expect(energy(preview) > 0.03, "Playback must use the audible raw microphone, not the silent recorded copy")
        let previewEnergy = energy(preview)
        let audioEnergy = energy(audio)
        let videoEnergy = energy(video)
        #expect(abs(previewEnergy - audioEnergy) < 0.002,
            "Preview energy \(previewEnergy) and WAV energy \(audioEnergy) must match over \(preview.count)/\(audio.count) frames")
        #expect(abs(videoEnergy - audioEnergy) < 0.01,
            "MP4 energy \(videoEnergy) and WAV energy \(audioEnergy) must match over \(video.count)/\(audio.count) frames")
        project.edits.voiceEffects = .init()
        let plain = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let plainSamples = try await samples(plain.asset, mix: plain.audioMix)
        #expect(abs(energy(plainSamples) - energy(preview)) > 0.003, "Disabling voice enhancement must restore original audio")
        #expect(try fixture.files() == ["mic-raw.wav", "mic-recorded.wav", "screen.mp4"])
    }

    @Test func perClipEffectsSurviveAudioDetachmentAndDoNotAffectOtherClips() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        _ = try fixture.createTone("mic-raw.wav")
        var project = fixture.project()
        project.microphoneFile = "mic-raw.wav"
        project.timeline = .migrating(project)
        let id = try #require(project.timeline?.clips.first?.id)
        let effects = RecordingVoiceEffects(preset: .bright, amount: 0.6)
        project.timeline?.clips[0].voiceEffects = effects
        let before = try await ScreenRecordingExporter().playbackItem(project: project, directory: fixture.directory)
        let expected = try await samples(before.asset, mix: before.audioMix)
        let detached = try #require(try await ScreenRecordingAudioDetachment.prepare(project: project, directory: fixture.directory, clipID: id))
        let audio = try #require(detached.timeline?.clips.first { $0.content.trackKind == .audio })
        #expect(audio.voiceEffects == effects)
        let after = try await ScreenRecordingExporter().playbackItem(project: detached, directory: fixture.directory)
        #expect(try await samples(after.asset, mix: after.audioMix) == expected)
    }

    private func energy(_ samples: [Float]) -> Double {
        samples.reduce(0) { $0 + abs(Double($1)) } / Double(max(1, samples.count))
    }

    private func createMultichannelMovie(at url: URL, channels: Int) async throws {
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)))
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, interleaved: true, channelLayout: layout)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format.formatDescription)
        writer.add(input)
        try #require(writer.startWriting())
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)
        for start in stride(from: 0, to: 24_000, by: 2_400) {
            while !input.isReadyForMoreMediaData { try Task.checkCancellation(); await Task.yield() }
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_400))
            buffer.frameLength = 2_400
            let values = try #require(buffer.mutableAudioBufferList.pointee.mBuffers.mData).assumingMemoryBound(to: Float.self)
            for frame in 0..<2_400 {
                for channel in 0..<channels {
                    values[frame * channels + channel] = channel == channels - 1 ? 0
                        : Float(0.1 * sin(2 * .pi * Double(220 + channel * 330) * Double(start + frame) / 48_000))
                }
            }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                presentationTimeStamp: CMTime(value: Int64(12_000 + start), timescale: 48_000), decodeTimeStamp: .invalid)
            var size = Int(format.streamDescription.pointee.mBytesPerFrame)
            var sample: CMSampleBuffer?
            try #require(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
                formatDescription: format.formatDescription, sampleCount: 2_400, sampleTimingEntryCount: 1,
                sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr)
            let packet = try #require(sample)
            try #require(CMSampleBufferSetDataBufferFromAudioBufferList(packet, blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList) == noErr)
            try #require(input.append(packet))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 36_000, timescale: 48_000))
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }

    private func channelSamples(_ asset: AVAsset) async throws
        -> (channels: [[Float]], format: AVAudioFormat, start: CMTime, end: CMTime) {
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let segments = try await track.load(.segments).filter { !$0.isEmpty }
        let rangeStart = try #require(segments.first?.timeMapping.target.start)
        let rangeEnd = try #require(segments.last?.timeMapping.target.end)
        reader.timeRange = CMTimeRange(start: rangeStart, end: rangeEnd)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        try #require(reader.startReading())
        defer { reader.cancelReading(); withExtendedLifetime(asset) {} }
        let first = try #require(output.copyNextSampleBuffer())
        let format = AVAudioFormat(cmAudioFormatDescription: try #require(first.formatDescription))
        var channels = [[Float]](repeating: [], count: Int(format.channelCount))
        var end = first.presentationTimeStamp
        var sample: CMSampleBuffer? = first
        while let current = sample {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(current.numSamples)))
            buffer.frameLength = buffer.frameCapacity
            try #require(CMSampleBufferCopyPCMDataIntoAudioBufferList(current, at: 0, frameCount: Int32(current.numSamples),
                into: buffer.mutableAudioBufferList) == noErr)
            let values = try #require(buffer.mutableAudioBufferList.pointee.mBuffers.mData).assumingMemoryBound(to: Float.self)
            for frame in 0..<current.numSamples {
                for channel in channels.indices { channels[channel].append(values[frame * channels.count + channel]) }
            }
            end = current.presentationTimeStamp + current.duration
            sample = output.copyNextSampleBuffer()
        }
        try #require(reader.status == .completed)
        return (channels, format, first.presentationTimeStamp, end)
    }

    private func samples(_ asset: AVAsset, mix: AVAudioMix? = nil) async throws -> [Float] {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = mix
        output.audioTimePitchAlgorithm = .spectral
        let count = Int((try await asset.load(.duration).seconds * 48_000).rounded())
        reader.add(output)
        try #require(reader.startReading(), "The authored voice track must decode")
        defer { reader.cancelReading(); withExtendedLifetime(asset) {} }
        var result: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            let data = try #require(sample.dataBuffer)
            var values = [Float](repeating: 0, count: data.dataLength / MemoryLayout<Float>.size)
            let status = values.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: data.dataLength, destination: bytes.baseAddress!)
            }
            try #require(status == noErr)
            // Preserve decoder timestamps rather than shifting spectral startup delay into the audio.
            let start = Int((sample.presentationTimeStamp.seconds * 48_000).rounded())
            if start > result.count { result.append(contentsOf: repeatElement(0, count: min(count, start) - result.count)) }
            let offset = max(0, result.count - start)
            if offset < sample.numSamples {
                result.append(contentsOf: stride(from: offset * 2, to: values.count, by: 2)
                    .prefix(max(0, count - result.count)).map { values[$0] })
            }
        }
        #expect(reader.status == .completed && reader.error == nil)
        result.append(contentsOf: repeatElement(0, count: count - result.count))
        return result
    }
}
