import AVFoundation
import Foundation
import ZislaCore
import ZislaKit

enum ScreenRecordingExportError: LocalizedError, Equatable, Sendable {
    case emptyTimeline
    case invalidConfiguration
    case unavailableMedia
    case timelineOutsideMedia
    case invalidDestination
    case cannotRender
    case encoderFailure
    case exportInProgress

    var errorDescription: String? {
        switch self {
        case .emptyTimeline: AppLocalization.text("录屏时间线为空，无法导出")
        case .invalidConfiguration: AppLocalization.text("录屏导出配置无效")
        case .unavailableMedia: AppLocalization.text("录屏素材中缺少可用媒体轨道")
        case .timelineOutsideMedia: AppLocalization.text("剪辑片段超出录屏素材的时长")
        case .invalidDestination: AppLocalization.text("请将录屏导出到项目目录之外的普通文件")
        case .cannotRender: AppLocalization.text("无法分配或合成录屏画面")
        case .encoderFailure: AppLocalization.text("系统无法编码录屏文件")
        case .exportInProgress: AppLocalization.text("录屏正在导出，请等待或取消")
        }
    }
}

struct RecordingExportSlice: Equatable, Sendable {
    let index: Int
    let sourceStart: Double
    let sourceEnd: Double
    let speed: Double
    let outputStart: Double
    let outputEnd: Double

    func sourceTime(at outputTime: Double) -> Double {
        min(sourceEnd, max(sourceStart, sourceStart + (outputTime - outputStart) * speed))
    }
}

struct RecordingExportTimeline: Sendable {
    let slices: [RecordingExportSlice]
    let duration: Double

    init(project: ScreenRecordingProject) throws {
        try project.validate()
        guard !project.edits.segments.isEmpty else { throw ScreenRecordingExportError.emptyTimeline }
        var cursor = 0.0
        slices = project.edits.segments.enumerated().map { index, segment in
            let end = cursor + segment.outputDuration
            defer { cursor = end }
            return RecordingExportSlice(index: index, sourceStart: segment.start, sourceEnd: segment.end,
                                        speed: segment.speed, outputStart: cursor, outputEnd: end)
        }
        duration = cursor
    }

    func slice(at outputTime: Double) -> RecordingExportSlice? {
        // Treat floating-point addition noise at a cut as the exact media-clock boundary.
        let boundary = outputTime + outputTime.ulp * 4
        let index = recordingUpperBound(slices, value: boundary, key: \.outputEnd)
        return index < slices.count && boundary >= slices[index].outputStart ? slices[index] : nil
    }
}

struct RecordingExportFrameSchedule: Equatable, Sendable {
    let frameRate: Int
    let frameCount: Int

    init(duration: Double, configuration: RecordingExportConfiguration) throws {
        let limit = configuration.format == .gif ? 50 : 60
        guard (1...limit).contains(configuration.frameRate), duration.isFinite, duration > 0 else {
            throw ScreenRecordingExportError.invalidConfiguration
        }
        let count = duration * Double(configuration.frameRate)
        guard count < Double(Int.max) else { throw ScreenRecordingExportError.invalidConfiguration }
        // Snap representation noise at an integer boundary without losing a real partial frame.
        let integer = count.rounded()
        let stable = abs(count - integer) <= max(count.ulp, integer.ulp) * 4 ? integer : count
        frameRate = configuration.frameRate
        frameCount = Int(stable.rounded(.up))
    }

    func time(at index: Int) -> CMTime {
        CMTime(value: Int64(index), timescale: Int32(frameRate))
    }
}

func recordingUpperBound<Element>(_ elements: [Element], value: Double,
                                  key: KeyPath<Element, Double>) -> Int {
    var low = 0
    var high = elements.count
    while low < high {
        let middle = (low + high) / 2
        if elements[middle][keyPath: key] <= value { low = middle + 1 } else { high = middle }
    }
    return low
}

struct RecordingExportMediaTrack {
    let composition: AVMutableComposition
    let track: AVMutableCompositionTrack
    let transform: CGAffineTransform
    let availableRanges: [CMTimeRange?]
}

struct RecordingExportMedia {
    let video: RecordingExportMediaTrack
    let camera: RecordingExportMediaTrack?
    let audioComposition: AVMutableComposition?
    let audioTracks: [AVMutableCompositionTrack]
    let audioVolumes: [Float]
    let sourceSize: CGSize
    let timeline: RecordingExportTimeline

    func audioMix(for tracks: [AVCompositionTrack]) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.enumerated().map { index, track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(audioVolumes[index], at: .zero)
            if timeline.slices.contains(where: { $0.speed != 1 }) {
                parameters.audioTimePitchAlgorithm = .spectral
            }
            return parameters
        }
        return mix
    }

    static func prepare(project: ScreenRecordingProject, directory: URL,
                        timeline: RecordingExportTimeline) async throws -> RecordingExportMedia {
        let store = ScreenRecordingProjectStore(root: directory)
        let videoURL = try store.mediaURL(project.videoFile, in: directory)
        let asset = AVURLAsset(url: videoURL)
        var sourceAssets = [asset]
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw ScreenRecordingExportError.unavailableMedia
        }
        let naturalSize = try await sourceVideo.load(.naturalSize)
        let transform = try await sourceVideo.load(.preferredTransform)
        let sourceBounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let sourceRange = try await availableRange(of: sourceVideo)
        guard timeline.slices.allSatisfy({ $0.sourceStart < sourceRange.end.seconds
            && $0.sourceEnd <= sourceRange.end.seconds + 0.001 }) else {
            throw ScreenRecordingExportError.timelineOutsideMedia
        }
        let video = try makeTrack(source: sourceVideo, range: sourceRange, transform: transform,
                                  timeline: timeline, mediaType: .video)

        let camera: RecordingExportMediaTrack?
        if let cameraFile = project.cameraFile {
            let cameraAsset = AVURLAsset(url: try store.mediaURL(cameraFile, in: directory))
            sourceAssets.append(cameraAsset)
            guard let sourceCamera = try await cameraAsset.loadTracks(withMediaType: .video).first else {
                throw ScreenRecordingExportError.unavailableMedia
            }
            camera = try makeTrack(source: sourceCamera, range: try await availableRange(of: sourceCamera),
                                   transform: try await sourceCamera.load(.preferredTransform),
                                   timeline: timeline, mediaType: .video)
        } else { camera = nil }

        var audioSources = try await asset.loadTracks(withMediaType: .audio).prefix(1).map {
            (track: $0, volume: Float(project.edits.effectiveScreenAudioVolume))
        }
        if let microphoneFile = project.microphoneFile {
            let microphoneAsset = AVURLAsset(url: try store.mediaURL(microphoneFile, in: directory))
            sourceAssets.append(microphoneAsset)
            guard let sourceMicrophone = try await microphoneAsset.loadTracks(withMediaType: .audio).first else {
                throw ScreenRecordingExportError.unavailableMedia
            }
            audioSources.append((track: sourceMicrophone, volume: Float(project.edits.effectiveMicrophoneVolume)))
        }
        let audioComposition = audioSources.isEmpty ? nil : AVMutableComposition()
        var audioTracks: [AVMutableCompositionTrack] = []
        if let audioComposition {
            for source in audioSources {
                let part = try makeTrack(source: source.track, range: try await availableRange(of: source.track),
                                         transform: .identity, timeline: timeline, mediaType: .audio,
                                         composition: audioComposition)
                audioTracks.append(part.track)
            }
        }
        // AVAssetTrack holds its asset weakly; retain every source until composition insertion finishes.
        withExtendedLifetime(sourceAssets) {}
        return RecordingExportMedia(video: video, camera: camera, audioComposition: audioComposition,
                                    audioTracks: audioTracks, audioVolumes: audioSources.map { $0.volume },
                                    sourceSize: sourceBounds.size, timeline: timeline)
    }

    static func availableRange(of track: AVAssetTrack) async throws -> CMTimeRange {
        let segments = try await track.load(.segments).filter { !$0.isEmpty }
        guard let first = segments.first, let last = segments.last else {
            throw ScreenRecordingExportError.unavailableMedia
        }
        return CMTimeRange(start: first.timeMapping.target.start, end: last.timeMapping.target.end)
    }

    private static func makeTrack(source: AVAssetTrack, range: CMTimeRange, transform: CGAffineTransform,
                                  timeline: RecordingExportTimeline, mediaType: AVMediaType,
                                  composition: AVMutableComposition = AVMutableComposition()) throws
        -> RecordingExportMediaTrack {
        guard let track = composition.addMutableTrack(withMediaType: mediaType,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ScreenRecordingExportError.unavailableMedia
        }
        track.preferredTransform = transform
        var ranges: [CMTimeRange?] = []
        for slice in timeline.slices {
            let start = max(slice.sourceStart, range.start.seconds)
            let end = min(slice.sourceEnd, range.end.seconds)
            guard end > start else { ranges.append(nil); continue }
            let destinationStart = CMTime(seconds: slice.outputStart + (start - slice.sourceStart) / slice.speed,
                                          preferredTimescale: 60_000)
            let sourceDuration = CMTime(seconds: end - start, preferredTimescale: 60_000)
            let destinationDuration = CMTime(seconds: (end - start) / slice.speed, preferredTimescale: 60_000)
            try track.insertTimeRange(CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 60_000),
                                                 duration: sourceDuration), of: source, at: destinationStart)
            track.scaleTimeRange(CMTimeRange(start: destinationStart, duration: sourceDuration),
                                 toDuration: destinationDuration)
            ranges.append(CMTimeRange(start: destinationStart, duration: destinationDuration))
        }
        let total = CMTime(seconds: timeline.duration, preferredTimescale: 60_000)
        if track.timeRange.end < total {
            track.insertEmptyTimeRange(CMTimeRange(start: track.timeRange.end, end: total))
        }
        return RecordingExportMediaTrack(composition: composition, track: track,
                                         transform: transform, availableRanges: ranges)
    }
}
