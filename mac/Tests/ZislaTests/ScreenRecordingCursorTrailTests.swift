import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingCursorTrailTests {
    @Test
    func movingPointerLeavesAVisibleTrailBehindTheCursor() throws {
        let image = try render(project(), at: 0.5)
        let trail = try RecordingMultitrackTestFixture.pixel(image, x: 160, y: 120)
        #expect(trail[1] > 40 && trail[2] > 80, "Moving the cursor must leave a visible cyan trail behind its current position")
    }

    @Test(arguments: [nil, false] as [Bool?])
    func disabledTrailPreservesExistingCursorAndClickPixels(_ choice: Bool?) throws {
        var source = project()
        source.edits.cursorTrail = choice
        source.edits.clickEffects = true
        source.pointers[2].kind = .leftClick
        let baseline = try render(source, at: 0.6)
        source.edits.cursorTrail = false
        #expect(try pixels(render(source, at: 0.6)) == pixels(baseline))
        #expect(try RecordingMultitrackTestFixture.pixel(baseline, x: 160, y: 120) == [0, 0, 0])
    }

    @Test
    func hidingTheCursorAlsoHidesItsTrail() throws {
        var source = project()
        source.edits.showCursor = false
        let hidden = try render(source, at: 0.5)
        source.edits.cursorTrail = false
        #expect(try pixels(hidden) == pixels(render(source, at: 0.5)),
            "The show-cursor switch must suppress both the cursor and its motion trail")
    }

    @Test
    func trailWidthFollowsTheSelectedCursorSize() throws {
        var source = project()
        source.edits.cursorSize = 4
        let large = try RecordingMultitrackTestFixture.pixel(render(source, at: 0.5), x: 160, y: 122)
        source.edits.cursorSize = 0.5
        let small = try RecordingMultitrackTestFixture.pixel(render(source, at: 0.5), x: 160, y: 122)
        #expect(large[2] > 30 && small[2] == 0, "The trail width must follow cursor size without adding another setting")
    }

    @Test
    func trailFadesAfterMovementStopsAndDoesNotLeaveAStationaryDot() throws {
        var source = project()
        source.pointers.append(.init(time: 1.5, x: 0.7, y: 0.5))
        let fresh = try RecordingMultitrackTestFixture.pixel(render(source, at: 0.5), x: 160, y: 120)
        let fading = try RecordingMultitrackTestFixture.pixel(render(source, at: 0.8), x: 160, y: 120)
        let gone = try RecordingMultitrackTestFixture.pixel(render(source, at: 1.2), x: 160, y: 120)
        #expect(fresh[2] > fading[2] && fading[2] > 0, "The same section of the trail must gradually fade")
        #expect(gone == [0, 0, 0], "The trail must completely disappear after the pointer stops")
        source.edits.cursorTrail = false
        #expect(try pixels(render(source, at: 1.2)) == pixels(render(project(), at: 1.2)),
            "A stopped pointer must not gain a persistent trail dot")
    }

    @Test(arguments: [[], [.init(time: 0, x: 0.4, y: 0.5)],
        [.init(time: 0, x: 0.4, y: 0.5), .init(time: 1, x: 0.4, y: 0.5)]] as [[RecordingPointer]])
    func missingOrStationaryPointerDataDoesNotChangeTheFrame(_ pointers: [RecordingPointer]) throws {
        var source = project()
        source.pointers = pointers
        let enabled = try render(source, at: 0.5)
        source.edits.cursorTrail = false
        #expect(try pixels(enabled) == pixels(render(source, at: 0.5)),
            "Empty, single, and stationary pointer tracks must not draw a trail")
    }

    @Test
    func trailEndsAtTheInterpolatedCursorAndSeekingIsDeterministic() throws {
        let track = RecordingExportEffectTrack(project: project())
        let first = track.trail(at: 0.375, slice: nil)
        _ = track.trail(at: 1.5, slice: nil)
        let second = track.trail(at: 0.375, slice: nil)
        #expect(first == second, "Seeking backward must produce the same trail without frame history")
        let head = try #require(first.last)
        let cursor = try #require(track.pointer(at: 0.375, slice: nil))
        #expect(head.time == 0.375 && head.x == cursor.x && head.y == cursor.y,
            "The trail must reach the displayed interpolated cursor instead of lagging by a sample")
    }

    @Test
    func trailDoesNotUseRemovedHistoryOrFutureSamplesAcrossACut() throws {
        var source = project()
        let slice = RecordingExportSlice(index: 1, sourceStart: 0.5, sourceEnd: 1.5, speed: 2,
            outputStart: 0, outputEnd: 0.5)
        let track = RecordingExportEffectTrack(project: source)
        #expect(track.trail(at: 0.6, slice: slice).allSatisfy { $0.time >= 0.5 })
        let cut = try render(source, at: 0.6, slice: slice)
        source.edits.cursorTrail = false
        #expect(try pixels(cut) == pixels(render(source, at: 0.6, slice: slice)),
            "Movement trimmed before the clip must not appear in the next clip")

        let end = RecordingExportSlice(index: 0, sourceStart: 0, sourceEnd: 0.4, speed: 1,
            outputStart: 0, outputEnd: 0.4)
        let samples = track.trail(at: 0.375, slice: end)
        #expect(samples.allSatisfy { $0.x <= 0.4 }, "A removed future pointer must not pull the trail past a cut")
    }

    @Test(arguments: [0.25, 1, 4] as [Double])
    func trailFollowsTheSourceClockAtEveryClipSpeed(_ speed: Double) throws {
        let slice = RecordingExportSlice(index: 0, sourceStart: 0, sourceEnd: 2, speed: speed,
            outputStart: 0, outputEnd: 2 / speed)
        let sourceTime = slice.sourceTime(at: 0.5 / speed)
        #expect(sourceTime == 0.5)
        #expect(try pixels(render(project(), at: sourceTime, slice: slice)) == pixels(render(project(), at: 0.5)))
    }

    @Test
    func denseLongTracksHaveABoundedPerFrameTrail() throws {
        var source = project()
        source.duration = 100
        source.edits.segments = [.init(start: 0, end: 100)]
        source.pointers = (0..<120_000).map { index in
            .init(time: Double(index) / 1_200, x: Double(index % 1_000) / 1_000, y: 0.5)
        }
        try source.validate()
        let track = RecordingExportEffectTrack(project: source)
        for time in [0, 0.001, 10, 50, 99.9] {
            let samples = track.trail(at: time, slice: nil)
            #expect(samples.count <= 37, "Dense recordings must never allocate an unbounded trail per frame")
            #expect(samples.allSatisfy { $0.time <= time && $0.time >= max(0, time - 0.6) - 0.000_001 })
        }
    }

    @Test
    func trailUsesTheSameCropZoomAndScreenMaskAsTheVideo() throws {
        var source = project()
        source.edits.crop = .init(x: 0.25, y: 0, width: 0.5, height: 1)
        source.edits.zoomClips = [.init(time: 0, duration: 2, scale: 2)]
        source.edits.background = .white
        source.edits.padding = 0.1
        source.edits.cornerRadius = 0.1
        let image = try render(source, at: 0.5)
        let trail = try RecordingMultitrackTestFixture.pixel(image, x: 160, y: 120)
        #expect(trail[1] > 40 && trail[2] > 80, "Source-space trails must remain aligned after crop and zoom: \(trail)")
        #expect(try RecordingMultitrackTestFixture.pixel(image, x: 3, y: 120) == [255, 255, 255],
            "The trail must stay inside the video mask and not draw over the background")
        source.pointers = [.init(time: 0, x: 0.05, y: 0.05), .init(time: 0.5, x: 0.1, y: 0.05)]
        let outside = try render(source, at: 0.5)
        source.edits.cursorTrail = false
        #expect(try pixels(outside) == pixels(render(source, at: 0.5)),
            "A trail fully outside the viewport must be discarded without a render failure")
    }

    @Test
    func trailSettingCanBeUndoneRedoneSavedAndReopened() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        try Data([1]).write(to: fixture.directory.appendingPathComponent("screen.mp4"))
        let model = try fixture.model()
        defer { model.shutdown() }
        var original = project()
        original.edits.cursorTrail = nil
        model.install(original, directory: fixture.directory)
        await model.previewTask?.value
        model.update { $0.edits.cursorTrail = true }
        await model.previewTask?.value
        #expect(model.project?.edits.cursorTrail == true && model.isDirty && model.canUndo)
        model.undo()
        await model.previewTask?.value
        #expect(model.project == original)
        model.redo()
        await model.previewTask?.value
        #expect(model.project?.edits.cursorTrail == true)
        try model.save()
        #expect(!model.isDirty)
        #expect(try fixture.store.load(from: fixture.directory) == model.project,
            "Reopening the project must preserve the edited trail setting")
        #expect(try fixture.files() == [ScreenRecordingProjectStore.manifestName, "screen.mp4"].sorted())
    }

    @Test(arguments: [false, true], [RecordingExportFormat.mp4, .gif])
    func previewPlaybackAndExportShareTheAnimatedTrail(_ multitrack: Bool, _ format: RecordingExportFormat) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let size = CGSize(width: 320, height: 240)
        _ = try await fixture.createVideo(size: size, colors: [.black])
        var source = project()
        if multitrack { source.timeline = .migrating(source) }
        let exporter = ScreenRecordingExporter()
        let preview = try await exporter.preview(project: source, directory: fixture.directory,
            sourceTime: 0.5, maximumSize: size)
        let item = try await exporter.playbackItem(project: source, directory: fixture.directory)
        let frames = try await RecordingMultitrackTestFixture.decode(item.asset, composition: item.videoComposition)
        let playback = try #require(frames.first { abs($0.0 - 0.5) < 0.001 }?.1)
        let previewPixel = try RecordingMultitrackTestFixture.pixel(preview, x: 160, y: 120)
        let playbackPixel = try RecordingMultitrackTestFixture.pixel(playback, x: 160, y: 120)
        #expect(previewPixel[2] > 80 && playbackPixel[2] > 80)
        let playbackTail = try #require(frames.first { abs($0.0 - 1.5) < 0.001 }?.1)
        #expect(try RecordingMultitrackTestFixture.pixel(playbackTail, x: 160, y: 120)[2] < 10,
            "Continuous playback must fade the same section of the trail when the pointer stops")

        let destination = fixture.root.appendingPathComponent("trail." + format.fileExtension)
        try await exporter.export(project: source, directory: fixture.directory, to: destination,
            configuration: .init(format: format, resolution: .source, frameRate: 12))
        let exported: CGImage
        let faded: CGImage
        if format == .gif {
            let images = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
            exported = try #require(CGImageSourceCreateImageAtIndex(images, 6, nil))
            faded = try #require(CGImageSourceCreateImageAtIndex(images, 18, nil))
        } else {
            let images = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
            images.requestedTimeToleranceBefore = .zero
            images.requestedTimeToleranceAfter = .zero
            exported = try await images.image(at: .init(seconds: 0.5, preferredTimescale: 600)).image
            faded = try await images.image(at: .init(seconds: 1.5, preferredTimescale: 600)).image
        }
        let exportedPixel = try RecordingMultitrackTestFixture.pixel(exported, x: 160, y: 120)
        #expect(exportedPixel[1] > 25 && exportedPixel[2] > 50, "The trail must survive the video and GIF encoders")
        #expect(try RecordingMultitrackTestFixture.pixel(faded, x: 160, y: 120)[2] < 10,
            "Exported animation must also fade completely after motion stops")
        #expect(exporter.progress == 1 && !exporter.isExporting)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
            == ["fixture.zisla-recording", "trail." + format.fileExtension].sorted(),
            "Export must remove all temporary staging files")
    }

    private func project() -> ScreenRecordingProject {
        var source = ScreenRecordingProject(name: "Trail", createdAt: Date(timeIntervalSince1970: 0),
            videoFile: "screen.mp4", duration: 2, width: 320, height: 240)
        source.edits.background = .none
        source.edits.clickEffects = false
        source.edits.cursorTrail = true
        source.pointers = [.init(time: 0, x: 0.1, y: 0.5), .init(time: 0.25, x: 0.4, y: 0.5),
            .init(time: 0.5, x: 0.7, y: 0.5)]
        return source
    }

    private func render(_ source: ScreenRecordingProject, at time: Double, slice: RecordingExportSlice? = nil) throws -> CGImage {
        let size = CGSize(width: 320, height: 240)
        let screen = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        return try RecordingExportRenderer(project: source, size: size)
            .image(screen: screen, camera: nil, sourceTime: time, slice: slice)
    }

    private func pixels(_ image: CGImage) throws -> Data {
        try #require(image.dataProvider?.data) as Data
    }
}
