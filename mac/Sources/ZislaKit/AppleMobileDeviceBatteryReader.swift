import Darwin
import Foundation

// Adapted for Zisla from MacTools' Apache-2.0 DeviceBattery mobile-device reader.

enum AppleMobileDeviceCategory: Equatable, Sendable {
    case phone
    case tablet
    case watch
    case other

    var deviceType: NetworkBatteryDevice.DeviceType {
        switch self {
        case .phone: .iPhone
        case .tablet: .iPad
        case .watch: .appleWatch
        case .other: .accessory
        }
    }

    static func resolve(deviceClass: String?, productType: String) -> Self {
        let value = [deviceClass, productType]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if value.contains("iphone") || value.contains("mobilephone") { return .phone }
        if value.contains("ipad") || value.contains("tablet") { return .tablet }
        if value.contains("watch") { return .watch }
        return .other
    }
}

enum AppleMobileDeviceBatteryParser {
    static func device(
        identifier: String,
        name: String,
        productType: String,
        deviceClass: String?,
        connectionType: String,
        parentName: String? = nil,
        battery: [String: Any],
        now: Date = Date()
    ) -> NetworkBatteryDevice? {
        guard let level = batteryLevel(from: battery) else { return nil }
        let category = AppleMobileDeviceCategory.resolve(
            deviceClass: deviceClass,
            productType: productType
        )
        return NetworkBatteryDevice(
            identifier: "idevice:\(identifier)",
            name: name.isEmpty
                ? fallbackName(category: category, productType: productType)
                : name,
            deviceType: category.deviceType,
            batteryLevel: Double(level) / 100,
            isCharging: chargingState(from: battery),
            lastSeen: now,
            source: .iDevice,
            parentName: parentName,
            connectionDetail: connectionType.isEmpty ? nil : connectionType
        )
    }

    static func batteryLevel(from battery: [String: Any]) -> Int? {
        if let capacity = intValue(battery["BatteryCurrentCapacity"]),
           (0...100).contains(capacity) {
            return capacity
        }

        let current = firstPositiveInt(
            battery["AppleRawCurrentCapacity"],
            battery["CurrentCapacity"]
        )
        let maximum = firstPositiveInt(
            battery["AppleRawMaxCapacity"],
            battery["NominalChargeCapacity"],
            battery["MaxCapacity"]
        )
        guard let current, let maximum, maximum > 0 else { return nil }
        return min(max(Int((Double(current) / Double(maximum) * 100).rounded()), 0), 100)
    }

    private static func chargingState(from battery: [String: Any]) -> Bool {
        boolValue(battery["BatteryIsCharging"])
            || boolValue(battery["IsCharging"])
    }

    private static func fallbackName(
        category: AppleMobileDeviceCategory,
        productType: String
    ) -> String {
        switch category {
        case .phone: "iPhone"
        case .tablet: "iPad"
        case .watch: "Apple Watch"
        case .other: productType.isEmpty ? "Apple 设备" : productType
        }
    }

    private static func firstPositiveInt(_ values: Any?...) -> Int? {
        values.lazy.compactMap(intValue).first { $0 > 0 }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let value = value as? Bool { return value }
        if let value = value as? String {
            return value.caseInsensitiveCompare("true") == .orderedSame
                || value.caseInsensitiveCompare("yes") == .orderedSame
                || value == "1"
        }
        return false
    }
}

enum AppleMobileDeviceBatteryReader {
    static func readDevices() -> [NetworkBatteryDevice] {
        AppleMobileDeviceBridge.readDevices()
    }
}

private enum AppleMobileDeviceBridge {
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"
    private static let success: Int32 = 0
    private static let serviceTimeoutSeconds = 2
    private static let lock = NSLock()

    private typealias DevicePointer = UnsafeMutableRawPointer
    private typealias CreateDeviceListFunction = @convention(c) () -> Unmanaged<CFArray>?
    private typealias DeviceResultFunction = @convention(c) (DevicePointer) -> Int32
    private typealias CopyDeviceIdentifierFunction =
        @convention(c) (DevicePointer) -> Unmanaged<CFString>?
    private typealias CopyValueFunction =
        @convention(c) (DevicePointer, CFString?, CFString?) -> Unmanaged<CFTypeRef>?
    private typealias StartServiceFunction = @convention(c) (
        DevicePointer,
        CFString,
        CFDictionary?,
        UnsafeMutablePointer<DevicePointer?>
    ) -> Int32
    private typealias SendMessageFunction = @convention(c) (
        DevicePointer,
        CFTypeRef,
        CFPropertyListFormat
    ) -> Int32
    private typealias ReceiveMessageFunction = @convention(c) (
        DevicePointer,
        UnsafeMutablePointer<Unmanaged<CFTypeRef>?>,
        UnsafeMutablePointer<CFPropertyListFormat>
    ) -> Int32

    private struct Symbols: @unchecked Sendable {
        let createDeviceList: CreateDeviceListFunction
        let connect: DeviceResultFunction
        let disconnect: DeviceResultFunction
        let validatePairing: DeviceResultFunction
        let startSession: DeviceResultFunction
        let stopSession: DeviceResultFunction
        let interfaceType: DeviceResultFunction
        let copyDeviceIdentifier: CopyDeviceIdentifierFunction
        let copyValue: CopyValueFunction
        let startService: StartServiceFunction
        let sendMessage: SendMessageFunction
        let receiveMessage: ReceiveMessageFunction
        let invalidateConnection: DeviceResultFunction
        let connectionSocket: DeviceResultFunction
    }

    private static let symbols = loadSymbols()

    static func readDevices() -> [NetworkBatteryDevice] {
        lock.lock()
        defer { lock.unlock() }

        guard let symbols,
              let unmanagedList = symbols.createDeviceList()
        else {
            return []
        }

        let list = unmanagedList.takeRetainedValue()
        var devices: [NetworkBatteryDevice] = []
        for index in 0..<CFArrayGetCount(list) {
            guard let value = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: value)
            devices.append(contentsOf: readDevice(device, symbols: symbols))
        }
        return devices
    }

    private static func readDevice(
        _ device: DevicePointer,
        symbols: Symbols
    ) -> [NetworkBatteryDevice] {
        guard symbols.connect(device) == success else { return [] }
        defer { _ = symbols.disconnect(device) }

        guard symbols.validatePairing(device) == success,
              symbols.startSession(device) == success
        else {
            return []
        }
        defer { _ = symbols.stopSession(device) }

        let identifier = symbols.copyDeviceIdentifier(device)?
            .takeRetainedValue() as String? ?? ""
        guard !identifier.isEmpty else { return [] }

        let name = copiedString("DeviceName", device: device, symbols: symbols)
        let productType = copiedString("ProductType", device: device, symbols: symbols)
        let deviceClass = copiedString("DeviceClass", device: device, symbols: symbols)
        let connectionType = connectionLabel(symbols.interfaceType(device))
        let directBattery = copiedDictionary(
            domain: "com.apple.mobile.battery",
            key: nil,
            device: device,
            symbols: symbols
        )
        let battery = directBattery.flatMap {
            AppleMobileDeviceBatteryParser.batteryLevel(from: $0) == nil ? nil : $0
        } ?? readIORegistryBattery(device: device, symbols: symbols)

        var devices: [NetworkBatteryDevice] = []
        if let battery,
           let parsed = AppleMobileDeviceBatteryParser.device(
               identifier: opaqueIdentifier(identifier),
               name: name,
               productType: productType,
               deviceClass: deviceClass,
               connectionType: connectionType,
               battery: battery
           ) {
            devices.append(parsed)
        }

        if AppleMobileDeviceCategory.resolve(
            deviceClass: deviceClass,
            productType: productType
        ) == .phone {
            devices.append(contentsOf: readPairedWatches(
                device: device,
                parentName: name,
                connectionType: connectionType,
                symbols: symbols
            ))
        }
        return devices
    }

    private static func readPairedWatches(
        device: DevicePointer,
        parentName: String,
        connectionType: String,
        symbols: Symbols
    ) -> [NetworkBatteryDevice] {
        guard let registry = sendServiceRequest(
            service: "com.apple.companion_proxy",
            request: ["Command": "GetDeviceRegistry"],
            format: .binaryFormat_v1_0,
            device: device,
            symbols: symbols
        ),
            let identifiers = registry["PairedDevicesArray"] as? [String]
        else {
            return []
        }

        return identifiers.compactMap { watchIdentifier in
            var values: [String: Any] = [:]
            for key in ["DeviceName", "ProductType", "BatteryCurrentCapacity", "BatteryIsCharging"] {
                if let value = companionValue(
                    watchIdentifier: watchIdentifier,
                    key: key,
                    device: device,
                    symbols: symbols
                ) {
                    values[key] = value
                }
            }
            return AppleMobileDeviceBatteryParser.device(
                identifier: "watch-\(opaqueIdentifier(watchIdentifier))",
                name: values["DeviceName"] as? String ?? "Apple Watch",
                productType: values["ProductType"] as? String ?? "Watch",
                deviceClass: "Watch",
                connectionType: connectionType,
                parentName: parentName.isEmpty ? nil : parentName,
                battery: values
            )
        }
    }

    private static func companionValue(
        watchIdentifier: String,
        key: String,
        device: DevicePointer,
        symbols: Symbols
    ) -> Any? {
        guard let response = sendServiceRequest(
            service: "com.apple.companion_proxy",
            request: [
                "Command": "GetValueFromRegistry",
                "GetValueGizmoUDIDKey": watchIdentifier,
                "GetValueKeyKey": key,
            ],
            format: .binaryFormat_v1_0,
            device: device,
            symbols: symbols
        ),
            let dictionary = response["RetrievedValueDictionary"] as? [String: Any]
        else {
            return nil
        }
        return dictionary[key]
    }

    private static func readIORegistryBattery(
        device: DevicePointer,
        symbols: Symbols
    ) -> [String: Any]? {
        guard let response = sendServiceRequest(
            service: "com.apple.mobile.diagnostics_relay",
            request: [
                "Request": "IORegistry",
                "EntryClass": "AppleSmartBattery",
            ],
            format: .xmlFormat_v1_0,
            device: device,
            symbols: symbols
        ),
            response["Status"] as? String == "Success",
            let diagnostics = response["Diagnostics"] as? [String: Any],
            let registry = diagnostics["IORegistry"] as? [String: Any]
        else {
            return nil
        }
        return registry
    }

    private static func sendServiceRequest(
        service: String,
        request: [String: Any],
        format: CFPropertyListFormat,
        device: DevicePointer,
        symbols: Symbols
    ) -> [String: Any]? {
        var connection: DevicePointer?
        guard symbols.startService(device, service as CFString, nil, &connection) == success,
              let connection
        else {
            return nil
        }
        defer { _ = symbols.invalidateConnection(connection) }

        configureTimeout(on: connection, symbols: symbols)
        guard symbols.sendMessage(connection, request as CFDictionary, format) == success else {
            return nil
        }

        var response: Unmanaged<CFTypeRef>?
        var responseFormat = format
        guard symbols.receiveMessage(connection, &response, &responseFormat) == success else {
            return nil
        }
        return response?.takeRetainedValue() as? [String: Any]
    }

    private static func configureTimeout(on connection: DevicePointer, symbols: Symbols) {
        let socket = symbols.connectionSocket(connection)
        guard socket >= 0 else { return }
        var timeout = timeval(tv_sec: serviceTimeoutSeconds, tv_usec: 0)
        withUnsafePointer(to: &timeout) { pointer in
            _ = setsockopt(
                socket,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            )
            _ = setsockopt(
                socket,
                SOL_SOCKET,
                SO_SNDTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }
    }

    private static func copiedString(
        _ key: String,
        device: DevicePointer,
        symbols: Symbols
    ) -> String {
        symbols.copyValue(device, nil, key as CFString)?
            .takeRetainedValue() as? String ?? ""
    }

    private static func copiedDictionary(
        domain: String?,
        key: String?,
        device: DevicePointer,
        symbols: Symbols
    ) -> [String: Any]? {
        symbols.copyValue(device, domain as CFString?, key as CFString?)?
            .takeRetainedValue() as? [String: Any]
    }

    private static func connectionLabel(_ type: Int32) -> String {
        switch type {
        case 1: "USB"
        case 2, 3: "Wi-Fi"
        default: ""
        }
    }

    private static func opaqueIdentifier(_ identifier: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func loadSymbols() -> Symbols? {
        guard let handle = dlopen(frameworkPath, RTLD_NOW | RTLD_LOCAL) else { return nil }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        guard let createDeviceList = symbol("AMDCreateDeviceList", as: CreateDeviceListFunction.self),
              let connect = symbol("AMDeviceConnect", as: DeviceResultFunction.self),
              let disconnect = symbol("AMDeviceDisconnect", as: DeviceResultFunction.self),
              let validatePairing = symbol("AMDeviceValidatePairing", as: DeviceResultFunction.self),
              let startSession = symbol("AMDeviceStartSession", as: DeviceResultFunction.self),
              let stopSession = symbol("AMDeviceStopSession", as: DeviceResultFunction.self),
              let interfaceType = symbol("AMDeviceGetInterfaceType", as: DeviceResultFunction.self),
              let copyDeviceIdentifier = symbol(
                  "AMDeviceCopyDeviceIdentifier",
                  as: CopyDeviceIdentifierFunction.self
              ),
              let copyValue = symbol("AMDeviceCopyValue", as: CopyValueFunction.self),
              let startService = symbol("AMDeviceSecureStartService", as: StartServiceFunction.self),
              let sendMessage = symbol(
                  "AMDServiceConnectionSendMessage",
                  as: SendMessageFunction.self
              ),
              let receiveMessage = symbol(
                  "AMDServiceConnectionReceiveMessage",
                  as: ReceiveMessageFunction.self
              ),
              let invalidateConnection = symbol(
                  "AMDServiceConnectionInvalidate",
                  as: DeviceResultFunction.self
              ),
              let connectionSocket = symbol(
                  "AMDServiceConnectionGetSocket",
                  as: DeviceResultFunction.self
              )
        else {
            dlclose(handle)
            return nil
        }

        return Symbols(
            createDeviceList: createDeviceList,
            connect: connect,
            disconnect: disconnect,
            validatePairing: validatePairing,
            startSession: startSession,
            stopSession: stopSession,
            interfaceType: interfaceType,
            copyDeviceIdentifier: copyDeviceIdentifier,
            copyValue: copyValue,
            startService: startService,
            sendMessage: sendMessage,
            receiveMessage: receiveMessage,
            invalidateConnection: invalidateConnection,
            connectionSocket: connectionSocket
        )
    }
}
