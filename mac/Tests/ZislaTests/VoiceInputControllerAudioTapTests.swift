import AVFoundation
import Foundation
import Speech
import Testing

@testable import Zisla

struct VoiceInputControllerAudioTapTests {
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
