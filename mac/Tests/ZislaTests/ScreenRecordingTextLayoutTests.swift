import AppKit
import CoreImage
import Testing
import ZislaCore

@testable import Zisla

@Suite(.serialized) @MainActor
struct ScreenRecordingTextLayoutTests {
    private let canvas = CGSize(width: 800, height: 600)

    @Test(arguments: ["Hi", "文字标注", "English\n中文"])
    func selectedTextFitsItsContentInsteadOfTheDefaultRectangle(_ text: String) {
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 1, text: text)
        let bounds = RecordingCanvasElement.annotation(annotation).bounds(canvas: canvas)
        #expect(bounds.minX == 160 && bounds.minY == 120)
        #expect(bounds.width < 200 && bounds.height < 100,
                "Short text must not retain the default 400 × 120 empty selection rectangle")
        #expect(!RecordingCanvasGeometry.hit(.annotation(annotation), at: CGPoint(x: 550, y: 230),
            canvas: canvas, tolerance: 4), "The former blank area must not intercept other canvas elements")
    }

    @Test
    func textSizeTracksFontChangesAndPreservesEmptyAndTrailingLines() {
        var annotation = RecordingAnnotation(kind: .text, start: 0, end: 1, text: "文字")
        let before = RecordingCanvasElement.annotation(annotation).bounds(canvas: canvas)
        annotation.fontSize *= 2
        let enlarged = RecordingCanvasElement.annotation(annotation).bounds(canvas: canvas)
        #expect(enlarged.origin == before.origin)
        #expect(enlarged.width >= before.width * 1.9 && enlarged.height >= before.height * 1.9)
        annotation.text = ""
        let empty = RecordingCanvasElement.annotation(annotation).bounds(canvas: canvas)
        #expect(empty.width > 0 && empty.height > 0, "An empty label must retain a selectable line and caret area")
        annotation.text = "Hi\n"
        let newline = RecordingCanvasElement.annotation(annotation).bounds(canvas: canvas)
        annotation.text = "Hi"
        let oneLine = RecordingCanvasElement.annotation(annotation).bounds(canvas: canvas)
        #expect(newline.height > oneLine.height * 1.5, "A trailing newline needs room for the next insertion line")
        #expect(RecordingCanvasElement.annotation(annotation).bounds(canvas: .zero) == .zero)
    }

    @Test
    func textSelectionStaysInsideTheCanvasWhenSavedNearTheBottom() {
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 1,
            y: 0.97, endY: 0.99, text: "Line\nLine\nLine")
        let bounds = RecordingCanvasElement.annotation(annotation).bounds(canvas: canvas)
        #expect(CGRect(origin: .zero, size: canvas).contains(bounds),
            "Saved text near the edge must not place selection handles outside the canvas")
        #expect(bounds.height > 0)
    }

    @Test
    func textResizingKeepsTheSavedWrappingLimitAvailableForLaterTyping() throws {
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 1, text: "Hi")
        let element = RecordingCanvasElement.annotation(annotation)
        let bounds = element.bounds(canvas: canvas)
        let resized = RecordingCanvasGeometry.transformed(element, by: bounds.size, handle: .bottomRight, canvas: canvas)
        guard case let .annotation(value) = resized else { Issue.record("Expected text annotation"); return }
        let longer = value.text + " English"
        let expanded = resized.replacingText(longer).bounds(canvas: canvas)
        #expect(expanded.width > resized.bounds(canvas: canvas).width * 2,
                "Resizing letters must not collapse their wrapping limit to the old short word")
        let saved = try JSONDecoder().decode(RecordingAnnotation.self, from: JSONEncoder().encode(value))
        #expect(saved == value && saved.isValid(duration: 1))
    }

    @Test
    func textSelectionContainsTheExportedGlyphsWithOnlyTypographicLeading() throws {
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 1, endY: 0.21, text: "文字标注\nEnglish")
        let frame = CGRect(origin: .zero, size: canvas)
        let image = try RecordingExportRenderer.annotationImage(annotation, canvas: frame)
        let raster = try #require(CIContext().createCGImage(image, from: frame))
        var pixels = [UInt8](repeating: 0, count: 800 * 600 * 4)
        try pixels.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(data: pointer.baseAddress, width: 800, height: 600,
                bitsPerComponent: 8, bytesPerRow: 800 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(raster, in: frame)
        }
        let occupied = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0 + 3] > 64 }
        #expect(!occupied.isEmpty, "The measured frame must still render text")
        let left = try #require(occupied.map { ($0 / 4) % 800 }.min())
        let right = try #require(occupied.map { ($0 / 4) % 800 }.max()) + 1
        let top = try #require(occupied.map { ($0 / 4) / 800 }.min())
        let bottom = try #require(occupied.map { ($0 / 4) / 800 }.max()) + 1
        let glyphs = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        let selection = RecordingCanvasElement.annotation(annotation).bounds(canvas: canvas)
        #expect(selection.insetBy(dx: -1, dy: -1).contains(glyphs))
        #expect(selection.width - glyphs.width < 36 && selection.height - glyphs.height < 36,
                "Selection and exported glyphs must use the same content layout")
    }

    @Test
    func typingExpandsAndShrinksTheNativeEditorAndCommitsOneUndoableValue() throws {
        let annotation = RecordingAnnotation(kind: .text, start: 0, end: 1, text: "Hi")
        var project = ScreenRecordingProject(name: "Text", videoFile: "screen.mp4", duration: 1, width: 800, height: 600)
        project.edits.annotations = [annotation]
        let context = CIContext()
        let base = try #require(context.createCGImage(CIImage(color: .black), from: CGRect(origin: .zero, size: canvas)))
        let view = RecordingCanvasEditorView(frame: CGRect(origin: .zero, size: canvas))
        let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { view.cancelEditing(); window.close() }
        var replacements: [RecordingCanvasElement] = []
        view.onCommit = { original, replacement in
            #expect(original == .annotation(annotation))
            replacements.append(replacement)
        }
        view.configure(project: project, sourceTime: 0, baseImage: base, selection: .annotation(annotation.id), editable: true)
        let box = RecordingCanvasElement.annotation(annotation).bounds(canvas: canvas)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: view.convert(CGPoint(x: box.midX, y: box.midY), to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1))
        view.mouseDown(with: event)
        let editor = try #require(view.textEditor)
        let initial = editor.frame
        editor.string = "English and 中文\nSecond line"
        view.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        #expect(editor.frame.width > initial.width * 2 && editor.frame.height > initial.height * 1.5,
                "Text entry must resize both the selection and native editor as content grows")
        #expect(replacements.isEmpty, "Typing must remain a draft until the editor is committed")
        editor.string = "字"
        view.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        #expect(editor.frame.width < 60 && editor.frame.height < 60,
                "Deleting text must remove unused selection space")
        view.finishTextEditing(commit: true)
        #expect(replacements.count == 1 && replacements.first?.text == "字")
        #expect(view.textEditor == nil && view.draft == nil)
    }
}
