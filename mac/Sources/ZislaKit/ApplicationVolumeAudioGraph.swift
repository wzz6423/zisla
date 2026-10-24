import CoreAudio
import Darwin
import Foundation

struct ApplicationVolumeOutput: Equatable, Sendable {
    let id: AudioObjectID
    let uid: String
}

struct ApplicationVolumeStereoChannels: Equatable, Sendable {
    let left: Int
    let right: Int
}

protocol ApplicationVolumeAudioHardware: Sendable {
    func defaultOutput() throws -> ApplicationVolumeOutput
    func processObjects(for identifiers: [pid_t]) throws -> [AudioObjectID]
    func createTap(_ description: CATapDescription) throws -> AudioObjectID
    func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription
    func createAggregate(_ description: [String: Any]) throws -> AudioObjectID
    func outputFormats(_ device: AudioObjectID) throws -> [AudioStreamBasicDescription]
    func inputChannels(_ device: AudioObjectID) throws -> [Int]
    func stereoChannels(_ device: AudioObjectID) throws -> ApplicationVolumeStereoChannels
    func tapLevelCompensation(for processObjects: [AudioObjectID]) throws -> Float
    func createIO(_ device: AudioObjectID, callback: @escaping AudioDeviceIOBlock) throws -> AudioDeviceIOProcID
    func startIO(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID) throws
    func stopIO(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID)
    func destroyIO(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID)
    func destroyAggregate(_ device: AudioObjectID)
    func destroyTap(_ tap: AudioObjectID)
}

struct CoreAudioVolumeHardware: ApplicationVolumeAudioHardware {
    func defaultOutput() throws -> ApplicationVolumeOutput {
        var device = AudioObjectID(kAudioObjectUnknown)
        try Self.read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &device)
        guard device != kAudioObjectUnknown else { throw ApplicationVolumeFailure.outputUnavailable }
        var uid: CFString?
        try Self.read(device, kAudioDevicePropertyDeviceUID, into: &uid)
        guard let uid else { throw ApplicationVolumeFailure.outputUnavailable }
        return ApplicationVolumeOutput(id: device, uid: uid as String)
    }

    func processObjects(for identifiers: [pid_t]) throws -> [AudioObjectID] {
        guard #available(macOS 14.4, *) else { throw ApplicationVolumeFailure.outputUnavailable }
        var objects: Set<AudioObjectID> = []
        for var identifier in identifiers {
            var address = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
            var object = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &identifier, &size, &object
            )
            try Self.check(status)
            if object != kAudioObjectUnknown { objects.insert(object) }
        }
        guard !objects.isEmpty else { throw ApplicationVolumeFailure.hardware(kAudioHardwareBadObjectError) }
        return objects.sorted()
    }

    func createTap(_ description: CATapDescription) throws -> AudioObjectID {
        guard #available(macOS 14.4, *) else { throw ApplicationVolumeFailure.outputUnavailable }
        var tap = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tap)
        if status == kAudioDevicePermissionsError || status == kAudioHardwareIllegalOperationError {
            throw ApplicationVolumeFailure.permissionDenied
        }
        try Self.check(status)
        guard tap != kAudioObjectUnknown else { throw ApplicationVolumeFailure.hardware(kAudioHardwareBadObjectError) }
        return tap
    }

    func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        try Self.read(tap, kAudioTapPropertyFormat, into: &format)
        return format
    }

    func createAggregate(_ description: [String: Any]) throws -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &device))
        guard device != kAudioObjectUnknown else { throw ApplicationVolumeFailure.hardware(kAudioHardwareBadObjectError) }
        return device
    }

    func outputFormats(_ device: AudioObjectID) throws -> [AudioStreamBasicDescription] {
        var address = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        try Self.check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size))
        var streams = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !streams.isEmpty else { throw ApplicationVolumeFailure.outputUnavailable }
        try Self.check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams))
        return try streams.map { stream in
            var format = AudioStreamBasicDescription()
            try Self.read(stream, kAudioStreamPropertyVirtualFormat, into: &format)
            return format
        }
    }

    func inputChannels(_ device: AudioObjectID) throws -> [Int] {
        try bufferChannels(device, scope: kAudioObjectPropertyScopeInput)
    }

    func stereoChannels(_ device: AudioObjectID) throws -> ApplicationVolumeStereoChannels {
        var address = Self.address(kAudioDevicePropertyPreferredChannelsForStereo, scope: kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(device, &address) else {
            let channels = try bufferChannels(device, scope: kAudioObjectPropertyScopeOutput).reduce(0, +)
            return ApplicationVolumeStereoChannels(left: 0, right: channels == 1 ? 0 : 1)
        }
        var pair: [UInt32] = [0, 0]
        var size = UInt32(MemoryLayout<UInt32>.size * 2)
        try Self.check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &pair))
        guard size == MemoryLayout<UInt32>.size * 2, pair.allSatisfy({ $0 > 0 }) else {
            throw ApplicationVolumeFailure.unsupportedFormat
        }
        return ApplicationVolumeStereoChannels(left: Int(pair[0]) - 1, right: Int(pair[1]) - 1)
    }

    func tapLevelCompensation(for processObjects: [AudioObjectID]) throws -> Float {
        guard #available(macOS 14.4, *) else { throw ApplicationVolumeFailure.outputUnavailable }
        var devices: Set<AudioObjectID> = []
        for process in processObjects {
            var address = Self.address(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
            var size: UInt32 = 0
            try Self.check(AudioObjectGetPropertyDataSize(process, &address, 0, nil, &size))
            guard size > 0 else { continue }
            var outputs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            try Self.check(AudioObjectGetPropertyData(process, &address, 0, nil, &size, &outputs))
            devices.formUnion(outputs)
        }
        var streamChannels: [Int] = []
        for device in devices {
            let channels = try bufferChannels(device, scope: kAudioObjectPropertyScopeOutput)
            let left = try stereoChannels(device).left
            var offset = 0
            for count in channels {
                if (offset..<(offset + count)).contains(left) { streamChannels.append(count) }
                offset += count
            }
        }
        // Core Audio attenuates stereo mixdown by 2/N on an N-channel source stream.
        return Self.tapLevelCompensation(streamChannels: streamChannels)
    }

    static func tapLevelCompensation(streamChannels: [Int]) -> Float {
        max(1, Float(streamChannels.min() ?? 2) / 2)
    }

    private func bufferChannels(_ device: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [Int] {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        try Self.check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size))
        guard size >= MemoryLayout<AudioBufferList>.size else { throw ApplicationVolumeFailure.unsupportedFormat }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        try Self.check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, memory))
        let list = memory.assumingMemoryBound(to: AudioBufferList.self)
        let count = Int(list.pointee.mNumberBuffers)
        guard count > 0, MemoryLayout<AudioBufferList>.size + (count - 1) * MemoryLayout<AudioBuffer>.stride <= Int(size) else {
            throw ApplicationVolumeFailure.unsupportedFormat
        }
        return UnsafeMutableAudioBufferListPointer(list).map { Int($0.mNumberChannels) }
    }

    func createIO(_ device: AudioObjectID, callback: @escaping AudioDeviceIOBlock) throws -> AudioDeviceIOProcID {
        var proc: AudioDeviceIOProcID?
        try Self.check(AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil, callback))
        guard let proc else { throw ApplicationVolumeFailure.hardware(kAudioHardwareBadObjectError) }
        return proc
    }

    func startIO(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID) throws {
        try Self.check(AudioDeviceStart(device, proc))
    }

    func stopIO(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID) { AudioDeviceStop(device, proc) }
    func destroyIO(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID) { AudioDeviceDestroyIOProcID(device, proc) }
    func destroyAggregate(_ device: AudioObjectID) { AudioHardwareDestroyAggregateDevice(device) }
    func destroyTap(_ tap: AudioObjectID) {
        if #available(macOS 14.4, *) { AudioHardwareDestroyProcessTap(tap) }
    }

    static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T
    ) throws {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutablePointer(to: &value) { pointer in
            try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer))
        }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw ApplicationVolumeFailure.hardware(status) }
    }
}

// OSAtomic remains available on macOS 14, unlike Swift Synchronization.Atomic.
private final class ApplicationVolumeRenderControl: @unchecked Sendable {
    private var gainBits: Int32
    private var progress: Int32 = 0
    private var isStopped: Int32 = 0

    init(gain: Float) { gainBits = Int32(bitPattern: gain.bitPattern) }

    var gain: Float {
        get { Float(bitPattern: UInt32(bitPattern: OSAtomicAdd32Barrier(0, &gainBits))) }
        set {
            let replacement = Int32(bitPattern: newValue.bitPattern)
            var current: Int32
            repeat { current = OSAtomicAdd32Barrier(0, &gainBits) }
            while !OSAtomicCompareAndSwap32Barrier(current, replacement, &gainBits)
        }
    }

    var renderProgress: Int32 { OSAtomicAdd32Barrier(0, &progress) }
    var isActive: Bool { OSAtomicAdd32Barrier(0, &isStopped) == 0 }
    func stop() { OSAtomicCompareAndSwap32Barrier(0, 1, &isStopped) }
    func didRender() { OSAtomicIncrement32Barrier(&progress) }
}

enum ApplicationVolumeRenderer {
    static func render(
        input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>,
        tapBufferIndex: Int, tapChannels: Int, stereoChannels: ApplicationVolumeStereoChannels, gain: Float,
        outputFormats: [AudioStreamBasicDescription], isActive: Bool
    ) -> Int {
        let destination = UnsafeMutableAudioBufferListPointer(output)
        for buffer in destination {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard isActive else { return 0 }
        var outputBufferIndex = 0
        for format in outputFormats {
            let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            let bufferCount = planar ? Int(format.mChannelsPerFrame) : 1
            let channelsPerBuffer = planar ? 1 : Int(format.mChannelsPerFrame)
            guard bufferCount <= destination.count - outputBufferIndex else { return 0 }
            for _ in 0..<bufferCount {
                guard Int(destination[outputBufferIndex].mNumberChannels) == channelsPerBuffer else { return 0 }
                outputBufferIndex += 1
            }
        }
        guard outputBufferIndex == destination.count else { return 0 }
        let incoming = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        // A missing tap must never fall back to a physical input with the same channel count.
        guard tapBufferIndex >= 0, incoming.count == tapBufferIndex + 1 else { return 0 }
        let source = incoming[tapBufferIndex]
        guard tapChannels > 0, Int(source.mNumberChannels) == tapChannels,
              let samples = source.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
        let sourceFrames = Int(source.mDataByteSize) / (MemoryLayout<Float>.size * tapChannels)
        let outputChannels = destination.reduce(0) { $0 + Int($1.mNumberChannels) }
        var channelOffset = 0
        var renderedFrames = 0
        for buffer in destination {
            let channels = Int(buffer.mNumberChannels)
            defer { channelOffset += channels }
            guard channels > 0, let target = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let frameCount = min(sourceFrames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let outputChannel = channelOffset + channel
                    if outputChannels == 1 {
                        var mixed: Float = 0
                        for sourceChannel in 0..<tapChannels { mixed += samples[frame * tapChannels + sourceChannel] }
                        target[frame * channels + channel] = mixed * gain / Float(tapChannels)
                    } else if tapChannels == 1 && (outputChannel == stereoChannels.left || outputChannel == stereoChannels.right) {
                        target[frame * channels + channel] = samples[frame] * gain
                    } else if outputChannel == stereoChannels.left {
                        target[frame * channels + channel] = samples[frame * tapChannels] * gain
                    } else if outputChannel == stereoChannels.right && tapChannels > 1 {
                        target[frame * channels + channel] = samples[frame * tapChannels + 1] * gain
                    }
                }
            }
            renderedFrames = max(renderedFrames, frameCount)
        }
        return renderedFrames
    }
}

final class ApplicationVolumeAudioGraph: @unchecked Sendable {
    let processObjects: [AudioObjectID]
    let output: ApplicationVolumeOutput
    private let hardware: any ApplicationVolumeAudioHardware
    private let control: ApplicationVolumeRenderControl
    private let dispose: @Sendable (@escaping @Sendable () -> Void) -> Void
    private var tap: AudioObjectID?
    private var aggregate: AudioObjectID?
    private var proc: AudioDeviceIOProcID?
    private var isReading = false

    var gain: Float {
        get { control.gain }
        set { control.gain = newValue }
    }
    var renderProgress: Int32 { control.renderProgress }

    init(
        processObjects: [AudioObjectID], output: ApplicationVolumeOutput, gain: Float,
        hardware: any ApplicationVolumeAudioHardware,
        dispose: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = {
            DispatchQueue.global(qos: .utility).async(execute: $0)
        }
    ) throws {
        self.processObjects = processObjects
        self.output = output
        self.hardware = hardware
        self.dispose = dispose
        control = ApplicationVolumeRenderControl(gain: gain)
        do {
            let compensation = try hardware.tapLevelCompensation(for: processObjects)
            let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
            description.name = "zisla App Volume"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            let tap = try hardware.createTap(description)
            self.tap = tap
            let format = try hardware.tapFormat(tap)
            guard Self.isNativeFloat(format), format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 else {
                throw ApplicationVolumeFailure.unsupportedFormat
            }
            let aggregate = try hardware.createAggregate([
                kAudioAggregateDeviceNameKey: "zisla App Volume",
                kAudioAggregateDeviceUIDKey: "dev.wzz.zisla.volume.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: output.uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]],
            ])
            self.aggregate = aggregate
            let outputFormats = try hardware.outputFormats(aggregate)
            let inputChannels = try hardware.inputChannels(aggregate)
            let stereoChannels = try hardware.stereoChannels(output.id)
            let outputChannelCount = outputFormats.reduce(0) { $0 + Int($1.mChannelsPerFrame) }
            guard !outputFormats.isEmpty,
                  outputFormats.allSatisfy({ Self.isNativeFloat($0) && $0.mSampleRate == format.mSampleRate }),
                  inputChannels.last == Int(format.mChannelsPerFrame),
                  stereoChannels.left >= 0, stereoChannels.left < outputChannelCount,
                  stereoChannels.right >= 0, stereoChannels.right < outputChannelCount,
                  outputChannelCount == 1 || stereoChannels.left != stereoChannels.right else {
                throw ApplicationVolumeFailure.unsupportedFormat
            }
            let control = self.control
            let channels = Int(format.mChannelsPerFrame)
            let proc = try hardware.createIO(aggregate) { _, input, _, output, _ in
                if ApplicationVolumeRenderer.render(
                    input: input, output: output, tapBufferIndex: inputChannels.count - 1,
                    tapChannels: channels, stereoChannels: stereoChannels, gain: control.gain * compensation,
                    outputFormats: outputFormats, isActive: control.isActive
                ) > 0 {
                    control.didRender()
                }
            }
            self.proc = proc
            try hardware.startIO(aggregate, proc)
            isReading = true
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    func stop() {
        stopReading()
        let hardware = self.hardware
        let aggregate = self.aggregate
        let proc = self.proc
        let tap = self.tap
        self.proc = nil
        self.aggregate = nil
        self.tap = nil
        guard aggregate != nil || tap != nil else { return }
        // HAL destruction may block; original playback resumes before resources are disposed.
        dispose {
            if let aggregate, let proc {
                hardware.destroyIO(aggregate, proc)
            }
            if let aggregate { hardware.destroyAggregate(aggregate) }
            if let tap { hardware.destroyTap(tap) }
        }
    }

    func stopReading() {
        control.stop()
        if isReading, let aggregate, let proc { hardware.stopIO(aggregate, proc) }
        isReading = false
    }

    static func isNativeFloat(_ format: AudioStreamBasicDescription) -> Bool {
        let channels = format.mChannelsPerFrame
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        return format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
            && format.mBitsPerChannel == 32 && channels > 0
            && UInt64(format.mBytesPerFrame) == (nonInterleaved ? 4 : UInt64(channels) * 4)
            && format.mSampleRate.isFinite && format.mSampleRate > 0
    }
}
