import AVFoundation
import CoreImage
import Foundation
import Testing
import ZislaCore
@testable import Zisla

@MainActor
struct ScreenRecordingPortraitPreviewTests {
    @Test(arguments: [CGSize(width: 1280, height: 720), CGSize(width: 320, height: 240)])
    func enabledPreviewIsScaledWithoutUpsizingTheCamera(_ size: CGSize) async throws {
        let camera = ScreenRecordingCameraCapture(identifier: nil, onFailure: { Issue.record("Valid camera frames must render: \($0)") })
        var frames: [CGImage] = []
        camera.setPortraitEffects(.init(brightening: 0.4)) { if let image = $0 { frames.append(image) } }
        let sample = try video(size)
        deliver(sample, to: camera)
        await drain()
        let frame = try #require(frames.first)
        let scale = min(1, 640 / max(size.width, size.height))
        #expect(frame.width == Int(size.width * scale) && frame.height == Int(size.height * scale))
        #expect(frames.count == 1)
        await camera.stop()
    }

    @Test func disabledEffectsDoNotAllocateOrDeliverAProcessedPreview() async throws {
        let camera = ScreenRecordingCameraCapture(identifier: nil, onFailure: { Issue.record("Disabled processing must skip invalid frames: \($0)") })
        var frames = 0
        camera.setPortraitEffects(.init()) { _ in frames += 1 }
        deliver(try video(), to: camera)
        deliver(try missingImage(), to: camera)
        await drain()
        #expect(frames == 0)
        await camera.stop()
    }

    @Test func nilHandlerLeavesTheFrameUnprocessed() async throws {
        let camera = ScreenRecordingCameraCapture(identifier: nil, onFailure: { Issue.record("An absent preview handler must skip malformed input: \($0)") })
        camera.setPortraitEffects(.init(brightening: 0.4), onFrame: nil)
        deliver(try missingImage(), to: camera)
        await drain()
        var frames = 0
        camera.setPortraitEffects(.init(brightening: 0.4)) { _ in frames += 1 }
        deliver(try video(), to: camera)
        await drain()
        #expect(frames == 1, "Installing a callback after a disabled delivery path must still accept the next frame")
        await camera.stop()
    }

    @Test func aBurstKeepsOnePendingFrameAndDeliveryCompletionAllowsTheNextFrame() async throws {
        let camera = ScreenRecordingCameraCapture(identifier: nil, onFailure: { Issue.record("The bounded frame burst must not fail: \($0)") })
        var frames = 0
        camera.setPortraitEffects(.init(brightening: 0.4)) { _ in frames += 1 }
        let sample = try video()
        for _ in 0..<12 { deliver(sample, to: camera) }
        await drain()
        #expect(frames == 1, "While MainActor is busy, camera processing must keep one pending preview delivery")
        deliver(sample, to: camera)
        await drain()
        #expect(frames == 2, "Completing a delivery must allow another preview frame")
        await camera.stop()
    }

    @Test func processingFailureIsNotifiedAndReleasesThePendingSlotForRecovery() async throws {
        var errors: [Error] = []
        var frames = 0
        let camera = ScreenRecordingCameraCapture(identifier: nil, onFailure: { errors.append($0) })
        camera.setPortraitEffects(.init(brightening: 2)) { _ in frames += 1 }
        deliver(try video(), to: camera)
        await drain()
        #expect(errors.count == 1 && frames == 0)
        #expect(errors.first as? ScreenRecordingExportError == .invalidConfiguration)
        camera.setPortraitEffects(.init(brightening: 0.4)) { _ in frames += 1 }
        deliver(try video(), to: camera)
        await drain()
        #expect(frames == 1 && errors.count == 1)
        await camera.stop()
    }

    @Test func aMissingImageFailsWithoutPublishingAFrameAndCanRecover() async throws {
        var errors: [Error] = []
        var frames = 0
        let camera = ScreenRecordingCameraCapture(identifier: nil, onFailure: { errors.append($0) })
        camera.setPortraitEffects(.init(brightening: 0.4)) { _ in frames += 1 }
        deliver(try missingImage(), to: camera)
        await drain()
        #expect(errors.first as? ScreenRecordingCaptureError == .noCameraFrames && frames == 0)
        deliver(try video(), to: camera)
        await drain()
        #expect(frames == 1 && errors.count == 1)
        await camera.stop()
    }

    @Test func stoppingDropsTheFrameCallbackBeforeNewSamplesArrive() async throws {
        let camera = ScreenRecordingCameraCapture(identifier: nil, onFailure: { Issue.record("Stopped capture must discard input: \($0)") })
        var frames = 0
        camera.setPortraitEffects(.init(brightening: 0.4)) { _ in frames += 1 }
        deliver(try video(), to: camera)
        await drain()
        #expect(frames == 1)
        await camera.stop()
        deliver(try video(), to: camera)
        await drain()
        #expect(frames == 1)
    }

    private func drain() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func deliver(_ sample: CMSampleBuffer, to camera: ScreenRecordingCameraCapture) {
        camera.captureOutput(AVCaptureVideoDataOutput(), didOutput: sample, from: AVCaptureConnection(inputPorts: [], output: AVCaptureVideoDataOutput()))
    }

    private func video(_ size: CGSize = .init(width: 64, height: 48)) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        try #require(CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &pixel) == kCVReturnSuccess)
        let buffer = try #require(pixel)
        let bounds = CGRect(origin: .zero, size: size)
        CIContext().render(CIImage(color: .init(red: 0.3, green: 0.25, blue: 0.2)).cropped(to: bounds), to: buffer)
        var description: CMVideoFormatDescription?
        try #require(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &description) == noErr)
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 30), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        try #require(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer,
            formatDescription: try #require(description), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }

    private func missingImage() throws -> CMSampleBuffer {
        var sample: CMSampleBuffer?
        try #require(CMSampleBufferCreateReady(allocator: nil, dataBuffer: nil, formatDescription: nil, sampleCount: 0,
            sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}
