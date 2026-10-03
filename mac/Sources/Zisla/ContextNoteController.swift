import AppKit
import Combine
import SwiftUI
import ZislaCore
import ZislaKit

struct ContextNoteVisitTracker {
    private var location: ContextNoteLocation?
    private var reminded = false

    mutating func candidate(for observation: ContextNoteObservation, items: [FileShelfItem]) -> FileShelfItem? {
        switch observation {
        case .ignored, .unavailable:
            return nil
        case .location(let current):
            if location?.matches(current) != true {
                location = current
                reminded = false
            }
            guard !reminded else { return nil }
            return items.filter { $0.noteLocation?.matches(current) == true }.max { $0.addedAt < $1.addedAt }
        }
    }

    mutating func didPresent() { reminded = true }

    mutating func didSave(at location: ContextNoteLocation) {
        self.location = location
        reminded = true
    }
}

@MainActor
final class ContextNoteDraft: ObservableObject {
    let location: ContextNoteLocation
    let createdAt: Date
    @Published var text = ""
    @Published var error: String?

    init(location: ContextNoteLocation, createdAt: Date = Date()) {
        self.location = location
        self.createdAt = createdAt
    }
}

enum ContextNoteLayout {
    static func frame(near point: CGPoint, in visibleFrame: CGRect) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(360, bounds.width), height: min(44, bounds.height))
        let x = point.x + 18 + size.width <= bounds.maxX ? point.x + 18 : point.x - 18 - size.width
        return CGRect(x: min(max(x, bounds.minX), bounds.maxX - size.width),
                      y: min(max(point.y - size.height / 2, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }
}

@MainActor
final class ContextNoteController {
    private let settingsStore: FeatureSettingsStore
    private let languageStore: AppLanguageStore
    private let shelf: FileShelfStore
    private let captureLocation: @MainActor (CGPoint) -> ContextNoteObservation
    private let currentLocation: @MainActor (CGPoint) -> ContextNoteObservation
    private let canInteract: () -> Bool
    private let onReminder: (FileShelfItem) -> Bool
    private let onCaptureFailure: () -> Void
    private let onSaved: (FileShelfItem) -> Void
    private let pressedMouseButtons: () -> Int
    private let windowPresenter: (ContextNoteController, CGPoint, Bool) -> Void
    private var subscription: AnyCancellable?
    private var pointerMonitor: PointerEdgeMonitor?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var detector = ContextNoteShakeDetector()
    private var visits = ContextNoteVisitTracker()
    private var shelfLocation: ContextNoteObservation = .unavailable
    private var window: IslandPanel?
    private var cancelMonitor: Any?
    private var sourceApplication: NSRunningApplication?
    private var anchor = CGPoint.zero
    private var enabled: Bool
    private var screenLocked = false
    private var screenshotActive = false
    private var systemScreenshotActive = false
    private var sleeping = false
    private var isStarted = false
    private(set) var draft: ContextNoteDraft?

    private var isSuspended: Bool { screenLocked || screenshotActive || systemScreenshotActive || sleeping }

    init(settingsStore: FeatureSettingsStore, languageStore: AppLanguageStore, shelf: FileShelfStore,
         captureLocation: @escaping @MainActor (CGPoint) -> ContextNoteObservation = ContextNoteLocationReader.capture,
         currentLocation: @escaping @MainActor (CGPoint) -> ContextNoteObservation = ContextNoteLocationReader.current,
         canInteract: @escaping () -> Bool,
         onReminder: @escaping (FileShelfItem) -> Bool,
         onCaptureFailure: @escaping () -> Void,
         onSaved: @escaping (FileShelfItem) -> Void,
         pressedMouseButtons: @escaping () -> Int = { NSEvent.pressedMouseButtons },
         windowPresenter: @escaping (ContextNoteController, CGPoint, Bool) -> Void = { $0.presentWindow(at: $1, focus: $2) }) {
        self.settingsStore = settingsStore
        self.languageStore = languageStore
        self.shelf = shelf
        self.captureLocation = captureLocation
        self.currentLocation = currentLocation
        self.canInteract = canInteract
        self.onReminder = onReminder
        self.onCaptureFailure = onCaptureFailure
        self.onSaved = onSaved
        self.pressedMouseButtons = pressedMouseButtons
        self.windowPresenter = windowPresenter
        enabled = settingsStore.settings.clipboardAssistantEnabled && settingsStore.settings.contextNotesEnabled
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        subscription = settingsStore.$settings
            .map { $0.clipboardAssistantEnabled && $0.contextNotesEnabled }
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.enabled = enabled
                self?.updateMonitoring()
            }
        for (name, sleeping) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = sleeping
                    self?.updateMonitoring()
                }
            })
        }
    }

    func setScreenLocked(_ value: Bool) { screenLocked = value; updateMonitoring() }
    func setScreenshotActive(_ value: Bool) { screenshotActive = value; updateMonitoring() }
    func setSystemScreenshotActive(_ value: Bool) { systemScreenshotActive = value; updateMonitoring() }

    func stop() {
        enabled = false
        isStarted = false
        shelfLocation = .unavailable
        subscription = nil
        pointerMonitor?.stop()
        pointerMonitor = nil
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        discard()
    }

    isolated deinit {
        pointerMonitor?.stop()
        timer?.invalidate()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor) }
        window?.close()
    }

    private func updateMonitoring() {
        detector.reset()
        guard enabled, !isSuspended else {
            if isSuspended { shelfLocation = .unavailable }
            pointerMonitor?.stop()
            pointerMonitor = nil
            timer?.invalidate()
            timer = nil
            window?.orderOut(nil)
            return
        }
        guard isStarted, pointerMonitor == nil else { return }
        let monitor = PointerEdgeMonitor { [weak self] point, interaction in
            self?.handlePointer(at: point, interaction: interaction)
        }
        pointerMonitor = monitor
        monitor.start()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForReturn(at: NSEvent.mouseLocation) }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if draft != nil { windowPresenter(self, anchor, false) }
    }

    func handlePointer(at point: CGPoint, interaction: PointerEdgeMonitor.Interaction,
                       timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard enabled, !isSuspended, draft == nil, canInteract() else { detector.reset(); return }
        guard interaction == .moved, pressedMouseButtons() == 0 else { detector.reset(); return }
        guard detector.record(point, at: timestamp) else { return }
        detector.reset()
        let observation = captureLocation(point)
        if observation == .unavailable { onCaptureFailure() }
        guard case .location(let location) = observation else { return }
        anchor = point
        draft = ContextNoteDraft(location: location)
        windowPresenter(self, point, true)
    }

    func save(at date: Date = Date()) {
        guard let draft, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let item = shelf.addContextNote(draft.text, location: draft.location, addedAt: date) else {
            draft.error = shelf.errorDescription
            return
        }
        didSaveNote(item)
        discard()
        onSaved(item)
    }

    func discard() {
        draft = nil
        detector.reset()
        if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor) }
        cancelMonitor = nil
        window?.close()
        window = nil
        if NSApp?.isActive == true { sourceApplication?.activate(options: []) }
        sourceApplication = nil
    }

    func checkForReturn(at point: CGPoint) {
        guard enabled, !isSuspended, draft == nil, canInteract(), shelf.items.contains(where: { $0.noteLocation != nil }) else { return }
        let observation = currentLocation(point)
        if let item = visits.candidate(for: observation, items: shelf.items), onReminder(item) {
            visits.didPresent()
        }
    }

    func prepareShelfCapture(at point: CGPoint) {
        guard !isSuspended else { shelfLocation = .unavailable; return }
        shelfLocation = currentLocation(point)
    }

    func makeShelfDraft(at point: CGPoint, createdAt: Date = Date()) -> ContextNoteDraft? {
        guard !isSuspended else { return nil }
        let observation = currentLocation(point)
        // Clicking the island activates this app; keep the context captured before that click.
        if observation != .ignored { shelfLocation = observation }
        guard case .location(let location) = shelfLocation else { return nil }
        return ContextNoteDraft(location: location, createdAt: createdAt)
    }

    func didSaveNote(_ item: FileShelfItem) {
        guard let location = item.noteLocation else { return }
        visits.didSave(at: location)
    }

    private func presentWindow(at point: CGPoint, focus: Bool) {
        guard let draft, let screen = WindowPlacement.screenUnderMouse(point: point) else { return }
        if let window {
            window.setFrame(ContextNoteLayout.frame(near: point, in: screen.visibleFrame), display: true)
            window.orderFrontRegardless()
            return
        }
        sourceApplication = NSWorkspace.shared.frontmostApplication
        let content = ContextNoteInputView(draft: draft, settingsStore: settingsStore,
                                          onSave: { [weak self] in self?.save() },
                                          onDiscard: { [weak self] in self?.discard() })
        let hosting = NSHostingView(rootView: AppLanguageEnvironment(languageStore: languageStore, content: content))
        hosting.sizingOptions = []
        let panel = ClipboardAssistantController.makeWindow(contentView: hosting,
                                                            frame: ContextNoteLayout.frame(near: point, in: screen.visibleFrame))
        panel.allowsKeyWindow = true
        panel.avoidsAppActivation = false
        window = panel
        cancelMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let panel, event.window === panel, ContextNoteInputCommand.isDiscard(event) else { return event }
            self?.discard()
            return nil
        }
        panel.orderFrontRegardless()
        if focus { panel.takeKeyboardFocus() }
    }
}

@MainActor
enum ContextNoteReminderPresenter {
    static func present(_ item: FileShelfItem, on controller: ClipboardAssistantController, settings: FeatureSettings) -> Bool {
        guard settings.clipboardAssistantEnabled, settings.contextNotesEnabled, let text = item.text,
              let location = item.noteLocation, controller.presentation.detection == nil else { return false }
        let detection = ClipboardAssistantDetection(kind: .text, title: text,
            detail: .path(ContextNoteDetailView.locationDescription(location)),
            actions: [.showContextNote(item.id)], fullContent: text)
        controller.displayDuration = settings.clipboardAssistantDisplayDuration
        controller.isLightweightMode = settings.clipboardAssistantLightweightMode
        controller.presentation.progressGlowEnabled = settings.collapsedProgressGlowEnabled
        controller.presentation.notchBackground = settings.islandNotchBackground
        return controller.present(detection, visualStyle: settings.islandVisualStyle) != nil
    }
}
