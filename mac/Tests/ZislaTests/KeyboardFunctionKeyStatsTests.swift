import AppKit
import CoreGraphics
import Testing

@testable import KeyboardKit

/// F1-F12 only reach the usage-frequency stats if the tap also listens for the NX_SYSDEFINED
/// auxiliary-control events the top row emits while acting as brightness/media controls.
struct KeyboardFunctionKeyStatsTests {
    private static let systemDefinedMaskBit =
        CGEventMask(1) << KeyboardMonitor.AuxiliaryControlKey.eventTypeRawValue

    /// (NX_KEYTYPE_*, virtual key code) pairs that identify a top-row key unambiguously.
    private static let auxiliaryControlMappings: [(nxKeyType: Int, keyCode: UInt16)] = [
        (3, 122), // BRIGHTNESS_DOWN -> F1
        (2, 120), // BRIGHTNESS_UP -> F2
        (13, 118), // LAUNCH_PANEL -> F4
        (22, 96), // ILLUMINATION_DOWN -> F5
        (21, 97), // ILLUMINATION_UP -> F6
        (20, 98), // REWIND -> F7
        (18, 98), // PREVIOUS -> F7
        (16, 100), // PLAY -> F8
        (19, 101), // FAST -> F9
        (17, 101), // NEXT -> F9
        (7, 109), // MUTE -> F10
        (1, 103), // SOUND_DOWN -> F11
        (0, 111), // SOUND_UP -> F12
    ]

    private static func auxiliaryControlData1(
        nxKeyType: Int,
        isDown: Bool,
        isRepeat: Bool = false
    ) -> Int {
        (nxKeyType << 16) | ((isDown ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0)
    }

    private typealias Deduplicator = KeyboardMonitor.FunctionKeyDeduplicator

    /// F5 is the key that actually collides in the field: an Apple keyboard reports it both as
    /// NX_KEYTYPE_ILLUMINATION_DOWN and as the private virtual key code 176 (Dictation).
    private static let f5KeyCode: UInt16 = 96
    private static let illuminationDownKeyType = 22
    private static let dictationVirtualKey: UInt16 = 176

    @MainActor
    private static func auxiliaryKeyboardEvent(
        nxKeyType: Int,
        isDown: Bool,
        isRepeat: Bool = false
    ) -> KeyboardEvent? {
        KeyboardMonitor.AuxiliaryControlKey.keyboardEvent(
            subtype: KeyboardMonitor.AuxiliaryControlKey.subtypeRawValue,
            data1: auxiliaryControlData1(nxKeyType: nxKeyType, isDown: isDown, isRepeat: isRepeat),
            isShortcutModified: false
        )
    }

    @MainActor
    private static func standardKeyboardEvent(
        virtualKey: UInt16,
        isDown: Bool,
        isRepeat: Bool = false
    ) -> KeyboardEvent? {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(virtualKey),
            keyDown: isDown
        ) else { return nil }
        event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
        guard case let .keyboard(keyboardEvent)? = KeyboardMonitor.decodedInputEvent(
            rawEventType: isDown ? CGEventType.keyDown.rawValue : CGEventType.keyUp.rawValue,
            event: event
        ) else { return nil }
        return keyboardEvent
    }

    /// Mirrors `KeyboardMonitor.receive`: an event reaches the handler unless it is a duplicate.
    @MainActor
    private static func forwarded(
        _ stream: [(KeyboardEvent, Deduplicator.Source, TimeInterval)]
    ) -> [KeyboardEvent] {
        var deduplicator = Deduplicator()
        return stream.compactMap { event, source, timestamp in
            deduplicator.isDuplicate(event, from: source, at: timestamp) ? nil : event
        }
    }

    /// `#expect` expands into a closure that cannot call a mutating member, so the decision is
    /// taken here and only the resulting flag is asserted.
    @MainActor
    private static func expect(
        duplicate isExpected: Bool,
        _ event: KeyboardEvent,
        from source: Deduplicator.Source,
        at timestamp: TimeInterval,
        in deduplicator: inout Deduplicator,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let isDuplicate = deduplicator.isDuplicate(event, from: source, at: timestamp)
        #expect(isDuplicate == isExpected, sourceLocation: sourceLocation)
    }

    @Test @MainActor
    func keyboardInterestTapsSystemDefinedEvents() {
        let presses = KeyboardMonitor.EventInterest(
            keyboardPresses: true,
            keyboardReleases: false,
            pointerPresses: false,
            pointerReleases: false
        )
        let releases = KeyboardMonitor.EventInterest(
            keyboardPresses: false,
            keyboardReleases: true,
            pointerPresses: false,
            pointerReleases: false
        )
        let pointerOnly = KeyboardMonitor.EventInterest(
            keyboardPresses: false,
            keyboardReleases: false,
            pointerPresses: true,
            pointerReleases: true
        )
        let empty = KeyboardMonitor.EventInterest(
            keyboardPresses: false,
            keyboardReleases: false,
            pointerPresses: false,
            pointerReleases: false
        )

        #expect(presses.observesAuxiliaryControls)
        #expect(releases.observesAuxiliaryControls)
        #expect(!pointerOnly.observesAuxiliaryControls)
        #expect(presses.eventMask & Self.systemDefinedMaskBit != 0)
        #expect(releases.eventMask & Self.systemDefinedMaskBit != 0)
        #expect(pointerOnly.eventMask & Self.systemDefinedMaskBit == 0)
        #expect(KeyboardMonitor.observedEventMask & Self.systemDefinedMaskBit != 0)
        // The extra bit must not turn an idle interest into a live tap.
        #expect(empty.isEmpty)
        #expect(!presses.isEmpty)
        // NX_SYSDEFINED has no CGEventType case, so it stays out of the type list.
        #expect(presses.eventTypes == [.keyDown, .flagsChanged])
    }

    @Test @MainActor
    func auxiliaryControlsDecodeToFunctionKeyDowns() throws {
        for (nxKeyType, keyCode) in Self.auxiliaryControlMappings {
            let event = try #require(
                KeyboardMonitor.AuxiliaryControlKey.keyboardEvent(
                    subtype: KeyboardMonitor.AuxiliaryControlKey.subtypeRawValue,
                    data1: Self.auxiliaryControlData1(nxKeyType: nxKeyType, isDown: true),
                    isShortcutModified: false
                ),
                "NX_KEYTYPE \(nxKeyType) should decode"
            )
            #expect(event.kind == .keyDown)
            #expect(event.keyCode == keyCode)
            #expect(!event.isRepeat)
            // Function keys must not inflate the character totals.
            #expect(!TypingCharacterKeyFilter.countsAsCharacter(
                keyCode: event.keyCode,
                isShortcutModified: false
            ))
        }

        let expectedKeyCodes: Set<UInt16> = [122, 120, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        #expect(Set(Self.auxiliaryControlMappings.map { $0.keyCode }) == expectedKeyCodes)
    }

    @Test @MainActor
    func auxiliaryControlsReportBothTransitionsAndRepeats() throws {
        let mute = 7
        let down = try #require(KeyboardMonitor.AuxiliaryControlKey.keyboardEvent(
            subtype: KeyboardMonitor.AuxiliaryControlKey.subtypeRawValue,
            data1: Self.auxiliaryControlData1(nxKeyType: mute, isDown: true),
            isShortcutModified: false
        ))
        let up = try #require(KeyboardMonitor.AuxiliaryControlKey.keyboardEvent(
            subtype: KeyboardMonitor.AuxiliaryControlKey.subtypeRawValue,
            data1: Self.auxiliaryControlData1(nxKeyType: mute, isDown: false),
            isShortcutModified: false
        ))
        // Holding a volume/brightness key repeats; stats only count non-repeat key downs.
        let repeated = try #require(KeyboardMonitor.AuxiliaryControlKey.keyboardEvent(
            subtype: KeyboardMonitor.AuxiliaryControlKey.subtypeRawValue,
            data1: Self.auxiliaryControlData1(nxKeyType: mute, isDown: true, isRepeat: true),
            isShortcutModified: false
        ))

        #expect(down.kind == .keyDown)
        #expect(!down.isRepeat)
        #expect(up.kind == .keyUp)
        #expect(up.keyCode == 109)
        #expect(repeated.kind == .keyDown)
        #expect(repeated.isRepeat)
    }

    @Test @MainActor
    func unsupportedSystemDefinedEventsAreIgnored() {
        let auxSubtype = KeyboardMonitor.AuxiliaryControlKey.subtypeRawValue
        // Caps lock, help, power, num lock, eject, contrast, video mirror, illumination toggle.
        for nxKeyType in [4, 5, 6, 10, 11, 12, 14, 15, 23, 25] {
            #expect(KeyboardMonitor.AuxiliaryControlKey.keyboardEvent(
                subtype: auxSubtype,
                data1: Self.auxiliaryControlData1(nxKeyType: nxKeyType, isDown: true),
                isShortcutModified: false
            ) == nil, "NX_KEYTYPE \(nxKeyType) is not a top-row function key")
        }

        // NX_SUBTYPE_POWER_KEY and NX_SUBTYPE_AUX_MOUSE_BUTTONS must pass through untouched.
        for subtype in [Int16(1), Int16(7), Int16(10)] {
            #expect(KeyboardMonitor.AuxiliaryControlKey.keyboardEvent(
                subtype: subtype,
                data1: Self.auxiliaryControlData1(nxKeyType: 7, isDown: true),
                isShortcutModified: false
            ) == nil, "subtype \(subtype) is not an aux-control button")
        }

        // Neither NX_KEYDOWN nor NX_KEYUP in the state byte.
        #expect(KeyboardMonitor.AuxiliaryControlKey.keyboardEvent(
            subtype: auxSubtype,
            data1: (7 << 16) | (0x0C << 8),
            isShortcutModified: false
        ) == nil)
    }

    @Test @MainActor
    func systemDefinedNSEventsDecodeThroughTheMonitor() throws {
        let brightnessUp = try #require(NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: KeyboardMonitor.AuxiliaryControlKey.subtypeRawValue,
            data1: Self.auxiliaryControlData1(nxKeyType: 2, isDown: true),
            data2: -1
        ))
        let decoded = KeyboardMonitor.decodedSystemDefinedEvent(brightnessUp)
        guard case let .keyboard(keyboardEvent)? = decoded else {
            Issue.record("brightness up should decode to a keyboard event")
            return
        }
        #expect(keyboardEvent.kind == .keyDown)
        #expect(keyboardEvent.keyCode == 120)

        let applicationDefined = try #require(NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: KeyboardMonitor.AuxiliaryControlKey.subtypeRawValue,
            data1: Self.auxiliaryControlData1(nxKeyType: 2, isDown: true),
            data2: -1
        ))
        #expect(KeyboardMonitor.decodedSystemDefinedEvent(applicationDefined) == nil)
    }

    @Test @MainActor
    func rawEventTypeDispatchKeepsOrdinaryFunctionKeys() throws {
        let f5Down = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 96, keyDown: true))
        let decoded = KeyboardMonitor.decodedInputEvent(
            rawEventType: CGEventType.keyDown.rawValue,
            event: f5Down
        )
        guard case let .keyboard(keyboardEvent)? = decoded else {
            Issue.record("F5 keyDown should decode to a keyboard event")
            return
        }
        #expect(keyboardEvent.kind == .keyDown)
        #expect(keyboardEvent.keyCode == 96)

        let f5Up = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 96, keyDown: false))
        guard case let .keyboard(release)? = KeyboardMonitor.decodedInputEvent(
            rawEventType: CGEventType.keyUp.rawValue,
            event: f5Up
        ) else {
            Issue.record("F5 keyUp should stay available for release sounds")
            return
        }
        #expect(release.kind == .keyUp)

        // mouseMoved is neither tapped nor decodable.
        #expect(KeyboardMonitor.decodedInputEvent(
            rawEventType: CGEventType.mouseMoved.rawValue,
            event: f5Down
        ) == nil)

        #expect(KeyboardMonitor.decodedInputEvent(
            rawEventType: KeyboardMonitor.AuxiliaryControlKey.eventTypeRawValue,
            event: f5Down
        ) == nil)
    }

    @Test @MainActor
    func modernTopRowAliasesNormalizeToFunctionKeys() throws {
        let aliases: [(raw: UInt16, function: UInt16)] = [
            (129, 118), // Spotlight on older keyboards
            (131, 118), // App Exposé / Launchpad on older keyboards
            (160, 99), // Mission Control -> F3
            (177, 118), // Spotlight -> F4
            (176, 96), // Dictation -> F5
            (178, 97), // Focus / Do Not Disturb -> F6
            (179, 98), // Previous track -> F7
            (180, 101), // Next track -> F9
        ]

        for (rawKeyCode, functionKeyCode) in aliases {
            let event = try #require(
                CGEvent(keyboardEventSource: nil, virtualKey: rawKeyCode, keyDown: true)
            )
            guard case let .keyboard(decoded)? = KeyboardMonitor.decodedInputEvent(
                rawEventType: CGEventType.keyDown.rawValue,
                event: event
            ) else {
                Issue.record("key code \(rawKeyCode) should decode to a keyboard event")
                continue
            }
            #expect(decoded.keyCode == functionKeyCode)
        }

        for keyCode in [UInt16(122), 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111] {
            #expect(KeyboardMonitor.AuxiliaryControlKey.standardFunctionKeyCode(for: keyCode) == keyCode)
        }
    }

    @Test @MainActor
    func decodedFunctionKeyDownProducesUsageAggregate() async throws {
        let persistence = CapturingTypingStatsPersistence()
        let model = TypingStatsModel(persistence: persistence)
        let event = try #require(
            CGEvent(keyboardEventSource: nil, virtualKey: 160, keyDown: true)
        )
        guard case let .keyboard(decoded)? = KeyboardMonitor.decodedInputEvent(
            rawEventType: CGEventType.keyDown.rawValue,
            event: event
        ) else {
            Issue.record("Mission Control key event should decode")
            return
        }

        let application = TypingApplicationIdentity.unknown
        let occurredAt = Date(timeIntervalSince1970: 1_756_000_000)
        model.recordKeyDown(
            keyCode: decoded.keyCode,
            isRepeat: decoded.isRepeat,
            isShortcutModified: decoded.isShortcutModified,
            application: application,
            at: occurredAt
        )
        model.recordKeyDown(
            keyCode: decoded.keyCode,
            isRepeat: true,
            isShortcutModified: decoded.isShortcutModified,
            application: application,
            at: occurredAt
        )

        #expect(await model.flushPending())
        let batches = await persistence.recordedBatches()
        let aggregates = batches.flatMap { $0.keyAggregates }
        #expect(aggregates.count == 1)
        #expect(aggregates.first?.keyCode == 99)
        #expect(aggregates.first?.count == 1)
        #expect(batches.flatMap { $0.characterAggregates }.isEmpty)
    }

    @Test @MainActor
    func bothPathsReportTheSameF5PressAsTheSameKeyCode() throws {
        let auxiliary = try #require(Self.auxiliaryKeyboardEvent(
            nxKeyType: Self.illuminationDownKeyType,
            isDown: true
        ))
        let standard = try #require(Self.standardKeyboardEvent(
            virtualKey: Self.dictationVirtualKey,
            isDown: true
        ))

        // Without this collision there would be nothing to de-duplicate.
        #expect(auxiliary.keyCode == Self.f5KeyCode)
        #expect(standard.keyCode == Self.f5KeyCode)
        #expect(KeyboardMonitor.AuxiliaryControlKey.reportedFunctionKeyCodes
            .contains(Self.f5KeyCode))
    }

    @Test @MainActor
    func oneF5PressReachesTheHandlerOnceRegardlessOfPathOrder() throws {
        let auxDown = try #require(Self.auxiliaryKeyboardEvent(
            nxKeyType: Self.illuminationDownKeyType,
            isDown: true
        ))
        let auxUp = try #require(Self.auxiliaryKeyboardEvent(
            nxKeyType: Self.illuminationDownKeyType,
            isDown: false
        ))
        let standardDown = try #require(Self.standardKeyboardEvent(
            virtualKey: Self.dictationVirtualKey,
            isDown: true
        ))
        let standardUp = try #require(Self.standardKeyboardEvent(
            virtualKey: Self.dictationVirtualKey,
            isDown: false
        ))

        // The echo arrives in the same tap burst, ~1 ms behind the first copy.
        let auxiliaryFirst = Self.forwarded([
            (auxDown, .auxiliaryControl, 10.000),
            (standardDown, .standardKey, 10.001),
            (auxUp, .auxiliaryControl, 10.120),
            (standardUp, .standardKey, 10.121),
        ])
        let standardFirst = Self.forwarded([
            (standardDown, .standardKey, 10.000),
            (auxDown, .auxiliaryControl, 10.001),
            (standardUp, .standardKey, 10.120),
            (auxUp, .auxiliaryControl, 10.121),
        ])
        // Some sources release in the opposite order they pressed.
        let interleavedRelease = Self.forwarded([
            (auxDown, .auxiliaryControl, 10.000),
            (standardDown, .standardKey, 10.001),
            (standardUp, .standardKey, 10.120),
            (auxUp, .auxiliaryControl, 10.121),
        ])

        for stream in [auxiliaryFirst, standardFirst, interleavedRelease] {
            #expect(stream.map(\.kind) == [.keyDown, .keyUp])
            #expect(stream.allSatisfy { $0.keyCode == Self.f5KeyCode })
            #expect(stream.allSatisfy { !$0.isRepeat })
        }
    }

    @Test @MainActor
    func realConsecutiveFunctionKeyPressesAreAllForwarded() throws {
        let down = try #require(Self.auxiliaryKeyboardEvent(
            nxKeyType: Self.illuminationDownKeyType,
            isDown: true
        ))
        let up = try #require(Self.auxiliaryKeyboardEvent(
            nxKeyType: Self.illuminationDownKeyType,
            isDown: false
        ))

        // A keyboard on a single path taps F5 three times: nothing may be swallowed.
        let singlePath = Self.forwarded([
            (down, .auxiliaryControl, 10.0),
            (up, .auxiliaryControl, 10.05),
            (down, .auxiliaryControl, 10.1),
            (up, .auxiliaryControl, 10.15),
            (down, .auxiliaryControl, 10.2),
            (up, .auxiliaryControl, 10.25),
        ])
        #expect(singlePath.count == 6)
        #expect(singlePath.map(\.kind) == [.keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp])

        // Releases are not always tapped, so consecutive key downs must still all count.
        let downsOnly = Self.forwarded([
            (down, .standardKey, 10.0),
            (down, .standardKey, 10.3),
            (down, .standardKey, 10.6),
        ])
        #expect(downsOnly.count == 3)

        // Whichever path leads may flip between presses; past the window that is a real press.
        let pathFlips = Self.forwarded([
            (down, .standardKey, 10.0),
            (down, .auxiliaryControl, 10.4),
            (down, .standardKey, 10.8),
        ])
        #expect(pathFlips.count == 3)

        // Events inside the window are echoes; events outside it are new presses.
        var atBoundary = Deduplicator()
        Self.expect(duplicate: false, down, from: .standardKey, at: 10.0, in: &atBoundary)
        Self.expect(
            duplicate: true,
            down,
            from: .auxiliaryControl,
            at: 10.0 + Deduplicator.duplicateWindow - 0.001,
            in: &atBoundary
        )
        var pastBoundary = Deduplicator()
        Self.expect(duplicate: false, down, from: .standardKey, at: 10.0, in: &pastBoundary)
        Self.expect(
            duplicate: false,
            down,
            from: .auxiliaryControl,
            at: 10.0 + Deduplicator.duplicateWindow + 0.001,
            in: &pastBoundary
        )
    }

    @Test @MainActor
    func holdingF5KeepsAutorepeatAndReleaseSemantics() throws {
        let auxDown = try #require(Self.auxiliaryKeyboardEvent(
            nxKeyType: Self.illuminationDownKeyType,
            isDown: true
        ))
        let auxRepeat = try #require(Self.auxiliaryKeyboardEvent(
            nxKeyType: Self.illuminationDownKeyType,
            isDown: true,
            isRepeat: true
        ))
        let auxUp = try #require(Self.auxiliaryKeyboardEvent(
            nxKeyType: Self.illuminationDownKeyType,
            isDown: false
        ))
        let standardDown = try #require(Self.standardKeyboardEvent(
            virtualKey: Self.dictationVirtualKey,
            isDown: true
        ))
        let standardRepeat = try #require(Self.standardKeyboardEvent(
            virtualKey: Self.dictationVirtualKey,
            isDown: true,
            isRepeat: true
        ))
        let standardUp = try #require(Self.standardKeyboardEvent(
            virtualKey: Self.dictationVirtualKey,
            isDown: false
        ))
        #expect(auxRepeat.isRepeat)
        #expect(standardRepeat.isRepeat)

        let held = Self.forwarded([
            (auxDown, .auxiliaryControl, 10.000),
            (standardDown, .standardKey, 10.001),
            (auxRepeat, .auxiliaryControl, 10.500),
            (standardRepeat, .standardKey, 10.501),
            (auxRepeat, .auxiliaryControl, 10.533),
            (standardRepeat, .standardKey, 10.534),
            (auxUp, .auxiliaryControl, 10.700),
            (standardUp, .standardKey, 10.701),
        ])

        // One initial press, both autorepeats, one release — each exactly once.
        #expect(held.map(\.kind) == [.keyDown, .keyDown, .keyDown, .keyUp])
        #expect(held.map(\.isRepeat) == [false, true, true, false])

        // The two paths can disagree on the autorepeat bit; they still describe one transition.
        var mismatched = Deduplicator()
        Self.expect(duplicate: false, auxDown, from: .auxiliaryControl, at: 10.0, in: &mismatched)
        Self.expect(
            duplicate: true,
            standardRepeat,
            from: .standardKey,
            at: 10.001,
            in: &mismatched
        )
    }

    @Test @MainActor
    func keysOnlyOnePathReportsAreNeverDeduplicated() {
        // 'a', left command, left shift, and F3 (Mission Control has no NX_KEYTYPE_* code).
        for keyCode in [UInt16(0), 55, 56, 99] {
            #expect(!KeyboardMonitor.AuxiliaryControlKey.reportedFunctionKeyCodes.contains(keyCode))
            var deduplicator = Deduplicator()
            let event = KeyboardEvent(kind: .keyDown, keyCode: keyCode, isRepeat: false)
            Self.expect(duplicate: false, event, from: .standardKey, at: 10.0, in: &deduplicator)
            // Even an identical event from the other path stays, so no keystroke can go missing.
            Self.expect(
                duplicate: false,
                event,
                from: .auxiliaryControl,
                at: 10.001,
                in: &deduplicator
            )
            Self.expect(duplicate: false, event, from: .standardKey, at: 10.002, in: &deduplicator)
        }
    }

    @Test @MainActor
    func everyAuxiliaryReportedFunctionKeyIsDeduplicated() {
        let expected = Set(Self.auxiliaryControlMappings.map { $0.keyCode })
        #expect(KeyboardMonitor.AuxiliaryControlKey.reportedFunctionKeyCodes == expected)

        for keyCode in expected.sorted() {
            var deduplicator = Deduplicator()
            let down = KeyboardEvent(kind: .keyDown, keyCode: keyCode, isRepeat: false)
            let up = KeyboardEvent(kind: .keyUp, keyCode: keyCode, isRepeat: false)
            Self.expect(duplicate: false, down, from: .auxiliaryControl, at: 10.0, in: &deduplicator)
            Self.expect(duplicate: true, down, from: .standardKey, at: 10.001, in: &deduplicator)
            Self.expect(duplicate: false, up, from: .auxiliaryControl, at: 10.1, in: &deduplicator)
            Self.expect(duplicate: true, up, from: .standardKey, at: 10.101, in: &deduplicator)
        }

        // Keys are tracked independently: F11 down must not mask F12 down.
        var shared = Deduplicator()
        let volumeDown = KeyboardEvent(kind: .keyDown, keyCode: 103, isRepeat: false)
        let volumeUp = KeyboardEvent(kind: .keyDown, keyCode: 111, isRepeat: false)
        Self.expect(duplicate: false, volumeDown, from: .auxiliaryControl, at: 10.0, in: &shared)
        Self.expect(duplicate: false, volumeUp, from: .standardKey, at: 10.001, in: &shared)
    }

    @Test @MainActor
    func resetClearsPendingDuplicateStateLikeTapRestarts() {
        var deduplicator = Deduplicator()
        let down = KeyboardEvent(kind: .keyDown, keyCode: Self.f5KeyCode, isRepeat: false)
        Self.expect(duplicate: false, down, from: .auxiliaryControl, at: 10.0, in: &deduplicator)

        // stop() and the tap re-enable path drop the state, so nothing is suppressed afterwards.
        deduplicator.reset()
        Self.expect(duplicate: false, down, from: .standardKey, at: 10.001, in: &deduplicator)
    }

    @Test @MainActor
    func sourceIsDerivedFromTheRawEventType() {
        #expect(Deduplicator.Source(
            rawEventType: KeyboardMonitor.AuxiliaryControlKey.eventTypeRawValue
        ) == .auxiliaryControl)
        for rawEventType in [
            CGEventType.keyDown.rawValue,
            CGEventType.keyUp.rawValue,
            CGEventType.flagsChanged.rawValue,
        ] {
            #expect(Deduplicator.Source(rawEventType: rawEventType) == .standardKey)
        }
    }

    @Test @MainActor
    func duplicatedF5PressesCountOncePerRealPressInUsageStats() async throws {
        let persistence = CapturingTypingStatsPersistence()
        let model = TypingStatsModel(persistence: persistence)
        let auxDown = try #require(Self.auxiliaryKeyboardEvent(
            nxKeyType: Self.illuminationDownKeyType,
            isDown: true
        ))
        let auxUp = try #require(Self.auxiliaryKeyboardEvent(
            nxKeyType: Self.illuminationDownKeyType,
            isDown: false
        ))
        let standardDown = try #require(Self.standardKeyboardEvent(
            virtualKey: Self.dictationVirtualKey,
            isDown: true
        ))
        let standardUp = try #require(Self.standardKeyboardEvent(
            virtualKey: Self.dictationVirtualKey,
            isDown: false
        ))

        // Two real F5 presses, each echoed on the other path a millisecond later.
        let stream: [(KeyboardEvent, Deduplicator.Source, TimeInterval)] = [
            (auxDown, .auxiliaryControl, 10.000),
            (standardDown, .standardKey, 10.001),
            (auxUp, .auxiliaryControl, 10.120),
            (standardUp, .standardKey, 10.121),
            (auxDown, .auxiliaryControl, 10.400),
            (standardDown, .standardKey, 10.401),
            (auxUp, .auxiliaryControl, 10.520),
            (standardUp, .standardKey, 10.521),
        ]

        let application = TypingApplicationIdentity.unknown
        let occurredAt = Date(timeIntervalSince1970: 1_756_000_000)
        for event in Self.forwarded(stream) where event.kind == .keyDown {
            model.recordKeyDown(
                keyCode: event.keyCode,
                isRepeat: event.isRepeat,
                isShortcutModified: event.isShortcutModified,
                application: application,
                at: occurredAt
            )
        }

        #expect(await model.flushPending())
        let batches = await persistence.recordedBatches()
        let aggregates = batches.flatMap { $0.keyAggregates }
        #expect(aggregates.count == 1)
        #expect(aggregates.first?.keyCode == Self.f5KeyCode)
        // Two presses, not the four the un-deduplicated stream would have produced.
        #expect(aggregates.first?.count == 2)
        #expect(batches.flatMap { $0.characterAggregates }.isEmpty)
    }
}

private actor CapturingTypingStatsPersistence: TypingStatsPersistence {
    private var batches: [TypingStatsWriteBatch] = []

    func record(_ batch: TypingStatsWriteBatch) async throws {
        batches.append(batch)
    }

    func loadSnapshot(timelineRange: TypingTimelineRange) async throws -> TypingStatsSnapshot {
        fatalError("The test persistence does not load snapshots")
    }

    func clearAll() async throws {}

    func recordedBatches() -> [TypingStatsWriteBatch] {
        batches
    }
}
