import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ZislaCore

enum ScreenRecordingSampleKind: Hashable, Sendable {
    case screen, systemAudio, microphone, camera
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
    private let files: ScreenRecordingCaptureFiles
    private let configuration: RecordingCaptureConfiguration
    private let factory: Factory
    private let onFailure: @Sendable (Error) -> Void
    private let finishTimeout: Double
    private let firstFrame = ScreenRecordingCaptureStartGate()
    private var state = State.accepting
    private var timeline = ScreenRecordingCaptureTimeline()
    private var assets: [ScreenRecordingSampleKind: any ScreenRecordingCaptureAssetWriter] = [:]
    private var lastTimes: [ScreenRecordingSampleKind: Double] = [:]
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
        let assetQueue = queue
        self.factory = factory ?? { url, kind, sample in
            try ScreenRecordingNativeAssetWriter(url: url, kind: kind, firstSample: sample,
                                                  width: width, height: height,
                                                  systemAudio: configuration.systemAudio,
                                                  frameRate: configuration.frameRate, finishQueue: assetQueue)
        }
    }

    func receive(_ sample: ScreenRecordingCaptureSample) {
        ingressLock.lock()
        guard pendingCount < 32 else { ingressLock.unlock(); return }
        pendingCount += 1
        ingressLock.unlock()
        queue.async {
            self.ingressLock.lock()
            self.pendingCount -= 1
            self.ingressLock.unlock()
            guard self.state == .accepting, self.terminalError == nil else { return }
            do { try self.consume(sample) } catch { self.fail(error) }
        }
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
            queue.async {
                if self.state == .accepting {
                    self.state = .sealed
                    self.recordedDuration = max(self.timeline.elapsed(at: time), self.lastSampleEnd)
                    self.buffered.removeAll()
                }
                continuation.resume()
            }
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
                            if case let .failure(error) = result, self.terminalError == nil { self.terminalError = error }
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
                    for asset in self.assets.values { asset.cancel() }
                    self.resolveFinish(.failure(ScreenRecordingCaptureError.saveFailed(AppLocalization.text("录屏文件写入超时"))))
                }
                self.finishDeadline = deadline
                self.queue.asyncAfter(deadline: .now() + self.finishTimeout, execute: deadline)
            }
        }
    }

    func cancel() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.state = .cancelled
                self.finishDeadline?.cancel()
                self.finishDeadline = nil
                self.buffered.removeAll()
                for asset in self.assets.values { asset.cancel() }
                self.assets.removeAll()
                self.firstFrame.resolve(.failure(CancellationError()))
                if !self.finishWaiters.isEmpty { self.resolveFinish(.failure(CancellationError())) }
                continuation.resume()
            }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    private func consume(_ sample: ScreenRecordingCaptureSample) throws {
        guard sample.hostTime.isFinite, CMSampleBufferIsValid(sample.buffer), CMSampleBufferDataIsReady(sample.buffer) else { return }
        switch sample.kind {
        case .systemAudio where !configuration.systemAudio, .microphone where !configuration.microphone,
             .camera where !configuration.camera: return
        default: break
        }
        if timeline.epoch == nil, sample.kind != .screen {
            if buffered.count == 16 { buffered.removeFirst() }
            buffered.append(sample)
            return
        }
        guard let time = timeline.epoch == nil ? 0 : timeline.time(for: sample.hostTime),
              lastTimes[sample.kind].map({ time > $0 }) != false else { return }
        let key: ScreenRecordingSampleKind = sample.kind == .systemAudio ? .screen : sample.kind
        if assets[key] == nil {
            let name: String
            switch key {
            case .screen, .systemAudio: name = files.screenName
            case .microphone: name = files.microphoneName
            case .camera: name = files.cameraName
            }
            assets[key] = try factory(files.url(for: name), key, sample.buffer)
        }
        let retimed = try ScreenRecordingCaptureRetimer.copy(sample.buffer, presentationTime: CMTime(seconds: time, preferredTimescale: 1_000_000))
        guard try assets[key]!.append(retimed, kind: sample.kind) else { return }
        if timeline.epoch == nil { timeline.begin(at: sample.hostTime) }
        lastTimes[sample.kind] = time
        let duration = CMSampleBufferGetDuration(sample.buffer).seconds
        let end = time + (duration.isFinite && duration > 0 ? duration : 1 / Double(configuration.frameRate))
        lastSampleEnd = max(lastSampleEnd, end)
        if sample.kind == .screen {
            firstFrame.resolve(.success(timeline.epoch!))
            let pending = buffered
            buffered.removeAll()
            for value in pending.sorted(by: { $0.hostTime < $1.hostTime }) { try consume(value) }
        }
    }

    private func fail(_ error: Error) {
        guard terminalError == nil else { return }
        terminalError = error
        firstFrame.resolve(.failure(error))
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

private final class ScreenRecordingNativeAssetWriter: ScreenRecordingCaptureAssetWriter, @unchecked Sendable {
    private let asset: AVAssetWriter
    private let inputs: [ScreenRecordingSampleKind: AVAssetWriterInput]
    private let frameRate: Int
    private var lastScreenSample: CMSampleBuffer?
    private let finishQueue: DispatchQueue

    init(url: URL, kind: ScreenRecordingSampleKind, firstSample: CMSampleBuffer,
         width: Int, height: Int, systemAudio: Bool, frameRate: Int, finishQueue: DispatchQueue) throws {
        asset = try AVAssetWriter(outputURL: url, fileType: .mp4)
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
                rate = description.pointee.mSampleRate
                channels = description.pointee.mChannelsPerFrame
            } else { rate = 48_000; channels = 2 }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 192_000,
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
    }

    func append(_ sample: CMSampleBuffer, kind: ScreenRecordingSampleKind) throws -> Bool {
        guard asset.status == .writing else { throw asset.error ?? ScreenRecordingCaptureError.writerUnavailable }
        guard let input = inputs[kind] else { throw ScreenRecordingCaptureError.writerUnavailable }
        guard input.isReadyForMoreMediaData else { return false }
        guard input.append(sample) else { throw asset.error ?? ScreenRecordingCaptureError.writerUnavailable }
        if kind == .screen { lastScreenSample = sample }
        return true
    }

    func finish(at time: Double, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        guard asset.status == .writing else {
            completion(.failure(asset.error ?? ScreenRecordingCaptureError.writerUnavailable)); return
        }
        let complete: @Sendable () -> Void = { [self] in
            guard asset.status == .writing else {
                completion(.failure(asset.error ?? ScreenRecordingCaptureError.writerUnavailable)); return
            }
            asset.endSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 1_000_000))
            for input in inputs.values { input.markAsFinished() }
            asset.finishWriting { [self] in
                completion(asset.status == .completed ? .success(()) : .failure(asset.error ?? ScreenRecordingCaptureError.writerUnavailable))
            }
        }
        let sample = lastScreenSample
        lastScreenSample = nil
        let tailTime = time - 1 / Double(frameRate)
        if let sample, let input = inputs[.screen], tailTime > CMSampleBufferGetPresentationTimeStamp(sample).seconds {
            do {
                let buffer = try ScreenRecordingCaptureRetimer.copy(sample, presentationTime: CMTime(seconds: tailTime, preferredTimescale: 1_000_000))
                let tail = ScreenRecordingCaptureSample(buffer: buffer, kind: .screen, hostTime: tailTime)
                input.requestMediaDataWhenReady(on: finishQueue) { [self] in
                    let input = inputs[.screen]!
                    guard input.isReadyForMoreMediaData else { return }
                    guard asset.status == .writing, input.append(tail.buffer) else {
                        completion(.failure(asset.error ?? ScreenRecordingCaptureError.writerUnavailable)); return
                    }
                    complete()
                }
            } catch { completion(.failure(error)) }
        } else { complete() }
    }

    func cancel() {
        lastScreenSample = nil
        if asset.status == .writing || asset.status == .unknown { asset.cancelWriting() }
    }
}
