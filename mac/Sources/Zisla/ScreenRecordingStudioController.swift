import AppKit
import Combine
import SwiftUI
import ZislaCore
import ZislaKit

@MainActor
final class ScreenRecordingStudioWindow: NSWindow {
    weak var studioModel: ScreenRecordingStudioModel?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.window === self else { return super.performKeyEquivalent(with: event) }
        if firstResponder is NSTextView {
            return TextEditingCommands.performKeyEquivalent(with: event, in: self) || super.performKeyEquivalent(with: event)
        }
        if event.charactersIgnoringModifiers == " ",
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty,
           attachedSheet == nil, NSApp.modalWindow == nil,
           let model = studioModel, model.canExport {
            if !event.isARepeat { model.playTimeline() }
            return true
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if modifiers == .command, let model = studioModel, model.canEdit {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                if let id = model.selectedTimelineClipID, model.copyTimelineClip(id) { return true }
            case "v":
                if model.pasteTimelineClip() != nil { return true }
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

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
    private lazy var cameraPreview = ScreenRecordingCameraPreviewController(capture: model.capture,
        changeSize: { [weak self] in self?.model.recordingCameraSize = $0 },
        changeCornerRadius: { [weak self] radius in
            self?.model.recordingCameraCornerRadius = radius
        })
    private lazy var captureBar: ScreenRecordingCaptureBarController = {
        let model = self.model
        return ScreenRecordingCaptureBarController(model: model, languageStore: languageStore,
            selectRegion: { [weak self] in self?.selectRegion() },
            start: { [weak self] in self?.startCapture() },
            openStudio: { [weak self] in self?.present() },
            cancel: { [weak self] in self?.dismissCaptureControls() })
    }()

    init(appModel: AppModel) {
        model = ScreenRecordingStudioModel(appModel: appModel)
        languageStore = appModel.languageStore
        let window = ScreenRecordingStudioWindow(contentRect: NSRect(x: 0, y: 0, width: 1_160, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.studioModel = model
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
        model.$recordingCameraAspectRatio.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCameraPreviewLayout() }
            .store(in: &subscriptions)
        model.$recordingCameraCornerRadius.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCameraPreviewLayout() }
            .store(in: &subscriptions)
        model.$recordingCameraBorder.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCameraPreviewLayout() }
            .store(in: &subscriptions)
        model.$recordingCameraSize.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCameraPreviewLayout() }
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

    private func updateCameraPreviewLayout() {
        guard captureControlsPresented else { return }
        let configuration = model.configuration
        if configuration.camera {
            cameraPreview.present(configuration: .init(cameraSize: model.recordingCameraSize,
                cameraAspectRatio: model.recordingCameraAspectRatio,
                cameraCornerRadius: model.recordingCameraCornerRadius,
                cameraBorder: model.recordingCameraBorder))
        }
        else { cameraPreview.hide() }
    }

    private func refreshCameraPreview() {
        updateCameraPreviewLayout()
        guard captureControlsPresented, !model.isRecording else { return }
        let configuration = model.configuration
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
        let originalSourceID = model.configuration.sourceID
        let screenFrames = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            ScreenshotCaptureService.displayID(for: screen).map { ($0, screen.frame) }
        })
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first
        let windowTarget = model.configuration.mode == .window
            ? model.capture.sources.first(where: { $0.id == originalSourceID && $0.mode == .window })
            : nil
        let targetFrame: CGRect? = windowTarget.flatMap { source in
            primaryScreen.flatMap { primary in
                ScreenRecordingCaptureBarGeometry.targetFrame(configuration: model.configuration,
                    sources: [source], screenFrames: screenFrames, primaryScreenFrame: primary.frame)
            }
        }
        let targetScreen: NSScreen? = targetFrame.flatMap { target -> NSScreen? in
            let screen = NSScreen.screens.max { left, right in
                func area(_ frame: CGRect) -> CGFloat {
                    let intersection = frame.intersection(target)
                    return intersection.isNull ? 0 : intersection.width * intersection.height
                }
                return area(left.frame) < area(right.frame)
            }
            guard let screen else { return nil }
            let intersection = screen.frame.intersection(target)
            return intersection.isNull || intersection.width <= 0 || intersection.height <= 0 ? nil : screen
        }
        let screen = targetScreen ?? (model.configuration.mode == .window
            ? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            : NSScreen.screens.first(where: { ScreenshotCaptureService.displayID(for: $0) == originalSourceID }))
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen, let displayID = ScreenshotCaptureService.displayID(for: screen) else { return }
        model.configuration.mode = .region
        model.configuration.sourceID = displayID
        model.configuration.region = nil
        window?.orderOut(nil)
        captureBar.hide()
        cameraPreview.hide()
        let returnsToCaptureControls = captureControlsPresented
        let selector = ScreenRecordingRegionSelector(screen: screen)
        regionSelector = selector
        selector.onFinish = { [weak self] (region: RecordingRect?) in
            guard let self else { return }
            regionSelector = nil
            if let region, model.configuration.sourceID == displayID {
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
