import Foundation
import Testing
@testable import ZislaCore

struct ScreenRecordingMultitrackModelsTests {
    private func legacyProject() -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Legacy", videoFile: "screen.mp4", duration: 12, width: 64, height: 48)
        project.version = 1
        project.edits.segments = [.init(start: 8, end: 12, speed: 2), .init(start: 0, end: 2, speed: 0.5),
                                  .init(start: 8, end: 10)]
        project.edits.annotations = [.init(kind: .text, start: 8.5, end: 9.5, text: "Repeated text")]
        project.captions = [.init(start: 8, end: 9, text: "Repeated caption"), .init(start: 1, end: 1.5, text: "Slow caption")]
        return project
    }

    @Test func legacyMigrationPreservesRepeatedRetimedOverlaysAndDoesNotMutateTheSource() throws {
        let source = legacyProject()
        let timeline = RecordingMultitrackTimeline.migrating(source)
        #expect(source.timeline == nil && source.version == 1)
        #expect(timeline.duration == source.outputDuration && timeline.duration == 8)
        #expect(timeline.assets.count == 1 && timeline.assets[0].id == source.id)
        #expect(timeline.tracks.map(\.id) == ["recording", "annotations", "captions"])
        let recording = timeline.clips.filter { $0.content == .recording(source.id) }
        #expect(recording.map(\.id) == source.edits.segments.map { $0.id.uuidString })
        #expect(recording.map(\.start) == [0, 2, 6])
        #expect(recording.map(\.speed) == [2, 0.5, 1])
        let annotation = try #require(source.edits.annotations?.first)
        let overlays = timeline.clips.filter { $0.content == .annotation(annotation.id) }
        #expect(overlays.map(\.start) == [0.25, 6.5])
        #expect(overlays.map(\.duration) == [0.5, 1])
        #expect(overlays[0].sourceTime(at: 0.5) == 9 && overlays[1].sourceTime(at: 7) == 9)
        let firstCaption = timeline.clips.filter { $0.content == .caption(source.captions[0].id) }
        #expect(firstCaption.map(\.start) == [0, 6])
        #expect(firstCaption.map(\.duration) == [0.5, 1])
        let slowCaption = try #require(timeline.clips.first { $0.content == .caption(source.captions[1].id) })
        #expect(slowCaption.start == 4 && slowCaption.duration == 1)
        var migrated = source
        migrated.version = 2
        migrated.timeline = timeline
        try migrated.validate()
        #expect(RecordingMultitrackTimeline.migrating(migrated) == timeline)
        #expect(try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(migrated)) == migrated)
    }

    @Test func absentV1TimelineDecodesWithoutImplicitlyPersistingMigration() throws {
        let source = legacyProject()
        var manifest = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        manifest.removeValue(forKey: "timeline")
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONSerialization.data(withJSONObject: manifest))
        try decoded.validate()
        #expect(decoded == source && decoded.timeline == nil)
        #expect(RecordingMultitrackTimeline.migrating(decoded).duration == 8)
    }

    @Test func importingAssetsAloneDoesNotCreateTracksOrExtendOutputDuration() throws {
        let image = RecordingMediaAsset(name: "Picture", file: "picture.png", kind: .image, duration: 5, width: 64, height: 48)
        var project = ScreenRecordingProject(name: "Library", videoFile: "", duration: 5, width: 64, height: 48,
            edits: .init(segments: []), timeline: .init(assets: [image]))
        try project.validate()
        #expect(project.outputDuration == 0 && project.timeline?.tracks.isEmpty == true && project.timeline?.clips.isEmpty == true)
        let added = project.timeline?.addAssetClip(image.id, at: 3)
        let clipID = try #require(added)
        try project.validate()
        #expect(project.timeline?.tracks.count == 1 && project.timeline?.clips.first?.trackID == project.timeline?.tracks.first?.id)
        #expect(project.timeline?.clips.first?.content == .image(image.id))
        #expect(project.timeline?.clips.first?.id == clipID && project.outputDuration == 8)
    }

    @Test func everyExistingTrackAcceptsAssetsAndInvalidDestinationsDoNotCreateTracks() {
        let video = RecordingMediaAsset(name: "Video", file: "video.mp4", kind: .video, duration: 2, width: 64, height: 48)
        var timeline = RecordingMultitrackTimeline(assets: [video], tracks: [.init(id: "v", kind: .video), .init(id: "a", kind: .audio)])
        #expect(timeline.addAssetClip(video.id, at: 0, trackID: "v") != nil)
        #expect(timeline.tracks.count == 2 && timeline.clips[0].trackID == "v")
        #expect(timeline.addAssetClip(video.id, at: 2, trackID: "a") != nil)
        #expect(timeline.tracks.count == 2 && timeline.clips[1].trackID == "a")
        let unchanged = timeline
        for time in [-1, Double.nan, .infinity] { #expect(timeline.addAssetClip(video.id, at: time) == nil) }
        #expect(timeline.addAssetClip(UUID(), at: 0) == nil && timeline == unchanged)
        #expect(timeline.addAssetClip(video.id, at: 0, trackID: "missing") == nil && timeline == unchanged)
    }

    @Test(arguments: RecordingTimelineTrackKind.allCases)
    func legacyTracksAcceptEveryContentAndRoundTripWithoutLosingTheirNames(_ kind: RecordingTimelineTrackKind) throws {
        var project = legacyProject()
        project.version = 2
        let image = RecordingMediaAsset(name: "Picture", file: "picture.png", kind: .image, duration: 2, width: 64, height: 48)
        let audio = RecordingMediaAsset(name: "Sound", file: "tone.wav", kind: .audio, duration: 2)
        let source = RecordingMediaAsset(id: project.id, name: project.name, file: project.videoFile,
            kind: .video, duration: project.duration, width: project.width, height: project.height, hasAudio: true)
        let annotation = try #require(project.edits.annotations?.first)
        let contents: [RecordingTimelineContent] = [.recording(source.id), .video(source.id), .image(image.id),
            .audio(audio.id), .annotation(annotation.id), .caption(project.captions[0].id)]
        project.timeline = .init(assets: [source, image, audio],
            tracks: [.init(id: "mixed", kind: kind, name: "My legacy track", isMuted: true)],
            clips: contents.enumerated().map {
                .init(id: "content\($0.offset)", trackID: "mixed", content: $0.element, start: 0, sourceEnd: 1)
            })
        try project.validate()
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(project))
        try decoded.validate()
        #expect(decoded == project && decoded.timeline?.tracks[0].kind == kind)
        #expect(decoded.timeline?.tracks[0].name == "My legacy track")
        #expect(decoded.timeline?.visibleClips(at: 0.5).map(\.content) == contents.filter { $0 != .audio(audio.id) },
            "Track metadata and mute state must not suppress visual content, and audio must never become a visual layer")
        project.timeline?.tracks[0].isHidden = true
        #expect(project.timeline?.visibleClips(at: 0.5).isEmpty == true)
    }

    @Test(arguments: [0.1, 0.5, 1.0, 2.0, 8.0])
    func splittingPreservesSourceContinuitySpeedAndLayerProperties(_ speed: Double) throws {
        let original = RecordingTimelineClip(id: "cut", trackID: "v", content: .video(UUID()),
            start: 3, sourceStart: 2, sourceEnd: 6, speed: speed,
            layout: .init(x: 0.1, y: 0.2, width: 0.6, height: 0.7), volume: 0.3, audioEnabled: false)
        var timeline = RecordingMultitrackTimeline(clips: [original])
        let cut = original.start + 2 / speed
        let splitID = timeline.splitClip(original.id, at: cut)
        let tailID = try #require(splitID)
        #expect(timeline.clips[0].id == original.id && tailID != original.id)
        #expect(timeline.clips[0].sourceEnd == 4 && timeline.clips[1].sourceStart == 4)
        #expect(timeline.clips[1].start == cut && abs(timeline.clips[1].end - original.end) < 0.000_001)
        #expect(timeline.clips.allSatisfy { $0.speed == speed && $0.layout == original.layout && $0.volume == 0.3 && !$0.audioEnabled })
        let split = timeline
        for time in [original.start, original.start + 0.000_5, original.end, Double.nan] {
            #expect(timeline.splitClip(original.id, at: time) == nil)
        }
        #expect(timeline == split)
    }

    @Test func existingV2TrackMetadataDecodesAndKeepsItsSavedKindAndFlags() throws {
        let data = Data(#"{"id":"legacy","kind":"audio","name":"My track","isHidden":true,"isMuted":true}"#.utf8)
        let track = try JSONDecoder().decode(RecordingTimelineTrack.self, from: data)
        #expect(track.id == "legacy" && track.kind == .audio && track.name == "My track" && track.isHidden && track.isMuted)
        #expect(track.title(at: 3) == "My track")
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        #expect(encoded["kind"] as? String == "audio")
        #expect(try JSONDecoder().decode(RecordingTimelineTrack.self, from: JSONEncoder().encode(track)) == track)
    }

    @Test(arguments: [0.5, 1.0, 7.25, 65_536.0])
    func fourULPToleranceChoosesTheFollowingClipAtARoundedBoundary(_ boundary: Double) {
        let previous = RecordingTimelineClip(id: "previous", trackID: "v", content: .video(UUID()), start: 0, sourceEnd: boundary)
        let next = RecordingTimelineClip(id: "next", trackID: "v", content: .video(UUID()), start: boundary, sourceEnd: 1)
        for distance in 0...8 {
            let time = boundary - Double(distance) * boundary.ulp
            let expectedNext = time + time.ulp * 4 >= boundary
            #expect(next.contains(time) == expectedNext)
            #expect(previous.contains(time) == !expectedNext)
        }
    }

    @Test func visibleLayersRespectTrackOrderHiddenTracksAndClipOrder() {
        let id = UUID()
        let tracks: [RecordingTimelineTrack] = [.init(id: "back", kind: .video), .init(id: "front", kind: .video),
            .init(id: "hidden", kind: .video, isHidden: true), .init(id: "audio", kind: .audio)]
        let clips = ["front", "back", "hidden", "audio", "front"].enumerated().map {
            RecordingTimelineClip(id: String($0.offset), trackID: $0.element, content: .video(id), start: 1, sourceEnd: 2)
        }
        var timeline = RecordingMultitrackTimeline(tracks: tracks, clips: clips)
        timeline.clips.append(.init(id: "sound", trackID: "back", content: .audio(id), start: 1, sourceEnd: 2))
        #expect(timeline.visibleClips(at: 1.5).map(\.id) == ["1", "0", "4", "3"])
        #expect(timeline.visibleClips(at: 0).isEmpty && timeline.visibleClips(at: 3).isEmpty)
    }

    @Test(arguments: ["asset", "track", "clip", "content", "path", "speed", "layout", "duration", "version"])
    func invalidMultitrackReferencesAndBoundsAreRejected(_ fault: String) throws {
        var project = legacyProject()
        project.version = 2
        project.timeline = .migrating(project)
        let valid = project
        switch fault {
        case "asset": project.timeline?.assets.append(valid.timeline!.assets[0])
        case "track": project.timeline?.clips[0].trackID = "missing"
        case "clip": project.timeline?.clips.append(valid.timeline!.clips[0])
        case "content": project.timeline?.clips[0].content = .video(UUID())
        case "path": project.timeline?.assets[0].file = "../escaped.mp4"
        case "speed": project.timeline?.clips[0].speed = .nan
        case "layout": project.timeline?.clips[0].layout.width = 2
        case "duration": project.timeline?.clips[0].start = 604_800
        default: project.version = 1
        }
        #expect(throws: ScreenRecordingProjectError.self) { try project.validate() }
        try valid.validate()
    }
}
