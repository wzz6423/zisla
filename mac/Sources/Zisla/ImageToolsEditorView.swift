import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

@MainActor
final class ImageToolsEditorSession: ObservableObject {
    let model: ScreenshotEditorModel
    let selectionState = ScreenshotAnnotationSelectionState()
    private(set) var isClosed = false

    init(image: NSImage, initialTool: ScreenshotTool = .mosaic) {
        model = ScreenshotEditorModel(image: image)
        model.tool = initialTool
        model.obscureEffect = .pixelate
    }

    func apply() -> CGImage? {
        guard !isClosed, !model.isExtracting, !model.isRecognizing else { return nil }
        let rendered = model.renderedImage()
        guard let output = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            model.statusMessage = AppLocalization.text("图片生成失败")
            return nil
        }
        close()
        return output
    }

    func copyImage(write: (Data) -> Bool = { ClipboardHistoryPasteboard.write(.image($0)) }) {
        guard !isClosed, !model.isExtracting, !model.isRecognizing else { return }
        guard let data = model.pngData() else {
            model.statusMessage = AppLocalization.text("图片生成失败")
            return
        }
        model.statusMessage = write(data)
            ? AppLocalization.text("已复制")
            : AppLocalization.text("无法写入剪贴板")
    }

    func close() {
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
    let onApply: (CGImage) -> Void

    init(
        image: NSImage,
        settingsStore: FeatureSettingsStore,
        saveLocations: SaveLocationStore = AppModel.shared.saveLocations,
        initialTool: ScreenshotTool = .mosaic,
        onApply: @escaping (CGImage) -> Void
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
                guard let image = session.apply() else { return }
                onApply(image)
                dismiss()
            },
            onPinToggle: { _ in },
            onLongCapture: {}
        )
        .onDisappear { session.close() }
    }
}
