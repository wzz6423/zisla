import AppKit
import CoreGraphics
import Testing
@testable import ZislaKit

@MainActor
struct ScreenCleaningControllerTests {
    @Test
    func startsWhenEventTapWasInstalledEvenIfAccessibilityPreflightIsStale() {
        let result = ScreenCleaningController.keyboardCleaningStartResult(
            eventTapInstalled: true,
            hasAccessibilityAccess: false
        )

        #expect(result == .started)
    }

    @Test
    func reportsAccessibilityPermissionWhenEventTapCannotBeInstalled() {
        let result = ScreenCleaningController.keyboardCleaningStartResult(
            eventTapInstalled: false,
            hasAccessibilityAccess: false
        )

        #expect(result == .accessibilityPermissionRequired)
    }

    @Test
    func reportsRegistrationFailureWhenAccessibilityIsGrantedButEventTapFails() {
        let result = ScreenCleaningController.keyboardCleaningStartResult(
            eventTapInstalled: false,
            hasAccessibilityAccess: true
        )

        #expect(result == .registrationFailed)
    }

    @Test
    func keyboardCleaningEventMaskIncludesKeyAndSystemDefinedEvents() {
        // NX_SYSDEFINED is raw event type 14 and intentionally has no Swift enum case.
        for rawEventType in [UInt32(10), 11, 12, 14] {
            let eventBit = CGEventMask(1) << rawEventType
            #expect(ScreenCleaningController.keyboardCleaningEventMask & eventBit != 0)
        }
    }

    @Test
    func onlyAuxiliaryControlSystemEventsAreBlocked() throws {
        let auxiliaryControl = try #require(NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: 0,
            data2: 0
        ))
        let powerKey = try #require(NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 1,
            data1: 0,
            data2: 0
        ))
        let auxiliaryMouse = try #require(NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 7,
            data1: 0,
            data2: 0
        ))

        #expect(ScreenCleaningController.shouldBlockSystemDefinedEvent(auxiliaryControl))
        #expect(!ScreenCleaningController.shouldBlockSystemDefinedEvent(powerKey))
        #expect(!ScreenCleaningController.shouldBlockSystemDefinedEvent(auxiliaryMouse))
    }
}
