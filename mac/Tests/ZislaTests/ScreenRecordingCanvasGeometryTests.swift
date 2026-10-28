import CoreGraphics
import Testing
import ZislaCore

@testable import Zisla

struct ScreenRecordingCanvasGeometryTests {
    private let canvas = CGSize(width: 800, height: 600)

    @Test
    func aspectFitUsesTheDisplayedCanvasAndExcludesLetterboxing() {
        #expect(RecordingCanvasGeometry.fittedRect(canvas: canvas, in: CGRect(x: 0, y: 0, width: 1_000, height: 600))
            == CGRect(x: 100, y: 0, width: 800, height: 600))
        #expect(RecordingCanvasGeometry.fittedRect(canvas: canvas, in: CGRect(x: 0, y: 0, width: 400, height: 600))
            == CGRect(x: 0, y: 150, width: 400, height: 300))
        #expect(RecordingCanvasGeometry.fittedRect(canvas: .zero, in: .zero) == .zero)
    }

    @Test(arguments: RecordingAnnotationKind.allCases)
    func movingAnnotationsClampsTheWholeObjectAndPreservesItsDirectionAndStyle(_ kind: RecordingAnnotationKind) {
        let annotation = RecordingAnnotation(kind: kind, start: 0, end: 1, x: 0.7, y: 0.6, endX: 0.2, endY: 0.2, text: "1234")
        let original = RecordingCanvasElement.annotation(annotation)
        guard case let .annotation(moved) = RecordingCanvasGeometry.transformed(original,
            by: CGSize(width: 1_000, height: -1_000), handle: nil, canvas: canvas) else { Issue.record("Expected annotation"); return }
        let bounds = RecordingCanvasElement.annotation(moved).bounds(canvas: canvas)
        #expect(abs(bounds.maxX - canvas.width) < 1 && bounds.minY == 0)
        #expect(abs(bounds.width - original.bounds(canvas: canvas).width) < 1)
        #expect(abs(bounds.height - original.bounds(canvas: canvas).height) < 1)
        #expect(moved.x > moved.endX && moved.y > moved.endY)
        #expect(moved.text == annotation.text && moved.fontSize == annotation.fontSize && moved.lineWidth == annotation.lineWidth)
        #expect(moved.isValid(duration: 1))
    }

    @Test
    func textCornerResizingScalesLettersWithTheBoxAndKeepsTheOppositeCorner() {
        let original = RecordingAnnotation(kind: .text, start: 0, end: 1, x: 0.1, y: 0.1, endX: 0.3, endY: 0.3, text: "1234")
        let originalBounds = RecordingCanvasElement.annotation(original).bounds(canvas: canvas)
        guard case let .annotation(resized) = RecordingCanvasGeometry.transformed(.annotation(original),
            by: originalBounds.size, handle: .bottomRight, canvas: canvas) else { Issue.record("Expected annotation"); return }
        #expect(resized.x == original.x && resized.y == original.y)
        let resizedBounds = RecordingCanvasElement.annotation(resized).bounds(canvas: canvas)
        #expect(abs(resizedBounds.width - originalBounds.width * 2) <= 1)
        #expect(abs(resizedBounds.height - originalBounds.height * 2) <= 1)
        #expect(abs(resized.fontSize - 0.12) < 0.000_001)
        #expect(resized.isValid(duration: 1))
    }

    @Test(arguments: [RecordingCanvasHandle.topLeft, .topRight, .bottomLeft, .bottomRight])
    func rectangleCornersResizeWithoutInvertingOrLeavingTheCanvas(_ handle: RecordingCanvasHandle) {
        let original = RecordingAnnotation(kind: .rectangle, start: 0, end: 1)
        for delta in [CGSize(width: 10_000, height: 10_000), CGSize(width: -10_000, height: -10_000)] {
            guard case let .annotation(resized) = RecordingCanvasGeometry.transformed(.annotation(original), by: delta,
                handle: handle, canvas: canvas) else { Issue.record("Expected annotation"); return }
            #expect(resized.isValid(duration: 1))
            #expect(resized.fontSize == original.fontSize && resized.lineWidth == original.lineWidth)
        }
    }

    @Test
    func arrowSelectionFollowsTheLineAndEndpointEditsCanReverseItsDirection() {
        let annotation = RecordingAnnotation(kind: .arrow, start: 0, end: 1, x: 0.2, y: 0.2, endX: 0.8, endY: 0.8)
        let element = RecordingCanvasElement.annotation(annotation)
        #expect(RecordingCanvasGeometry.hit(element, at: CGPoint(x: 400, y: 300), canvas: canvas, tolerance: 6))
        #expect(!RecordingCanvasGeometry.hit(element, at: CGPoint(x: 400, y: 150), canvas: canvas, tolerance: 6))
        guard case let .annotation(moved) = RecordingCanvasGeometry.transformed(element,
            by: CGSize(width: -600, height: 0), handle: .end, canvas: canvas) else { Issue.record("Expected annotation"); return }
        #expect(moved.x == 0.2 && abs(moved.endX - 0.05) < 0.000_001)
        #expect(moved.y == annotation.y && moved.endY == annotation.endY)
        #expect(moved.isValid(duration: 1))
        let collision = RecordingCanvasGeometry.transformed(element, by: CGSize(width: -480, height: -360), handle: .end, canvas: canvas)
        #expect(collision == element, "Coincident arrow endpoints must retain the previous valid object")
    }

    @Test
    func captionsMoveAndScaleUsingTheSameBoundsAsTheirRenderedBackground() {
        let original = RecordingCaption(start: 0, end: 1, text: "字幕1234")
        let element = RecordingCanvasElement.caption(original)
        let before = element.bounds(canvas: canvas)
        guard case let .caption(moved) = RecordingCanvasGeometry.transformed(element,
            by: CGSize(width: 0, height: -120), handle: nil, canvas: canvas) else { Issue.record("Expected caption"); return }
        let movedBox = RecordingCanvasElement.caption(moved).bounds(canvas: canvas)
        #expect(abs(movedBox.minY - before.minY + 120) < 0.000_001)
        #expect(abs(movedBox.width - before.width) < 0.000_001 && abs(movedBox.height - before.height) < 0.000_001)
        #expect(moved.fontSize == nil, "Moving a caption must preserve its automatic font size")
        let resized = RecordingCanvasGeometry.transformed(.caption(moved),
            by: CGSize(width: -before.width / 2, height: -before.height / 2), handle: .bottomRight, canvas: canvas)
        guard case let .caption(value) = resized else { Issue.record("Expected caption"); return }
        #expect(abs((value.fontSize ?? 0) - 0.0175) < 0.000_001)
        #expect(abs(resized.bounds(canvas: canvas).width - before.width / 2) < 0.000_001)
        #expect(value.layout?.isNormalized == true)
    }

    @Test
    func onlyTheTopVisibleCaptionAndAnnotationsAtTheCurrentSourceTimeAreSelectable() {
        var project = ScreenRecordingProject(name: "Canvas", videoFile: "screen.mp4", duration: 3, width: 800, height: 600)
        let annotation = RecordingAnnotation(kind: .text, start: 1, end: 2, text: "1234")
        let first = RecordingCaption(start: 1, end: 2, text: "First")
        project.edits.annotations = [annotation]
        project.captions = [first, .init(start: 1, end: 3, text: "Second")]
        #expect(RecordingCanvasElement.visible(in: project, at: 0).isEmpty)
        #expect(RecordingCanvasElement.visible(in: project, at: 1) == [.annotation(annotation), .caption(first)])
        #expect(RecordingCanvasElement.visible(in: project, at: 2).count == 1)
        project.edits.showCaptions = false
        #expect(RecordingCanvasElement.visible(in: project, at: 2).isEmpty)
    }

    @Test
    func invalidEventsAndNoMotionRetainTheOriginalObjectAndConcurrentEditsAreNeverOverwritten() {
        let caption = RecordingCanvasElement.caption(RecordingCaption(start: 0, end: 1, text: "Caption"))
        #expect(RecordingCanvasGeometry.transformed(caption, by: .zero, handle: nil, canvas: canvas) == caption)
        #expect(RecordingCanvasGeometry.transformed(caption, by: CGSize(width: CGFloat.nan, height: 1), handle: nil, canvas: canvas) == caption)
        #expect(RecordingCanvasGeometry.transformed(caption, by: CGSize(width: 1, height: 1), handle: nil, canvas: .zero) == caption)
        var project = ScreenRecordingProject(name: "Canvas", videoFile: "screen.mp4", duration: 2, width: 800, height: 600)
        if case let .caption(value) = caption { project.captions = [value] }
        project.captions[0].text = "Newer edit"
        let newer = project
        caption.replacingText("Old draft").write(to: &project, replacing: caption)
        #expect(project == newer)
    }

    @Test
    func tinyAndEdgeAlignedBoxesStayValidWhenResizeMinimumsExceedTheAvailableSpace() throws {
        let boxes: [RecordingRect] = [
            .init(x: 0, y: 0, width: 0.000_001, height: 0.000_001),
            .init(x: 0.999_999, y: 0.999_999, width: 0.000_001, height: 0.000_001),
            .init(x: 0, y: 0, width: 1, height: 1),
            .init(x: 0.2, y: 0.9, width: 0.000_01, height: 0.1),
        ]
        let deltas = [CGSize.zero, CGSize(width: 10_000, height: 10_000), CGSize(width: -10_000, height: -10_000)]
        for box in boxes {
            for fontSize in [0.01, 0.3] {
                let text = RecordingAnnotation(kind: .text, start: 0, end: 1, x: box.x, y: box.y,
                    endX: box.x + box.width, endY: box.y + box.height, text: "1234", fontSize: fontSize)
                let caption = RecordingCaption(start: 0, end: 1, text: "Caption", layout: box, fontSize: fontSize)
                for element in [RecordingCanvasElement.annotation(text), .caption(caption)] {
                    for handle in [RecordingCanvasHandle.topLeft, .topRight, .bottomLeft, .bottomRight] {
                        for delta in deltas {
                            let resized = RecordingCanvasGeometry.transformed(element, by: delta, handle: handle, canvas: canvas)
                            var project = ScreenRecordingProject(name: "Edge", videoFile: "screen.mp4", duration: 1, width: 800, height: 600)
                            switch resized {
                            case let .annotation(value): project.edits.annotations = [value]
                            case let .caption(value): project.captions = [value]
                            case .image: Issue.record("Expected a text element")
                            }
                            try project.validate()
                        }
                    }
                }
            }
        }
    }
}
