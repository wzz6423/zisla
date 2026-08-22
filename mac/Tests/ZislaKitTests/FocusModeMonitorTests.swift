import Foundation
import Testing
@testable import ZislaKit

@Suite(.serialized)
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
    func workoutModeDoesNotMatchWorkMode() {
        let status = FocusModeStatus(
            isActive: true,
            identifier: "com.apple.donotdisturb.mode.workout"
        )

        #expect(status.presentation == FocusModePresentation(
            title: "健身",
            symbolName: "figure.run"
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
    func systemModeNameAndSymbolTakePriorityOverIdentifierFallback() {
        let mode = FocusTestMode(
            modeIdentifier: "com.example.workout",
            name: "训练",
            symbolImageName: "figure.strengthtraining.traditional"
        )
        let state = FocusTestState(
            activeModeIdentifier: mode.modeIdentifier,
            activeModeConfiguration: FocusTestModeConfiguration(mode: mode)
        )
        let update = FocusTestStateUpdate(state: state)

        let status = FocusStateUpdateListener.status(from: update)

        #expect(status?.presentation == FocusModePresentation(
            title: "训练",
            symbolName: "figure.strengthtraining.traditional"
        ))
    }

    @Test
    func stateWithoutExplicitActivityFlagIsIgnored() {
        let update = FocusTestIdentifierOnlyStateUpdate(
            state: FocusTestIdentifierOnlyState(
                activeModeIdentifier: "com.apple.donotdisturb.mode.work"
            )
        )

        #expect(FocusStateUpdateListener.status(from: update) == nil)
    }

    @Test
    func assertionStoreCannotEraseSystemModePresentation() {
        let systemStatus = FocusModeStatus(
            isActive: true,
            identifier: "com.example.workout",
            displayName: "训练",
            symbolName: "figure.strengthtraining.traditional"
        )
        let storeStatus = FocusModeStatus(
            isActive: true,
            identifier: "com.example.workout"
        )

        let resolved = storeStatus.preservingMissingPresentation(from: systemStatus)

        #expect(resolved.presentation == FocusModePresentation(
            title: "训练",
            symbolName: "figure.strengthtraining.traditional"
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
    func assertionStoreHonorsGlobalInvalidationRequest() throws {
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
            "storeInvalidationRequestRecords": [{
              "invalidationRequestPredicate": {
                "invalidationPredicateType": "any"
              },
              "invalidationRequestDateTimestamp": 300
            }]
          }],
          "header": {"timestamp": 400}
        }
        """#.utf8)

        #expect(try FocusModeStatusStore.decode(data) == .inactive)
    }

    @Test
    func recentInvalidationReportsTheModeThatJustEnded() throws {
        let data = Data(#"""
        {
          "data": [{
            "storeInvalidationRecords": [{
              "invalidationAssertion": {
                "assertionDetails": {
                  "assertionDetailsModeIdentifier": "com.apple.focus.work"
                }
              },
              "invalidationDateTimestamp": 300
            }]
          }],
          "header": {"timestamp": 300}
        }
        """#.utf8)

        let status = try FocusModeStatusStore.decode(data, currentTimestamp: 303)

        #expect(!status.isActive)
        #expect(status.identifier == "com.apple.focus.work")
    }

    @Test
    func oldInvalidationDoesNotProduceAStartupTransition() throws {
        let data = Data(#"""
        {
          "data": [{
            "storeInvalidationRecords": [{
              "invalidationAssertion": {
                "assertionDetails": {
                  "assertionDetailsModeIdentifier": "com.apple.focus.work"
                }
              },
              "invalidationDateTimestamp": 300
            }]
          }],
          "header": {"timestamp": 300}
        }
        """#.utf8)

        #expect(try FocusModeStatusStore.decode(data, currentTimestamp: 306) == .inactive)
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

        try inactiveAfterGlobalInvalidationAssertionData.write(to: url, options: .atomic)
        #expect(await waitUntil { !monitor.status.isActive })
        #expect(monitor.status.identifier == "com.apple.donotdisturb.mode.work")

        try reactivatedAssertionData.write(to: url, options: .atomic)
        #expect(await waitUntil { monitor.status.isActive })
        #expect(monitor.status.identifier == "com.apple.donotdisturb.mode.work")
    }

    @Test @MainActor
    func assertionStoreAppearingAfterStartIsMonitored() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("Assertions.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let monitor = FocusModeMonitor(
            clientIdentifier: "dev.wzz.zisla.focus-test",
            statusStoreURL: url,
            storePollingInterval: .milliseconds(10)
        )
        monitor.start()
        defer { monitor.stop() }

        try activeAssertionData.write(to: url, options: .atomic)
        #expect(await waitUntil(timeout: 2) { monitor.status.isActive })
        #expect(monitor.status.identifier == "com.apple.donotdisturb.mode.work")
    }

    @Test @MainActor
    func distributedEnabledNotificationDoesNotPublishTransitionWithoutAuthoritativeState() async {
        let monitor = FocusModeMonitor(
            clientIdentifier: "dev.wzz.zisla.focus-notification-test",
            statusStoreURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString),
            storePollingInterval: .milliseconds(10)
        )
        monitor.start()
        defer { monitor.stop() }

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("_NSDoNotDisturbEnabledNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        try? await Task.sleep(for: .milliseconds(100))
        #expect(monitor.latestTransition == nil)
        #expect(!monitor.status.isActive)
    }

    @Test @MainActor
    func repeatedInvalidationsPublishTransitionsEvenWhenTheResolvedStatusIsUnchanged() async throws {
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
        #expect(await waitUntil { monitor.isAvailable })

        try invalidationData(assertionID: "first").write(to: url, options: .atomic)
        #expect(await waitUntil { monitor.latestTransition != nil })
        let firstTransitionID = try #require(monitor.latestTransition?.id)

        try invalidationData(assertionID: "second").write(to: url, options: .atomic)
        #expect(await waitUntil { monitor.latestTransition?.id != firstTransitionID })
        #expect(monitor.latestTransition?.status == FocusModeStatus(
            isActive: false,
            identifier: "com.apple.donotdisturb.mode.default"
        ))
    }

    @Test @MainActor
    func invalidationFromBeforeStartDoesNotPublishATransition() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("Assertions.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try invalidationData(
            assertionID: "before-start",
            timestamp: Date().timeIntervalSinceReferenceDate - 0.1
        ).write(to: url, options: .atomic)

        let monitor = FocusModeMonitor(
            clientIdentifier: "dev.wzz.zisla.focus-test",
            statusStoreURL: url,
            storePollingInterval: .milliseconds(10)
        )
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .milliseconds(100))

        #expect(monitor.latestTransition == nil)
    }

    private var activeAssertionData: Data {
        Data(#"{"data":[{"storeAssertionRecords":[{"assertionStartDateTimestamp":200,"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.work"}}]}],"header":{}}"#.utf8)
    }

    private var inactiveAssertionData: Data {
        Data(#"{"data":[{"storeInvalidationRecords":[]}],"header":{}}"#.utf8)
    }

    private var inactiveAfterGlobalInvalidationAssertionData: Data {
        Data(#"{"data":[{"storeAssertionRecords":[{"assertionUUID":"focus","assertionStartDateTimestamp":200,"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.work"}}],"storeInvalidationRequestRecords":[{"invalidationRequestPredicate":{"invalidationPredicateType":"any"},"invalidationRequestDateTimestamp":300}]}],"header":{"timestamp":400}}"#.utf8)
    }

    private var reactivatedAssertionData: Data {
        Data(#"{"data":[{"storeAssertionRecords":[{"assertionUUID":"focus-new","assertionStartDateTimestamp":400,"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.work"}}],"storeInvalidationRequestRecords":[{"invalidationRequestPredicate":{"invalidationPredicateType":"any"},"invalidationRequestDateTimestamp":400}]}],"header":{"timestamp":500}}"#.utf8)
    }

    private func invalidationData(
        assertionID: String,
        timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> Data {
        return Data(
            #"{"data":[{"storeInvalidationRecords":[{"invalidationAssertion":{"assertionUUID":"\#(assertionID)","assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}},"invalidationDateTimestamp":\#(timestamp)}]}],"header":{"timestamp":\#(timestamp)}}"#
                .utf8
        )
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

private final class FocusTestMode: NSObject {
    @objc dynamic var modeIdentifier: String
    @objc dynamic var name: String
    @objc dynamic var symbolImageName: String

    init(modeIdentifier: String, name: String, symbolImageName: String) {
        self.modeIdentifier = modeIdentifier
        self.name = name
        self.symbolImageName = symbolImageName
        super.init()
    }
}

private final class FocusTestModeConfiguration: NSObject {
    @objc dynamic var mode: FocusTestMode

    init(mode: FocusTestMode) {
        self.mode = mode
        super.init()
    }
}

private final class FocusTestState: NSObject {
    @objc dynamic var activeModeIdentifier: String
    @objc dynamic var activeModeConfiguration: FocusTestModeConfiguration
    @objc dynamic var isActive = true

    init(activeModeIdentifier: String, activeModeConfiguration: FocusTestModeConfiguration) {
        self.activeModeIdentifier = activeModeIdentifier
        self.activeModeConfiguration = activeModeConfiguration
        super.init()
    }
}

private final class FocusTestStateUpdate: NSObject {
    @objc dynamic var state: FocusTestState

    init(state: FocusTestState) {
        self.state = state
        super.init()
    }
}

private final class FocusTestIdentifierOnlyState: NSObject {
    @objc dynamic var activeModeIdentifier: String

    init(activeModeIdentifier: String) {
        self.activeModeIdentifier = activeModeIdentifier
        super.init()
    }
}

private final class FocusTestIdentifierOnlyStateUpdate: NSObject {
    @objc dynamic var state: FocusTestIdentifierOnlyState

    init(state: FocusTestIdentifierOnlyState) {
        self.state = state
        super.init()
    }
}
