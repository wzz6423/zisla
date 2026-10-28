import Foundation

public enum RecordingMediaKind: String, Codable, CaseIterable, Sendable {
    case video, image, audio
}

public struct RecordingMediaAsset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var file: String
    public var kind: RecordingMediaKind
    public var duration: Double
    public var width: Int
    public var height: Int
    public var hasAudio: Bool
    public var isHiddenFromLibrary: Bool?

    public init(id: UUID = UUID(), name: String, file: String, kind: RecordingMediaKind,
                duration: Double, width: Int = 0, height: Int = 0, hasAudio: Bool = false,
                isHiddenFromLibrary: Bool? = nil) {
        self.id = id
        self.name = name
        self.file = file
        self.kind = kind
        self.duration = duration
        self.width = width
        self.height = height
        self.hasAudio = hasAudio
        self.isHiddenFromLibrary = isHiddenFromLibrary
    }
}

public enum RecordingTimelineTrackKind: String, Codable, CaseIterable, Sendable {
    case video, image, text, audio

    public var title: String {
        switch self {
        case .video: "视频轨道"
        case .image: "图片轨道"
        case .text: "文字轨道"
        case .audio: "音频轨道"
        }
    }

    public var symbol: String {
        switch self {
        case .video: "film"
        case .image: "photo"
        case .text: "textformat"
        case .audio: "waveform"
        }
    }
}

public struct RecordingTimelineTrack: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: RecordingTimelineTrackKind
    public var name: String
    public var isHidden: Bool
    public var isMuted: Bool

    public init(id: String = UUID().uuidString, kind: RecordingTimelineTrackKind = .video,
                name: String = "", isHidden: Bool = false, isMuted: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isHidden = isHidden
        self.isMuted = isMuted
    }

    public func title(at index: Int) -> String {
        name.isEmpty ? AppLocalization.text("轨道 %ld", index + 1) : name
    }
}

public enum RecordingTimelineContent: Codable, Hashable, Sendable {
    case recording(UUID)
    case video(UUID)
    case image(UUID)
    case audio(UUID)
    case annotation(UUID)
    case caption(UUID)

    public var assetID: UUID? {
        switch self {
        case let .recording(id), let .video(id), let .image(id), let .audio(id): id
        case .annotation, .caption: nil
        }
    }

    public var trackKind: RecordingTimelineTrackKind {
        switch self {
        case .recording, .video: .video
        case .image: .image
        case .audio: .audio
        case .annotation, .caption: .text
        }
    }
}

public struct RecordingTimelineClip: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var trackID: String
    public var content: RecordingTimelineContent
    public var start: Double
    public var sourceStart: Double
    public var sourceEnd: Double
    public var speed: Double
    public var layout: RecordingRect
    public var volume: Double
    public var audioEnabled: Bool

    public init(id: String = UUID().uuidString, trackID: String, content: RecordingTimelineContent,
                start: Double, sourceStart: Double = 0, sourceEnd: Double, speed: Double = 1,
                layout: RecordingRect = .init(x: 0, y: 0, width: 1, height: 1),
                volume: Double = 1, audioEnabled: Bool = true) {
        self.id = id
        self.trackID = trackID
        self.content = content
        self.start = start
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.speed = speed
        self.layout = layout
        self.volume = volume
        self.audioEnabled = audioEnabled
    }

    public var duration: Double { (sourceEnd - sourceStart) / speed }
    public var end: Double { start + duration }
    public func contains(_ time: Double) -> Bool {
        let boundary = time + time.ulp * 4
        return boundary >= start && boundary < end
    }
    public func sourceTime(at time: Double) -> Double { min(sourceEnd, max(sourceStart, sourceStart + (time - start) * speed)) }
}

public struct RecordingMultitrackTimeline: Codable, Equatable, Sendable {
    public var assets: [RecordingMediaAsset]
    public var tracks: [RecordingTimelineTrack]
    public var clips: [RecordingTimelineClip]

    public init(assets: [RecordingMediaAsset] = [], tracks: [RecordingTimelineTrack] = [],
                clips: [RecordingTimelineClip] = []) {
        self.assets = assets
        self.tracks = tracks
        self.clips = clips
    }

    public var duration: Double { clips.map(\.end).max() ?? 0 }

    public func visibleClips(at time: Double) -> [RecordingTimelineClip] {
        let order = Dictionary(uniqueKeysWithValues: tracks.enumerated().filter {
            !$0.element.isHidden
        }.map { ($0.element.id, $0.offset) })
        return clips.enumerated().filter {
            order[$0.element.trackID] != nil && $0.element.contains(time) && $0.element.content.trackKind != .audio
        }
            .sorted {
                let left = order[$0.element.trackID]!
                let right = order[$1.element.trackID]!
                return left == right ? $0.offset < $1.offset : left < right
            }.map(\.element)
    }

    public func validate(project: ScreenRecordingProject) throws {
        guard assets.count <= 2_000, tracks.count <= 256, clips.count <= 100_000,
              Set(assets.map(\.id)).count == assets.count,
              Set(tracks.map(\.id)).count == tracks.count,
              Set(clips.map(\.id)).count == clips.count,
              duration.isFinite, duration <= 604_800 else { throw ScreenRecordingProjectError.invalidProject }
        for asset in assets {
            guard ScreenRecordingProject.isSafeMediaPath(asset.file) else { throw ScreenRecordingProjectError.unsafeMediaPath }
            guard !asset.name.isEmpty, asset.name.count <= 512, asset.duration.isFinite,
                  asset.duration > 0, asset.duration <= 604_800,
                  asset.kind == .audio || ((1...16_384).contains(asset.width) && (1...16_384).contains(asset.height))
            else { throw ScreenRecordingProjectError.invalidProject }
        }
        let media = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let trackMap = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let annotations = Set((project.edits.annotations ?? []).map(\.id))
        let captions = Set(project.captions.map(\.id))
        for track in tracks {
            guard !track.id.isEmpty, track.id.count <= 255, track.name.count <= 512 else {
                throw ScreenRecordingProjectError.invalidProject
            }
        }
        for clip in clips {
            guard !clip.id.isEmpty, clip.id.count <= 255,
                  trackMap[clip.trackID] != nil,
                  [clip.start, clip.sourceStart, clip.sourceEnd, clip.speed, clip.volume].allSatisfy(\.isFinite),
                  clip.start >= 0, clip.sourceStart >= 0, clip.sourceEnd > clip.sourceStart,
                  (0.1...8).contains(clip.speed), (0...1).contains(clip.volume), clip.layout.isNormalized
            else { throw ScreenRecordingProjectError.invalidProject }
            switch clip.content {
            case let .recording(id), let .video(id):
                guard let asset = media[id], asset.kind == .video, clip.sourceEnd <= asset.duration + 0.001 else {
                    throw ScreenRecordingProjectError.invalidProject
                }
                if case .recording = clip.content, asset.file != project.videoFile {
                    throw ScreenRecordingProjectError.invalidProject
                }
            case let .image(id):
                guard media[id]?.kind == .image else { throw ScreenRecordingProjectError.invalidProject }
            case let .audio(id):
                guard let asset = media[id], asset.kind == .audio || asset.hasAudio,
                      clip.sourceEnd <= asset.duration + 0.001 else { throw ScreenRecordingProjectError.invalidProject }
            case let .annotation(id):
                guard annotations.contains(id) else {
                    throw ScreenRecordingProjectError.invalidProject
                }
            case let .caption(id):
                guard captions.contains(id) else { throw ScreenRecordingProjectError.invalidProject }
            }
        }
    }

    public static func migrating(_ project: ScreenRecordingProject) -> Self {
        if let timeline = project.timeline { return timeline }
        let videoTrack = RecordingTimelineTrack(id: "recording")
        let source = RecordingMediaAsset(id: project.id, name: project.name, file: project.videoFile,
            kind: .video, duration: project.duration, width: project.width, height: project.height, hasAudio: true)
        var timeline = Self(assets: [source], tracks: [videoTrack])
        var offset = 0.0
        for segment in project.edits.segments {
            timeline.clips.append(.init(id: segment.id.uuidString, trackID: videoTrack.id,
                content: .recording(source.id), start: offset, sourceStart: segment.start,
                sourceEnd: segment.end, speed: segment.speed))
            for annotation in project.edits.annotations ?? [] {
                timeline.appendLegacyOverlay(id: "annotation.\(annotation.id).\(segment.id)",
                    content: .annotation(annotation.id), range: annotation.start...annotation.end,
                    segment: segment, offset: offset, trackID: "annotations")
            }
            for caption in project.captions {
                timeline.appendLegacyOverlay(id: "caption.\(caption.id).\(segment.id)",
                    content: .caption(caption.id), range: caption.start...caption.end,
                    segment: segment, offset: offset, trackID: "captions")
            }
            offset += segment.outputDuration
        }
        for id in ["annotations", "captions"] where timeline.clips.contains(where: { $0.trackID == id }) {
            timeline.tracks.append(.init(id: id))
        }
        return timeline
    }

    private mutating func appendLegacyOverlay(id: String, content: RecordingTimelineContent,
                                              range: ClosedRange<Double>, segment: RecordingSegment,
                                              offset: Double, trackID: String) {
        let start = max(segment.start, range.lowerBound)
        let end = min(segment.end, range.upperBound)
        if end > start {
            clips.append(.init(id: id, trackID: trackID, content: content,
                start: offset + (start - segment.start) / segment.speed,
                sourceStart: start, sourceEnd: end, speed: segment.speed))
        }
    }

    @discardableResult
    public mutating func addTrack(_ kind: RecordingTimelineTrackKind = .video) -> String {
        let track = RecordingTimelineTrack(kind: kind)
        tracks.append(track)
        return track.id
    }

    @discardableResult
    public mutating func addAssetClip(_ id: UUID, at time: Double, trackID: String? = nil) -> String? {
        guard let asset = assets.first(where: { $0.id == id }), time.isFinite, time >= 0 else { return nil }
        let content: RecordingTimelineContent
        switch asset.kind {
        case .video: content = .video(id)
        case .image: content = .image(id)
        case .audio: content = .audio(id)
        }
        let target: String
        if let trackID {
            guard tracks.contains(where: { $0.id == trackID }) else { return nil }
            target = trackID
        } else { target = addTrack() }
        let clip = RecordingTimelineClip(trackID: target, content: content, start: time, sourceEnd: asset.duration)
        clips.append(clip)
        return clip.id
    }

    @discardableResult
    public mutating func splitClip(_ id: String, at time: Double) -> String? {
        guard let index = clips.firstIndex(where: { $0.id == id }), time.isFinite else { return nil }
        let clip = clips[index]
        guard time > clip.start + 0.001, time < clip.end - 0.001 else { return nil }
        var tail = clip
        tail.id = UUID().uuidString
        tail.start = time
        tail.sourceStart = clip.sourceTime(at: time)
        clips[index].sourceEnd = tail.sourceStart
        clips.insert(tail, at: index + 1)
        return tail.id
    }
}
