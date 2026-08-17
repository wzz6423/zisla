import Foundation
import Testing

@testable import ZislaKit

struct NetworkBatteryMonitorTests {
    @Test
    func parsesConnectedBluetoothBatteryDevices() throws {
        let data = try #require(bluetoothFixture.data(using: .utf8))
        let devices = NetworkBatteryMonitor.devices(
            fromBluetoothProfile: data,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(devices.count == 2)
        let airPods = try #require(devices.first { $0.name == "AirPods Pro" })
        #expect(airPods.deviceType == .airPods)
        #expect(airPods.batteryPercentInt == 61)
        #expect(airPods.components.map(\.percentInt) == [82, 61, 70])
        #expect(airPods.source == .bluetooth)

        let keyboard = try #require(devices.first { $0.name == "Magic Keyboard" })
        #expect(keyboard.deviceType == .keyboard)
        #expect(keyboard.batteryPercentInt == 73)
    }

    @Test
    func ignoresMalformedOrBatterylessBluetoothEntries() {
        #expect(NetworkBatteryMonitor.devices(fromBluetoothProfile: Data("{}".utf8)).isEmpty)
        let batteryless = Data("""
        {"SPBluetoothDataType":[{"device_connected":[{"Phone":{"device_minorType":"Phone"}}]}]}
        """.utf8)
        #expect(NetworkBatteryMonitor.devices(fromBluetoothProfile: batteryless).isEmpty)
    }

    @Test
    func parsesExternalMagicAccessoryFromIORegistry() throws {
        let target = BluetoothBatteryTarget(
            identifier: "aabbccddeeff",
            name: "工作室键盘",
            deviceType: .keyboard,
            isConnected: true,
            supportsAppleHeadphoneAdvertisement: false
        )

        let device = try #require(NetworkBatteryMonitor.magicAccessoryDevice(
            fromIORegistryProperties: [
                "BatteryPercent": 84,
                "BatteryStatusFlags": 1,
                "DeviceAddress": "AA-BB-CC-DD-EE-FF",
                "Product": "Magic Keyboard",
            ],
            serviceClass: "AppleDeviceManagementHIDEventService",
            targets: [target],
            now: Date(timeIntervalSince1970: 100)
        ))

        #expect(device.identifier == "bluetooth:aabbccddeeff")
        #expect(device.name == "工作室键盘")
        #expect(device.deviceType == .keyboard)
        #expect(device.batteryPercentInt == 84)
        #expect(device.isCharging)
        #expect(device.connectionDetail == "已连接")
    }

    @Test
    func ignoresInternalOrInvalidIORegistryBatteryEntries() {
        let internalDevice = NetworkBatteryMonitor.magicAccessoryDevice(
            fromIORegistryProperties: [
                "BatteryPercent": 100,
                "Product": "Apple Internal Keyboard / Trackpad",
            ],
            serviceClass: "AppleDeviceManagementHIDEventService",
            targets: []
        )
        let invalidBattery = NetworkBatteryMonitor.magicAccessoryDevice(
            fromIORegistryProperties: [
                "BatteryPercent": 101,
                "Product": "Magic Mouse",
            ],
            serviceClass: "BNBMouseDevice",
            targets: []
        )

        #expect(internalDevice == nil)
        #expect(invalidBattery == nil)
    }

    @Test
    func keepsKnownBatterylessAccessoriesAsActiveScanTargets() throws {
        let data = Data("""
        {
          "SPBluetoothDataType": [{
            "device_connected": [{
              "Generic Buds": {
                "device_minorType": "Headphones",
                "device_address": "AA-BB-CC-DD-EE-FF"
              }
            }],
            "device_not_connected": [{
              "Travel AirPods": {
                "device_minorType": "Headphones",
                "device_vendorID": "0x004C"
              }
            }]
          }]
        }
        """.utf8)

        let discovery = NetworkBatteryMonitor.bluetoothDiscovery(from: data)

        #expect(discovery.devices.isEmpty)
        #expect(discovery.targets.count == 2)
        let buds = try #require(discovery.targets.first { $0.name == "Generic Buds" })
        #expect(buds.identifier == "aabbccddeeff")
        #expect(buds.isConnected)
        #expect(!buds.supportsAppleHeadphoneAdvertisement)
        let airPods = try #require(discovery.targets.first { $0.name == "Travel AirPods" })
        #expect(!airPods.isConnected)
        #expect(airPods.supportsAppleHeadphoneAdvertisement)
    }

    @Test
    func mergesBluetoothReadingsAndKeepsTheRicherFreshSnapshot() throws {
        let profile = NetworkBatteryDevice(
            identifier: "bluetooth:aabbcc",
            name: "AirPods Pro",
            deviceType: .airPods,
            batteryLevel: 0.70,
            isCharging: false,
            lastSeen: Date(timeIntervalSince1970: 10),
            connectionDetail: "已连接"
        )
        let advertisement = NetworkBatteryDevice(
            identifier: "apple-headphone:aabbcc",
            name: "airpods pro",
            deviceType: .airPods,
            batteryLevel: 0.42,
            isCharging: true,
            lastSeen: Date(timeIntervalSince1970: 20),
            components: [
                BatteryLevelComponent(kind: .left, level: 0.80),
                BatteryLevelComponent(kind: .right, level: 0.42),
            ],
            connectionDetail: "BLE"
        )

        let merged = try #require(NetworkBatteryMonitor.mergedDevices([
            profile,
            advertisement,
        ]).first)

        #expect(NetworkBatteryMonitor.mergedDevices([profile, advertisement]).count == 1)
        #expect(merged.identifier == profile.identifier)
        #expect(merged.batteryPercentInt == 42)
        #expect(merged.components.map(\.percentInt) == [80, 42])
        #expect(merged.isCharging)
        #expect(merged.connectionDetail == "BLE")
    }

    @Test
    func clampsDeviceAndComponentLevels() {
        let device = NetworkBatteryDevice(
            identifier: "test",
            name: "Test",
            deviceType: .accessory,
            batteryLevel: 1.5,
            isCharging: false,
            components: [BatteryLevelComponent(kind: .left, level: -0.2)]
        )

        #expect(device.batteryPercentInt == 100)
        #expect(device.components.first?.percentInt == 0)
    }

    @Test
    func choosesBatterySymbolsAtStableThresholds() {
        let cases: [(Double, Bool, String)] = [
            (0.05, false, "battery.0percent"),
            (0.20, false, "battery.25percent"),
            (0.45, false, "battery.50percent"),
            (0.70, false, "battery.75percent"),
            (0.95, false, "battery.100percent"),
            (0.50, true, "battery.100percent.bolt"),
        ]

        for (level, charging, expected) in cases {
            let device = NetworkBatteryDevice(
                identifier: "test",
                name: "Test",
                deviceType: .unknown,
                batteryLevel: level,
                isCharging: charging
            )
            #expect(device.batterySymbolName == expected)
        }
    }

    @MainActor
    @Test
    func refreshPublishesInjectedAccessoryReaderResult() async {
        let expected = NetworkBatteryDevice(
            identifier: "bluetooth:test",
            name: "Test Headphones",
            deviceType: .headphones,
            batteryLevel: 0.42,
            isCharging: false
        )
        let monitor = NetworkBatteryMonitor(
            accessoryReader: { [expected] in [expected] }
        )

        monitor.refresh()
        let refreshFinished = await waitForRefreshToFinish(monitor)

        #expect(refreshFinished)
        #expect(monitor.devices == [expected])
        #expect(!monitor.isScanning)
        monitor.stop()
    }

    @MainActor
    @Test
    func ignoresAStaleRefreshAfterRestart() async {
        let gate = AccessoryReaderGate()
        let stale = device(named: "Stale")
        let fresh = device(named: "Fresh")
        let monitor = NetworkBatteryMonitor(
            accessoryReader: { await gate.read() }
        )

        monitor.refresh()
        let firstReadStarted = await waitForPendingReads(1, in: gate)
        #expect(firstReadStarted)
        guard firstReadStarted else {
            await gate.resumeAll(with: [])
            monitor.stop()
            return
        }
        monitor.stop()
        monitor.refresh()
        let secondReadStarted = await waitForPendingReads(2, in: gate)
        #expect(secondReadStarted)
        guard secondReadStarted else {
            await gate.resumeAll(with: [])
            monitor.stop()
            return
        }

        await gate.resumeNext(with: [stale])
        try? await Task.sleep(for: .milliseconds(10))
        #expect(monitor.isScanning)
        #expect(monitor.devices.isEmpty)

        await gate.resumeNext(with: [fresh])
        let refreshFinished = await waitForRefreshToFinish(monitor)
        #expect(refreshFinished)
        #expect(monitor.devices == [fresh])
        await gate.resumeAll(with: [])
        monitor.stop()
    }

    private func device(named name: String) -> NetworkBatteryDevice {
        NetworkBatteryDevice(
            identifier: "bluetooth:\(name.lowercased())",
            name: name,
            deviceType: .headphones,
            batteryLevel: 0.5,
            isCharging: false
        )
    }

    private func waitForPendingReads(_ count: Int, in gate: AccessoryReaderGate) async -> Bool {
        for _ in 0..<500 {
            if await gate.pendingCount() == count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @MainActor
    private func waitForRefreshToFinish(_ monitor: NetworkBatteryMonitor) async -> Bool {
        for _ in 0..<500 {
            if !monitor.isScanning { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private var bluetoothFixture: String {
        """
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "AirPods Pro": {
                    "device_minorType": "Headphones",
                    "device_batteryLevelLeft": "82%",
                    "device_batteryLevelRight": "61%",
                    "device_batteryLevelCase": "70%"
                  }
                },
                {
                  "Magic Keyboard": {
                    "device_minorType": "Keyboard",
                    "device_batteryLevelMain": "73%"
                  }
                },
                {
                  "No Battery": {
                    "device_minorType": "Phone"
                  }
                }
              ]
            }
          ]
        }
        """
    }
}

private actor AccessoryReaderGate {
    private var continuations: [CheckedContinuation<[NetworkBatteryDevice], Never>] = []

    func read() async -> [NetworkBatteryDevice] {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func pendingCount() -> Int {
        continuations.count
    }

    func resumeNext(with devices: [NetworkBatteryDevice]) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: devices)
    }

    func resumeAll(with devices: [NetworkBatteryDevice]) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: devices) }
    }
}
