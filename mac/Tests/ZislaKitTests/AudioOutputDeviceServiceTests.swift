import Combine
import CoreAudio
import Foundation
import Testing
@testable import ZislaKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct AudioOutputDeviceServiceTests {
    @Test
    func recognizesCommonHeadphoneNames() {
        #expect(AudioOutputDevice(id: 1, name: "AirPods Pro", isBluetoothAudio: true).isHeadphones)
        #expect(AudioOutputDevice(id: 2, name: "Beats Studio Buds", isBluetoothAudio: true).isHeadphones)
        #expect(AudioOutputDevice(id: 3, name: "三年后AirPods Max", isBluetoothAudio: true).isHeadphones)
        #expect(AudioOutputDevice(id: 3, name: "三年后AirPods Max", isBluetoothAudio: true).isAirPodsMax)
        #expect(!AudioOutputDevice(id: 4, name: "MacBook Pro Speakers").isHeadphones)
    }

    @Test
    func publishesNewlyConnectedAirPodsMaxWithoutDefaultOutputChange() {
        let airPodsPro = AudioOutputDevice(id: 1, name: "AirPods Pro", isBluetoothAudio: true)
        let airPodsMax = AudioOutputDevice(id: 2, name: "三年后AirPods Max", isBluetoothAudio: true)

        let candidate = AudioOutputDeviceService.connectionCandidate(
            previousDevice: airPodsPro,
            currentDevice: airPodsPro,
            previousHeadphoneDeviceIDs: [airPodsPro.id],
            updatedDevices: [airPodsPro, airPodsMax]
        )

        #expect(candidate == airPodsMax)
    }

    @Test
    func parsesConnectedAirPodsBatteryLevelsFromBluetoothProfile() throws {
        let data = try #require(
            """
            {
              "SPBluetoothDataType": [
                {
                  "device_connected": [
                    {
                      "AirPods Pro": {
                        "device_minorType": "Headphones",
                        "device_productID": "0x2027",
                        "device_batteryLevelLeft": "91%",
                        "device_batteryLevelRight": "83%",
                        "device_batteryLevelCase": "62%"
                      }
                    }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let snapshot = HeadphoneBatterySnapshot.fromBluetoothProfile(data, deviceName: "AirPods Pro")

        #expect(snapshot == HeadphoneBatterySnapshot(leftLevel: 91, rightLevel: 83, caseLevel: 62))
        #expect(snapshot?.noticeLevels.map(\.level) == [91, 83, 62])

        let profile = HeadphoneBluetoothProfile.fromBluetoothProfile(data, deviceName: "AirPods Pro")
        #expect(profile?.productID == 0x2027)
    }

    @Test
    func keepsBatteryWhenBluetoothProfileProductIDIsInvalid() throws {
        let data = try #require(
            """
            {
              "SPBluetoothDataType": [
                {
                  "device_connected": [
                    {
                      "AirPods Pro": {
                        "device_minorType": "Headphones",
                        "device_productID": "not-a-product-id",
                        "device_batteryLevelLeft": "91%"
                      }
                    }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let profile = HeadphoneBluetoothProfile.fromBluetoothProfile(data, deviceName: "AirPods Pro")

        #expect(profile?.productID == nil)
        #expect(profile?.battery == HeadphoneBatterySnapshot(
            leftLevel: 91,
            rightLevel: nil,
            caseLevel: nil
        ))
    }

    @Test
    func parsesSingleAirPodsMaxBatteryLevel() throws {
        let data = try #require(
            """
            {
              "SPBluetoothDataType": [
                {
                  "device_connected": [
                    {
                      "AirPods Max": {
                        "device_minorType": "Headphones",
                        "device_batteryLevelMain": "81%"
                      }
                    }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let snapshot = HeadphoneBatterySnapshot.fromBluetoothProfile(
            data,
            deviceName: "AirPods Max"
        )

        #expect(snapshot == HeadphoneBatterySnapshot(
            leftLevel: nil,
            rightLevel: nil,
            caseLevel: nil,
            mainLevel: 81
        ))
        #expect(snapshot?.noticeLevels.map(\.label) == ["耳机"])
        #expect(snapshot?.noticeLevels.map(\.level) == [81])
    }

    @Test
    func mapsScannedAirPodsMaxBatteryToOneNoticeLevel() {
        let device = NetworkBatteryDevice(
            identifier: "apple-headphone:test",
            name: "AirPods Max",
            deviceType: .headphones,
            batteryLevel: 0.58,
            isCharging: false,
            components: [
                BatteryLevelComponent(kind: .left, level: 0.58),
                BatteryLevelComponent(kind: .right, level: 0.61),
            ]
        )

        let snapshot = HeadphoneBatterySnapshot.fromNetworkBatteryDevice(device)

        #expect(snapshot == HeadphoneBatterySnapshot(
            leftLevel: nil,
            rightLevel: nil,
            caseLevel: nil,
            mainLevel: 58
        ))
        #expect(snapshot?.noticeLevels.map(\.level) == [58])
    }

    @Test
    func bluetoothTransportDoesNotChangeHeadphoneNameRecognition() {
        #expect(!AudioOutputDevice(id: 1, name: "AirPods Pro").isBluetoothAudio)
        #expect(AudioOutputDeviceService.isBluetoothTransport(kAudioDeviceTransportTypeBluetooth))
        #expect(AudioOutputDeviceService.isBluetoothTransport(kAudioDeviceTransportTypeBluetoothLE))
        for transport in [kAudioDeviceTransportTypeBuiltIn, kAudioDeviceTransportTypeUSB,
                          kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeUnknown] {
            #expect(!AudioOutputDeviceService.isBluetoothTransport(transport))
        }
        let speaker = AudioOutputDevice(id: 2, name: "Bluetooth Speaker", isBluetoothAudio: true)
        #expect(speaker.isBluetoothAudio)
        #expect(!speaker.isHeadphones)
    }

    @Test
    func multipleHeadphonesDoNotBorrowUnmatchedDevicesBattery() throws {
        let data = try #require(
            """
            {"SPBluetoothDataType":[{"device_connected":[{"AirPods Pro":{
                "device_minorType":"Headphones", "device_batteryLevelLeft":"91%"
            }}]}]}
            """.data(using: .utf8)
        )
        #expect(HeadphoneBluetoothProfile.fromBluetoothProfile(
            data, deviceName: "AirPods Pro", allowsSingleHeadphoneFallback: false
        )?.battery?.leftLevel == 91)
        #expect(HeadphoneBluetoothProfile.fromBluetoothProfile(
            data, deviceName: "Beats Studio Buds", allowsSingleHeadphoneFallback: false
        ) == nil)
        #expect(HeadphoneBluetoothProfile.fromBluetoothProfile(
            data, deviceName: "Renamed Headphones"
        )?.battery?.leftLevel == 91)
    }

    @Test
    func readsAlreadyConnectedHeadphonesAtStartWithoutConnectionNotice() async throws {
        let output = HeadphoneOutputStub(devices: [Self.airPods], selectedID: Self.airPods.id)
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(81)])
        let clock = HeadphoneRefreshClock()
        let service = Self.service(output: output, reader: reader, clock: clock)
        defer { service.stop() }
        service.setHeadphoneBatteryMonitoringEnabled(true)
        #expect(await reader.callCount == 0)
        service.start()
        try await Self.waitUntil { service.headphoneStatuses.first?.battery?.leftLevel == 81 }
        #expect(service.headphoneStatuses.map(\.device) == [Self.airPods])
        #expect(service.headphoneConnection == nil)
        #expect(await reader.callCount == 1)
        service.start()
        service.setHeadphoneBatteryMonitoringEnabled(true)
        #expect(await reader.callCount == 1)
    }

    @Test
    func keepsMultipleConnectedHeadphonesAndMissingBatteryAsNil() async throws {
        let unknown = AudioOutputDevice(id: 3, name: "Beats Studio Buds", isBluetoothAudio: true)
        let wired = AudioOutputDevice(id: 4, name: "USB Headphones")
        let output = HeadphoneOutputStub(
            devices: [Self.airPods, Self.airPodsMax, unknown, wired, Self.speakers],
            selectedID: Self.speakers.id
        )
        let reader = HeadphoneReaderStub(profiles: [
            Self.airPods.name: Self.profile(91),
            Self.airPodsMax.name: HeadphoneBluetoothProfile(
                battery: HeadphoneBatterySnapshot(leftLevel: nil, rightLevel: nil, caseLevel: nil, mainLevel: 58),
                productID: 0x200a
            ),
        ])
        let service = Self.service(output: output, reader: reader)
        defer { service.stop() }
        service.start()
        service.setHeadphoneBatteryMonitoringEnabled(true)
        try await Self.waitUntil { service.headphoneStatuses.first?.battery?.leftLevel == 91 }
        #expect(service.headphoneStatuses.map(\.device) == [Self.airPods, Self.airPodsMax, unknown, wired])
        #expect(service.headphoneStatuses[1].battery?.mainLevel == 58)
        #expect(service.headphoneStatuses[1].productID == 0x200a)
        #expect(service.headphoneStatuses[2].battery == nil)
        #expect(service.headphoneStatuses[3].battery == nil)
        #expect(service.headphoneStatuses[0].battery?.rightLevel == nil)
        #expect(await reader.requests == [[Self.airPods.name, Self.airPodsMax.name, unknown.name]])
    }

    @Test
    func periodicAndDeviceRefreshUpdateBatteryWithoutRepeatingConnectionEvents() async throws {
        let output = HeadphoneOutputStub(devices: [Self.speakers], selectedID: Self.speakers.id)
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(90)])
        let clock = HeadphoneRefreshClock()
        let service = Self.service(output: output, reader: reader, clock: clock)
        var notices: [HeadphoneConnection] = []
        let subscription = service.$headphoneConnection.compactMap { $0 }.sink { notices.append($0) }
        defer { service.stop(); subscription.cancel() }
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.start()
        output.devices.append(Self.airPods)
        service.refresh()
        try await Self.waitUntil { notices.count == 1 && service.headphoneStatuses.first?.battery != nil }
        let statusID = try #require(service.headphoneStatuses.first?.id)
        #expect(await reader.callCount == 1)

        await reader.setProfiles([Self.airPods.name: Self.profile(70)])
        try await Self.waitUntil { await clock.pendingCount == 1 }
        await clock.tick()
        try await Self.waitUntil { service.headphoneStatuses.first?.battery?.leftLevel == 70 }
        #expect(service.headphoneStatuses.first?.id == statusID)
        #expect(notices.count == 1)
        #expect(notices.first?.battery?.leftLevel == 90)

        await reader.setProfiles([Self.airPods.name: Self.profile(60)])
        service.refresh()
        try await Self.waitUntil { service.headphoneStatuses.first?.battery?.leftLevel == 60 }
        #expect(notices.count == 1)
        #expect(await reader.callCount == 3)
    }

    @Test
    func disconnectRemovesStatusesButDefaultOutputSwitchDoesNot() async throws {
        let output = HeadphoneOutputStub(
            devices: [Self.airPods, Self.speakers], selectedID: Self.airPods.id
        )
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(80)])
        let service = Self.service(output: output, reader: reader)
        var notices: [HeadphoneConnection] = []
        let subscription = service.$headphoneConnection.compactMap { $0 }.sink { notices.append($0) }
        defer { service.stop(); subscription.cancel() }
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.start()
        try await Self.waitUntil { service.headphoneStatuses.first?.battery != nil }
        output.selectedID = Self.speakers.id
        service.refresh()
        #expect(service.selectedDevice == Self.speakers)
        #expect(service.headphoneStatuses.map(\.device) == [Self.airPods])
        try await Self.waitUntil { await reader.callCount == 2 }
        output.selectedID = Self.airPods.id
        service.refresh()
        try await Self.waitUntil { notices.count == 1 }
        #expect(service.headphoneStatuses.map(\.device) == [Self.airPods])
        output.devices = [Self.speakers]
        output.selectedID = Self.speakers.id
        service.refresh()
        #expect(service.headphoneStatuses.isEmpty)
        #expect(notices.count == 1)
    }

    @Test
    func coalescesDeviceRefreshesAndRejectsDisconnectedInflightResult() async throws {
        let output = HeadphoneOutputStub(devices: [Self.airPods], selectedID: Self.airPods.id)
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(88)], suspended: true)
        let service = Self.service(output: output, reader: reader)
        defer { service.stop(); Task { await reader.release() } }
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.start()
        try await Self.waitUntil { await reader.callCount == 1 }
        for _ in 0..<32 { service.refresh() }
        #expect(await reader.callCount == 1)
        output.devices = [Self.airPodsMax]
        output.selectedID = Self.airPodsMax.id
        await reader.setProfiles([Self.airPodsMax.name: Self.profile(55)])
        service.refresh()
        #expect(service.headphoneStatuses.map(\.device) == [Self.airPodsMax])
        #expect(service.headphoneStatuses.first?.battery == nil)
        await reader.release()
        try await Self.waitUntil { service.headphoneStatuses.first?.battery?.leftLevel == 55 }
        #expect(service.headphoneConnection?.device == Self.airPodsMax)
        #expect(await reader.callCount == 2)
        #expect(await reader.maximumConcurrentReads == 1)
    }

    @Test
    func disconnectReconnectRejectsBatteryFromPreviousDeviceSession() async throws {
        let output = HeadphoneOutputStub(devices: [Self.airPods], selectedID: Self.airPods.id)
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(99)], suspended: true)
        let service = Self.service(output: output, reader: reader)
        var publishedLevels: [Int] = []
        let subscription = service.$headphoneStatuses.sink { statuses in
            if let level = statuses.first?.battery?.leftLevel { publishedLevels.append(level) }
        }
        defer { service.stop(); subscription.cancel(); Task { await reader.release() } }
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.start()
        try await Self.waitUntil { await reader.callCount == 1 }
        output.devices = []
        output.selectedID = nil
        service.refresh()
        #expect(service.headphoneStatuses.isEmpty)
        output.devices = [Self.airPods]
        output.selectedID = Self.airPods.id
        service.refresh()
        await reader.setProfiles([Self.airPods.name: Self.profile(50)])
        await reader.release()
        try await Self.waitUntil { service.headphoneStatuses.first?.battery?.leftLevel == 50 }
        #expect(!publishedLevels.contains(99))
        #expect(service.headphoneConnection?.battery?.leftLevel == 50)
        #expect(await reader.callCount == 2)
    }

    @Test
    func disablingCancelsInflightAndTimerWithoutPublishingLateBattery() async throws {
        let output = HeadphoneOutputStub(devices: [Self.airPods], selectedID: Self.airPods.id)
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(99)], suspended: true)
        let clock = HeadphoneRefreshClock()
        let service = Self.service(output: output, reader: reader, clock: clock)
        defer { service.stop(); Task { await reader.release() } }
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.start()
        try await Self.waitUntil {
            let calls = await reader.callCount
            let pending = await clock.pendingCount
            return calls == 1 && pending == 1
        }
        service.setHeadphoneBatteryMonitoringEnabled(false)
        #expect(service.headphoneStatuses.isEmpty)
        try await Self.waitUntil {
            let cancellations = await reader.cancellationCount
            let pending = await clock.pendingCount
            return cancellations == 1 && pending == 0
        }
        await reader.release()
        try await Self.waitUntil { await reader.activeReads == 0 }
        service.refresh()
        #expect(service.headphoneStatuses.isEmpty)
        #expect(service.headphoneConnection == nil)
        #expect(await reader.callCount == 1)
    }

    @Test
    func disablingBeforeScheduledReadAvoidsReaderEntirely() async throws {
        let output = HeadphoneOutputStub(devices: [Self.airPods], selectedID: Self.airPods.id)
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(99)])
        let service = Self.service(output: output, reader: reader)
        defer { service.stop() }
        service.start()
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.setHeadphoneBatteryMonitoringEnabled(false)
        for _ in 0..<16 { await Task.yield() }
        #expect(await reader.callCount == 0)
        #expect(service.headphoneStatuses.isEmpty)
    }

    @Test
    func connectionNoticesRemainAvailableWhenBatteryMonitoringIsDisabled() async throws {
        let output = HeadphoneOutputStub(devices: [Self.speakers], selectedID: Self.speakers.id)
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(75)])
        let clock = HeadphoneRefreshClock()
        let service = Self.service(output: output, reader: reader, clock: clock)
        defer { service.stop() }
        service.start()
        output.devices.append(Self.airPods)
        service.refresh()
        try await Self.waitUntil { service.headphoneConnection?.battery?.leftLevel == 75 }
        #expect(service.headphoneStatuses.isEmpty)
        #expect(await clock.pendingCount == 0)
        service.refresh()
        #expect(await reader.callCount == 1)
    }

    @Test
    func disablingStatusMonitoringDoesNotCancelSharedConnectionNotice() async throws {
        let output = HeadphoneOutputStub(devices: [Self.speakers], selectedID: Self.speakers.id)
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(75)], suspended: true)
        let service = Self.service(output: output, reader: reader)
        defer { service.stop(); Task { await reader.release() } }
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.start()
        output.devices.append(Self.airPods)
        service.refresh()
        try await Self.waitUntil { await reader.callCount == 1 }
        service.setHeadphoneBatteryMonitoringEnabled(false)
        await reader.release()
        try await Self.waitUntil { service.headphoneConnection?.battery?.leftLevel == 75 }
        #expect(service.headphoneStatuses.isEmpty)
        #expect(await reader.cancellationCount == 0)
    }

    @Test
    func failedReadClearsOldBatteryAndNextRefreshRecovers() async throws {
        let output = HeadphoneOutputStub(devices: [Self.airPods], selectedID: Self.airPods.id)
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(90)])
        let clock = HeadphoneRefreshClock()
        let service = Self.service(output: output, reader: reader, clock: clock)
        defer { service.stop() }
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.start()
        try await Self.waitUntil { service.headphoneStatuses.first?.battery?.leftLevel == 90 }
        let statusID = try #require(service.headphoneStatuses.first?.id)
        await reader.setProfiles([:])
        service.refresh()
        try await Self.waitUntil { await reader.callCount == 2 && service.headphoneStatuses.first?.battery == nil }
        #expect(service.headphoneStatuses.first?.id == statusID)
        #expect(service.headphoneStatuses.first?.productID == nil)
        await reader.setProfiles([Self.airPods.name: Self.profile(45)])
        service.refresh()
        try await Self.waitUntil { service.headphoneStatuses.first?.battery?.leftLevel == 45 }
        #expect(service.headphoneConnection == nil)
    }

    @Test(arguments: 0..<8)
    func stopRestartRaceHasBoundedSerialReadsAndNoExpiredResults(iteration: Int) async throws {
        let output = HeadphoneOutputStub(devices: [Self.airPods], selectedID: Self.airPods.id)
        let reader = HeadphoneReaderStub(profiles: [Self.airPods.name: Self.profile(99)], suspended: true)
        let clock = HeadphoneRefreshClock()
        let service = Self.service(output: output, reader: reader, clock: clock)
        var publishedLevels: [Int] = []
        let subscription = service.$headphoneStatuses.sink { statuses in
            if let level = statuses.first?.battery?.leftLevel { publishedLevels.append(level) }
        }
        defer { service.stop(); subscription.cancel(); Task { await reader.release() } }
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.start()
        try await Self.waitUntil { await reader.callCount == 1 }
        service.stop()
        #expect(service.headphoneStatuses.isEmpty)
        try await Self.waitUntil {
            let cancellations = await reader.cancellationCount
            let pending = await clock.pendingCount
            return cancellations == 1 && pending == 0
        }
        service.setHeadphoneBatteryMonitoringEnabled(false)
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.start()
        for _ in 0..<8 { service.refresh() }
        #expect(await reader.callCount == 1)
        await reader.setProfiles([Self.airPods.name: Self.profile(20 + iteration)])
        await reader.release()
        try await Self.waitUntil { service.headphoneStatuses.first?.battery?.leftLevel == 20 + iteration }
        #expect(!publishedLevels.contains(99))
        #expect(await reader.callCount == 2)
        #expect(await reader.maximumConcurrentReads == 1)
        #expect(service.headphoneConnection == nil)
        service.stop()
        try await Self.waitUntil { await clock.pendingCount == 0 }
    }

    @Test
    func emptyAndWiredOutputsNeverRequestBluetoothBattery() async throws {
        let output = HeadphoneOutputStub(devices: [], selectedID: nil)
        let reader = HeadphoneReaderStub(profiles: [:])
        let clock = HeadphoneRefreshClock()
        let service = Self.service(output: output, reader: reader, clock: clock)
        defer { service.stop() }
        service.setHeadphoneBatteryMonitoringEnabled(true)
        service.start()
        #expect(service.headphoneStatuses.isEmpty)
        output.devices = [AudioOutputDevice(id: 4, name: "USB Headphones")]
        output.selectedID = 4
        service.stop()
        service.start()
        #expect(service.headphoneStatuses.count == 1)
        #expect(service.headphoneStatuses.first?.battery == nil)
        try await Self.waitUntil { await clock.pendingCount == 1 }
        await clock.tick()
        try await Self.waitUntil { await clock.pendingCount == 1 }
        #expect(await reader.callCount == 0)
    }

    private static let airPods = AudioOutputDevice(id: 1, name: "AirPods Pro", isBluetoothAudio: true)
    private static let airPodsMax = AudioOutputDevice(id: 2, name: "AirPods Max", isBluetoothAudio: true)
    private static let speakers = AudioOutputDevice(id: 10, name: "MacBook Pro Speakers")

    private static func profile(_ level: Int) -> HeadphoneBluetoothProfile {
        HeadphoneBluetoothProfile(
            battery: HeadphoneBatterySnapshot(leftLevel: level, rightLevel: nil, caseLevel: nil),
            productID: 0x2027
        )
    }

    private static func service(
        output: HeadphoneOutputStub,
        reader: HeadphoneReaderStub,
        clock: HeadphoneRefreshClock = HeadphoneRefreshClock()
    ) -> AudioOutputDeviceService {
        AudioOutputDeviceService(
            outputSnapshot: { (output.devices, output.selectedID) },
            bluetoothConnectionReader: { await reader.read($0) },
            batteryRefreshDelay: { try await clock.waitForTick() }
        )
    }

    private static func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw HeadphoneTestError.timedOut }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

@MainActor
private final class HeadphoneOutputStub {
    var devices: [AudioOutputDevice]
    var selectedID: UInt32?

    init(devices: [AudioOutputDevice], selectedID: UInt32?) {
        self.devices = devices
        self.selectedID = selectedID
    }
}

private actor HeadphoneReaderStub {
    private var profiles: [String: HeadphoneBluetoothProfile]
    private var suspended: Bool
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var requests: [[String]] = []
    private(set) var activeReads = 0
    private(set) var maximumConcurrentReads = 0
    private(set) var cancellationCount = 0
    var callCount: Int { requests.count }

    init(profiles: [String: HeadphoneBluetoothProfile], suspended: Bool = false) {
        self.profiles = profiles
        self.suspended = suspended
    }

    func read(_ names: [String]) async -> [String: HeadphoneBluetoothProfile] {
        requests.append(names)
        activeReads += 1
        maximumConcurrentReads = max(maximumConcurrentReads, activeReads)
        let result = profiles.filter { names.contains($0.key) }
        if suspended {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuations.append($0) }
            } onCancel: {
                Task { await self.recordCancellation() }
            }
        }
        activeReads -= 1
        return result
    }

    func setProfiles(_ profiles: [String: HeadphoneBluetoothProfile]) {
        self.profiles = profiles
    }

    func release() {
        suspended = false
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }

    private func recordCancellation() { cancellationCount += 1 }
}

private actor HeadphoneRefreshClock {
    private var nextID = 0
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    var pendingCount: Int { continuations.count }

    func waitForTick() async throws {
        try Task.checkCancellation()
        let identifier = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuations[identifier] = $0 }
        } onCancel: {
            Task { await self.cancel(identifier) }
        }
    }

    func tick() {
        guard let identifier = continuations.keys.min() else { return }
        continuations.removeValue(forKey: identifier)?.resume()
    }

    private func cancel(_ identifier: Int) {
        continuations.removeValue(forKey: identifier)?.resume(throwing: CancellationError())
    }
}

private enum HeadphoneTestError: Error {
    case timedOut
}
