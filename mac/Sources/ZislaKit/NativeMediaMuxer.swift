import AVFoundation
import Foundation
import ZislaCore

public protocol MediaMuxing: Sendable {
    func mux(videoURL: URL, audioURL: URL, outputURL: URL) async throws
}

public enum NativeMediaMuxerError: LocalizedError, Equatable, Sendable {
    case missingVideoTrack
    case missingAudioTrack
    case cannotCreateCompositionTrack
    case unsupportedMP4Output
    case outputAlreadyExists
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return "下载组件中缺少可用视频轨"
        case .missingAudioTrack:
            return "下载组件中缺少可用音频轨"
        case .cannotCreateCompositionTrack:
            return "系统无法创建媒体封装轨道"
        case .unsupportedMP4Output:
            return "当前媒体编码无法原样封装为 MP4"
        case .outputAlreadyExists:
            return "目标文件已存在，未执行覆盖"
        case let .exportFailed(message):
            return "系统媒体封装失败：\(message)"
        }
    }
}

public struct NativeMediaMuxer: MediaMuxing, Sendable {
    public init() {}

    public func mux(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NativeMediaMuxerError.outputAlreadyExists
        }

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack
        do {
            guard let track = try await videoAsset.loadTracks(withMediaType: .video).first else {
                throw NativeMediaMuxerError.missingVideoTrack
            }
            videoTrack = track
        } catch let error as NativeMediaMuxerError {
            throw error
        } catch {
            throw NativeMediaMuxerError.missingVideoTrack
        }
        do {
            guard let track = try await audioAsset.loadTracks(withMediaType: .audio).first else {
                throw NativeMediaMuxerError.missingAudioTrack
            }
            audioTrack = track
        } catch let error as NativeMediaMuxerError {
            throw error
        } catch {
            throw NativeMediaMuxerError.missingAudioTrack
        }

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let composition = AVMutableComposition()
        guard
            let compositionVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let compositionAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw NativeMediaMuxerError.cannotCreateCompositionTrack
        }

        try compositionVideo.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoTrack,
            at: .zero
        )
        try compositionAudio.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTimeMinimum(audioDuration, videoDuration)),
            of: audioTrack,
            at: .zero
        )
        if let transform = try? await videoTrack.load(.preferredTransform) {
            compositionVideo.preferredTransform = transform
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ), exporter.supportedFileTypes.contains(.mp4) else {
            throw NativeMediaMuxerError.unsupportedMP4Output
        }
        exporter.shouldOptimizeForNetworkUse = true
        let box = ExportSessionBox(exporter)

        do {
            try await withTaskCancellationHandler {
                try await box.export(to: outputURL)
            } onCancel: {
                box.cancel()
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw NativeMediaMuxerError.exportFailed(error.localizedDescription)
        }
    }

}

private final class ExportSessionBox: @unchecked Sendable {
    private let exporter: AVAssetExportSession

    init(_ exporter: AVAssetExportSession) {
        self.exporter = exporter
    }

    func export(to outputURL: URL) async throws {
        if #available(macOS 15, *) {
            try await exporter.export(to: outputURL, as: .mp4)
        } else {
            try await legacyExport(to: outputURL)
        }
    }

    @available(macOS, introduced: 14, obsoleted: 15)
    private func legacyExport(to outputURL: URL) async throws {
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously { [self] in
                switch status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(
                        throwing: error
                            ?? NativeMediaMuxerError.exportFailed(AppLocalization.text("AVFoundation 导出失败"))
                    )
                }
            }
        }
    }

    private var status: AVAssetExportSession.Status {
        exporter.status
    }

    private var error: Error? {
        exporter.error
    }

    func cancel() {
        exporter.cancelExport()
    }
}
