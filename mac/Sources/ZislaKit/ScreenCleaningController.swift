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

/// 清屏使用全屏黑遮罩；键盘清洁通过辅助功能授权后的全局 event tap 吞掉按键。
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
        guard Self.hasAccessibilityAccess else { return .accessibilityPermissionRequired }
        guard installKeyboardEventTap() else { return .registrationFailed }
        isKeyboardCleaning = true
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
        // 隐藏 Dock，避免鼠标移到底部时 Dock 浮出遮罩
        savedPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions.insert(.hideDock)
        let screens = NSScreen.screens
        for (index, screen) in screens.enumerated() {
            let window = makeOverlayWindow(for: screen)
            overlayWindows.append(window)
            if index == 0 {
                // 主屏窗口成为 key window，确保能接收鼠标点击（borderless 默认 canBecomeKey=false，
                // 用子类 CleaningOverlayWindow 覆写为 true；且 acceptsFirstMouse=true 让非前台状态下
                // 第一次点击也能直接派发 mouseDown，而不是被系统拿去激活窗口）。
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
        let eventMask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keyboardCleaningEventTapCallback,
            userInfo: selfPointer
        ) else {
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        keyboardEventTap = eventTap
        keyboardEventTapRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        return true
    }

    private func removeKeyboardEventTap() {
        if let keyboardEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyboardEventTapRunLoopSource, .commonModes)
            self.keyboardEventTapRunLoopSource = nil
        }
        keyboardEventTap = nil
    }

    fileprivate func shouldPassKeyboardEventTap(type: CGEventType) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyboardEventTap {
                CGEvent.tapEnable(tap: keyboardEventTap, enable: true)
            }
            return true
        }
        return false
    }
}

/// 无边框黑遮罩窗口需要成为 key window，才能接收点击退出。
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
    let shouldPass = MainActor.assumeIsolated { controller.shouldPassKeyboardEventTap(type: type) }
    return shouldPass ? Unmanaged.passUnretained(event) : nil
}
