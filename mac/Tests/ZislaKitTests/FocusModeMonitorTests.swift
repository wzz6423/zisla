import Foundation
import Testing
@testable import ZislaKit

struct FocusModeMonitorTests {
    @Test
    func knownSystemModeUsesLocalizedPresentation() {
        let status = FocusModeStatus(
            isActive: true,
            identifier: "com.apple.donotdisturb.mode.work"
        )

        #expect(status.presentation == FocusModePresentation(
            title: "工作",
            symbolName: "briefcase.fill"
        ))
    }

    @Test
    func customDisplayNameTakesPriorityOverIdentifierFallback() {
        let status = FocusModeStatus(
            isActive: true,
            identifier: "com.example.deep-work",
            displayName: " 深度工作 "
        )

        #expect(status.presentation == FocusModePresentation(
            title: "深度工作",
            symbolName: "briefcase.fill"
        ))
    }

    @Test
    func unknownModeFallsBackToGenericFocusPresentation() {
        let status = FocusModeStatus(isActive: true, identifier: "com.example.custom")

        #expect(status.presentation == FocusModePresentation(
            title: "专注模式",
            symbolName: "moon.fill"
        ))
    }

    @Test
    func assertionStoreDecodesCurrentSleepMode() throws {
        let data = Data(#"""
        {
          "data": [{
            "storeAssertionRecords": [{
              "assertionStartDateTimestamp": 200,
              "assertionDetails": {
                "assertionDetailsModeIdentifier": "com.apple.sleep.sleep-mode"
              }
            }]
          }],
          "header": {"version": 1, "timestamp": 200}
        }
        """#.utf8)

        let status = try FocusModeStatusStore.decode(data)

        #expect(status.isActive)
        #expect(status.identifier == "com.apple.sleep.sleep-mode")
        #expect(status.presentation.symbolName == "bed.double.fill")
    }

    @Test
    func assertionStoreWithoutActiveRecordsIsInactive() throws {
        let data = Data(#"{"data":[{"storeInvalidationRecords":[]}],"header":{}}"#.utf8)

        #expect(try FocusModeStatusStore.decode(data) == .inactive)
    }

    @Test
    func inactiveTransitionKeepsThePreviousModePresentation() {
        let sleep = FocusModeStatus(
            isActive: true,
            identifier: "com.apple.sleep.sleep-mode"
        )

        let inactive = FocusModeStatus.inactive.preservingMode(from: sleep)

        #expect(!inactive.isActive)
        #expect(inactive.identifier == sleep.identifier)
        #expect(inactive.presentation.symbolName == "bed.double.fill")
    }
}
