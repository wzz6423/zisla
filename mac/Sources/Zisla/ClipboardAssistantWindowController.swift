import AppKit
import Combine
import SkyLightWindow
import SwiftUI
import ZislaCore
import ZislaKit

/// Auto-dismiss delays for the assistant toast; hovering pauses the countdown.
private extension ClipboardAssistantController {
    static let autoDismissInterval: Duration = .seconds(6)
    static let lightweightDismissInterval: Duration = .seconds(3)
    static let hoverResumeInterval: Duration = .seconds(3)
    static let collapsedHeight: CGFloat = 58
}

/// Borderless always-on-top panel hosting the assistant toast; mirrors IslandPanel's window setup.
@MainActor
final class ClipboardAssistantWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentView: NSView, frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level.statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        self.contentView = contentView
        SkyLightOperator.shared.delegateWindow(self)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Presentation state driving the toast's SwiftUI content.
@MainActor
final class ClipboardAssistantPresentation: ObservableObject {
    @Published var detection: ClipboardAssistantDetection?
    /// Thumbnail preview shown for copied images.
    @Published var imageThumbnail: NSImage?
    /// Toggled from the view so the countdown pauses while the pointer rests on the toast.
    var isHovered = false
}

/// Shows a small island-style toast below the Dynamic Island after every copy, offering smart
/// next-step actions for the copied content.
@MainActor
final class ClipboardAssistantController: ObservableObject {
    let presentation = ClipboardAssistantPresentation()
    /// Executes a detection action; provided by AppModel.
    var onPerformAction: ((ClipboardAssistantAction) -> Void)?
    /// Compact reminder mode: no buttons, tapping anywhere performs the primary action.
    var isLightweightMode = false {
        didSet {
            guard isLightweightMode != oldValue else { return }
            presentation.objectWillChange.send()
        }
    }

    private var window: ClipboardAssistantWindow?
    private var dismissTask: Task<Void, Never>?
    private let triggerMonitor = ClipboardAssistantTriggerMonitor()
    private let gestureMonitor = ClipboardAssistantMouseGestureMonitor()

    /// Applies the user-configured quick triggers (hotkey + mouse side button).
    /// Returns `false` when a configured trigger needs the input-monitoring permission
    /// that has not been granted yet.
    @discardableResult
    func setTriggers(
        hotkey: VoiceInputHotkeyPreset?,
        mouseButton: Int?
    ) -> Bool {
        triggerMonitor.apply(hotkey: hotkey, mouseButton: mouseButton) { [weak self] in
            MainActor.assumeIsolated { self?.performCurrentAction() }
        }
    }

    /// Enables the hold-left + right-click quick copy gesture. Returns `false` when either the
    /// input-monitoring or the accessibility permission is missing.
    @discardableResult
    func setMouseGesture(
        enabled: Bool,
        onQuickCopy: @escaping () -> Void
    ) -> Bool {
        guard enabled else {
            gestureMonitor.stop()
            return true
        }
        return gestureMonitor.start(onCopy: onQuickCopy)
    }

    var isMouseGestureActive: Bool { gestureMonitor.isActive }

    /// Window accessor used by the toast view to animate expansion.
    var windowForFrameUpdate: NSWindow? { window }

    func present(_ detection: ClipboardAssistantDetection) {
        dismissTask?.cancel()
        presentation.isHovered = false
        presentation.detection = detection
        presentation.imageThumbnail = Self.thumbnail(for: detection)
        showWindow(collapsedHeight: Self.collapsedHeight)
        scheduleDismiss(after: isLightweightMode ? Self.lightweightDismissInterval : Self.autoDismissInterval)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let window, window.isVisible else {
            presentation.detection = nil
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                window.orderOut(nil)
                window.alphaValue = 1
                self.presentation.detection = nil
            }
        })
    }

    /// Fires the given action (button click or quick trigger) and dismisses the toast.
    func perform(_ action: ClipboardAssistantAction) {
        onPerformAction?(action)
        dismiss()
    }

    /// Fires the current detection's primary action (quick trigger or lightweight-mode tap).
    func performCurrentAction() {
        guard let action = presentation.detection?.action else { return }
        perform(action)
    }

    func setHovered(_ hovered: Bool) {
        presentation.isHovered = hovered
        if hovered {
            dismissTask?.cancel()
            dismissTask = nil
        } else {
            scheduleDismiss(after: Self.hoverResumeInterval)
        }
    }

    private func scheduleDismiss(after interval: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.presentation.isHovered { return }
                self.dismiss()
            }
        }
    }

    private static func thumbnail(for detection: ClipboardAssistantDetection) -> NSImage? {
        guard case .saveImage(let data)? = detection.action else { return nil }
        return NSImage(data: data)
    }

    private func showWindow(collapsedHeight: CGFloat) {
        guard let screen = WindowPlacement.screenUnderMouse() ?? NSScreen.main else { return }
        let width = min(480, max(320, screen.visibleFrame.width - 48))
        // Place the toast right under the collapsed island strip at the top of the screen.
        let topInset: CGFloat = 42
        let frame = CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - topInset - collapsedHeight,
            width: width,
            height: collapsedHeight
        )
        let window: ClipboardAssistantWindow
        if let existing = self.window {
            window = existing
        } else {
            let hostingView = NSHostingView(
                rootView: AppLanguageEnvironment(
                    languageStore: AppModel.shared.languageStore,
                    content: ClipboardAssistantToastView(
                        presentation: presentation,
                        controller: self
                    )
                )
            )
            hostingView.sizingOptions = []
            window = ClipboardAssistantWindow(contentView: hostingView, frame: frame)
            self.window = window
        }
        window.setFrame(frame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }
}

/// Dark island-styled toast: thumbnail or kind icon (color swatch for colors), preview lines,
/// an optional expandable full-content view, and the offered actions. All visible strings are
/// rendered through the app localization so they follow the user's interface language.
struct ClipboardAssistantToastView: View {
    @ObservedObject var presentation: ClipboardAssistantPresentation
    @ObservedObject var controller: ClipboardAssistantController

    /// Fixed collapsed height of the toast capsule; also drives the corner radius.
    private static let collapsedHeight: CGFloat = 58
    private static let maxExpandedContentHeight: CGFloat = 220

    @Environment(\.locale) private var locale
    @State private var isExpanded = false

    var body: some View {
        Group {
            if let detection = presentation.detection {
                VStack(spacing: 0) {
                    toastHeader(detection)
                    if isExpanded, let content = expandableContent(detection) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.horizontal, 14)
                        expandedContentView(content)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Self.collapsedHeight / 2, style: .continuous)
                        .fill(Color.black.opacity(0.86))
                        .overlay(
                            RoundedRectangle(cornerRadius: Self.collapsedHeight / 2, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: Self.collapsedHeight / 2, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: presentation.detection)
                .onChange(of: presentation.detection) {
                    // A new copy collapses any previously expanded preview.
                    if isExpanded { isExpanded = false }
                }
            }
        }
    }

    // MARK: Header row

    @ViewBuilder
    private func toastHeader(_ detection: ClipboardAssistantDetection) -> some View {
        HStack(spacing: 10) {
            leadingAccessory(detection)

            VStack(alignment: .leading, spacing: 2) {
                Text(detection.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detailText = detailText(detection.detail) {
                    Text(detailText)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if controller.isLightweightMode {
                    controller.performCurrentAction()
                } else if canExpand(detection) {
                    toggleExpansion(detection)
                }
            }

            trailingControls(detection)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.collapsedHeight)
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(detection.actions, id: \.identifier) { action in
                Button(loc(actionLabel(action))) {
                    controller.perform(action)
                }
            }
        }
        .onHover { hovering in
            controller.setHovered(hovering)
        }
    }

    @ViewBuilder
    private func leadingAccessory(_ detection: ClipboardAssistantDetection) -> some View {
        if let thumbnail = presentation.imageThumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        } else if let components = detection.colorComponents {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(red: components.red, green: components.green, blue: components.blue))
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        } else {
            Image(systemName: detection.kind.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 26, height: 26)
        }
    }

    @ViewBuilder
    private func trailingControls(_ detection: ClipboardAssistantDetection) -> some View {
        if controller.isLightweightMode {
            // Lightweight mode keeps the toast minimal: no buttons at all.
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20, height: 20)
        } else {
            if canExpand(detection) {
                Button {
                    toggleExpansion(detection)
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? loc("收起") : loc("展开完整内容"))
            }
            ForEach(detection.secondaryActions, id: \.identifier) { action in
                Button {
                    controller.perform(action)
                } label: {
                    Text(loc(actionLabel(action)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .help(loc(actionLabel(action)))
            }
            if let primary = detection.action {
                Button {
                    controller.perform(primary)
                } label: {
                    Text(loc(actionLabel(primary)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help(loc(actionLabel(primary)))
            }
            Button {
                controller.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc("关闭"))
        }
    }

    // MARK: Expanded content

    private func canExpand(_ detection: ClipboardAssistantDetection) -> Bool {
        guard !controller.isLightweightMode, let content = detection.fullContent else { return false }
        return content.count > 40 || content.contains("\n")
    }

    private func expandableContent(_ detection: ClipboardAssistantDetection) -> String? {
        canExpand(detection) ? detection.fullContent : nil
    }

    private func toggleExpansion(_ detection: ClipboardAssistantDetection) {
        isExpanded.toggle()
        let expanded = isExpanded
        guard let window = controller.windowForFrameUpdate else { return }
        guard let screen = WindowPlacement.screenUnderMouse() ?? NSScreen.main else { return }
        var frame = window.frame
        let topY = frame.maxY
        var newHeight = Self.collapsedHeight
        if expanded {
            let textHeight = estimateExpandedHeight(detection.fullContent ?? "", width: frame.width)
            newHeight = Self.collapsedHeight + min(textHeight, Self.maxExpandedContentHeight)
        }
        newHeight = min(newHeight, screen.visibleFrame.height - 80)
        frame.origin.y = topY - newHeight
        frame.size.height = newHeight
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: false)
        }
    }

    private func estimateExpandedHeight(_ content: String, width: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let textWidth = width - 40
        var totalLines: CGFloat = 0
        for line in content.components(separatedBy: "\n") {
            let lineWidth = (line as NSString).size(withAttributes: [.font: font]).width
            totalLines += lineWidth > 0 ? max(1, ceil(lineWidth / max(textWidth, 1))) : 1
        }
        return totalLines * 13 + 24
    }

    private func expandedContentView(_ content: String) -> some View {
        ScrollView(.vertical) {
            Text(content)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(height: isExpanded ? nil : 0)
    }

    // MARK: Localized strings

    private func loc(_ key: String) -> String {
        AppLocalization.string(key, locale: locale)
    }

    /// Locale-aware rendering of the structured detection detail.
    private func detailText(_ detail: ClipboardAssistantDetail?) -> String? {
        switch detail {
        case .characterCount(let count):
            AppLocalization.format("%ld 个字符", locale: locale, [count])
        case .characterAndWordCount(let characters, let words):
            AppLocalization.format("%ld 个字符 · %ld 个词", locale: locale, [characters, words])
        case .chineseCharacterCount(let count):
            AppLocalization.format("%ld 个字", locale: locale, [count])
        case .codeLines(let lines):
            AppLocalization.format("%ld 行", locale: locale, [lines])
        case .imageSize(let wide, let high, let bytes):
            "\(wide) × \(high) · " + byteCountText(bytes)
        case .fileSize(let bytes):
            byteCountText(bytes)
        case .mathExpression(let expression):
            expression + " ="
        case .rgb(let red, let green, let blue, let hex):
            String(format: "R%.0f G%.0f B%.0f · #%@", red * 255, green * 255, blue * 255, hex)
        case .path(let path):
            path
        case nil:
            nil
        }
    }

    private func byteCountText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Localization key for each executable action.
    private func actionLabel(_ action: ClipboardAssistantAction) -> String {
        switch action {
        case .openURL: "打开链接"
        case .openDownload: "下载"
        case .revealInFinder: "在 Finder 中显示"
        case .search: "搜索"
        case .translate: "翻译"
        case .composeMail: "写邮件"
        case .copyText: "复制结果"
        case .saveImage: "保存图片"
        case .saveText: "保存文本"
        case .createCalendarEvent: "新建日程"
        }
    }
}


/// Fires the assistant's primary action from user-configured quick triggers:
/// - Ordinary hotkey combos register through Carbon (no permission needed).
/// - Modifier-only hotkeys use a listen-only event tap with double-tap detection, so ordinary
///   modifier usage (copy/paste chords) never fires the action accidentally.
/// - Mouse side buttons always require the input-monitoring permission.
@MainActor
final class ClipboardAssistantTriggerMonitor {
    private var configuredHotkey: VoiceInputHotkeyPreset?
    private var configuredMouseButton: Int?
    private var needsInputMonitoring = false
    private let carbonHotkeyManager = GlobalHotkeyManager()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierKeyCode: UInt32?
    private var lastModifierReleaseAt: TimeInterval = 0
    private var onTrigger: (() -> Void)?
    private static let doubleTapWindow: TimeInterval = 0.45

    /// Applies both triggers. Returns `false` when any configured trigger needs the
    /// input-monitoring permission that is not granted yet.
    @discardableResult
    func apply(
        hotkey: VoiceInputHotkeyPreset?,
        mouseButton: Int?,
        onTrigger: @escaping () -> Void
    ) -> Bool {
        guard hotkey != configuredHotkey || mouseButton != configuredMouseButton || needsInputMonitoring else {
            return true
        }
        stop()
        configuredHotkey = hotkey
        configuredMouseButton = mouseButton

        needsInputMonitoring = false
        if let hotkey {
            if hotkey.isModifierOnly {
                if GlobalHotkeyManager.hasInputMonitoringAccess {
                    modifierKeyCode = hotkey.keyCode
                    ensureEventTap()
                } else {
                    needsInputMonitoring = true
                }
            } else {
                carbonHotkeyManager.register(hotkey: hotkey, onKeyDown: onTrigger, onKeyUp: {})
            }
        }
        if mouseButton != nil {
            if GlobalHotkeyManager.hasInputMonitoringAccess {
                ensureEventTap()
            } else {
                needsInputMonitoring = true
            }
        }
        self.onTrigger = onTrigger
        return !needsInputMonitoring
    }

    func stop() {
        carbonHotkeyManager.unregister()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        modifierKeyCode = nil
        lastModifierReleaseAt = 0
        configuredHotkey = nil
        configuredMouseButton = nil
        needsInputMonitoring = false
    }

    /// One shared listen-only tap covers both flagsChanged (modifier double-tap) and
    /// otherMouseDown (side button); the handler filters events by the current configuration.
    private func ensureEventTap() {
        guard eventTap == nil else { return }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventType.flagsChanged.rawValue
                | CGEventMask(1) << CGEventType.otherMouseDown.rawValue,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ClipboardAssistantTriggerMonitor>
                    .fromOpaque(userInfo).takeUnretainedValue()
                MainActor.assumeIsolated {
                    monitor.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .otherMouseDown:
            let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard buttonNumber == configuredMouseButton else { return }
            onTrigger?()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        default:
            break
        }
    }

    /// Double-tap detection for modifier-only hotkeys: only completed press-release cycles count.
    private func handleFlagsChanged(_ event: CGEvent) {
        guard let targetKeyCode = modifierKeyCode else { return }
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == targetKeyCode else { return }
        let stillPressed = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
        guard !stillPressed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let interval = now - lastModifierReleaseAt
        if interval > 0.03, interval <= Self.doubleTapWindow {
            lastModifierReleaseAt = 0
            onTrigger?()
        } else {
            lastModifierReleaseAt = now
        }
    }
}

/// Hold-left-mouse + right-click quick copy gesture (off by default): listens globally for a
/// right mouse-down while the left button is held, then simulates ⌘C so the selection lands in
/// the pasteboard and the assistant picks it up. Requires input monitoring (listening) and
/// accessibility (posting keystrokes) permissions.
@MainActor
final class ClipboardAssistantMouseGestureMonitor {
    private(set) var isActive = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onCopy: (() -> Void)?

    /// Starts listening; returns `false` when the required permissions are missing.
    @discardableResult
    func start(onCopy: @escaping () -> Void) -> Bool {
        stop()
        guard GlobalHotkeyManager.hasInputMonitoringAccess,
              AccessibilityPermission.isTrusted else {
            return false
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventType.otherMouseDown.rawValue,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ClipboardAssistantMouseGestureMonitor>
                    .fromOpaque(userInfo).takeUnretainedValue()
                MainActor.assumeIsolated {
                    monitor.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        self.onCopy = onCopy
        isActive = true
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        onCopy = nil
        isActive = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .otherMouseDown:
            // Right mouse down (CGEvent button 1) while the left button stays held.
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            guard buttonNumber == Int64(CGMouseButton.right.rawValue) else { return }
            guard CGEventSource.buttonState(.combinedSessionState, button: .left) else { return }
            postCommandC()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        default:
            break
        }
    }

    /// Simulates ⌘C on a detached queue so the event-tap handler returns immediately.
    private func postCommandC() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let keyC: CGKeyCode = 8 // kVK_ANSI_C
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyC, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: keyC, keyDown: false)
            else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            usleep(30_000)
            up.post(tap: .cghidEventTap)
        }
        onCopy?()
    }
}
