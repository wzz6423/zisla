import Testing
@testable import ZislaCore

struct RecordingLivePhotoPolicyTests {
    @Test(arguments: [0.1, 1, 3.0.nextDown, 3.0])
    func supportsPositiveDurationsThroughTheCompatibilityLimit(_ duration: Double) {
        #expect(RecordingLivePhotoPolicy.maximumDuration == 3)
        #expect(RecordingLivePhotoPolicy.supports(duration: duration))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1, 0, 3.0.nextUp, 3.01, 20])
    func rejectsInvalidAndLongDurationsWithoutRoundingThemDown(_ duration: Double) {
        #expect(!RecordingLivePhotoPolicy.supports(duration: duration))
    }

    @Test func trimmedAndAcceleratedLongSourcesUseTheirEditedDuration() throws {
        var project = ScreenRecordingProject(name: "Long source", videoFile: "screen.mp4", duration: 12,
            width: 64, height: 48)
        #expect(!RecordingLivePhotoPolicy.supports(duration: project.outputDuration))
        project.edits.segments = [.init(start: 2, end: 5)]
        try project.validate()
        #expect(project.outputDuration == 3)
        #expect(RecordingLivePhotoPolicy.supports(duration: project.outputDuration))
        project.edits.segments = [.init(start: 0, end: 6, speed: 2)]
        try project.validate()
        #expect(RecordingLivePhotoPolicy.supports(duration: project.outputDuration))
        project.edits.segments[0].speed = 1
        #expect(!RecordingLivePhotoPolicy.supports(duration: project.outputDuration))
    }

    @Test func delayedClipsAndOtherTracksExtendTheFinalDuration() throws {
        var project = ScreenRecordingProject(name: "Timeline", videoFile: "screen.mp4", duration: 2,
            width: 64, height: 48)
        var timeline = RecordingMultitrackTimeline.migrating(project)
        timeline.clips[0].start = 1
        project.timeline = timeline
        project.version = ScreenRecordingProject.currentVersion
        try project.validate()
        #expect(project.outputDuration == 3)
        #expect(RecordingLivePhotoPolicy.supports(duration: project.outputDuration))
        timeline.clips[0].start = 1.01
        project.timeline = timeline
        try project.validate()
        #expect(!RecordingLivePhotoPolicy.supports(duration: project.outputDuration))
        timeline.clips[0].start = 0
        let additionalTrack = timeline.addTrack()
        timeline.clips.append(.init(trackID: additionalTrack, content: .video(project.id), start: 2, sourceEnd: 2))
        project.timeline = timeline
        try project.validate()
        #expect(project.outputDuration == 4)
        #expect(!RecordingLivePhotoPolicy.supports(duration: project.outputDuration))
    }
}
