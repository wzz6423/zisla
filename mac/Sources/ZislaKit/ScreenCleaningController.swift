import AppKit
@preconcurrency import ApplicationServices
import Combine
import Foundation

public enum KeyboardCleaningStartResult: Equatable, Sendable {
    case started
    case alreadyActive
    case accessibilityPermissionRequired
    case registrationFailed
}

/// Screen cleaning uses a full-screen black overlay; keyboard cleaning swallows key events via a global event tap after accessibility authorization.
@MainActor
public final class ScreenCleaningController: ObservableObject {
    @Published public private(set) var isScreenCleaning = false
    @Published public private(set) var isKeyboardCleaning = false

    public var onCleaningDidEnd: (() -> Void)?

    private var overlayWindows: [NSWindow] = []
    private var keyboardEventTap: CFMachPort?
    private var keyboardEventTapRunLoopSource: CFRunLoopSource?
    private var screenChangeObserver: NSObjectProtocol?
    private var savedPresentationOptions: NSApplication.PresentationOptions?

    public init() {}

    public static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestAccessibilityAccess() -> Bool {
        let authorizationHost = WindowPlacement.authorizationPromptHost()
        defer {
            authorizationHost?.orderOut(nil)
            authorizationHost?.close()
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static let systemDefinedEventTypeRawValue: UInt32 =
        UInt32(NSEvent.EventType.systemDefined.rawValue)
    private nonisolated static let auxiliaryControlSubtypeRawValue: Int16 = 8

    static let keyboardCleaningEventMask: CGEventMask = [
        CGEventType.keyDown.rawValue,
        CGEventType.keyUp.rawValue,
        CGEventType.flagsChanged.rawValue,
        // CoreGraphics omits the system-defined case from its Swift API, although event taps
        // still deliver it for hardware function/media keys.
        systemDefinedEventTypeRawValue,
    ].reduce(CGEventMask(0)) {
        $0 | (CGEventMask(1) << $1)
    }

    isolated deinit {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        removeKeyboardEventTap()
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    public func startScreenCleaning() {
        guard !isScreenCleaning else { return }
        endKeyboardCleaning(notify: false)
        presentBlackOverlays()
        isScreenCleaning = true
    }

    public func endScreenCleaning() {
        endScreenCleaning(notify: true)
    }

    private func endScreenCleaning(notify: Bool) {
        guard isScreenCleaning else { return }
        tearDownOverlays()
        isScreenCleaning = false
        if notify { onCleaningDidEnd?() }
    }

    @discardableResult
    public func startKeyboardCleaning() -> KeyboardCleaningStartResult {
        guard !isKeyboardCleaning else { return .alreadyActive }
        endScreenCleaning(notify: false)
        let result = Self.keyboardCleaningStartResult(
            eventTapInstalled: installKeyboardEventTap(),
            hasAccessibilityAccess: Self.hasAccessibilityAccess
        )
        guard result == .started else { return result }
        isKeyboardCleaning = true
        return .started
    }

    static func keyboardCleaningStartResult(
        eventTapInstalled: Bool,
        hasAccessibilityAccess: @autoclosure () -> Bool
    ) -> KeyboardCleaningStartResult {
        guard eventTapInstalled else {
            return hasAccessibilityAccess() ? .registrationFailed : .accessibilityPermissionRequired
        }
        return .started
    }

    public func endKeyboardCleaning() {
        endKeyboardCleaning(notify: true)
    }

    private func endKeyboardCleaning(notify: Bool) {
        guard isKeyboardCleaning else { return }
        removeKeyboardEventTap()
        isKeyboardCleaning = false
        if notify { onCleaningDidEnd?() }
    }

    public func stopAll() {
        endScreenCleaning()
        endKeyboardCleaning()
    }

    private func presentBlackOverlays() {
        tearDownOverlays()
        // Hide the Dock so it doesn't float above the overlay when the cursor moves to the bottom.
        savedPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions.insert(.hideDock)
        let screens = NSScreen.screens
        for (index, screen) in screens.enumerated() {
            let window = makeOverlayWindow(for: screen)
            overlayWindows.append(window)
            if index == 0 {
                // The primary-screen window becomes the key window so it can receive mouse clicks
                // (borderless windows have canBecomeKey=false by default; CleaningOverlayWindow
                // overrides it to true, and acceptsFirstMouse=true lets the first click while the
                // app is inactive dispatch mouseDown directly rather than just activating the window).
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        startObservingScreenChanges()
    }

    private func startObservingScreenChanges() {
        if screenChangeObserver == nil {
            screenChangeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreenChange()
                }
            }
        }
    }

    private func handleScreenChange() {
        if isScreenCleaning {
            presentBlackOverlays()
        }
    }

    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = CleaningOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = false

        let root = CleaningOverlayRootView(
            showsEndControl: true,
            onClickToDismiss: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.endScreenCleaning()
                }
            }
        )
        window.contentView = root
        window.setFrame(screen.frame, display: true)
        return window
    }

    private func tearDownOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.contentView = nil
        }
        overlayWindows.removeAll()
        removeScreenChangeObserver()
        if let savedPresentationOptions {
            NSApp.presentationOptions = savedPresentationOptions
            self.savedPresentationOptions = nil
        }
    }

    private func removeScreenChangeObserver() {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
    }

    private func installKeyboardEventTap() -> Bool {
        removeKeyboardEventTap()
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.keyboardCleaningEventMask,
            callback: keyboardCleaningEventTapCallback,
            userInfo: selfPointer
        ) else {
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        keyboardEventTap = eventTap
        keyboardEventTapRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func removeKeyboardEventTap() {
        if let keyboardEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyboardEventTapRunLoopSource, .commonModes)
            self.keyboardEventTapRunLoopSource = nil
        }
        keyboardEventTap = nil
    }

    nonisolated static func shouldBlockSystemDefinedEvent(_ event: NSEvent) -> Bool {
        event.type == .systemDefined
            && event.subtype.rawValue == auxiliaryControlSubtypeRawValue
    }

    fileprivate func shouldPassKeyboardEventTap(
        type: CGEventType,
        blocksAuxiliaryControl: Bool
    ) -> Bool {
        let rawEventType = type.rawValue
        if rawEventType == CGEventType.tapDisabledByTimeout.rawValue
            || rawEventType == CGEventType.tapDisabledByUserInput.rawValue {
            if let keyboardEventTap {
                CGEvent.tapEnable(tap: keyboardEventTap, enable: true)
            }
            return true
        }

        if rawEventType == Self.systemDefinedEventTypeRawValue {
            return !blocksAuxiliaryControl
        }

        return false
    }
}

/// Borderless black overlay window that must become the key window to receive click-to-dismiss.
private final class CleaningOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class CleaningOverlayRootView: NSView {
    private let onClickToDismiss: () -> Void

    init(
        showsEndControl: Bool,
        onClickToDismiss: @escaping () -> Void
    ) {
        self.onClickToDismiss = onClickToDismiss
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        if showsEndControl {
            let button = CleaningExitControl(
                title: "退出清洁屏幕",
                onClick: onClickToDismiss
            )
            button.autoresizingMask = [
                .minXMargin,
                .maxXMargin,
                .minYMargin,
                .maxYMargin,
            ]
            button.frame = exitButtonFrame(in: bounds)
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        for case let button as CleaningExitControl in subviews {
            button.frame = exitButtonFrame(in: bounds)
        }
    }

    private func exitButtonFrame(in bounds: CGRect) -> CGRect {
        let size = CGSize(width: 184, height: 52)
        return CGRect(
            x: floor(bounds.midX - size.width / 2),
            y: floor(bounds.midY - size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    override func mouseDown(with event: NSEvent) {
        onClickToDismiss()
    }

    override var acceptsFirstResponder: Bool { true }
}

@MainActor
private final class CleaningExitControl: NSView {
    private let title: String
    private let onClick: () -> Void

    init(title: String, onClick: @escaping () -> Void) {
        self.title = title
        self.onClick = onClick
        super.init(frame: .zero)
        toolTip = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.28, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ]
        let textHeight = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(
            in: CGRect(x: 0, y: floor((bounds.height - textHeight) / 2), width: bounds.width, height: textHeight),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}

private func keyboardCleaningEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userData: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userData else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<ScreenCleaningController>.fromOpaque(userData).takeUnretainedValue()
    let blocksAuxiliaryControl = type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue)
        && (NSEvent(cgEvent: event).map(ScreenCleaningController.shouldBlockSystemDefinedEvent) ?? false)
    let shouldPass = MainActor.assumeIsolated {
        controller.shouldPassKeyboardEventTap(
            type: type,
            blocksAuxiliaryControl: blocksAuxiliaryControl
        )
    }
    return shouldPass ? Unmanaged.passUnretained(event) : nil
}
