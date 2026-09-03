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
