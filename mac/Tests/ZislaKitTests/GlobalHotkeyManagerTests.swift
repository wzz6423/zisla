import AppKit
import Carbon.HIToolbox
import Testing

@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct GlobalHotkeyManagerTests {
    @Test
    func recordingAndEditorSuspensionComposeAndResumeTheLatestRegistration() throws {
        _ = NSApplication.shared
        let manager = GlobalHotkeyManager()
        let flags = UInt32(controlKey | optionKey | cmdKey | shiftKey)
        var count = 0
        var releases = 0
        #expect(manager.register(
            hotkey: .init(keyCode: UInt32(kVK_F17), carbonModifiers: flags, keyDisplayName: "F17"),
            onKeyDown: { count += 1 }, onKeyUp: { releases += 1 }
        ) == .registered)
        defer { manager.unregister() }
        try sendHotkeyPressed(keyCode: UInt32(kVK_F17), modifiers: flags)
        let owner = GlobalHotkeyManager.beginRecording()
        #expect(manager.isSuspended)
        #expect(!manager.hasActiveRegistration)
        #expect(releases == 1)
        let nested = GlobalHotkeyManager.beginRecording()
        manager.setSuspended(true, reason: "editor")
        #expect(manager.register(keyCode: UInt32(kVK_F18), modifiers: flags, action: { count += 10 }) == .registered)
        GlobalHotkeyManager.endRecording(owner)
        GlobalHotkeyManager.endRecording(nested)
        #expect(manager.isSuspended)
        #expect(count == 1)
        manager.setSuspended(false, reason: "editor")
        #expect(!manager.isSuspended)
        #expect(manager.hasActiveRegistration)
        try sendHotkeyPressed(keyCode: UInt32(kVK_F18), modifiers: flags)
        #expect(count == 11)
    }

    @Test
    func carbonHandlersForwardEventsToTheMatchingManager() throws {
        _ = NSApplication.shared
        let firstManager = GlobalHotkeyManager()
        let secondManager = GlobalHotkeyManager()
        let modifiers = UInt32(controlKey | optionKey | cmdKey | shiftKey)
        let firstKeyCode = UInt32(kVK_F17)
        let secondKeyCode = UInt32(kVK_F18)
        var firstPressCount = 0
        var secondPressCount = 0

        let firstResult = firstManager.register(
            keyCode: firstKeyCode,
            modifiers: modifiers,
            action: { firstPressCount += 1 }
        )
        let secondResult = secondManager.register(
            keyCode: secondKeyCode,
            modifiers: modifiers,
            action: { secondPressCount += 1 }
        )
        defer {
            secondManager.unregister()
            firstManager.unregister()
        }

        #expect(firstResult == .registered)
        #expect(secondResult == .registered)
        guard firstResult == .registered, secondResult == .registered else { return }

        try sendHotkeyPressed(keyCode: firstKeyCode, modifiers: modifiers)
        #expect(firstPressCount == 1)
        #expect(secondPressCount == 0)

        try sendHotkeyPressed(keyCode: secondKeyCode, modifiers: modifiers)
        #expect(firstPressCount == 1)
        #expect(secondPressCount == 1)
    }

    @Test
    func carbonModifiersIgnoreFlagsThatAreNotPartOfACombination() {
        #expect(GlobalHotkeyManager.carbonModifiers(from: []) == 0)
        #expect(GlobalHotkeyManager.carbonModifiers(from: .control) == UInt32(controlKey))
        #expect(
            GlobalHotkeyManager.carbonModifiers(from: [.command, .shift, .option, .control])
                == UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        // Caps lock, Fn and the numeric pad ride along in NSEvent.modifierFlags; letting them through
        // would make the polled comparison miss the registered combination.
        #expect(
            GlobalHotkeyManager.carbonModifiers(from: [.control, .capsLock, .function, .numericPad])
                == UInt32(controlKey)
        )
    }

    @Test
    func flagsChangedTracksRightOptionWithoutGlobalKeyState() {
        let rightOption = VoiceInputModifier.rightOption
        var modifierSides = GlobalHotkeyManager.modifierSides(
            afterFlagsChangedFor: rightOption.keyCode,
            flags: .maskAlternate,
            from: []
        )
        #expect(modifierSides == [rightOption])

        modifierSides = GlobalHotkeyManager.modifierSides(
            afterFlagsChangedFor: rightOption.keyCode,
            flags: [],
            from: modifierSides
        )
        #expect(modifierSides.isEmpty)

        modifierSides = GlobalHotkeyManager.modifierSides(
            afterFlagsChangedFor: rightOption.keyCode,
            flags: .maskAlternate,
            from: [.leftOption]
        )
        #expect(modifierSides == [.leftOption, rightOption])

        modifierSides = GlobalHotkeyManager.modifierSides(
            afterFlagsChangedFor: rightOption.keyCode,
            flags: .maskAlternate,
            from: modifierSides
        )
        #expect(modifierSides == [.leftOption])
    }

    @Test
    func flagsChangedUsesPhysicalModifierBitsWhenAvailable() {
        let rightOption = VoiceInputModifier.rightOption
        let rightOptionFlags = CGEventFlags(rawValue: 0x40 | 0x0008_0000)

        #expect(
            GlobalHotkeyManager.modifierSides(from: rightOptionFlags) == [rightOption]
        )
        #expect(
            GlobalHotkeyManager.modifierSides(
                afterFlagsChangedFor: rightOption.keyCode,
                flags: rightOptionFlags,
                from: [.leftOption]
            ) == [rightOption]
        )
        #expect(
            GlobalHotkeyManager.modifierSides(
                afterFlagsChangedFor: rightOption.keyCode,
                flags: [],
                from: [rightOption]
            ).isEmpty
        )
    }

    @Test
    func modifierOnlyHotkeySuppressesOnlyItsMatchedPressAndRelease() {
        let rightOption = VoiceInputModifier.rightOption
        let hotkey = VoiceInputHotkeyPreset(
            keyCode: rightOption.keyCode,
            carbonModifiers: rightOption.carbonModifier,
            keyDisplayName: "R⌥",
            modifierSides: [rightOption]
        )

        #expect(GlobalHotkeyManager.shouldSuppressModifierOnlyEvent(
            hotkey: hotkey,
            hotkeyIsPressed: false,
            keyCode: rightOption.keyCode,
            modifierSides: [rightOption]
        ))
        #expect(GlobalHotkeyManager.shouldSuppressModifierOnlyEvent(
            hotkey: hotkey,
            hotkeyIsPressed: true,
            keyCode: rightOption.keyCode,
            modifierSides: []
        ))
        #expect(!GlobalHotkeyManager.shouldSuppressModifierOnlyEvent(
            hotkey: hotkey,
            hotkeyIsPressed: false,
            keyCode: VoiceInputModifier.leftOption.keyCode,
            modifierSides: [.leftOption]
        ))
        #expect(!GlobalHotkeyManager.shouldSuppressModifierOnlyEvent(
            hotkey: hotkey,
            hotkeyIsPressed: false,
            keyCode: rightOption.keyCode,
            modifierSides: [.leftOption, .rightOption]
        ))
    }

    private func sendHotkeyPressed(keyCode: UInt32, modifiers: UInt32) throws {
        var createdEvent: EventRef?
        let createResult = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            UInt32(kEventHotKeyPressed),
            0,
            0,
            &createdEvent
        )
        #expect(createResult == noErr)
        let event = try #require(createdEvent)
        defer { ReleaseEvent(event) }

        var hotkeyID = EventHotKeyID(
            signature: OSType(0x4F524254),
            id: (keyCode << 16) | (modifiers & 0xFFFF)
        )
        let parameterResult = withUnsafePointer(to: &hotkeyID) { pointer in
            SetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                MemoryLayout<EventHotKeyID>.size,
                pointer
            )
        }
        #expect(parameterResult == noErr)
        guard parameterResult == noErr else { return }

        #expect(SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr)
    }
}
