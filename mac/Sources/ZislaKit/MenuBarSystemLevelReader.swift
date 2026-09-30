import CoreAudio
import CoreGraphics
import CoreWLAN
import Darwin

public enum MenuBarWiFiState: Equatable, Sendable {
    case unavailable
    case off
    case disconnected
    case connected(strength: Double)
}

public struct MenuBarSystemLevels: Equatable, Sendable {
    public var wifi: MenuBarWiFiState
    public var volume: Double?
    public var brightness: Double?

    public init(
        wifi: MenuBarWiFiState = .unavailable,
        volume: Double? = nil,
        brightness: Double? = nil
    ) {
        self.wifi = wifi
        self.volume = volume
        self.brightness = brightness
    }
}

public enum MenuBarSystemLevelReader {
    public static func read(includeVolume: Bool, includeBrightness: Bool) -> MenuBarSystemLevels {
        read(
            includeVolume: includeVolume,
            includeBrightness: includeBrightness,
            wifi: readWiFi,
            volume: readVolume,
            brightness: readBrightness
        )
    }

    static func read(
        includeVolume: Bool,
        includeBrightness: Bool,
        wifi: () -> MenuBarWiFiState,
        volume: () -> Double?,
        brightness: () -> Double?
    ) -> MenuBarSystemLevels {
        MenuBarSystemLevels(
            wifi: wifi(),
            volume: includeVolume ? volume() : nil,
            brightness: includeBrightness ? brightness() : nil
        )
    }

    static func wifiState(powerOn: Bool?, rssi: Int) -> MenuBarWiFiState {
        guard let powerOn else { return .unavailable }
        guard powerOn else { return .off }
        guard rssi != 0 else { return .disconnected }
        guard rssi < 0 else { return .unavailable }
        return .connected(strength: min(max((Double(rssi) + 100) / 50, 0), 1))
    }

    static func normalizedLevel(_ value: Double) -> Double? {
        guard value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }

    enum AudioProperty<Value> {
        case unsupported
        case failed
        case value(Value)
    }

    static func volume(
        deviceID: AudioDeviceID?,
        mute: (AudioDeviceID, AudioObjectPropertyElement) -> AudioProperty<UInt32>,
        scalar: (AudioDeviceID, AudioObjectPropertyElement) -> AudioProperty<Float32>,
        channelCount: (AudioDeviceID) -> UInt32?
    ) -> Double? {
        guard let deviceID, deviceID != kAudioObjectUnknown else { return nil }
        switch mute(deviceID, kAudioObjectPropertyElementMain) {
        case .value(let value) where value != 0: return 0
        case .failed: return nil
        default: break
        }
        switch scalar(deviceID, kAudioObjectPropertyElementMain) {
        case .value(let value): return normalizedLevel(Double(value))
        case .failed: return nil
        case .unsupported: break
        }
        guard let count = channelCount(deviceID), count > 0 else { return nil }
        var levels: [Double] = []
        for channel in 1...count {
            switch mute(deviceID, channel) {
            case .value(let value) where value != 0:
                levels.append(0)
                continue
            case .failed: return nil
            default: break
            }
            switch scalar(deviceID, channel) {
            case .value(let value):
                guard let level = normalizedLevel(Double(value)) else { return nil }
                levels.append(level)
            case .failed: return nil
            case .unsupported: continue
            }
        }
        guard !levels.isEmpty else { return nil }
        return levels.reduce(0, +) / Double(levels.count)
    }

    static func outputChannelCount(buffer: UnsafeRawPointer, byteCount: Int) -> UInt32? {
        let headerSize = MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.size
        guard byteCount >= headerSize else { return nil }
        let bufferCount = buffer.load(as: UInt32.self)
        guard bufferCount > 0,
              Int(bufferCount) <= (byteCount - headerSize) / MemoryLayout<AudioBuffer>.size
        else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: buffer.assumingMemoryBound(to: AudioBufferList.self))
        )
        var count: UInt32 = 0
        for audioBuffer in buffers {
            let (sum, overflow) = count.addingReportingOverflow(audioBuffer.mNumberChannels)
            guard !overflow else { return nil }
            count = sum
        }
        return count > 0 ? count : nil
    }

    static func brightness(
        displayIDs: [CGDirectDisplayID],
        mainDisplayID: CGDirectDisplayID,
        isBuiltin: (CGDirectDisplayID) -> Bool,
        readBrightness: (CGDirectDisplayID) -> Double?
    ) -> Double? {
        let builtin = displayIDs.first { $0 != kCGNullDirectDisplay && isBuiltin($0) }
        guard let displayID = builtin ?? (displayIDs.contains(mainDisplayID) ? mainDisplayID : nil),
              displayID != kCGNullDirectDisplay
        else { return nil }
        return readBrightness(displayID)
    }

    static func displayBrightness(
        displayID: CGDirectDisplayID,
        getter: ((CGDirectDisplayID, UnsafeMutablePointer<Float32>) -> Int32)?
    ) -> Double? {
        guard displayID != kCGNullDirectDisplay, let getter else { return nil }
        var value = Float32.nan
        guard getter(displayID, &value) == 0 else { return nil }
        return normalizedLevel(Double(value))
    }

    private static func readWiFi() -> MenuBarWiFiState {
        guard let interface = CWWiFiClient.shared().interface() else { return .unavailable }
        let powerOn = interface.powerOn()
        return wifiState(powerOn: powerOn, rssi: powerOn ? interface.rssiValue() : 0)
    }

    private static func readVolume() -> Double? {
        let deviceID: AudioDeviceID?
        switch audioProperty(
            object: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal,
            initialValue: AudioDeviceID()
        ) {
        case .value(let value): deviceID = value
        default: deviceID = nil
        }
        return volume(
            deviceID: deviceID,
            mute: { device, channel in
                audioProperty(
                    object: device,
                    selector: kAudioDevicePropertyMute,
                    element: channel,
                    initialValue: UInt32()
                )
            },
            scalar: { device, channel in
                audioProperty(
                    object: device,
                    selector: kAudioDevicePropertyVolumeScalar,
                    element: channel,
                    initialValue: Float32.nan
                )
            },
            channelCount: readOutputChannelCount
        )
    }

    private static func audioProperty<Value>(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        initialValue: Value
    ) -> AudioProperty<Value> {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return .unsupported }
        var value = initialValue
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, size == MemoryLayout<Value>.size
        else { return .failed }
        return .value(value)
    }

    private static func readOutputChannelCount(_ deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size
        else { return nil }
        let byteCount = Int(size)
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer) == noErr,
              size <= byteCount
        else { return nil }
        return outputChannelCount(buffer: buffer, byteCount: Int(size))
    }

    private static func readBrightness() -> Double? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return brightness(
            displayIDs: Array(displays.prefix(Int(count))),
            mainDisplayID: CGMainDisplayID(),
            isBuiltin: { CGDisplayIsBuiltin($0) != 0 },
            readBrightness: readDisplayBrightness
        )
    }

    private static func readDisplayBrightness(_ displayID: CGDirectDisplayID) -> Double? {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY | RTLD_LOCAL
        ) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float32>) -> Int32
        let getter = unsafeBitCast(symbol, to: Getter.self)
        return displayBrightness(displayID: displayID, getter: getter)
    }
}
