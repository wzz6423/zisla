import AppKit
import CoreImage
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct ScreenRecordingCanvasPreviewTests {
    @Test
    func previewExtractsOneCleanFrameAndAddsExactlyTheSameOverlaysAsExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-canvas-preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let base = try image(width: 400, color: .black)
        let store = ScreenRecordingProjectStore(root: root)
        let directory = try store.createDirectory()
        try Data([1]).write(to: directory.appendingPathComponent("screen.mp4"))
        var project = fixture()
        project.edits.annotations = [.init(kind: .text, start: 0, end: 2, text: "1234")]
        project.captions = [.init(start: 0, end: 2, text: "Caption", layout: .init(x: 0.1, y: 0.6, width: 0.8, height: 0.2), fontSize: 0.06)]
        var calls = 0
        let model = ScreenRecordingStudioModel(projectStore: store, renderPreview: { requested, _, _ in
            calls += 1
            #expect(requested.edits.annotations?.isEmpty == true && !requested.edits.showCaptions,
                    "The base video frame must never bake editable overlays")
            return base
        })
        defer { model.shutdown() }
        model.install(project, directory: directory)
        await model.previewTask?.value
        #expect(calls == 1, "Editing must not decode the source video twice for one preview")
        #expect(try bytes(#require(model.canvasPreview)) == bytes(base))
        let expected = try RecordingExportRenderer(project: project, size: CGSize(width: base.width, height: base.height))
            .image(screen: CIImage(cgImage: base), camera: nil, sourceTime: 0)
        let preview = try #require(model.preview?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(try bytes(preview) == bytes(expected), "The regular preview must retain complete exported overlays")
        #expect(model.project == project && !model.canUndo && !model.isDirty)
    }

    @Test
    func latePreviewAndFailedPreviewKeepTheLatestBaseAndCompleteImageTogether() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-canvas-preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScreenRecordingProjectStore(root: root)
        let directory = try store.createDirectory()
        try Data([1]).write(to: directory.appendingPathComponent("screen.mp4"))
        let stale = Gate<CGImage>()
        let latest = Gate<CGImage>()
        let model = ScreenRecordingStudioModel(projectStore: store, renderPreview: { _, _, time in
            if time == 0 { return try await stale.wait() }
            if time == 1 { return try await latest.wait() }
            throw ScreenRecordingExportError.cannotRender
        })
        defer { model.shutdown() }
        model.install(fixture(), directory: directory)
        await stale.entered()
        let first = model.previewTask
        model.seek(to: 1)
        await latest.entered()
        latest.resolve(try image(width: 200, color: CIColor(red: 0, green: 0, blue: 1)))
        await model.previewTask?.value
        let base = try bytes(#require(model.canvasPreview))
        let full = try bytes(#require(model.preview?.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        stale.resolve(try image(width: 100, color: CIColor(red: 1, green: 0, blue: 0)))
        await first?.value
        #expect(model.canvasPreview?.width == 200 && model.preview?.size.width == 200)
        #expect(try bytes(#require(model.canvasPreview)) == base)
        #expect(try bytes(#require(model.preview?.cgImage(forProposedRect: nil, context: nil, hints: nil))) == full)
        model.seek(to: 2)
        await model.previewTask?.value
        #expect(model.errorMessage == ScreenRecordingExportError.cannotRender.localizedDescription)
        #expect(try bytes(#require(model.canvasPreview)) == base)
        #expect(try bytes(#require(model.preview?.cgImage(forProposedRect: nil, context: nil, hints: nil))) == full)
    }

    @Test
    func customCaptionFontSizeChangesTheExportedGlyphPixels() throws {
        let base = try image(width: 400, color: .black)
        var counts: [Int] = []
        for fontSize in [0.03, 0.09] {
            var project = fixture()
            project.captions = [.init(start: 0, end: 2, text: "MMMM",
                layout: .init(x: 0.1, y: 0.2, width: 0.8, height: 0.5), fontSize: fontSize)]
            let output = try RecordingExportRenderer(project: project, size: CGSize(width: 400, height: 300))
                .image(screen: CIImage(cgImage: base), camera: nil, sourceTime: 0)
            let pixels = try bytes(output)
            counts.append(stride(from: 0, to: pixels.count, by: 4).filter {
                pixels[$0] > 240 && pixels[$0 + 1] > 240 && pixels[$0 + 2] > 240
            }.count)
        }
        #expect(counts[0] > 0 && counts[1] > counts[0] * 4,
                "The saved caption font size must change exported glyphs, not only the editor handles")
    }

    @Test
    func tinyCustomCaptionBoxesRemainRenderable() throws {
        var project = fixture()
        project.captions = [.init(start: 0, end: 2, text: "字幕", layout: .init(x: 0, y: 0, width: 0.001, height: 0.001), fontSize: 0.3)]
        try project.validate()
        let layout = RecordingExportRenderer.captionLayout(project.captions[0], canvas: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(!layout.textRect.isEmpty && layout.box.contains(layout.textRect),
                "Caption editing must keep a positive text area inside even the smallest saved box")
        let base = try image(width: 400, color: .black)
        let output = try RecordingExportRenderer(project: project, size: CGSize(width: 400, height: 300))
            .image(screen: CIImage(cgImage: base), camera: nil, sourceTime: 0)
        #expect(output.width == 400 && output.height == 300)
    }

    private func fixture() -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Canvas", videoFile: "screen.mp4", duration: 3, width: 400, height: 300)
        project.edits.background = .none
        project.edits.padding = 0
        project.edits.cornerRadius = 0
        project.edits.shadow = 0
        project.edits.showCursor = false
        project.edits.clickEffects = false
        return project
    }

    private func image(width: Int, color: CIColor) throws -> CGImage {
        try #require(CIContext().createCGImage(CIImage(color: color), from: CGRect(x: 0, y: 0, width: width, height: 300)))
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(data: pointer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    @MainActor private final class Gate<Value: Sendable> {
        private var continuation: CheckedContinuation<Value, Error>?
        private var waiter: CheckedContinuation<Void, Never>?
        private var hasEntered = false
        func wait() async throws -> Value {
            hasEntered = true
            waiter?.resume()
            waiter = nil
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func entered() async {
            if hasEntered { return }
            await withCheckedContinuation { waiter = $0 }
        }
        func resolve(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    }
}
