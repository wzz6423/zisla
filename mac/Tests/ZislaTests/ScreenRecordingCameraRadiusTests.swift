import AppKit
import CoreImage
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct ScreenRecordingCameraRadiusTests {
    @Test(arguments: [Double?(nil), 0.0, 0.125, 0.5])
    func changingCameraRatioPreservesRadiusAndTheLegacyProjectFlag(radius: Double?) async throws {
        let image = try #require(CIContext().createCGImage(CIImage(color: .black),
            from: CGRect(x: 0, y: 0, width: 16, height: 16)))
        let model = ScreenRecordingStudioModel(renderPreview: { _, _, _ in image })
        defer { model.shutdown() }
        var project = ScreenRecordingProject(name: "Camera ratio", videoFile: "screen.mp4", cameraFile: "camera.mp4",
                                            duration: 1, width: 16, height: 16)
        project.edits.cameraRound = true
        project.edits.cameraCornerRadius = radius
        model.install(project, directory: URL(fileURLWithPath: "/synthetic-camera-radius"))
        await model.previewTask?.value
        let view = ScreenRecordingEffectsView(model: model)
        for ratio in [RecordingCameraAspectRatio.standard, .widescreen, .square] {
            view.cameraAspectRatioBinding.wrappedValue = ratio
            let edited = try #require(model.project?.edits)
            #expect(edited.effectiveCameraAspectRatio == ratio)
            #expect(edited.effectiveCameraCornerRadius == (radius ?? 0.5),
                    "Changing the aspect ratio must preserve the radius already shown by a legacy project")
            #expect(edited.cameraRound)
            #expect(edited.cameraSize == project.edits.cameraSize && edited.cameraBorder == project.edits.cameraBorder)
            #expect(edited.padding == 0 && edited.cornerRadius == 0 && edited.shadow == 0)
        }
    }

    @Test(arguments: [Double?(nil), 0.0, 0.125, 0.5])
    func studioShowsAndEditsRadiusForLegacyCircularProjects(radius: Double?) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let image = try #require(CIContext().createCGImage(CIImage(color: .black),
            from: CGRect(x: 0, y: 0, width: 16, height: 16)))
        let model = ScreenRecordingStudioModel(renderPreview: { _, _, _ in image })
        defer { model.shutdown() }
        var project = ScreenRecordingProject(name: "Camera radius", videoFile: "screen.mp4", cameraFile: "camera.mp4",
                                            duration: 1, width: 16, height: 16)
        project.edits.cameraRound = true
        project.edits.cameraAspectRatio = .square
        project.edits.cameraCornerRadius = radius
        model.install(project, directory: URL(fileURLWithPath: "/synthetic-camera-radius"))
        await model.previewTask?.value
        let host = NSHostingView(rootView: ScreenRecordingEffectsView(model: model))
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 1_400)
        let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        await settle(host)
        let disclosure = try #require(elements(in: host).first {
            value($0, key: "accessibilityRole") as? String == NSAccessibility.Role.disclosureTriangle.rawValue
                && (value($0, key: "accessibilityTitle") as? String == AppLocalization.text("摄像头叠加")
                    || value($0, key: "accessibilityLabel") as? String == AppLocalization.text("摄像头叠加"))
        })
        try perform("accessibilityPerformPress", on: disclosure)
        await settle(host)
        let controls = elements(in: host)
        #expect(controls.allSatisfy {
            value($0, key: "accessibilityTitle") as? String != AppLocalization.text("圆形摄像头")
                && value($0, key: "accessibilityLabel") as? String != AppLocalization.text("圆形摄像头")
        })
        let radiusSlider = try #require(controls.first {
            value($0, key: "accessibilityIdentifier") as? String == "screenRecording.cameraCornerRadius.slider"
        },
            "The camera inspector must expose radius even for an old circular project")
        #expect((value(radiusSlider, key: "accessibilityValue") as? NSNumber)?.doubleValue == (radius ?? 0.5))
        try perform(radius == 0 ? "accessibilityPerformIncrement" : "accessibilityPerformDecrement", on: radiusSlider)
        await settle(host)
        let updated = try #require(model.project)
        let editedRadius = try #require(updated.edits.cameraCornerRadius)
        #expect((0...0.5).contains(editedRadius))
        #expect(editedRadius != (radius ?? 0.5))
        #expect(updated.edits.effectiveCameraCornerRadius == editedRadius)
        #expect(updated.edits.cameraAspectRatio == .square)
        #expect(updated.edits.cameraRound, "Editing radius must keep the legacy project field compatible")
        #expect(updated.edits.padding == 0 && updated.edits.cornerRadius == 0 && updated.edits.shadow == 0)
        model.undo()
        await settle(host)
        #expect(model.project == project, "Undo must restore the original explicit or absent radius")
        #expect(!window.isVisible)
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    private func elements(in host: NSView) -> [NSObject] {
        var result: [NSObject] = []
        func visit(_ object: NSObject) {
            result.append(object)
            for child in value(object, key: "accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
        }
        for child in host.accessibilityChildren() as? [NSObject] ?? [] { visit(child) }
        return result
    }

    private func value(_ object: NSObject, key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }

    private func perform(_ action: String, on object: NSObject) throws {
        let selector = NSSelectorFromString(action)
        try #require(object.responds(to: selector))
        object.performSelector(onMainThread: selector, with: nil, waitUntilDone: true)
    }
}
