import AVFoundation
import Foundation
import Speech
import Testing

@testable import Zisla

struct VoiceInputControllerAudioTapTests {
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
            request: SFSpeechAudioBufferRecognitionRequest(),
            recordingFile: recordingFile,
            recordingID: UUID()
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
}
