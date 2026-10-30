import Foundation

public enum RecordingClipAnimationKind: String, Codable, CaseIterable, Sendable {
    case fade, slideLeft, slideRight, slideUp, slideDown, scale, typewriter

    public var entranceTitle: String {
        switch self {
        case .fade: "淡入"
        case .slideLeft: "从左滑入"
        case .slideRight: "从右滑入"
        case .slideUp: "从上滑入"
        case .slideDown: "从下滑入"
        case .scale: "缩放入场"
        case .typewriter: "打字机"
        }
    }

    public var exitTitle: String {
        switch self {
        case .fade: "淡出"
        case .slideLeft: "向左滑出"
        case .slideRight: "向右滑出"
        case .slideUp: "向上滑出"
        case .slideDown: "向下滑出"
        case .scale: "缩放出场"
        case .typewriter: "打字机"
        }
    }
}

public struct RecordingClipAnimation: Codable, Equatable, Sendable {
    public var kind: RecordingClipAnimationKind
    public var duration: Double

    public init(kind: RecordingClipAnimationKind, duration: Double = 0.5) {
        self.kind = kind
        self.duration = duration
    }

    public var isValid: Bool { duration > 0 && duration <= 30 }
}

public enum RecordingClipTransitionKind: String, Codable, CaseIterable, Sendable {
    case dissolve, slideLeft, slideRight, zoom

    public var title: String {
        switch self {
        case .dissolve: "叠化"
        case .slideLeft: "向左推移"
        case .slideRight: "向右推移"
        case .zoom: "缩放转场"
        }
    }
}

public struct RecordingClipTransition: Codable, Equatable, Sendable {
    public var kind: RecordingClipTransitionKind
    public var duration: Double

    public init(kind: RecordingClipTransitionKind, duration: Double = 0.5) {
        self.kind = kind
        self.duration = duration
    }

    public var isValid: Bool { duration > 0 && duration <= 30 }
}

public struct RecordingClipAnimationSample: Equatable, Sendable {
    public var opacity = 1.0
    public var offsetX = 0.0
    public var offsetY = 0.0
    public var scale = 1.0
    public var visibleCharacters: Int?

    public init() {}

    public static func sample(_ clip: RecordingTimelineClip, at time: Double,
                              characterCount: Int? = nil) -> Self {
        guard time.isFinite else { return Self() }
        let entranceAnimation = clip.entranceAnimation
        let exitAnimation = clip.exitAnimation
        let entrance = entranceAnimation?.duration ?? 0
        let exit = exitAnimation?.duration ?? 0
        let durationScale = entrance + exit > clip.duration ? clip.duration / (entrance + exit) : 1
        var sample = Self()
        if let animation = entranceAnimation {
            let progress = min(1, max(0, (time - clip.start) / (animation.duration * durationScale)))
            if animation.kind == .typewriter, let characterCount {
                let count = max(0, characterCount)
                sample.visibleCharacters = progress == 1 ? count : Int((Double(count) * progress).rounded(.down))
            } else {
                sample.apply(animation.kind, visibility: smooth(progress))
            }
        }
        if let animation = exitAnimation {
            let visibility = min(1, max(0, (clip.end - time) / (animation.duration * durationScale)))
            sample.apply(animation.kind, visibility: smooth(visibility))
        }
        return sample
    }

    private static func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }

    private mutating func apply(_ kind: RecordingClipAnimationKind, visibility: Double) {
        let hidden = 1 - visibility
        switch kind {
        case .fade: opacity *= visibility
        case .slideLeft: offsetX -= hidden
        case .slideRight: offsetX += hidden
        case .slideUp: offsetY -= hidden
        case .slideDown: offsetY += hidden
        case .scale:
            scale *= 0.5 + 0.5 * visibility
            opacity *= visibility
        case .typewriter: break
        }
    }
}

public struct RecordingClipTransitionSample: Equatable, Sendable {
    public let kind: RecordingClipTransitionKind
    public let progress: Double
    public let start: Double
    public let end: Double

    public static func sample(_ incoming: RecordingTimelineClip, from outgoing: RecordingTimelineClip,
                              at time: Double) -> Self? {
        guard let transition = incoming.transition,
              incoming.contains(time), outgoing.contains(time) else { return nil }
        let end = min(incoming.end, outgoing.end, incoming.start + transition.duration)
        let progress = min(1, max(0, (time - incoming.start) / (end - incoming.start)))
        return Self(kind: transition.kind, progress: progress * progress * (3 - 2 * progress),
                    start: incoming.start, end: end)
    }
}

extension RecordingMultitrackTimeline {
    public func transitionSources() -> [String: RecordingTimelineClip] {
        let visibleTracks = Set(tracks.filter { !$0.isHidden }.map(\.id))
        let ordered = clips.enumerated().filter {
            visibleTracks.contains($0.element.trackID) && $0.element.content.trackKind != .audio
        }.sorted {
            $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start
        }
        var preceding: [String: RecordingTimelineClip] = [:]
        var sources: [String: RecordingTimelineClip] = [:]
        for entry in ordered {
            let clip = entry.element
            if let previous = preceding[clip.trackID], previous.end > clip.start {
                sources[clip.id] = previous
            }
            preceding[clip.trackID] = clip
        }
        return sources
    }
}
