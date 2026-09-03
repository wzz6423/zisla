import AppKit
import CoreGraphics
import Foundation

struct KeyboardEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case keyDown
        case keyUp
    }

    let kind: Kind
    let keyCode: UInt16
    let isRepeat: Bool
    let isShortcutModified: Bool

    init(
        kind: Kind,
        keyCode: UInt16,
        isRepeat: Bool,
        isShortcutModified: Bool = false
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.isRepeat = isRepeat
        self.isShortcutModified = isShortcutModified
    }
}

@MainActor
final class KeyboardMonitor {
    struct EventInterest: Equatable, Sendable {
        let keyboardPresses: Bool
        let keyboardReleases: Bool
        let pointerPresses: Bool
        let pointerReleases: Bool

        static let all = EventInterest(
            keyboardPresses: true,
            keyboardReleases: true,
            pointerPresses: true,
            pointerReleases: true
        )

        var eventTypes: [CGEventType] {
            var types: [CGEventType] = []
            if keyboardPresses { types.append(.keyDown) }
            if keyboardReleases { types.append(.keyUp) }
            // Modifier keys arrive only as flagsChanged, which represents both
            // transitions even when a future caller asks only for releases.
            if keyboardPresses || keyboardReleases { types.append(.flagsChanged) }
            if pointerPresses { types.append(.leftMouseDown) }
            if pointerReleases { types.append(.leftMouseUp) }
            if pointerPresses { types.append(.rightMouseDown) }
            if pointerReleases { types.append(.rightMouseUp) }
            if pointerPresses { types.append(.otherMouseDown) }
            if pointerReleases { types.append(.otherMouseUp) }
            return types
        }

        var eventMask: CGEventMask {
            var mask = eventTypes.reduce(CGEventMask(0)) { mask, type in
                mask | (CGEventMask(1) << type.rawValue)
            }
            // Top-row keys acting as brightness/media controls never emit keyDown/keyUp,
            // so the F1-F12 presses only show up through NX_SYSDEFINED.
            if observesAuxiliaryControls {
                mask |= CGEventMask(1) << AuxiliaryControlKey.eventTypeRawValue
            }
            return mask
        }

        /// NX_SYSDEFINED carries both transitions, so either keyboard interest opts in.
        var observesAuxiliaryControls: Bool { keyboardPresses || keyboardReleases }

        var isEmpty: Bool { eventTypes.isEmpty }
    }

    private struct RunState {
        let port: CFMachPort
        let source: CFRunLoopSource
    }

    private var runState: RunState?
    private var handler: (@MainActor (GlobalInputEvent) -> Void)?
    private var pressedModifierKeyCodes: Set<UInt16> = []

    static let observedEventTypes = EventInterest.all.eventTypes
    static let observedEventMask = EventInterest.all.eventMask

    @discardableResult
    func start(
        interest: EventInterest = .all,
        handler: @escaping @MainActor (GlobalInputEvent) -> Void
    ) -> Bool {
        stop()
        guard !interest.isEmpty else { return true }
        self.handler = handler

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: interest.eventMask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ), let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            self.handler = nil
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        runState = RunState(port: port, source: source)
        return true
    }

    func stop() {
        pressedModifierKeyCodes.removeAll()
        guard let runState else {
            handler = nil
            return
        }
        CGEvent.tapEnable(tap: runState.port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runState.source, .commonModes)
        CFMachPortInvalidate(runState.port)
        self.runState = nil
        handler = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        // NX_SYSDEFINED has no CGEventType case, so compare raw values instead of cases.
        let rawEventType = type.rawValue
        let wasDisabled = rawEventType == CGEventType.tapDisabledByTimeout.rawValue
            || rawEventType == CGEventType.tapDisabledByUserInput.rawValue
        let payload = decodedInputEvent(rawEventType: rawEventType, event: event)
        let modifierKeyCode = rawEventType == CGEventType.flagsChanged.rawValue
            ? UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            : nil

        precondition(Thread.isMainThread)
        MainActor.assumeIsolated {
            if wasDisabled {
                monitor.reenableTap()
            } else if let payload {
                monitor.receive(payload)
            } else if let modifierKeyCode {
                monitor.receiveModifierChange(
                    keyCode: modifierKeyCode,
                    flags: event.flags
                )
            }
        }
        return Unmanaged.passUnretained(event)
    }

    static func decodedInputEvent(rawEventType: UInt32, event: CGEvent) -> GlobalInputEvent? {
        if rawEventType == AuxiliaryControlKey.eventTypeRawValue {
            guard let systemEvent = NSEvent(cgEvent: event) else { return nil }
            return decodedSystemDefinedEvent(systemEvent)
        }
        guard let type = CGEventType(rawValue: rawEventType) else { return nil }
        return decodedInputEvent(type: type, event: event)
    }

    /// Only the aux-control buttons that map onto F1-F12 become keyboard events; every other
    /// system-defined event (caps lock, power, eject, aux mouse buttons…) is left alone.
    static func decodedSystemDefinedEvent(_ event: NSEvent) -> GlobalInputEvent? {
        guard event.type == .systemDefined else { return nil }
        guard let keyboardEvent = AuxiliaryControlKey.keyboardEvent(
            subtype: event.subtype.rawValue,
            data1: event.data1,
            isShortcutModified: event.modifierFlags.contains(.command)
                || event.modifierFlags.contains(.control)
        ) else { return nil }
        return .keyboard(keyboardEvent)
    }

    static func decodedInputEvent(type: CGEventType, event: CGEvent) -> GlobalInputEvent? {
        switch type {
        case .keyDown, .keyUp:
            let keyboardEvent = KeyboardEvent(
                kind: type == .keyDown ? .keyDown : .keyUp,
                keyCode: AuxiliaryControlKey.standardFunctionKeyCode(
                    for: UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                ),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                isShortcutModified: event.flags.contains(.maskCommand)
                    || event.flags.contains(.maskControl)
            )
            return .keyboard(keyboardEvent)
        case .leftMouseDown, .leftMouseUp:
            return .pointer(PointerEvent(
                phase: type == .leftMouseDown ? .press : .release,
                button: .primary
            ))
        case .rightMouseDown, .rightMouseUp:
            return .pointer(PointerEvent(
                phase: type == .rightMouseDown ? .press : .release,
                button: .secondary
            ))
        case .otherMouseDown, .otherMouseUp:
            return .pointer(PointerEvent(
                phase: type == .otherMouseDown ? .press : .release,
                button: PointerButton(
                    mouseButtonNumber: event.getIntegerValueField(.mouseEventButtonNumber)
                )
            ))
        default:
            return nil
        }
    }

    private func reenableTap() {
        pressedModifierKeyCodes.removeAll()
        if let port = runState?.port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    private func receive(_ payload: GlobalInputEvent) {
        guard let handler else { return }
        handler(payload)
    }

    private static let deviceModifierMasks: [(keyCode: UInt16, mask: UInt64)] = [
        (59, 0x0000_0000_0000_0001), // left control
        (56, 0x0000_0000_0000_0002), // left shift
        (60, 0x0000_0000_0000_0004), // right shift
        (55, 0x0000_0000_0000_0008), // left command
        (54, 0x0000_0000_0000_0010), // right command
        (58, 0x0000_0000_0000_0020), // left option
        (61, 0x0000_0000_0000_0040), // right option
        (62, 0x0000_0000_0000_2000), // right control
    ]

    private static let allDeviceModifierMask = deviceModifierMasks.reduce(UInt64(0)) {
        $0 | $1.mask
    }

    private func receiveModifierChange(keyCode: UInt16, flags: CGEventFlags) {
        let isDown = Self.modifierIsDown(
            keyCode: keyCode,
            flags: flags,
            pressedModifierKeyCodes: pressedModifierKeyCodes
        )
        let wasDown = pressedModifierKeyCodes.contains(keyCode)
        guard wasDown != isDown else { return }

        if isDown {
            pressedModifierKeyCodes.insert(keyCode)
        } else {
            pressedModifierKeyCodes.remove(keyCode)
        }
        let kind: KeyboardEvent.Kind = isDown ? .keyDown : .keyUp
        receive(.keyboard(KeyboardEvent(kind: kind, keyCode: keyCode, isRepeat: false)))
    }

    static func modifierIsDown(
        keyCode: UInt16,
        flags: CGEventFlags,
        pressedModifierKeyCodes: Set<UInt16>
    ) -> Bool {
        let rawFlags = flags.rawValue
        if let physicalMask = Self.deviceModifierMasks.first(where: { $0.keyCode == keyCode })?.mask,
           rawFlags & Self.allDeviceModifierMask != 0 {
            return rawFlags & physicalMask != 0
        }

        if let genericIsDown = Self.genericModifierIsDown(keyCode: keyCode, flags: flags) {
            // Some event sources omit the device-specific side bits. Modifier events still
            // alternate press/release, so use the monitor's own state to preserve right/left side.
            return genericIsDown && !pressedModifierKeyCodes.contains(keyCode)
        }

        return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
    }

    private static func genericModifierIsDown(
        keyCode: UInt16,
        flags: CGEventFlags
    ) -> Bool? {
        switch keyCode {
        case 55, 54: flags.contains(.maskCommand)
        case 56, 60: flags.contains(.maskShift)
        case 58, 61: flags.contains(.maskAlternate)
        case 59, 62: flags.contains(.maskControl)
        default: nil
        }
    }

    isolated deinit {
        guard let runState else { return }
        CGEvent.tapEnable(tap: runState.port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runState.source, .commonModes)
        CFMachPortInvalidate(runState.port)
    }
}

extension KeyboardMonitor {
    /// Decodes the auxiliary-control buttons the HID system reports as NX_SYSDEFINED events
    /// (see `IOKit/hidsystem/IOLLEvent.h` and `ev_keymap.h`). The top row emits these instead
    /// of keyDown/keyUp whenever the keys behave as brightness/media controls.
    enum AuxiliaryControlKey {
        /// NX_SYSDEFINED. `CGEventType` declares no case for it.
        static let eventTypeRawValue: UInt32 = 14
        /// NX_SUBTYPE_AUX_CONTROL_BUTTONS
        static let subtypeRawValue: Int16 = 8

        private static let keyDownState = 0x0A // NX_KEYDOWN
        private static let keyUpState = 0x0B // NX_KEYUP

        /// NX_KEYTYPE_* codes whose physical position on the top row is unambiguous, mapped to
        /// the F1-F12 virtual key codes the layout and the stats already use. Mission Control,
        /// Spotlight, Dictation and Do Not Disturb have no NX_KEYTYPE_* code, so F3 is counted
        /// only while the row acts as standard function keys.
        private static let functionKeyCodes: [Int: UInt16] = [
            3: 122, // BRIGHTNESS_DOWN -> F1
            2: 120, // BRIGHTNESS_UP -> F2
            13: 118, // LAUNCH_PANEL -> F4
            22: 96, // ILLUMINATION_DOWN -> F5
            21: 97, // ILLUMINATION_UP -> F6
            20: 98, // REWIND -> F7
            18: 98, // PREVIOUS -> F7
            16: 100, // PLAY -> F8
            19: 101, // FAST -> F9
            17: 101, // NEXT -> F9
            7: 109, // MUTE -> F10
            1: 103, // SOUND_DOWN -> F11
            0: 111, // SOUND_UP -> F12
        ]

        /// Some modern top-row controls arrive as ordinary key events with a private virtual
        /// key code instead of an NX_SYSDEFINED event.
        private static let standardFunctionKeyCodeAliases: [UInt16: UInt16] = [
            129: 118, // Spotlight / older keyboards -> F4
            131: 118, // App Exposé / older keyboards -> F4
            160: 99, // Mission Control -> F3
            177: 118, // Spotlight -> F4
            176: 96, // Dictation -> F5
            178: 97, // Focus / Do Not Disturb -> F6
            179: 98, // Previous track -> F7
            180: 101, // Next track -> F9
        ]

        static func standardFunctionKeyCode(for keyCode: UInt16) -> UInt16 {
            standardFunctionKeyCodeAliases[keyCode] ?? keyCode
        }

        /// `data1` packs the NX_KEYTYPE_* code in the high half, and the key state plus the
        /// autorepeat bit in the low half.
        static func keyboardEvent(
            subtype: Int16,
            data1: Int,
            isShortcutModified: Bool
        ) -> KeyboardEvent? {
            guard subtype == subtypeRawValue else { return nil }
            guard let keyCode = functionKeyCodes[(data1 & 0xFFFF_0000) >> 16] else { return nil }

            let keyFlags = data1 & 0x0000_FFFF
            let kind: KeyboardEvent.Kind? = switch (keyFlags & 0xFF00) >> 8 {
            case keyDownState: .keyDown
            case keyUpState: .keyUp
            default: nil
            }
            guard let kind else { return nil }

            return KeyboardEvent(
                kind: kind,
                keyCode: keyCode,
                isRepeat: keyFlags & 0x1 != 0,
                isShortcutModified: isShortcutModified
            )
        }
    }
}
