import Foundation
import Testing

@testable import ZislaCore

struct ScreenRecordingVisualEditingModelsTests {
    @Test
    func canvasRatiosHaveStableValuesAndOriginalPreservesTheSourceRatio() throws {
        #expect(RecordingCanvasAspectRatio.allCases.count == 5)
        #expect(RecordingCanvasAspectRatio.original.ratio == nil)
        #expect(RecordingCanvasAspectRatio.landscape.ratio == 16.0 / 9)
        #expect(RecordingCanvasAspectRatio.portrait.ratio == 9.0 / 16)
        #expect(RecordingCanvasAspectRatio.square.ratio == 1)
        #expect(RecordingCanvasAspectRatio.standard.ratio == 4.0 / 3)
        for ratio in RecordingCanvasAspectRatio.allCases {
            let decoded = try JSONDecoder().decode(RecordingCanvasAspectRatio.self, from: JSONEncoder().encode(ratio))
            #expect(decoded == ratio)
        }
    }

    @Test(arguments: [0.0, 0.5, 1.0])
    func colorRoundTripsAtNormalizedBoundaries(_ component: Double) throws {
        let color = RecordingColor(red: component, green: component, blue: component)
        #expect(color.isValid)
        let decoded = try JSONDecoder().decode(RecordingColor.self, from: JSONEncoder().encode(color))
        #expect(decoded == color)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.001, 1.001])
    func colorsRejectNonFiniteAndOutOfRangeChannels(_ component: Double) {
        #expect(!RecordingColor(red: component, green: 0, blue: 0).isValid)
        #expect(!RecordingColor(red: 0, green: component, blue: 0).isValid)
        #expect(!RecordingColor(red: 0, green: 0, blue: component).isValid)
    }

    @Test(arguments: RecordingAnnotationKind.allCases)
    func annotationsRoundTripAndUseOriginalSourceTime(_ kind: RecordingAnnotationKind) throws {
        let annotation = RecordingAnnotation(kind: kind, start: 1, end: 2, text: "说明 مرحبا 👋")
        #expect(annotation.isValid(duration: 3))
        #expect(!annotation.isVisible(at: 0.999))
        #expect(annotation.isVisible(at: 1))
        #expect(annotation.isVisible(at: 1.999))
        #expect(!annotation.isVisible(at: 2))
        let decoded = try JSONDecoder().decode(RecordingAnnotation.self, from: JSONEncoder().encode(annotation))
        #expect(decoded == annotation)
    }

    @Test
    func arrowsAllowEitherDirectionAndAxisAlignedEndpointsWhileBoxesNeedAnArea() {
        var arrow = RecordingAnnotation(kind: .arrow, start: 0, end: 1, x: 0.8, y: 0.7, endX: 0.2, endY: 0.1)
        #expect(arrow.isValid(duration: 1))
        #expect(arrow.bounds.x == 0.2 && arrow.bounds.y == 0.1)
        #expect(abs(arrow.bounds.width - 0.6) < 0.000_001 && abs(arrow.bounds.height - 0.6) < 0.000_001)
        arrow.endX = arrow.x
        #expect(arrow.isValid(duration: 1))
        arrow.kind = .rectangle
        #expect(!arrow.isValid(duration: 1))
        arrow.kind = .text
        #expect(!arrow.isValid(duration: 1))
        arrow.kind = .arrow
        arrow.endY = arrow.y
        #expect(!arrow.isValid(duration: 1))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.001, 1.001])
    func annotationEndpointsRejectNonFiniteAndOutsideCanvasCoordinates(_ coordinate: Double) {
        for path in [\RecordingAnnotation.x, \.y, \.endX, \.endY] {
            var annotation = RecordingAnnotation(kind: .arrow, start: 0, end: 1)
            annotation[keyPath: path] = coordinate
            #expect(!annotation.isValid(duration: 1))
        }
    }

    @Test
    func annotationsRejectInvalidTimesStyleAndUnboundedTextButAllowAnEmptyTextDraft() {
        var annotation = RecordingAnnotation(kind: .text, start: 0, end: 1)
        #expect(annotation.isValid(duration: 1))
        for (start, end) in [(Double.nan, 1.0), (0, Double.infinity), (-1, 1), (1, 1), (0, 1.01)] {
            annotation.start = start
            annotation.end = end
            #expect(!annotation.isValid(duration: 1))
        }
        annotation.start = 0
        annotation.end = 1
        annotation.text = String(repeating: "x", count: 4_001)
        #expect(!annotation.isValid(duration: 1))
        annotation.text = "Draft"
        for path in [\RecordingAnnotation.fontSize, \.lineWidth] {
            let original = annotation[keyPath: path]
            annotation[keyPath: path] = .nan
            #expect(!annotation.isValid(duration: 1))
            annotation[keyPath: path] = original
        }
        annotation.color = .init(red: -1, green: 1, blue: 1)
        #expect(!annotation.isValid(duration: 1))
    }

    @Test
    func legacyProjectWithoutVisualEditingFieldsLoadsWithItsOriginalAppearance() throws {
        var project = ScreenRecordingProject(name: "Legacy", videoFile: "screen.mp4", duration: 3, width: 160, height: 90)
        project.edits.canvasAspectRatio = .portrait
        project.edits.backgroundColor = .background
        project.edits.annotations = [.init(kind: .text, start: 0, end: 1, text: "Label")]
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        var edits = try #require(object["edits"] as? [String: Any])
        for key in ["canvasAspectRatio", "backgroundColor", "annotations"] { edits.removeValue(forKey: key) }
        object["edits"] = edits
        let restored = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONSerialization.data(withJSONObject: object))
        try restored.validate()
        #expect(restored.edits.canvasAspectRatio == nil)
        #expect(restored.edits.backgroundColor == nil)
        #expect(restored.edits.annotations == nil)
        #expect(restored.version == project.version)
    }

    @Test
    func visualEditingRoundTripsAndRejectsInvalidPayloadsWithoutDiscardingOtherEdits() throws {
        var project = ScreenRecordingProject(name: "Visual", videoFile: "screen.mp4", duration: 3, width: 160, height: 90)
        project.edits.canvasAspectRatio = .square
        project.edits.backgroundColor = .init(red: 0.1, green: 0.2, blue: 0.3)
        let annotation = RecordingAnnotation(kind: .rectangle, start: 0, end: 3)
        project.edits.annotations = [annotation]
        try project.validate()
        let restored = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(project))
        #expect(restored == project)
        project.edits.annotations = [annotation, annotation]
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try project.validate() }
        project.edits.annotations = (0...RecordingAnnotation.maximumCount).map { _ in .init(kind: .arrow, start: 0, end: 1) }
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try project.validate() }
        project.edits.annotations = [.init(kind: .text, start: 2, end: 4)]
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try project.validate() }
        project.edits.annotations = []
        project.edits.backgroundColor = .init(red: 0, green: .nan, blue: 0)
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try project.validate() }
    }
}
