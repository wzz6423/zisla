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
    func assertionStoreSelectsLatestValidModeInsteadOfUnrelatedAssertion() throws {
        let data = Data(#"""
        {
          "data": [{
            "storeAssertionRecords": [
              {
                "assertionUUID": "focus",
                "assertionStartDateTimestamp": 200,
                "assertionDetails": {
                  "assertionDetailsModeIdentifier": "com.apple.focus.work"
                }
              },
              {
                "assertionUUID": "unrelated",
                "assertionStartDateTimestamp": 300,
                "assertionDetails": {
                  "assertionDetailsIdentifier": "com.apple.some-other-assertion"
                }
              }
            ]
          }],
          "header": {"timestamp": 400}
        }
        """#.utf8)

        let status = try FocusModeStatusStore.decode(data)

        #expect(status.isActive)
        #expect(status.identifier == "com.apple.focus.work")
    }

    @Test
    func assertionStoreIgnoresInvalidatedModeAssertion() throws {
        let data = Data(#"""
        {
          "data": [{
            "storeAssertionRecords": [{
              "assertionUUID": "focus",
              "assertionStartDateTimestamp": 200,
              "assertionDetails": {
                "assertionDetailsModeIdentifier": "com.apple.focus.work"
              }
            }],
            "storeInvalidationRecords": [{
              "invalidationAssertion": {
                "assertionUUID": "focus"
              },
              "invalidationDateTimestamp": 300
            }]
          }],
          "header": {"timestamp": 400}
        }
        """#.utf8)

        #expect(try FocusModeStatusStore.decode(data) == .inactive)
    }

    @Test
    func assertionStoreIgnoresExpiredModeAssertion() throws {
        let data = Data(#"""
        {
          "data": [{
            "storeAssertionRecords": [{
              "assertionStartDateTimestamp": 200,
              "assertionDetails": {
                "assertionDetailsModeIdentifier": "com.apple.focus.work",
                "assertionDetailsUserVisibleEndDate": 300
              }
            }]
          }],
          "header": {"timestamp": 400}
        }
        """#.utf8)

        #expect(try FocusModeStatusStore.decode(data) == .inactive)
    }

    @Test
    func assertionStoreLoadsStatusFromDiskAsynchronously() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"data":[{"storeAssertionRecords":[]}],"header":{}}"#.utf8)
            .write(to: url)

        #expect(await FocusModeStatusStore.load(from: url) == .inactive)
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

    @Test @MainActor
    func readableAssertionStoreTakesPriorityOverPrivateFramework() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("Assertions.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try inactiveAssertionData.write(to: url, options: .atomic)

        let monitor = FocusModeMonitor(
            clientIdentifier: "dev.wzz.zisla.focus-test",
            statusStoreURL: url,
            storePollingInterval: .milliseconds(10)
        )
        monitor.start()
        defer { monitor.stop() }

        try activeAssertionData.write(to: url, options: .atomic)
        #expect(await waitUntil { monitor.status.isActive })

        try inactiveAssertionData.write(to: url, options: .atomic)
        #expect(await waitUntil { !monitor.status.isActive })
        #expect(monitor.status.identifier == "com.apple.donotdisturb.mode.work")
    }

    private var activeAssertionData: Data {
        Data(#"{"data":[{"storeAssertionRecords":[{"assertionStartDateTimestamp":200,"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.work"}}]}],"header":{}}"#.utf8)
    }

    private var inactiveAssertionData: Data {
        Data(#"{"data":[{"storeInvalidationRecords":[]}],"header":{}}"#.utf8)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 10,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
