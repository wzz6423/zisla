import CoreMedia
import Foundation
import ZislaCore

final class ScreenRecordingCaptureAudioBacklog: @unchecked Sendable {
    static let sampleLimit = 512
    static let byteLimit = 8 * 1_024 * 1_024

    static func byteCount(_ sample: CMSampleBuffer) -> Int {
        max(CMSampleBufferGetTotalSampleSize(sample), sample.dataBuffer.map(CMBlockBufferGetDataLength) ?? 0)
    }

    private enum State { case accepting, finishing, stopped }
    private let appendSample: (CMSampleBuffer) throws -> Bool
    private let scheduleTimeout: (DispatchWorkItem) -> Void
    private let onFinished: () -> Void
    private let onFailure: (Error) -> Void
    private var state = State.accepting
    private var pending: [CMSampleBuffer] = []
    private var pendingBytes = 0
    private var deadline: DispatchWorkItem?

    init(append: @escaping (CMSampleBuffer) throws -> Bool,
         scheduleTimeout: @escaping (DispatchWorkItem) -> Void,
         onFinished: @escaping () -> Void, onFailure: @escaping (Error) -> Void) {
        appendSample = append
        self.scheduleTimeout = scheduleTimeout
        self.onFinished = onFinished
        self.onFailure = onFailure
    }

    func append(_ sample: CMSampleBuffer) throws {
        guard state == .accepting else { throw ScreenRecordingCaptureError.writerUnavailable }
        do {
            let bytes = Self.byteCount(sample)
            guard pending.count < Self.sampleLimit, bytes <= Self.byteLimit - pendingBytes else {
                throw ScreenRecordingCaptureError.writerUnavailable
            }
            pending.append(sample)
            pendingBytes += bytes
            try drainPending()
        } catch {
            cancel()
            throw error
        }
    }

    func drain() {
        do { try drainPending() } catch {
            cancel()
            onFailure(error)
        }
    }

    func finish() {
        guard state == .accepting else { return }
        state = .finishing
        drain()
    }

    func cancel() {
        state = .stopped
        pending.removeAll()
        pendingBytes = 0
        cancelDeadline()
    }

    private func drainPending() throws {
        while let sample = pending.first {
            guard try appendSample(sample) else {
                if deadline == nil {
                    let item = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.cancel()
                        self.onFailure(ScreenRecordingCaptureError.saveFailed(AppLocalization.text("录屏文件写入超时")))
                    }
                    deadline = item
                    scheduleTimeout(item)
                }
                return
            }
            pending.removeFirst()
            pendingBytes -= Self.byteCount(sample)
            cancelDeadline()
        }
        if state == .finishing {
            state = .stopped
            onFinished()
        }
    }

    private func cancelDeadline() {
        deadline?.cancel()
        deadline = nil
    }
}
