import Foundation
import Testing

@testable import ZislaCore

struct ScreenRecordingCaptionLayoutTests {
    @Test
    func captionsWithoutLayoutKeepTheirLegacyDefaults() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"start\":0,\"end\":1,\"text\":\"字幕\"}".utf8)
        let caption = try JSONDecoder().decode(RecordingCaption.self, from: data)
        #expect(caption == RecordingCaption(id: id, start: 0, end: 1, text: "字幕"))
        #expect(caption.layout == nil && caption.fontSize == nil)
        var project = fixture()
        project.captions = [caption]
        try project.validate()
    }

    @Test
    func editedCaptionLayoutAndFontRoundTripInTheSameProject() throws {
        var project = fixture()
        project.captions = [.init(start: 0, end: 2, text: "1234\n字幕 مرحبا",
                                  layout: .init(x: 0.1, y: 0.2, width: 0.6, height: 0.3), fontSize: 0.075)]
        try project.validate()
        let restored = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(project))
        #expect(restored == project)
        try restored.validate()
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.01, 0.0, 0.009, 0.301])
    func projectsRejectInvalidCaptionFontSizes(_ fontSize: Double) {
        var project = fixture()
        project.captions = [.init(start: 0, end: 1, text: "Label", fontSize: fontSize)]
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try project.validate() }
    }

    @Test(arguments: [0.01, 0.035, 0.3])
    func projectsAcceptCaptionFontSizeBoundaries(_ fontSize: Double) throws {
        var project = fixture()
        project.captions = [.init(start: 0, end: 1, text: "Label", fontSize: fontSize)]
        try project.validate()
    }

    @Test
    func projectsRejectInvalidCaptionLayoutCoordinatesAndEmptyBoxes() {
        let layouts: [RecordingRect] = [
            .init(x: -.infinity, y: 0, width: 0.5, height: 0.5),
            .init(x: 0, y: .nan, width: 0.5, height: 0.5),
            .init(x: -0.01, y: 0, width: 0.5, height: 0.5),
            .init(x: 0.6, y: 0, width: 0.5, height: 0.5),
            .init(x: 0, y: 0.6, width: 0.5, height: 0.5),
            .init(x: 0, y: 0, width: 0, height: 0.5),
            .init(x: 0, y: 0, width: 0.5, height: -0.1),
        ]
        for layout in layouts {
            var project = fixture()
            project.captions = [.init(start: 0, end: 1, text: "Label", layout: layout)]
            #expect(throws: ScreenRecordingProjectError.invalidProject) { try project.validate() }
        }
    }

    private func fixture() -> ScreenRecordingProject {
        ScreenRecordingProject(name: "Caption Layout", videoFile: "screen.mp4", duration: 2, width: 800, height: 600)
    }
}
