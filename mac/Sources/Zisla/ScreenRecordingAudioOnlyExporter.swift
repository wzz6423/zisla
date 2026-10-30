import AVFoundation
import Darwin
import Foundation
import ZislaCore

enum RecordingAudioOnlyExportError: LocalizedError, Equatable, Sendable {
    case noAudio
    var errorDescription: String? { AppLocalization.text("录屏时间线中没有可导出的音频") }
}

enum ScreenRecordingAudioOnlyExporter {
    static func run(project: ScreenRecordingProject, directory: URL, destination: URL,
                    configuration: RecordingExportConfiguration,
                    checkpoint: @escaping @Sendable (RecordingExportCheckpoint) throws -> Void,
                    resolveFFmpeg: @escaping @Sendable () throws -> URL,
                    progress: @escaping @Sendable (Double) async -> Void) async throws {
        try Task.checkCancellation()
        try project.validate()
        guard configuration.format.isAudioOnly else { throw ScreenRecordingExportError.invalidConfiguration }
        guard project.outputDuration > 0 else { throw ScreenRecordingExportError.emptyTimeline }
        let target = try RecordingExportJob.validateDestination(destination, directory: directory)
        try checkpoint(.beforeRead)
        var audioProject = project
        audioProject.timeline = .migrating(project)
        audioProject.version = ScreenRecordingProject.currentVersion
        let media = try await RecordingMultitrackMedia.prepare(project: audioProject, directory: directory, includeVideo: false)
        guard !media.audioTracks.isEmpty else { throw RecordingAudioOnlyExportError.noAudio }
        let executable = configuration.format.requiresFFmpeg ? try resolveFFmpeg() : nil
        let staging = target.deletingLastPathComponent().appendingPathComponent(".zisla-recording-export-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let temporary = staging.appendingPathComponent("output." + configuration.format.fileExtension)
        let rendered = executable == nil ? temporary : staging.appendingPathComponent("mixed.wav")
        try checkpoint(.beforeWrite)
        try Task.checkCancellation()
        try await write(media: media, to: rendered, format: executable == nil ? configuration.format : .wav,
            checkpoint: checkpoint) { await progress($0 * (executable == nil ? 0.98 : 0.7)) }
        if let executable {
            try await ScreenRecordingFFmpegTranscoder.run(input: rendered, output: temporary,
                format: configuration.format, duration: media.duration, executable: executable,
                inputFormat: "wav", checkpoint: checkpoint) { await progress(0.7 + $0 * 0.28) }
        }
        try checkpoint(.beforeCommit)
        try Task.checkCancellation()
        _ = try RecordingExportJob.validateDestination(target, directory: directory)
        guard Darwin.rename(temporary.path, target.path) == 0 else { throw ScreenRecordingExportError.invalidDestination }
        await progress(1)
    }

    private static func write(media: RecordingMultitrackMedia, to url: URL, format: RecordingExportFormat,
                              checkpoint: @escaping @Sendable (RecordingExportCheckpoint) throws -> Void,
                              progress: @escaping @Sendable (Double) async -> Void) async throws {
        let reader = try AVAssetReader(asset: media.composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: media.audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = media.audioMix
        if media.adjustsSpeed { output.audioTimePitchAlgorithm = .spectral }
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ScreenRecordingExportError.unavailableMedia }
        reader.add(output)
        reader.timeRange = .init(start: .zero, duration: CMTime(seconds: media.duration, preferredTimescale: 60_000))
        let file = try AVAudioFile(forWriting: url, settings: settings(format: format), commonFormat: .pcmFormatFloat32, interleaved: true)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096) else {
            throw ScreenRecordingExportError.cannotRender
        }
        guard reader.startReading() else { throw ScreenRecordingExportError.unavailableMedia }
        defer { reader.cancelReading() }
        let total = Int64((media.duration * 48_000).rounded())
        var audibleRanges: [Range<Int64>] = []
        for track in media.audioTracks {
            for segment in track.segments where !segment.isEmpty {
                let range = segment.timeMapping.target
                let start = Int64((range.start.seconds * 48_000).rounded())
                let end = Int64((range.end.seconds * 48_000).rounded())
                audibleRanges.append(start..<end)
            }
        }
        audibleRanges.sort { $0.lowerBound < $1.lowerBound }
        var rangeIndex = 0
        var position: Int64 = 0
        func silence(until end: Int64) throws {
            while position < end {
                try Task.checkCancellation()
                buffer.frameLength = AVAudioFrameCount(min(4_096, end - position))
                let audio = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                for channel in audio { memset(channel.mData!, 0, Int(channel.mDataByteSize)) }
                try file.write(from: buffer)
                position += Int64(buffer.frameLength)
            }
        }
        var index = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            try checkpoint(.audioSample(index))
            let start = Int64((sample.presentationTimeStamp.seconds * 48_000).rounded())
            try silence(until: min(total, start))
            var offset = max(0, Int(position - start))
            while offset < sample.numSamples && position < total {
                try Task.checkCancellation()
                let count = min(4_096, min(sample.numSamples - offset, Int(total - position)))
                buffer.frameLength = AVAudioFrameCount(count)
                guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: Int32(offset), frameCount: Int32(count),
                    into: buffer.mutableAudioBufferList) == noErr else { throw ScreenRecordingExportError.unavailableMedia }
                // Spectral time stretching can emit a delayed tail into empty composition ranges.
                var frame = 0
                while frame < count {
                    let time = position + Int64(frame)
                    while rangeIndex < audibleRanges.count && audibleRanges[rangeIndex].upperBound <= time { rangeIndex += 1 }
                    if rangeIndex < audibleRanges.count && audibleRanges[rangeIndex].contains(time) {
                        frame += min(count - frame, Int(audibleRanges[rangeIndex].upperBound - time))
                    } else {
                        let next = rangeIndex < audibleRanges.count ? audibleRanges[rangeIndex].lowerBound : total
                        let frames = min(count - frame, Int(next - time))
                        for channel in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
                            let stride = Int(channel.mNumberChannels) * MemoryLayout<Float>.size
                            memset(channel.mData!.advanced(by: frame * stride), 0, frames * stride)
                        }
                        frame += frames
                    }
                }
                try file.write(from: buffer)
                offset += count
                position += Int64(count)
            }
            await progress(Double(position) / Double(total))
            index += 1
        }
        guard reader.status == .completed else { throw ScreenRecordingExportError.unavailableMedia }
        // Empty time ranges can be omitted by AVAssetReader; keep the edited timeline's full duration.
        try silence(until: total)
        await progress(1)
    }

    private static func settings(format: RecordingExportFormat) -> [String: Any] {
        let identifier: AudioFormatID = format == .flac ? kAudioFormatFLAC
            : format == .m4a || format == .aac ? kAudioFormatMPEG4AAC : kAudioFormatLinearPCM
        var result: [String: Any] = [AVFormatIDKey: identifier, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2]
        if identifier == kAudioFormatMPEG4AAC { result[AVEncoderBitRateKey] = 192_000 }
        if identifier == kAudioFormatFLAC { result[AVLinearPCMBitDepthKey] = 16 }
        if identifier == kAudioFormatLinearPCM {
            result[AVLinearPCMBitDepthKey] = 16
            result[AVLinearPCMIsFloatKey] = false
            result[AVLinearPCMIsBigEndianKey] = format == .aiff
            result[AVLinearPCMIsNonInterleaved] = false
        }
        return result
    }
}
