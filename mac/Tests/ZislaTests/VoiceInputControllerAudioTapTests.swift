import AVFoundation
import Foundation
import Speech
import Testing

@testable import Zisla

struct VoiceInputControllerAudioTapTests {
    @Test
    func speechRecognizerFallbackUsesSystemLocale() throws {
        let source = try String(contentsOf: Self.controllerSourceURL, encoding: .utf8)

        #expect(source.contains("SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)"))
        #expect(!source.contains("Locale(identifier: \"zh-CN\")"))
    }

    @Test
    func macOS26UsesDictationTranscriberAndKeepsLegacyFallback() throws {
        let source = try String(contentsOf: Self.controllerSourceURL, encoding: .utf8)

        #expect(source.contains("if #available(macOS 26.0, *)"))
        #expect(source.contains("DictationTranscriber"))
        #expect(source.contains("SFSpeechAudioBufferRecognitionRequest"))
    }

    @Test
    func systemDictationUsesShortLivePresetAndNaturalInputFormat() throws {
        let source = try String(contentsOf: Self.controllerSourceURL, encoding: .utf8)

        #expect(source.contains("preset: .progressiveShortDictation"))
        #expect(source.contains("considering: sourceFormat"))
        #expect(source.contains("contextualStrings = strings.filter"))
        #expect(source.contains("request.contextualStrings = contextualStrings"))
        #expect(source.contains("context.contextualStrings[.general] = contextualStrings"))
        #expect(source.contains("format: nil"))
        #expect(!source.contains("strings != VoiceLexicon.terms(for: VoiceLexicon.defaultEnabled)"))
        #expect(!source.contains(".prefix("))
    }

    @Test
    func audioTapFormatRefreshDetectsInputDeviceChanges() throws {
        let preparedFormat = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 24_000,
            channels: 1
        ))
        let liveFormat = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 1
        ))
        let unchangedFormat = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 24_000,
            channels: 1
        ))

        #expect(VoiceInputController.audioTapFormatNeedsRefresh(
            preparedFormat: preparedFormat,
            liveFormat: liveFormat
        ))
        #expect(!VoiceInputController.audioTapFormatNeedsRefresh(
            preparedFormat: preparedFormat,
            liveFormat: unchangedFormat
        ))
    }

    @MainActor
    @Test
    func productionAudioTapHandlerRunsOutsideMainActor() async throws {
        let format = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 16_000,
            channels: 1
        ))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-voice-tap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("recording.caf", isDirectory: false)
        let recordingFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        let handler = VoiceInputController.makeAudioTapHandler(
            recordingFile: recordingFile,
            recordingID: UUID(),
            onBuffer: { _ in }
        ) { _, _ in
            Issue.record("Unexpected audio write failure")
        }

        await Task.detached {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
            buffer.frameLength = 1_024
            handler(buffer, AVAudioTime(hostTime: 0))
        }.value

        #expect(recordingFile.length == 1_024)
    }

    @MainActor
    @Test
    func productionAudioTapHandlerForwardsBufferAndWritesRecording() async throws {
        let format = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 16_000,
            channels: 1
        ))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-voice-tap-forward-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recordingFile = try AVAudioFile(
            forWriting: directory.appendingPathComponent("recording.caf"),
            settings: format.settings
        )
        let probe = AudioBufferProbe()
        let handler = VoiceInputController.makeAudioTapHandler(
            recordingFile: recordingFile,
            recordingID: UUID(),
            onBuffer: { probe.record($0) }
        ) { _, _ in
            Issue.record("Unexpected audio write failure")
        }

        await Task.detached {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
            buffer.frameLength = 1_024
            handler(buffer, AVAudioTime(hostTime: 0))
        }.value

        #expect(recordingFile.length == 1_024)
        #expect(probe.frameLength == 1_024)
    }

    private static var controllerSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/VoiceInputController.swift")
    }
}

private final class AudioBufferProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedFrameLength = 0

    var frameLength: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedFrameLength
    }

    func record(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        recordedFrameLength = Int(buffer.frameLength)
        lock.unlock()
    }
}
