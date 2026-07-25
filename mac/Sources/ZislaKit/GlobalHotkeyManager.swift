import ApplicationServices
import Carbon.HIToolbox
import Foundation
import ZislaCore

public enum GlobalHotkeyRegistrationResult: Equatable, Sendable {
    case registered
    case inputMonitoringPermissionRequired
    case registrationFailed
}

/// 全局快捷键封装：旧通用组合使用 Carbon，带左右侧要求的组合使用只读事件监听。
/// 事件 tap 被添加到主 RunLoop，因此其回调与注册/注销操作都在主线程串行执行。
public final class GlobalHotkeyManager: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
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

    public func unregister() {
        if sideSpecificHotkeyIsPressed {
            sideSpecificHotkeyIsPressed = false
            onKeyUp?()
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }
        eventTap = nil
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

        let hotKeyID = EventHotKeyID(signature: OSType(0x4F524254), id: 1)
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
        return .registered
    }

    private func registerSideSpecific(
        hotkey: VoiceInputHotkeyPreset,
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) -> GlobalHotkeyRegistrationResult {
        let eventMask = eventMask(for: [.flagsChanged, .keyDown, .keyUp])
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: globalHotkeyEventTapCallback,
            userInfo: selfPtr
        ) else {
            return .registrationFailed
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        eventTapRunLoopSource = runLoopSource
        sideSpecificHotkey = hotkey
        pressedModifierSides = currentModifierSides()
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        return .registered
    }

    fileprivate func handleSideSpecificEvent(type: CGEventType, keyCode: UInt32?) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        switch type {
        case .flagsChanged:
            pressedModifierSides = currentModifierSides()
            guard let sideSpecificHotkey, sideSpecificHotkey.isModifierOnly, let keyCode else {
                return
            }
            if !sideSpecificHotkeyIsPressed,
               sideSpecificHotkey.matches(keyCode: keyCode, modifierSides: pressedModifierSides) {
                sideSpecificHotkeyIsPressed = true
                onKeyDown?()
            } else if sideSpecificHotkeyIsPressed,
                      keyCode == sideSpecificHotkey.keyCode,
                      !sideSpecificHotkey.matches(
                        keyCode: keyCode,
                        modifierSides: pressedModifierSides
                      ) {
                sideSpecificHotkeyIsPressed = false
                onKeyUp?()
            }
        case .keyDown:
            guard let sideSpecificHotkey, !sideSpecificHotkeyIsPressed, let keyCode else { return }
            pressedModifierSides = currentModifierSides()
            guard sideSpecificHotkey.matches(
                keyCode: keyCode,
                modifierSides: pressedModifierSides
            ) else {
                return
            }
            sideSpecificHotkeyIsPressed = true
            onKeyDown?()
        case .keyUp:
            guard let sideSpecificHotkey,
                  sideSpecificHotkeyIsPressed,
                  keyCode == sideSpecificHotkey.keyCode
            else {
                return
            }
            sideSpecificHotkeyIsPressed = false
            onKeyUp?()
        default:
            break
        }
    }

    private func currentModifierSides() -> Set<VoiceInputModifier> {
        Set(VoiceInputModifier.allCases.filter {
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0.keyCode))
        })
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
    guard let event, let userData else { return noErr }
    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
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
    MainActor.assumeIsolated {
        manager.handleSideSpecificEvent(type: type, keyCode: keyCode)
    }
    return Unmanaged.passUnretained(event)
}
