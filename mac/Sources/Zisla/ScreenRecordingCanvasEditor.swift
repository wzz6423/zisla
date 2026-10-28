import AppKit
import CoreImage
import SwiftUI
import ZislaCore

private struct RecordingCanvasSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<RecordingCanvasSelection?> = .constant(nil)
}

extension EnvironmentValues {
    var recordingCanvasSelection: Binding<RecordingCanvasSelection?> {
        get { self[RecordingCanvasSelectionKey.self] }
        set { self[RecordingCanvasSelectionKey.self] = newValue }
    }
}

struct ScreenRecordingCanvasEditor: NSViewRepresentable {
    @ObservedObject var model: ScreenRecordingStudioModel
    @Binding var selection: RecordingCanvasSelection?

    func makeNSView(context: Context) -> RecordingCanvasEditorView {
        let view = RecordingCanvasEditorView()
        model.commitPendingCanvasText = { [weak view] in
            view?.finishTextEditing(commit: true)
        }
        return view
    }

    func updateNSView(_ view: RecordingCanvasEditorView, context: Context) {
        view.onSelect = { selection = $0 }
        view.onCommit = { original, replacement in
            model.update { replacement.write(to: &$0, replacing: original) }
        }
        view.onRenderingFailure = model.reportCanvasRenderingFailure
        let time = model.project?.timeline == nil ? model.currentTime : model.playbackTime
        view.configure(project: model.project, sourceTime: time, baseImage: model.canvasPreview,
                       selection: selection, editable: model.canEdit && !model.isShowingSourcePlayback && !model.isShowingTimelinePlayback,
                       multitrackScene: model.multitrackPreviewScene)
    }

    static func dismantleNSView(_ view: RecordingCanvasEditorView, coordinator: ()) { view.cancelEditing() }
}

final class RecordingCanvasEditorView: NSView, NSTextViewDelegate {
    var onSelect: (RecordingCanvasSelection?) -> Void = { _ in }
    var onCommit: (RecordingCanvasElement, RecordingCanvasElement) -> Void = { _, _ in }
    var onRenderingFailure: (Error) -> Void = { _ in }
    private var project: ScreenRecordingProject?
    private var sourceTime = 0.0
    private var baseImage: CGImage?
    private var multitrackScene: RecordingMultitrackPreviewScene?
    private var selection: RecordingCanvasSelection?
    private var editable = false
    private let imageContext = CIContext(options: [.cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private var original: RecordingCanvasElement?
    private(set) var draft: RecordingCanvasElement?
    private var gestureOrigin: CGPoint?
    private var resizeHandle: RecordingCanvasHandle?
    private var moved = false
    private(set) var textEditor: NSTextView?
    private(set) var renderedImage: CGImage?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { editable }
    var canvasSize: CGSize { baseImage.map { CGSize(width: $0.width, height: $0.height) } ?? .zero }
    var canvasRect: CGRect { RecordingCanvasGeometry.fittedRect(canvas: canvasSize, in: bounds) }

    func configure(project: ScreenRecordingProject?, sourceTime: Double, baseImage: CGImage?,
                   selection: RecordingCanvasSelection?, editable: Bool,
                   multitrackScene: RecordingMultitrackPreviewScene? = nil) {
        let editable = editable && (project?.timeline == nil || multitrackScene?.time == sourceTime)
        let originalStillPresent = original.map { original in
            project.map { RecordingCanvasElement.visible(in: $0, at: sourceTime).contains(original) } ?? false
        } ?? true
        if self.project?.id != project?.id || self.sourceTime != sourceTime || self.selection != selection || !editable
            || !originalStillPresent {
            cancelEditing()
        }
        self.project = project
        self.sourceTime = sourceTime
        self.baseImage = baseImage
        self.multitrackScene = multitrackScene
        self.selection = selection
        self.editable = editable
        setAccessibilityIdentifier("screenRecording.canvas")
        setAccessibilityLabel(AppLocalization.text("录屏工作室"))
        render()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        editable && baseImage != nil ? super.hitTest(point) : nil
    }

    override func layout() {
        super.layout()
        positionTextEditor()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let renderedImage {
            NSImage(cgImage: renderedImage, size: canvasSize).draw(in: canvasRect, from: .zero,
                operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        guard editable, let element = selectedElement else { return }
        let box = viewRect(element.bounds(canvas: canvasSize))
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: box)
        outline.lineWidth = 1
        outline.stroke()
        if textEditor == nil {
            for (_, point) in RecordingCanvasGeometry.handles(for: element, canvas: canvasSize) {
                let position = viewPoint(point)
                let handle = NSBezierPath(rect: CGRect(x: position.x - 4, y: position.y - 4, width: 8, height: 8))
                NSColor.white.setFill()
                handle.fill()
                NSColor.controlAccentColor.setStroke()
                handle.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard editable, let project, baseImage != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if textEditor != nil { finishTextEditing(commit: true) }
        window?.makeFirstResponder(self)
        let canvasPoint = imagePoint(point)
        if let element = selectedElement,
           let handle = RecordingCanvasGeometry.handles(for: element, canvas: canvasSize).first(where: {
               let pointOnView = viewPoint($0.1)
               return hypot(pointOnView.x - point.x, pointOnView.y - point.y) <= 9
           })?.0 {
            beginGesture(element, point: canvasPoint, handle: handle)
            return
        }
        let elements = RecordingCanvasElement.visible(in: project, at: sourceTime)
        let tolerance = 5 * canvasSize.width / canvasRect.width
        let selectedHit = selectedElement.flatMap {
            if case .video = $0 { return nil as RecordingCanvasElement? }
            return RecordingCanvasGeometry.hit($0, at: canvasPoint, canvas: canvasSize, tolerance: tolerance) ? $0 : nil
        }
        let hit = selectedHit ?? elements.reversed().first {
            RecordingCanvasGeometry.hit($0, at: canvasPoint, canvas: canvasSize, tolerance: tolerance)
        }
        selection = hit?.selection
        onSelect(selection)
        guard let hit else { needsDisplay = true; return }
        if event.clickCount >= 2, hit.text != nil { beginTextEditing(hit) }
        else { beginGesture(hit, point: canvasPoint, handle: nil) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let original, let gestureOrigin else { return }
        let point = imagePoint(convert(event.locationInWindow, from: nil))
        let translation = CGSize(width: point.x - gestureOrigin.x, height: point.y - gestureOrigin.y)
        if hypot(translation.width, translation.height) * canvasRect.width / canvasSize.width > 1 { moved = true }
        guard moved else { return }
        draft = RecordingCanvasGeometry.transformed(original, by: translation, handle: resizeHandle, canvas: canvasSize)
        render()
    }

    override func mouseUp(with event: NSEvent) {
        guard textEditor == nil, gestureOrigin != nil else { return }
        mouseDragged(with: event)
        let original = self.original, replacement = draft
        let shouldCommit = moved
        clearDraft()
        if shouldCommit, let original, let replacement { commit(original, replacement) }
        render()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelEditing(); return }
        if event.keyCode == 36, let element = selectedElement, element.text != nil { beginTextEditing(element); return }
        super.keyDown(with: event)
    }

    func cancelEditing() {
        textEditor?.delegate = nil
        textEditor?.undoManager?.removeAllActions()
        textEditor?.removeFromSuperview()
        textEditor = nil
        clearDraft()
        render()
    }

    func textDidChange(_ notification: Notification) {
        guard let textEditor, let original else { return }
        let text = String(textEditor.string.prefix(4_000))
        if textEditor.string != text { textEditor.string = text }
        draft = original.replacingText(text)
        render()
    }

    func textDidEndEditing(_ notification: Notification) { finishTextEditing(commit: true) }

    private var selectedElement: RecordingCanvasElement? {
        if let draft { return draft }
        guard let project else { return nil }
        return RecordingCanvasElement.visible(in: project, at: sourceTime).first { $0.selection == selection }
    }

    private func beginGesture(_ element: RecordingCanvasElement, point: CGPoint, handle: RecordingCanvasHandle?) {
        original = element
        draft = element
        gestureOrigin = point
        resizeHandle = handle
        moved = false
        needsDisplay = true
    }

    private func beginTextEditing(_ element: RecordingCanvasElement) {
        guard let text = element.text else { return }
        clearDraft()
        original = element
        draft = element
        let editor = RecordingCanvasTextView()
        editor.string = text
        editor.isRichText = false
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.delegate = self
        editor.onFinish = { [weak self] commit in self?.finishTextEditing(commit: commit) }
        editor.setAccessibilityIdentifier("screenRecording.canvasText")
        editor.setAccessibilityLabel(AppLocalization.text(element.selection.isCaption ? "字幕内容" : "标注内容"))
        textEditor = editor
        addSubview(editor)
        positionTextEditor()
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
        render()
    }

    private func positionTextEditor() {
        guard let textEditor, let element = draft else { return }
        var box = element.bounds(canvas: canvasSize)
        let color: NSColor
        switch element {
        case let .annotation(value): color = NSColor(srgbRed: value.color.red, green: value.color.green, blue: value.color.blue, alpha: 1)
        case let .caption(value):
            let layout = RecordingExportRenderer.captionLayout(value, canvas: CGRect(origin: .zero, size: canvasSize))
            box = box.insetBy(dx: layout.padding, dy: layout.padding)
            color = .white
        case .image, .video: return
        }
        textEditor.frame = viewRect(box)
        let fontSize = RecordingCanvasGeometry.fontSize(of: element, canvas: canvasSize)
            * min(canvasSize.width, canvasSize.height) * canvasRect.width / canvasSize.width
        textEditor.font = NSFont(name: "Helvetica-Bold", size: fontSize)
        textEditor.textColor = color
        textEditor.insertionPointColor = color
        textEditor.textContainer?.containerSize = textEditor.bounds.size
    }

    func finishTextEditing(commit: Bool) {
        guard textEditor != nil else { return }
        let original = self.original, replacement = draft
        textEditor?.delegate = nil
        textEditor?.undoManager?.removeAllActions()
        textEditor?.removeFromSuperview()
        textEditor = nil
        clearDraft()
        if commit, let original, let replacement { self.commit(original, replacement) }
        window?.makeFirstResponder(self)
        render()
    }

    private func clearDraft() {
        original = nil
        draft = nil
        gestureOrigin = nil
        resizeHandle = nil
        moved = false
    }

    private func commit(_ original: RecordingCanvasElement, _ replacement: RecordingCanvasElement) {
        guard original != replacement else { return }
        if var project {
            replacement.write(to: &project, replacing: original)
            self.project = project
        }
        onCommit(original, replacement)
    }

    private func render() {
        guard var project, let baseImage else { renderedImage = nil; needsDisplay = true; return }
        if let original, let draft { draft.write(to: &project, replacing: original) }
        do {
            let editingText = textEditor == nil ? nil : selection
            if project.timeline != nil {
                guard let multitrackScene, multitrackScene.time == sourceTime else {
                    renderedImage = nil
                    needsDisplay = true
                    return
                }
                renderedImage = try multitrackScene.image(project: project, editingText: editingText)
            } else {
                renderedImage = try RecordingExportRenderer.composedPreview(base: baseImage, project: project,
                    sourceTime: sourceTime, context: imageContext, editingText: editingText)
            }
        } catch {
            renderedImage = nil
            onRenderingFailure(error)
        }
        positionTextEditor()
        needsDisplay = true
    }

    private func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: canvasRect.minX + point.x * canvasRect.width / canvasSize.width,
                y: canvasRect.minY + point.y * canvasRect.height / canvasSize.height)
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(origin: viewPoint(rect.origin), size: CGSize(width: rect.width * canvasRect.width / canvasSize.width,
                                                          height: rect.height * canvasRect.height / canvasSize.height))
    }

    private func imagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - canvasRect.minX) * canvasSize.width / canvasRect.width,
                y: (point.y - canvasRect.minY) * canvasSize.height / canvasRect.height)
    }
}

private final class RecordingCanvasTextView: NSTextView {
    private let textUndoManager = UndoManager()
    var onFinish: (Bool) -> Void = { _ in }

    override var undoManager: UndoManager? { textUndoManager }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(false) }
        else if event.keyCode == 36, !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.option) { onFinish(true) }
        else { super.keyDown(with: event) }
    }
}

private extension RecordingCanvasSelection {
    var isCaption: Bool { if case .caption = self { true } else { false } }
}
