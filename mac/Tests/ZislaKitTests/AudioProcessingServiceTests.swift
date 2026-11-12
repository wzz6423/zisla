import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct AudioProcessingServiceTests {
    @Test(arguments: AudioExportFormat.allCases)
    func lossyExportBitratesMatchTheFormatContract(format: AudioExportFormat) {
        #expect(format.maximumBitrateKbps == (format == .opus ? 256 : 320))
    }

    @Test
    func rejectsMissingToolsWithoutCreatingOutput() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let service = AudioProcessingService(tools: { throw AudioProcessingError.missingTools }, run: { _, _ in
            Issue.record("A missing dependency must not launch a process")
            throw CancellationError()
        })
        await #expect(throws: AudioProcessingError.missingTools) {
            try await service.process(.init(operation: .convert, inputURLs: [fixture.input]), outputURL: fixture.output)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    }

    @Test
    func resolutionRequiresTrustedFFmpegAndFFprobeTogether() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zisla-audio-tools-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        let ffmpeg = managed.appendingPathComponent("ffmpeg")
        let ffprobe = managed.appendingPathComponent("ffprobe")
        #expect(throws: AudioProcessingError.missingTools) {
            try AudioProcessingService.resolveTools(bundle: root, managedTools: managed, candidates: [])
        }
        for tool in [ffmpeg, ffprobe] {
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
            if tool == ffmpeg {
                #expect(throws: AudioProcessingError.missingTools) {
                    try AudioProcessingService.resolveTools(bundle: root, managedTools: managed, candidates: [])
                }
            }
        }
        let resolved = try AudioProcessingService.resolveTools(bundle: root, managedTools: managed, candidates: [])
        #expect(resolved == .init(ffmpeg: ffmpeg, ffprobe: ffprobe))
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: ffprobe.path)
        #expect(throws: AudioProcessingError.missingTools) {
            try AudioProcessingService.resolveTools(bundle: root, managedTools: managed, candidates: [])
        }
    }

    @Test
    func incompletePreferredToolLocationDoesNotHideACompleteFallback() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zisla-audio-tools-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed")
        let fallback = root.appendingPathComponent("fallback")
        for directory in [managed, fallback] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ffmpeg = directory.appendingPathComponent("ffmpeg")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: ffmpeg)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpeg.path)
        }
        let ffprobe = fallback.appendingPathComponent("ffprobe")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: ffprobe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffprobe.path)
        let tools = try AudioProcessingService.resolveTools(bundle: root, managedTools: managed,
                                                           candidates: [fallback.appendingPathComponent("ffmpeg")])
        #expect(tools == .init(ffmpeg: fallback.appendingPathComponent("ffmpeg"), ffprobe: ffprobe))
    }

    @Test(arguments: [AudioToolOperation.convert, .merge, .generateTone])
    func rejectsInvalidInputCounts(operation: AudioToolOperation) async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let inputs = operation == .generateTone ? [fixture.input] : []
        await #expect(throws: AudioProcessingError.invalidInputCount) {
            try await fixture.service().process(.init(operation: operation, inputURLs: inputs), outputURL: fixture.output)
        }
        #expect(try fixture.contents() == ["input.wav"])
    }

    @Test(arguments: [Double.nan, .infinity, -1, 31])
    func rejectsInvalidTrimTimes(start: Double) async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.startTime = start
        options.endTime = 1
        await #expect(throws: AudioProcessingError.invalidTimeRange) {
            try await fixture.service().process(.init(operation: .trim, inputURLs: [fixture.input], options: options), outputURL: fixture.output)
        }
        #expect(try fixture.contents() == ["input.wav"])
    }

    @Test
    func rejectsNonfiniteAndOutOfRangeEffectParameters() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        for value in [Double.nan, .infinity, -.infinity, -0.25, 0, 4.01] {
            var options = AudioProcessingOptions()
            options.speed = value
            await #expect(throws: AudioProcessingError.invalidParameter("速度倍数")) {
                try await fixture.service().process(.init(operation: .speed, inputURLs: [fixture.input], options: options), outputURL: fixture.output)
            }
        }
        #expect(try fixture.contents() == ["input.wav"])
    }

    @Test
    func refusesInputsExistingFilesAndDanglingSymlinksAsDestinations() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let source = try Data(contentsOf: fixture.input)
        let service = fixture.service()
        let request = AudioProcessingRequest(operation: .convert, inputURLs: [fixture.input])
        await #expect(throws: AudioProcessingError.outputMatchesInput(fixture.input)) {
            try await service.process(request, outputURL: fixture.input)
        }
        try Data("keep".utf8).write(to: fixture.output)
        await #expect(throws: AudioProcessingError.outputAlreadyExists(fixture.output)) {
            try await service.process(request, outputURL: fixture.output)
        }
        #expect(try String(contentsOf: fixture.output, encoding: .utf8) == "keep")
        let link = fixture.root.appendingPathComponent("link.m4a")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.root.appendingPathComponent("missing"))
        await #expect(throws: AudioProcessingError.outputAlreadyExists(link)) {
            try await service.process(request, outputURL: link)
        }
        #expect(try Data(contentsOf: fixture.input) == source)
    }

    @Test
    func preservesOutputCreatedDuringEncoding() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let service = fixture.service(encode: { output in
            try Data("staged".utf8).write(to: output)
            try Data("arrived".utf8).write(to: fixture.output)
            return 0
        })
        await #expect(throws: AudioProcessingError.outputAlreadyExists(fixture.output)) {
            try await service.process(.init(operation: .convert, inputURLs: [fixture.input]), outputURL: fixture.output)
        }
        #expect(try String(contentsOf: fixture.output, encoding: .utf8) == "arrived")
        #expect(try fixture.contents() == ["input.wav", "output.m4a"])
    }

    @Test
    func removesPartialOutputWhenEncoderFails() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let source = try Data(contentsOf: fixture.input)
        let service = fixture.service(encode: { output in
            try Data("partial".utf8).write(to: output)
            return 1
        })
        await #expect(throws: AudioProcessingError.processFailed("injected failure")) {
            try await service.process(.init(operation: .convert, inputURLs: [fixture.input]), outputURL: fixture.output)
        }
        #expect(try fixture.contents() == ["input.wav"])
        #expect(try Data(contentsOf: fixture.input) == source)
    }

    @Test
    func doesNotPublishSuccessfulEncodeWithoutAudio() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let service = fixture.service(probe: { url in url == fixture.input ? AudioFixture.probeJSON : #"{"streams":[]}"# })
        do {
            _ = try await service.process(.init(operation: .convert, inputURLs: [fixture.input]), outputURL: fixture.output)
            Issue.record("An encode with no readable audio must fail")
        } catch AudioProcessingError.noAudio { }
        #expect(try fixture.contents() == ["input.wav"])
    }

    @Test
    func cancellationCleansStagingAndDoesNotPublish() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let service = fixture.service(encode: { output in
            try Data("partial".utf8).write(to: output)
            throw CancellationError()
        })
        await #expect(throws: CancellationError.self) {
            try await service.process(.init(operation: .convert, inputURLs: [fixture.input]), outputURL: fixture.output)
        }
        #expect(try fixture.contents() == ["input.wav"])
    }

    @Test
    func batchFailureLeavesNoPublishedFiles() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let second = fixture.root.appendingPathComponent("other.wav")
        try Data("second".utf8).write(to: second)
        let service = fixture.service(encode: { output in
            try Data("partial".utf8).write(to: output)
            return output.lastPathComponent.hasPrefix("1.") ? 1 : 0
        })
        await #expect(throws: AudioProcessingError.processFailed("injected failure")) {
            try await service.process(.init(operation: .convert, inputURLs: [fixture.input, second]), outputURL: fixture.root)
        }
        #expect(try fixture.contents() == ["input.wav", "other.wav"])
    }

    @Test
    func rollsBackEarlierPublicationsWhenLaterDestinationAppears() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let second = fixture.root.appendingPathComponent("other.wav")
        try Data("second".utf8).write(to: second)
        let secondOutput = fixture.root.appendingPathComponent("2-other.m4a")
        let service = fixture.service(encode: { output in
            try Data("encoded".utf8).write(to: output)
            if output.lastPathComponent.hasPrefix("1.") { try Data("preserved".utf8).write(to: secondOutput) }
            return 0
        })
        await #expect(throws: AudioProcessingError.outputAlreadyExists(secondOutput)) {
            try await service.process(.init(operation: .convert, inputURLs: [fixture.input, second]), outputURL: fixture.root)
        }
        #expect(try fixture.contents() == ["2-other.m4a", "input.wav", "other.wav"])
        #expect(try String(contentsOf: secondOutput, encoding: .utf8) == "preserved")
    }

    @Test(arguments: [#"{"streams":[]}"#, "not JSON", #"{"streams":[{"codec_name":"pcm","sample_rate":"0","channels":2}],"format":{"duration":"1"}}"#,
                      #"{"streams":[{"codec_name":"pcm","sample_rate":"48000","channels":2}],"format":{"duration":"nan"}}"#])
    func rejectsMalformedOrEmptyProbeResponses(response: String) async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        await #expect(throws: AudioProcessingError.noAudio(fixture.input)) {
            try await fixture.service(probe: { _ in response }).inspect(fixture.input)
        }
    }

    @Test
    func refusesPlaylistsRemoteInputsAndInvalidMetadata() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let playlist = fixture.root.appendingPathComponent("audio.m3u8")
        try Data("https://example.invalid/audio".utf8).write(to: playlist)
        await #expect(throws: AudioProcessingError.unsupportedInput(playlist)) { try await fixture.service().inspect(playlist) }
        let remote = try #require(URL(string: "https://example.invalid/input.wav"))
        await #expect(throws: AudioProcessingError.invalidInput(remote)) { try await fixture.service().inspect(remote) }
        var options = AudioProcessingOptions()
        options.metadata = ["title": "bad\0value"]
        await #expect(throws: AudioProcessingError.invalidParameter("音频标签")) {
            try await fixture.service().process(.init(operation: .metadata, inputURLs: [fixture.input], options: options), outputURL: fixture.output)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    }

    @Test
    func segmentationAndReverseHaveExplicitResourceBudgets() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let service = fixture.service(probe: { _ in AudioFixture.probeJSON.replacingOccurrences(of: "2.0", with: "99999.0") })
        await #expect(throws: AudioProcessingError.tooManyOutputs) {
            try await service.process(.init(operation: .split, inputURLs: [fixture.input]), outputURL: fixture.root)
        }
        await #expect(throws: AudioProcessingError.reverseTooLarge) {
            try await service.process(.init(operation: .reverse, inputURLs: [fixture.input]), outputURL: fixture.output)
        }
        #expect(try fixture.contents() == ["input.wav"])
    }

    @Test
    func seededInputFormatFuzzRejectsUnknownExtensions() throws {
        var seed: UInt64 = 0xA0D10
        let symbols = Array("xyz;[]:/\\$'\"\n ")
        for _ in 0..<128 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let ext = String((0..<8).map { index in symbols[Int((seed >> (index * 6)) % UInt64(symbols.count))] })
            let url = URL(fileURLWithPath: "/fixture/input").appendingPathExtension(ext)
            #expect(throws: AudioProcessingError.unsupportedInput(url)) { try AudioProcessingService.inputFormat(url) }
        }
    }

    @Test
    func rejectsUnsupportedEncodingCombinationsAndMonoChannelExtraction() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        var options = AudioProcessingOptions()
        options.format = .opus
        options.sampleRate = 44_100
        await #expect(throws: AudioProcessingError.invalidParameter("采样率")) {
            try await fixture.service().process(.init(operation: .convert, inputURLs: [fixture.input], options: options), outputURL: fixture.output)
        }
        options = .init()
        options.channelMode = .right
        let mono = fixture.service(probe: { _ in AudioFixture.probeJSON.replacingOccurrences(of: "\"channels\":2", with: "\"channels\":1") })
        await #expect(throws: AudioProcessingError.stereoRequired) {
            try await mono.process(.init(operation: .channels, inputURLs: [fixture.input], options: options), outputURL: fixture.output)
        }
        options.format = .ogg
        options.channelMode = .mono
        await #expect(throws: AudioProcessingError.invalidParameter("输出格式")) {
            try await fixture.service().process(.init(operation: .convert, inputURLs: [fixture.input], options: options), outputURL: fixture.output)
        }
    }

    @Test
    func validatesAllEffectParametersBeforeEncoding() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let cases: [(AudioToolOperation, String, @Sendable (inout AudioProcessingOptions) -> Void)] = [
            (.split, "分段时长（秒）", { $0.segmentDuration = 0 }),
            (.volume, "音量（dB）", { $0.volumeDB = 25 }),
            (.normalize, "目标响度（LUFS）", { $0.targetLoudness = 0 }),
            (.fade, "淡入（秒）", { $0.fadeInDuration = 3 }),
            (.fade, "淡出（秒）", { $0.fadeOutDuration = -1 }),
            (.pitch, "音高（半音）", { $0.pitchSemitones = 13 }),
            (.denoise, "降噪强度（dB）", { $0.noiseReductionDB = 0 }),
            (.removeSilence, "静音阈值（dB）", { $0.silenceThresholdDB = -90 }),
            (.removeSilence, "最短静音（秒）", { $0.silenceDuration = 0 }),
            (.equalizer, "低频（dB）", { $0.bassDB = 21 }),
            (.equalizer, "中频（dB）", { $0.midDB = -21 }),
            (.equalizer, "高频（dB）", { $0.trebleDB = 21 }),
            (.dynamics, "压缩阈值（dB）", { $0.compressorThresholdDB = 1 }),
            (.dynamics, "压缩比", { $0.compressorRatio = 0 }),
            (.dynamics, "峰值上限（dB）", { $0.peakLimitDB = 1 }),
            (.echo, "回声延迟（秒）", { $0.echoDelay = 3 }),
            (.echo, "回声衰减", { $0.echoDecay = 1 }),
            (.repeatAudio, "重复次数", { $0.repeatCount = 1 }),
            (.insertSilence, "静音时长（秒）", { $0.generatedDuration = 0 }),
            (.generateTone, "生成时长（秒）", { $0.generatedDuration = 0 }),
            (.generateTone, "频率（Hz）", { $0.toneFrequency = 24_001 }),
            (.generateTone, "频率（Hz）", { $0.toneFrequency = 24_000 }),
            (.compress, "输出格式", { $0.format = .wav }),
            (.convert, "码率", { $0.bitrateKbps = 321 }),
            (.convert, "位深", { $0.format = .flac; $0.bitDepth = 32 }),
        ]
        for (operation, title, change) in cases {
            var options = AudioProcessingOptions()
            change(&options)
            let inputs = operation.generatesAudio ? [] : [fixture.input]
            await #expect(throws: AudioProcessingError.invalidParameter(title)) {
                try await fixture.service().process(.init(operation: operation, inputURLs: inputs, options: options), outputURL: fixture.output)
            }
            #expect(try fixture.contents() == ["input.wav"], "Invalid \(title) must leave no output")
        }
    }

    @Test(arguments: [false, true])
    func rawDurationScanRejectsFailuresAndMissingFinalTiming(fails: Bool) async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let input = fixture.root.appendingPathComponent("recording.aac")
        try Data("AAC fixture".utf8).write(to: input)
        let service = AudioProcessingService(tools: { .init(ffmpeg: URL(fileURLWithPath: "/fixture/ffmpeg"),
                                                           ffprobe: URL(fileURLWithPath: "/fixture/ffprobe")) }, run: { executable, _ in
            if executable.lastPathComponent == "ffprobe" {
                return .init(status: 0, standardOutput: Data(AudioFixture.probeJSON.utf8), standardError: "", didTimeout: false)
            }
            return .init(status: fails ? 1 : 0, standardOutput: Data("progress=end".utf8), standardError: "scan failure", didTimeout: false)
        })
        await #expect(throws: fails ? AudioProcessingError.processFailed("scan failure") : AudioProcessingError.noAudio(input)) {
            try await service.process(.init(operation: .split, inputURLs: [input]), outputURL: fixture.root)
        }
        #expect(try fixture.contents() == ["input.wav", "recording.aac"])
    }

    @Test(arguments: ["process failure", "missing stats", "malformed stats", "nonfinite stats", "unmeasurable audio", "cancelled"])
    func normalizationMeasurementFailuresCleanStagingWithoutPublishing(failure: String) async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let source = try Data(contentsOf: fixture.input)
        let service = AudioProcessingService(tools: { .init(ffmpeg: URL(fileURLWithPath: "/fixture/ffmpeg"),
                                                           ffprobe: URL(fileURLWithPath: "/fixture/ffprobe")) }, run: { executable, arguments in
            if executable.lastPathComponent == "ffprobe" {
                return .init(status: 0, standardOutput: Data(AudioFixture.probeJSON.utf8), standardError: "", didTimeout: false)
            }
            if failure == "cancelled" { throw CancellationError() }
            #expect(arguments.last == "-", "Invalid measurement must never reach encoding")
            let stats = failure == "malformed stats" ? "{invalid}" : failure == "nonfinite stats"
                ? #"{"input_i":"nan","input_tp":"-1","input_lra":"3","input_thresh":"-30","target_offset":"0"}"#
                : failure == "unmeasurable audio"
                ? #"{"input_i":"-inf","input_tp":"-20","input_lra":"0","input_thresh":"-70","target_offset":"inf"}"# : ""
            return .init(status: failure == "process failure" ? 1 : 0, standardOutput: Data(), standardError: stats, didTimeout: false)
        })
        do {
            _ = try await service.process(.init(operation: .normalize, inputURLs: [fixture.input]), outputURL: fixture.output)
            Issue.record("Invalid normalization measurement must fail")
        } catch is CancellationError {
            #expect(failure == "cancelled")
        } catch let error as AudioProcessingError {
            #expect(error == (failure == "process failure" ? .processFailed("") : .noAudio(fixture.input)))
        }
        #expect(try fixture.contents() == ["input.wav"])
        #expect(try Data(contentsOf: fixture.input) == source)
    }

    @Test
    func invalidDestinationAndPrecancelledTaskDoNotCreateStaging() async throws {
        let fixture = try AudioFixture()
        defer { fixture.clean() }
        let missing = fixture.root.appendingPathComponent("absent/output.m4a")
        await #expect(throws: AudioProcessingError.cannotWriteOutput(missing)) {
            try await fixture.service().process(.init(operation: .convert, inputURLs: [fixture.input]), outputURL: missing)
        }
        let remote = try #require(URL(string: "https://example.invalid/out.m4a"))
        await #expect(throws: AudioProcessingError.cannotWriteOutput(remote)) {
            try await fixture.service().process(.init(operation: .convert, inputURLs: [fixture.input]), outputURL: remote)
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.service().process(.init(operation: .convert, inputURLs: [fixture.input]), outputURL: fixture.output)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fixture.contents() == ["input.wav"])
    }
}

private struct AudioFixture: Sendable {
    let root: URL
    var input: URL { root.appendingPathComponent("input.wav") }
    var output: URL { root.appendingPathComponent("output.m4a") }
    static let probeJSON = #"{"streams":[{"codec_name":"pcm_s16le","sample_rate":"48000","channels":2,"duration":"2.0"}],"format":{"duration":"2.0","tags":{"title":"Fixture"}}}"#

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioProcessingTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("input remains intact".utf8).write(to: input)
    }

    func clean() { try? FileManager.default.removeItem(at: root) }
    func contents() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() }

    func service(
        probe: @escaping @Sendable (URL) -> String = { _ in Self.probeJSON },
        encode: @escaping @Sendable (URL) throws -> Int32 = { try Data("encoded".utf8).write(to: $0); return 0 }
    ) -> AudioProcessingService {
        AudioProcessingService(tools: {
            .init(ffmpeg: URL(fileURLWithPath: "/fixture/ffmpeg"), ffprobe: URL(fileURLWithPath: "/fixture/ffprobe"))
        }, run: { executable, arguments in
            if executable.lastPathComponent == "ffprobe" {
                let index = try #require(arguments.firstIndex(of: "-i"))
                return .init(status: 0, standardOutput: Data(probe(URL(fileURLWithPath: arguments[index + 1])).utf8), standardError: "", didTimeout: false)
            }
            let output = URL(fileURLWithPath: try #require(arguments.last))
            let status = try encode(output)
            return .init(status: status, standardOutput: Data(), standardError: status == 0 ? "" : "injected failure", didTimeout: false)
        })
    }
}
