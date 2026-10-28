import AVFoundation
import CoreImage
import Darwin
import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized, .timeLimit(.minutes(2)))
struct ScreenRecordingAudioOnlyExportTests {
    @Test(arguments: [RecordingExportFormat.m4a, .wav, .flac, .aac, .aiff], [false, true])
    func nativeAudioFormatsPreserveTheEditedMixedTimelineWithoutVideo(_ format: RecordingExportFormat, _ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        _ = try fixture.createTone()
        var project = fixture.project()
        project.microphoneFile = "tone.wav"
        project.cameraFile = "unused-camera.mov"
        project.edits.showCamera = true
        project.edits.microphoneVolume = 0.5
        project.edits.segments = [.init(start: 0.5, end: 1.5, speed: 2)]
        if multitrack { project.timeline = .migrating(project) }
        let output = fixture.root.appendingPathComponent("Audio." + format.fileExtension)
        let exporter = ScreenRecordingExporter(resolveFFmpeg: { throw ScreenRecordingExportError.missingFFmpeg }, checkpoint: {
            if case .frame = $0 { Issue.record("Audio exports must not render video frames") }
        })
        try await exporter.export(project: project, directory: fixture.directory, to: output,
            configuration: .init(format: format, resolution: .ultraHD, frameRate: -99))
        #expect(exporter.progress == 1 && !exporter.isExporting)
        let asset = AVURLAsset(url: output)
        #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
        let audioTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let description = try #require(try await audioTrack.load(.formatDescriptions).first)
        let stream = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(description))
        let expectedCodec = format == .flac ? kAudioFormatFLAC
            : format == .m4a || format == .aac ? kAudioFormatMPEG4AAC : kAudioFormatLinearPCM
        #expect(stream.pointee.mFormatID == expectedCodec)
        let decoded = try await decode(output)
        #expect(decoded.rate == 48_000 && decoded.channels == 2)
        #expect(abs(Double(decoded.samples.count) / decoded.rate - 0.5) < 0.06)
        #expect(energy(decoded.samples, start: 0.12, end: 0.35, rate: decoded.rate) > 0.000_5)
        #expect(try stagingFiles(in: fixture.root).isEmpty)
        #expect(try fixture.files() == ["screen.mp4", "tone.wav"])
    }

    @Test(arguments: [RecordingExportFormat.wav, .flac, .aiff], [24_000, 48_001])
    func losslessFormatsPreserveValidFramesWithoutDecoderPadding(_ format: RecordingExportFormat, _ frames: Int) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createTone()
        var project = toneProject()
        project.timeline?.clips[0].sourceEnd = Double(frames) / 48_000
        let output = fixture.root.appendingPathComponent("valid-frames." + format.fileExtension)
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory, to: output,
            configuration: .init(format: format))
        let file = try AVAudioFile(forReading: output)
        #expect(file.length == AVAudioFramePosition(frames))
        let decoded = try await decode(output)
        #expect(decoded.samples.count == frames, "Decoder block padding must not extend the exported timeline")
        #expect(energy(decoded.samples, start: 0.12, end: 0.35, rate: decoded.rate) > 0.000_5)
        #expect(try stagingFiles(in: fixture.root).isEmpty)
    }

    @Test func audioOnlyCompositionKeepsOverlapGainAndLeadingInternalTrailingSilence() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createTone()
        var project = fixture.project()
        project.videoFile = ""
        let audio = RecordingMediaAsset(name: "Tone", file: "tone.wav", kind: .audio, duration: 2)
        let image = RecordingMediaAsset(name: "Unneeded image", file: "not-decoded.png", kind: .image,
            duration: 2, width: 64, height: 48)
        project.timeline = .init(assets: [audio, image], tracks: [.init(id: "mixed"), .init(id: "overlay")], clips: [
            .init(trackID: "mixed", content: .audio(audio.id), start: 0.2, sourceStart: 0.2, sourceEnd: 0.6, volume: 0.4),
            .init(trackID: "overlay", content: .audio(audio.id), start: 0.2, sourceStart: 0.2, sourceEnd: 0.6, volume: 0.4),
            .init(trackID: "mixed", content: .audio(audio.id), start: 0.9, sourceStart: 0.2, sourceEnd: 0.6, volume: 0.4),
            .init(trackID: "overlay", content: .image(image.id), start: 0, sourceEnd: 2),
        ])
        let output = fixture.root.appendingPathComponent("mixed.wav")
        let exporter = ScreenRecordingExporter()
        try await exporter.export(project: project, directory: fixture.directory, to: output,
            configuration: .init(format: .wav))
        let decoded = try await decode(output)
        #expect(abs(Double(decoded.samples.count) / decoded.rate - 2) < 1 / decoded.rate)
        let single = energy(decoded.samples, start: 1.0, end: 1.2)
        let overlap = energy(decoded.samples, start: 0.3, end: 0.5)
        #expect(single > 0.000_1)
        #expect(abs(overlap / single - 4) < 0.3, "Overlapping clips must add their selected gains")
        var referenceProject = project
        referenceProject.timeline?.clips.removeAll { $0.trackID == "overlay" }
        referenceProject.timeline?.clips[1].volume = 1
        let referenceURL = fixture.root.appendingPathComponent("reference.wav")
        try await ScreenRecordingExporter().export(project: referenceProject, directory: fixture.directory, to: referenceURL,
            configuration: .init(format: .wav))
        let reference = try await decode(referenceURL)
        let fullGain = energy(reference.samples, start: 1.0, end: 1.2)
        #expect(abs(single / fullGain - 0.16) < 0.01, "A clip gain of 0.4 must preserve its energy scale")
        for (start, end) in [(0.02, 0.16), (0.65, 0.82), (1.45, 1.95)] {
            #expect(energy(decoded.samples, start: start, end: end) < 0.000_000_1,
                "Empty edited ranges must remain silent instead of collapsing the timeline")
        }
        #expect(try fixture.files() == ["tone.wav"])
        #expect(try stagingFiles(in: fixture.root).isEmpty)
    }

    @Test func delayedSlowAudioRangesKeepSilenceBetweenDifferentGainLanes() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createTone()
        var project = toneProject()
        let asset = try #require(project.timeline?.assets[0])
        project.timeline?.tracks.append(.init(id: "other"))
        project.timeline?.clips = [
            .init(trackID: "mixed", content: .audio(asset.id), start: 0.1, sourceStart: 0.123_456, sourceEnd: 0.543_21, speed: 0.5, volume: 0.3),
            .init(trackID: "other", content: .audio(asset.id), start: 1.22, sourceStart: 0.3, sourceEnd: 0.88, speed: 0.5, volume: 0.7),
        ]
        let output = fixture.root.appendingPathComponent("two-lanes.wav")
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory, to: output,
            configuration: .init(format: .wav))
        let samples = try await decode(output)
        #expect(energy(samples.samples, start: 0.944, end: 0.956) < 0.000_000_1)
        #expect(energy(samples.samples, start: 1.03, end: 1.17) < 0.000_000_1)
        #expect(energy(samples.samples, start: 0.4, end: 0.7) > 0.000_1)
        #expect(energy(samples.samples, start: 1.4, end: 1.8) > 0.000_1)
    }

    @Test(arguments: [0.1, 0.5, 1.0, 1.3, 2.0, 8.0])
    func resamplingKeepsFractionalCutsAndTimelineDuration(_ speed: Double) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createTone()
        var project = toneProject()
        project.timeline?.clips[0].start = 0.137
        project.timeline?.clips[0].sourceStart = 0.123_456
        project.timeline?.clips[0].sourceEnd = 0.987_654
        project.timeline?.clips[0].speed = speed
        let clip = try #require(project.timeline?.clips.first)
        let image = RecordingMediaAsset(name: "Image duration", file: "not-loaded.png", kind: .image,
            duration: 2, width: 64, height: 48)
        project.timeline?.assets.append(image)
        project.timeline?.tracks.append(.init(id: "visual"))
        project.timeline?.clips.append(.init(trackID: "visual", content: .image(image.id), start: 0, sourceEnd: clip.end + 0.137))
        let output = fixture.root.appendingPathComponent("resampled.wav")
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory, to: output,
            configuration: .init(format: .wav))
        let decoded = try await decode(output)
        #expect(abs(Double(decoded.samples.count) / 48_000 - project.outputDuration) <= 1 / 48_000)
        #expect(energy(decoded.samples, start: 0.01, end: 0.11) < 0.000_000_1)
        #expect(energy(decoded.samples, start: clip.start + clip.duration * 0.3,
            end: clip.start + clip.duration * 0.7) > 0.000_1)
        #expect(energy(decoded.samples, start: clip.end + 0.002, end: clip.end + 0.01) < 0.000_000_1)
        #expect(energy(decoded.samples, start: clip.end + 0.04, end: clip.end + 0.12) < 0.000_000_1)
        #expect(try stagingFiles(in: fixture.root).isEmpty)
    }

    @Test(arguments: [false, true])
    func absentOrDisabledAudioFailsWithoutReplacingAnExistingFile(_ disabled: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        if disabled {
            _ = try fixture.createTone()
            project.microphoneFile = "tone.wav"
            var timeline = RecordingMultitrackTimeline.migrating(project)
            timeline.tracks[0].isMuted = true
            project.timeline = timeline
        }
        let output = fixture.root.appendingPathComponent("existing.wav")
        let original = Data("existing audio".utf8)
        try original.write(to: output)
        let exporter = ScreenRecordingExporter()
        await #expect(throws: RecordingAudioOnlyExportError.noAudio) {
            try await exporter.export(project: project, directory: fixture.directory, to: output,
                configuration: .init(format: .wav))
        }
        #expect(try Data(contentsOf: output) == original)
        #expect(!exporter.isExporting && exporter.progress < 1)
        #expect(try stagingFiles(in: fixture.root).isEmpty)
    }

    @Test(arguments: ["empty", "corrupt", "unsafe", "missingEncoder"])
    func invalidMediaAndMissingEncoderPreserveTheExistingDestination(_ failure: String) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createTone()
        var project = toneProject()
        if failure == "empty" { project.timeline?.clips = [] }
        if failure == "corrupt" { try Data("invalid WAV".utf8).write(to: fixture.directory.appendingPathComponent("tone.wav")) }
        if failure == "unsafe" { project.timeline?.assets[0].file = "../outside.wav" }
        let output = fixture.root.appendingPathComponent("existing.wav")
        let original = Data([7, 8, 9])
        try original.write(to: output)
        let exporter = ScreenRecordingExporter(resolveFFmpeg: { throw ScreenRecordingExportError.missingFFmpeg })
        await #expect(throws: (any Error).self) {
            try await exporter.export(project: project, directory: fixture.directory, to: output,
                configuration: .init(format: failure == "missingEncoder" ? .mp3 : .wav))
        }
        #expect(try Data(contentsOf: output) == original)
        #expect(!exporter.isExporting && exporter.progress < 1)
        #expect(try stagingFiles(in: fixture.root).isEmpty)
    }

    @Test(arguments: [RecordingExportCheckpoint.beforeWrite, .audioSample(0), .beforeCommit])
    func injectedWriteFailuresDoNotReplaceOldAudioAndCleanStaging(_ checkpoint: RecordingExportCheckpoint) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createTone()
        let project = toneProject()
        let output = fixture.root.appendingPathComponent("existing.wav")
        let original = Data("old audio".utf8)
        try original.write(to: output)
        let exporter = ScreenRecordingExporter(checkpoint: {
            if $0 == checkpoint { throw CocoaError(.fileWriteOutOfSpace) }
        })
        await #expect(throws: CocoaError.self) {
            try await exporter.export(project: project, directory: fixture.directory, to: output,
                configuration: .init(format: .wav))
        }
        #expect(try Data(contentsOf: output) == original)
        #expect(!exporter.isExporting && exporter.progress < 1)
        #expect(try stagingFiles(in: fixture.root).isEmpty)
        try await ScreenRecordingExporter().export(project: project, directory: fixture.directory, to: output,
            configuration: .init(format: .wav))
        #expect(try Data(contentsOf: output).prefix(4) == Data("RIFF".utf8))
    }

    @Test(arguments: [false, true])
    func cancellingAnAudioSampleResetsExportStateAndPreservesTheTarget(_ cancelExporter: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createTone()
        let project = toneProject()
        let output = fixture.root.appendingPathComponent("existing.wav")
        let original = Data([1, 3, 5])
        try original.write(to: output)
        let gate = AudioExportGate()
        let exporter = ScreenRecordingExporter(checkpoint: { if $0 == .audioSample(0) { gate.pause() } })
        let task = Task {
            try await exporter.export(project: project, directory: fixture.directory, to: output,
                configuration: .init(format: .wav))
        }
        await gate.waitUntilPaused()
        #expect(exporter.isExporting)
        if cancelExporter { exporter.cancel() } else { task.cancel() }
        gate.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: output) == original)
        #expect(!exporter.isExporting && exporter.progress < 1)
        #expect(try stagingFiles(in: fixture.root).isEmpty)
    }

    @Test func aDestinationChangedToASymlinkBeforeCommitIsRejected() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createTone()
        let project = toneProject()
        let output = fixture.root.appendingPathComponent("destination.wav")
        let protected = fixture.root.appendingPathComponent("protected.wav")
        let original = Data([4, 3, 2])
        try original.write(to: protected)
        let exporter = ScreenRecordingExporter(checkpoint: {
            if $0 == .beforeCommit { try FileManager.default.createSymbolicLink(at: output, withDestinationURL: protected) }
        })
        await #expect(throws: ScreenRecordingExportError.invalidDestination) {
            try await exporter.export(project: project, directory: fixture.directory, to: output,
                configuration: .init(format: .wav))
        }
        #expect(try Data(contentsOf: protected) == original)
        #expect(try stagingFiles(in: fixture.root).isEmpty)
    }

    @Test(arguments: [RecordingExportFormat.mp3, .ogg, .opus], [false, true])
    func audioTranscodeFailureOrCancellationPreservesTheTarget(_ format: RecordingExportFormat, _ cancellation: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createTone()
        let project = toneProject()
        let script = fixture.root.appendingPathComponent("ffmpeg-failure")
        try Data("#!/bin/sh\nfor arg; do target=\"$arg\"; done\nprintf partial > \"$target\"\nexit 1\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let output = fixture.root.appendingPathComponent("existing." + format.fileExtension)
        let original = Data([1, 2, 3])
        try original.write(to: output)
        let exporter = ScreenRecordingExporter(resolveFFmpeg: { script }, checkpoint: {
            if cancellation && $0 == .beforeTranscode { throw CancellationError() }
        })
        do {
            try await exporter.export(project: project, directory: fixture.directory, to: output,
                configuration: .init(format: format))
            Issue.record("The injected audio encoder failure must fail the export")
        } catch {
            #expect(cancellation ? error is CancellationError : error as? ScreenRecordingExportError == .transcodingFailure)
        }
        #expect(try Data(contentsOf: output) == original)
        #expect(!exporter.isExporting && exporter.progress < 1)
        #expect(try stagingFiles(in: fixture.root).isEmpty)
    }

    fileprivate func toneProject() -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Tone fixture", videoFile: "", duration: 2, width: 64, height: 48)
        let asset = RecordingMediaAsset(name: "Tone", file: "tone.wav", kind: .audio, duration: 2)
        project.timeline = .init(assets: [asset], tracks: [.init(id: "mixed")], clips: [
            .init(trackID: "mixed", content: .audio(asset.id), start: 0, sourceEnd: 2),
        ])
        return project
    }

    private final class AudioExportGate: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var paused = false
        private var waiter: CheckedContinuation<Void, Never>?

        func pause() {
            let continuation = lock.withLock {
                paused = true
                defer { waiter = nil }
                return waiter
            }
            continuation?.resume()
            semaphore.wait()
        }

        func waitUntilPaused() async {
            await withCheckedContinuation { continuation in
                let complete = lock.withLock {
                    if paused { return true }
                    waiter = continuation
                    return false
                }
                if complete { continuation.resume() }
            }
        }

        func resume() { semaphore.signal() }
    }

    private struct Decoded {
        let samples: [Float]
        let rate: Double
        let channels: UInt32
    }

    private func decode(_ url: URL) async throws -> Decoded {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096))
        var samples: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: buffer)
            try #require(buffer.frameLength > 0)
            let channel = try #require(buffer.floatChannelData?[0])
            samples += UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        }
        return .init(samples: samples, rate: format.sampleRate, channels: format.channelCount)
    }

    fileprivate func energy(_ samples: [Float], start: Double, end: Double, rate: Double = 48_000) -> Double {
        let lower = min(samples.count, max(0, Int(start * rate)))
        let upper = min(samples.count, max(lower, Int(end * rate)))
        guard upper > lower else { return 0 }
        return samples[lower..<upper].reduce(0) { $0 + Double($1 * $1) } / Double(upper - lower)
    }

    private func stagingFiles(in root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".zisla-recording-export-") }
    }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(2)), .enabled(if: ProcessInfo.processInfo.environment["ZISLA_RUN_FFMPEG_EXPORT_TESTS"] == "1"))
struct ScreenRecordingAudioOnlyIntegrationTests {
    @Test(arguments: [RecordingExportFormat.mp3, .ogg, .opus])
    func externalAudioFormatsContainOnlyTheEditedAudioStream(_ format: RecordingExportFormat) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createTone()
        var project = ScreenRecordingAudioOnlyExportTests().toneProject()
        project.timeline?.clips[0].sourceStart = 0.3
        project.timeline?.clips[0].sourceEnd = 1.3
        project.timeline?.clips[0].speed = 2
        let output = fixture.root.appendingPathComponent("audio." + format.fileExtension)
        let executable = try ScreenRecordingFFmpegTranscoder.resolveExecutable()
        let probe = executable.deletingLastPathComponent().appendingPathComponent("ffprobe")
        try #require(YTDLPResolver.isTrustedExecutable(probe))
        let exporter = ScreenRecordingExporter()
        try await exporter.export(project: project, directory: fixture.directory, to: output,
            configuration: .init(format: format, frameRate: -99))
        let result = try await AIAgentProcessRunner.run(executableURL: probe,
            arguments: ["-v", "error", "-protocol_whitelist", "file", "-show_streams", "-show_format", "-of", "json", output.path],
            timeout: 15, maximumOutputBytes: 16_384, maximumErrorBytes: 4_096)
        #expect(result.status == 0 && !result.didTimeout)
        let json = try #require(JSONSerialization.jsonObject(with: result.standardOutput) as? [String: Any])
        let streams = try #require(json["streams"] as? [[String: Any]])
        #expect(streams.count == 1 && streams[0]["codec_type"] as? String == "audio")
        let codec = format == .ogg ? "vorbis" : format.rawValue
        #expect(streams[0]["codec_name"] as? String == codec)
        #expect(streams[0]["sample_rate"] as? String == "48000" && streams[0]["channels"] as? Int == 2)
        let container = try #require(json["format"] as? [String: Any])
        let durationString = try #require(container["duration"] as? String)
        let duration = try #require(Double(durationString))
        #expect(abs(duration - 0.5) < 0.06)
        let decoded = try await AIAgentProcessRunner.run(executableURL: executable,
            arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-i", output.path,
                        "-map", "0:a:0", "-f", "f32le", "-ac", "1", "-ar", "48000", "pipe:1"],
            timeout: 15, maximumOutputBytes: 48_000 * 4, maximumErrorBytes: 4_096)
        #expect(decoded.status == 0)
        let samples = decoded.standardOutput.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(abs(Double(samples.count) / 48_000 - 0.5) < 0.06)
        #expect(ScreenRecordingAudioOnlyExportTests().energy(samples, start: 0.1, end: 0.4) > 0.000_5)
        #expect(exporter.progress == 1 && !exporter.isExporting)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).allSatisfy { !$0.hasPrefix(".zisla-recording-export-") })
        #expect(try fixture.files() == ["tone.wav"])
    }
}
