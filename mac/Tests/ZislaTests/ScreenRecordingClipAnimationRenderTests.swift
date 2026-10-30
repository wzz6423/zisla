import CoreImage
import CoreText
import Foundation
import Testing
import ZislaCore
@testable import Zisla

@MainActor
struct ScreenRecordingClipAnimationRenderTests {
    @Test(arguments: RecordingClipAnimationKind.allCases.filter { $0 != .typewriter }, [false, true])
    func mediaAnimationsChangeRealPixelsAndRestoreTheOriginalLayout(_ kind: RecordingClipAnimationKind, video: Bool) throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let size = CGSize(width: 128, height: 96)
        var project = fixture.project()
        project.width = 128
        project.height = 96
        project.edits.padding = 0
        project.edits.shadow = 0
        project.edits.cornerRadius = 0
        let asset = RecordingMediaAsset(name: "Red", file: video ? "red.mp4" : "red.png",
            kind: video ? .video : .image, duration: 3, width: 128, height: 96)
        if !video { _ = try fixture.createImage("red.png", size: size, color: .init(red: 1, green: 0, blue: 0)) }
        var clip = RecordingTimelineClip(id: "red", trackID: "visual", content: video ? .video(asset.id) : .image(asset.id),
            start: 0, sourceEnd: 3, layout: .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5), audioEnabled: false)
        project.timeline = .init(assets: [asset], tracks: [.init(id: "visual")], clips: [clip])
        let frame = CIImage(color: .red).cropped(to: CGRect(origin: .zero, size: size))
        let frames = video ? [clip.id: frame] : [:]
        let original = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: size)
            .image(frames: frames, at: 1)
        let originalPixels = try RecordingImageFixture.pixels(original)
        let originalRed = redPixels(originalPixels)
        #expect(originalRed > 2_000)
        clip.entranceAnimation = .init(kind: kind, duration: 1)
        clip.exitAnimation = .init(kind: kind, duration: 1)
        project.timeline?.clips = [clip]
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: size)
        for time in [0.0, 3.0.nextDown] {
            let hidden = try RecordingImageFixture.pixels(renderer.image(frames: frames, at: time))
            #expect(redPixels(hidden) == 0, "The clip must leave the visible canvas at both animation endpoints")
        }
        for time in [0.5, 2.5] {
            let middle = try RecordingImageFixture.pixels(renderer.image(frames: frames, at: time))
            #expect(middle.bytes != originalPixels.bytes && redPixels(middle) > 0)
            switch kind {
            case .fade, .scale:
                let center = middle.pixel(x: 64, y: 48)
                #expect(center[0] > 50 && center[0] < 240 && center[1] < 10 && center[2] < 10)
                if kind == .scale { #expect(redPixels(middle) < originalRed * 3 / 4) }
            case .slideLeft, .slideRight, .slideUp, .slideDown:
                #expect(abs(redPixels(middle) * 2 - originalRed) <= 100,
                    "At half progress, half of the original media must remain on screen")
                #expect(middle.pixel(x: 64, y: 48)[0] < 10)
            case .typewriter: Issue.record("Typewriter does not apply to media")
            }
        }
        #expect(try RecordingImageFixture.pixels(renderer.image(frames: frames, at: 1.5)).bytes == originalPixels.bytes,
            "Completed entrance and unstarted exit must preserve the unanimated pixels")
    }

    @Test func absentAnimationsKeepTheExistingLayerOrderAndLegacyPixels() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createImage("red.png", color: .red)
        _ = try fixture.createImage("blue.png", color: .blue)
        var project = fixture.project()
        let red = RecordingMediaAsset(name: "Red", file: "red.png", kind: .image, duration: 3, width: 64, height: 48)
        let blue = RecordingMediaAsset(name: "Blue", file: "blue.png", kind: .image, duration: 3, width: 64, height: 48)
        let first = RecordingTimelineClip(id: "red", trackID: "mixed", content: .image(red.id), start: 0, sourceEnd: 3)
        let second = RecordingTimelineClip(id: "blue", trackID: "mixed", content: .image(blue.id), start: 1, sourceEnd: 2)
        project.timeline = .init(assets: [red, blue], tracks: [.init(id: "mixed")], clips: [second, first])
        let oldManifest = try JSONEncoder().encode(project)
        #expect(!String(decoding: oldManifest, as: UTF8.self).contains("Animation"))
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: oldManifest)
        let renderer = try RecordingMultitrackRenderer(project: decoded, directory: fixture.directory,
            size: CGSize(width: 64, height: 48))
        let pixels = try RecordingImageFixture.pixels(renderer.image(frames: [:], at: 1.5))
        #expect(pixels.pixel(x: 32, y: 24) == [255, 0, 0, 255],
            "Unconfigured effects must retain stored layer order even when it differs from time order")
        #expect(decoded == project)
    }

    @Test func threeOverlappingTransitionsConsumeEachSourceOnceAndPreserveLowerTrackTransparency() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createImage("green.png", color: .green)
        _ = try fixture.createImage("red.png", color: .init(red: 1, green: 0, blue: 0, alpha: 0.5))
        _ = try fixture.createImage("blue.png", color: .init(red: 0, green: 0, blue: 1, alpha: 0.5))
        _ = try fixture.createImage("white.png", color: .init(red: 1, green: 1, blue: 1, alpha: 0.5))
        var project = fixture.project()
        let assets = ["green", "red", "blue", "white"].map {
            RecordingMediaAsset(name: $0, file: $0 + ".png", kind: .image, duration: 4, width: 64, height: 48)
        }
        let green = RecordingTimelineClip(id: "green", trackID: "bottom", content: .image(assets[0].id), start: 0, sourceEnd: 4)
        let red = RecordingTimelineClip(id: "red", trackID: "top", content: .image(assets[1].id), start: 0, sourceEnd: 4)
        let blue = RecordingTimelineClip(id: "blue", trackID: "top", content: .image(assets[2].id),
            start: 1, sourceEnd: 3, transition: .init(kind: .dissolve, duration: 1))
        let white = RecordingTimelineClip(id: "white", trackID: "top", content: .image(assets[3].id),
            start: 1.25, sourceEnd: 2.75, transition: .init(kind: .dissolve, duration: 0.5))
        project.timeline = .init(assets: assets, tracks: [.init(id: "bottom"), .init(id: "top")],
            clips: [white, green, blue, red])
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory,
            size: CGSize(width: 64, height: 48))
        let middle = try RecordingImageFixture.pixels(renderer.image(frames: [:], at: 1.5)).pixel(x: 32, y: 24)
        #expect(abs(Int(middle[0]) - 96) <= 2 && abs(Int(middle[1]) - 191) <= 2
            && abs(Int(middle[2]) - 96) <= 2 && middle[3] == 255,
            "A duplicated outgoing layer would alter the three-source color mixture")
        let final = try RecordingImageFixture.pixels(renderer.image(frames: [:], at: 2)).pixel(x: 32, y: 24)
        #expect(abs(Int(final[0]) - 128) <= 1 && abs(Int(final[1]) - 255) <= 1
            && final[2] == final[0] && final[3] == 255,
            "After both transitions, only the half-transparent white source must cover the green track")
    }

    @Test(arguments: [false, true], ["你👨‍👩‍👧‍👦e\u{301}\n字!", "א ב ג 👩🏽‍💻 ד ה", "你 office affinity"])
    func typewriterRevealsWholeUnicodeGlyphsWithoutMovingPreviouslyVisiblePixels(_ caption: Bool, text: String) throws {
        for fontSize in [0.07, 0.11] {
            try expectFixedTypewriterPixels(caption: caption, text: text, fontSize: fontSize)
        }
    }

    private func expectFixedTypewriterPixels(caption: Bool, text: String, fontSize: Double) throws {
        let canvas = CGRect(x: 0, y: 0, width: 400, height: 300)
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 3, x: 0.1, y: 0.1, endX: 0.75, endY: 0.8,
            text: text, color: .init(red: 1, green: 1, blue: 1), fontSize: fontSize)
        let subtitle = RecordingCaption(start: 0, end: 3, text: text,
            layout: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.8), fontSize: fontSize)
        func render(_ count: Int?) throws -> RecordingImageFixture.Pixels {
            let image = try caption ? RecordingExportRenderer.captionImage(subtitle, canvas: canvas, visibleCharacters: count)
                : RecordingExportRenderer.annotationImage(annotation, canvas: canvas, visibleCharacters: count)
            let raster = try #require(CIContext().createCGImage(image, from: canvas, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
            return try RecordingImageFixture.pixels(raster)
        }
        let complete = try render(nil)
        let empty = try render(0)
        #expect(complete.bytes != empty.bytes)
        #expect(try render(text.count).bytes == complete.bytes)
        var previous = empty
        for count in 1..<text.count {
            let partial = try render(count)
            var exposed = 0
            var changedGlyphPixels = 0
            var movedGlyphPixels = 0
            for offset in stride(from: 0, to: partial.bytes.count, by: 4) {
                let value = Array(partial.bytes[offset..<offset + 4])
                let hidden = Array(empty.bytes[offset..<offset + 4])
                let final = Array(complete.bytes[offset..<offset + 4])
                let prior = Array(previous.bytes[offset..<offset + 4])
                if value != hidden {
                    exposed += 1
                    if value != final { changedGlyphPixels += 1 }
                }
                if prior != hidden && value != prior { movedGlyphPixels += 1 }
            }
            #expect(exposed > 0)
            #expect(changedGlyphPixels == 0, "Visible graphemes must use the exact final glyph pixels and positions")
            #expect(movedGlyphPixels == 0, "Already revealed glyphs must remain fixed")
            previous = partial
        }
        #expect(try render(-1).bytes == empty.bytes)
        #expect(try render(Int.max).bytes == complete.bytes)
        let emojiOnly = RecordingAnnotation(kind: .text, start: 0, end: 1, x: 0.1, y: 0.1, endX: 0.9, endY: 0.8,
            text: "👩‍❤️‍💋‍👨", fontSize: 0.15)
        let fullEmoji = try RecordingExportRenderer.annotationImage(emojiOnly, canvas: canvas)
        let typedEmoji = try RecordingExportRenderer.annotationImage(emojiOnly, canvas: canvas, visibleCharacters: 1)
        let context = CIContext()
        #expect(try RecordingImageFixture.pixels(#require(context.createCGImage(fullEmoji, from: canvas))).bytes
            == RecordingImageFixture.pixels(#require(context.createCGImage(typedEmoji, from: canvas))).bytes)
    }

    @Test func typewriterPreviewAndRenderUseTheSameFullLayoutForAnnotationsAndCaptions() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let size = CGSize(width: 400, height: 300)
        var project = fixture.project()
        project.width = 400
        project.height = 300
        project.videoFile = ""
        project.edits.segments = []
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 2, x: 0.1, y: 0.1, endX: 0.9, endY: 0.4,
            text: "字幕👩🏽‍💻e\u{301}", color: .init(red: 1, green: 1, blue: 1), fontSize: 0.1)
        let caption = RecordingCaption(start: 0, end: 2, text: "第二行👨‍👩‍👧‍👦",
            layout: .init(x: 0.1, y: 0.6, width: 0.8, height: 0.3), fontSize: 0.1)
        project.edits.annotations = [annotation]
        project.captions = [caption]
        project.timeline = .init(tracks: [.init(id: "text")], clips: [
            .init(id: "annotation", trackID: "text", content: .annotation(annotation.id), start: 0, sourceEnd: 2,
                entranceAnimation: .init(kind: .typewriter, duration: 1)),
            .init(id: "caption", trackID: "text", content: .caption(caption.id), start: 0, sourceEnd: 2,
                entranceAnimation: .init(kind: .typewriter, duration: 1)),
        ])
        try project.validate()
        let renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: size)
        var previous: [UInt8]?
        for time in [0.0, 0.4, 0.8, 1.5] {
            let scene = RecordingMultitrackPreviewScene(project: project, directory: fixture.directory, time: time, size: size, frames: [:])
            let rendered = try RecordingImageFixture.pixels(renderer.image(frames: [:], at: time)).bytes
            #expect(try RecordingImageFixture.pixels(scene.image(project: project)).bytes == rendered)
            if let previous { #expect(rendered != previous, "Each sampled typewriter phase must change displayed pixels") }
            previous = rendered
        }
    }

    @Test func hidingCaptionOrEditingAnnotationCannotConsumeAnOtherwiseVisibleTransitionSource() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try fixture.createImage("red.png", color: .red)
        var project = fixture.project()
        let asset = RecordingMediaAsset(name: "Red", file: "red.png", kind: .image, duration: 3, width: 64, height: 48)
        let caption = RecordingCaption(start: 0, end: 3, text: "Hidden")
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 3, text: "Editing")
        project.captions = [caption]
        project.edits.annotations = [annotation]
        let red = RecordingTimelineClip(id: "red", trackID: "mixed", content: .image(asset.id), start: 0, sourceEnd: 3)
        let subtitle = RecordingTimelineClip(id: "caption", trackID: "mixed", content: .caption(caption.id),
            start: 0.5, sourceEnd: 2, transition: .init(kind: .dissolve, duration: 0.5))
        let text = RecordingTimelineClip(id: "annotation", trackID: "mixed", content: .annotation(annotation.id),
            start: 0.5, sourceEnd: 2, transition: .init(kind: .dissolve, duration: 0.5))
        project.timeline = .init(assets: [asset], tracks: [.init(id: "mixed")], clips: [red, subtitle])
        project.edits.showCaptions = false
        var renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: .init(width: 64, height: 48))
        #expect(try RecordingImageFixture.pixels(renderer.image(frames: [:], at: 1.5)).pixel(x: 32, y: 24) == [255, 0, 0, 255],
            "A caption removed by the visibility toggle cannot replace another visible clip")
        project.timeline?.clips = [red, text]
        renderer = try RecordingMultitrackRenderer(project: project, directory: fixture.directory, size: .init(width: 64, height: 48))
        #expect(try RecordingImageFixture.pixels(renderer.image(frames: [:], at: 1.5, editingText: .annotation(annotation.id)))
            .pixel(x: 32, y: 24) == [255, 0, 0, 255],
            "Temporarily hiding text beneath the inline editor cannot remove its visible transition source")
    }

    @Test(arguments: ["office affinity", "مرحبا", "אבג👩🏽‍💻דה", "你👨‍👩‍👧‍👦e\u{301}\n!", "🙂fi字"])
    func typewriterRetainsFinalGlyphsLineOriginsAndLigaturesForComplexScripts(_ text: String) throws {
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 33, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
        let path = CGPath(rect: CGRect(x: 19.8, y: 19.8, width: 280.4, height: 200.4), transform: nil)
        let original = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed),
            CFRange(location: 0, length: 0), path, nil)
        let signature = frameSignature(original)
        for count in 1..<text.count {
            let partial = try RecordingExportRenderer.typewriterFrame(attributed, frame: original, visibleCharacters: count)
            let actual = frameSignature(partial)
            #expect(actual.glyphs == signature.glyphs && actual.positions == signature.positions
                && actual.indices == signature.indices && actual.origins == signature.origins,
                "Revealing characters must preserve final glyph shaping, line wrapping and positions")
            let boundary = text.prefix(count).utf16.count
            for line in CTFrameGetLines(partial) as! [CTLine] {
                for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    let color = try #require(attributes[kCTForegroundColorAttributeName]) as! CGColor
                    let range = CTRunGetStringRange(run)
                    if color.alpha != 0 {
                        #expect(range.location + range.length <= boundary,
                            "A visible ligature must not expose a character beyond the grapheme boundary")
                    }
                }
            }
        }
    }

    private func frameSignature(_ frame: CTFrame) -> (glyphs: [CGGlyph], positions: [CGPoint], indices: [CFIndex], origins: [CGPoint]) {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var result: (glyphs: [CGGlyph], positions: [CGPoint], indices: [CFIndex], origins: [CGPoint]) = ([], [], [], origins)
        for line in lines {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                result.glyphs += glyphs
                result.positions += positions
                result.indices += indices
            }
        }
        return result
    }

    private func redPixels(_ pixels: RecordingImageFixture.Pixels) -> Int {
        stride(from: 0, to: pixels.bytes.count, by: 4).filter {
            pixels.bytes[$0] > 40 && pixels.bytes[$0 + 1] < 10 && pixels.bytes[$0 + 2] < 10
        }.count
    }
}
