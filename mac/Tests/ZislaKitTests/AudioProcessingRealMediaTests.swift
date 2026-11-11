import AVFoundation
import Foundation
import Testing
@testable import ZislaKit

@Suite(.serialized, .timeLimit(.minutes(3)), .enabled(if: ProcessInfo.processInfo.environment["ZISLA_AUDIO_TEST_MEDIA_DIRECTORY"] != nil))
struct AudioProcessingRealMediaTests {
    @Test(arguments: AudioToolOperation.allCases)
    func realRecordingsExerciseEveryOperationWithoutChangingSources(operation: AudioToolOperation) async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = operation == .compress ? .mp3 : .wav
        options.bitrateKbps = 64
        options.startTime = 2
        options.endTime = 6
        options.segmentDuration = 4
        options.generatedDuration = 1
        options.fadeInDuration = 1.5
        options.fadeOutDuration = 1.5
        options.speed = 1.5
        options.pitchSemitones = 5
        options.bassDB = 6
        options.midDB = -4
        options.trebleDB = 3
        var names = ["speech.wav"]
        if operation.generatesAudio { names = [] }
        if operation.requiresMultipleInputs { names = ["music.wav", "speech.wav"] }
        if [.equalizer, .dynamics, .fade, .channels, .splitChannels].contains(operation) { names = ["music.wav"] }
        if operation == .vocalReduction { names = ["centered-vocals.wav"] }
        if operation == .extract { names = ["video.mp4"] }
        if operation == .denoise { names = ["noisy-speech.wav"] }
        if operation == .removeSilence { names = ["padded-speech.wav"] }
        let inputs = try names.map { try fixture.media($0) }
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let destination = operation.exportsToDirectory(inputCount: inputs.count) ? fixture.root : fixture.output(options.format)
        let outputs = try await fixture.service.process(.init(operation: operation, inputURLs: inputs, options: options), outputURL: destination)
        #expect(!outputs.isEmpty)
        for output in outputs {
            let summary = try await fixture.service.inspect(output)
            #expect(summary.duration > 0 && summary.sampleRate == 48_000)
            let decoded = try await AudioProcessingService.runProcess(fixture.tools.ffmpeg, [
                "-v", "error", "-nostdin", "-xerror", "-i", output.path, "-map", "0:a:0", "-f", "null", "-",
            ])
            #expect(decoded.status == 0, "The complete export must decode: \(decoded.standardError)")
        }
        for (input, original) in zip(inputs, originals) { #expect(try Data(contentsOf: input) == original) }
        #expect(try fixture.contents().allSatisfy { !$0.hasPrefix(".zisla-audio-") })
    }

    @Test(arguments: ["speech.wav", "music.wav"], AudioExportFormat.allCases)
    func everyFormatDecodesRealMonoAndStereoRecordings(name: String, format: AudioExportFormat) async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = format
        let input = try fixture.media(name)
        let expected = try await fixture.service.inspect(input)
        let output = fixture.output(format)
        _ = try await fixture.service.process(.init(operation: .convert, inputURLs: [input], options: options), outputURL: output)
        let decoded = try await fixture.decode(output)
        let file = try AVAudioFile(forReading: decoded)
        #expect(abs(Double(file.length) / file.processingFormat.sampleRate - expected.duration) < 0.06)
        #expect(file.processingFormat.channelCount == (format == .ogg ? 2 : expected.channels))
        let summary = try await fixture.service.inspect(output)
        #expect(abs(summary.duration - Double(file.length) / file.processingFormat.sampleRate) < 0.06)
    }

    @Test(arguments: AudioExportFormat.allCases)
    func reencodedFilesSplitWithoutLosingOrAddingDecodedAudio(format: AudioExportFormat) async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = format
        let input = fixture.root.appendingPathComponent("source.\(format.fileExtension)")
        _ = try await fixture.service.process(.init(operation: .convert, inputURLs: [try fixture.media("music.wav")], options: options), outputURL: input)
        let original = try fixture.samples(try await fixture.decode(input))
        let directory = fixture.root.appendingPathComponent("split")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        options.format = .wav
        options.segmentDuration = 1
        let outputs = try await fixture.service.process(.init(operation: .split, inputURLs: [input], options: options), outputURL: directory)
        var joined = Array(repeating: [Float](), count: original.count)
        for output in outputs {
            let part = try fixture.samples(output)
            for channel in 0..<joined.count { joined[channel] += part[channel] }
        }
        #expect(joined.map(\.count) == original.map(\.count))
        for channel in 0..<joined.count {
            #expect(zip(joined[channel], original[channel]).allSatisfy { abs($0 - $1) <= 1.0 / 32_768 })
        }
    }

    @Test
    func delayedContainerTimestampsDoNotShiftRequestedEditRanges() async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .wma
        let input = fixture.root.appendingPathComponent("input.wma")
        _ = try await fixture.service.process(.init(operation: .convert, inputURLs: [try fixture.media("music.wav")], options: options), outputURL: input)
        let original = try fixture.samples(try await fixture.decode(input))
        options.format = .wav
        options.startTime = 2
        options.endTime = 6
        options.generatedDuration = 0.5
        for operation in [AudioToolOperation.trim, .removeSegment, .insertSilence] {
            let output = fixture.root.appendingPathComponent("\(operation.rawValue).wav")
            _ = try await fixture.service.process(.init(operation: operation, inputURLs: [input], options: options), outputURL: output)
            let actual = try fixture.samples(output)
            for channel in 0..<original.count {
                let samples = original[channel]
                let expected: [Float]
                switch operation {
                case .trim: expected = Array(samples[96_000..<288_000])
                case .removeSegment: expected = Array(samples[..<96_000]) + Array(samples[288_000...])
                default: expected = Array(samples[..<96_000]) + Array(repeating: 0, count: 24_000) + Array(samples[96_000...])
                }
                #expect(actual[channel].count == expected.count)
                #expect(zip(actual[channel], expected).allSatisfy { abs($0 - $1) <= 1.0 / 32_768 })
            }
        }
    }

    @Test(arguments: ["speech.aac", "headerless.mp3"])
    func rawCompressedAudioUsesDecodedDurationAndSplitsWithoutEmptyTails(name: String) async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        let input = try fixture.media(name)
        let original = try fixture.samples(try await fixture.decode(input))[0]
        let summary = try await fixture.service.inspect(input)
        #expect(abs(summary.duration - Double(original.count) / 48_000) <= 1.0 / 48_000)
        var options = AudioProcessingOptions()
        options.format = .wav
        options.segmentDuration = 1
        let outputs = try await fixture.service.process(.init(operation: .split, inputURLs: [input], options: options), outputURL: fixture.root)
        #expect(outputs.count == Int(ceil(Double(original.count) / 48_000)))
        var reconstructed: [Float] = []
        for output in outputs { reconstructed += try fixture.samples(output)[0] }
        #expect(reconstructed.count == original.count)
        #expect(zip(reconstructed, original).allSatisfy { abs($0 - $1) <= 1.0 / 32_768 })
        #expect(try fixture.contents().allSatisfy { !$0.hasPrefix(".zisla-audio-") })
    }

    @Test
    func opusRejectsUnsupportedMonoBitrateBeforeCreatingAnyOutput() async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .opus
        options.channelMode = .mono
        options.bitrateKbps = 320
        await #expect(throws: AudioProcessingError.invalidParameter("码率")) {
            try await fixture.service.process(.init(operation: .convert, inputURLs: [try fixture.media("speech.wav")], options: options), outputURL: fixture.output(.opus))
        }
        #expect(try fixture.contents().isEmpty)
    }

    @Test(arguments: ["speech.wav", "music-full.wav"], [-24.0, -16.0])
    func normalizationMeasuresRealVoiceAndMusicBeforeExport(name: String, target: Double) async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .wav
        options.targetLoudness = target
        let output = fixture.output(.wav)
        _ = try await fixture.service.process(.init(operation: .normalize, inputURLs: [try fixture.media(name)], options: options), outputURL: output)
        let metrics = try await fixture.loudness(output)
        #expect(abs(metrics.integrated - target) < 0.6, "Requested \(target) LUFS, measured \(metrics.integrated) LUFS")
        #expect(metrics.peak <= -1.3, "Normalization must respect its true-peak ceiling")
    }

    @Test(arguments: ["speech.wav", "music-full.wav"])
    func normalizationPrioritizesPeakCeilingForUnreachableLoudness(name: String) async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .wav
        options.targetLoudness = -5
        let output = fixture.output(.wav)
        _ = try await fixture.service.process(.init(operation: .normalize, inputURLs: [try fixture.media(name)], options: options), outputURL: output)
        #expect(try await fixture.loudness(output).peak <= -1.3)
    }

    @Test(arguments: AudioExportFormat.allCases)
    func tagsRoundTripAndClearAcrossEveryExportFormat(format: AudioExportFormat) async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = format
        options.metadata = ["title": "真实录音 \"quoted\" ; $(touch unwanted) `pwd`\nline",
                            "artist": "Garth Comira", "album": "Audio", "comment": "Local recording"]
        let tagged = fixture.output(format)
        _ = try await fixture.service.process(.init(operation: .metadata, inputURLs: [try fixture.media("speech.wav")], options: options), outputURL: tagged)
        let tags = try await fixture.service.inspect(tagged).metadata
        for (key, value) in options.metadata { #expect(tags[key] == value, "Missing \(key) in \(format)") }
        options.clearMetadata = true
        let cleared = fixture.root.appendingPathComponent("cleared.\(format.fileExtension)")
        _ = try await fixture.service.process(.init(operation: .metadata, inputURLs: [tagged], options: options), outputURL: cleared)
        let remaining = try await fixture.service.inspect(cleared).metadata
        #expect(options.metadata.keys.allSatisfy { remaining[$0] == nil })
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("unwanted").path))
    }

    @Test
    func convertingRealMonoToStereoPreservesEachChannelLevel() async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        let input = try fixture.media("speech.wav")
        var options = AudioProcessingOptions()
        options.format = .wav
        options.channelMode = .stereo
        let output = fixture.output(.wav)
        _ = try await fixture.service.process(.init(operation: .channels, inputURLs: [input], options: options), outputURL: output)
        let original = try fixture.samples(input)[0]
        let converted = try fixture.samples(output)
        #expect(converted.count == 2)
        for channel in converted {
            #expect(channel.count == original.count)
            #expect(zip(channel, original).allSatisfy { abs($0 - $1) <= 1.0 / 32_768 })
        }
    }

    @Test
    func stereoBatchAndJoinPreserveTheLaterStereoRecording() async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .wav
        options.channelMode = .stereo
        let speech = try fixture.media("speech.wav")
        let music = try fixture.media("music.wav")
        let inputs = [speech, music]
        let outputs = try await fixture.service.process(.init(operation: .convert, inputURLs: inputs, options: options), outputURL: fixture.root)
        let expectedMusic = try fixture.samples(music)
        let convertedMusic = try fixture.samples(outputs[1])
        #expect(convertedMusic == expectedMusic)
        let joined = fixture.root.appendingPathComponent("joined.wav")
        _ = try await fixture.service.process(.init(operation: .merge, inputURLs: inputs, options: options), outputURL: joined)
        let samples = try fixture.samples(joined)
        let speechFrames = try fixture.samples(speech)[0].count
        for channel in 0..<2 {
            #expect(Array(samples[channel].dropFirst(speechFrames)) == expectedMusic[channel])
        }
    }

    @Test
    func cancelsAnActualLongExportAndCleansItsPartialFile() async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        let input = try fixture.media("long-speech.m4a")
        let original = try Data(contentsOf: input)
        var options = AudioProcessingOptions()
        options.format = .flac
        let output = fixture.output(.flac)
        let request = AudioProcessingRequest(operation: .convert, inputURLs: [input], options: options)
        let clock = ContinuousClock()
        let task = Task {
            try await fixture.service.process(request, outputURL: output)
        }
        defer { task.cancel() }
        let deadline = clock.now + .seconds(10)
        var partial: URL?
        while clock.now < deadline, partial == nil {
            for directory in try FileManager.default.contentsOfDirectory(at: fixture.root, includingPropertiesForKeys: nil)
                where directory.lastPathComponent.hasPrefix(".zisla-audio-") {
                for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
                    where (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 {
                    partial = file
                }
            }
            if partial == nil { try await Task.sleep(for: .milliseconds(10)) }
        }
        let staged = try #require(partial, "The real encoder must have written a partial output before cancellation")
        let cancelled = clock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.now - cancelled < .seconds(5))
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        #expect(try fixture.contents().isEmpty)
        #expect(try Data(contentsOf: input) == original)
        options.format = .wav
        options.startTime = 1788
        options.endTime = 1800
        let trimmed = fixture.output(.wav)
        _ = try await fixture.service.process(.init(operation: .trim, inputURLs: [input], options: options), outputURL: trimmed)
        #expect(abs(try await fixture.service.inspect(trimmed).duration - 12) <= 1.0 / 48_000)
    }

    @Test
    func longExportFullyDecodesAndPreservesItsThirtyMinuteDuration() async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .flac
        let input = try fixture.media("long-speech.m4a")
        let output = fixture.output(.flac)
        _ = try await fixture.service.process(.init(operation: .convert, inputURLs: [input], options: options), outputURL: output)
        #expect(abs(try await fixture.service.inspect(output).duration - 1800) <= 1.0 / 48_000)
        let decoded = try await AudioProcessingService.runProcess(fixture.tools.ffmpeg, [
            "-v", "error", "-nostdin", "-xerror", "-i", output.path, "-map", "0:a:0", "-f", "null", "-",
        ])
        #expect(decoded.status == 0, "Long audio must decode completely: \(decoded.standardError)")
        await #expect(throws: AudioProcessingError.reverseTooLarge) {
            try await fixture.service.process(.init(operation: .reverse, inputURLs: [input], options: options),
                                              outputURL: fixture.root.appendingPathComponent("reverse.flac"))
        }
        #expect(try fixture.contents() == [output.lastPathComponent])
    }

    @Test
    func denoisingKeepsSpeechAlignedAndLowersRecordedRainNoise() async throws {
        let fixture = try RealAudioFixture()
        defer { fixture.clean() }
        let noisy = try fixture.samples(try fixture.media("noisy-speech.wav"))[0]
        let clean = try fixture.samples(try fixture.media("padded-clean.wav"))[0]
        var options = AudioProcessingOptions()
        options.format = .wav
        let output = fixture.output(.wav)
        _ = try await fixture.service.process(.init(operation: .denoise, inputURLs: [try fixture.media("noisy-speech.wav")], options: options), outputURL: output)
        let denoised = try fixture.samples(output)[0]
        #expect(denoised.count == noisy.count)
        let voice = 192_000..<576_000
        let noise = 24_000..<72_000
        let dot = zip(denoised[voice], clean[voice]).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
        let energy = sqrt(denoised[voice].reduce(0.0) { $0 + Double($1 * $1) } * clean[voice].reduce(0.0) { $0 + Double($1 * $1) })
        #expect(dot / energy > 0.995, "Denoising must preserve the recording's timing")
        #expect(20 * log10(fixture.rms(denoised[noise]) / fixture.rms(noisy[noise])) < -0.5)
        let errorAfter = zip(denoised[voice], clean[voice]).reduce(0.0) { $0 + pow(Double($1.0 - $1.1), 2) }
        let errorBefore = zip(noisy[voice], clean[voice]).reduce(0.0) { $0 + pow(Double($1.0 - $1.1), 2) }
        #expect(errorAfter < errorBefore)
    }
}

private struct RealAudioFixture {
    let root: URL
    let mediaRoot: URL
    let service = AudioProcessingService()
    let tools: AudioProcessingTools

    init() throws {
        mediaRoot = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["ZISLA_AUDIO_TEST_MEDIA_DIRECTORY"]))
        tools = try AudioProcessingService.resolveTools()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioRealMedia-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    func clean() { try? FileManager.default.removeItem(at: root) }
    func output(_ format: AudioExportFormat) -> URL { root.appendingPathComponent("output.\(format.fileExtension)") }
    func contents() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() }

    func media(_ name: String) throws -> URL {
        let url = mediaRoot.appendingPathComponent(name)
        #expect(FileManager.default.isReadableFile(atPath: url.path), "Missing opt-in recording: \(name)")
        return url
    }

    func samples(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)))
        try file.read(into: buffer)
        let channels = try #require(buffer.floatChannelData)
        return (0..<Int(buffer.format.channelCount)).map { Array(UnsafeBufferPointer(start: channels[$0], count: Int(buffer.frameLength))) }
    }

    func decode(_ url: URL) async throws -> URL {
        let decoded = root.appendingPathComponent("\(UUID()).wav")
        let result = try await AudioProcessingService.runProcess(tools.ffmpeg, [
            "-v", "error", "-nostdin", "-xerror", "-i", url.path, "-map", "0:a:0", "-ar", "48000", "-c:a", "pcm_s16le", decoded.path,
        ])
        #expect(result.status == 0, "Audio decoding failed: \(result.standardError)")
        return decoded
    }

    func rms(_ samples: ArraySlice<Float>) -> Double {
        sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
    }

    func loudness(_ url: URL) async throws -> (integrated: Double, peak: Double) {
        let result = try await AudioProcessingService.runProcess(tools.ffmpeg, [
            "-hide_banner", "-nostats", "-nostdin", "-i", url.path, "-map", "0:a:0",
            "-af", "ebur128=peak=true:framelog=verbose", "-f", "null", "-",
        ])
        #expect(result.status == 0)
        let summary = try #require(result.standardError.range(of: "Summary:", options: .backwards))
        let text = String(result.standardError[summary.lowerBound...])
        func value(_ pattern: String) throws -> Double {
            let regex = try NSRegularExpression(pattern: pattern)
            let match = try #require(regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)))
            let range = try #require(Range(match.range(at: 1), in: text))
            return try #require(Double(text[range]))
        }
        return try (value(#"I:\s+(-?[\d.]+) LUFS"#), value(#"Peak:\s+(-?[\d.]+) dBFS"#))
    }
}
