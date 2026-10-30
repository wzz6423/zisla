import AppKit
import CoreGraphics
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized) @MainActor
struct ScreenRecordingImageCanvasTests {
    @Test(arguments: [RecordingCanvasHandle.topLeft, .topRight, .bottomLeft, .bottomRight])
    func imageCornersPreserveThePixelAspectRatioAndOppositeAnchorInsideTheCanvas(_ handle: RecordingCanvasHandle) {
        let canvas = CGSize(width: 800, height: 600)
        let clip = RecordingTimelineClip(trackID: "image", content: .image(UUID()), start: 0, sourceEnd: 2,
            layout: .init(x: 0.2, y: 0.3, width: 0.3, height: 0.2))
        let element = RecordingCanvasElement.image(clip)
        let original = element.bounds(canvas: canvas)
        let left = handle == .topLeft || handle == .bottomLeft
        let top = handle == .topLeft || handle == .topRight
        for delta in [CGSize(width: 120, height: 90), CGSize(width: 10_000, height: -10_000),
                      CGSize(width: -10_000, height: 10_000)] {
            let resized = RecordingCanvasGeometry.transformed(element, by: delta, handle: handle, canvas: canvas)
            guard case let .image(value) = resized else { Issue.record("Expected image clip"); return }
            let box = resized.bounds(canvas: canvas)
            #expect(abs(box.width / box.height - original.width / original.height) < 0.000_001)
            #expect(abs((left ? box.maxX : box.minX) - (left ? original.maxX : original.minX)) < 0.000_001)
            #expect(abs((top ? box.maxY : box.minY) - (top ? original.maxY : original.minY)) < 0.000_001)
            #expect(value.layout.isNormalized && min(box.width, box.height) >= 4 - 0.000_001)
            #expect(value.id == clip.id && value.content == clip.content && value.start == clip.start && value.sourceEnd == clip.sourceEnd)
        }
    }

    @Test
    func imageMovesClampTheWholeObjectAndRejectInvalidEvents() {
        let canvas = CGSize(width: 800, height: 600)
        let element = RecordingCanvasElement.image(.init(trackID: "image", content: .image(UUID()), start: 0, sourceEnd: 2,
            layout: .init(x: 0.2, y: 0.3, width: 0.3, height: 0.2)))
        let moved = RecordingCanvasGeometry.transformed(element, by: CGSize(width: 5_000, height: -5_000), handle: nil, canvas: canvas)
        let box = moved.bounds(canvas: canvas)
        #expect(box.maxX == canvas.width && box.minY == 0)
        #expect(box.size == element.bounds(canvas: canvas).size)
        #expect(RecordingCanvasGeometry.transformed(element, by: .zero, handle: nil, canvas: canvas) == element)
        #expect(RecordingCanvasGeometry.transformed(element, by: CGSize(width: CGFloat.nan, height: 1), handle: .topLeft, canvas: canvas) == element)
        #expect(RecordingCanvasGeometry.transformed(element, by: CGSize(width: 1, height: 1), handle: nil,
            canvas: CGSize(width: CGFloat.infinity, height: 600)) == element)
        #expect(element.text == nil && element.replacingText("Ignored") == element)
    }

    @Test
    func imageVisibilityUsesOutputTimeAndTheSameTrackOrderAsCompositing() throws {
        let media = try RecordingImageFixture()
        defer { media.close() }
        let asset = try media.addImage(width: 40, height: 20)
        let bottom = RecordingTimelineTrack(id: "bottom", kind: .image)
        let top = RecordingTimelineTrack(id: "top", kind: .image)
        let hidden = RecordingTimelineTrack(id: "hidden", kind: .image, isHidden: true)
        let first = RecordingTimelineClip(id: "first", trackID: bottom.id, content: .image(asset.id), start: 1,
                                          sourceStart: 10, sourceEnd: 12, speed: 2)
        let second = RecordingTimelineClip(id: "second", trackID: top.id, content: .image(asset.id), start: 1, sourceEnd: 1)
        let invisible = RecordingTimelineClip(trackID: hidden.id, content: .image(asset.id), start: 0, sourceEnd: 3)
        media.project.timeline?.tracks = [bottom, top, hidden]
        media.project.timeline?.clips = [second, invisible, first]
        #expect(RecordingCanvasElement.visible(in: media.project, at: 0.9).isEmpty)
        #expect(RecordingCanvasElement.visible(in: media.project, at: 1) == [.image(first), .image(second)])
        #expect(RecordingCanvasElement.visible(in: media.project, at: 2).isEmpty,
                "Images must disappear at the exclusive output endpoint, irrespective of source offset and speed")
    }

    @Test
    func updatingAnImageClipNeverChangesAnotherUseOfItsAssetOrOverwritesANewerEdit() {
        let assetID = UUID()
        let first = RecordingTimelineClip(id: "first", trackID: "image", content: .image(assetID), start: 0, sourceEnd: 2,
            layout: .init(x: 0.1, y: 0.1, width: 0.3, height: 0.2))
        var second = first
        second.id = "second"
        let original = RecordingCanvasElement.image(first)
        var project = ScreenRecordingProject(name: "Images", videoFile: "screen.mp4", duration: 3, width: 800, height: 600,
            timeline: .init(clips: [first, second]))
        let moved = RecordingCanvasGeometry.transformed(original, by: CGSize(width: 100, height: 90), handle: nil,
                                                       canvas: CGSize(width: 800, height: 600))
        moved.write(to: &project, replacing: original)
        #expect(project.timeline?.clips[0] != first && project.timeline?.clips[1] == second)
        let updated = project
        original.write(to: &project, replacing: original)
        #expect(project == updated, "A draft based on an older layout must not replace a concurrent clip change")
    }

    @Test(arguments: [false, true])
    func draggingMediaRecomposesTheLivePixelsWithoutGhostsAndCommitsOneUndoableLayout(_ video: Bool) async throws {
        let fixture = try Fixture(video: video)
        defer { fixture.close() }
        await fixture.ready()
        let original = try #require(fixture.model.project)
        let second = try #require(original.timeline?.clips.last)
        let beforePixels = try RecordingImageFixture.pixels(#require(fixture.view.renderedImage)).bytes
        fixture.view.mouseDown(with: try fixture.mouse(.leftMouseDown, x: 0.25, y: 0.2))
        fixture.view.mouseDragged(with: try fixture.mouse(.leftMouseDragged, x: 0.6, y: 0.5))
        let draft = try #require(fixture.view.draft)
        var expected = original
        let first = try #require(original.timeline?.clips.first)
        draft.write(to: &expected, replacing: video ? .video(first) : .image(first))
        #expect(fixture.model.project == original && fixture.commits == 0)
        let live = try RecordingImageFixture.pixels(#require(fixture.view.renderedImage)).bytes
        #expect(live != beforePixels)
        #expect(try live == RecordingImageFixture.pixels(fixture.scene.image(project: expected)).bytes,
                "Moving media must rebuild all layers so its old location is removed")
        fixture.view.mouseUp(with: try fixture.mouse(.leftMouseUp, x: 0.6, y: 0.5))
        #expect(fixture.model.project == expected && fixture.commits == 1 && fixture.model.canUndo)
        #expect(fixture.model.project?.timeline?.clips.last == second)
        #expect(fixture.view.textEditor == nil, "Media must never enter inline text editing")
        fixture.model.undo()
        #expect(fixture.model.project == original && !fixture.model.canUndo)
        fixture.model.redo()
        #expect(fixture.model.project == expected)
        await fixture.model.previewTask?.value
        #expect(fixture.errors.isEmpty && !fixture.window.isVisible)
    }

    @Test(arguments: [false, true])
    func mediaCornerEventsPreserveAspectRatioAndEscapeRestoresTheCompositedPixels(_ video: Bool) async throws {
        let fixture = try Fixture(video: video)
        defer { fixture.close() }
        await fixture.ready()
        let project = try #require(fixture.model.project)
        let before = try RecordingImageFixture.pixels(#require(fixture.view.renderedImage)).bytes
        fixture.view.mouseDown(with: try fixture.mouse(.leftMouseDown, x: 0.4, y: 0.3))
        fixture.view.mouseDragged(with: try fixture.mouse(.leftMouseDragged, x: 0.5, y: 0.5))
        let draft = try #require(fixture.view.draft)
        let box = draft.bounds(canvas: fixture.view.canvasSize)
        #expect(abs(box.width / box.height - 2) < 0.000_001)
        #expect(fixture.model.project == project)
        fixture.view.keyDown(with: try fixture.escape())
        #expect(fixture.view.draft == nil && fixture.commits == 0 && !fixture.model.canUndo)
        #expect(try RecordingImageFixture.pixels(#require(fixture.view.renderedImage)).bytes == before)
    }

    @Test
    func selectingOverlappingImagesTargetsTheTopVisibleTrack() async throws {
        let fixture = try Fixture(overlapping: true)
        defer { fixture.close() }
        await fixture.ready(selection: nil)
        fixture.view.mouseDown(with: try fixture.mouse(.leftMouseDown, x: 0.25, y: 0.2, clicks: 2))
        let clip = try #require(fixture.model.project?.timeline?.clips.last)
        #expect(fixture.selection == .image(clip.id) && fixture.view.draft == .image(clip))
        #expect(fixture.view.textEditor == nil && fixture.commits == 0)
    }

    @Test(arguments: [false, true])
    func aSelectedImageRemainsTheDragTargetWhenAnotherTrackCoversItsBodyOrCorner(_ corner: Bool) async throws {
        let fixture = try Fixture(overlapping: true)
        defer { fixture.close() }
        await fixture.ready()
        let project = try #require(fixture.model.project)
        let first = try #require(project.timeline?.clips.first)
        let second = try #require(project.timeline?.clips.last)
        let x = corner ? 0.4 : 0.25
        let y = corner ? 0.3 : 0.2
        fixture.view.mouseDown(with: try fixture.mouse(.leftMouseDown, x: x, y: y))
        fixture.view.mouseDragged(with: try fixture.mouse(.leftMouseDragged, x: x + 0.1, y: y + 0.1))
        let draft = try #require(fixture.view.draft)
        #expect(fixture.selection == .image(first.id) && draft.selection == .image(first.id))
        #expect(fixture.model.project == project && draft != .image(first))
        fixture.view.mouseUp(with: try fixture.mouse(.leftMouseUp, x: x + 0.1, y: y + 0.1))
        #expect(fixture.model.project?.timeline?.clips.last == second && fixture.commits == 1)
        fixture.model.undo()
        #expect(fixture.model.project == project && !fixture.model.canUndo)
    }

    @Test
    func imageDoubleClickAndNoMotionReleasePreserveTheLayoutAndUndoHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.ready()
        let project = fixture.model.project
        let before = try RecordingImageFixture.pixels(#require(fixture.view.renderedImage)).bytes
        fixture.view.mouseDown(with: try fixture.mouse(.leftMouseDown, x: 0.25, y: 0.2, clicks: 2))
        fixture.view.mouseUp(with: try fixture.mouse(.leftMouseUp, x: 0.25, y: 0.2))
        #expect(fixture.view.textEditor == nil && fixture.view.draft == nil)
        #expect(fixture.model.project == project && fixture.commits == 0 && !fixture.model.canUndo)
        #expect(try RecordingImageFixture.pixels(#require(fixture.view.renderedImage)).bytes == before)
    }

    @Test
    func seekingOrRemovingAnImageCancelsItsDraftAndStaleScenesCannotAcceptInput() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.ready()
        fixture.view.mouseDown(with: try fixture.mouse(.leftMouseDown, x: 0.25, y: 0.2))
        fixture.view.mouseDragged(with: try fixture.mouse(.leftMouseDragged, x: 0.3, y: 0.3))
        fixture.view.configure(project: fixture.model.project, sourceTime: 0.5, baseImage: fixture.base,
            selection: fixture.selection, editable: true, multitrackScene: fixture.scene)
        #expect(fixture.view.draft == nil && fixture.view.renderedImage == nil && fixture.commits == 0)
        #expect(fixture.view.hitTest(CGPoint(x: 100, y: 100)) == nil)
        await fixture.ready()
        fixture.view.mouseDown(with: try fixture.mouse(.leftMouseDown, x: 0.25, y: 0.2))
        fixture.view.mouseDragged(with: try fixture.mouse(.leftMouseDragged, x: 0.3, y: 0.3))
        var project = try #require(fixture.model.project)
        project.timeline?.clips.removeFirst()
        let scene = RecordingMultitrackPreviewScene(project: project, directory: fixture.media.directory,
            time: 0, size: fixture.view.canvasSize, frames: [:])
        fixture.view.configure(project: project, sourceTime: 0, baseImage: fixture.base,
            selection: fixture.selection, editable: true, multitrackScene: scene)
        #expect(fixture.view.draft == nil && fixture.commits == 0)
        #expect(try RecordingImageFixture.pixels(#require(fixture.view.renderedImage)).bytes
            == RecordingImageFixture.pixels(scene.image(project: project)).bytes)
    }

    @Test
    func anUnreadableImageClearsThePreviewAndSurfacesTheFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.ready()
        let asset = try #require(fixture.media.project.timeline?.assets.first)
        try FileManager.default.removeItem(at: fixture.media.url(asset))
        fixture.view.configure(project: fixture.model.project, sourceTime: 0, baseImage: fixture.base,
            selection: fixture.selection, editable: true, multitrackScene: fixture.scene)
        #expect(fixture.view.renderedImage == nil && fixture.errors.count == 1)
        #expect(!fixture.model.canUndo && fixture.commits == 0)
    }

    @Test(arguments: [false, true])
    func selectedVideoBodyDoesNotBlockSelectingTheImageOrTextOnTheTopTrack(_ text: Bool) async throws {
        let fixture = try Fixture(video: true)
        defer { fixture.close() }
        await fixture.ready()
        var project = try #require(fixture.model.project)
        let video = try #require(project.timeline?.clips.first)
        let overlay = try #require(project.timeline?.clips.last)
        let selection: RecordingCanvasSelection
        let point: CGPoint
        if text {
            let annotation = RecordingAnnotation(kind: .text, start: 0, end: 2, x: 0.15, y: 0.15,
                endX: 0.4, endY: 0.3, text: "Overlay")
            project.edits.annotations = [annotation]
            project.timeline?.clips[1].content = .annotation(annotation.id)
            selection = .annotation(annotation.id)
            let box = RecordingCanvasElement.annotation(annotation).bounds(canvas: fixture.view.canvasSize)
            point = CGPoint(x: box.midX / fixture.view.canvasSize.width, y: box.midY / fixture.view.canvasSize.height)
        } else {
            let asset = try fixture.media.addImage(width: 60, height: 30)
            project.timeline?.assets.append(asset)
            project.timeline?.clips[1].content = .image(asset.id)
            project.timeline?.clips[1].layout = video.layout
            selection = .image(overlay.id)
            point = CGPoint(x: 0.25, y: 0.2)
        }
        let scene = RecordingMultitrackPreviewScene(project: project, directory: fixture.media.directory,
            time: 0, size: fixture.view.canvasSize, frames: fixture.scene.frames)
        fixture.view.configure(project: project, sourceTime: 0, baseImage: fixture.base,
            selection: .video(video.id), editable: true, multitrackScene: scene)
        fixture.view.mouseDown(with: try fixture.mouse(.leftMouseDown, x: point.x, y: point.y))
        #expect(fixture.selection == selection && fixture.view.draft?.selection == selection)
        #expect(fixture.commits == 0 && fixture.view.textEditor == nil)
    }

    @Test(arguments: [RecordingCanvasHandle.topLeft, .topRight, .bottomLeft, .bottomRight])
    func videoCornersUseTheSameAspectAndAnchorConstraintsAndNeverOverwriteANewerClipEdit(_ handle: RecordingCanvasHandle) {
        let canvas = CGSize(width: 800, height: 600)
        let clip = RecordingTimelineClip(id: "video", trackID: "video", content: .video(UUID()), start: 2,
            sourceStart: 0.5, sourceEnd: 2, speed: 2, layout: .init(x: 0.2, y: 0.3, width: 0.3, height: 0.2))
        let original = RecordingCanvasElement.video(clip)
        let before = original.bounds(canvas: canvas)
        let moved = RecordingCanvasGeometry.transformed(original, by: CGSize(width: 30, height: 20),
            handle: handle, canvas: canvas)
        guard case let .video(replacement) = moved else { Issue.record("Expected video clip"); return }
        let after = moved.bounds(canvas: canvas)
        #expect(after != before, "Dragging a video corner must change its layout")
        let left = handle == .topLeft || handle == .bottomLeft
        let top = handle == .topLeft || handle == .topRight
        #expect(abs(before.width / before.height - after.width / after.height) < 0.000_001)
        #expect(abs((left ? before.maxX : before.minX) - (left ? after.maxX : after.minX)) < 0.000_001)
        #expect(abs((top ? before.maxY : before.minY) - (top ? after.maxY : after.minY)) < 0.000_001)
        #expect(replacement.layout.isNormalized && replacement.sourceStart == clip.sourceStart && replacement.speed == clip.speed)
        #expect(original.text == nil && original.replacingText("Ignored") == original)
        var project = ScreenRecordingProject(name: "Video", videoFile: "screen.mp4", duration: 3, width: 800, height: 600,
            timeline: .init(clips: [clip]))
        moved.write(to: &project, replacing: original)
        #expect(project.timeline?.clips.first == replacement)
        let updated = project
        original.write(to: &project, replacing: original)
        #expect(project == updated, "A stale canvas gesture must not overwrite a newer layout")
    }

    @MainActor private final class Fixture {
        let media: RecordingImageFixture
        let model: ScreenRecordingStudioModel
        let view = RecordingCanvasEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let window: NSWindow
        let scene: RecordingMultitrackPreviewScene
        let base: CGImage
        var selection: RecordingCanvasSelection?
        var commits = 0
        var errors: [Error] = []

        init(overlapping: Bool = false, video: Bool = false) throws {
            media = try RecordingImageFixture()
            let asset = try media.addImage(width: 60, height: 30, transparent: true)
            let bottom = RecordingTimelineTrack(id: "bottom", kind: .image)
            let top = RecordingTimelineTrack(id: "top", kind: .image)
            let layout = RecordingRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
            let first = RecordingTimelineClip(id: "first", trackID: bottom.id, content: .image(asset.id), start: 0,
                                              sourceEnd: 2, layout: layout)
            let second = RecordingTimelineClip(id: "second", trackID: top.id, content: .image(asset.id), start: 0,
                sourceEnd: 2, layout: overlapping ? layout : .init(x: 0.65, y: 0.7, width: 0.3, height: 0.2))
            media.project.timeline?.tracks = [bottom, top]
            media.project.timeline?.clips = [first, second]
            var frames: [String: CGImage] = [:]
            if video {
                let image = try #require(NSImage(contentsOf: media.url(asset))?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let source = RecordingMediaAsset(name: "Video", file: "screen.mp4", kind: .video,
                    duration: 2, width: 60, height: 30)
                media.project.timeline?.assets.append(source)
                media.project.timeline?.clips[0].content = .video(source.id)
                media.project.timeline?.clips[1].content = .video(source.id)
                frames = [first.id: image, second.id: image]
            }
            selection = video ? .video(first.id) : .image(first.id)
            scene = RecordingMultitrackPreviewScene(project: media.project, directory: media.directory,
                time: 0, size: CGSize(width: 400, height: 300), frames: frames)
            base = try scene.image(project: media.project)
            let base = self.base
            model = ScreenRecordingStudioModel(projectStore: .init(root: media.root), renderPreview: { _, _, _ in base })
            window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            model.install(media.project, directory: media.directory)
            view.onSelect = { [weak self] in self?.selection = $0 }
            view.onCommit = { [weak self] original, replacement in
                guard let self else { return }
                commits += 1
                model.update { replacement.write(to: &$0, replacing: original) }
            }
            view.onRenderingFailure = { [weak self] in self?.errors.append($0) }
        }

        func ready(selection: RecordingCanvasSelection? = .image("first")) async {
            await model.previewTask?.value
            if selection == .image("first"), model.timeline?.clips.first?.content.trackKind == .video {
                self.selection = .video("first")
            } else { self.selection = selection }
            view.configure(project: model.project, sourceTime: 0, baseImage: base,
                           selection: self.selection, editable: true, multitrackScene: scene)
        }

        func close() {
            view.cancelEditing()
            window.close()
            model.shutdown()
            media.close()
        }

        func mouse(_ type: NSEvent.EventType, x: Double, y: Double, clicks: Int = 1) throws -> NSEvent {
            let point = view.convert(CGPoint(x: x * view.bounds.width, y: y * view.bounds.height), to: nil)
            return try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
        }

        func escape() throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: 53))
        }
    }
}
