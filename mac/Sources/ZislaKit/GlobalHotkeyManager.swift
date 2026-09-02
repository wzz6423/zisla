import ApplicationServices
import Carbon.HIToolbox
import Foundation
import ZislaCore

public enum GlobalHotkeyRegistrationResult: Equatable, Sendable {
    case registered
    case inputMonitoringPermissionRequired
    case registrationFailed
}

/// Global hotkey wrapper: generic combinations use Carbon; combinations requiring left/right side
/// modifiers prefer a filtering event tap and fall back to a read-only tap.
/// The event tap is added to the main RunLoop, so its callbacks and register/unregister calls
/// are all serialized on the main thread.
public final class GlobalHotkeyManager: @unchecked Sendable {
    // CGEventFlags preserves device-specific bits that distinguish left and right physical modifier keys.
    private static let deviceModifierMasks: [(modifier: VoiceInputModifier, mask: UInt64)] = [
        (.leftControl, 0x0000_0000_0000_0001),
        (.leftShift, 0x0000_0000_0000_0002),
        (.rightShift, 0x0000_0000_0000_0004),
        (.leftCommand, 0x0000_0000_0000_0008),
        (.rightCommand, 0x0000_0000_0000_0010),
        (.leftOption, 0x0000_0000_0000_0020),
        (.rightOption, 0x0000_0000_0000_0040),
        (.rightControl, 0x0000_0000_0000_2000),
    ]

    private var hotKeyRef: EventHotKeyRef?
    fileprivate private(set) var registeredCarbonHotkeyID: UInt32?
    private var eventHandler: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    fileprivate var canSuppressSideSpecificEvents = false
    private var sideSpecificHotkey: VoiceInputHotkeyPreset?
    private var sideSpecificHotkeyIsPressed = false
    private var pressedModifierSides: Set<VoiceInputModifier> = []
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    public init() {}

    public static var hasInputMonitoringAccess: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    @MainActor
    public static func requestInputMonitoringAccess() -> Bool {
        let authorizationHost = WindowPlacement.authorizationPromptHost()
        defer {
            authorizationHost?.orderOut(nil)
            authorizationHost?.close()
        }
        return CGRequestListenEventAccess()
    }

    @discardableResult
    public func register(
        hotkey: VoiceInputHotkeyPreset,
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) -> GlobalHotkeyRegistrationResult {
        unregister()

        if hotkey.requiresInputMonitoring {
            guard Self.hasInputMonitoringAccess else {
                return .inputMonitoringPermissionRequired
            }
            return registerSideSpecific(
                hotkey: hotkey,
                onKeyDown: onKeyDown,
                onKeyUp: onKeyUp
            )
        }
        return registerCarbon(
            keyCode: hotkey.keyCode,
            modifiers: hotkey.carbonModifiers,
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp
        )
    }

    /// Registers a conventional combination hotkey that only needs a press action.
    @discardableResult
    public func register(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping () -> Void
    ) -> GlobalHotkeyRegistrationResult {
        unregister()
        return registerCarbon(
            keyCode: keyCode,
            modifiers: modifiers,
            onKeyDown: action,
            onKeyUp: {}
        )
    }

    public func unregister() {
        releaseSideSpecificHotkey()
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registeredCarbonHotkeyID = nil
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        canSuppressSideSpecificEvents = false
        sideSpecificHotkey = nil
        pressedModifierSides.removeAll()
        onKeyDown = nil
        onKeyUp = nil
    }

    deinit {
        unregister()
    }

    private func registerCarbon(
        keyCode: UInt32,
        modifiers: UInt32,
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) -> GlobalHotkeyRegistrationResult {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotkeyEventHandlerCallback,
            2,
            &specs,
            selfPtr,
            &eventHandler
        ) == noErr else {
            self.onKeyDown = nil
            self.onKeyUp = nil
            return .registrationFailed
        }

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4F524254),
            id: (keyCode << 16) | (modifiers & 0xFFFF)
        )
        guard RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        ) == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            self.onKeyDown = nil
            self.onKeyUp = nil
            return .registrationFailed
        }
        registeredCarbonHotkeyID = hotKeyID.id
        return .registered
    }

    private func registerSideSpecific(
        hotkey: VoiceInputHotkeyPreset,
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) -> GlobalHotkeyRegistrationResult {
        let eventMask = eventMask(for: [.flagsChanged, .keyDown, .keyUp])
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let filteringTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: globalHotkeyEventTapCallback,
            userInfo: selfPtr
        )
        let eventTap = filteringTap ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: globalHotkeyEventTapCallback,
            userInfo: selfPtr
        )
        guard let eventTap else {
            return .registrationFailed
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        eventTapRunLoopSource = runLoopSource
        canSuppressSideSpecificEvents = filteringTap != nil
        sideSpecificHotkey = hotkey
        pressedModifierSides = currentModifierSides()
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return .registered
    }

    fileprivate func handleSideSpecificEvent(
        type: CGEventType,
        keyCode: UInt32?,
        flags: CGEventFlags
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            releaseSideSpecificHotkey(resamplingModifierSides: true)
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }

        switch type {
        case .flagsChanged:
            guard let keyCode else { return false }
            pressedModifierSides = Self.modifierSides(
                afterFlagsChangedFor: keyCode,
                flags: flags,
                from: pressedModifierSides
            )
            guard let sideSpecificHotkey, sideSpecificHotkey.isModifierOnly else {
                return false
            }
            let shouldSuppress = Self.shouldSuppressModifierOnlyEvent(
                hotkey: sideSpecificHotkey,
                hotkeyIsPressed: sideSpecificHotkeyIsPressed,
                keyCode: keyCode,
                modifierSides: pressedModifierSides
            )
            if !sideSpecificHotkeyIsPressed,
               sideSpecificHotkey.matches(keyCode: keyCode, modifierSides: pressedModifierSides) {
                sideSpecificHotkeyIsPressed = true
                onKeyDown?()
                return true
            } else if sideSpecificHotkeyIsPressed,
                      keyCode == sideSpecificHotkey.keyCode,
                      !sideSpecificHotkey.matches(
                        keyCode: keyCode,
                        modifierSides: pressedModifierSides
                      ) {
                releaseSideSpecificHotkey()
            }
            return shouldSuppress
        case .keyDown:
            guard let sideSpecificHotkey,
                  let keyCode,
                  keyCode == sideSpecificHotkey.keyCode else {
                return false
            }
            // Keep auto-repeat events from leaking the registered key into the frontmost app.
            if sideSpecificHotkeyIsPressed { return true }
            pressedModifierSides = currentModifierSides()
            guard sideSpecificHotkey.matches(
                keyCode: keyCode,
                modifierSides: pressedModifierSides
            ) else {
                return false
            }
            sideSpecificHotkeyIsPressed = true
            onKeyDown?()
            return true
        case .keyUp:
            guard let sideSpecificHotkey,
                  sideSpecificHotkeyIsPressed,
                  keyCode == sideSpecificHotkey.keyCode
            else {
                return false
            }
            releaseSideSpecificHotkey()
            return true
        default:
            break
        }
        return false
    }

    static func shouldSuppressModifierOnlyEvent(
        hotkey: VoiceInputHotkeyPreset,
        hotkeyIsPressed: Bool,
        keyCode: UInt32,
        modifierSides: Set<VoiceInputModifier>
    ) -> Bool {
        guard hotkey.isModifierOnly else { return false }
        if hotkeyIsPressed {
            return keyCode == hotkey.keyCode
                && !hotkey.matches(keyCode: keyCode, modifierSides: modifierSides)
        }
        return hotkey.matches(keyCode: keyCode, modifierSides: modifierSides)
    }

    static func modifierSides(
        afterFlagsChangedFor keyCode: UInt32,
        flags: CGEventFlags,
        from pressedModifierSides: Set<VoiceInputModifier>
    ) -> Set<VoiceInputModifier> {
        let deviceModifierSides = Self.modifierSides(from: flags)
        if !deviceModifierSides.isEmpty {
            return deviceModifierSides
        }

        guard let modifier = VoiceInputModifier(keyCode: keyCode) else {
            return pressedModifierSides
        }

        let isModifierPressed: Bool = switch modifier {
        case .leftControl, .rightControl: flags.contains(.maskControl)
        case .leftOption, .rightOption: flags.contains(.maskAlternate)
        case .leftCommand, .rightCommand: flags.contains(.maskCommand)
        case .leftShift, .rightShift: flags.contains(.maskShift)
        }

        var modifierSides = pressedModifierSides
        if !isModifierPressed {
            modifierSides.remove(modifier)
        } else if modifierSides.contains(modifier),
                  modifierSides.contains(where: {
                      $0 != modifier && $0.carbonModifier == modifier.carbonModifier
                  }) {
            modifierSides.remove(modifier)
        } else {
            modifierSides.insert(modifier)
        }
        return modifierSides
    }

    static func modifierSides(from flags: CGEventFlags) -> Set<VoiceInputModifier> {
        Set(Self.deviceModifierMasks.compactMap { entry in
            flags.rawValue & entry.mask == 0 ? nil : entry.modifier
        })
    }

    private func currentModifierSides() -> Set<VoiceInputModifier> {
        let deviceModifierSides = Self.modifierSides(
            from: CGEventSource.flagsState(.combinedSessionState)
        )
        guard deviceModifierSides.isEmpty else {
            return deviceModifierSides
        }
        return Set(VoiceInputModifier.allCases.filter {
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0.keyCode))
        })
    }

    private func releaseSideSpecificHotkey(resamplingModifierSides: Bool = false) {
        if resamplingModifierSides {
            pressedModifierSides = currentModifierSides()
        }
        guard sideSpecificHotkeyIsPressed else { return }
        sideSpecificHotkeyIsPressed = false
        onKeyUp?()
    }

    private func eventMask(for eventTypes: [CGEventType]) -> CGEventMask {
        eventTypes.reduce(CGEventMask(0)) { mask, eventType in
            mask | (CGEventMask(1) << eventType.rawValue)
        }
    }
}

private func globalHotkeyEventHandlerCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    var hotkeyID = EventHotKeyID()
    guard GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    ) == noErr,
        hotkeyID.id == manager.registeredCarbonHotkeyID
    else { return OSStatus(eventNotHandledErr) }
    let kind = GetEventKind(event)
    MainActor.assumeIsolated {
        if kind == UInt32(kEventHotKeyPressed) {
            manager.onKeyDown?()
        } else if kind == UInt32(kEventHotKeyReleased) {
            manager.onKeyUp?()
        }
    }
    return noErr
}

private func globalHotkeyEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userData: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userData else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    let keyCode: UInt32? = switch type {
    case .flagsChanged, .keyDown, .keyUp:
        UInt32(event.getIntegerValueField(.keyboardEventKeycode))
    default:
        nil
    }
    let flags = event.flags
    let shouldSuppress = MainActor.assumeIsolated {
        manager.handleSideSpecificEvent(type: type, keyCode: keyCode, flags: flags)
    }
    return shouldSuppress && manager.canSuppressSideSpecificEvents
        ? nil
        : Unmanaged.passUnretained(event)
}
