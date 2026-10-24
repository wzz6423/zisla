import AppKit
import Combine
import SwiftUI
import ZislaCore
import ZislaKit

@MainActor
final class ScreenRecordingStudioController: NSWindowController, NSWindowDelegate {
    let model: ScreenRecordingStudioModel
    private let languageStore: AppLanguageStore
    private var regionSelector: ScreenRecordingRegionSelector?
    private var subscriptions: Set<AnyCancellable> = []
    private var setupTask: Task<Void, Never>?
    private var cameraTask: Task<Void, Error>?
    private var captureControlsPresented = false
    private var recordingProjectID: UUID?
    private lazy var cameraPreview = ScreenRecordingCameraPreviewController(capture: model.capture)
    private lazy var captureBar: ScreenRecordingCaptureBarController = {
        let model = self.model
        return ScreenRecordingCaptureBarController(model: model, languageStore: languageStore,
            selectRegion: { [weak self] in self?.selectRegion() },
            start: { [weak self] in self?.startCapture() },
            chooseDirectory: { [weak self] in self?.chooseRecordingDirectory() },
            openStudio: { [weak self] in self?.present() },
            cancel: { [weak self] in self?.dismissCaptureControls() },
            displaySaveDirectory: { model.recordingOutputDirectory.path(percentEncoded: false) })
    }()

    init(appModel: AppModel) {
        model = ScreenRecordingStudioModel(appModel: appModel)
        languageStore = appModel.languageStore
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_160, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = AppLocalization.text("录屏工作室")
        window.minSize = NSSize(width: 960, height: 640)
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ScreenRecordingStudioView(model: model,
            languageStore: appModel.languageStore, prepareCapture: { [weak self] in self?.presentCaptureControls() }))
        model.hideWindow = { [weak window] in window?.orderOut(nil) }
        model.showWindow = { [weak self] in self?.captureOperationFinished() }
        appModel.languageStore.$language.dropFirst().sink { [weak window] _ in
            window?.title = AppLocalization.text("录屏工作室")
        }.store(in: &subscriptions)
        model.$configuration
            .removeDuplicates { $0.camera == $1.camera && $0.cameraID == $1.cameraID }
            .dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCameraPreview() }
            .store(in: &subscriptions)
        model.$recordingCameraRound.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCameraPreview() }
            .store(in: &subscriptions)
        model.$recordingCameraCornerRadius.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCameraPreview() }
            .store(in: &subscriptions)
        model.$isChoosingFile.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] choosing in
                guard let self, !choosing, captureControlsPresented, regionSelector == nil else { return }
                captureBar.present()
            }.store(in: &subscriptions)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        if model.isRecording { captureBar.present(); return }
        dismissCaptureControls()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func perform(_ action: RecordingShortcutAction) {
        switch action {
        case .display:
            presentCaptureControls(mode: .display)
        case .window:
            presentCaptureControls(mode: .window)
        case .region:
            presentCaptureControls(mode: .region)
        case .pause: model.pause()
        case .stop: model.stop()
        case .studio: present()
        case .openProject: present(); model.openProject()
        case .saveProject: model.saveProject()
        case .export: present(); model.export()
        }
    }

    func presentCaptureControls(mode: RecordingCaptureMode? = nil) {
        guard !model.isBusy, !model.isChoosingFile, !model.exporter.isExporting else { return }
        if model.isRecording { captureBar.present(); return }
        setupTask?.cancel()
        regionSelector?.cancel()
        if let mode { model.selectMode(mode) }
        recordingProjectID = model.project?.id
        captureControlsPresented = true
        window?.orderOut(nil)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if model.configuration.mode != .window, mode != nil || model.configuration.sourceID == 0,
           let screen, let id = ScreenshotCaptureService.displayID(for: screen) {
            if model.configuration.sourceID != id { model.configuration.region = nil }
            model.configuration.sourceID = id
        }
        captureBar.present(on: screen)
        refreshCameraPreview()
        setupTask = Task { [weak self] in
            guard let self else { return }
            await model.loadSources()
            guard !Task.isCancelled, captureControlsPresented else { return }
            captureBar.refreshTargetOutline()
        }
    }

    private func startCapture() {
        guard captureControlsPresented, !model.isRecording else { return }
        recordingProjectID = model.project?.id
        model.start()
    }

    private func chooseRecordingDirectory() {
        captureBar.hide()
        model.chooseRecordingOutputDirectory()
    }

    private func refreshCameraPreview() {
        guard captureControlsPresented else { return }
        let configuration = model.configuration
        if configuration.camera {
            cameraPreview.present(configuration: .init(cameraRound: model.recordingCameraRound,
                cameraCornerRadius: model.recordingCameraCornerRadius))
        }
        else { cameraPreview.hide() }
        guard !model.isRecording else { return }
        cameraTask?.cancel()
        cameraTask = Task { [capture = model.capture] in
            try await capture.prepareCameraPreview(configuration: configuration)
        }
    }

    private func captureOperationFinished() {
        if let project = model.project, project.id != recordingProjectID {
            present()
        } else if captureControlsPresented {
            captureBar.present()
            refreshCameraPreview()
        }
    }

    private func dismissCaptureControls() {
        captureControlsPresented = false
        setupTask?.cancel()
        cameraTask?.cancel()
        regionSelector?.cancel()
        captureBar.hide()
        cameraPreview.hide()
        Task { [capture = model.capture] in await capture.stopCameraPreview() }
    }

    func selectRegion() {
        guard !model.isRecording, !model.isBusy, !model.isChoosingFile, regionSelector == nil else { return }
        guard let screen = NSScreen.screens.first(where: {
            ScreenshotCaptureService.displayID(for: $0) == model.configuration.sourceID
        }) else { return }
        window?.orderOut(nil)
        captureBar.hide()
        cameraPreview.hide()
        let sourceID = model.configuration.sourceID
        let returnsToCaptureControls = captureControlsPresented
        let selector = ScreenRecordingRegionSelector(screen: screen)
        regionSelector = selector
        selector.onFinish = { [weak self] region in
            guard let self else { return }
            regionSelector = nil
            if let region, model.configuration.sourceID == sourceID {
                model.configuration.region = region
            }
            if returnsToCaptureControls {
                guard captureControlsPresented else { return }
                captureBar.present(on: screen)
                refreshCameraPreview()
            } else { present() }
        }
        selector.present()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.prepareToClose() else { present(); return false }
        return true
    }

    func prepareToTerminate() -> Bool {
        guard model.prepareToClose() else { present(); return false }
        dismissCaptureControls()
        return true
    }

    func shutdown() {
        dismissCaptureControls()
        captureBar.shutdown()
        cameraPreview.shutdown()
        model.shutdown()
    }
}
