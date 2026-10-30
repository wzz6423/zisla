import AVFoundation
import Foundation
import ZislaCore
import ZislaKit

enum ScreenRecordingAudioDetachment {
    typealias AudioProbe = @Sendable (URL) async throws -> [Range<Double>]

    static func prepare(project: ScreenRecordingProject, directory: URL, clipID: String,
                        probe: AudioProbe = audioRanges) async throws -> ScreenRecordingProject? {
        try Task.checkCancellation()
        try project.validate()
        var timeline = RecordingMultitrackTimeline.migrating(project)
        guard let clipIndex = timeline.clips.firstIndex(where: { $0.id == clipID }),
              timeline.clips[clipIndex].audioEnabled else { return nil }
        let clip = timeline.clips[clipIndex]
        let assetID: UUID
        let isRecording: Bool
        switch clip.content {
        case let .recording(id): assetID = id; isRecording = true
        case let .video(id): assetID = id; isRecording = false
        default: return nil
        }
        let assetIndex = timeline.assets.firstIndex(where: { $0.id == assetID })!
        let asset = timeline.assets[assetIndex]
        let sourceTrack = timeline.tracks.first(where: { $0.id == clip.trackID })!
        let store = ScreenRecordingProjectStore(root: directory)
        let videoRanges = try await probe(store.mediaURL(asset.file, in: directory))
        try Task.checkCancellation()
        var sources = [(asset: asset, ranges: videoRanges,
            volume: clip.volume * (isRecording ? project.edits.effectiveScreenAudioVolume : 1))]
        if isRecording, let microphoneFile = project.microphoneFile {
            let ranges = try await probe(store.mediaURL(microphoneFile, in: directory))
            try Task.checkCancellation()
            if let end = ranges.map(\.upperBound).max() {
                let microphone = timeline.assets.first(where: { $0.file == microphoneFile && $0.kind == .audio })
                    ?? RecordingMediaAsset(name: AppLocalization.text("麦克风"), file: microphoneFile,
                        kind: .audio, duration: end, hasAudio: true)
                sources.append((microphone, ranges, clip.volume * project.edits.effectiveMicrophoneVolume))
            }
        }

        var detached = false
        for source in sources {
            let ranges = source.ranges.filter { $0.upperBound > clip.sourceStart && $0.lowerBound < clip.sourceEnd }
            guard let first = ranges.map(\.lowerBound).min(), let last = ranges.map(\.upperBound).max() else { continue }
            let start = max(clip.sourceStart, first)
            let end = min(clip.sourceEnd, last)
            var media = source.asset
            media.hasAudio = true
            if let index = timeline.assets.firstIndex(where: { $0.id == media.id }) { timeline.assets[index] = media }
            else { timeline.assets.append(media) }
            let track = RecordingTimelineTrack(isMuted: sourceTrack.isMuted)
            timeline.tracks.append(track)
            timeline.clips.append(.init(trackID: track.id, content: .audio(media.id),
                start: clip.start + (start - clip.sourceStart) / clip.speed,
                sourceStart: start, sourceEnd: end, speed: clip.speed, volume: source.volume))
            detached = true
        }
        guard detached else { return nil }
        timeline.clips[clipIndex].audioEnabled = false
        var replacement = project
        replacement.version = ScreenRecordingProject.currentVersion
        replacement.timeline = timeline
        try replacement.validate()
        return replacement
    }

    static func audioRanges(at url: URL) async throws -> [Range<Double>] {
        let asset = AVURLAsset(url: url)
        defer { withExtendedLifetime(asset) {} }
        var ranges: [Range<Double>] = []
        for track in try await asset.loadTracks(withMediaType: .audio).prefix(1) {
            for segment in try await track.load(.segments) where !segment.isEmpty {
                let time = segment.timeMapping.target
                let start = time.start.seconds
                let end = time.end.seconds
                guard start.isFinite, end.isFinite, end > start else {
                    throw ScreenRecordingExportError.unavailableMedia
                }
                ranges.append(start..<end)
            }
        }
        return ranges
    }
}
