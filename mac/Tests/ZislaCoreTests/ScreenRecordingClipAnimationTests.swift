import Foundation
import Testing
@testable import ZislaCore

struct ScreenRecordingClipAnimationTests {
    private func project() -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Animations", videoFile: "screen.mp4", duration: 8, width: 64, height: 48)
        project.edits.annotations = [.init(kind: .text, start: 0, end: 4, text: "你好👨‍👩‍👧‍👦e\u{301}\n!")]
        project.captions = [.init(start: 0, end: 4, text: "Caption")]
        project.timeline = .migrating(project)
        return project
    }

    @Test func oldClipsDecodeWithoutAnimationsAndEffectsRoundTrip() throws {
        var project = project()
        let old = project
        let manifest = try JSONEncoder().encode(old)
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: manifest)
        #expect(decoded == old && decoded.timeline?.clips.allSatisfy {
            $0.entranceAnimation == nil && $0.exitAnimation == nil && $0.transition == nil
        } == true)
        project.timeline?.clips[0].entranceAnimation = .init(kind: .slideLeft, duration: 0.25)
        project.timeline?.clips[0].exitAnimation = .init(kind: .scale, duration: 0.75)
        project.timeline?.clips[0].transition = .init(kind: .dissolve, duration: 0.5)
        try project.validate()
        #expect(try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(project)) == project)
        #expect(String(decoding: manifest, as: UTF8.self).contains("entranceAnimation") == false,
            "Nil animation fields must not be written into existing manifests")
    }

    @Test(arguments: [0.25, 1.0, 2.0, 8.0])
    func animationsUseOutputSecondsAndShortClipsFitEntranceAndExit(_ speed: Double) {
        let clip = RecordingTimelineClip(trackID: "video", content: .video(UUID()), start: 4,
            sourceStart: 3, sourceEnd: 11, speed: speed,
            entranceAnimation: .init(kind: .fade, duration: 0.25), exitAnimation: .init(kind: .fade, duration: 0.25))
        #expect(RecordingClipAnimationSample.sample(clip, at: 4).opacity == 0)
        #expect(abs(RecordingClipAnimationSample.sample(clip, at: 4.125).opacity - 0.5) < 0.000_001)
        #expect(RecordingClipAnimationSample.sample(clip, at: 4.25).opacity == 1)
        #expect(abs(RecordingClipAnimationSample.sample(clip, at: clip.end - 0.125).opacity - 0.5) < 0.000_001)
        #expect(RecordingClipAnimationSample.sample(clip, at: clip.end).opacity == 0)
        var short = clip
        short.sourceEnd = short.sourceStart + 0.1 * speed
        short.entranceAnimation?.duration = 2
        short.exitAnimation?.duration = 2
        #expect(abs(RecordingClipAnimationSample.sample(short, at: 4.025).opacity - 0.5) < 0.000_001)
        #expect(abs(RecordingClipAnimationSample.sample(short, at: 4.05).opacity - 1) < 0.000_001)
        #expect(abs(RecordingClipAnimationSample.sample(short, at: 4.075).opacity - 0.5) < 0.000_001)
        #expect(short.entranceAnimation?.duration == 2 && short.exitAnimation?.duration == 2,
            "Sampling must not rewrite the user's saved duration after trimming")
    }

    @Test(arguments: RecordingClipAnimationKind.allCases)
    func samplingEndsInTheOriginalLayoutAndPreservesDirection(_ kind: RecordingClipAnimationKind) {
        let clip = RecordingTimelineClip(trackID: "visual", content: .annotation(UUID()), start: 1, sourceEnd: 3,
            entranceAnimation: .init(kind: kind, duration: 1))
        let middle = RecordingClipAnimationSample.sample(clip, at: 1.5, characterCount: 6)
        #expect(RecordingClipAnimationSample.sample(clip, at: 2).scale == 1)
        #expect(RecordingClipAnimationSample.sample(clip, at: 2).offsetX == 0)
        #expect(RecordingClipAnimationSample.sample(clip, at: 2).offsetY == 0)
        switch kind {
        case .fade: #expect(middle.opacity == 0.5)
        case .slideLeft: #expect(middle.offsetX == -0.5)
        case .slideRight: #expect(middle.offsetX == 0.5)
        case .slideUp: #expect(middle.offsetY == -0.5)
        case .slideDown: #expect(middle.offsetY == 0.5)
        case .scale: #expect(middle.scale == 0.75 && middle.opacity == 0.5)
        case .typewriter: #expect(middle.visibleCharacters == 3 && middle.opacity == 1)
        }
    }

    @Test func typewriterUsesWholeUnicodeCharactersIncludingNewlinesAndEmptyText() {
        let text = "你👨‍👩‍👧‍👦e\u{301}\n!"
        #expect(text.count == 5 && text.utf16.count > text.count)
        let clip = RecordingTimelineClip(trackID: "text", content: .caption(UUID()), start: 0, sourceEnd: 3,
            entranceAnimation: .init(kind: .typewriter, duration: 1))
        for index in 0...5 {
            let sample = RecordingClipAnimationSample.sample(clip, at: Double(index) / 5, characterCount: text.count)
            #expect(sample.visibleCharacters == index)
            #expect(String(text.prefix(sample.visibleCharacters!)) == String(Array(text).prefix(index)))
        }
        #expect(RecordingClipAnimationSample.sample(clip, at: 0.5, characterCount: 0).visibleCharacters == 0)
    }

    @Test(arguments: [-1.0, 0.0, 30.001, Double.nan, Double.infinity])
    func invalidAnimationAndTransitionDurationsAreRejected(_ duration: Double) {
        let valid = project()
        for field in 0...2 {
            var invalid = valid
            if field == 0 { invalid.timeline?.clips[0].entranceAnimation = .init(kind: .fade, duration: duration) }
            if field == 1 { invalid.timeline?.clips[0].exitAnimation = .init(kind: .fade, duration: duration) }
            if field == 2 { invalid.timeline?.clips[0].transition = .init(kind: .dissolve, duration: duration) }
            #expect(throws: ScreenRecordingProjectError.invalidProject) { try invalid.validate() }
        }
    }

    @Test func typewriterRejectsExitImagesVideoAudioAndShapeAnnotations() throws {
        let original = project()
        let textIndex = try #require(original.timeline?.clips.firstIndex { $0.content.trackKind == .text })
        var valid = original
        valid.timeline?.clips[textIndex].entranceAnimation = .init(kind: .typewriter)
        try valid.validate()
        var invalidExit = valid
        invalidExit.timeline?.clips[textIndex].exitAnimation = .init(kind: .typewriter)
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try invalidExit.validate() }
        var invalidVideo = original
        invalidVideo.timeline?.clips[0].entranceAnimation = .init(kind: .typewriter)
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try invalidVideo.validate() }
        var invalidShape = valid
        invalidShape.edits.annotations?[0].kind = .rectangle
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try invalidShape.validate() }
        let audio = RecordingMediaAsset(name: "Audio", file: "tone.wav", kind: .audio, duration: 8)
        var invalidAudio = original
        invalidAudio.timeline?.assets.append(audio)
        invalidAudio.timeline?.clips[0].content = .audio(audio.id)
        for effect in 0...2 {
            var project = invalidAudio
            if effect == 0 { project.timeline?.clips[0].entranceAnimation = .init(kind: .fade) }
            if effect == 1 { project.timeline?.clips[0].exitAnimation = .init(kind: .scale) }
            if effect == 2 { project.timeline?.clips[0].transition = .init(kind: .dissolve) }
            #expect(throws: ScreenRecordingProjectError.invalidProject) { try project.validate() }
        }
    }

    @Test func unknownEffectNamesAreRejectedRatherThanSilentlyDropped() throws {
        let clip = RecordingTimelineClip(trackID: "track", content: .video(UUID()), start: 0, sourceEnd: 1,
            entranceAnimation: .init(kind: .fade))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any])
        object["entranceAnimation"] = ["kind": "unknown", "duration": 0.5]
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RecordingTimelineClip.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func splittingKeepsEntranceAndTransitionAtTheOriginalStartAndExitAtTheOriginalEnd() throws {
        let source = RecordingTimelineClip(id: "source", trackID: "track", content: .video(UUID()),
            start: 2, sourceStart: 1, sourceEnd: 5, speed: 2,
            entranceAnimation: .init(kind: .fade), exitAnimation: .init(kind: .slideDown),
            transition: .init(kind: .dissolve))
        var timeline = RecordingMultitrackTimeline(clips: [source])
        let splitID = timeline.splitClip(source.id, at: 3)
        let tailID = try #require(splitID)
        let head = timeline.clips[0]
        let tail = timeline.clips[1]
        #expect(head.entranceAnimation == source.entranceAnimation && head.transition == source.transition && head.exitAnimation == nil)
        #expect(tail.id == tailID && tail.entranceAnimation == nil && tail.transition == nil && tail.exitAnimation == source.exitAnimation)
        #expect(head.end == tail.start && tail.end == source.end && head.sourceEnd == tail.sourceStart)
        #expect(RecordingClipAnimationSample.sample(head, at: head.end - 0.001).opacity == 1)
        #expect(RecordingClipAnimationSample.sample(tail, at: tail.start).offsetY == 0)
    }

    @Test func invalidSamplingInputsCannotProduceNonfiniteTransformsOrTrapTypewriterCounts() {
        let clip = RecordingTimelineClip(trackID: "text", content: .caption(UUID()), start: 1, sourceEnd: 2,
            entranceAnimation: .init(kind: .typewriter, duration: 1), exitAnimation: .init(kind: .fade))
        for time in [Double.nan, .infinity, -.infinity] {
            #expect(RecordingClipAnimationSample.sample(clip, at: time, characterCount: 5) == .init())
        }
        #expect(RecordingClipAnimationSample.sample(clip, at: 1.5, characterCount: -3).visibleCharacters == 0)
        #expect(RecordingClipAnimationSample.sample(clip, at: 2, characterCount: Int.max).visibleCharacters == Int.max)

    }

    @Test(arguments: RecordingClipTransitionKind.allCases)
    func transitionsUseOnlyExistingOverlapAndKeepTheCompletedIncomingLayer(_ kind: RecordingClipTransitionKind) throws {
        let outgoing = RecordingTimelineClip(id: "outgoing", trackID: "mixed", content: .video(UUID()),
            start: 1, sourceStart: 3, sourceEnd: 9, speed: 2)
        let incoming = RecordingTimelineClip(id: "incoming", trackID: "mixed", content: .image(UUID()),
            start: 3, sourceEnd: 3, transition: .init(kind: kind, duration: 0.5))
        let originals = [outgoing, incoming]
        let start = try #require(RecordingClipTransitionSample.sample(incoming, from: outgoing, at: 3))
        let middle = try #require(RecordingClipTransitionSample.sample(incoming, from: outgoing, at: 3.25))
        let completed = try #require(RecordingClipTransitionSample.sample(incoming, from: outgoing, at: 3.75))
        #expect(start.kind == kind && start.progress == 0 && start.start == 3 && start.end == 3.5)
        #expect(middle.progress == 0.5 && completed.progress == 1)
        #expect(RecordingClipTransitionSample.sample(incoming, from: outgoing, at: 2.9) == nil)
        #expect(RecordingClipTransitionSample.sample(incoming, from: outgoing, at: outgoing.end) == nil)
        var long = incoming
        long.transition?.duration = 30
        let clamped = try #require(RecordingClipTransitionSample.sample(long, from: outgoing, at: 3.5))
        #expect(clamped.end == 4 && clamped.progress == 0.5 && long.transition?.duration == 30)
        #expect([outgoing, incoming] == originals, "Sampling must not move, trim or rewrite either clip")
    }

    @Test func transitionSourcesShareOneTrackOrderRespectHiddenAudioAndDoNotSkipTheDirectPredecessor() {
        let first = RecordingTimelineClip(id: "first", trackID: "track", content: .video(UUID()), start: 0, sourceEnd: 10)
        let blocker = RecordingTimelineClip(id: "blocker", trackID: "track", content: .annotation(UUID()), start: 1, sourceEnd: 0.5)
        let later = RecordingTimelineClip(id: "later", trackID: "track", content: .image(UUID()), start: 2, sourceEnd: 2)
        var equal = later
        equal.id = "equal"
        let audio = RecordingTimelineClip(id: "audio", trackID: "track", content: .audio(UUID()), start: 1.5, sourceEnd: 8)
        let hidden = RecordingTimelineClip(id: "hidden", trackID: "hidden", content: .video(UUID()), start: 0, sourceEnd: 10)
        var other = later
        other.id = "other"
        other.trackID = "other"
        let timeline = RecordingMultitrackTimeline(tracks: [.init(id: "track"), .init(id: "hidden", isHidden: true),
            .init(id: "other")], clips: [later, first, blocker, audio, equal, hidden, other])
        #expect(timeline.transitionSources() == ["blocker": first, "equal": later])
        #expect(timeline.transitionSources()["later"] == nil,
            "An ended direct predecessor must not be replaced by an older overlapping clip")
        #expect(timeline.clips.allSatisfy { $0.transition == nil }, "Candidate lookup must not add an effect")
    }

    @Test func transitionsRejectAbsentNonoverlappingAndInvalidTimeInputs() {
        let outgoing = RecordingTimelineClip(id: "outgoing", trackID: "track", content: .video(UUID()), start: 1, sourceEnd: 2)
        var incoming = RecordingTimelineClip(id: "incoming", trackID: "track", content: .image(UUID()), start: 2, sourceEnd: 2)
        #expect(RecordingClipTransitionSample.sample(incoming, from: outgoing, at: 2.5) == nil)
        incoming.transition = .init(kind: .dissolve)
        for time in [Double.nan, .infinity, -.infinity] {
            #expect(RecordingClipTransitionSample.sample(incoming, from: outgoing, at: time) == nil)
        }
        var touching = incoming
        touching.start = outgoing.end
        #expect(RecordingClipTransitionSample.sample(touching, from: outgoing, at: touching.start) == nil)
        #expect(RecordingClipTransitionSample.sample(incoming, from: outgoing, at: 4) == nil)
    }

    @Test func seededSamplingKeepsTransformsBoundedAndTimeMonotonicWithoutChangingClips() {
        var seed: UInt64 = 4_217
        for index in 0..<96 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let duration = Double(seed % 3_000 + 1) / 100
            let animation = RecordingClipAnimationKind.allCases[index % RecordingClipAnimationKind.allCases.count]
            let clip = RecordingTimelineClip(trackID: "seed", content: .caption(UUID()), start: Double(index),
                sourceEnd: duration, entranceAnimation: .init(kind: animation, duration: Double((seed >> 24) % 3_000 + 1) / 100))
            var previousVisibility = 0.0
            var previousCount = 0
            for step in 0...24 {
                let sample = RecordingClipAnimationSample.sample(clip, at: clip.start + clip.duration * Double(step) / 24,
                    characterCount: 31)
                #expect([sample.opacity, sample.offsetX, sample.offsetY, sample.scale].allSatisfy { $0.isFinite })
                #expect((0...1).contains(sample.opacity) && (0.5...1).contains(sample.scale))
                #expect((-1...1).contains(sample.offsetX) && (-1...1).contains(sample.offsetY))
                #expect(sample.opacity >= previousVisibility)
                #expect((sample.visibleCharacters ?? 0) >= previousCount)
                previousVisibility = sample.opacity
                previousCount = sample.visibleCharacters ?? 0
            }
            #expect(clip.entranceAnimation?.kind == animation && clip.exitAnimation == nil && clip.transition == nil)
        }
    }
}
