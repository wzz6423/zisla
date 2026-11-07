import AVFoundation
import Foundation
import ZislaCore

actor RecordingVoiceMedia {
    private struct Key: Hashable {
        let url: URL
        let preset: RecordingVoicePreset
        let amount: Double
    }

    private var directory: URL?
    private var assets: [Key: AVURLAsset] = [:]

    deinit { if let directory { try? FileManager.default.removeItem(at: directory) } }

    func asset(from source: AVURLAsset, effects: RecordingVoiceEffects) async throws -> AVURLAsset {
        guard effects.isValid else { throw ScreenRecordingExportError.invalidConfiguration }
        guard effects.isEnabled else { return source }
        let key = Key(url: source.url, preset: effects.preset, amount: effects.amount)
        if let cached = assets[key] { return cached }
        try Task.checkCancellation()
        guard let track = try await source.loadTracks(withMediaType: .audio).first else {
            throw ScreenRecordingExportError.unavailableMedia
        }
        let range = try await RecordingExportMedia.availableRange(of: track)
        if directory == nil {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-voice-media-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            directory = folder
        }
        let url = directory!.appendingPathComponent("\(UUID()).mov")
        let reader = try AVAssetReader(asset: source)
        reader.timeRange = range
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw ScreenRecordingExportError.unavailableMedia }
        reader.add(output)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var completed = false
        defer {
            reader.cancelReading()
            if !completed {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
            }
            withExtendedLifetime(source) {}
        }
        guard reader.startReading(), let first = output.copyNextSampleBuffer(),
              let description = first.formatDescription else {
            throw reader.error ?? ScreenRecordingExportError.unavailableMedia
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: description)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw ScreenRecordingExportError.encoderFailure }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ScreenRecordingExportError.encoderFailure }
        writer.startSession(atSourceTime: .zero)
        let processor = RecordingVoiceProcessor()
        var sample: CMSampleBuffer? = first
        while let current = sample {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? ScreenRecordingExportError.encoderFailure }
                try await Task.sleep(for: .milliseconds(2))
            }
            let processed = try processor.process(current, effects: effects)
            guard input.append(processed) else { throw writer.error ?? ScreenRecordingExportError.encoderFailure }
            sample = output.copyNextSampleBuffer()
        }
        guard reader.status == .completed else { throw reader.error ?? ScreenRecordingExportError.unavailableMedia }
        input.markAsFinished()
        writer.endSession(atSourceTime: range.end)
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw writer.error ?? ScreenRecordingExportError.encoderFailure }
        let asset = AVURLAsset(url: url)
        assets[key] = asset
        completed = true
        return asset
    }
}
