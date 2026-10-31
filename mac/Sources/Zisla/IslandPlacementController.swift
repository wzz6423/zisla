import AppKit
import ZislaCore
import ZislaKit

@MainActor
final class IslandPlacementController {
    @MainActor
    struct Dependencies {
        var screens: () -> [ScreenSnapshot] = {
            NSScreen.screens.compactMap { ScreenSnapshot(screen: $0) }
        }
        var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }
        var presentWindow: (NSWindow, Bool) -> Void = { window, isPrimary in
            if isPrimary {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                window.orderFrontRegardless()
            }
        }
        var observeScreens: (@escaping @MainActor () -> Void) -> NSObjectProtocol = { action in
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in MainActor.assumeIsolated { action() } }
        }
        var removeObserver: (NSObjectProtocol) -> Void = {
            NotificationCenter.default.removeObserver($0)
        }
    }

    private let dependencies: Dependencies
    private var windows: [CGDirectDisplayID: IslandPlacementWindow] = [:]
    private var screens: [ScreenSnapshot] = []
    private var engine = ScreenLayoutEngine()
    private var screenObserver: NSObjectProtocol?
    private var completion: ((IslandPlacement) -> Void)?
    private var onCancel: (() -> Void)?
    private var dragOffset: CGPoint?
    private(set) var selection: IslandPlacement?
    private(set) var selectedDisplayID: CGDirectDisplayID?
    private(set) var previewFrame: CGRect?

    var isSelecting: Bool { completion != nil }
    var windowCount: Int { windows.count }

    init(dependencies: Dependencies = Dependencies()) {
        self.dependencies = dependencies
    }

    isolated deinit {
        tearDown()
    }

    func show(
        initialPlacement: IslandPlacement,
        configuration: ScreenLayoutConfiguration = ScreenLayoutConfiguration(),
        completion: @escaping (IslandPlacement) -> Void,
        onCancel: @escaping () -> Void
    ) {
        cancel()
        screens = dependencies.screens()
        guard !screens.isEmpty else {
            onCancel()
            return
        }
        self.completion = completion
        self.onCancel = onCancel
        var configuration = configuration
        configuration.layoutStyle = .pill
        configuration.placement = IslandPlacement(
            mode: .custom,
            edge: initialPlacement.mode == .camera ? .top : initialPlacement.edge,
            offset: initialPlacement.mode == .camera ? 0.5 : initialPlacement.offset
        )
        engine = ScreenLayoutEngine(configuration: configuration)
        selection = configuration.placement
        let screen = nearestScreen(to: dependencies.pointerLocation())
        selectedDisplayID = screen.displayID
        previewFrame = engine.layout(for: screen).collapsedFrame

        for screen in screens {
            let view = IslandPlacementView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onDragStarted = { [weak self] in self?.beginDragging(at: $0) ?? false }
            view.onDragged = { [weak self] in self?.drag(to: $0) }
            view.onDragEnded = { [weak self] in self?.endDragging(at: $0) }
            view.onConfirm = { [weak self] in self?.confirm() }
            view.onCancel = { [weak self] in self?.cancel() }
            let window = IslandPlacementWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.contentView = view
            window.onConfirm = { [weak self] in self?.confirm() }
            window.onCancel = { [weak self] in self?.cancel() }
            window.setFrame(screen.frame, display: false)
            windows[screen.displayID] = window
        }
        updateViews()
        screenObserver = dependencies.observeScreens { [weak self] in self?.screensDidChange() }
        for screen in screens where screen.displayID != selectedDisplayID {
            if let window = windows[screen.displayID] { dependencies.presentWindow(window, false) }
        }
        if let selectedDisplayID, let window = windows[selectedDisplayID] {
            dependencies.presentWindow(window, true)
        }
    }

    @discardableResult
    func beginDragging(at point: CGPoint) -> Bool {
        guard isSelecting, let previewFrame, previewFrame.contains(point) else { return false }
        dragOffset = CGPoint(x: point.x - previewFrame.midX, y: point.y - previewFrame.midY)
        return true
    }

    func drag(to point: CGPoint) {
        guard let dragOffset, let selection else { return }
        let center = CGPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
        let screen = nearestScreen(to: center)
        let placement = engine.placement(nearest: center, on: screen, preferredEdge: selection.edge)
        self.selection = placement
        selectedDisplayID = screen.displayID
        engine.configuration.placement = placement
        let size = engine.layout(for: screen).collapsedFrame.size
        previewFrame = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        updateViews()
    }

    func endDragging(at point: CGPoint) {
        guard dragOffset != nil else { return }
        drag(to: point)
        dragOffset = nil
        if let screen = screens.first(where: { $0.displayID == selectedDisplayID }) {
            previewFrame = engine.layout(for: screen).collapsedFrame
        }
        updateViews()
    }

    func confirm() {
        guard let completion, let selection else { return }
        tearDown()
        completion(selection)
    }

    func cancel() {
        guard isSelecting else { return }
        let onCancel = onCancel
        tearDown()
        onCancel?()
    }

    private func screensDidChange() {
        let current = dependencies.screens()
        guard current.count != screens.count || screens.contains(where: { !current.contains($0) }) else { return }
        cancel()
    }

    private func nearestScreen(to point: CGPoint) -> ScreenSnapshot {
        screens.min { lhs, rhs in
            distance(to: lhs.frame, from: point) < distance(to: rhs.frame, from: point)
        }!
    }

    private func distance(to frame: CGRect, from point: CGPoint) -> CGFloat {
        let x = min(frame.maxX, max(frame.minX, point.x))
        let y = min(frame.maxY, max(frame.minY, point.y))
        return hypot(point.x - x, point.y - y)
    }

    private func updateViews() {
        for screen in screens {
            guard let view = windows[screen.displayID]?.contentView as? IslandPlacementView else { continue }
            let isSelected = screen.displayID == selectedDisplayID
            view.previewFrame = isSelected
                ? previewFrame?.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) : nil
            view.targetFrame = isSelected && dragOffset != nil
                ? engine.layout(for: screen).collapsedFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                : nil
        }
    }

    private func tearDown() {
        completion = nil
        onCancel = nil
        dragOffset = nil
        selection = nil
        selectedDisplayID = nil
        previewFrame = nil
        if let screenObserver {
            dependencies.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        for window in windows.values {
            window.onConfirm = nil
            window.onCancel = nil
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        screens.removeAll()
    }
}

@MainActor
final class IslandPlacementWindow: NSWindow {
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 36, 76: onConfirm?()
        default: super.keyDown(with: event)
        }
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
private final class IslandPlacementView: NSView {
    var previewFrame: CGRect? { didSet { needsDisplay = true } }
    var targetFrame: CGRect? { didSet { needsDisplay = true } }
    var onDragStarted: ((CGPoint) -> Bool)?
    var onDragged: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let hint = NSTextField(wrappingLabelWithString: AppLocalization.text("拖动药丸到屏幕边缘，按回车完成，按 Esc 取消。"))
        hint.font = .systemFont(ofSize: 15, weight: .medium)
        hint.textColor = .white
        hint.alignment = .center
        let confirm = NSButton(title: AppLocalization.text("完成"), target: self, action: #selector(confirmClicked))
        confirm.bezelStyle = .rounded
        confirm.keyEquivalent = "\r"
        let cancel = NSButton(title: AppLocalization.text("取消"), target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancel, confirm])
        buttons.spacing = 12
        let instructions = NSStackView(views: [hint, buttons])
        instructions.orientation = .vertical
        instructions.spacing = 16
        instructions.translatesAutoresizingMaskIntoConstraints = false
        instructions.userInterfaceLayoutDirection = AppLocalization.currentLanguage.isRightToLeft ? .rightToLeft : .leftToRight
        addSubview(instructions)
        NSLayoutConstraint.activate([
            instructions.centerXAnchor.constraint(equalTo: centerXAnchor),
            instructions.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -80),
            instructions.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            hint.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
        ])
        setAccessibilityLabel(hint.stringValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.3, alpha: 0.65).setFill()
        bounds.fill()
        if let targetFrame {
            let radius = min(targetFrame.width, targetFrame.height) / 2
            let path = NSBezierPath(roundedRect: targetFrame, xRadius: radius, yRadius: radius)
            NSColor.white.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
        if let previewFrame {
            let radius = min(previewFrame.width, previewFrame.height) / 2
            let path = NSBezierPath(roundedRect: previewFrame, xRadius: radius, yRadius: radius)
            NSColor.black.setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
            NSColor.white.withAlphaComponent(0.8).setFill()
            for offset in [-5.0, 0, 5.0] {
                let isVertical = previewFrame.height > previewFrame.width
                NSBezierPath(ovalIn: CGRect(
                    x: previewFrame.midX - 1.5 + (isVertical ? 0 : offset),
                    y: previewFrame.midY - 1.5 + (isVertical ? offset : 0),
                    width: 3,
                    height: 3
                )).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        isDragging = onDragStarted?(window.convertPoint(toScreen: event.locationInWindow)) == true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window else { return }
        onDragged?(window.convertPoint(toScreen: event.locationInWindow))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let window else { return }
        isDragging = false
        onDragEnded?(window.convertPoint(toScreen: event.locationInWindow))
    }

    @objc private func confirmClicked() { onConfirm?() }
    @objc private func cancelClicked() { onCancel?() }
}
