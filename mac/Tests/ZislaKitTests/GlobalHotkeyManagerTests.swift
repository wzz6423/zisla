import AppKit
import Carbon.HIToolbox
import Testing

@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct GlobalHotkeyManagerTests {
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
