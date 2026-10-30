import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Testing
import ZislaCore
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingMultitrackMediaTests {
    @Test func mixedPortraitAndLandscapeLayersFitTheirOwnAspectRatioAcrossPreviewPlaybackMP4AndGIF() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo(colors: [.init(red: 1, green: 0, blue: 0)])
        _ = try await fixture.createVideo("portrait.mp4", size: .init(width: 24, height: 48),
            colors: [.init(red: 0, green: 1, blue: 0)])
        var project = fixture.project()
        var timeline = RecordingMultitrackTimeline.migrating(project)
        let portrait = RecordingMediaAsset(name: "Portrait", file: "portrait.mp4", kind: .video,
            duration: 2, width: 24, height: 48)
        timeline.assets.append(portrait)
        let top = timeline.addTrack(.video)
        timeline.tracks[timeline.tracks.count - 1].kind = .audio
        timeline.clips.append(.init(trackID: top, content: .video(portrait.id), start: 0, sourceEnd: 1))
        project.timeline = timeline
        let exporter = ScreenRecordingExporter()
        let preview = try await exporter.multitrackPreview(project: project, directory: fixture.directory, time: 0.5)
        try expectPortraitOverLandscape(preview.image(project: project))
        let playerItem = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let playback = try await RecordingMultitrackTestFixture.decode(playerItem.asset, composition: playerItem.videoComposition)
        #expect(playback.count == 60)
        try expectPortraitOverLandscape(try #require(playback.first { abs($0.0 - 0.5) < 0.001 }?.1))
        #expect(try RecordingMultitrackTestFixture.pixel(try #require(playback.first { abs($0.0 - 1.5) < 0.001 }?.1), x: 32, y: 24)[0] > 220)
        for format in [RecordingExportFormat.mp4, .gif] {
            let destination = fixture.root.appendingPathComponent("mixed." + format.rawValue)
            try await exporter.export(project: project, directory: fixture.directory, to: destination,
                configuration: .init(format: format, resolution: .source, frameRate: 4))
            if format == .mp4 {
                let decoded = try await RecordingMultitrackTestFixture.decode(AVURLAsset(url: destination))
                #expect(decoded.count == 8)
                try expectPortraitOverLandscape(decoded[2].1)
                #expect(try RecordingMultitrackTestFixture.pixel(decoded[6].1, x: 32, y: 24)[0] > 220)
            } else {
                let gif = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
                #expect(CGImageSourceGetCount(gif) == 8)
                try expectPortraitOverLandscape(try #require(CGImageSourceCreateImageAtIndex(gif, 2, nil)))
                #expect(try RecordingMultitrackTestFixture.pixel(try #require(CGImageSourceCreateImageAtIndex(gif, 6, nil)), x: 32, y: 24)[0] > 220)
            }
        }
        timeline.tracks.reverse()
        project.timeline = timeline
        let reordered = try await exporter.multitrackPreview(project: project, directory: fixture.directory, time: 0.5)
        #expect(try RecordingMultitrackTestFixture.pixel(reordered.image(project: project), x: 32, y: 24)[0] > 220,
            "Reordering tracks must change the topmost rendered layer")
        timeline.tracks[1].isHidden = true
        project.timeline = timeline
        let hidden = try await exporter.multitrackPreview(project: project, directory: fixture.directory, time: 0.5)
        #expect(try RecordingMultitrackTestFixture.pixel(hidden.image(project: project), x: 32, y: 24)[1] > 220)
    }

    @Test func oneLegacyAudioTrackMixesVideoImageTextCaptionAndAudioAcrossPreviewPlaybackMP4AndGIF() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo(colors: [.init(red: 1, green: 0, blue: 0)])
        _ = try fixture.createImage(color: .init(red: 0, green: 1, blue: 0))
        _ = try fixture.createTone()
        var project = fixture.project()
        project.edits.padding = 0
        project.edits.cornerRadius = 0
        project.edits.shadow = 0
        project.edits.annotations = [.init(kind: .text, start: 0, end: 2, x: 0.02, y: 0.02,
            endX: 0.8, endY: 0.3, text: "TEXT", color: .init(red: 0, green: 0, blue: 1), fontSize: 0.2)]
        project.captions = [.init(start: 0, end: 2, text: "CAP", layout: .init(x: 0.1, y: 0.6, width: 0.8, height: 0.4), fontSize: 0.15)]
        let image = RecordingMediaAsset(name: "Image", file: "picture.png", kind: .image, duration: 2, width: 64, height: 48)
        let audio = RecordingMediaAsset(name: "Sound", file: "tone.wav", kind: .audio, duration: 2)
        let source = RecordingMediaAsset(id: project.id, name: project.name, file: project.videoFile,
            kind: .video, duration: 2, width: 64, height: 48)
        project.timeline = .init(assets: [source, image, audio], tracks: [.init(id: "mixed", kind: .audio)], clips: [
            .init(id: "video", trackID: "mixed", content: .video(source.id), start: 0, sourceEnd: 2),
            .init(id: "image", trackID: "mixed", content: .image(image.id), start: 0, sourceEnd: 2,
                layout: .init(x: 0.7, y: 0.3, width: 0.2, height: 0.2)),
            .init(id: "text", trackID: "mixed", content: .annotation(project.edits.annotations![0].id), start: 0, sourceEnd: 2),
            .init(id: "caption", trackID: "mixed", content: .caption(project.captions[0].id), start: 0, sourceEnd: 2),
            .init(id: "audio", trackID: "mixed", content: .audio(audio.id), start: 0, sourceEnd: 2),
        ])
        try project.validate()
        let exporter = ScreenRecordingExporter()
        let scene = try await exporter.multitrackPreview(project: project, directory: fixture.directory, time: 0.5)
        try expectMixedContent(scene.image(project: project))
        let item = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let playback = try await RecordingMultitrackTestFixture.decode(item.asset, composition: item.videoComposition)
        #expect(playback.count == 60)
        #expect(try await item.asset.loadTracks(withMediaType: .audio).count == 1)
        try expectMixedContent(try #require(playback.first { abs($0.0 - 0.5) < 0.001 }?.1))
        for format in [RecordingExportFormat.mp4, .gif] {
            let destination = fixture.root.appendingPathComponent("mixed-content." + format.rawValue)
            try await exporter.export(project: project, directory: fixture.directory, to: destination,
                configuration: .init(format: format, resolution: .source, frameRate: 4))
            if format == .mp4 {
                let asset = AVURLAsset(url: destination)
                let frames = try await RecordingMultitrackTestFixture.decode(asset)
                #expect(frames.count == 8)
                #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
                try expectMixedContent(frames[2].1)
            } else {
                let gif = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
                #expect(CGImageSourceGetCount(gif) == 8)
                try expectMixedContent(try #require(CGImageSourceCreateImageAtIndex(gif, 2, nil)))
            }
        }
        #expect(try fixture.files() == ["picture.png", "screen.mp4", "tone.wav"])
    }

    @Test func repeatedRetimedSourceCutsAndShortCameraTracksRenderEveryBlankIntervalWithoutStaleFrames() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        _ = try await fixture.createVideo("camera.mp4", duration: 0.5, colors: [.init(red: 0, green: 1, blue: 0)])
        var project = fixture.project()
        project.cameraFile = "camera.mp4"
        project.edits.cameraRound = false
        project.edits.cameraCornerRadius = 0
        project.edits.cameraPosition = .topLeft
        project.edits.cameraSize = 0.4
        project.edits.background = .none
        project.edits.backgroundColor = .init(red: 0, green: 0, blue: 0)
        project.edits.segments = [.init(start: 0, end: 0.5, speed: 2), .init(start: 1, end: 2, speed: 2),
                                  .init(start: 0, end: 0.5)]
        var timeline = RecordingMultitrackTimeline.migrating(project)
        timeline.clips[0].start = 0.25
        timeline.clips[1].start = 0.75
        timeline.clips[2].start = 1.5
        project.timeline = timeline
        let exporter = ScreenRecordingExporter()
        for time in [0.125, 0.375, 0.625, 0.875, 1.375, 1.625, 1.875] {
            let scene = try await exporter.multitrackPreview(project: project, directory: fixture.directory, time: time)
            try expectRepeatedCut(scene.image(project: project), at: time)
        }
        let item = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let frames = try await RecordingMultitrackTestFixture.decode(item.asset, composition: item.videoComposition)
        #expect(frames.count == 60)
        for (time, image) in frames where time > 0.01 {
            try expectRepeatedCut(image, at: time)
        }
        let destination = fixture.root.appendingPathComponent("cuts.mp4")
        try await exporter.export(project: project, directory: fixture.directory, to: destination,
            configuration: .init(resolution: .source, frameRate: 8))
        let exported = try await RecordingMultitrackTestFixture.decode(AVURLAsset(url: destination))
        #expect(exported.count == 16)
        for (time, image) in exported { try expectRepeatedCut(image, at: time) }
        #expect(try fixture.files() == ["camera.mp4", "screen.mp4"])
    }

    @Test func aTextOnlyTimelineHasATinyCarrierAndDeletesItWhenThePlaybackInstructionIsReleased() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        var project = fixture.project()
        project.videoFile = ""
        project.edits.segments = []
        project.edits.annotations = [.init(kind: .rectangle, start: 0, end: 1,
            x: 0.2, y: 0.2, endX: 0.8, endY: 0.8, color: .init(red: 0, green: 1, blue: 0), lineWidth: 0.05)]
        project.timeline = .init(tracks: [.init(id: "text", kind: .text)], clips: [
            .init(trackID: "text", content: .annotation(project.edits.annotations![0].id), start: 0, sourceEnd: 1),
        ])
        var media: RecordingMultitrackMedia? = try await RecordingMultitrackMedia.prepare(project: project, directory: fixture.directory)
        weak var released = media
        #expect(media?.videoTracks.isEmpty == true && media?.composition.tracks.isEmpty == true)
        try await media?.addPlaybackClock()
        let clock = try #require(media?.playbackClockTrackID)
        let segment = try #require(media?.composition.track(withTrackID: clock)?.segments.first)
        let url = try #require(segment.sourceURL)
        let carrier = AVURLAsset(url: url)
        let track = try #require(try await carrier.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 16, height: 16))
        #expect(try await carrier.load(.duration).seconds == 1)
        #expect(FileManager.default.fileExists(atPath: url.path))
        media = nil
        #expect(released == nil && !FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        let exporter = ScreenRecordingExporter()
        let item = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let frames = try await RecordingMultitrackTestFixture.decode(item.asset, composition: item.videoComposition)
        #expect(frames.count == 30 && frames.allSatisfy { $0.1.width == 64 && $0.1.height == 48 })
        let destination = fixture.root.appendingPathComponent("text-only.gif")
        try await exporter.export(project: project, directory: fixture.directory, to: destination,
            configuration: .init(format: .gif, resolution: .source, frameRate: 4))
        #expect(CGImageSourceGetCount(try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))) == 4)
        #expect(try fixture.files().isEmpty)
    }

    @Test(arguments: [RecordingExportCheckpoint.beforeRead, .beforeWrite, .frame(1), .beforeCommit])
    func cancelledMultitrackExportPreservesTheDestinationAndLibraryAndRemovesStaging(_ checkpoint: RecordingExportCheckpoint) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        project.timeline = .migrating(project)
        let destination = fixture.root.appendingPathComponent("preserved.gif")
        try Data([4, 2]).write(to: destination)
        let original = try Data(contentsOf: fixture.directory.appendingPathComponent("screen.mp4"))
        let exporter = ScreenRecordingExporter(checkpoint: { if $0 == checkpoint { throw CancellationError() } })
        await #expect(throws: CancellationError.self) {
            try await exporter.export(project: project, directory: fixture.directory, to: destination,
                configuration: .init(format: .gif, resolution: .source, frameRate: 4))
        }
        #expect(!exporter.isExporting && exporter.progress < 1)
        #expect(try Data(contentsOf: destination) == Data([4, 2]))
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("screen.mp4")) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
            == [fixture.directory.lastPathComponent, destination.lastPathComponent].sorted())
    }

    @Test func intervalIndexMatchesThePublicVisibilityContractAtSeededAndFourULPBoundaries() {
        var seed: UInt64 = 3_731
        let tracks = (0..<8).map { RecordingTimelineTrack(id: "track\($0)", kind: $0 == 7 ? .audio : .video, isHidden: $0 == 6) }
        var clips: [RecordingTimelineClip] = []
        for index in 0..<96 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            clips.append(.init(id: "clip\(index)", trackID: tracks[index % 8].id, content: .video(UUID()),
                start: Double(seed % 100) / 4, sourceEnd: Double((seed >> 32) % 8 + 1) / 4))
        }
        let timeline = RecordingMultitrackTimeline(tracks: tracks, clips: clips)
        let index = RecordingTimelineClipIndex(timeline)
        for clip in clips {
            for time in [clip.start, clip.start - clip.start.ulp * 2, clip.end, clip.end - clip.end.ulp * 2,
                         clip.end - clip.end.ulp * 8, clip.start + clip.duration / 2] {
                #expect(index.clips(at: time) == timeline.visibleClips(at: time),
                    "The optimized renderer index must preserve layer order and exact clip boundary selection")
            }
        }
        let audio = RecordingTimelineClip(trackID: tracks[7].id, content: .audio(UUID()), start: 0, sourceEnd: 40)
        let mixed = RecordingMultitrackTimeline(tracks: tracks, clips: clips + [audio])
        #expect(RecordingTimelineClipIndex(mixed).clips(at: 0.5) == mixed.visibleClips(at: 0.5))
        #expect(RecordingTimelineClipIndex(mixed).clips(at: 0.5).allSatisfy { $0.content.trackKind != .audio })
    }

    @Test func subpixelImageLayoutsStillDecodeAndRenderWithoutRoundingTheirPosition() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createImage("thin.png", size: .init(width: 1_024, height: 1))
        let asset = RecordingMediaAsset(name: "Thin image", file: "thin.png", kind: .image, duration: 1, width: 1_024, height: 1)
        var project = fixture.project()
        project.videoFile = ""
        project.edits.segments = []
        project.timeline = .init(assets: [asset], tracks: [.init(id: "images", kind: .image)], clips: [
            .init(trackID: "images", content: .image(asset.id), start: 0, sourceEnd: 1,
                layout: .init(x: 0.5, y: 0.5, width: 0.1, height: 0.000_1)),
        ])
        try project.validate()
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: .init(width: 64, height: 48))
        let image = try renderer.image(frames: [:], at: 0.5)
        #expect(image.width == 64 && image.height == 48)
        #expect(project.timeline?.clips[0].layout.height == 0.000_1)
    }

    private func expectMixedContent(_ image: CGImage) throws {
        #expect(image.width == 64 && image.height == 48)
        let video = try RecordingMultitrackTestFixture.pixel(image, x: 60, y: 24)
        let picture = try RecordingMultitrackTestFixture.pixel(image, x: 50, y: 19)
        #expect(video[0] > 210 && video[1] < 50, "Video must render even when its saved track metadata is audio")
        #expect(picture[1] > 200 && picture[0] < 60, "Images must composite above videos on the same track; pixel \(picture)")
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        #expect(stride(from: 0, to: pixels.count, by: 4).contains {
            pixels[$0 + 2] > 130 && pixels[$0] < 90 && pixels[$0 + 1] < 90
        }, "The same track's text annotation must remain visible")
        #expect(stride(from: 0, to: pixels.count, by: 4).contains {
            pixels[$0] > 160 && pixels[$0 + 1] > 160 && pixels[$0 + 2] > 160
        }, "The same track's caption must remain visible")
    }

    private func expectPortraitOverLandscape(_ image: CGImage) throws {
        #expect(image.width == 64 && image.height == 48)
        let edge = try RecordingMultitrackTestFixture.pixel(image, x: 6, y: 24)
        let center = try RecordingMultitrackTestFixture.pixel(image, x: 32, y: 24)
        #expect(edge[0] > 220 && edge[1] < 40, "The portrait video's transparent fitted margin must reveal the landscape layer")
        #expect(center[1] > 220 && center[0] < 40, "The later portrait track must appear above the recording; pixel \(center)")
    }

    private func expectRepeatedCut(_ image: CGImage, at time: Double) throws {
        let center = try RecordingMultitrackTestFixture.pixel(image, x: 40, y: 30)
        let camera = try RecordingMultitrackTestFixture.pixel(image, x: 8, y: 8)
        let first = time >= 0.25 && time < 0.5
        let second = time >= 0.75 && time < 1.25
        let repeated = time >= 1.5 && time < 2
        if first || repeated {
            #expect(center[0] > 220 && center[2] < 40)
            #expect(camera[1] > 220 && camera[0] < 40, "Short camera media must reappear for each repeated source range; pixel \(camera), time \(time)")
        } else if second {
            #expect(center[2] > 220 && center[0] < 40)
            #expect(camera[2] > 220 && camera[1] < 40, "A cached camera generator must not return its last frame beyond source duration")
        } else {
            #expect(center.allSatisfy { $0 < 40 } && camera.allSatisfy { $0 < 40 },
                "Timeline gaps must stay blank instead of extending the previous decoded frame")
        }
    }
}
