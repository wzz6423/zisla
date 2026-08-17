import CoreBluetooth
import Foundation

// The Apple headphone packet parser follows MacTools' Apache-2.0 implementation.

struct BluetoothBatteryTarget: Equatable, Sendable {
    let identifier: String
    let name: String
    let deviceType: NetworkBatteryDevice.DeviceType
    let isConnected: Bool
    let supportsAppleHeadphoneAdvertisement: Bool
}

struct AppleHeadphoneAdvertisementReading: Equatable, Sendable {
    let component: BatteryLevelComponent.Kind
    let level: Int
    let isCharging: Bool
}

enum AppleHeadphoneAdvertisementParser {
    static func readings(from manufacturerData: Data) -> [AppleHeadphoneAdvertisementReading] {
        let bytes = [UInt8](manufacturerData)
        guard bytes.count >= 2, bytes[0] == 0x4C, bytes[1] == 0x00 else { return [] }

        switch bytes.count {
        case 29 where bytes[2] == 0x07:
            let flip = (bytes[7] & 0x02) == 0
            return [
                reading(component: .caseBattery, rawLevel: bytes[16]),
                reading(component: .left, rawLevel: bytes[flip ? 15 : 14]),
                reading(component: .right, rawLevel: bytes[flip ? 14 : 15]),
            ].compactMap { $0 }
        case 25 where bytes[2] == 0x12:
            return [
                reading(component: .caseBattery, rawLevel: bytes[12]),
                reading(component: .left, rawLevel: bytes[13]),
                reading(component: .right, rawLevel: bytes[14]),
            ].compactMap { $0 }
        default:
            return []
        }
    }

    private static func reading(
        component: BatteryLevelComponent.Kind,
        rawLevel: UInt8
    ) -> AppleHeadphoneAdvertisementReading? {
        guard rawLevel != 0xFF else { return nil }
        let level = Int(rawLevel & 0x7F)
        guard (0...100).contains(level) else { return nil }
        return AppleHeadphoneAdvertisementReading(
            component: component,
            level: level,
            isCharging: rawLevel > 100
        )
    }
}

@MainActor
final class BluetoothBatteryScanner: NSObject,
    @preconcurrency CBCentralManagerDelegate,
    @preconcurrency CBPeripheralDelegate {
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevelCharacteristic = CBUUID(string: "2A19")

    private let targets: [BluetoothBatteryTarget]
    private let referenceDate: Date
    private var centralManager: CBCentralManager?
    private var continuation: CheckedContinuation<[NetworkBatteryDevice], Never>?
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var targetsByPeripheralID: [UUID: BluetoothBatteryTarget] = [:]
    private var connectionsStartedByReader: Set<UUID> = []
    private var gattLevelsByTargetID: [String: Int] = [:]
    private var advertisementReadingsByTargetID:
        [String: [BatteryLevelComponent.Kind: AppleHeadphoneAdvertisementReading]] = [:]
    private var timeoutTask: Task<Void, Never>?
    private var didFinish = false

    static func collectBatteryDevices(
        targets: [BluetoothBatteryTarget],
        referenceDate: Date = Date()
    ) async -> [NetworkBatteryDevice] {
        guard !targets.isEmpty else { return [] }
        let scanner = BluetoothBatteryScanner(targets: targets, referenceDate: referenceDate)
        return await withTaskCancellationHandler {
            await scanner.collect()
        } onCancel: {
            Task { @MainActor in scanner.finish() }
        }
    }

    private init(targets: [BluetoothBatteryTarget], referenceDate: Date) {
        self.targets = targets
        self.referenceDate = referenceDate
        super.init()
    }

    private func collect() async -> [NetworkBatteryDevice] {
        await withCheckedContinuation { continuation in
            guard !Task.isCancelled else {
                continuation.resume(returning: [])
                return
            }
            self.continuation = continuation
            centralManager = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.finish()
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            if central.state != .unknown, central.state != .resetting { finish() }
            return
        }

        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.batteryService]) {
            guard let target = target(for: peripheral, advertisedName: nil) else { continue }
            register(peripheral, target: target, central: central)
        }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let target = target(for: peripheral, advertisedName: advertisedName) else { return }

        if target.supportsAppleHeadphoneAdvertisement,
           let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            let readings = AppleHeadphoneAdvertisementParser.readings(from: data)
            if !readings.isEmpty {
                var components = advertisementReadingsByTargetID[target.identifier] ?? [:]
                for reading in readings { components[reading.component] = reading }
                advertisementReadingsByTargetID[target.identifier] = components
            }
        }

        if target.isConnected, !target.supportsAppleHeadphoneAdvertisement {
            register(peripheral, target: target, central: central)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectionsStartedByReader.remove(peripheral.identifier)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService })
        else {
            return
        }
        peripheral.discoverCharacteristics([Self.batteryLevelCharacteristic], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil,
              let characteristic = service.characteristics?.first(where: {
                  $0.uuid == Self.batteryLevelCharacteristic
              })
        else {
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == Self.batteryLevelCharacteristic,
              let level = characteristic.value?.first,
              level <= 100,
              let target = targetsByPeripheralID[peripheral.identifier]
        else {
            return
        }
        gattLevelsByTargetID[target.identifier] = Int(level)
    }

    private func register(
        _ peripheral: CBPeripheral,
        target: BluetoothBatteryTarget,
        central: CBCentralManager
    ) {
        guard peripheralsByID[peripheral.identifier] == nil else { return }
        peripheralsByID[peripheral.identifier] = peripheral
        targetsByPeripheralID[peripheral.identifier] = target
        peripheral.delegate = self

        if peripheral.state == .connected {
            peripheral.discoverServices([Self.batteryService])
        } else {
            connectionsStartedByReader.insert(peripheral.identifier)
            central.connect(peripheral, options: nil)
        }
    }

    private func target(
        for peripheral: CBPeripheral,
        advertisedName: String?
    ) -> BluetoothBatteryTarget? {
        let candidate = peripheral.name ?? advertisedName
        guard let candidate else { return nil }
        let normalizedCandidate = Self.normalizedName(candidate)
        if let exact = targets.first(where: { Self.normalizedName($0.name) == normalizedCandidate }) {
            return exact
        }
        let matches = targets.filter {
            let name = Self.normalizedName($0.name)
            return name.contains(normalizedCandidate) || normalizedCandidate.contains(name)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        timeoutTask?.cancel()
        timeoutTask = nil
        centralManager?.stopScan()
        for identifier in connectionsStartedByReader {
            if let peripheral = peripheralsByID[identifier] {
                centralManager?.cancelPeripheralConnection(peripheral)
            }
        }
        peripheralsByID.values.forEach { $0.delegate = nil }

        let devices = batteryDevices()
        let continuation = continuation
        self.continuation = nil
        centralManager = nil
        continuation?.resume(returning: devices)
    }

    private func batteryDevices() -> [NetworkBatteryDevice] {
        var devices: [NetworkBatteryDevice] = []
        for (targetID, level) in gattLevelsByTargetID {
            guard let target = targets.first(where: { $0.identifier == targetID }) else { continue }
            devices.append(NetworkBatteryDevice(
                identifier: "ble:\(target.identifier)",
                name: target.name,
                deviceType: target.deviceType,
                batteryLevel: Double(level) / 100,
                isCharging: false,
                lastSeen: referenceDate,
                source: .bluetooth,
                connectionDetail: "BLE"
            ))
        }

        for (targetID, readingsByComponent) in advertisementReadingsByTargetID {
            guard let target = targets.first(where: { $0.identifier == targetID }) else { continue }
            let readings = readingsByComponent.values.sorted {
                Self.componentRank($0.component) < Self.componentRank($1.component)
            }
            guard let primaryLevel = readings.map(\.level).min() else { continue }
            devices.append(NetworkBatteryDevice(
                identifier: "apple-headphone:\(target.identifier)",
                name: target.name,
                deviceType: target.deviceType,
                batteryLevel: Double(primaryLevel) / 100,
                isCharging: readings.contains(where: \.isCharging),
                lastSeen: referenceDate,
                source: .bluetooth,
                components: readings.map {
                    BatteryLevelComponent(kind: $0.component, level: Double($0.level) / 100)
                },
                connectionDetail: "BLE"
            ))
        }
        return devices
    }

    private static func componentRank(_ kind: BatteryLevelComponent.Kind) -> Int {
        switch kind {
        case .left: 0
        case .right: 1
        case .caseBattery: 2
        case .main: 3
        }
    }
}
