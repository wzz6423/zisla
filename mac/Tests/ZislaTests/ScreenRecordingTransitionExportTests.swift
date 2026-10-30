import AVFoundation
import CoreImage
import ImageIO
import Testing
import ZislaCore
@testable import Zisla

// Each case opens AVAssetReaders and a hardware encoder. Parallel cases stall that pool until the suite timeout.
@Suite(.serialized) @MainActor
struct ScreenRecordingTransitionExportTests {
    @Test(.serialized, arguments: RecordingClipTransitionKind.allCases, [false, true])
    func explicitOverlappingTransitionsUseBothRetimedClipsInPreviewPlaybackMP4AndGIF(
        kind: RecordingClipTransitionKind, reversedStorage: Bool
    ) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo(colors: [.init(red: 1, green: 0, blue: 0)])
        _ = try await fixture.createVideo("incoming.mp4", colors: [.init(red: 0, green: 1, blue: 0),
                                                                .init(red: 0, green: 0, blue: 1)])
        _ = try fixture.createImage("background.png")
        var project = fixture.project()
        project.edits.padding = 0
        project.edits.cornerRadius = 0
        project.edits.shadow = 0
        let outgoing = RecordingMediaAsset(name: "Outgoing", file: "screen.mp4", kind: .video,
            duration: 2, width: 64, height: 48)
        let incoming = RecordingMediaAsset(name: "Incoming", file: "incoming.mp4", kind: .video,
            duration: 2, width: 64, height: 48)
        let background = RecordingMediaAsset(name: "Background", file: "background.png", kind: .image,
            duration: 2, width: 64, height: 48)
        let first = RecordingTimelineClip(id: "outgoing", trackID: "video", content: .video(outgoing.id),
            start: 0, sourceEnd: 1.25, audioEnabled: false)
        let second = RecordingTimelineClip(id: "incoming", trackID: "video", content: .video(incoming.id),
            start: 0.5, sourceStart: 1, sourceEnd: 1.5, speed: 0.5, layout: .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            audioEnabled: false, transition: .init(kind: kind, duration: 0.5))
        project.timeline = .init(assets: [outgoing, incoming, background], tracks: [.init(id: "background"), .init(id: "video")],
            clips: [.init(id: "background", trackID: "background", content: .image(background.id),
                          start: 0, sourceEnd: 1.5)] + (reversedStorage ? [second, first] : [first, second]))
        let original = project
        let exporter = ScreenRecordingExporter()
        for time in [0.25, 0.5, 0.75, 1.125, 1.375] {
            let scene = try await exporter.multitrackPreview(project: project, directory: fixture.directory, time: time)
            try expectTransition(scene.image(project: project), at: time)
        }
        let item = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let playback = try await RecordingMultitrackTestFixture.decode(item.asset, composition: item.videoComposition)
        #expect(playback.count == 45)
        for time in [0.25, 0.5, 0.75, 1.125, 1.375] {
            let frame = try #require(playback.min { abs($0.0 - time) < abs($1.0 - time) })
            try expectTransition(frame.1, at: frame.0)
        }
        for format in [RecordingExportFormat.mp4, .gif] {
            let destination = fixture.root.appendingPathComponent("transition." + format.fileExtension)
            try await exporter.export(project: project, directory: fixture.directory, to: destination,
                configuration: .init(format: format, resolution: .source, frameRate: 8))
            let frames: [(Double, CGImage)]
            if format == .mp4 {
                frames = try await RecordingMultitrackTestFixture.decode(AVURLAsset(url: destination))
            } else {
                let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
                frames = try (0..<CGImageSourceGetCount(source)).map {
                    (Double($0) / 8, try #require(CGImageSourceCreateImageAtIndex(source, $0, nil)))
                }
            }
            #expect(frames.count == 12)
            for index in [2, 4, 6, 9, 11] { try expectTransition(frames[index].1, at: frames[index].0) }
        }
        #expect(project == original && project.outputDuration == 1.5,
            "Adding a transition must preserve clip positions, saved effect duration and timeline duration")
        #expect(try fixture.files() == ["background.png", "incoming.mp4", "screen.mp4"])
    }

    @Test
    func transitionIndexUsesOnlyTheImmediateOverlappingVisualPredecessorOnTheSameVisibleTrack() {
        let first = RecordingTimelineClip(id: "first", trackID: "top", content: .video(UUID()), start: 0, sourceEnd: 10)
        let nearest = RecordingTimelineClip(id: "nearest", trackID: "top", content: .image(UUID()), start: 1, sourceEnd: 2)
        var incoming = RecordingTimelineClip(id: "incoming", trackID: "top", content: .video(UUID()),
            start: 2, sourceEnd: 2, transition: .init(kind: .dissolve))
        let other = RecordingTimelineClip(id: "other", trackID: "other", content: .video(UUID()), start: 1.5, sourceEnd: 5)
        let audio = RecordingTimelineClip(id: "audio", trackID: "top", content: .audio(UUID()), start: 1.75, sourceEnd: 3)
        var timeline = RecordingMultitrackTimeline(tracks: [.init(id: "top"), .init(id: "other")],
            clips: [incoming, other, audio, nearest, first])
        #expect(RecordingTimelineClipIndex(timeline).transitionSource(for: incoming.id) == nearest,
            "Timeline storage order, other tracks and audio must not change the preceding visual clip")
        timeline.clips[3].sourceEnd = 0.5
        #expect(RecordingTimelineClipIndex(timeline).transitionSource(for: incoming.id) == nil,
            "A nonoverlapping immediate predecessor must not fall back to an older overlapping clip")
        timeline.tracks[0].isHidden = true
        #expect(RecordingTimelineClipIndex(timeline).transitionSource(for: incoming.id) == nil)
        timeline.tracks[0].isHidden = false
        timeline.clips[3] = nearest
        incoming.transition = nil
        timeline.clips[0] = incoming
        #expect(RecordingTimelineClipIndex(timeline).transitionSource(for: incoming.id) == nearest,
            "Inspector availability and the renderer must use the same preceding clip before an effect is selected")
    }

    @Test(.serialized, arguments: [false, true])
    func explicitTextAnimationsKeepTheSameRevealAndFadeInPreviewPlaybackMP4AndGIF(_ caption: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let size = CGSize(width: 256, height: 192)
        _ = try fixture.createImage("black.png", size: size, color: .black)
        var project = fixture.project()
        project.width = 256
        project.height = 192
        project.videoFile = ""
        project.edits.segments = []
        let text = "中👩🏽‍💻文AB"
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 2,
            x: 0.1, y: 0.1, endX: 0.9, endY: 0.8, text: text,
            color: .init(red: 1, green: 1, blue: 1), fontSize: 0.16)
        let subtitle = RecordingCaption(start: 0, end: 2, text: text,
            layout: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.7), fontSize: 0.16)
        project.edits.annotations = caption ? [] : [annotation]
        project.captions = caption ? [subtitle] : []
        let background = RecordingMediaAsset(name: "Black", file: "black.png", kind: .image,
            duration: 2, width: 256, height: 192)
        let animatedText = RecordingTimelineClip(id: "animated-text", trackID: "text",
            content: caption ? .caption(subtitle.id) : .annotation(annotation.id), start: 0, sourceEnd: 2,
            entranceAnimation: .init(kind: .typewriter, duration: 1), exitAnimation: .init(kind: .fade, duration: 0.5))
        project.timeline = .init(assets: [background], tracks: [.init(id: "background"), .init(id: "text")], clips: [
            .init(trackID: "background", content: .image(background.id), start: 0, sourceEnd: 2), animatedText,
        ])
        try fixture.store.save(project, in: fixture.directory)
        project = try fixture.store.load(from: fixture.directory)
        let original = project
        let exporter = ScreenRecordingExporter()
        let times = [0.0, 0.25, 0.5, 0.75, 1.25, 1.75, 1.875]
        var expected: [[UInt8]] = []
        var brightCounts: [Int] = []
        for time in times {
            let scene = try await exporter.multitrackPreview(project: project, directory: fixture.directory, time: time)
            let pixels = try RecordingImageFixture.pixels(scene.image(project: project))
            expected.append(pixels.bytes)
            brightCounts.append(stride(from: 0, to: pixels.bytes.count, by: 4).filter {
                pixels.bytes[$0] > 170 && pixels.bytes[$0 + 1] > 170 && pixels.bytes[$0 + 2] > 170
            }.count)
        }
        #expect(brightCounts[0] == 0 && brightCounts[1] > 100)
        #expect(brightCounts[2] >= brightCounts[1] && brightCounts[3] > brightCounts[2]
            && brightCounts[4] > brightCounts[3], "Typing must reveal additional complete characters before the exit")
        #expect(brightCounts[5] < brightCounts[4] / 4 && brightCounts[6] <= brightCounts[5],
            "The configured exit fade must reduce the completed text after the reveal")
        let item = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let playback = try await RecordingMultitrackTestFixture.decode(item.asset, composition: item.videoComposition)
        #expect(playback.count == 60)
        for (index, time) in times.enumerated() {
            let frame = try #require(playback.min { abs($0.0 - time) < abs($1.0 - time) })
            try expectTextPixels(frame.1, toMatch: expected[index])
        }
        for format in [RecordingExportFormat.mp4, .gif] {
            let destination = fixture.root.appendingPathComponent("animated-text." + format.fileExtension)
            try await exporter.export(project: project, directory: fixture.directory, to: destination,
                configuration: .init(format: format, resolution: .source, frameRate: 8))
            let frames: [(Double, CGImage)]
            if format == .mp4 {
                frames = try await RecordingMultitrackTestFixture.decode(AVURLAsset(url: destination))
            } else {
                let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
                frames = try (0..<CGImageSourceGetCount(source)).map {
                    (Double($0) / 8, try #require(CGImageSourceCreateImageAtIndex(source, $0, nil)))
                }
            }
            #expect(frames.count == 16)
            for (index, time) in times.enumerated() {
                try expectTextPixels(frames[Int(time * 8)].1, toMatch: expected[index])
            }
        }
        #expect(project == original && project.outputDuration == 2)
        #expect(try fixture.store.load(from: fixture.directory) == original)
        #expect(try fixture.files() == ["black.png", "project.json"])
    }

    private func expectTextPixels(_ image: CGImage, toMatch expected: [UInt8]) throws {
        let actual = try RecordingImageFixture.pixels(image).bytes
        try #require(actual.count == expected.count)
        let difference = zip(actual, expected).enumerated().reduce(0) { sum, entry in
            entry.offset % 4 == 3 ? sum : sum + abs(Int(entry.element.0) - Int(entry.element.1))
        }
        #expect(Double(difference) / Double(actual.count / 4 * 3) < 4,
            "Decoded animation frames must retain the preview's character reveal and exit timing within codec tolerance")
    }

    @Test(arguments: RecordingClipAnimationKind.allCases.filter { $0 != .typewriter })
    func entranceAnimationsPreserveAnOffCenterClipAndItsNamedSlideDirection(_ kind: RecordingClipAnimationKind) throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createImage("red.png", size: .init(width: 160, height: 120), color: .red)
        var project = fixture.project()
        project.width = 160
        project.height = 120
        let asset = RecordingMediaAsset(name: "Red", file: "red.png", kind: .image,
            duration: 2, width: 160, height: 120)
        let clip = RecordingTimelineClip(trackID: "visual", content: .image(asset.id), start: 0, sourceEnd: 2,
            layout: .init(x: 0.625, y: 0.625, width: 0.25, height: 0.25),
            entranceAnimation: .init(kind: kind, duration: 1))
        project.timeline = .init(assets: [asset], tracks: [.init(id: "visual")], clips: [clip])
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory,
            size: .init(width: 160, height: 120))
        let pixels = try RecordingImageFixture.pixels(renderer.image(frames: [:], at: 0.5))
        let center: CGPoint
        switch kind {
        case .slideLeft: center = .init(x: 40, y: 30)
        case .slideRight: center = .init(x: 200, y: 30)
        case .slideUp: center = .init(x: 120, y: 90)
        case .slideDown: center = .init(x: 120, y: -30)
        case .fade, .scale: center = .init(x: 120, y: 30)
        case .typewriter: Issue.record("Typewriter applies only to text"); return
        }
        let bounds = CGRect(x: center.x - (kind == .scale ? 15 : 20),
            y: center.y - (kind == .scale ? 11.25 : 15),
            width: kind == .scale ? 30 : 40, height: kind == .scale ? 22.5 : 30)
            .intersection(CGRect(x: 0, y: 0, width: 160, height: 120))
        let red = (0..<120).flatMap { y in
            (0..<160).compactMap { x -> CGPoint? in
                let value = pixels.pixel(x: x, y: y)
                return value[0] > 40 && value[1] < 10 && value[2] < 10
                    ? CGPoint(x: Double(x) + 0.5, y: 120 - Double(y) - 0.5) : nil
            }
        }
        if bounds.isNull { #expect(red.isEmpty) }
        else {
            #expect(red.count > 100)
            #expect(red.allSatisfy { bounds.insetBy(dx: -1, dy: -1).contains($0) },
                "The chosen slide direction and center-based scale must preserve the saved off-center layout")
        }
    }

    @Test(arguments: [RecordingClipTransitionKind.slideLeft, .slideRight, .zoom])
    func transitionsMoveOrScaleBothSourcesInTheChosenDirection(_ kind: RecordingClipTransitionKind) throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createImage("red.png", color: .red)
        _ = try fixture.createImage("blue.png", color: .blue)
        var project = fixture.project()
        let red = RecordingMediaAsset(name: "Red", file: "red.png", kind: .image, duration: 3, width: 64, height: 48)
        let blue = RecordingMediaAsset(name: "Blue", file: "blue.png", kind: .image, duration: 3, width: 64, height: 48)
        let outgoing = RecordingTimelineClip(trackID: "visual", content: .image(red.id), start: 0, sourceEnd: 3,
            layout: kind == .zoom ? .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5) : .init(x: 0, y: 0, width: 1, height: 1))
        let incoming = RecordingTimelineClip(trackID: "visual", content: .image(blue.id), start: 1, sourceEnd: 2,
            transition: .init(kind: kind, duration: 1))
        project.timeline = .init(assets: [red, blue], tracks: [.init(id: "visual")], clips: [outgoing, incoming])
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory,
            size: .init(width: 64, height: 48))
        let pixels = try RecordingImageFixture.pixels(renderer.image(frames: [:], at: 1.5))
        if kind == .zoom {
            #expect(pixels.pixel(x: 2, y: 24)[0] < 10 && pixels.pixel(x: 2, y: 24)[2] < 10,
                "The scaled incoming source must leave the outside of its zoom footprint visible")
            #expect(pixels.pixel(x: 14, y: 24)[0] > 60 && pixels.pixel(x: 14, y: 24)[2] > 60,
                "The outgoing source must scale out around its center while both sources are mixed")
        } else {
            let left = pixels.pixel(x: 8, y: 24)
            let right = pixels.pixel(x: 56, y: 24)
            #expect((kind == .slideLeft ? left[0] : right[0]) > 240)
            #expect((kind == .slideLeft ? right[2] : left[2]) > 240,
                "A left push brings the next source from the right; a right push brings it from the left")
        }
    }

    @Test(arguments: [false, true])
    func aHiddenOrEditedTransitionPredecessorDoesNotHideTheIncomingImage(_ caption: Bool) throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createImage("blue.png", color: .blue)
        var project = fixture.project()
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 3, text: "Editing")
        let subtitle = RecordingCaption(start: 0, end: 3, text: "Hidden")
        project.edits.annotations = caption ? [] : [annotation]
        project.captions = caption ? [subtitle] : []
        project.edits.showCaptions = !caption
        let blue = RecordingMediaAsset(name: "Blue", file: "blue.png", kind: .image, duration: 2, width: 64, height: 48)
        project.timeline = .init(assets: [blue], tracks: [.init(id: "mixed")], clips: [
            .init(trackID: "mixed", content: caption ? .caption(subtitle.id) : .annotation(annotation.id),
                start: 0, sourceEnd: 3),
            .init(trackID: "mixed", content: .image(blue.id), start: 0.5, sourceEnd: 2,
                transition: .init(kind: .dissolve, duration: 0.5)),
        ])
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory,
            size: .init(width: 64, height: 48))
        let image = try renderer.image(frames: [:], at: 1.5, editingText: caption ? nil : .annotation(annotation.id))
        #expect(try RecordingImageFixture.pixels(image).pixel(x: 32, y: 24) == [0, 0, 255, 255],
            "A predecessor excluded by caption visibility or text editing must not participate in the transition chain")
    }

    private func expectTransition(_ image: CGImage, at time: Double) throws {
        let center = try RecordingMultitrackTestFixture.pixel(image, x: 32, y: 24)
        let corner = try RecordingMultitrackTestFixture.pixel(image, x: 2, y: 2)
        if time <= 0.5 {
            #expect(center[0] > 215 && center[1] < 40 && center[2] < 40,
                "Before and at transition start, the outgoing source must still be visible")
        } else if time >= 1 {
            #expect(center[2] > 215 && center[0] < 40 && center[1] < 40,
                "The incoming clip must use its trimmed source range and remain after the effect completes")
            #expect(corner[1] > 215 && corner[0] < 40 && corner[2] < 40,
                "Completed transitions must reveal lower tracks around a small incoming layout without reviving the outgoing clip")
        } else {
            var pixels: [[UInt8]] = []
            for y in stride(from: 0, through: 47, by: 4) {
                for x in stride(from: 0, through: 63, by: 4) {
                    pixels.append(try RecordingMultitrackTestFixture.pixel(image, x: x, y: y))
                }
            }
            #expect(pixels.contains { $0[0] > 60 } && pixels.contains { $0[2] > 60 },
                "A real transition must display both source clips rather than fading one clip to the background")
        }
    }
}
