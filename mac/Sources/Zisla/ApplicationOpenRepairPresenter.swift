import AppKit
import ZislaCore
import ZislaKit

@MainActor
final class ApplicationOpenRepairPresenter {
    private let controller: ClipboardAssistantController
    private let settings: @MainActor () -> FeatureSettings
    private let canPresent: @MainActor () -> Bool
    private(set) var task: Task<Void, Never>?
    private var pending: ClipboardAssistantDetection?
    private var requiresSystemMonitoring = false

    init(
        controller: ClipboardAssistantController,
        settings: @escaping @MainActor () -> FeatureSettings,
        canPresent: @escaping @MainActor () -> Bool
    ) {
        self.controller = controller
        self.settings = settings
        self.canPresent = canPresent
    }

    func receive(_ urls: [URL], fromSystemAlert: Bool = false) {
        let urls = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "app" }
        guard !urls.isEmpty else { return }
        cancel()
        requiresSystemMonitoring = fromSystemAlert
        let settings = settings()
        guard fromSystemAlert ? settings.applicationOpenFailureMonitoringActive : settings.applicationOpenRepairEnabled else { return }
        task = Task { [weak self] in
            let inspection = Task.detached(priority: .userInitiated) {
                urls.lazy.compactMap { url -> ClipboardAssistantDetection? in
                    ClipboardAssistantDetector.detect(
                        content: .file(ClipboardFileReference(url: url, displayName: url.lastPathComponent, bookmark: Data())),
                        enabledKinds: [.appCannotOpen]
                    )
                }.first
            }
            let detection = await withTaskCancellationHandler {
                await inspection.value
            } onCancel: {
                inspection.cancel()
            }
            guard !Task.isCancelled, let self else { return }
            pending = detection
            flush()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        pending = nil
        requiresSystemMonitoring = false
    }

    func flush() {
        let settings = settings()
        guard requiresSystemMonitoring ? settings.applicationOpenFailureMonitoringActive : settings.applicationOpenRepairEnabled else {
            cancel()
            return
        }
        guard canPresent(), let detection = pending else { return }
        controller.displayDuration = settings.clipboardAssistantDisplayDuration
        controller.presentation.progressGlowEnabled = settings.collapsedProgressGlowEnabled
        controller.presentation.notchBackground = settings.islandNotchBackground
        if controller.present(detection, visualStyle: settings.islandVisualStyle) != nil { pending = nil }
    }
}
