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
    func carbonHotkeysPollTheKeyStateWhileOneOfOurOwnMenusTracks() throws {
        let source = try String(contentsOf: globalHotkeyManagerSourceURL, encoding: .utf8)
        let registration = try sourceSlice(
            in: source,
            from: "private func registerCarbon(",
            to: "private func registerSideSpecific("
        )

        #expect(registration.contains("startObservingMenuTracking()"))
        #expect(registration.contains("NSMenu.didBeginTrackingNotification"))
        #expect(registration.contains("NSMenu.didEndTrackingNotification"))
        // Event tracking mode only runs timers registered in the common modes.
        #expect(registration.contains("RunLoop.main.add(timer, forMode: .common)"))
        #expect(registration.contains("CGEventSource.keyState("))
        // The press the tracking loop replays after the menu closes must not fire the action twice.
        #expect(registration.contains("menuTrackingPressConsumedAt"))
        // Esc and other bare keys belong to the menu itself while it tracks.
        #expect(registration.contains("guard let carbonHotkey, carbonHotkey.modifiers != 0 else { return }"))
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
    func sideSpecificHotkeysPreferFilteringButFallBackToListening() throws {
        let source = try String(contentsOf: globalHotkeyManagerSourceURL, encoding: .utf8)
        let registration = try sourceSlice(
            in: source,
            from: "private func registerSideSpecific(",
            to: "fileprivate func handleSideSpecificEvent("
        )
        let callback = try sourceSlice(
            in: source,
            from: "private func globalHotkeyEventTapCallback(",
            to: source.endIndex
        )

        #expect(registration.contains("let filteringTap = CGEvent.tapCreate("))
        #expect(registration.contains("options: .defaultTap"))
        #expect(registration.contains("let eventTap = filteringTap ?? CGEvent.tapCreate("))
        #expect(registration.contains("options: .listenOnly"))
        #expect(registration.contains("canSuppressSideSpecificEvents = filteringTap != nil"))
        #expect(callback.contains("let shouldSuppress = MainActor.assumeIsolated"))
        #expect(callback.contains("return shouldSuppress && manager.canSuppressSideSpecificEvents"))
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

    @Test
    func sideSpecificTapDisableReleasesAStuckPressWithoutRequiringHostPermission() throws {
        let source = try String(contentsOf: globalHotkeyManagerSourceURL, encoding: .utf8)
        let handler = try sourceSlice(
            in: source,
            from: "fileprivate func handleSideSpecificEvent(",
            to: "static func shouldSuppressModifierOnlyEvent("
        )

        #expect(handler.contains("releaseSideSpecificHotkey(resamplingModifierSides: true)"))
        #expect(handler.contains("keyCode == sideSpecificHotkey.keyCode"))
    }

    @Test
    func sideSpecificHotkeySuppressesRepeatedKeyDownEvents() throws {
        let source = try String(contentsOf: globalHotkeyManagerSourceURL, encoding: .utf8)
        let handler = try sourceSlice(
            in: source,
            from: "fileprivate func handleSideSpecificEvent(",
            to: "static func shouldSuppressModifierOnlyEvent("
        )

        #expect(handler.contains("if sideSpecificHotkeyIsPressed { return true }"))
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

    private func sourceSlice(
        in source: String,
        from start: String,
        to end: String.Index
    ) throws -> Substring {
        let startRange = try #require(source.range(of: start))
        return source[startRange.lowerBound..<end]
    }

    private func sourceSlice(
        in source: String,
        from start: String,
        to end: String
    ) throws -> Substring {
        let startRange = try #require(source.range(of: start))
        let endRange = try #require(source[startRange.upperBound...].range(of: end))
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private var globalHotkeyManagerSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ZislaKit/GlobalHotkeyManager.swift")
    }
}
