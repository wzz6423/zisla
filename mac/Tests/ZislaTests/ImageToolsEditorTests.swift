import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ImageToolsEditorTests {
    @Test(arguments: [ScreenshotTool.mosaic, .extraction])
    func sessionsKeepTheirSourceAndSelectToolsWithoutStartingExtraction(initialTool: ScreenshotTool) throws {
        let source = try image(pixelScale: 2)
        let original = try rgba(pixels(source))
        let session = ImageToolsEditorSession(image: source, initialTool: initialTool)
        #expect(session.model.image === source)
        #expect(session.model.tool == initialTool)
        #expect(session.model.obscureEffect == .pixelate)
        #expect(session.model.extractionMode == nil && !session.model.isExtracting)
        #expect(session.model.annotations.isEmpty && !session.model.canUndo && !session.model.canRedo)
        #expect(!session.isClosed && session.selectionState.selectedAnnotationID == nil)
        session.close()
        #expect(session.apply() == nil)
        #expect(try rgba(pixels(source)) == original)
    }

    @Test(arguments: ScreenshotObscureEffect.allCases, [1, 2])
    func applyingLocalObscuresPreservesUnselectedPixelsTransparencyAndResolution(
        effect: ScreenshotObscureEffect, pixelScale: Int
    ) throws {
        let source = try image(pixelScale: pixelScale)
        let sourcePixels = try rgba(pixels(source))
        let session = ImageToolsEditorSession(image: source)
        let before = try rgba(pixels(session.model.renderedImage()))
        let selection = CGRect(x: 24, y: 18, width: 48, height: 30)
        session.model.add(ScreenshotAnnotation(kind: .mosaic, rect: selection,
            obscureEffect: effect, obscureStrength: 8))
        let output = try #require(session.apply())
        let after = try rgba(output)
        #expect(output.width == 96 * pixelScale && output.height == 80 * pixelScale)
        var changedInside = 0
        var changedOutside = 0
        for y in 0..<output.height {
            for x in 0..<output.width {
                let offset = (y * output.width + x) * 4
                if before[offset..<(offset + 4)] != after[offset..<(offset + 4)] {
                    if selection.contains(CGPoint(x: CGFloat(x) / CGFloat(pixelScale),
                                                  y: CGFloat(y) / CGFloat(pixelScale))) {
                        changedInside += 1
                    } else { changedOutside += 1 }
                }
            }
        }
        #expect(changedInside > 0, "The selected region must contain processed pixels")
        #expect(changedOutside == 0, "Local obscuring must leave every unselected pixel unchanged")
        let bitmap = NSBitmapImageRep(cgImage: output)
        #expect(try #require(bitmap.colorAt(x: pixelScale, y: pixelScale)).alphaComponent == 0)
        #expect(try rgba(pixels(source)) == sourcePixels, "Applying must never mutate the source image")
        #expect(session.isClosed && session.apply() == nil)
    }

    @Test(arguments: ScreenshotObscureEffect.allCases)
    func sharedUndoAndRedoRestoreLocalObscuresBeforeApplying(effect: ScreenshotObscureEffect) throws {
        let session = ImageToolsEditorSession(image: try image())
        let original = try #require(session.model.pngData())
        session.model.add(ScreenshotAnnotation(kind: .mosaic,
            rect: CGRect(x: 24, y: 18, width: 48, height: 30), obscureEffect: effect, obscureStrength: 6))
        let obscured = try #require(session.model.pngData())
        #expect(obscured != original && session.model.canUndo)
        session.model.undo()
        #expect(session.model.pngData() == original && session.model.canRedo)
        session.model.redo()
        #expect(session.model.pngData() == obscured)
        session.model.undo()
        let output = try #require(session.apply())
        #expect(try rgba(output) == rgba(try #require(NSBitmapImageRep(data: original)?.cgImage)))
    }

    @Test(arguments: [ScreenshotAnnotation.Kind.mosaic, .brush, .text])
    func applyingIncludesVisibleDraftsWithoutMouseUp(kind: ScreenshotAnnotation.Kind) throws {
        let session = ImageToolsEditorSession(image: try image(pixelScale: 2))
        let before = try rgba(pixels(session.model.renderedImage()))
        let annotation = ScreenshotAnnotation(kind: kind,
            points: [CGPoint(x: 20, y: 24), CGPoint(x: 60, y: 42)],
            rect: CGRect(x: 20, y: 18, width: 50, height: 30),
            color: .black, lineWidth: 4, fontSize: 18,
            obscureEffect: .pixelate, obscureStrength: 6)
        if kind == .text {
            session.model.add(annotation, saveUndo: false)
            session.model.beginTextDraft(id: annotation.id, text: "", isNew: true)
            session.model.updateTextDraft(id: annotation.id, text: "Draft", isNew: true)
        } else { session.model.updatePendingAnnotationDraft(annotation) }
        let output = try #require(session.apply())
        #expect(output.width == 192 && output.height == 160)
        #expect(try rgba(output) != before)
        #expect(session.model.pendingAnnotationDraft == nil && session.model.pendingTextDraft == nil)
        #expect(session.model.annotations.count == 1 && session.model.annotations[0].id == annotation.id)
        if kind == .text { #expect(session.model.annotations[0].text == "Draft") }
        #expect(session.model.canUndo)
    }

    @Test
    func invalidImagesCannotApplyOrWriteToTheClipboard() {
        let session = ImageToolsEditorSession(image: NSImage())
        #expect(session.apply() == nil && !session.isClosed)
        #expect(session.model.statusMessage == AppLocalization.text("图片生成失败"))
        session.copyImage { _ in
            Issue.record("Invalid images must never be written to the clipboard")
            return true
        }
        #expect(session.model.statusMessage == AppLocalization.text("图片生成失败"))
    }

    @Test(arguments: [false, true])
    func copyingIsExplicitKeepsTheSessionOpenAndReportsWriteFailures(succeeds: Bool) throws {
        let source = try image(pixelScale: 2)
        let original = try rgba(pixels(source))
        let session = ImageToolsEditorSession(image: source)
        var writes = 0
        var data: Data?
        #expect(writes == 0 && session.model.statusMessage == nil)
        session.copyImage { png in writes += 1; data = png; return succeeds }
        let png = try #require(data)
        let bitmap = try #require(NSBitmapImageRep(data: png))
        #expect(bitmap.pixelsWide == 192 && bitmap.pixelsHigh == 160)
        #expect(try #require(bitmap.colorAt(x: 2, y: 2)).alphaComponent == 0)
        #expect(writes == 1 && !session.isClosed)
        #expect(session.model.statusMessage == AppLocalization.text(succeeds ? "已复制" : "无法写入剪贴板"))
        #expect(try rgba(pixels(source)) == original)
        session.close()
        session.copyImage { _ in writes += 1; return true }
        #expect(writes == 1, "A dismissed editor must not write to the clipboard")
    }

    @Test(arguments: ["recognition", "extraction"])
    func busySessionsCannotApplyOrCopyUntilTheirOperationFinishes(operation: String) async throws {
        let session = ImageToolsEditorSession(image: try image())
        let release = AsyncStream<Void>.makeStream()
        defer { release.continuation.finish() }
        let task: Task<Void, Never>?
        if operation == "recognition" {
            task = session.model.recognize(.text, recognizeImage: { _, _ in
                for await _ in release.stream {}
                return []
            }) { _, _ in Issue.record("Empty recognition must not present a result") }
        } else {
            task = session.model.selectExtractionMode(.foreground, extractImage: { source, _ in
                for await _ in release.stream {}
                return source
            })
        }
        #expect(session.model.isRecognizing || session.model.isExtracting)
        #expect(session.apply() == nil && !session.isClosed)
        session.copyImage { _ in Issue.record("Busy editors must not write to the clipboard"); return true }
        release.continuation.finish()
        let runningTask = try #require(task)
        await runningTask.value
        #expect(!session.model.isRecognizing && !session.model.isExtracting)
        #expect(session.apply() != nil && session.isClosed)
    }

    @Test
    func closingCancelsRecognitionAndExtractionAndDiscardsTheirLateSuccesses() async throws {
        let source = try image()
        let original = try rgba(pixels(source))
        let session = ImageToolsEditorSession(image: source)
        let startedOCR = AsyncStream<ScreenshotRecognitionOperation>.makeStream()
        let startedExtraction = AsyncStream<ScreenshotExtractionOperation>.makeStream()
        let releaseOCR = AsyncStream<Void>.makeStream()
        let releaseExtraction = AsyncStream<Void>.makeStream()
        defer {
            startedOCR.continuation.finish(); startedExtraction.continuation.finish()
            releaseOCR.continuation.finish(); releaseExtraction.continuation.finish()
        }
        let ocrTask = try #require(session.model.recognize(.text, recognizeImage: { _, operation in
            startedOCR.continuation.yield(operation)
            for await _ in releaseOCR.stream {}
            return [ScreenshotRecognizedFragment(text: "Late result", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2))]
        }) { _, _ in Issue.record("Dismissed image editors must never present late recognition") })
        let extractionResult = session.model.selectExtractionMode(.foreground, extractImage: { image, operation in
            startedExtraction.continuation.yield(operation)
            for await _ in releaseExtraction.stream {}
            return image
        })
        let extractionTask = try #require(extractionResult)
        var ocrOperation: ScreenshotRecognitionOperation?
        for await operation in startedOCR.stream { ocrOperation = operation; break }
        var extractionOperation: ScreenshotExtractionOperation?
        for await operation in startedExtraction.stream { extractionOperation = operation; break }
        #expect(session.model.isRecognizing && session.model.isExtracting)
        session.close()
        #expect(session.isClosed && !session.model.isRecognizing && !session.model.isExtracting)
        #expect(throws: CancellationError.self) { try #require(ocrOperation).checkCancellation() }
        #expect(throws: CancellationError.self) { try #require(extractionOperation).checkCancellation() }
        session.model.statusMessage = "Closed state"
        releaseOCR.continuation.finish()
        releaseExtraction.continuation.finish()
        await ocrTask.value
        await extractionTask.value
        #expect(session.model.statusMessage == "Closed state")
        #expect(session.model.image === source && !session.model.hasExtractedImage)
        #expect(session.model.annotations.isEmpty && !session.model.canUndo)
        #expect(session.apply() == nil)
        #expect(try rgba(pixels(source)) == original)
    }

    @Test(arguments: [ScreenshotEditorMode.screenshot, .localImage])
    func toolbarCountMatchesVisibleControlsAndLocalModeOmitsCaptureActions(mode: ScreenshotEditorMode) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let preferencesName = "zisla-local-image-toolbar-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: preferencesName))
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let settings = FeatureSettingsStore(defaults: preferences)
        defer { settings.flushPendingChanges() }
        let model = ScreenshotEditorModel(image: try image())
        let editor = ScreenshotEditorView(model: model, selectionState: ScreenshotAnnotationSelectionState(),
            settingsStore: settings, toolbarOnly: true, mode: mode, onClose: {}, onCopy: {},
            onPinToggle: { _ in }, onLongCapture: {})
        let fixture = Fixture(editor, size: CGSize(width: 1_600, height: 38))
        defer { fixture.close() }
        await fixture.settle()
        #expect(editor.toolbarControlCount == (mode == .screenshot ? 17 : 14))
        #expect(fixture.controls.count == editor.toolbarControlCount)
        let copy = try #require(fixture.control(label: AppLocalization.text("复制")))
        let copyHelp = fixture.help(copy)
        #expect(copyHelp.contains("Enter") == (mode == .screenshot),
                "Local image controls must not claim screenshot window shortcuts")
        let labels = fixture.labels
        for key in ["长截图", "钉图", "暂存", "保存"] {
            #expect(labels.contains(AppLocalization.text(key)) == (mode == .screenshot))
        }
        for key in ["提取", "复制", "关闭"] { #expect(labels.contains(AppLocalization.text(key))) }
        #expect(labels.contains(AppLocalization.text("应用编辑")) == (mode == .localImage))
        let brush = ScreenshotAnnotation(kind: .brush, points: [.zero, CGPoint(x: 20, y: 20)])
        model.add(brush)
        model.add(ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 24, y: 20, width: 30, height: 20)))
        model.undo()
        await fixture.settle()
        #expect(editor.toolbarControlCount == (mode == .screenshot ? 19 : 16))
        #expect(fixture.controls.count == editor.toolbarControlCount)
        model.beginLongCapturePreview()
        await fixture.settle()
        #expect(editor.toolbarControlCount == (mode == .screenshot ? 21 : 16))
        #expect(fixture.controls.count == editor.toolbarControlCount)
        model.completeLongCapturePreview()
        await fixture.settle()
        #expect(editor.toolbarControlCount == (mode == .screenshot ? 21 : 16))
        #expect(fixture.controls.count == editor.toolbarControlCount)
        #expect(!fixture.window.isVisible)
    }

    @Test
    func localToolbarDisablesApplyAndCopyWhileExtractionRunsAndKeepsCloseAvailable() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let preferencesName = "zisla-local-image-busy-toolbar-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: preferencesName))
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let settings = FeatureSettingsStore(defaults: preferences)
        defer { settings.flushPendingChanges() }
        let model = ScreenshotEditorModel(image: try image())
        let editor = ScreenshotEditorView(model: model, selectionState: ScreenshotAnnotationSelectionState(),
            settingsStore: settings, toolbarOnly: true, mode: .localImage,
            onClose: {}, onCopy: {}, onPinToggle: { _ in }, onLongCapture: {})
        let fixture = Fixture(editor, size: CGSize(width: 1_600, height: 38))
        defer { fixture.close() }
        let release = AsyncStream<Void>.makeStream()
        defer { model.cancelExtraction(); release.continuation.finish() }
        let operation = model.selectExtractionMode(.foreground, extractImage: { source, _ in
            for await _ in release.stream {}
            return source
        })
        let task = try #require(operation)
        await fixture.settle()
        for key in ["应用编辑", "复制"] {
            let control = try #require(fixture.control(label: AppLocalization.text(key)))
            #expect(try !fixture.isEnabled(control), "Applying or copying must wait for extraction to finish")
        }
        let closeControl = try #require(fixture.control(label: AppLocalization.text("关闭")))
        #expect(try fixture.isEnabled(closeControl))
        release.continuation.finish()
        await task.value
        await fixture.settle()
        for key in ["应用编辑", "复制"] {
            let control = try #require(fixture.control(label: AppLocalization.text(key)))
            #expect(try fixture.isEnabled(control))
        }
    }

    @Test(arguments: [false, true])
    func wrapperOnlyReturnsAnImageAfterTheUserAppliesEdits(apply: Bool) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let preferencesName = "zisla-local-image-wrapper-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: preferencesName))
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let settings = FeatureSettingsStore(defaults: preferences)
        defer { settings.flushPendingChanges() }
        let source = try image(pixelScale: 2)
        let original = try rgba(pixels(source))
        var applied: CGImage?
        let fixture = Fixture(ImageToolsEditorView(image: source, settingsStore: settings) { applied = $0 },
            size: CGSize(width: 1_600, height: 480))
        defer { fixture.close() }
        await fixture.settle()
        #expect(applied == nil)
        #expect(fixture.labels.contains(AppLocalization.text("图片编辑")))
        #expect(!fixture.labels.contains(AppLocalization.text("截图编辑")))
        let action = try #require(fixture.control(label: AppLocalization.text(apply ? "应用编辑" : "关闭")))
        try fixture.press(action)
        await fixture.settle()
        if apply {
            let output = try #require(applied)
            #expect(output.width == 192 && output.height == 160)
            #expect(try rgba(output) == rgba(pixels(ImageToolsEditorSession(image: source).model.renderedImage())))
        } else { #expect(applied == nil) }
        #expect(try rgba(pixels(source)) == original)
        #expect(!fixture.window.isVisible)
    }

    @Test
    func OCRTablePanelsReadTheLatestImageDirectoryAndCancellationCreatesNoFiles() async throws {
        let name = "zisla-local-image-table-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let settings = FeatureSettingsStore(defaults: preferences)
        defer { settings.flushPendingChanges() }
        let locations = SaveLocationStore(defaults: preferences)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = ScreenshotEditorView(model: ScreenshotEditorModel(image: try image()),
            selectionState: ScreenshotAnnotationSelectionState(), settingsStore: settings,
            mode: .localImage, tableDirectory: { locations[.imageTools] },
            onClose: {}, onCopy: {}, onPinToggle: { _ in }, onLongCapture: {})
        let panel = TablePanel()
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        for name in ["Initial images", "Updated images"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try locations.setDirectory(directory, for: .imageTools)
            let result: URL? = await withCheckedContinuation { continuation in
                editor.chooseTableDestination(panel: panel) { continuation.resume(returning: $0) }
                #expect(panel.directoryURL?.standardizedFileURL == directory.standardizedFileURL)
                #expect(panel.nameFieldStringValue == AppLocalization.text("识别表格.xlsx"))
                panel.respond(.cancel)
            }
            #expect(result == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    private func image(pixelScale: Int = 1) throws -> NSImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 96 * pixelScale, pixelsHigh: 80 * pixelScale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = CGSize(width: 96, height: 80)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let dark = ((x / (3 * pixelScale)) + (y / (3 * pixelScale))).isMultiple(of: 2)
                bitmap.setColor(NSColor(deviceRed: dark ? 0.1 : 0.9, green: dark ? 0.7 : 0.2,
                    blue: dark ? 0.3 : 0.8, alpha: y < 6 * pixelScale ? 0 : 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func pixels(_ image: NSImage) throws -> CGImage {
        try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try data.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    @MainActor
    private final class TablePanel: NSSavePanel {
        private var completion: ((NSApplication.ModalResponse) -> Void)?

        override func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
            completion = handler
        }

        override func beginSheetModal(for window: NSWindow,
                                      completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
            completion = handler
        }

        func respond(_ result: NSApplication.ModalResponse) {
            let handler = completion
            completion = nil
            handler?(result)
        }
    }

    @MainActor
    private final class Fixture {
        let window: NSWindow
        let host: NSView

        init<Content: View>(_ content: Content, size: CGSize) {
            host = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
            window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
        }

        func close() { window.contentView = nil; window.close() }

        func settle() async {
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }

        private func value(_ object: NSObject, _ key: String) -> Any? {
            object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
        }

        private func objects(_ root: NSObject) -> [NSObject] {
            [root] + (value(root, "accessibilityChildren") as? [NSObject] ?? []).flatMap(objects)
        }

        var controls: [NSObject] {
            objects(host).filter {
                ["AXButton", "AXMenuButton", "AXPopUpButton"].contains(value($0, "accessibilityRole") as? String ?? "")
            }
        }

        var labels: Set<String> {
            Set(objects(host).flatMap { object in
                ["accessibilityTitle", "accessibilityLabel", "accessibilityValue", "accessibilityHelp"]
                    .compactMap { value(object, $0) as? String }
            })
        }

        func control(label: String) -> NSObject? {
            controls.first { object in
                ["accessibilityTitle", "accessibilityLabel", "accessibilityValue", "accessibilityHelp"]
                    .contains { value(object, $0) as? String == label }
            }
        }

        func help(_ object: NSObject) -> String { value(object, "accessibilityHelp") as? String ?? "" }

        func isEnabled(_ object: NSObject) throws -> Bool {
            try #require(value(object, "isAccessibilityEnabled") as? Bool)
        }

        func press(_ object: NSObject) throws {
            let action = NSSelectorFromString("accessibilityPerformPress")
            try #require(object.responds(to: action))
            object.performSelector(onMainThread: action, with: nil, waitUntilDone: true)
        }
    }
}
