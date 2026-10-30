import AVFoundation
import Foundation
import ZislaCore
import ZislaKit

enum ScreenRecordingFFmpegTranscoder {
    static func resolveExecutable(bundle: URL = Bundle.main.bundleURL,
                                  managedTools: URL = AppPaths.managedTools,
                                  candidates: [URL] = YTDLPResolver.defaultFFmpegCandidates) throws -> URL {
        let urls = [managedTools.appendingPathComponent("ffmpeg"),
                    bundle.appendingPathComponent("Contents/Helpers/ffmpeg")] + candidates
        guard let executable = urls.first(where: YTDLPResolver.isTrustedExecutable) else {
            throw ScreenRecordingExportError.missingFFmpeg
        }
        return executable.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func run(input: URL, output: URL, format: RecordingExportFormat, duration: Double,
                    executable: URL, inputFormat: String = "mov",
                    checkpoint: @escaping @Sendable (RecordingExportCheckpoint) throws -> Void,
                    progress: @escaping @Sendable (Double) async -> Void) async throws {
        let progressURL = output.deletingLastPathComponent().appendingPathComponent("ffmpeg-progress-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: progressURL) }
        let arguments = try arguments(input: input, output: output, format: format, progress: progressURL, inputFormat: inputFormat)
        try Task.checkCancellation()
        try checkpoint(.beforeTranscode)
        let worker = Task {
            try await AIAgentProcessRunner.run(executableURL: executable, arguments: arguments,
                standardInput: Data(), environment: ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") },
                workingDirectoryURL: output.deletingLastPathComponent(), timeout: nil,
                maximumOutputBytes: 1_024, maximumErrorBytes: 8_192)
        }
        let monitor = Task {
            var last = 0.0
            while !Task.isCancelled {
                if let handle = try? FileHandle(forReadingFrom: progressURL) {
                    defer { try? handle.close() }
                    let end = try handle.seekToEnd()
                    try handle.seek(toOffset: end > 8_192 ? end - 8_192 : 0)
                    if let data = try handle.read(upToCount: 8_192), let fraction = progressFraction(data, duration: duration), fraction > last {
                        last = fraction
                        await progress(fraction)
                    }
                }
                try await Task.sleep(for: .milliseconds(80))
            }
        }
        let result: AIAgentProcessOutput
        do {
            result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
        } catch {
            monitor.cancel()
            _ = try? await monitor.value
            throw error
        }
        monitor.cancel()
        _ = try? await monitor.value
        try Task.checkCancellation()
        guard result.status == 0 else { throw ScreenRecordingExportError.transcodingFailure }
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
            throw ScreenRecordingExportError.transcodingFailure
        }
        await progress(1)
    }

    static func arguments(input: URL, output: URL, format: RecordingExportFormat, progress: URL, inputFormat: String = "mov") throws -> [String] {
        let codec: [String]
        switch format {
        case .mkv: codec = ["-c:v", "copy", "-c:a", "copy", "-f", "matroska"]
        case .webm: codec = ["-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "5", "-crf", "30", "-b:v", "0",
                             "-c:a", "libopus", "-b:a", "192k", "-f", "webm"]
        case .avi: codec = ["-c:v", "mpeg4", "-q:v", "3", "-c:a", "libmp3lame", "-b:a", "192k", "-f", "avi"]
        case .wmv: codec = ["-c:v", "wmv2", "-b:v", "8M", "-c:a", "wmav2", "-b:a", "192k", "-f", "asf"]
        case .flv: codec = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-c:a", "aac", "-b:a", "192k", "-f", "flv"]
        case .mpeg: codec = ["-c:v", "mpeg2video", "-q:v", "3", "-c:a", "mp2", "-b:a", "192k", "-f", "mpeg"]
        case .ts: codec = ["-c:v", "copy", "-c:a", "copy", "-f", "mpegts"]
        case .threeGP: codec = ["-c:v", "mpeg4", "-q:v", "3", "-c:a", "aac", "-b:a", "128k", "-f", "3gp"]
        case .mp3: codec = ["-c:a", "libmp3lame", "-b:a", "192k", "-f", "mp3"]
        case .ogg: codec = ["-c:a", "vorbis", "-strict", "experimental", "-q:a", "5", "-f", "ogg"]
        case .opus: codec = ["-c:a", "libopus", "-b:a", "192k", "-f", "opus"]
        default: throw ScreenRecordingExportError.unsupportedFormat
        }
        let mapping = format.isAudioOnly ? ["-map", "0:a:0", "-vn"]
            : ["-map", "0:v:0", "-map", "0:a:0?", "-pix_fmt", "yuv420p"]
        return ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-protocol_whitelist", "file", "-f", inputFormat,
                "-i", input.path, "-threads", "2"] + mapping + codec + ["-progress", progress.path, "-nostats", output.path]
    }

    static func progressFraction(_ data: Data, duration: Double) -> Double? {
        let times = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line -> Double? in
            guard line.hasPrefix("out_time_us="), let time = Double(line.dropFirst(12)), time.isFinite else { return nil }
            return time / 1_000_000 / duration
        }
        return times.max().map { min(1, max(0, $0)) }
    }
}

extension RecordingExportFormat {
    var nativeVideoFileType: AVFileType {
        switch self {
        case .mov: .mov
        case .m4v: .m4v
        default: .mp4
        }
    }
}
