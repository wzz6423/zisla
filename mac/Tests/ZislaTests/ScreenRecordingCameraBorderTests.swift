import AppKit
import CoreImage
import Testing
import ZislaCore

@testable import Zisla

@MainActor
struct ScreenRecordingCameraBorderTests {
    @Test
    func previewBorderFollowsTheChoiceAndResizesWithTheCamera() throws {
        let view = ScreenRecordingCameraPreviewView(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
        defer { view.detach() }
        let layer = try #require(view.layer?.sublayers?.first)
        view.update(session: nil, state: .running, configuration: .init())
        view.layoutSubtreeIfNeeded()
        #expect(layer.borderWidth == 0, "A new camera preview must not add a border")
        for enabled in [true, false, true] {
            view.update(session: nil, state: .running, configuration: .init(cameraBorder: enabled))
            view.layoutSubtreeIfNeeded()
            #expect(layer.borderWidth == (enabled ? 1.6 : 0))
        }
        let cornerRadius = layer.cornerRadius
        view.setFrameSize(CGSize(width: 420, height: 340))
        view.layoutSubtreeIfNeeded()
        #expect(layer.borderWidth == 3.2)
        #expect(layer.cornerRadius == cornerRadius * 2, "Changing border visibility must leave the camera shape intact")
        view.update(session: nil, state: .idle, configuration: .init(cameraBorder: false))
        view.layoutSubtreeIfNeeded()
        #expect(layer.borderWidth == 0)
    }

    @Test(arguments: [false, true])
    func renderedBorderFollowsTheCameraOutlineAndCanBeRemoved(round: Bool) throws {
        var project = project(round: round)
        let plain = try render(project)
        project.edits.cameraBorder = true
        let bordered = try render(project)
        let edge = try green(bordered, x: 88, y: 8)
        #expect(edge > 0.65 && edge < 0.97, "The camera edge must show the translucent white border used by the live preview")
        #expect(try green(plain, x: 88, y: 8) < 0.05)
        #expect(try green(bordered, x: 88, y: 88) < 0.05, "A border must not tint the camera content")
        #expect(try green(bordered, x: 88, y: 11) < 0.05, "Pixels beyond the inner antialiasing transition must not be tinted")
        #expect(try green(bordered, x: 88, y: 6) < 0.05, "The border must stay inside the camera bounds")
        if round {
            #expect(try green(bordered, x: 8, y: 8) < 0.05, "A circular camera must not gain rectangular border corners")
        }
        project.edits.cameraBorder = false
        #expect(try bytes(render(project)) == bytes(plain), "Turning the border back off must restore the original image")
    }

    @Test
    func hiddenOrUnavailableCameraDoesNotLeaveABorderBehind() throws {
        var project = project(round: false)
        let noCamera = try render(project, hasCamera: false)
        project.edits.cameraBorder = true
        #expect(try bytes(render(project, hasCamera: false)) == bytes(noCamera))
        project.edits.showCamera = false
        #expect(try bytes(render(project)) == bytes(noCamera))
    }

    private func project(round: Bool) -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Border", videoFile: "screen.mp4", duration: 1, width: 400, height: 320)
        project.edits.background = .none
        project.edits.showCursor = false
        project.edits.clickEffects = false
        project.edits.cameraPosition = .topLeft
        project.edits.cameraSize = 0.5
        project.edits.cameraRound = round
        project.edits.cameraAspectRatio = .square
        project.edits.cameraCornerRadius = round ? 0.5 : 0
        return project
    }

    private func render(_ project: ScreenRecordingProject, hasCamera: Bool = true) throws -> CGImage {
        let canvas = CGRect(x: 0, y: 0, width: project.width, height: project.height)
        return try RecordingExportRenderer(project: project, size: canvas.size).image(
            screen: CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: canvas),
            camera: hasCamera ? CIImage(color: .black).cropped(to: canvas) : nil, sourceTime: 0)
    }

    private func green(_ image: CGImage, x: Int, y: Int) throws -> Double {
        Double(try bytes(image)[(y * image.width + x) * 4 + 1]) / 255
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try #require(CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
