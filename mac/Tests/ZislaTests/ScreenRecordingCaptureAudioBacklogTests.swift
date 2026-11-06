import CoreMedia
import Foundation
import Testing
import ZislaCore
@testable import Zisla

@Suite
struct ScreenRecordingCaptureAudioBacklogTests {
    @Test
    func temporaryBackpressureKeepsEveryPacketInOrderUntilReadinessReturns() throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        output.ready = false
        for index in 0..<100 { try backlog.append(sample(at: Double(index) / 100)) }
        #expect(output.times.isEmpty)
        #expect(output.deadlines.count == 1, "Later packets must not extend the blocked head's deadline")
        output.ready = true
        backlog.drain()
        #expect(output.times == (0..<100).map { Double($0) / 100 })
        output.deadlines[0].perform()
        #expect(output.errors.isEmpty, "A drained packet must invalidate its old timeout")
        backlog.finish()
        #expect(output.finished == 1)
    }

    @Test
    func finishWaitsForAcceptedAudioAndRejectsLaterPackets() throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        output.ready = false
        try backlog.append(sample(at: 0))
        try backlog.append(sample(at: 0.01))
        backlog.finish()
        backlog.finish()
        #expect(output.finished == 0)
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try backlog.append(sample(at: 0.02)) }
        output.ready = true
        backlog.drain()
        backlog.drain()
        backlog.finish()
        #expect(output.times == [0, 0.01])
        #expect(output.finished == 1, "Repeated finish and readiness events must finish the input once")
    }

    @Test
    func continuouslyBlockedHeadTimesOutWithoutRenewalByNewPackets() throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        output.ready = false
        try backlog.append(sample(at: 0))
        let firstDeadline = try #require(output.deadlines.first)
        try backlog.append(sample(at: 0.01))
        backlog.drain()
        #expect(output.deadlines.count == 1)
        firstDeadline.perform()
        firstDeadline.perform()
        output.ready = true
        backlog.drain()
        backlog.finish()
        #expect(output.times.isEmpty)
        #expect(output.errors == [.saveFailed(AppLocalization.text("录屏文件写入超时"))])
        #expect(output.finished == 0)
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try backlog.append(sample(at: 0.02)) }
    }

    @Test
    func partiallyDrainedQueueGivesItsNewBlockedHeadAnIndependentDeadline() throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        output.ready = false
        try backlog.append(sample(at: 0))
        try backlog.append(sample(at: 0.01))
        output.ready = true
        output.acceptedBeforeBlocking = 1
        backlog.drain()
        #expect(output.times == [0])
        #expect(output.deadlines.count == 2)
        output.deadlines[0].perform()
        #expect(output.errors.isEmpty, "A timeout for an appended head must not fail its successor")
        try #require(output.deadlines.dropFirst().first).perform()
        #expect(output.errors == [.saveFailed(AppLocalization.text("录屏文件写入超时"))])
    }

    @Test
    func cancellationDropsPendingAudioAndInvalidatesReadinessAndTimeoutCallbacks() throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        output.ready = false
        try backlog.append(sample(at: 0))
        backlog.finish()
        backlog.cancel()
        backlog.cancel()
        output.ready = true
        backlog.drain()
        output.deadlines[0].perform()
        backlog.finish()
        #expect(output.times.isEmpty)
        #expect(output.errors.isEmpty)
        #expect(output.finished == 0)
    }

    @Test
    func packetCountLimitFailsExplicitlyAndCannotPublishATruncatedQueue() throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        output.ready = false
        let packet = try sample(at: 0)
        for _ in 0..<ScreenRecordingCaptureAudioBacklog.sampleLimit { try backlog.append(packet) }
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try backlog.append(packet) }
        output.ready = true
        backlog.drain()
        backlog.finish()
        #expect(output.times.isEmpty, "Capacity exhaustion must fail the recording instead of publishing a missing packet")
        #expect(output.finished == 0)
    }

    @Test
    func byteLimitRejectsAQueueBelowThePacketLimitAndReleasesItsPayload() throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        output.ready = false
        let halfBudget = try sample(at: 0, bytes: ScreenRecordingCaptureAudioBacklog.byteLimit / 2)
        try backlog.append(halfBudget)
        try backlog.append(halfBudget)
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try backlog.append(sample(at: 0.01, bytes: 1)) }
        output.ready = true
        backlog.drain()
        #expect(output.times.isEmpty)
        output.deadlines[0].perform()
        #expect(output.errors.isEmpty)
    }

    @Test
    func successfullyWrittenPacketsReleaseTheByteBudget() throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        let packet = try sample(at: 0, bytes: ScreenRecordingCaptureAudioBacklog.byteLimit)
        for _ in 0..<3 { try backlog.append(packet) }
        backlog.finish()
        #expect(output.times == [0, 0, 0])
        #expect(output.finished == 1)
        #expect(output.deadlines.isEmpty)
    }

    @Test
    func byteBudgetIncludesRetainedDataBeyondTheLogicalSampleSize() throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        output.ready = false
        let packet = try sample(at: 0, bytes: 1, blockBytes: ScreenRecordingCaptureAudioBacklog.byteLimit)
        try backlog.append(packet)
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try backlog.append(sample(at: 0.01)) }
        output.ready = true
        backlog.drain()
        #expect(output.times.isEmpty)
    }

    @Test(arguments: [false, true])
    func appendErrorsAbortPendingAudioAndKeepTheOriginalError(duringDrain: Bool) throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        if duringDrain {
            output.ready = false
            try backlog.append(sample(at: 0))
            output.ready = true
            output.error = .diskFull
            backlog.drain()
            #expect(output.originalErrors == [.diskFull])
        } else {
            output.error = .diskFull
            #expect(throws: AudioBacklogTestError.diskFull) { try backlog.append(sample(at: 0)) }
            #expect(output.originalErrors.isEmpty, "Synchronous append failure belongs to the caller")
        }
        output.error = nil
        backlog.drain()
        backlog.finish()
        #expect(output.times.isEmpty)
        #expect(output.finished == 0)
        #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try backlog.append(sample(at: 0.01)) }
    }

    @Test(arguments: [false, true])
    func drainingAndCancellationReleaseTheRetainedPacket(cancelled: Bool) throws {
        let output = AudioBacklogTestOutput()
        let backlog = output.makeBacklog()
        output.ready = false
        weak var lifetime: NSObject?
        try autoreleasepool {
            let marker = NSObject()
            lifetime = marker
            let packet = try sample(at: 0)
            CMSetAttachment(packet, key: "AudioBacklogTestLifetime" as CFString, value: marker, attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
            try backlog.append(packet)
        }
        #expect(lifetime != nil, "The blocked packet must remain retained until it is written or cancelled")
        if cancelled { backlog.cancel() }
        else { output.ready = true; backlog.drain() }
        #expect(lifetime == nil, "Completed or cancelled audio must release the sample buffer")
    }

    private func sample(at time: Double, bytes: Int = 16, blockBytes: Int? = nil) throws -> CMSampleBuffer {
        let length = blockBytes ?? bytes
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
                                                  blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                  offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 100),
                                        presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 1_000_000),
                                        decodeTimeStamp: .invalid)
        var size = bytes
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: try #require(block), formatDescription: nil,
                                          sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                          sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}

private enum AudioBacklogTestError: Error, Equatable { case diskFull }

private final class AudioBacklogTestOutput {
    var ready = true
    var acceptedBeforeBlocking: Int?
    var error: AudioBacklogTestError?
    var times: [Double] = []
    var deadlines: [DispatchWorkItem] = []
    var errors: [ScreenRecordingCaptureError] = []
    var originalErrors: [AudioBacklogTestError] = []
    var finished = 0

    func makeBacklog() -> ScreenRecordingCaptureAudioBacklog {
        ScreenRecordingCaptureAudioBacklog(append: { [self] sample in
            if let error { throw error }
            guard ready else { return false }
            if let acceptedBeforeBlocking {
                guard acceptedBeforeBlocking > 0 else { return false }
                self.acceptedBeforeBlocking = acceptedBeforeBlocking - 1
            }
            times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            return true
        }, scheduleTimeout: { [self] in deadlines.append($0) }, onFinished: { [self] in finished += 1 },
        onFailure: { [self] error in
            if let error = error as? ScreenRecordingCaptureError { errors.append(error) }
            else if let error = error as? AudioBacklogTestError { originalErrors.append(error) }
            else { Issue.record("Unexpected audio backlog error: \(error)") }
        })
    }
}
