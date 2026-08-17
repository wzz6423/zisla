import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import os.log

private let deliveryLogger = Logger(
    subsystem: "com.zisla.ZislaKit",
    category: "VoiceTranscriptDelivery"
)

public enum VoiceTranscriptDeliveryOutcome: Equatable, Sendable {
    case copiedAndPasted
    case copiedOnly
    case copyFailed
}

enum HoveredInputDeliveryResult: Equatable, Sendable {
    case noInput
    case pasted
    case blocked
}

/// The AX element captured at recording start. Mouse position is only a fallback for recovering focus.
@MainActor
public final class VoiceTranscriptDeliveryTarget {
    public let processIdentifier: pid_t
    fileprivate let element: AXUIElement

    fileprivate init(processIdentifier: pid_t, element: AXUIElement) {
        self.processIdentifier = processIdentifier
        self.element = element
    }
}

@MainActor
public struct VoiceTranscriptDelivery {
    private let pasteboard: NSPasteboard
    private let pasteIntoTargetInput: (String, CGPoint?) -> HoveredInputDeliveryResult
    private let postPaste: (pid_t) -> Bool

    public init() {
        pasteboard = .general
        pasteIntoTargetInput = Self.pasteIntoTargetTextInput
        postPaste = Self.postCommandV
    }

    init(
        pasteboard: NSPasteboard,
        pasteIntoTargetInput: @escaping (String, CGPoint?) -> HoveredInputDeliveryResult,
        postPaste: @escaping (pid_t) -> Bool
    ) {
        self.pasteboard = pasteboard
        self.pasteIntoTargetInput = pasteIntoTargetInput
        self.postPaste = postPaste
    }

    // Preserve the single-parameter injector for legacy tests and internal callers, avoiding an unrelated API migration.
    init(
        pasteboard: NSPasteboard,
        pasteIntoHoveredInput: @escaping (String) -> HoveredInputDeliveryResult,
        postPaste: @escaping (pid_t) -> Bool
    ) {
        self.init(
            pasteboard: pasteboard,
            pasteIntoTargetInput: { transcript, _ in pasteIntoHoveredInput(transcript) },
            postPaste: postPaste
        )
    }

    public func deliver(
        _ transcript: String,
        to targetProcessIdentifier: pid_t?,
        at savedMouseLocation: CGPoint? = nil,
        target: VoiceTranscriptDeliveryTarget? = nil
    ) -> VoiceTranscriptDeliveryOutcome {
        guard ClipboardHistoryPasteboard.write(.text(transcript), to: pasteboard) else {
            deliveryLogger.error("deliver: clipboard write failed")
            return .copyFailed
        }

        // Writes to the pasteboard server are asynchronous; sending Cmd+V too early reads stale content.
        Thread.sleep(forTimeInterval: 0.08)

        let targetPID = target?.processIdentifier ?? targetProcessIdentifier
        if let targetPID, Self.isExternalProcess(targetPID) {
            Self.reactivateTargetApplication(targetPID, waitUntilFrontmost: true)
        }

        // Prefer the element captured at recording start so mouse movement or the panel cannot redirect focus.
        if let target,
           target.processIdentifier == targetPID,
           Self.isExternalProcess(target.processIdentifier) {
            _ = Self.focus(target.element)
            if Self.tryDirectTextInsertion(target.element, text: transcript) {
                deliveryLogger.info("deliver: direct AX insertion succeeded on saved target")
                return .copiedAndPasted
            }
        }

        // If the captured element is stale, read the target app's current AX focus.
        if let targetPID,
           Self.isExternalProcess(targetPID),
           let focused = Self.focusedEditableTextInput(in: targetPID) {
            _ = Self.focus(focused)
            if Self.tryDirectTextInsertion(focused, text: transcript) {
                deliveryLogger.info("deliver: direct AX insertion succeeded on current focus")
                return .copiedAndPasted
            }
        }

        // Direct insertion usually fails in web apps, so send Cmd+V to the known target process.
        if let targetPID, Self.isExternalProcess(targetPID) {
            if postPaste(targetPID) {
                deliveryLogger.info("deliver: posted Cmd+V to target process")
                return .copiedAndPasted
            }
        }

        // Without an explicit target process, fall back to the input under the saved mouse position.
        switch pasteIntoTargetInput(transcript, savedMouseLocation) {
        case .pasted:
            deliveryLogger.info("deliver: pasted via hovered input")
            return .copiedAndPasted
        case .blocked:
            deliveryLogger.warning("deliver: hovered input blocked paste")
            return .copiedOnly
        case .noInput:
            deliveryLogger.error("deliver: no valid input target found")
            return .copiedOnly
        }
    }

    /// Captures the frontmost app's actual focused element at recording start.
    public static func captureTarget(for processIdentifier: pid_t? = nil) -> VoiceTranscriptDeliveryTarget? {
        guard AXIsProcessTrusted() else { return nil }

        let pid = processIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
            ?? 0
        guard isExternalProcess(pid) else { return nil }

        let application = AXUIElementCreateApplication(pid)
        guard let focused = elementAttribute(kAXFocusedUIElementAttribute, of: application),
              let editable = findEditableTextInput(from: focused),
              pidOf(element: editable) == pid else {
            return nil
        }
        return VoiceTranscriptDeliveryTarget(processIdentifier: pid, element: editable)
    }

    /// Restores focus to the target element when recording ends.
    public static func focusTarget(_ target: VoiceTranscriptDeliveryTarget) -> Bool {
        focus(target.element)
    }

    public static func reactivateTargetApplication(
        _ processIdentifier: pid_t,
        waitUntilFrontmost: Bool = false
    ) {
        guard isExternalProcess(processIdentifier),
              let application = NSRunningApplication(processIdentifier: processIdentifier) else {
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != processIdentifier else {
            return
        }
        application.activate()
        guard waitUntilFrontmost else { return }
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != processIdentifier {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    public static func shouldRequestEventSynthesisAccess(
        hasAccess: Bool,
        hasRequestedInCurrentLaunch: Bool
    ) -> Bool {
        !hasAccess && !hasRequestedInCurrentLaunch
    }

    @discardableResult
    public static func requestEventSynthesisAccess() -> Bool {
        requestEventSynthesisAccess(
            hasAccess: CGPreflightPostEventAccess(),
            requestAccess: { CGRequestPostEventAccess() }
        )
    }

    static func requestEventSynthesisAccess(
        hasAccess: Bool,
        requestAccess: () -> Bool
    ) -> Bool {
        hasAccess || requestAccess()
    }

    static func postCommandVWithStrategy(
        to processIdentifier: pid_t,
        hasPostEventAccess: Bool,
        postToPID: (pid_t) -> Bool
    ) -> Bool {
        guard hasPostEventAccess else { return false }
        return postToPID(processIdentifier)
    }

    static func commandVEvents() -> (
        commandDown: CGEvent,
        vDown: CGEvent,
        vUp: CGEvent,
        commandUp: CGEvent
    )? {
        let source = CGEventSource(stateID: .privateState)
        guard let commandDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 55,
            keyDown: true
        ), let vDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 9,
            keyDown: true
        ), let vUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 9,
            keyDown: false
        ), let commandUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 55,
            keyDown: false
        ) else {
            return nil
        }
        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        return (commandDown, vDown, vUp, commandUp)
    }

    static func deliverToHoveredTarget(
        processIdentifier: pid_t,
        isFrontmost: Bool,
        isFocused: Bool,
        postPaste: (pid_t) -> Bool
    ) -> Bool {
        guard isFrontmost, isFocused else { return false }
        return postPaste(processIdentifier)
    }

    static func isEditableTextInput(role: String, subrole: String?, isEnabled: Bool) -> Bool {
        guard isEnabled, subrole != kAXSecureTextFieldSubrole as String else { return false }
        return [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ].contains(role)
    }

    static func isFocusedPasteTarget(
        role: String,
        subrole: String?,
        isEnabled: Bool?,
        belongsToHitProcess: Bool,
        containsPointer: Bool
    ) -> Bool {
        guard belongsToHitProcess, containsPointer,
              subrole != kAXSecureTextFieldSubrole as String else { return false }
        let standardRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]
        if standardRoles.contains(role) { return isEnabled != false }
        if role == kAXGroupRole as String, subrole == "iOSContentGroup" { return isEnabled != false }
        if role == kAXUnknownRole as String { return isEnabled != false }
        return false
    }

    /// Replaces a UTF-16 selection for both tests and AX delivery without truncating emoji or CJK characters.
    static func replacingSelection(
        in value: String,
        location: Int,
        length: Int,
        with replacement: String
    ) -> String? {
        let source = value as NSString
        guard location >= 0, length >= 0, location <= source.length,
              length <= source.length - location else { return nil }
        return source.replacingCharacters(
            in: NSRange(location: location, length: length),
            with: replacement
        )
    }

    private static func postCommandV(to processIdentifier: pid_t) -> Bool {
        guard let events = commandVEvents() else { return false }
        let sequence = [events.commandDown, events.vDown, events.vUp, events.commandUp]

        return postCommandVWithStrategy(
            to: processIdentifier,
            hasPostEventAccess: CGPreflightPostEventAccess()
        ) { pid in
            let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            for (index, event) in sequence.enumerated() {
                if isFrontmost {
                    event.post(tap: .cgAnnotatedSessionEventTap)
                } else {
                    event.postToPid(pid)
                }
                if index < sequence.count - 1 {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
            return true
        }
    }

    private static func pasteIntoTargetTextInput(
        _ transcript: String,
        savedMouseLocation: CGPoint?
    ) -> HoveredInputDeliveryResult {
        guard AXIsProcessTrusted() else { return .noInput }
        let location = savedMouseLocation ?? CGEvent(source: nil)?.location
        guard let location else { return .noInput }

        let systemWide = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(location.x),
            Float(location.y),
            &hitElement
        ) == .success,
        let hitElement else { return .noInput }

        let hitPID = pidOf(element: hitElement)
        guard let pid = hitPID, isExternalProcess(pid) else { return .noInput }
        let candidate = findEditableTextInput(from: hitElement)
            ?? focusedEditableTextInput(in: pid)
        guard let candidate, pidOf(element: candidate) == pid else { return .noInput }

        _ = focus(candidate)
        if tryDirectTextInsertion(candidate, text: transcript) { return .pasted }
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        return deliverToHoveredTarget(
            processIdentifier: pid,
            isFrontmost: isFrontmost,
            isFocused: getAttribute(candidate, kAXFocusedAttribute) as? Bool == true,
            postPaste: postCommandV
        ) ? .pasted : .blocked
    }

    private static func focusedEditableTextInput(in processIdentifier: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let focused = elementAttribute(kAXFocusedUIElementAttribute, of: application) else {
            return nil
        }
        return findEditableTextInput(from: focused)
    }

    private static func findEditableTextInput(from element: AXUIElement, maxDepth: Int = 8) -> AXUIElement? {
        if isEditableTextInput(element) { return element }
        if let editableAncestor = elementAttribute(kAXEditableAncestorAttribute, of: element),
           isEditableTextInput(editableAncestor) {
            return editableAncestor
        }

        var current = element
        for _ in 0..<maxDepth {
            guard let parent = elementAttribute(kAXParentAttribute, of: current) else { break }
            current = parent
            if isEditableTextInput(current) { return current }
        }
        return nil
    }

    private static func isEditableTextInput(_ element: AXUIElement) -> Bool {
        guard let role = getAttribute(element, kAXRoleAttribute) as? String else { return false }
        let subrole = getAttribute(element, kAXSubroleAttribute) as? String
        let enabled = getAttribute(element, kAXEnabledAttribute) as? Bool
        guard enabled != false,
              subrole != kAXSecureTextFieldSubrole as String,
              getAttribute(element, "AXIsReadOnly") as? Bool != true else {
            return false
        }
        if isEditableTextInput(role: role, subrole: subrole, isEnabled: enabled ?? true) {
            return true
        }
        return stringValue(getAttribute(element, kAXValueAttribute)) != nil
            && selectedRange(of: element) != nil
    }

    private static func tryDirectTextInsertion(_ element: AXUIElement, text: String) -> Bool {
        // Web inputs usually expose DOM attributes, and changing AXValue does not fire input events.
        // Use Cmd+V so Electron and browser frameworks receive a real paste event.
        let hasDOMIdentifier = getAttribute(element, "AXDOMIdentifier") != nil
        let hasDOMClassList = getAttribute(element, "AXDOMClassList") != nil
        if hasDOMIdentifier || hasDOMClassList {
            return false
        }

        // Native macOS inputs support direct insertion through the AX API.
        guard let current = stringValue(getAttribute(element, kAXValueAttribute)),
              let range = selectedRange(of: element) else {
            return false
        }

        // Treat a fully selected placeholder value as an empty input.
        let placeholderValue = stringValue(getAttribute(element, kAXPlaceholderValueAttribute))
        let actualCurrent: String
        if let placeholderValue,
           !placeholderValue.isEmpty,
           current == placeholderValue,
           range.location == 0,
           range.length == (current as NSString).length {
            // The selected placeholder is not actual content.
            actualCurrent = ""
        } else {
            actualCurrent = current
        }

        guard let expected = Self.replacingSelection(
                in: actualCurrent,
                location: min(range.location, (actualCurrent as NSString).length),
                length: min(range.length, (actualCurrent as NSString).length - range.location),
                with: text
              ) else {
            return false
        }

        guard AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            expected as CFString
        ) == .success else { return false }

        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline {
            let resultValue = stringValue(getAttribute(element, kAXValueAttribute))
            if resultValue == expected { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return stringValue(getAttribute(element, kAXValueAttribute)) == expected
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = getAttribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange(location: 0, length: 0)
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private static func stringValue(_ value: CFTypeRef?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSString { return value as String }
        if let value = value as? NSAttributedString { return value.string }
        return nil
    }

    private static func focus(_ element: AXUIElement) -> Bool {
        if getAttribute(element, kAXFocusedAttribute) as? Bool == true { return true }
        guard AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        ) == .success else { return false }

        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            if getAttribute(element, kAXFocusedAttribute) as? Bool == true { return true }
            Thread.sleep(forTimeInterval: 0.03)
        }
        return getAttribute(element, kAXFocusedAttribute) as? Bool == true
    }

    private static func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = getAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func getAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
            ? value
            : nil
    }

    private static func pidOf(element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    private static func isExternalProcess(_ processIdentifier: pid_t) -> Bool {
        processIdentifier > 0 && processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
}
