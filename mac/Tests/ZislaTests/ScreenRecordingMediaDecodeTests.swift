import AVFoundation
import CoreImage
import Testing
@testable import Zisla

@Suite @MainActor
struct ScreenRecordingMediaDecodeTests {
    @Test func compositionDecodeAllowsMainActorCallbacksAndPreservesEveryFrame() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let asset = AVURLAsset(url: try await fixture.createVideo())
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let composition = AVMutableVideoComposition()
        composition.renderSize = .init(width: 64, height: 48)
        composition.frameDuration = .init(value: 1, timescale: 8)
        composition.customVideoCompositorClass = MainActorDecodeCompositor.self
        composition.instructions = [MainActorDecodeInstruction(trackID: track.trackID)]
        let frames = try await RecordingMultitrackTestFixture.decode(asset, composition: composition)
        try #require(frames.count == 16, "A composition callback must remain runnable while all source frames are decoded")
        for (index, frame) in frames.enumerated() {
            #expect(abs(frame.0 - Double(index) / 8) < 0.001)
            let center = try RecordingMultitrackTestFixture.pixel(frame.1, x: 32, y: 24)
            #expect(center[index < 8 ? 0 : 2] > 215 && center[1] < 40)
        }
        #expect(try fixture.files() == ["screen.mp4"])
    }
}

private final class MainActorDecodeInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange = CMTimeRange(start: .zero, duration: .init(value: 2, timescale: 1))
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let requiredSourceTrackIDs: [NSValue]?
    let trackID: CMPersistentTrackID

    init(trackID: CMPersistentTrackID) {
        self.trackID = trackID
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

private final class MainActorDecodeCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let completion = MainActorDecodeCompletion(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { completion.timeout() }
        Task { @MainActor in completion.finish() }
    }
}

private final class MainActorDecodeCompletion: @unchecked Sendable {
    private let request: AVAsynchronousVideoCompositionRequest
    private let lock = NSLock()
    private var completed = false

    init(_ request: AVAsynchronousVideoCompositionRequest) { self.request = request }

    func timeout() {
        guard claim() else { return }
        request.finish(with: CancellationError())
    }

    @MainActor func finish() {
        guard claim() else { return }
        guard let instruction = request.videoCompositionInstruction as? MainActorDecodeInstruction,
              let frame = request.sourceFrame(byTrackID: instruction.trackID) else {
            request.finish(with: CocoaError(.fileReadCorruptFile))
            return
        }
        request.finish(withComposedVideoFrame: frame)
    }

    private func claim() -> Bool {
        lock.withLock {
            guard !completed else { return false }
            completed = true
            return true
        }
    }
}
