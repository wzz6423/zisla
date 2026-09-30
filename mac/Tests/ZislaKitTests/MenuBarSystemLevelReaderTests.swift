import CoreAudio
import CoreGraphics
import Testing

@testable import ZislaKit

struct MenuBarSystemLevelReaderTests {
    @Test
    func snapshotDefaultsAndPublicValues() {
        #expect(MenuBarSystemLevels() == MenuBarSystemLevels(wifi: .unavailable))
        var levels = MenuBarSystemLevels(wifi: .off, volume: 0.5, brightness: 1)
        levels.wifi = .connected(strength: 0.5)
        levels.volume = nil
        levels.brightness = 0
        #expect(levels == MenuBarSystemLevels(wifi: .connected(strength: 0.5), brightness: 0))
    }

    @Test(arguments: [false, true], [false, true])
    func optionalReadGates(includeVolume: Bool, includeBrightness: Bool) {
        let levels = MenuBarSystemLevelReader.read(
            includeVolume: includeVolume,
            includeBrightness: includeBrightness,
            wifi: { .disconnected },
            volume: {
                #expect(includeVolume)
                return 0.25
            },
            brightness: {
                #expect(includeBrightness)
                return 0.75
            }
        )
        #expect(levels == MenuBarSystemLevels(
            wifi: .disconnected,
            volume: includeVolume ? 0.25 : nil,
            brightness: includeBrightness ? 0.75 : nil
        ))
    }

    @Test
    func unavailableReadersDoNotInventZero() {
        let levels = MenuBarSystemLevelReader.read(
            includeVolume: true,
            includeBrightness: true,
            wifi: { .unavailable },
            volume: { nil },
            brightness: { nil }
        )
        #expect(levels == MenuBarSystemLevels())
    }

    @Test
    func wifiStatesDoNotRequireNetworkIdentity() {
        #expect(MenuBarSystemLevelReader.wifiState(powerOn: nil, rssi: -75) == .unavailable)
        #expect(MenuBarSystemLevelReader.wifiState(powerOn: false, rssi: -75) == .off)
        #expect(MenuBarSystemLevelReader.wifiState(powerOn: false, rssi: 0) == .off)
        #expect(MenuBarSystemLevelReader.wifiState(powerOn: true, rssi: 0) == .disconnected)
        #expect(MenuBarSystemLevelReader.wifiState(powerOn: true, rssi: 1) == .unavailable)
        #expect(MenuBarSystemLevelReader.wifiState(powerOn: true, rssi: Int.max) == .unavailable)
    }

    @Test(arguments: [Int.min, -150, -100, -75, -50, -1])
    func rssiClampsToUnitInterval(rssi: Int) {
        let expected: Double = rssi <= -100 ? 0 : rssi >= -50 ? 1 : 0.5
        #expect(MenuBarSystemLevelReader.wifiState(powerOn: true, rssi: rssi) == .connected(strength: expected))
    }

    @Test(arguments: [0.0, 0.5, 1.0])
    func validLevelBoundaries(value: Double) {
        #expect(MenuBarSystemLevelReader.normalizedLevel(value) == value)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.001, 1.001, Double.greatestFiniteMagnitude])
    func rejectsInvalidLevels(value: Double) {
        #expect(MenuBarSystemLevelReader.normalizedLevel(value) == nil)
    }

    @Test
    func masterVolumeAndMute() {
        #expect(volume(master: .value(0.5)) == 0.5)
        #expect(volume(master: .value(0)) == 0)
        #expect(volume(master: .value(1)) == 1)
        #expect(volume(master: .failed, masterMute: .value(1)) == 0)
        #expect(volume(master: .value(0.5), masterMute: .failed) == nil)
        #expect(volume(master: .failed) == nil)
        #expect(volume(master: .unsupported) == nil)
    }

    @Test(arguments: [Float32.nan, .infinity, -.infinity, -0.1, 1.1])
    func rejectsInvalidMasterAndChannelVolume(value: Float32) {
        #expect(volume(master: .value(value), channels: [.value(0.5)]) == nil)
        #expect(volume(master: .unsupported, channels: [.value(value)]) == nil)
    }

    @Test
    func fallsBackOnlyWhenMasterVolumeIsUnsupported() {
        #expect(volume(master: .unsupported, channels: [.value(0.25), .value(0.75)]) == 0.5)
        #expect(volume(master: .unsupported, channels: [.value(0.75)]) == 0.75)
        #expect(volume(master: .unsupported, channels: [.unsupported, .value(0.5)]) == 0.5)
        #expect(volume(master: .failed, channels: [.value(0.5)]) == nil)
        #expect(volume(master: .value(0.75), channels: [.failed]) == 0.75)
        #expect(volume(master: .unsupported, channels: [.unsupported, .unsupported]) == nil)
        #expect(volume(master: .unsupported, channels: [.value(0.5), .failed]) == nil)
    }

    @Test
    func channelMuteAndFailures() {
        #expect(volume(master: .unsupported, channels: [.failed], channelMutes: [.value(1)]) == 0)
        #expect(volume(
            master: .unsupported,
            channels: [.value(0.75), .value(0.5)],
            channelMutes: [.value(1), .value(0)]
        ) == 0.25)
        #expect(volume(master: .unsupported, channels: [.value(0.5)], channelMutes: [.failed]) == nil)
    }

    @Test
    func noDefaultDeviceDoesNotReadDeviceProperties() {
        for deviceID: AudioDeviceID? in [nil, kAudioObjectUnknown] {
            let level = MenuBarSystemLevelReader.volume(
                deviceID: deviceID,
                mute: { _, _ in Issue.record("Unexpected mute read"); return .failed },
                scalar: { _, _ in Issue.record("Unexpected volume read"); return .failed },
                channelCount: { _ in Issue.record("Unexpected channel read"); return nil }
            )
            #expect(level == nil)
        }
    }

    @Test
    func missingChannelConfigurationIsUnavailable() {
        for count: UInt32? in [nil, 0] {
            let level = MenuBarSystemLevelReader.volume(
                deviceID: 42,
                mute: { _, _ in .unsupported },
                scalar: { _, channel in
                    #expect(channel == kAudioObjectPropertyElementMain)
                    return .unsupported
                },
                channelCount: { _ in count }
            )
            #expect(level == nil)
        }
    }

    @Test
    func validatesAudioBufferLayout() {
        var buffer = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 0, mData: nil)
        )
        withUnsafePointer(to: &buffer) { pointer in
            #expect(MenuBarSystemLevelReader.outputChannelCount(buffer: pointer, byteCount: MemoryLayout<AudioBufferList>.size) == 2)
            #expect(MenuBarSystemLevelReader.outputChannelCount(buffer: pointer, byteCount: 0) == nil)
            #expect(MenuBarSystemLevelReader.outputChannelCount(buffer: pointer, byteCount: MemoryLayout<AudioBufferList>.size - 1) == nil)
        }
        buffer.mNumberBuffers = 2
        withUnsafePointer(to: &buffer) { pointer in
            #expect(MenuBarSystemLevelReader.outputChannelCount(buffer: pointer, byteCount: MemoryLayout<AudioBufferList>.size) == nil)
        }
        buffer.mNumberBuffers = 0
        withUnsafePointer(to: &buffer) { pointer in
            #expect(MenuBarSystemLevelReader.outputChannelCount(buffer: pointer, byteCount: MemoryLayout<AudioBufferList>.size) == nil)
        }
        buffer.mNumberBuffers = 1
        buffer.mBuffers.mNumberChannels = 0
        withUnsafePointer(to: &buffer) { pointer in
            #expect(MenuBarSystemLevelReader.outputChannelCount(buffer: pointer, byteCount: MemoryLayout<AudioBufferList>.size) == nil)
        }
    }

    @Test
    func sumsOutputChannelsAndRejectsOverflow() {
        let byteCount = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        let list = buffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        list.initialize(to: AudioBufferList(
            mNumberBuffers: 2,
            mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 0, mData: nil)
        ))
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        buffers[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 0, mData: nil)
        buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        #expect(MenuBarSystemLevelReader.outputChannelCount(buffer: buffers.unsafeMutablePointer, byteCount: byteCount) == 3)
        buffers[0].mNumberChannels = UInt32.max
        buffers[1].mNumberChannels = 2
        #expect(MenuBarSystemLevelReader.outputChannelCount(buffer: buffers.unsafeMutablePointer, byteCount: byteCount) == nil)
    }

    @Test
    func prefersBuiltinEvenWhenMainIsExternal() {
        let level = MenuBarSystemLevelReader.brightness(
            displayIDs: [10, 20],
            mainDisplayID: 10,
            isBuiltin: { $0 == 20 },
            readBrightness: { displayID in
                #expect(displayID == 20)
                return 0.75
            }
        )
        #expect(level == 0.75)
    }

    @Test
    func usesMainNotFirstExternalDisplay() {
        let level = MenuBarSystemLevelReader.brightness(
            displayIDs: [10, 20],
            mainDisplayID: 20,
            isBuiltin: { _ in false },
            readBrightness: { displayID in
                #expect(displayID == 20)
                return 0.25
            }
        )
        #expect(level == 0.25)
    }

    @Test
    func doesNotSubstituteDifferentDisplayAfterReadFailure() {
        let level = MenuBarSystemLevelReader.brightness(
            displayIDs: [10, 20],
            mainDisplayID: 10,
            isBuiltin: { $0 == 20 },
            readBrightness: { displayID in
                #expect(displayID == 20)
                return nil
            }
        )
        #expect(level == nil)
    }

    @Test
    func missingOrInvalidDisplayDoesNotReadBrightness() {
        for displays: [CGDirectDisplayID] in [[], [0], [10]] {
            let level = MenuBarSystemLevelReader.brightness(
                displayIDs: displays,
                mainDisplayID: 0,
                isBuiltin: { _ in false },
                readBrightness: { _ in Issue.record("Unexpected brightness read"); return 0 }
            )
            #expect(level == nil)
        }
    }

    @Test(arguments: [Float32(0), 0.5, 1])
    func brightnessSuccessUsesSelectedDisplay(value: Float32) {
        let level = MenuBarSystemLevelReader.displayBrightness(displayID: 20) { displayID, output in
            #expect(displayID == 20)
            output.pointee = value
            return 0
        }
        #expect(level == Double(value))
    }

    @Test
    func brightnessFailureAndMissingCapabilityAreNil() {
        #expect(MenuBarSystemLevelReader.displayBrightness(displayID: 20, getter: nil) == nil)
        let invalidDisplay = MenuBarSystemLevelReader.displayBrightness(displayID: 0) { _, _ in
            Issue.record("Unexpected getter call")
            return 0
        }
        #expect(invalidDisplay == nil)
        let failedRead = MenuBarSystemLevelReader.displayBrightness(displayID: 20) { _, output in
            output.pointee = 0.5
            return -1
        }
        #expect(failedRead == nil)
        let unwrittenOutput = MenuBarSystemLevelReader.displayBrightness(displayID: 20) { _, _ in 0 }
        #expect(unwrittenOutput == nil)
    }

    @Test(arguments: [Float32.nan, .infinity, -.infinity, -0.1, 1.1])
    func rejectsInvalidBrightness(value: Float32) {
        let level = MenuBarSystemLevelReader.displayBrightness(displayID: 20) { _, output in
            output.pointee = value
            return 0
        }
        #expect(level == nil)
    }

    private func volume(
        master: MenuBarSystemLevelReader.AudioProperty<Float32>,
        masterMute: MenuBarSystemLevelReader.AudioProperty<UInt32> = .unsupported,
        channels: [MenuBarSystemLevelReader.AudioProperty<Float32>] = [],
        channelMutes: [MenuBarSystemLevelReader.AudioProperty<UInt32>] = []
    ) -> Double? {
        MenuBarSystemLevelReader.volume(
            deviceID: 42,
            mute: { deviceID, channel in
                #expect(deviceID == 42)
                if channel == kAudioObjectPropertyElementMain { return masterMute }
                return channel <= channelMutes.count ? channelMutes[Int(channel) - 1] : .unsupported
            },
            scalar: { deviceID, channel in
                #expect(deviceID == 42)
                return channel == kAudioObjectPropertyElementMain ? master : channels[Int(channel) - 1]
            },
            channelCount: { deviceID in
                #expect(deviceID == 42)
                return UInt32(channels.count)
            }
        )
    }
}
