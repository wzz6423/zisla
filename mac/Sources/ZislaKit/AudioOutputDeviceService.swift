import CoreAudio
import Foundation
import ZislaCore

public struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let name: String

    public init(id: UInt32, name: String) {
        self.id = id
        self.name = name
    }

    public var symbolName: String {
        if isHeadphones {
            return "headphones"
        }
        let normalized = name.lowercased()
        if normalized.contains("speaker") || normalized.contains("扬声器") {
            return "speaker.wave.2"
        }
        return "hifispeaker.2"
    }

    public var isHeadphones: Bool {
        let normalized = name.lowercased()
        return ["headphone", "earphone", "earbud", "airpod", "airpods", "buds", "beats", "耳机"]
            .contains { normalized.contains($0) }
    }
}

public struct HeadphoneBatterySnapshot: Equatable, Sendable {
    public var leftLevel: Int?
    public var rightLevel: Int?
    public var caseLevel: Int?

    public init(leftLevel: Int?, rightLevel: Int?, caseLevel: Int?) {
        self.leftLevel = Self.normalized(leftLevel)
        self.rightLevel = Self.normalized(rightLevel)
        self.caseLevel = Self.normalized(caseLevel)
    }

    public var noticeLevels: [NoticeBatteryLevel] {
        [
            NoticeBatteryLevel(label: "左", level: leftLevel),
            NoticeBatteryLevel(label: "右", level: rightLevel),
            NoticeBatteryLevel(label: "盒", level: caseLevel),
        ]
    }

    static func fromBluetoothProfile(_ data: Data, deviceName: String) -> HeadphoneBatterySnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reports = root["SPBluetoothDataType"] as? [[String: Any]]
        else {
            return nil
        }
        var connectedDevices: [(name: String, details: [String: Any])] = []
        for report in reports {
            for entry in report["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let details = value as? [String: Any] else { continue }
                    connectedDevices.append((name, details))
                }
            }
        }
        let normalizedName = Self.normalizedName(deviceName)
        let namedDevice = connectedDevices.first { name, _ in
            let candidate = Self.normalizedName(name)
            return candidate.contains(normalizedName) || normalizedName.contains(candidate)
        }
        let connectedHeadphones = connectedDevices.filter { _, details in
            details["device_minorType"] as? String == "Headphones"
        }
        let matchedDevice = namedDevice ?? (connectedHeadphones.count == 1 ? connectedHeadphones.first : nil)
        guard let (_, details) = matchedDevice else { return nil }

        let snapshot = HeadphoneBatterySnapshot(
            leftLevel: Self.percentage(details["device_batteryLevelLeft"]),
            rightLevel: Self.percentage(details["device_batteryLevelRight"]),
            caseLevel: Self.percentage(details["device_batteryLevelCase"])
        )
        return snapshot.leftLevel != nil || snapshot.rightLevel != nil || snapshot.caseLevel != nil
            ? snapshot
            : nil
    }

    private static func percentage(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return normalized(number.intValue) }
        guard let text = value as? String else { return nil }
        return normalized(Int(text.filter(\.isNumber)))
    }

    private static func normalized(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 100) }
    }

    private static func normalizedName(_ value: String) -> String {
        value.lowercased().components(separatedBy: .whitespacesAndNewlines).joined()
    }
}

public struct HeadphoneConnection: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let device: AudioOutputDevice
    public let battery: HeadphoneBatterySnapshot?

    public init(
        id: UUID = UUID(),
        device: AudioOutputDevice,
        battery: HeadphoneBatterySnapshot?
    ) {
        self.id = id
        self.device = device
        self.battery = battery
    }
}

@MainActor
public final class AudioOutputDeviceService: ObservableObject {
    @Published public private(set) var devices: [AudioOutputDevice] = []
    @Published public private(set) var selectedDeviceID: UInt32?
    @Published public private(set) var selectedDevice: AudioOutputDevice?
    @Published public private(set) var headphoneConnection: HeadphoneConnection?

    private var isMonitoring = false
    private var defaultOutputListenerInstalled = false
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var batteryTask: Task<Void, Never>?

    public init() {}

    public func refresh() {
        updateCurrentOutput(publishConnection: isMonitoring)
    }

    public func start() {
        guard !isMonitoring else { return }
        updateCurrentOutput(publishConnection: false)
        var address = Self.systemAddress(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        defaultOutputListenerInstalled = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        ) == noErr
        if defaultOutputListenerInstalled {
            defaultOutputListener = listener
        }
        isMonitoring = true
    }

    public func stop() {
        guard isMonitoring || defaultOutputListenerInstalled else { return }
        batteryTask?.cancel()
        batteryTask = nil
        if defaultOutputListenerInstalled, let defaultOutputListener {
            var address = Self.systemAddress(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                defaultOutputListener
            )
        }
        defaultOutputListener = nil
        defaultOutputListenerInstalled = false
        isMonitoring = false
    }

    @discardableResult
    public func select(_ device: AudioOutputDevice) -> Bool {
        var deviceID = device.id
        var address = Self.systemAddress(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        ) == noErr else {
            return false
        }
        refresh()
        return true
    }

    private func updateCurrentOutput(publishConnection: Bool) {
        let previousDevice = selectedDevice
        let deviceID = Self.defaultOutputDeviceID()
        let updatedDevices = Self.outputDevices(defaultID: deviceID)
        let currentDevice = updatedDevices.first { $0.id == deviceID }
        selectedDeviceID = deviceID
        devices = updatedDevices
        selectedDevice = currentDevice

        guard publishConnection,
              previousDevice?.id != currentDevice?.id,
              let currentDevice,
              currentDevice.isHeadphones
        else {
            return
        }
        publishHeadphoneConnection(for: currentDevice)
    }

    private func publishHeadphoneConnection(for device: AudioOutputDevice) {
        batteryTask?.cancel()
        batteryTask = Task { [weak self] in
            let battery = await Task.detached(priority: .utility) {
                Self.readBluetoothBattery(for: device.name)
            }.value
            guard !Task.isCancelled, self?.selectedDevice?.id == device.id else { return }
            self?.headphoneConnection = HeadphoneConnection(device: device, battery: battery)
        }
    }

    nonisolated private static func readBluetoothBattery(
        for deviceName: String
    ) -> HeadphoneBatterySnapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return HeadphoneBatterySnapshot.fromBluetoothProfile(
                output.fileHandleForReading.readDataToEndOfFile(),
                deviceName: deviceName
            )
        } catch {
            return nil
        }
    }

    private static func outputDevices(defaultID: UInt32?) -> [AudioOutputDevice] {
        var address = systemAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.compactMap { id in
            guard hasOutputStream(id), let name = deviceName(id) else { return nil }
            return AudioOutputDevice(id: id, name: name)
        }
        .sorted {
            if $0.id == defaultID { return true }
            if $1.id == defaultID { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func defaultOutputDeviceID() -> UInt32? {
        var address = systemAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return nil
        }
        return deviceID
    }

    private static func hasOutputStream(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size
        else {
            return false
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            rawBuffer
        ) == noErr else {
            return false
        }
        return rawBuffer.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers > 0
    }

    private static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = systemAddress(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr else {
            return nil
        }
        guard let name else { return nil }
        let value = name.takeUnretainedValue() as String
        return value.isEmpty ? nil : value
    }

    private static func systemAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
