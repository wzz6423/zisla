import Accelerate
import AppKit
import Combine
import CoreAudio
import Darwin
import Foundation

enum AudioSpectrumAnalysisMode: Sendable {
    case visualization
    case audibilityOnly

    var minimumInterval: TimeInterval {
        switch self {
        case .visualization: 1.0 / 20.0
        case .audibilityOnly: 1.0 / 5.0
        }
    }

    var includesFrequencyLevels: Bool {
        self == .visualization
    }
}

final class AudioFrequencyAnalyzer {
    static let bandCount = 7

    let fftSize = 4_096

    private struct Band {
        var lowerFrequency: Double
        var upperFrequency: Double
        var minimumDecibels: Float
        var maximumDecibels: Float
    }

    private let bands = [
        Band(lowerFrequency: 30, upperFrequency: 90, minimumDecibels: -58, maximumDecibels: -10),
        Band(lowerFrequency: 90, upperFrequency: 180, minimumDecibels: -58, maximumDecibels: -10),
        Band(lowerFrequency: 180, upperFrequency: 350, minimumDecibels: -58, maximumDecibels: -12),
        Band(lowerFrequency: 350, upperFrequency: 700, minimumDecibels: -60, maximumDecibels: -14),
        Band(lowerFrequency: 700, upperFrequency: 1_400, minimumDecibels: -62, maximumDecibels: -16),
        Band(lowerFrequency: 1_400, upperFrequency: 3_500, minimumDecibels: -64, maximumDecibels: -18),
        Band(lowerFrequency: 3_500, upperFrequency: 12_000, minimumDecibels: -66, maximumDecibels: -20),
    ]
    private let fftSetup: FFTSetup
    private var history: [Float]
    private var window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var powers: [Float]
    private var magnitudes: [Float]

    init() {
        let log2Size = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else {
            preconditionFailure("无法创建 FFT")
        }
        self.fftSetup = fftSetup
        history = Array(repeating: 0, count: fftSize)
        window = Array(repeating: 0, count: fftSize)
        windowed = Array(repeating: 0, count: fftSize)
        real = Array(repeating: 0, count: fftSize / 2)
        imaginary = Array(repeating: 0, count: fftSize / 2)
        powers = Array(repeating: 0, count: fftSize / 2)
        magnitudes = Array(repeating: 0, count: fftSize / 2)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func reset() {
        history = Array(repeating: 0, count: fftSize)
    }

    func process(samples: [Float], sampleRate: Double) -> [Float] {
        append(samples)
        vDSP_vmul(history, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        for index in 0..<(fftSize / 2) {
            real[index] = windowed[index * 2]
            imaginary[index] = windowed[index * 2 + 1]
        }

        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard let realBase = realBuffer.baseAddress,
                      let imaginaryBase = imaginaryBuffer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)
                vDSP_fft_zrip(
                    fftSetup,
                    &split,
                    1,
                    vDSP_Length(log2(Float(fftSize))),
                    FFTDirection(FFT_FORWARD)
                )
                vDSP_zvmags(&split, 1, &powers, 1, vDSP_Length(fftSize / 2))
            }
        }

        powers[0] = 0
        var count = Int32(fftSize / 2)
        vvsqrtf(&magnitudes, powers, &count)
        var scale = 2 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))

        return bands.map { band in
            level(for: band, sampleRate: sampleRate)
        }
    }

    private func append(_ samples: [Float]) {
        let count = min(samples.count, fftSize)
        guard count > 0 else { return }
        let sourceStart = samples.count - count
        if count == fftSize {
            history.replaceSubrange(history.indices, with: samples[sourceStart...])
            return
        }

        let preservedCount = fftSize - count
        history.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            memmove(base, base.advanced(by: count), preservedCount * MemoryLayout<Float>.size)
            for index in 0..<count {
                base[preservedCount + index] = samples[sourceStart + index]
            }
        }
    }

    private func level(for band: Band, sampleRate: Double) -> Float {
        guard sampleRate > 0 else { return 0 }
        let lower = max(1, Int(band.lowerFrequency * Double(fftSize) / sampleRate))
        let upper = min(
            magnitudes.count - 1,
            Int(band.upperFrequency * Double(fftSize) / sampleRate)
        )
        guard lower <= upper else { return 0 }

        var peak: Float = 0
        for index in lower...upper {
            peak = max(peak, magnitudes[index])
        }
        let decibels = 20 * log10(max(peak, 0.000_000_1))
        let normalized = (decibels - band.minimumDecibels)
            / (band.maximumDecibels - band.minimumDecibels)
        return min(max(normalized, 0), 1)
    }
}

@MainActor
public final class AudioSpectrumService: ObservableObject {
    public static let shared = AudioSpectrumService()
    public static let bandCount = AudioFrequencyAnalyzer.bandCount

    @Published public private(set) var levels = Array(
        repeating: Float.zero,
        count: AudioFrequencyAnalyzer.bandCount
    )
    @Published public private(set) var isAudible = false

    private let capture: any AudioSpectrumCapturing
    private var isRequested = false
    private var analysisMode = AudioSpectrumAnalysisMode.visualization
    private var generation: UInt64 = 0
    private var lastAudibleTime: TimeInterval?

    init(capture: any AudioSpectrumCapturing = SystemAudioSpectrumCapture()) {
        self.capture = capture
    }

    public func startMonitoring() {
        guard !isRequested else { return }

        isRequested = true
        generation &+= 1
        let currentGeneration = generation
        levels = Self.silentLevels

        capture.setAnalysisMode(analysisMode)
        capture.start(
            onFrame: { [weak self] frame in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isRequested,
                          self.generation == currentGeneration else { return }
                    self.consume(frame)
                }
            },
            onFailure: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isRequested,
                          self.generation == currentGeneration
                    else { return }
                    self.isRequested = false
                    self.levels = Self.silentLevels
                    if self.isAudible { self.isAudible = false }
                    self.lastAudibleTime = nil
                }
            }
        )
    }

    func setVisualizationEnabled(_ enabled: Bool) {
        let mode: AudioSpectrumAnalysisMode = enabled ? .visualization : .audibilityOnly
        guard analysisMode != mode else { return }
        analysisMode = mode
        capture.setAnalysisMode(mode)
        if !enabled, levels != Self.silentLevels {
            levels = Self.silentLevels
        }
    }

    public func stop() {
        guard isRequested || levels.contains(where: { $0 > 0 }) else { return }
        isRequested = false
        generation &+= 1
        capture.stop()
        levels = Self.silentLevels
        if isAudible { isAudible = false }
        lastAudibleTime = nil
    }

    private func consume(_ frame: AudioSpectrumFrame) {
        if analysisMode == .visualization, let frequencyLevels = frame.levels {
            levels = Self.smoothed(previous: levels, target: frequencyLevels)
        }
        let now = Date.timeIntervalSinceReferenceDate
        if frame.rootMeanSquare >= 0.004 {
            lastAudibleTime = now
            if !isAudible { isAudible = true }
        } else if isAudible, now - (lastAudibleTime ?? now) >= 0.45 {
            isAudible = false
        }
    }

    private static var silentLevels: [Float] {
        Array(repeating: 0, count: bandCount)
    }

    private static func smoothed(previous: [Float], target: [Float]) -> [Float] {
        (0..<bandCount).map { index in
            let oldValue = previous.indices.contains(index) ? previous[index] : 0
            let newValue = target.indices.contains(index) ? target[index] : 0
            let response: Float = newValue > oldValue ? 0.78 : 0.34
            return oldValue + (newValue - oldValue) * response
        }
    }
}

protocol AudioSpectrumCapturing: AnyObject {
    func setAnalysisMode(_ mode: AudioSpectrumAnalysisMode)
    func start(
        onFrame: @escaping @Sendable (AudioSpectrumFrame) -> Void,
        onFailure: @escaping @Sendable () -> Void
    )
    func stop()
}

final class SystemAudioSpectrumCapture: AudioSpectrumCapturing, @unchecked Sendable {
    private let controlQueue = DispatchQueue(label: "dev.wzz.zisla.audio-spectrum.control")
    private let callbackQueue = DispatchQueue(
        label: "dev.wzz.zisla.audio-spectrum.callback",
        qos: .userInteractive
    )
    private let analyzer = AudioFrequencyAnalyzer()
    private var tapDescription: AnyObject?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRate = 48_000.0
    private var lastAnalysisTime: TimeInterval = 0
    private var analysisMode = AudioSpectrumAnalysisMode.visualization
    private var hasRequestedAuthorizationInCurrentLaunch = false

    /// Anchoring the system recording prompt activates the app, so it may only happen where a prompt
    /// can still appear: the tap creation just failed and this launch has not asked yet. Once the
    /// permission is granted the first, unanchored attempt succeeds — which is what keeps automatic
    /// graph rebuilds (track changes, island reveals, notice updates) from pulling the caret out of
    /// whatever the user is typing in.
    static func shouldRequestAuthorizationPrompt(
        creationFailed: Bool,
        hasRequestedInCurrentLaunch: Bool
    ) -> Bool {
        creationFailed && !hasRequestedInCurrentLaunch
    }

    func setAnalysisMode(_ mode: AudioSpectrumAnalysisMode) {
        callbackQueue.async { [weak self] in
            guard let self, self.analysisMode != mode else { return }
            self.analysisMode = mode
            self.analyzer.reset()
            self.lastAnalysisTime = 0
        }
    }

    func start(
        onFrame: @escaping @Sendable (AudioSpectrumFrame) -> Void,
        onFailure: @escaping @Sendable () -> Void
    ) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.teardown()
            do {
                try self.createGraph(onFrame: onFrame)
            } catch {
                self.teardown()
                onFailure()
            }
        }
    }

    func stop() {
        controlQueue.async { [weak self] in
            self?.teardown()
        }
    }

    private func createGraph(
        onFrame: @escaping @Sendable (AudioSpectrumFrame) -> Void
    ) throws {
        guard #available(macOS 14.2, *) else { throw CaptureError.unsupported }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "zisla 音频频谱"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        tapDescription = description

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        if Self.shouldRequestAuthorizationPrompt(
            creationFailed: status != noErr,
            hasRequestedInCurrentLaunch: hasRequestedAuthorizationInCurrentLaunch
        ) {
            hasRequestedAuthorizationInCurrentLaunch = true
            // A key host on the mouse's screen makes the system panel open there.
            var host: NSWindow?
            DispatchQueue.main.sync {
                host = WindowPlacement.authorizationPromptHost()
            }
            status = AudioHardwareCreateProcessTap(description, &newTapID)
            if let host {
                DispatchQueue.main.async {
                    host.orderOut(nil)
                    host.close()
                }
            }
        }
        try check(status)
        tapID = newTapID

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "zisla 音频频谱",
            kAudioAggregateDeviceUIDKey: "dev.wzz.zisla.spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var newAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &newAggregateDeviceID
        ))
        aggregateDeviceID = newAggregateDeviceID
        sampleRate = Self.nominalSampleRate(of: aggregateDeviceID) ?? 48_000
        lastAnalysisTime = 0

        var newIOProcID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(
            &newIOProcID,
            aggregateDeviceID,
            callbackQueue
        ) { [weak self] _, inputData, _, _, _ in
            self?.consume(inputData, onFrame: onFrame)
        })
        ioProcID = newIOProcID
        try check(AudioDeviceStart(aggregateDeviceID, ioProcID))
    }

    private func consume(
        _ inputData: UnsafePointer<AudioBufferList>,
        onFrame: @escaping @Sendable (AudioSpectrumFrame) -> Void
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        let mode = analysisMode
        guard now - lastAnalysisTime >= mode.minimumInterval else { return }
        lastAnalysisTime = now

        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        let descriptions = buffers.compactMap { buffer -> (AudioBuffer, Int, Int)? in
            let channels = max(1, Int(buffer.mNumberChannels))
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let frameCount = sampleCount / channels
            guard buffer.mData != nil, frameCount > 0 else { return nil }
            return (buffer, channels, frameCount)
        }
        guard let frameCount = descriptions.map(\.2).min(), frameCount > 0 else { return }

        var mono = Array(repeating: Float.zero, count: min(frameCount, analyzer.fftSize))
        var channelCount = 0
        for (buffer, channels, _) in descriptions {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            for frame in mono.indices {
                for channel in 0..<channels {
                    mono[frame] += samples[frame * channels + channel]
                }
            }
            channelCount += channels
        }
        guard channelCount > 0 else { return }
        var divisor = Float(channelCount)
        vDSP_vsdiv(mono, 1, &divisor, &mono, 1, vDSP_Length(mono.count))
        var rootMeanSquare = Float.zero
        vDSP_rmsqv(mono, 1, &rootMeanSquare, vDSP_Length(mono.count))
        onFrame(AudioSpectrumFrame(
            levels: mode.includesFrequencyLevels
                ? analyzer.process(samples: mono, sampleRate: sampleRate)
                : nil,
            rootMeanSquare: rootMeanSquare
        ))
    }

    private func teardown() {
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        ioProcID = nil
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
        tapDescription = nil
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw CaptureError.status(status) }
    }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double? {
        var sampleRate = Float64.zero
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        return status == noErr && sampleRate > 0 ? sampleRate : nil
    }

    private enum CaptureError: Error {
        case unsupported
        case status(OSStatus)
    }
}

struct AudioSpectrumFrame: Sendable {
    var levels: [Float]?
    var rootMeanSquare: Float
}
