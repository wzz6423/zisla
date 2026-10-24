import AppKit
import CoreImage
import Testing
import ZislaCore

@testable import Zisla

@Suite @MainActor
struct ScreenRecordingVisualEditingTests {
    @Test(arguments: RecordingCanvasAspectRatio.allCases)
    func canvasPresetsKeepTheirRatioAndEvenPixelDimensions(_ ratio: RecordingCanvasAspectRatio) throws {
        var edits = RecordingEdits()
        edits.canvasAspectRatio = ratio
        for resolution in RecordingExportResolution.allCases {
            let size = try RecordingExportRenderer.outputSize(source: .init(width: 1920, height: 1080), edits: edits, resolution: resolution)
            let expected = ratio.ratio ?? 16.0 / 9
            #expect(abs(size.width / size.height - expected) < 0.003)
            #expect(Int(size.width).isMultiple(of: 2) && Int(size.height).isMultiple(of: 2))
            #expect(max(size.width, size.height) == (resolution == .source || resolution == .fullHD ? 1920
                                                     : resolution == .quadHD ? 2560 : 3840))
        }
    }

    @Test
    func cropIsAppliedBeforeChoosingTheOutputCanvas() throws {
        var edits = RecordingEdits(crop: .init(x: 0.25, y: 0, width: 0.5, height: 1))
        #expect(try RecordingExportRenderer.outputSize(source: .init(width: 1920, height: 1080), edits: edits, resolution: .source)
            == CGSize(width: 960, height: 1080))
        edits.canvasAspectRatio = .square
        #expect(try RecordingExportRenderer.outputSize(source: .init(width: 1920, height: 1080), edits: edits, resolution: .source)
            == CGSize(width: 1080, height: 1080))
    }

    @Test
    func customBackgroundAndPortraitCanvasPreserveTheWholeScreenAndShowTheirChosenColor() throws {
        var project = project(width: 160, height: 90)
        project.edits.canvasAspectRatio = .portrait
        project.edits.backgroundColor = .init(red: 1, green: 0, blue: 0)
        let size = try RecordingExportRenderer.outputSize(source: .init(width: 160, height: 90), edits: project.edits, resolution: .source)
        #expect(size == CGSize(width: 90, height: 160))
        let renderer = try RecordingExportRenderer(project: project, size: size)
        let image = try renderer.image(screen: solid(red: 0, green: 1, blue: 0, width: 160, height: 90), camera: nil, sourceTime: 0)
        #expect(renderer.screenRect.width == 90)
        #expect(abs(renderer.screenRect.height - 50.625) < 0.001)
        #expect(try pixel(image, x: 5, y: 5).red > 0.9)
        #expect(try pixel(image, x: 45, y: 80).green > 0.9)
    }

    @Test(arguments: RecordingAnnotationKind.allCases)
    func annotationsAppearOnlyWithinTheirOriginalSourceTimeRange(_ kind: RecordingAnnotationKind) throws {
        var project = project()
        project.edits.annotations = [.init(kind: kind, start: 1, end: 2, x: 0.1, y: 0.1, endX: 0.9, endY: 0.6,
                                           text: "Hello 你好", color: .init(red: 1, green: 1, blue: 1), fontSize: 0.15, lineWidth: 0.02)]
        let renderer = try RecordingExportRenderer(project: project, size: .init(width: 200, height: 160))
        let screen = solid(red: 0, green: 0, blue: 0, width: 200, height: 160)
        for time in [0.999, 1.0, 1.999, 2.0] {
            let image = try renderer.image(screen: screen, camera: nil, sourceTime: time)
            let pixels = try bytes(image)
            let visible = stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] > 128 }
            #expect(visible == (time >= 1 && time < 2))
        }
    }

    @Test(arguments: [0.025, 0.05])
    func arrowHeadAndRectangleOutlineRenderInCanvasCoordinatesAndChosenColors(_ lineWidth: Double) throws {
        var project = project()
        project.edits.annotations = [.init(kind: .arrow, start: 0, end: 1, x: 0.2, y: 0.5, endX: 0.8, endY: 0.5,
                                           color: .init(red: 0, green: 0, blue: 1), lineWidth: lineWidth)]
        let screen = solid(red: 0, green: 0, blue: 0, width: 200, height: 160)
        let arrow = try RecordingExportRenderer(project: project, size: .init(width: 200, height: 160))
            .image(screen: screen, camera: nil, sourceTime: 0)
        #expect(try pixel(arrow, x: 100, y: 80).blue > 0.9)
        #expect(try pixel(arrow, x: 150, y: 74).blue > 0.8)
        #expect(try pixel(arrow, x: 150, y: 86).blue > 0.8)
        if lineWidth == 0.05 {
            #expect(try pixel(arrow, x: 140, y: 68).blue > 0.8)
            #expect(try pixel(arrow, x: 140, y: 92).blue > 0.8)
        }
        #expect(try pixel(arrow, x: 100, y: 60).blue < 0.1)
        project.edits.annotations = [.init(kind: .rectangle, start: 0, end: 1, x: 0.2, y: 0.2, endX: 0.8, endY: 0.7,
                                           color: .init(red: 1, green: 0, blue: 0), lineWidth: 0.025)]
        let rectangle = try RecordingExportRenderer(project: project, size: .init(width: 200, height: 160))
            .image(screen: screen, camera: nil, sourceTime: 0)
        #expect(try pixel(rectangle, x: 40, y: 60).red > 0.9)
        #expect(try pixel(rectangle, x: 100, y: 70).red < 0.1)
        #expect(try pixel(rectangle, x: 35, y: 60).red < 0.1)
    }

    @Test
    func emptyTextDraftDoesNotDrawAndColorPickerProducesNormalizedSRGB() throws {
        var project = project()
        project.edits.annotations = [.init(kind: .text, start: 0, end: 1)]
        let image = try RecordingExportRenderer(project: project, size: .init(width: 200, height: 160))
            .image(screen: solid(red: 0, green: 0, blue: 0, width: 200, height: 160), camera: nil, sourceTime: 0)
        let pixels = try bytes(image)
        #expect(!stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] > 0 })
        let color = try #require(ScreenRecordingColorPicker.components(for: NSColor(srgbRed: 1.2, green: -0.2, blue: 0.5, alpha: 1)))
        #expect(color.isValid)
        #expect(color.red == 1 && color.green == 0 && abs(color.blue - 0.5) < 0.001)
        #expect(ScreenRecordingColorPicker.components(for: NSColor(patternImage: NSImage(size: .init(width: 2, height: 2)))) == nil)
    }

    private func project(width: Int = 200, height: Int = 160) -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Visual", videoFile: "screen.mp4", duration: 3, width: width, height: height)
        project.edits.background = .none
        project.edits.padding = 0
        project.edits.cornerRadius = 0
        project.edits.shadow = 0
        project.edits.showCursor = false
        project.edits.clickEffects = false
        return project
    }

    private func solid(red: Double, green: Double, blue: Double, width: Int, height: Int) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue)).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (red: Double, green: Double, blue: Double) {
        let pixels = try bytes(image)
        let offset = (y * image.width + x) * 4
        return (Double(pixels[offset]) / 255, Double(pixels[offset + 1]) / 255, Double(pixels[offset + 2]) / 255)
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(data: pointer.baseAddress, width: image.width, height: image.height,
                                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}
