import AppKit
import Combine
import SwiftUI
import ZislaCore
import ZislaKit

@MainActor
final class ScreenRecordingStudioController: NSWindowController, NSWindowDelegate {
    let model: ScreenRecordingStudioModel
    private var regionSelector: ScreenRecordingRegionSelector?
    private var subscriptions: Set<AnyCancellable> = []

    init(appModel: AppModel) {
        model = ScreenRecordingStudioModel(appModel: appModel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_160, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = AppLocalization.text("录屏工作室")
        window.minSize = NSSize(width: 860, height: 560)
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ScreenRecordingStudioView(model: model,
            languageStore: appModel.languageStore, selectRegion: { [weak self] in self?.selectRegion() }))
        model.hideWindow = { [weak window] in window?.orderOut(nil) }
        model.showWindow = { [weak self] in self?.present() }
        appModel.languageStore.$language.dropFirst().sink { [weak window] _ in
            window?.title = AppLocalization.text("录屏工作室")
        }.store(in: &subscriptions)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func perform(_ action: RecordingShortcutAction) {
        switch action {
        case .display:
            guard !model.isRecording, !model.isBusy, !model.isChoosingFile else { return }
            model.selectMode(.display)
            Task { [weak self] in
                guard let self else { return }
                await model.loadSources()
                guard !model.availableSources.isEmpty else { present(); return }
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
                   let id = ScreenshotCaptureService.displayID(for: screen) { model.configuration.sourceID = id }
                model.start()
            }
        case .window:
            guard !model.isRecording, !model.isBusy, !model.isChoosingFile else { return }
            present()
            model.selectMode(.window)
            model.showCaptureSetup = true
            Task { await model.loadSources() }
        case .region:
            guard !model.isRecording, !model.isBusy, !model.isChoosingFile else { return }
            model.selectMode(.region)
            Task { [weak self] in
                guard let self else { return }
                await model.loadSources()
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
                   let id = ScreenshotCaptureService.displayID(for: screen) { model.configuration.sourceID = id }
                selectRegion(startAfterSelection: true)
            }
        case .pause: model.pause()
        case .stop: model.stop()
        case .studio: present()
        case .openProject: present(); model.openProject()
        case .saveProject: model.saveProject()
        case .export: present(); model.export()
        }
    }

    func selectRegion(startAfterSelection: Bool = false) {
        guard !model.isRecording, !model.isBusy, !model.isChoosingFile, regionSelector == nil else { return }
        guard let screen = NSScreen.screens.first(where: {
            ScreenshotCaptureService.displayID(for: $0) == model.configuration.sourceID
        }) else { present(); return }
        window?.orderOut(nil)
        let selector = ScreenRecordingRegionSelector(screen: screen)
        regionSelector = selector
        selector.onFinish = { [weak self] region in
            guard let self else { return }
            regionSelector = nil
            if let region {
                model.configuration.region = region
                if startAfterSelection { model.start(); return }
            }
            present()
        }
        selector.present()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.prepareToClose() else { present(); return false }
        return true
    }

    func prepareToTerminate() -> Bool {
        guard model.prepareToClose() else { present(); return false }
        regionSelector?.cancel()
        return true
    }

    func shutdown() {
        regionSelector?.cancel()
        model.shutdown()
    }
}
