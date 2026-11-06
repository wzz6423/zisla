import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ZislaCore

enum ScreenRecordingSampleKind: Hashable, Sendable {
    case screen, systemAudio, microphone, camera

    var isAudio: Bool { self == .systemAudio || self == .microphone }
}

struct ScreenRecordingCaptureSample: @unchecked Sendable {
    let buffer: CMSampleBuffer
    let kind: ScreenRecordingSampleKind
    let hostTime: Double
}

protocol ScreenRecordingCaptureAssetWriter: AnyObject {
    func append(_ sample: CMSampleBuffer, kind: ScreenRecordingSampleKind) throws -> Bool
    func finish(at time: Double, completion: @escaping @Sendable (Result<Void, Error>) -> Void)
    func cancel()
}

final class ScreenRecordingCaptureStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Double, Error>?
    private var waiters: [UUID: CheckedContinuation<Double, Error>] = [:]

    func resolve(_ result: Result<Double, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuations = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()
        for continuation in continuations { continuation.resume(with: result) }
    }

    func wait(timeout: Double) async throws -> Double {
        let identifier = UUID()
        let deadline = DispatchWorkItem { [weak self] in
            self?.resolve(.failure(ScreenRecordingCaptureError.noScreenFrames))
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                } else if Task<Never, Never>.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[identifier] = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            self.lock.lock()
            let continuation = self.waiters.removeValue(forKey: identifier)
            self.lock.unlock()
            continuation?.resume(throwing: CancellationError())
        }
    }
}

final class ScreenRecordingCaptureWriter: @unchecked Sendable {
    typealias Factory = (URL, ScreenRecordingSampleKind, CMSampleBuffer) throws -> any ScreenRecordingCaptureAssetWriter

    private enum State { case accepting, sealed, finishing, finished, cancelled }
    private let queue = DispatchQueue(label: "dev.wzz.zisla.recording.writer", qos: .userInitiated)
    private let ingressLock = NSLock()
    private var pendingCount = 0
    private var pendingAudioCount = 0
    private var pendingAudioBytes = 0
    private var ingressOpen = true
    private let files: ScreenRecordingCaptureFiles
    private let configuration: RecordingCaptureConfiguration
    private let factory: Factory?
    private let width: Int
    private let height: Int
    private let onFailure: @Sendable (Error) -> Void
    private let finishTimeout: Double
    private let firstFrame = ScreenRecordingCaptureStartGate()
    private var state = State.accepting
    private var timeline = ScreenRecordingCaptureTimeline()
    private var assets: [ScreenRecordingSampleKind: any ScreenRecordingCaptureAssetWriter] = [:]
    private var lastTimes: [ScreenRecordingSampleKind: CMTime] = [:]
    private var buffered: [ScreenRecordingCaptureSample] = []
    private var terminalError: Error?
    private var recordedDuration: Double = 0
    private var lastSampleEnd: Double = 0
    private var finishResult: Result<Double, Error>?
    private var finishWaiters: [CheckedContinuation<Double, Error>] = []
    private var finishingCount = 0
    private var finishDeadline: DispatchWorkItem?

    init(files: ScreenRecordingCaptureFiles, configuration: RecordingCaptureConfiguration,
         width: Int, height: Int, finishTimeout: Double = 15,
         onFailure: @escaping @Sendable (Error) -> Void,
         factory: Factory? = nil) {
        self.files = files
        self.configuration = configuration
        self.onFailure = onFailure
        self.finishTimeout = finishTimeout
        self.factory = factory
        self.width = width
        self.height = height
    }

    func receive(_ sample: ScreenRecordingCaptureSample) {
        guard sample.hostTime.isFinite, CMSampleBufferIsValid(sample.buffer), CMSampleBufferDataIsReady(sample.buffer) else { return }
        switch sample.kind {
        case .systemAudio where !configuration.systemAudio, .microphone where !configuration.microphone,
             .camera where !configuration.camera: return
        default: break
        }
        ingressLock.lock()
        guard ingressOpen else { ingressLock.unlock(); return }
        if sample.kind.isAudio {
            let bytes = ScreenRecordingCaptureAudioBacklog.byteCount(sample.buffer)
            guard pendingAudioCount < ScreenRecordingCaptureAudioBacklog.sampleLimit,
                  bytes <= ScreenRecordingCaptureAudioBacklog.byteLimit - pendingAudioBytes else {
                ingressOpen = false
                queue.async { self.fail(ScreenRecordingCaptureError.writerUnavailable) }
                ingressLock.unlock()
                return
            }
            pendingAudioCount += 1
            pendingAudioBytes += bytes
        } else {
            guard pendingCount < 32 else { ingressLock.unlock(); return }
            pendingCount += 1
        }
        queue.async {
            if !sample.kind.isAudio {
                self.ingressLock.lock()
                self.pendingCount -= 1
                self.ingressLock.unlock()
            }
            var buffered = false
            defer { if sample.kind.isAudio, !buffered { self.releaseAudio(sample) } }
            guard self.state == .accepting, self.terminalError == nil else { return }
            do { buffered = try self.consume(sample) } catch { self.fail(error) }
        }
        ingressLock.unlock()
    }

    func waitForFirstFrame(timeout: Double = 8) async throws -> Double {
        try await firstFrame.wait(timeout: timeout)
    }

    func setPaused(_ paused: Bool, at time: Double) async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.state == .accepting {
                    if paused { self.timeline.pause(at: time) } else { self.timeline.resume(at: time) }
                }
                continuation.resume()
            }
        }
    }

    func seal(at time: Double) async {
        await withCheckedContinuation { continuation in
            ingressLock.lock()
            ingressOpen = false
            queue.async {
                if self.state == .accepting {
                    self.state = .sealed
                    self.recordedDuration = max(self.timeline.elapsed(at: time), self.lastSampleEnd)
                    self.clearBuffered()
                }
                continuation.resume()
            }
            ingressLock.unlock()
        }
    }

    func finish() async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let result = self.finishResult { continuation.resume(with: result); return }
                if self.state == .cancelled { continuation.resume(throwing: CancellationError()); return }
                self.finishWaiters.append(continuation)
                guard self.state != .finishing else { return }
                if let error = self.terminalError { self.resolveFinish(.failure(error)); return }
                guard self.state == .sealed, self.lastTimes[.screen] != nil else {
                    self.resolveFinish(.failure(ScreenRecordingCaptureError.noScreenFrames)); return
                }
                if self.configuration.microphone, self.lastTimes[.microphone] == nil {
                    self.resolveFinish(.failure(ScreenRecordingCaptureError.noMicrophoneSamples)); return
                }
                if self.configuration.camera, self.lastTimes[.camera] == nil {
                    self.resolveFinish(.failure(ScreenRecordingCaptureError.noCameraFrames)); return
                }
                self.state = .finishing
                self.finishingCount = self.assets.count
                for asset in self.assets.values {
                    asset.finish(at: self.recordedDuration) { [weak self] result in
                        guard let self else { return }
                        self.queue.async {
                            guard self.state == .finishing else { return }
                            if case let .failure(error) = result { self.fail(error); return }
                            self.finishingCount -= 1
                            if self.finishingCount == 0 {
                                self.resolveFinish(self.terminalError.map { .failure($0) } ?? .success(self.recordedDuration))
                            }
                        }
                    }
                }
                let deadline = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    guard self.state == .finishing else { return }
                    self.fail(ScreenRecordingCaptureError.saveFailed(AppLocalization.text("录屏文件写入超时")))
                }
                self.finishDeadline = deadline
                self.queue.asyncAfter(deadline: .now() + self.finishTimeout, execute: deadline)
            }
        }
    }

    func cancel() async {
        await withCheckedContinuation { continuation in
            ingressLock.lock()
            ingressOpen = false
            queue.async {
                self.state = .cancelled
                self.finishDeadline?.cancel()
                self.finishDeadline = nil
                self.clearBuffered()
                for asset in self.assets.values { asset.cancel() }
                self.assets.removeAll()
                self.firstFrame.resolve(.failure(CancellationError()))
                if !self.finishWaiters.isEmpty { self.resolveFinish(.failure(CancellationError())) }
                continuation.resume()
            }
            ingressLock.unlock()
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    private func consume(_ sample: ScreenRecordingCaptureSample) throws -> Bool {
        if timeline.epoch == nil, sample.kind != .screen {
            if sample.kind == .camera, buffered.filter({ $0.kind == .camera }).count == 16 {
                buffered.remove(at: buffered.firstIndex(where: { $0.kind == .camera })!)
            }
            buffered.append(sample)
            return true
        }
        guard let time = timeline.epoch == nil ? 0 : timeline.time(for: sample.hostTime) else { return false }
        // Distinct host times can become equal at the media timescale, especially after a pause.
        let presentationTime = CMTime(seconds: time, preferredTimescale: 1_000_000)
        guard lastTimes[sample.kind].map({ CMTimeCompare(presentationTime, $0) > 0 }) != false else { return false }
        let key: ScreenRecordingSampleKind = sample.kind == .systemAudio ? .screen : sample.kind
        if assets[key] == nil {
            let name: String
            switch key {
            case .screen, .systemAudio: name = files.screenName
            case .microphone: name = files.microphoneName
            case .camera: name = files.cameraName
            }
            if let factory { assets[key] = try factory(files.url(for: name), key, sample.buffer) }
            else {
                assets[key] = try ScreenRecordingNativeAssetWriter(url: files.url(for: name), kind: key, firstSample: sample.buffer,
                                                                   width: width, height: height, systemAudio: configuration.systemAudio,
                                                                   frameRate: configuration.frameRate, finishQueue: queue,
                                                                   finishTimeout: finishTimeout, onFailure: { [weak self] error in
                    self?.fail(error)
                })
            }
        }
        let retimed = try ScreenRecordingCaptureRetimer.copy(sample.buffer, presentationTime: presentationTime)
        guard try assets[key]!.append(retimed, kind: sample.kind) else {
            if sample.kind.isAudio { throw ScreenRecordingCaptureError.writerUnavailable }
            return false
        }
        if timeline.epoch == nil { timeline.begin(at: sample.hostTime) }
        lastTimes[sample.kind] = presentationTime
        let duration = CMSampleBufferGetDuration(sample.buffer).seconds
        let end = time + (duration.isFinite && duration > 0 ? duration : 1 / Double(configuration.frameRate))
        lastSampleEnd = max(lastSampleEnd, end)
        if sample.kind == .screen {
            firstFrame.resolve(.success(timeline.epoch!))
            let pending = buffered
            buffered.removeAll()
            defer { for value in pending where value.kind.isAudio { releaseAudio(value) } }
            for value in pending.sorted(by: { $0.hostTime < $1.hostTime }) { _ = try consume(value) }
        }
        return false
    }

    private func releaseAudio(_ sample: ScreenRecordingCaptureSample) {
        ingressLock.lock()
        pendingAudioCount -= 1
        pendingAudioBytes -= ScreenRecordingCaptureAudioBacklog.byteCount(sample.buffer)
        ingressLock.unlock()
    }

    private func clearBuffered() {
        for value in buffered where value.kind.isAudio { releaseAudio(value) }
        buffered.removeAll()
    }

    private func fail(_ error: Error) {
        guard terminalError == nil, state != .cancelled, state != .finished else { return }
        terminalError = error
        ingressLock.lock()
        ingressOpen = false
        ingressLock.unlock()
        clearBuffered()
        for asset in assets.values { asset.cancel() }
        firstFrame.resolve(.failure(error))
        if state == .finishing { resolveFinish(.failure(error)) }
        onFailure(error)
    }

    private func resolveFinish(_ result: Result<Double, Error>) {
        finishDeadline?.cancel()
        finishDeadline = nil
        state = .finished
        finishResult = result
        let continuations = finishWaiters
        finishWaiters.removeAll()
        for continuation in continuations { continuation.resume(with: result) }
    }
}

enum ScreenRecordingCaptureEncoding {
    static func codec(width: Int, height: Int) -> AVVideoCodecType {
        width > 4_096 || height > 4_096 ? .hevc : .h264
    }
}

final class ScreenRecordingNativeAssetWriter: ScreenRecordingCaptureAssetWriter, @unchecked Sendable {
    private let asset: AVAssetWriter
    private let inputs: [ScreenRecordingSampleKind: AVAssetWriterInput]
    private let frameRate: Int
    private var lastScreenSample: CMSampleBuffer?
    private let finishQueue: DispatchQueue
    private var microphoneMixer: ScreenRecordingCaptureAudioMixer?
    private let onFailure: @Sendable (Error) -> Void
    private let isReady: (ScreenRecordingSampleKind, AVAssetWriterInput) -> Bool
    private let finishInput: (ScreenRecordingSampleKind, AVAssetWriterInput) -> Void
    private var audioBacklogs: [ScreenRecordingSampleKind: ScreenRecordingCaptureAudioBacklog] = [:]
    private var observations: [NSKeyValueObservation] = []
    private var markedInputs: Set<ScreenRecordingSampleKind> = []
    private var finishCompletion: (@Sendable (Result<Void, Error>) -> Void)?
    private var finishTime: Double = 0
    private var cancelled = false

    init(url: URL, kind: ScreenRecordingSampleKind, firstSample: CMSampleBuffer,
         width: Int, height: Int, systemAudio: Bool, frameRate: Int, finishQueue: DispatchQueue,
         finishTimeout: Double, onFailure: @escaping @Sendable (Error) -> Void,
         ready: @escaping (ScreenRecordingSampleKind, AVAssetWriterInput) -> Bool = { _, input in input.isReadyForMoreMediaData },
         markFinished: @escaping (ScreenRecordingSampleKind, AVAssetWriterInput) -> Void = { _, input in input.markAsFinished() }) throws {
        asset = try AVAssetWriter(outputURL: url, fileType: .mp4)
        self.onFailure = onFailure
        isReady = ready
        finishInput = markFinished
        var inputs: [ScreenRecordingSampleKind: AVAssetWriterInput] = [:]
        if kind == .screen || kind == .camera {
            let dimensions: (Int, Int)
            if kind == .camera {
                guard let format = CMSampleBufferGetFormatDescription(firstSample) else { throw ScreenRecordingCaptureError.writerUnavailable }
                let value = CMVideoFormatDescriptionGetDimensions(format)
                dimensions = (Int(value.width) / 2 * 2, Int(value.height) / 2 * 2)
            } else { dimensions = (width, height) }
            guard dimensions.0 > 0, dimensions.1 > 0 else { throw ScreenRecordingCaptureError.writerUnavailable }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: ScreenRecordingCaptureEncoding.codec(width: dimensions.0, height: dimensions.1),
                AVVideoWidthKey: dimensions.0, AVVideoHeightKey: dimensions.1,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: min(80_000_000, max(2_000_000, dimensions.0 * dimensions.1 * frameRate / 6)),
                    AVVideoExpectedSourceFrameRateKey: frameRate,
                    AVVideoAllowFrameReorderingKey: false,
                ],
            ])
            input.expectsMediaDataInRealTime = true
            guard asset.canAdd(input) else { throw ScreenRecordingCaptureError.writerUnavailable }
            asset.add(input)
            inputs[kind] = input
        }
        if kind == .microphone || kind == .screen && systemAudio {
            let rate: Double
            let channels: UInt32
            if kind == .microphone {
                guard let format = CMSampleBufferGetFormatDescription(firstSample),
                      let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) else {
                    throw ScreenRecordingCaptureError.writerUnavailable
                }
                rate = min(description.pointee.mSampleRate, 48_000)
                channels = min(description.pointee.mChannelsPerFrame, 2)
                if description.pointee.mChannelsPerFrame > 2 {
                    microphoneMixer = try ScreenRecordingCaptureAudioMixer(description: description.pointee)
                }
            } else { rate = 48_000; channels = 2 }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: Int(rate) * Int(channels) * 2,
            ])
            input.expectsMediaDataInRealTime = true
            guard asset.canAdd(input) else { throw ScreenRecordingCaptureError.writerUnavailable }
            asset.add(input)
            inputs[kind == .microphone ? .microphone : .systemAudio] = input
        }
        self.inputs = inputs
        self.frameRate = frameRate
        self.finishQueue = finishQueue
        guard asset.startWriting() else { throw asset.error ?? ScreenRecordingCaptureError.writerUnavailable }
        asset.startSession(atSourceTime: .zero)
        for (kind, input) in inputs where kind.isAudio {
            let mixer = microphoneMixer
            audioBacklogs[kind] = ScreenRecordingCaptureAudioBacklog(append: { [asset] sample in
                guard asset.status == .writing else { throw asset.error ?? ScreenRecordingCaptureError.writerUnavailable }
                guard ready(kind, input) else { return false }
                let encoded = kind == .microphone ? try mixer?.mix(sample) ?? sample : sample
                guard input.append(encoded) else { throw asset.error ?? ScreenRecordingCaptureError.writerUnavailable }
                return true
            }, scheduleTimeout: { item in
                finishQueue.asyncAfter(deadline: .now() + finishTimeout, execute: item)
            }, onFinished: { [weak self] in self?.markInputFinished(kind, input: input) },
            onFailure: { [weak self] in self?.reportFailure($0) })
            observations.append(input.observe(\.isReadyForMoreMediaData, options: [.new]) { [weak self] _, _ in
                finishQueue.async { [weak self] in self?.audioBacklogs[kind]?.drain() }
            })
        }
    }

    func append(_ sample: CMSampleBuffer, kind: ScreenRecordingSampleKind) throws -> Bool {
        guard asset.status == .writing else { throw asset.error ?? ScreenRecordingCaptureError.writerUnavailable }
        guard let input = inputs[kind] else { throw ScreenRecordingCaptureError.writerUnavailable }
        if let backlog = audioBacklogs[kind] {
            try backlog.append(sample)
            return true
        }
        guard isReady(kind, input) else { return false }
        guard input.append(sample) else { throw asset.error ?? ScreenRecordingCaptureError.writerUnavailable }
        if kind == .screen { lastScreenSample = sample }
        return true
    }

    func finish(at time: Double, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        guard asset.status == .writing else {
            completion(.failure(asset.error ?? ScreenRecordingCaptureError.writerUnavailable)); return
        }
        finishTime = time
        finishCompletion = completion
        // Finish each exhausted input independently so interleaving cannot stall the remaining audio.
        for backlog in audioBacklogs.values { backlog.finish() }
        guard !cancelled else { return }
        if let input = inputs[.camera] { markInputFinished(.camera, input: input) }
        let sample = lastScreenSample
        lastScreenSample = nil
        let tailTime = CMTime(seconds: time - 1 / Double(frameRate), preferredTimescale: 1_000_000)
        if let sample, let input = inputs[.screen], CMTimeCompare(tailTime, CMSampleBufferGetPresentationTimeStamp(sample)) > 0 {
            do {
                let buffer = try ScreenRecordingCaptureRetimer.copy(sample, presentationTime: tailTime)
                let tail = ScreenRecordingCaptureSample(buffer: buffer, kind: .screen, hostTime: tailTime.seconds)
                input.requestMediaDataWhenReady(on: finishQueue) { [weak self] in
                    guard let self else { return }
                    let input = self.inputs[.screen]!
                    guard self.isReady(.screen, input) else { return }
                    guard self.asset.status == .writing, input.append(tail.buffer) else {
                        self.reportFailure(self.asset.error ?? ScreenRecordingCaptureError.writerUnavailable); return
                    }
                    self.markInputFinished(.screen, input: input)
                }
            } catch { reportFailure(error) }
        } else if let input = inputs[.screen] { markInputFinished(.screen, input: input) }
    }

    func cancel() {
        cancelled = true
        finishCompletion = nil
        lastScreenSample = nil
        microphoneMixer = nil
        for observation in observations { observation.invalidate() }
        observations.removeAll()
        for backlog in audioBacklogs.values { backlog.cancel() }
        audioBacklogs.removeAll()
        if asset.status == .writing || asset.status == .unknown { asset.cancelWriting() }
    }

    private func markInputFinished(_ kind: ScreenRecordingSampleKind, input: AVAssetWriterInput) {
        markedInputs.insert(kind)
        finishInput(kind, input)
        if kind == .screen { audioBacklogs[.systemAudio]?.drain() }
        guard markedInputs.count == inputs.count, let completion = finishCompletion else { return }
        finishCompletion = nil
        asset.endSession(atSourceTime: CMTime(seconds: finishTime, preferredTimescale: 1_000_000))
        asset.finishWriting { [self] in
            finishQueue.async {
                completion(self.asset.status == .completed ? .success(()) : .failure(self.asset.error ?? ScreenRecordingCaptureError.writerUnavailable))
            }
        }
    }

    private func reportFailure(_ error: Error) {
        guard !cancelled else { return }
        let completion = finishCompletion
        cancel()
        if let completion { completion(.failure(error)) }
        else { onFailure(error) }
    }
}

final class ScreenRecordingCaptureAudioMixer {
    private let converter: AudioConverterRef
    private let sourceFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat

    init(description: AudioStreamBasicDescription) throws {
        var description = description
        let channels = Int(description.mChannelsPerFrame)
        guard description.mFormatID == kAudioFormatLinearPCM,
              let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | description.mChannelsPerFrame),
              let sourceFormat = AVAudioFormat(streamDescription: &description, channelLayout: layout),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: description.mSampleRate,
                                               channels: 2, interleaved: true) else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        self.sourceFormat = sourceFormat
        self.outputFormat = outputFormat
        var converter: AudioConverterRef?
        guard AudioConverterNew(&description, outputFormat.streamDescription, &converter) == noErr,
              let converter else { throw ScreenRecordingCaptureError.writerUnavailable }
        var downmix: UInt32 = 1
        // Device channels are adjacent stereo pairs; normalize each side so no input is discarded or clips the mix.
        let gains: [Float] = (0..<(channels * 2)).map { index in
            let input = index / 2
            let output = index % 2
            return input % 2 == output ? 1 / Float((channels + 1 - output) / 2) : 0
        }
        let status = AudioConverterSetProperty(converter, kAudioConverterPropertyPerformDownmix,
                                               UInt32(MemoryLayout<UInt32>.size), &downmix)
        let mixStatus = gains.withUnsafeBytes {
            AudioConverterSetProperty(converter, kAudioConverterPropertyChannelMixMap, UInt32($0.count), $0.baseAddress!)
        }
        guard status == noErr, mixStatus == noErr else {
            AudioConverterDispose(converter)
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        self.converter = converter
    }

    deinit { AudioConverterDispose(converter) }

    func mix(_ sample: CMSampleBuffer) throws -> CMSampleBuffer {
        guard sample.numSamples > 0 else { return sample }
        let frames = AVAudioFrameCount(sample.numSamples)
        guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frames) else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        source.frameLength = frames
        output.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                          into: source.mutableAudioBufferList) == noErr,
              AudioConverterConvertComplexBuffer(converter, frames, source.audioBufferList,
                                                  output.mutableAudioBufferList) == noErr else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        var timing = CMSampleTimingInfo()
        var result: CMSampleBuffer?
        var size = Int(outputFormat.streamDescription.pointee.mBytesPerFrame)
        guard CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing) == noErr,
              CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
                                        formatDescription: outputFormat.formatDescription, sampleCount: Int(frames),
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &result) == noErr,
              let result,
              CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: kCFAllocatorDefault,
                                                            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
                                                            bufferList: output.audioBufferList) == noErr else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        return result
    }
}
