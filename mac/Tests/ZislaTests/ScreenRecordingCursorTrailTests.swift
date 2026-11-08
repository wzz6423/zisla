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
        #expect(trail[0] > 40 && trail[0] == trail[1] && trail[1] == trail[2],
            "Moving the cursor must leave a visible white trail with no color tint: \(trail)")
    }

    @Test(arguments: [RecordingColor(red: 1, green: 0, blue: 0),
        .init(red: 0, green: 1, blue: 0), .init(red: 1, green: 0.5, blue: 0.2)])
    func chosenTrailColorControlsTheRenderedStroke(_ color: RecordingColor) throws {
        var source = project()
        source.edits.cursorTrailColor = color
        let pixel = try RecordingMultitrackTestFixture.pixel(render(source, at: 0.5), x: 160, y: 120)
        if color.red == 0 {
            #expect(pixel[0] == 0 && pixel[1] > 40 && pixel[2] == 0,
                "A chosen green trail must use the saved RGB color: \(pixel)")
        } else if color.green == 0 {
            #expect(pixel[0] > 40 && pixel[1] == 0 && pixel[2] == 0,
                "A chosen red trail must use the saved RGB color: \(pixel)")
        } else {
            #expect(pixel[0] > pixel[1] && pixel[1] > pixel[2] && pixel[2] > 0,
                "A mixed trail must retain the chosen channel proportions: \(pixel)")
        }
    }

    @Test(arguments: [RecordingColor(red: 0, green: 0, blue: 0), .init(red: 0.3, green: 0.3, blue: 0.3)])
    func blackAndGrayTrailChoicesRemainVisibleOnALightVideo(_ color: RecordingColor) throws {
        var source = project()
        source.edits.cursorTrailColor = color
        let image = try render(source, at: 0.5, screenColor: .white)
        let pixel = try RecordingMultitrackTestFixture.pixel(image, x: 160, y: 120)
        #expect(pixel[0] < 240 && pixel[0] == pixel[1] && pixel[1] == pixel[2],
            "Dark trail choices must remain neutral and visibly darken a light source: \(pixel)")
        #expect(try RecordingMultitrackTestFixture.pixel(image, x: 160, y: 80) == [255, 255, 255])
    }

    @Test
    func defaultTrailIsThinAndGraduallyTapersTowardItsOldestEnd() throws {
        let size = CGSize(width: 1_280, height: 960)
        let thin = try render(project(), at: 0.5, size: size)
        #expect(try visibleTrailRows(thin, x: 640, y: 480) <= 4,
            "The default trail must occupy at most four antialiased rows at this output size")
        var source = project()
        source.edits.cursorSize = 4
        let tapered = try render(source, at: 0.5, size: size)
        let widths = try [256, 384, 512, 640, 768].map { try visibleTrailRows(tapered, x: $0, y: 480) }
        #expect(widths[0] > 0 && widths[0] < widths[2] && widths[2] < widths[4],
            "The oldest tail must be thinnest, with a wider middle and head: \(widths)")
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 <= $1 && $1 - $0 <= 2 },
            "Width must increase gradually without an abrupt jump along the trail: \(widths)")
    }

    @Test(arguments: [false, true])
    func fastRightAngleMotionFormsARoundedContinuousTrailInsteadOfASharpCorner(_ pausesAtTurn: Bool) throws {
        var source = project()
        source.pointers = [.init(time: 0, x: 0.2, y: 0.65), .init(time: 0.39, x: 0.2, y: 0.65),
            .init(time: 0.4, x: 0.65, y: 0.65), .init(time: 0.41, x: 0.65, y: 0.2)]
        if pausesAtTurn {
            source.pointers = [.init(time: 0, x: 0.2, y: 0.65), .init(time: 0.3, x: 0.65, y: 0.65),
                .init(time: 0.4, x: 0.65, y: 0.65), .init(time: 0.6, x: 0.65, y: 0.2)]
        }
        let image = try render(source, at: 0.6, size: .init(width: 1_280, height: 960))
        let inside = try RecordingMultitrackTestFixture.pixel(image, x: 760, y: 570)
        let sharp = try RecordingMultitrackTestFixture.pixel(image, x: 831, y: 624)
        if !pausesAtTurn {
            #expect(inside.allSatisfy { $0 > 70 },
                "Sparse fast motion must round the inside of its turn instead of drawing two straight legs: \(inside)")
            let arc = try RecordingMultitrackTestFixture.pixel(image, x: 670, y: 610)
            #expect(arc[0] > 70, "The middle of the rounded bend must follow a smooth arc rather than two straight chords: \(arc)")
            #expect(sharp == [0, 0, 0], "The old right-angle vertex must not remain as a pointed corner: \(sharp)")
        } else {
            let knee = try RecordingMultitrackTestFixture.pixel(image, x: 831, y: 623)
            let arriving = try RecordingMultitrackTestFixture.pixel(image, x: 825, y: 624)
            let departing = try RecordingMultitrackTestFixture.pixel(image, x: 832, y: 615)
            #expect(knee[0] > 30 && knee[0] <= max(arriving[0], departing[0]) + 30,
                "A pause at the turn must keep its join connected without turning duplicate points into a bright bead")
        }
        #expect(try RecordingMultitrackTestFixture.pixel(image, x: 850, y: 650) == [0, 0, 0],
            "Smoothing must stay within the recorded turn and never overshoot its control points")
    }

    @Test(arguments: [false, true])
    func fractionalDiagonalMotionHasNoVisibleSeamsOrBrightBeads(_ pauses: Bool) throws {
        var source = project()
        source.pointers = [.init(time: 0, x: 0.17, y: 0.233), .init(time: 0.6, x: 0.83, y: 0.767)]
        if pauses {
            source.pointers = [.init(time: 0, x: 0.17, y: 0.233), .init(time: 0.25, x: 0.5, y: 0.5),
                .init(time: 0.35, x: 0.5, y: 0.5), .init(time: 0.6, x: 0.83, y: 0.767)]
        }
        let image = try render(source, at: 0.6, size: .init(width: 1_280, height: 960))
        let bytes = try pixels(image)
        let energies = (450..<850).map { x in
            let y = Int((0.233 + (Double(x) / 1_280 - 0.17) * (0.767 - 0.233) / (0.83 - 0.17)) * 960)
            return ((y - 5)...(y + 5)).map { Int(bytes[($0 * image.width + x) * 4]) }.reduce(0, +)
        }
        let peaks = (1..<(energies.count - 1)).map { index -> Int in
            let neighbors = energies[index - 1] + energies[index + 1]
            return (neighbors + energies[index]) / 3
        }
        #expect(peaks.allSatisfy { $0 > 30 }, "A thin diagonal trail must remain connected across sample boundaries")
        let steps = zip(peaks, peaks.dropFirst()).map { abs($1 - $0) }
        let largestStep = steps.max()!
        let largestIndex = steps.firstIndex(of: largestStep)!
        #expect(largestStep <= 30,
            "Adjacent pixels must not abruptly darken at a seam or brighten into overlapping beads: \(largestStep), x=\(451 + largestIndex), peaks=\(Array(peaks[max(0, largestIndex - 4)...min(peaks.count - 1, largestIndex + 5)]))")
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
        let size = CGSize(width: 1_280, height: 960)
        source.edits.cursorSize = 4
        let large = try render(source, at: 0.5, size: size)
        source.edits.cursorSize = 0.5
        let small = try render(source, at: 0.5, size: size)
        #expect(try visibleTrailRows(large, x: 640, y: 480) > visibleTrailRows(small, x: 640, y: 480),
            "The trail width must follow cursor size without adding another setting")
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
        let nearHead = try [0.5, 0.8, 1.2].map {
            try RecordingMultitrackTestFixture.pixel(render(source, at: $0), x: 222, y: 119)[0]
        }
        #expect(nearHead[0] > nearHead[1] && nearHead[1] > nearHead[2] && nearHead[2] == 0,
            "Repeated stationary samples must not renew the trail brightness beside its stopped head: \(nearHead)")
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
        #expect(trail[0] > 40 && trail[0] == trail[1] && trail[1] == trail[2],
            "The thin white trail must remain aligned after crop and zoom: \(trail)")
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
        let color = RecordingColor(red: 0.3, green: 0.7, blue: 0.2)
        model.update { $0.edits.cursorTrailColor = color }
        await model.previewTask?.value
        #expect(model.project?.edits.cursorTrailColor == color)
        model.undo()
        await model.previewTask?.value
        #expect(model.project?.edits.cursorTrailColor == nil)
        model.redo()
        await model.previewTask?.value
        model.update { $0.edits.cursorTrail = false }
        await model.previewTask?.value
        model.update { $0.edits.cursorTrail = true }
        await model.previewTask?.value
        #expect(model.project?.edits.cursorTrailColor == color,
            "Turning the trail off and on must retain its selected color")
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
        for pixel in [previewPixel, playbackPixel] {
            #expect(pixel.allSatisfy { $0 > 40 } && pixel.max()! - pixel.min()! <= 10,
                "Preview and playback must retain a visible white trail: \(pixel)")
        }
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
        #expect(exportedPixel.allSatisfy { $0 > 25 } && exportedPixel.max()! - exportedPixel.min()! <= 10,
            "The thin white trail must survive the video and GIF encoders: \(exportedPixel)")
        #expect(try RecordingMultitrackTestFixture.pixel(faded, x: 160, y: 120)[2] < 10,
            "Exported animation must also fade completely after motion stops")
        #expect(exporter.progress == 1 && !exporter.isExporting)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
            == ["fixture.zisla-recording", "trail." + format.fileExtension].sorted(),
            "Export must remove all temporary staging files")
    }

    @Test(arguments: [false, true], [RecordingColor(red: 1, green: 0, blue: 0),
        .init(red: 0, green: 1, blue: 0), .init(red: 1, green: 1, blue: 0)])
    func previewPlaybackAndExportRetainTheChosenTrailColor(_ multitrack: Bool, _ color: RecordingColor) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let size = CGSize(width: 320, height: 240)
        _ = try await fixture.createVideo(size: size, colors: [.black])
        var source = project()
        source.edits.cursorTrailColor = color
        if multitrack { source.timeline = .migrating(source) }
        let exporter = ScreenRecordingExporter()
        let preview = try await exporter.preview(project: source, directory: fixture.directory,
            sourceTime: 0.5, maximumSize: size)
        let item = try await exporter.playbackItem(project: source, directory: fixture.directory)
        let frames = try await RecordingMultitrackTestFixture.decode(item.asset, composition: item.videoComposition)
        let playback = try #require(frames.first { abs($0.0 - 0.5) < 0.001 }?.1)
        try expectColor(preview, color: color)
        try expectColor(playback, color: color)
        for format in [RecordingExportFormat.mp4, .gif] {
            let destination = fixture.root.appendingPathComponent("chosen." + format.fileExtension)
            try await exporter.export(project: source, directory: fixture.directory, to: destination,
                configuration: .init(format: format, resolution: .source, frameRate: 12))
            let exported: CGImage
            if format == .gif {
                let images = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
                exported = try #require(CGImageSourceCreateImageAtIndex(images, 6, nil))
            } else {
                let images = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
                images.requestedTimeToleranceBefore = .zero
                images.requestedTimeToleranceAfter = .zero
                exported = try await images.image(at: .init(seconds: 0.5, preferredTimescale: 600)).image
            }
            try expectColor(exported, color: color)
            #expect(exporter.progress == 1 && !exporter.isExporting)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
            == ["fixture.zisla-recording", "chosen.mp4", "chosen.gif"].sorted(),
            "Choosing a trail color must not leak export staging files")
    }

    private func expectColor(_ image: CGImage, color: RecordingColor) throws {
        let pixel = try RecordingMultitrackTestFixture.pixel(image, x: 160, y: 120)
        for (channel, selected) in zip(pixel, [color.red, color.green, color.blue]) {
            #expect(selected == 0 ? channel < 15 : channel > 25,
                "Preview, playback, and export must preserve the chosen trail channels: \(pixel), \(color)")
        }
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

    private func render(_ source: ScreenRecordingProject, at time: Double, slice: RecordingExportSlice? = nil,
                        size: CGSize = .init(width: 320, height: 240), screenColor: CIColor = .black) throws -> CGImage {
        let screen = CIImage(color: screenColor).cropped(to: CGRect(origin: .zero, size: size))
        return try RecordingExportRenderer(project: source, size: size)
            .image(screen: screen, camera: nil, sourceTime: time, slice: slice)
    }

    private func pixels(_ image: CGImage) throws -> Data {
        try #require(image.dataProvider?.data) as Data
    }

    private func visibleTrailRows(_ image: CGImage, x: Int, y: Int) throws -> Int {
        try ((y - 12)...(y + 12)).filter {
            try RecordingMultitrackTestFixture.pixel(image, x: x, y: $0)[2] > 5
        }.count
    }
}
