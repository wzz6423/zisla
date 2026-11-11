import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

@MainActor
final class ImageToolsEditorSession: ObservableObject {
    let model: ScreenshotEditorModel
    let selectionState = ScreenshotAnnotationSelectionState()
    @Published private(set) var isSaving = false
    private(set) var isClosed = false
    private var applyTask: Task<Bool, Never>?

    init(image: NSImage, initialTool: ScreenshotTool = .mosaic) {
        model = ScreenshotEditorModel(image: image)
        model.tool = initialTool
        model.obscureEffect = .pixelate
    }

    func apply() -> CGImage? {
        guard !isClosed, !isSaving, !model.isExtracting, !model.isRecognizing else { return nil }
        guard let rendered = try? model.renderedImage(requireCompleteRendering: true),
              let output = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            model.statusMessage = AppLocalization.text("图片生成失败")
            return nil
        }
        return output
    }

    @discardableResult
    func apply(persist: @escaping @MainActor (CGImage) async throws -> Void) -> Task<Bool, Never>? {
        guard let image = apply() else { return nil }
        isSaving = true
        model.statusMessage = nil
        applyTask = Task { [weak self] in
            do {
                try await persist(image)
                try Task.checkCancellation()
                guard let self else { return false }
                self.applyTask = nil
                self.close()
                return true
            } catch {
                guard let self, !self.isClosed else { return false }
                self.isSaving = false
                self.model.statusMessage = error is CancellationError ? AppLocalization.text("已取消") : error.localizedDescription
                return false
            }
        }
        return applyTask
    }

    func copyImage(write: (Data) -> Bool = { ClipboardHistoryPasteboard.write(.image($0)) }) {
        guard !isClosed, !isSaving, !model.isExtracting, !model.isRecognizing else { return }
        guard let data = model.pngData(requireCompleteRendering: true) else {
            model.statusMessage = AppLocalization.text("图片生成失败")
            return
        }
        model.statusMessage = write(data)
            ? AppLocalization.text("已复制")
            : AppLocalization.text("无法写入剪贴板")
    }

    func close() {
        applyTask?.cancel()
        isSaving = false
        isClosed = true
        model.cancelRecognition()
        model.cancelExtraction()
    }
}

struct ImageToolsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: ImageToolsEditorSession
    let settingsStore: FeatureSettingsStore
    let saveLocations: SaveLocationStore
    let onApply: @MainActor (CGImage) async throws -> Void

    init(
        image: NSImage,
        settingsStore: FeatureSettingsStore,
        saveLocations: SaveLocationStore = AppModel.shared.saveLocations,
        initialTool: ScreenshotTool = .mosaic,
        onApply: @escaping @MainActor (CGImage) async throws -> Void
    ) {
        _session = StateObject(wrappedValue: ImageToolsEditorSession(image: image, initialTool: initialTool))
        self.settingsStore = settingsStore
        self.saveLocations = saveLocations
        self.onApply = onApply
    }

    var body: some View {
        ScreenshotEditorView(
            model: session.model,
            selectionState: session.selectionState,
            settingsStore: settingsStore,
            mode: .localImage,
            tableDirectory: { saveLocations[.imageTools] },
            onClose: {
                session.close()
                dismiss()
            },
            onCopy: { session.copyImage() },
            onSave: {
                guard let task = session.apply(persist: onApply) else { return }
                Task { if await task.value { dismiss() } }
            },
            onPinToggle: { _ in },
            onLongCapture: {}
        )
        .background(ImageToolsEditorKeyboardView(session: session))
        .disabled(session.isSaving)
        .onDisappear { session.close() }
    }
}

private struct ImageToolsEditorKeyboardView: NSViewRepresentable {
    let session: ImageToolsEditorSession

    func makeNSView(context: Context) -> ImageToolsEditorKeyboardHost {
        ImageToolsEditorKeyboardHost(session: session)
    }

    func updateNSView(_ nsView: ImageToolsEditorKeyboardHost, context: Context) {}
}

@MainActor
final class ImageToolsEditorKeyboardHost: NSView {
    let session: ImageToolsEditorSession
    private var monitor: Any?

    init(session: ImageToolsEditorSession) {
        self.session = session
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) == true }
            return handled ? nil : event
        }
    }

    func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              event.keyCode == 51 || event.keyCode == 117,
              event.modifierFlags.subtracting([.capsLock, .numericPad, .function]).isEmpty,
              !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField),
              !session.isClosed, !session.isSaving,
              !session.model.isExtracting, !session.model.isRecognizing else { return false }
        return session.selectionState.deleteSelectedAnnotation(from: session.model)
    }
}
