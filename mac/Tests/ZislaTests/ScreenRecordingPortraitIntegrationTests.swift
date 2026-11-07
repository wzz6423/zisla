import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import Zisla

@MainActor
struct ScreenRecordingPortraitIntegrationTests {
    private let size = CGSize(width: 384, height: 384)
    private let regions = RecordingPortraitProcessor.Regions(
        faces: [.init(x: 0.3, y: 0.55, width: 0.4, height: 0.3)],
        bodies: [.init(x: 0.2, y: 0.05, width: 0.6, height: 0.9)])

    @Test(arguments: ["smoothing", "brightening", "faceSlimming", "bodySlimming"], [false, true])
    func cameraEffectsApplyOnceBeforeMirroringAndLeaveTheScreenUntouched(_ effect: String, mirrored: Bool) throws {
        var project = project()
        project.cameraFile = "camera.mp4"
        project.rawCameraFile = "camera-original.mp4"
        project.edits.cameraMirrored = mirrored
        project.edits.portraitEffects = effects(effect)
        let camera = chart()
        let screen = CIImage(color: .blue).cropped(to: CGRect(origin: .zero, size: size))
        let renderer = try RecordingExportRenderer(project: project, size: size, portraitProcessor: processor())
        let actual = try renderer.image(screen: screen, camera: camera, sourceTime: 0)
        let processed = try processor().apply(camera, effects: effects(effect), sourceTime: 0)
        var reset = project
        reset.edits.portraitEffects = .init()
        let baselineRenderer = try RecordingExportRenderer(project: reset, size: size, portraitProcessor: processor())
        let expected = try baselineRenderer.image(screen: screen, camera: processed, sourceTime: 0)
        let baseline = try baselineRenderer.image(screen: screen, camera: camera, sourceTime: 0)
        #expect(try pixels(actual) == pixels(expected), "\(effect) must process the raw camera exactly once before layout and mirroring")
        #expect(try pixels(actual) != pixels(baseline))
        try expectOutsideUnchanged(actual, baseline: baseline,
            excluding: CGRect(x: 181, y: 9, width: 195, height: 195))
        let restored = try renderer.render(screen: screen, camera: camera, sourceTime: 0, cameraEffects: .init())
        #expect(try pixels(restored) == pixels(CIImage(cgImage: baseline)), "An explicit reset must override the project effects")
    }

    @Test func recordingClipOverridesAndResetOnlyChangeTheirOwnCameraLayer() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        var project = project()
        project.cameraFile = "camera.mp4"
        project.edits.portraitEffects = .init(brightening: 1)
        var timeline = RecordingMultitrackTimeline.migrating(project)
        var first = try #require(timeline.clips.first)
        first.sourceEnd = 1
        first.id = "inherit"
        var reset = first
        reset.id = "reset"
        reset.start = 1
        reset.portraitEffects = .init()
        var override = first
        override.id = "override"
        override.start = 2
        override.portraitEffects = .init(bodySlimming: 1)
        timeline.clips = [first, reset, override]
        project.timeline = timeline
        try project.validate()
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: size,
            makePortraitProcessor: { processor() })
        let camera = chart()
        let screen = CIImage(color: .blue).cropped(to: CGRect(origin: .zero, size: size))
        func render(_ clip: RecordingTimelineClip) throws -> CGImage {
            try renderer.image(frames: [clip.id: screen, clip.id + ".camera": camera], at: clip.start)
        }
        let inherited = try render(first)
        let original = try render(reset)
        let overridden = try render(override)
        #expect(try pixels(inherited) != pixels(original))
        #expect(try pixels(overridden) != pixels(original))
        #expect(try pixels(inherited) != pixels(overridden), "A clip override must replace the project effect rather than combine with it")
        for image in [inherited, overridden] {
            try expectOutsideUnchanged(image, baseline: original,
                excluding: CGRect(x: 181, y: 9, width: 195, height: 195))
        }
        var expectedProject = project
        expectedProject.timeline = nil
        expectedProject.edits.portraitEffects = override.portraitEffects
        let expected = try RecordingExportRenderer(project: expectedProject, size: size, portraitProcessor: processor())
            .image(screen: screen, camera: camera, sourceTime: 0)
        #expect(try pixels(overridden) == pixels(expected))
        #expect(project.timeline?.clips[0].portraitEffects == nil && project.edits.portraitEffects == .init(brightening: 1))
    }

    @Test(arguments: [false, true], ["smoothing", "brightening", "faceSlimming", "bodySlimming"])
    func importedPortraitsOnlyChangeTheSelectedVideoOrImageClip(video: Bool, effect: String) throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let portrait = chart()
        let file = video ? "portrait.mp4" : "portrait.png"
        if !video { try write(portrait, to: fixture.directory.appendingPathComponent(file)) }
        var project = project()
        project.edits.portraitEffects = .init(brightening: 1)
        var timeline = RecordingMultitrackTimeline.migrating(project)
        let recording = try #require(timeline.clips.first)
        let asset = RecordingMediaAsset(name: "Portrait", file: file, kind: video ? .video : .image,
            duration: 2, width: 192, height: 192)
        let track = RecordingTimelineTrack(id: "portrait", kind: video ? .video : .image)
        let first = RecordingTimelineClip(id: "enhanced", trackID: track.id,
            content: video ? .video(asset.id) : .image(asset.id), start: 0, sourceEnd: 1,
            layout: .init(x: 0.5, y: 0.5, width: 0.5, height: 0.5), portraitEffects: effects(effect))
        var second = first
        second.id = "original"
        second.start = 1
        second.portraitEffects = .init()
        timeline.assets.append(asset)
        timeline.tracks.append(track)
        timeline.clips.append(contentsOf: [first, second])
        project.timeline = timeline
        try project.validate()
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: size,
            makePortraitProcessor: { processor() })
        let screen = CIImage(color: .blue).cropped(to: CGRect(origin: .zero, size: size))
        let changed = try renderer.image(frames: [recording.id: screen, first.id: portrait], at: 0)
        let restored = try renderer.image(frames: [recording.id: screen, second.id: portrait], at: 1)
        #expect(try pixels(changed) != pixels(restored), "\(effect) must alter the imported \(video ? "video" : "image")")
        try expectOutsideUnchanged(changed, baseline: restored, excluding: CGRect(x: 192, y: 0, width: 192, height: 192))
        var baselineProject = project
        baselineProject.edits.portraitEffects = .init()
        baselineProject.timeline?.clips[1].portraitEffects = .init()
        let baseline = try RecordingMultitrackRenderer(project: baselineProject, directory: fixture.directory, size: size,
            makePortraitProcessor: { processor() })
            .image(frames: [recording.id: screen, first.id: portrait], at: 0)
        #expect(try pixels(restored) == pixels(baseline), "Reset must disable imported media effects even when project camera effects are enabled")
    }

    @Test(arguments: [false, true])
    func importedPortraitProcessorCacheReleasesOldInstancesAfterSixteenClips(video: Bool) throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let portrait = chart()
        let file = video ? "portrait.mp4" : "portrait.png"
        if !video { try write(portrait, to: fixture.directory.appendingPathComponent(file)) }
        let project = try importedProject(video: video, file: file, clipCount: 17)
        let clips = try #require(project.timeline?.clips)
        var instances: [WeakProcessor] = []
        do {
            let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: size,
                makePortraitProcessor: {
                    let value = processor()
                    instances.append(WeakProcessor(value))
                    return value
                })
            let baseCount = instances.count
            for clip in clips.prefix(16) {
                _ = try renderer.image(frames: [clip.id: portrait], at: clip.start)
            }
            let earlier = Array(instances.dropFirst(baseCount))
            #expect(earlier.count == 16 && earlier.allSatisfy { $0.value != nil },
                "The active clip cache must retain reusable processors within its budget")
            let last = try #require(clips.last)
            _ = try renderer.image(frames: [last.id: portrait], at: last.start)
            #expect(earlier.contains { $0.value == nil },
                "Visiting a seventeenth clip must release an earlier clip processor")
            #expect(instances.dropFirst(baseCount).filter { $0.value != nil }.count <= 16)
            #expect(instances.last?.value != nil, "The current clip must retain its processor for the next frame")
        }
        #expect(instances.allSatisfy { $0.value == nil }, "Discarding the renderer must release every portrait processor")
    }

    @Test func aStaticImageReusesDetectionAcrossDifferentOutputTimes() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let file = "portrait.png"
        try write(chart(), to: fixture.directory.appendingPathComponent(file))
        let project = try importedProject(video: false, file: file, clipDuration: 2)
        var detections = 0
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: size,
            makePortraitProcessor: {
                RecordingPortraitProcessor { _, _, _ in
                    detections += 1
                    return regions
                }
            })
        let expected = try pixels(renderer.image(frames: [:], at: 0))
        for time in [0.2, 0.75, 1.75] {
            #expect(try pixels(renderer.image(frames: [:], at: time)) == expected)
        }
        #expect(detections == 1, "An unchanged static portrait must not rerun detection when output time advances")
    }

    @Test(arguments: ["camera", "video", "image"])
    func portraitRenderingRecoversAfterDetectionFailure(layer: String) throws {
        enum Failure: Error { case unavailable }
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let portrait = chart()
        var project: ScreenRecordingProject
        var frames: [String: CIImage]
        if layer == "camera" {
            project = self.project()
            project.cameraFile = "camera.mp4"
            project.edits.portraitEffects = .init(brightening: 1)
            project.timeline = .migrating(project)
            let clip = try #require(project.timeline?.clips.first)
            frames = [clip.id: CIImage(color: .blue).cropped(to: CGRect(origin: .zero, size: size)),
                clip.id + ".camera": portrait]
        } else {
            let video = layer == "video"
            let file = video ? "portrait.mp4" : "portrait.png"
            if !video { try write(portrait, to: fixture.directory.appendingPathComponent(file)) }
            project = try importedProject(video: video, file: file)
            let clip = try #require(project.timeline?.clips.first)
            frames = video ? [clip.id: portrait] : [:]
        }
        var detections = 0
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: size,
            makePortraitProcessor: {
                RecordingPortraitProcessor { _, _, _ in
                    detections += 1
                    if detections == 1 { throw Failure.unavailable }
                    return regions
                }
            })
        #expect(throws: Failure.unavailable) { try renderer.image(frames: frames, at: 0) }
        let recovered = try renderer.image(frames: frames, at: 0)
        let expected = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: size,
            makePortraitProcessor: { processor() }).image(frames: frames, at: 0)
        #expect(try pixels(recovered) == pixels(expected), "The \(layer) must render normally after a detection failure")
        #expect(detections == 2, "Failed detection must be retried on the next render")
    }

    @Test(.serialized, arguments: [false, true])
    func previewAndExportPreparationReadTheOriginalCameraCopyAfterReset(multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo(duration: 0.25, colors: [.blue])
        _ = try await fixture.createVideo("camera.mp4", duration: 0.25, colors: [.red])
        _ = try await fixture.createVideo("camera-original.mp4", duration: 0.25, colors: [.green])
        var project = fixture.project()
        project.duration = 0.25
        project.edits.segments = [.init(start: 0, end: 0.25)]
        project.cameraFile = "camera.mp4"
        project.rawCameraFile = "camera-original.mp4"
        project.edits.cameraAspectRatio = .square
        project.edits.cameraSize = 0.5
        project.edits.cameraCornerRadius = 0
        project.edits.portraitEffects = .init()
        if multitrack { project.timeline = .migrating(project) }
        let exporter = ScreenRecordingExporter()
        let image = try await exporter.preview(project: project, directory: fixture.directory, sourceTime: 0,
            maximumSize: CGSize(width: 64, height: 48))
        let pixel = try RecordingMultitrackTestFixture.pixel(image, x: 49, y: 35)
        #expect(pixel[1] > 200 && pixel[0] < 40, "Reset preview must use the green original rather than the red enhanced recording")
        if multitrack {
            let media = try await RecordingMultitrackMedia.prepare(project: project, directory: fixture.directory)
            let camera = try #require(media.layers.values.first { $0.key.hasSuffix(".camera") })
            let track = try #require(media.composition.track(withTrackID: camera.trackID))
            #expect(track.segments.contains { $0.sourceURL?.lastPathComponent == "camera-original.mp4" })
        } else {
            let media = try await RecordingExportMedia.prepare(project: project, directory: fixture.directory,
                timeline: RecordingExportTimeline(project: project))
            let camera = try #require(media.camera)
            #expect(camera.track.segments.contains { $0.sourceURL?.lastPathComponent == "camera-original.mp4" })
        }
        #expect(try fixture.files() == ["camera-original.mp4", "camera.mp4", "screen.mp4"])
    }

    private func project() -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Portrait integration", videoFile: "screen.mp4", duration: 2,
            width: 384, height: 384)
        project.edits.background = .none
        project.edits.showCursor = false
        project.edits.clickEffects = false
        project.edits.cameraSize = 0.5
        project.edits.cameraAspectRatio = .square
        project.edits.cameraCornerRadius = 0
        project.edits.cameraMirrored = false
        return project
    }

    private func processor() -> RecordingPortraitProcessor {
        RecordingPortraitProcessor { _, _, _ in regions }
    }

    private final class WeakProcessor {
        weak var value: RecordingPortraitProcessor?
        init(_ value: RecordingPortraitProcessor) { self.value = value }
    }

    private func importedProject(video: Bool, file: String, clipCount: Int = 1,
                                 clipDuration: Double = 1) throws -> ScreenRecordingProject {
        var project = project()
        let asset = RecordingMediaAsset(name: "Portrait", file: file, kind: video ? .video : .image,
            duration: clipDuration, width: 192, height: 192)
        let track = RecordingTimelineTrack(id: "portrait", kind: video ? .video : .image)
        let clips = (0..<clipCount).map { index in
            RecordingTimelineClip(id: "portrait-\(index)", trackID: track.id,
                content: video ? .video(asset.id) : .image(asset.id), start: Double(index) * clipDuration,
                sourceEnd: clipDuration, portraitEffects: .init(brightening: 1))
        }
        project.timeline = .init(assets: [asset], tracks: [track], clips: clips)
        try project.validate()
        return project
    }

    private func write(_ image: CIImage, to url: URL) throws {
        let raster = try #require(CIContext().createCGImage(image, from: image.extent))
        let output = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(output, raster, nil)
        try #require(CGImageDestinationFinalize(output))
    }

    private func effects(_ name: String) -> RecordingPortraitEffects {
        switch name {
        case "smoothing": .init(smoothing: 1)
        case "brightening": .init(brightening: 1)
        case "faceSlimming": .init(faceSlimming: 1)
        default: .init(bodySlimming: 1)
        }
    }

    private func chart() -> CIImage {
        var bytes = [UInt8](repeating: 0, count: 192 * 192 * 4)
        for y in 0..<192 {
            for x in 0..<192 {
                let offset = (y * 192 + x) * 4
                let face = (58..<135).contains(x) && (28..<86).contains(y)
                bytes[offset] = UInt8(face ? 140 + (x + y) % 2 * 8 : 60 + x / 2)
                bytes[offset + 1] = UInt8(face ? 100 + (x + y) % 2 * 8 : y / 2)
                bytes[offset + 2] = UInt8(face ? 70 : 120)
                bytes[offset + 3] = 255
            }
        }
        return CIImage(bitmapData: Data(bytes), bytesPerRow: 192 * 4, size: CGSize(width: 192, height: 192),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] { try pixels(CIImage(cgImage: image)) }

    private func pixels(_ image: CIImage) throws -> [UInt8] {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { pointer in
            CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!]).render(image,
                toBitmap: pointer.baseAddress!, rowBytes: width * 4, bounds: image.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        return bytes
    }

    private func expectOutsideUnchanged(_ image: CGImage, baseline: CGImage, excluding region: CGRect) throws {
        let before = try pixels(baseline)
        let after = try pixels(image)
        var changedOutside = 0
        for y in 0..<image.height {
            for x in 0..<image.width where !region.contains(CGPoint(x: CGFloat(x) + 0.5,
                y: CGFloat(image.height - y) - 0.5)) {
                let offset = (y * image.width + x) * 4
                if before[offset..<offset + 4] != after[offset..<offset + 4] { changedOutside += 1 }
            }
        }
        #expect(changedOutside == 0, "Portrait effects must not change the screen or the background outside their layer")
    }
}
