import AVFoundation
import Foundation
import Testing
@testable import ZislaKit

@Suite(.serialized, .timeLimit(.minutes(3)), .enabled(if: ProcessInfo.processInfo.environment["ZISLA_RUN_AUDIO_TOOL_TESTS"] == "1"))
struct AudioProcessingIntegrationTests {
    @Test(arguments: AudioToolOperation.allCases)
    func everyOperationProducesReadableAudio(operation: AudioToolOperation) async throws {
        let fixture = try AudioIntegrationFixture()
        defer { fixture.clean() }
        let service = fixture.service
        var options = AudioProcessingOptions()
        options.format = .wav
        options.startTime = 0.5
        options.endTime = 1.5
        options.segmentDuration = 0.7
        options.generatedDuration = 0.25
        options.fadeInDuration = 0.2
        options.fadeOutDuration = 0.2
        options.speed = 2
        options.bassDB = 3
        options.midDB = -2
        options.trebleDB = 2
        options.metadata = ["title": "Audio fixture", "artist": "Zisla"]
        let inputs = operation.generatesAudio ? [] : operation.requiresMultipleInputs ? [fixture.first, fixture.second] : [fixture.first]
        if operation == .compress { options.format = .mp3 }
        let output = operation.exportsToDirectory(inputCount: inputs.count) ? fixture.root
            : fixture.root.appendingPathComponent("output.\(options.format.fileExtension)")
        let original = try Data(contentsOf: fixture.first)
        let outputs = try await service.process(.init(operation: operation, inputURLs: inputs, options: options), outputURL: output)

        #expect(!outputs.isEmpty)
        for url in outputs {
            let summary = try await service.inspect(url)
            #expect(summary.duration > 0)
            #expect(summary.sampleRate == options.sampleRate)
        }
        #expect(try Data(contentsOf: fixture.first) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).allSatisfy { !$0.hasPrefix(".zisla-audio-") })
        switch operation {
        case .trim:
            #expect(abs(try await service.inspect(outputs[0]).duration - 1) < 0.02)
        case .removeSegment:
            #expect(abs(try await service.inspect(outputs[0]).duration - 1.1) < 0.02)
        case .insertSilence:
            #expect(abs(try await service.inspect(outputs[0]).duration - 2.35) < 0.02)
        case .split:
            #expect(outputs.count == 3)
            let duration = try await outputs.asyncDuration(using: service)
            #expect(abs(duration - 2.1) < 0.02)
        case .merge:
            #expect(abs(try await service.inspect(outputs[0]).duration - 3.2) < 0.02)
        case .mix:
            #expect(abs(try await service.inspect(outputs[0]).duration - 2.1) < 0.02)
        case .speed:
            #expect(abs(try await service.inspect(outputs[0]).duration - 1.05) < 0.05)
        case .pitch:
            #expect(abs(try await service.inspect(outputs[0]).duration - 2.1) < 0.08)
        case .splitChannels:
            #expect(outputs.count == 2)
            for url in outputs { #expect(try await service.inspect(url).channels == 1) }
        case .vocalReduction:
            #expect(try await service.inspect(outputs[0]).channels == 1)
        case .repeatAudio:
            #expect(abs(try await service.inspect(outputs[0]).duration - 4.2) < 0.03)
        default: break
        }
    }

    @Test(arguments: AudioExportFormat.allCases)
    func exportsEveryAdvertisedFormat(format: AudioExportFormat) async throws {
        let fixture = try AudioIntegrationFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = format
        let output = fixture.root.appendingPathComponent("converted.\(format.fileExtension)")
        let urls = try await fixture.service.process(.init(operation: .convert, inputURLs: [fixture.first], options: options), outputURL: output)
        #expect(urls == [output])
        let summary = try await fixture.service.inspect(output)
        #expect(summary.fileSize > 0)
        #expect(summary.sampleRate == 48_000)
        #expect(summary.channels == 2)
        #expect(abs(summary.duration - 2.1) < 0.15)
    }

    @Test(arguments: AudioExportFormat.allCases)
    func exportsMonoAtTheLowestAdvertisedRate(format: AudioExportFormat) async throws {
        let fixture = try AudioIntegrationFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = format
        options.channelMode = .mono
        if format == .ogg { options.channelMode = .stereo }
        options.sampleRate = try #require(format.sampleRates.first)
        let output = fixture.root.appendingPathComponent("mono.\(format.fileExtension)")
        _ = try await fixture.service.process(.init(operation: .convert, inputURLs: [fixture.first], options: options), outputURL: output)
        let summary = try await fixture.service.inspect(output)
        #expect(summary.sampleRate == options.sampleRate)
        #expect(summary.channels == (format == .ogg ? 2 : 1))
    }

    @Test(arguments: [0.25, 0.5, 1.0, 2.0, 4.0])
    func tempoExtremesPreserveTheRequestedDuration(speed: Double) async throws {
        let fixture = try AudioIntegrationFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .wav
        options.speed = speed
        let output = fixture.root.appendingPathComponent("tempo.wav")
        _ = try await fixture.service.process(.init(operation: .speed, inputURLs: [fixture.first], options: options), outputURL: output)
        #expect(abs(try await fixture.service.inspect(output).duration - 2.1 / speed) < 0.16)
    }

    @Test(arguments: AudioChannelMode.allCases)
    func appliesChannelSelectionAndSwap(mode: AudioChannelMode) async throws {
        let fixture = try AudioIntegrationFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .wav
        options.channelMode = mode
        let output = fixture.root.appendingPathComponent("channels.wav")
        _ = try await fixture.service.process(.init(operation: .channels, inputURLs: [fixture.first], options: options), outputURL: output)
        let samples = try fixture.samples(output)
        #expect(samples.count == ([AudioChannelMode.mono, .left, .right].contains(mode) ? 1 : 2))
        if mode == .left { #expect(abs(samples[0][100] - 0.2) < 0.002) }
        if mode == .right { #expect(abs(samples[0][100] + 0.1) < 0.002) }
        if mode == .swap {
            #expect(abs(samples[0][100] + 0.1) < 0.002)
            #expect(abs(samples[1][100] - 0.2) < 0.002)
        }
    }

    @Test
    func joinsMixedFormatsInUserOrderAndChangesVolume() async throws {
        let fixture = try AudioIntegrationFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .flac
        options.sampleRate = 44_100
        let flac = fixture.root.appendingPathComponent("second.flac")
        _ = try await fixture.service.process(.init(operation: .convert, inputURLs: [fixture.second], options: options), outputURL: flac)
        options.format = .wav
        options.sampleRate = 48_000
        let joined = fixture.root.appendingPathComponent("joined.wav")
        _ = try await fixture.service.process(.init(operation: .merge, inputURLs: [flac, fixture.first], options: options), outputURL: joined)
        let samples = try fixture.samples(joined)
        #expect(abs(samples[0][100] + 0.3) < 0.002)
        #expect(abs(samples[0][60_000] - 0.2) < 0.002)
        let quieter = fixture.root.appendingPathComponent("quieter.wav")
        options.volumeDB = -6
        _ = try await fixture.service.process(.init(operation: .volume, inputURLs: [fixture.first], options: options), outputURL: quieter)
        #expect(abs(try fixture.samples(quieter)[0][100] - 0.2 * pow(10, -6.0 / 20)) < 0.002)
    }

    @Test
    func extractionUsesVideoAudioAndReportsSilentVideo() async throws {
        let fixture = try AudioIntegrationFixture()
        defer { fixture.clean() }
        let video = fixture.root.appendingPathComponent("video.mp4")
        let tools = try AudioProcessingService.resolveTools()
        let result = try await AudioProcessingService.runProcess(tools.ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-f", "lavfi", "-i", "color=s=16x16:d=1",
            "-i", fixture.first.path, "-c:v", "mpeg4", "-c:a", "aac", "-shortest", video.path,
        ])
        #expect(result.status == 0)
        var options = AudioProcessingOptions()
        options.format = .wav
        let output = fixture.root.appendingPathComponent("extracted.wav")
        _ = try await fixture.service.process(.init(operation: .extract, inputURLs: [video], options: options), outputURL: output)
        #expect(try await fixture.service.inspect(output).duration > 0.9)
        let silentVideo = fixture.root.appendingPathComponent("silent.mp4")
        let silent = try await AudioProcessingService.runProcess(tools.ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-f", "lavfi", "-i", "color=s=16x16:d=0.1", "-c:v", "mpeg4", silentVideo.path,
        ])
        #expect(silent.status == 0)
        await #expect(throws: AudioProcessingError.noAudio(silentVideo)) { try await fixture.service.inspect(silentVideo) }
    }

    @Test
    func writesAndClearsMetadataWithoutShellInterpolation() async throws {
        let fixture = try AudioIntegrationFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        let title = "中文 \"quoted\" ; $(touch unwanted) `pwd`\nsecond line"
        options.metadata = ["title": title, "artist": "Fixture", "album": "Audio", "comment": "Keep"]
        let output = fixture.root.appendingPathComponent("tags.m4a")
        _ = try await fixture.service.process(.init(operation: .metadata, inputURLs: [fixture.first], options: options), outputURL: output)
        #expect(try await fixture.service.inspect(output).metadata["title"] == title)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("unwanted").path))
        options.clearMetadata = true
        let cleared = fixture.root.appendingPathComponent("cleared.m4a")
        _ = try await fixture.service.process(.init(operation: .metadata, inputURLs: [output], options: options), outputURL: cleared)
        let tags = try await fixture.service.inspect(cleared).metadata
        #expect(tags["title"] == nil && tags["artist"] == nil && tags["album"] == nil && tags["comment"] == nil)
    }

    @Test
    func removesSilenceAndKeepsFinalShortSegment() async throws {
        let fixture = try AudioIntegrationFixture()
        defer { fixture.clean() }
        let audio = fixture.root.appendingPathComponent("with-silence.wav")
        try fixture.write(audio, duration: 2.1, sampleRate: 48_000, values: [0.2, 0.1], silence: true)
        var options = AudioProcessingOptions()
        options.format = .wav
        options.silenceDuration = 0.1
        let output = fixture.root.appendingPathComponent("without-silence.wav")
        _ = try await fixture.service.process(.init(operation: .removeSilence, inputURLs: [audio], options: options), outputURL: output)
        #expect(try await fixture.service.inspect(output).duration < 1.4)
        options.segmentDuration = 0.8
        let outputs = try await fixture.service.process(.init(operation: .split, inputURLs: [fixture.first], options: options), outputURL: fixture.root)
        #expect(outputs.count == 3)
        #expect(abs(try await fixture.service.inspect(outputs[2]).duration - 0.5) < 0.02)
    }

    @Test(arguments: [0.0, 1.0])
    func removalAtEitherBoundaryDoesNotLoseRemainingAudio(start: Double) async throws {
        let fixture = try AudioIntegrationFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .wav
        options.startTime = start
        options.endTime = start == 0 ? 1 : 2.1
        let output = fixture.root.appendingPathComponent("removed.wav")
        _ = try await fixture.service.process(.init(operation: .removeSegment, inputURLs: [fixture.first], options: options), outputURL: output)
        #expect(abs(try await fixture.service.inspect(output).duration - (start == 0 ? 1.1 : 1)) < 0.02)
    }
}

private struct AudioIntegrationFixture {
    let root: URL
    let service = AudioProcessingService()
    var first: URL { root.appendingPathComponent("first \" ; $().wav") }
    var second: URL { root.appendingPathComponent("second.wav") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioIntegration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try write(first, duration: 2.1, sampleRate: 48_000, values: [0.2, -0.1])
        try write(second, duration: 1.1, sampleRate: 44_100, values: [-0.3])
    }

    func clean() { try? FileManager.default.removeItem(at: root) }

    func write(_ url: URL, duration: Double, sampleRate: Double, values: [Float], silence: Bool = false) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: UInt32(values.count)))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(duration * sampleRate)))
        buffer.frameLength = buffer.frameCapacity
        let channels = try #require(buffer.floatChannelData)
        for (channel, value) in values.enumerated() {
            for index in 0..<Int(buffer.frameLength) {
                let time = Double(index) / sampleRate
                let isSilent = silence && (time < 0.3 || (time > 0.8 && time < 1.2) || time > 1.7)
                channels[channel][index] = isSilent ? 0 : value
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    func samples(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)))
        try file.read(into: buffer)
        let samples = try #require(buffer.floatChannelData)
        return (0..<Int(buffer.format.channelCount)).map { Array(UnsafeBufferPointer(start: samples[$0], count: Int(buffer.frameLength))) }
    }
}

private extension [URL] {
    func asyncDuration(using service: AudioProcessingService) async throws -> Double {
        var duration = 0.0
        for url in self { duration += try await service.inspect(url).duration }
        return duration
    }
}
