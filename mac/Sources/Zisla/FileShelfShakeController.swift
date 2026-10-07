import AppKit
import Combine
import SwiftUI
import ZislaCore
import ZislaKit

struct FileShelfShakeSession {
    private var detector = DragShakeDetector()
    private(set) var changeCount: Int?

    mutating func record(
        _ point: CGPoint,
        at timestamp: TimeInterval,
        changeCount: Int,
        hasSupportedPayload: Bool,
        hasFilePayload: Bool
    ) -> Bool {
        guard hasSupportedPayload, hasFilePayload else {
            reset()
            return false
        }
        if self.changeCount != changeCount {
            detector.reset()
            self.changeCount = changeCount
        }
        return detector.record(point, at: timestamp)
    }

    mutating func reset() {
        detector.reset()
        changeCount = nil
    }
}

enum FileShelfShakeLayout {
    static let size = CGSize(width: 448, height: 144)
    static let shareWidth = (size.width - IslandModuleLayout.shelfColumnSpacing)
        * IslandModuleLayout.shelfShareWidth
        / (IslandModuleLayout.shelf.islandSize.width - IslandSurfaceGeometry.moduleInset * 2
           - IslandModuleLayout.shelfColumnSpacing)

    static func frame(near point: CGPoint, in visibleFrame: CGRect) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(Self.size.width, bounds.width), height: min(Self.size.height, bounds.height))
        let proposedX = point.x + 28 + size.width <= bounds.maxX
            ? point.x + 28 : point.x - 28 - size.width
        return CGRect(
            x: min(max(proposedX, bounds.minX), bounds.maxX - size.width),
            y: min(max(point.y - size.height / 2, bounds.minY), bounds.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
final class FileShelfShakeController: NSObject {
    private static let fileTypes: [NSPasteboard.PasteboardType] = [.fileURL]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    private let settingsStore: FeatureSettingsStore
    private let languageStore: AppLanguageStore
    private let dragPasteboard: NSPasteboard
    private let onItems: ([FileShelfDropItem]) -> Void
    private let onShare: ([TransferDropItem], NSView) -> Void
    private let windowPresenter: (FileShelfShakeController, CGPoint) -> Void
    private let dismissSleeper: @Sendable (Duration) async throws -> Void
    private let pressedMouseButtons: () -> Int
    private var settingsSubscription: AnyCancellable?
    private var pointerMonitor: PointerEdgeMonitor?
    private var session = FileShelfShakeSession()
    private var window: IslandPanel?
    private(set) var releaseTimer: Timer?
    private(set) var dismissTask: Task<Void, Never>?
    private var isEnabled = false
    private var isScreenLocked = false
    private var isScreenshotActive = false
    private(set) var isPresented = false
    private(set) var isSharing = false

    var isMonitoring: Bool { pointerMonitor?.isRunning == true }

    init(
        settingsStore: FeatureSettingsStore,
        languageStore: AppLanguageStore,
        dragPasteboard: NSPasteboard = NSPasteboard(name: .drag),
        windowPresenter: @escaping (FileShelfShakeController, CGPoint) -> Void = { $0.presentWindow(at: $1) },
        dismissSleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        pressedMouseButtons: @escaping () -> Int = { NSEvent.pressedMouseButtons },
        onItems: @escaping ([FileShelfDropItem]) -> Void,
        onShare: @escaping ([TransferDropItem], NSView) -> Void
    ) {
        self.settingsStore = settingsStore
        self.languageStore = languageStore
        self.dragPasteboard = dragPasteboard
        self.windowPresenter = windowPresenter
        self.dismissSleeper = dismissSleeper
        self.pressedMouseButtons = pressedMouseButtons
        self.onItems = onItems
        self.onShare = onShare
        super.init()

        settingsSubscription = settingsStore.$settings
            .map { $0.fileShelfEnabled && $0.fileShelfShakeEnabled }
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.isEnabled = enabled
                self?.updateMonitoring()
            }
        NotificationCenter.default.addObserver(
            self, selector: #selector(environmentDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(environmentDidChange), name: name, object: nil
            )
        }
    }

    func setScreenLocked(_ locked: Bool) {
        isScreenLocked = locked
        updateMonitoring()
    }

    func setScreenshotActive(_ active: Bool) {
        isScreenshotActive = active
        updateMonitoring()
    }

    func stop() {
        settingsSubscription = nil
        isEnabled = false
        updateMonitoring()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    isolated deinit {
        pointerMonitor?.stop()
        releaseTimer?.invalidate()
        dismissTask?.cancel()
        window?.close()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func updateMonitoring() {
        guard isEnabled, !isScreenLocked, !isScreenshotActive else {
            pointerMonitor?.stop()
            pointerMonitor = nil
            dismiss()
            return
        }
        guard pointerMonitor == nil else { return }
        let monitor = PointerEdgeMonitor(dragPasteboard: dragPasteboard) { [weak self] point, interaction in
            self?.handlePointer(at: point, interaction: interaction)
        }
        pointerMonitor = monitor
        monitor.start()
    }

    func handlePointer(
        at point: CGPoint,
        interaction: PointerEdgeMonitor.Interaction,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard isMonitoring, !isSharing else { return }
        switch interaction {
        case .dragging(let supported):
            let changeCount = dragPasteboard.changeCount
            let hasFiles = dragPasteboard.availableType(from: Self.fileTypes) != nil
            if !supported || !hasFiles || (session.changeCount != nil && session.changeCount != changeCount) {
                dismiss()
            }
            dismissTask?.cancel()
            dismissTask = nil
            if session.record(point, at: timestamp, changeCount: changeCount,
                              hasSupportedPayload: supported, hasFilePayload: hasFiles) {
                isPresented = true
                windowPresenter(self, point)
                let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.checkForDragEnd() }
                }
                releaseTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        case .dragEnded, .moved:
            if isPresented {
                scheduleDismiss()
            } else {
                session.reset()
            }
        }
    }

    private func checkForDragEnd() {
        if pressedMouseButtons() == 0 { scheduleDismiss() }
    }

    func receive(_ items: [FileShelfDropItem], forChangeCount changeCount: Int) {
        guard isPresented, !isSharing, session.changeCount == changeCount else { return }
        dismiss()
        onItems(items)
    }

    func share(_ items: [TransferDropItem], from anchor: NSView, forChangeCount changeCount: Int) {
        guard isPresented, !isSharing, session.changeCount == changeCount else { return }
        isSharing = true
        dismissTask?.cancel()
        dismissTask = nil
        releaseTimer?.invalidate()
        releaseTimer = nil
        onShare(items, anchor)
    }

    func sharingDidEnd() {
        if isSharing { dismiss() }
    }

    private func scheduleDismiss() {
        guard isPresented, dismissTask == nil else { return }
        // The source mouse-up can precede AppKit's performDragOperation on our destination.
        dismissTask = Task { @MainActor [weak self, dismissSleeper] in
            do { try await dismissSleeper(.milliseconds(200)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        session.reset()
        dismissTask?.cancel()
        dismissTask = nil
        releaseTimer?.invalidate()
        releaseTimer = nil
        isPresented = false
        isSharing = false
        window?.close()
        window = nil
    }

    @objc private func environmentDidChange(_ notification: Notification) {
        dismiss()
    }

    private func presentWindow(at point: CGPoint) {
        guard let screen = WindowPlacement.screenUnderMouse(point: point) else { return }
        let changeCount = dragPasteboard.changeCount
        let content = FileShelfShakeView(settingsStore: settingsStore, onItems: { [weak self] in
            self?.receive($0, forChangeCount: changeCount)
        }, onShare: { [weak self] items, anchor in
            self?.share(items, from: anchor, forChangeCount: changeCount)
        })
        let hostingView = NSHostingView(rootView: AppLanguageEnvironment(languageStore: languageStore, content: content))
        hostingView.sizingOptions = []
        let panel = Self.makeWindow(contentView: hostingView, frame: FileShelfShakeLayout.frame(near: point, in: screen.visibleFrame))
        window = panel
        panel.orderFrontRegardless()
    }

    static func makeWindow(contentView: NSView, frame: CGRect) -> IslandPanel {
        let panel = IslandPanel(contentView: contentView, frame: frame, blocksClicksInTransparentAreas: true)
        panel.avoidsAppActivation = true
        panel.hasShadow = true
        return panel
    }
}
