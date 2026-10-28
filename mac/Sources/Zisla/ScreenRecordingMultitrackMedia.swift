import AVFoundation
import CoreImage
import Foundation
import ZislaCore
import ZislaKit

struct RecordingMultitrackVideoLayer {
    let key: String
    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let range: CMTimeRange
}

final class RecordingMultitrackMedia {
    let composition: AVMutableComposition
    let layers: [String: RecordingMultitrackVideoLayer]
    let videoTracks: [AVMutableCompositionTrack]
    let audioTracks: [AVMutableCompositionTrack]
    let audioMix: AVAudioMix
    let duration: Double
    let adjustsSpeed: Bool
    private(set) var playbackClockTrackID: CMPersistentTrackID?
    private var carrier: URL?

    private init(composition: AVMutableComposition, layers: [String: RecordingMultitrackVideoLayer],
                 videoTracks: [AVMutableCompositionTrack], audioTracks: [AVMutableCompositionTrack],
                 audioMix: AVAudioMix, duration: Double, adjustsSpeed: Bool) {
        self.composition = composition
        self.layers = layers
        self.videoTracks = videoTracks
        self.audioTracks = audioTracks
        self.audioMix = audioMix
        self.duration = duration
        self.adjustsSpeed = adjustsSpeed
    }

    deinit { if let carrier { try? FileManager.default.removeItem(at: carrier) } }

    static func prepare(project: ScreenRecordingProject, directory: URL) async throws -> RecordingMultitrackMedia {
        try project.validate()
        guard let timeline = project.timeline, timeline.duration > 0 else { throw ScreenRecordingExportError.emptyTimeline }
        let store = ScreenRecordingProjectStore(root: directory)
        let assets = Dictionary(uniqueKeysWithValues: timeline.assets.map { ($0.id, $0) })
        let tracks = Dictionary(uniqueKeysWithValues: timeline.tracks.map { ($0.id, $0) })
        let composition = AVMutableComposition()
        var retained: [String: AVURLAsset] = [:]
        var videoSources: [String: AVAssetTrack] = [:]
        var audioSources: [String: AVAssetTrack] = [:]
        var silent: Set<String> = []
        var ranges: [String: CMTimeRange] = [:]
        var transforms: [String: CGAffineTransform] = [:]
        var videoEntries: [(clip: RecordingTimelineClip, key: String, source: AVAssetTrack, range: CMTimeRange, transform: CGAffineTransform)] = []
        var audioEntries: [(clip: RecordingTimelineClip, source: AVAssetTrack, range: CMTimeRange, volume: Float)] = []

        func asset(_ file: String) throws -> AVURLAsset {
            if let source = retained[file] { return source }
            let source = AVURLAsset(url: try store.mediaURL(file, in: directory))
            retained[file] = source
            return source
        }
        func video(_ file: String) async throws -> (AVAssetTrack, CMTimeRange, CGAffineTransform) {
            if let track = videoSources[file] { return (track, ranges["v" + file]!, transforms[file]!) }
            guard let track = try await asset(file).loadTracks(withMediaType: .video).first else {
                throw ScreenRecordingExportError.unavailableMedia
            }
            let range = try await RecordingExportMedia.availableRange(of: track)
            let transform = try await track.load(.preferredTransform)
            videoSources[file] = track
            ranges["v" + file] = range
            transforms[file] = transform
            return (track, range, transform)
        }
        func appendAudio(_ file: String, clip: RecordingTimelineClip, volume: Double) async throws {
            if silent.contains(file) { return }
            let track: AVAssetTrack
            let range: CMTimeRange
            if let cached = audioSources[file] { track = cached; range = ranges["a" + file]! }
            else {
                guard let loaded = try await asset(file).loadTracks(withMediaType: .audio).first else {
                    silent.insert(file)
                    return
                }
                track = loaded
                range = try await RecordingExportMedia.availableRange(of: loaded)
                audioSources[file] = loaded
                ranges["a" + file] = range
            }
            if max(clip.sourceStart, range.start.seconds) < min(clip.sourceEnd, range.end.seconds) {
                audioEntries.append((clip, track, range, Float(volume)))
            }
        }
        for clip in timeline.clips {
            try Task.checkCancellation()
            guard let track = tracks[clip.trackID] else { throw ScreenRecordingProjectError.invalidProject }
            switch clip.content {
            case let .recording(id), let .video(id):
                let file = assets[id]!.file
                if !track.isHidden {
                    let (source, range, transform) = try await video(file)
                    guard clip.sourceStart < range.end.seconds, clip.sourceEnd <= range.end.seconds + 0.001 else {
                        throw ScreenRecordingExportError.timelineOutsideMedia
                    }
                    videoEntries.append((clip, clip.id, source, range, transform))
                    if case .recording = clip.content, project.edits.effectiveShowCamera, let cameraFile = project.cameraFile {
                        let (camera, cameraRange, cameraTransform) = try await video(cameraFile)
                        if max(clip.sourceStart, cameraRange.start.seconds) < min(clip.sourceEnd, cameraRange.end.seconds) {
                            videoEntries.append((clip, clip.id + ".camera", camera, cameraRange, cameraTransform))
                        }
                    }
                }
                if clip.audioEnabled && !track.isMuted {
                    let recording: Bool
                    if case .recording = clip.content { recording = true } else { recording = false }
                    try await appendAudio(file, clip: clip,
                        volume: clip.volume * (recording ? project.edits.effectiveScreenAudioVolume : 1))
                    if recording, let microphone = project.microphoneFile {
                        try await appendAudio(microphone, clip: clip, volume: clip.volume * project.edits.effectiveMicrophoneVolume)
                    }
                }
            case let .audio(id):
                if clip.audioEnabled && !track.isMuted { try await appendAudio(assets[id]!.file, clip: clip, volume: clip.volume) }
            case .image, .annotation, .caption: break
            }
        }
        var videoLanes: [AVMutableCompositionTrack] = []
        var layers: [String: RecordingMultitrackVideoLayer] = [:]
        for entry in videoEntries.sorted(by: { $0.clip.start < $1.clip.start }) {
            let start = max(entry.clip.sourceStart, entry.range.start.seconds)
            let destination = entry.clip.start + (start - entry.clip.sourceStart) / entry.clip.speed
            let lane = try lane(at: destination, mediaType: .video, composition: composition, lanes: &videoLanes)
            let range = try insert(entry.clip, source: entry.source, range: entry.range, into: lane)
            layers[entry.key] = .init(key: entry.key, trackID: lane.trackID, transform: entry.transform, range: range)
        }
        var audioLanes: [AVMutableCompositionTrack] = []
        var audioVolumes: [CMPersistentTrackID: Float] = [:]
        var parameters: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]
        for entry in audioEntries.sorted(by: { $0.clip.start < $1.clip.start }) {
            let start = max(entry.clip.sourceStart, entry.range.start.seconds)
            let destination = entry.clip.start + (start - entry.clip.sourceStart) / entry.clip.speed
            let lane = try lane(at: destination, mediaType: .audio, composition: composition, lanes: &audioLanes,
                accepts: { audioVolumes[$0.trackID] == entry.volume })
            _ = try insert(entry.clip, source: entry.source, range: entry.range, into: lane)
            audioVolumes[lane.trackID] = entry.volume
            let parameter = parameters[lane.trackID] ?? AVMutableAudioMixInputParameters(track: lane)
            parameter.setVolume(entry.volume, at: .zero)
            if entry.clip.speed != 1 { parameter.audioTimePitchAlgorithm = .spectral }
            parameters[lane.trackID] = parameter
        }
        let end = CMTime(seconds: timeline.duration, preferredTimescale: 60_000)
        for track in videoLanes + audioLanes where track.timeRange.end < end {
            track.insertEmptyTimeRange(CMTimeRange(start: track.timeRange.end, end: end))
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = audioLanes.map { parameters[$0.trackID]! }
        withExtendedLifetime(retained) {}
        return .init(composition: composition, layers: layers, videoTracks: videoLanes, audioTracks: audioLanes,
            audioMix: mix, duration: timeline.duration, adjustsSpeed: timeline.clips.contains { $0.speed != 1 })
    }

    private static func lane(at start: Double, mediaType: AVMediaType, composition: AVMutableComposition,
                             lanes: inout [AVMutableCompositionTrack],
                             accepts: (AVMutableCompositionTrack) -> Bool = { _ in true }) throws -> AVMutableCompositionTrack {
        if let lane = lanes.first(where: { $0.timeRange.end.seconds <= start + 0.000_001 && accepts($0) }) { return lane }
        guard let lane = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ScreenRecordingExportError.unavailableMedia
        }
        lanes.append(lane)
        return lane
    }

    private static func insert(_ clip: RecordingTimelineClip, source: AVAssetTrack, range: CMTimeRange,
                               into track: AVMutableCompositionTrack) throws -> CMTimeRange {
        let start = max(clip.sourceStart, range.start.seconds)
        let end = min(clip.sourceEnd, range.end.seconds)
        let destination = CMTime(seconds: clip.start + (start - clip.sourceStart) / clip.speed, preferredTimescale: 60_000)
        let duration = CMTime(seconds: end - start, preferredTimescale: 60_000)
        let outputDuration = CMTime(seconds: (end - start) / clip.speed, preferredTimescale: 60_000)
        try track.insertTimeRange(CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 60_000), duration: duration),
            of: source, at: destination)
        track.scaleTimeRange(CMTimeRange(start: destination, duration: duration), toDuration: outputDuration)
        return CMTimeRange(start: destination, duration: outputDuration)
    }

    func addPlaybackClock() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-playback-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        carrier = folder
        let url = folder.appendingPathComponent("clock.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw ScreenRecordingExportError.encoderFailure }
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)
        while !input.isReadyForMoreMediaData { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(2)) }
        guard let pool = adaptor.pixelBufferPool else { throw ScreenRecordingExportError.cannotRender }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
            throw ScreenRecordingExportError.cannotRender
        }
        CIContext().render(CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16)), to: buffer)
        guard adaptor.append(buffer, withPresentationTime: .zero) else { throw ScreenRecordingExportError.encoderFailure }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 30))
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw ScreenRecordingExportError.encoderFailure }
        let asset = AVURLAsset(url: url)
        guard let source = try await asset.loadTracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ScreenRecordingExportError.unavailableMedia
        }
        let range = try await source.load(.timeRange)
        try track.insertTimeRange(range, of: source, at: .zero)
        track.scaleTimeRange(range, toDuration: CMTime(seconds: duration, preferredTimescale: 60_000))
        playbackClockTrackID = track.trackID
        withExtendedLifetime(asset) {}
    }
}

extension ScreenRecordingExporter {
    func multitrackPlaybackItem(project: ScreenRecordingProject, directory: URL) async throws -> AVPlayerItem {
        let media = try await RecordingMultitrackMedia.prepare(project: project, directory: directory)
        try await media.addPlaybackClock()
        try Task.checkCancellation()
        let original = try RecordingExportRenderer.outputSize(source: CGSize(width: project.width, height: project.height),
            edits: project.edits, resolution: .source)
        let scale = min(1, 1_280 / max(original.width, original.height))
        let size = CGSize(width: max(2, floor(original.width * scale / 2) * 2),
            height: max(2, floor(original.height * scale / 2) * 2))
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = RecordingMultitrackPlaybackCompositor.self
        composition.renderSize = size
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.instructions = [try RecordingMultitrackPlaybackInstruction(project: project, directory: directory,
            media: media, size: size)]
        let item = AVPlayerItem(asset: media.composition)
        item.videoComposition = composition
        if !media.audioTracks.isEmpty { item.audioMix = media.audioMix }
        item.audioTimePitchAlgorithm = .spectral
        return item
    }

    func multitrackPreview(project: ScreenRecordingProject, directory: URL, time: Double,
                           maximumSize: CGSize = .init(width: 1_200, height: 800)) async throws -> RecordingMultitrackPreviewScene {
        try project.validate()
        guard let timeline = project.timeline, time.isFinite, time >= 0, time <= timeline.duration,
              maximumSize.width >= 2, maximumSize.height >= 2 else { throw ScreenRecordingExportError.invalidConfiguration }
        let worker = Task.detached(priority: .userInitiated) {
            let original = try RecordingExportRenderer.outputSize(source: .init(width: project.width, height: project.height),
                edits: project.edits, resolution: .source)
            let scale = min(1, min(maximumSize.width / original.width, maximumSize.height / original.height))
            let size = CGSize(width: max(2, floor(original.width * scale / 2) * 2),
                height: max(2, floor(original.height * scale / 2) * 2))
            let visibleTime = timeline.duration > 0 ? min(time, max(0, timeline.duration - 1.0 / 60_000)) : 0
            let assets = Dictionary(uniqueKeysWithValues: timeline.assets.map { ($0.id, $0) })
            let store = ScreenRecordingProjectStore(root: directory)
            var generators: [String: AVAssetImageGenerator] = [:]
            var availableRanges: [String: CMTimeRange] = [:]
            var frames: [String: CGImage] = [:]
            func frame(_ file: String, at sourceTime: Double, optional: Bool) async throws -> CGImage? {
                let generator: AVAssetImageGenerator
                if let cached = generators[file] { generator = cached }
                else {
                    let asset = AVURLAsset(url: try store.mediaURL(file, in: directory))
                    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                        throw ScreenRecordingExportError.unavailableMedia
                    }
                    let range = try await RecordingExportMedia.availableRange(of: track)
                    availableRanges[file] = range
                    generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = maximumSize
                    generator.requestedTimeToleranceBefore = .zero
                    generator.requestedTimeToleranceAfter = .zero
                    generators[file] = generator
                }
                let range = availableRanges[file]!
                if optional && (sourceTime < range.start.seconds || sourceTime >= range.end.seconds) { return nil }
                guard sourceTime < range.end.seconds else { throw ScreenRecordingExportError.timelineOutsideMedia }
                return try await generator.image(at: CMTime(seconds: max(sourceTime, range.start.seconds), preferredTimescale: 60_000)).image
            }
            for clip in timeline.visibleClips(at: visibleTime) {
                try Task.checkCancellation()
                switch clip.content {
                case let .recording(id), let .video(id):
                    frames[clip.id] = try await frame(assets[id]!.file, at: clip.sourceTime(at: visibleTime), optional: false)
                    if case .recording = clip.content, project.edits.effectiveShowCamera, let camera = project.cameraFile {
                        frames[clip.id + ".camera"] = try await frame(camera, at: clip.sourceTime(at: visibleTime), optional: true)
                    }
                case .image, .audio, .annotation, .caption: break
                }
            }
            try Task.checkCancellation()
            return RecordingMultitrackPreviewScene(project: project, directory: directory, time: time, size: size, frames: frames)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
