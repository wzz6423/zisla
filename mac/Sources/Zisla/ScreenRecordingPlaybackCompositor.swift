import AVFoundation
import CoreImage
import ZislaCore

final class RecordingPlaybackInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let requiredSourceTrackIDs: [NSValue]?
    let screenTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID?
    let screenTransform: CGAffineTransform
    let cameraTransform: CGAffineTransform
    let cameraRanges: [CMTimeRange?]
    let timeline: RecordingExportTimeline
    let renderer: RecordingExportRenderer

    init(project: ScreenRecordingProject, media: RecordingExportMedia,
         cameraTrackID: CMPersistentTrackID?, size: CGSize) throws {
        timeline = media.timeline
        timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: timeline.duration,
                                                            preferredTimescale: 60_000))
        screenTrackID = media.video.track.trackID
        self.cameraTrackID = cameraTrackID
        requiredSourceTrackIDs = ([screenTrackID] + [cameraTrackID].compactMap { $0 }).map { NSNumber(value: $0) }
        screenTransform = media.video.transform
        cameraTransform = media.camera?.transform ?? .identity
        cameraRanges = media.camera?.availableRanges ?? []
        renderer = try RecordingExportRenderer(project: project, size: size)
    }
}

final class RecordingPlaybackCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            do {
                guard let instruction = request.videoCompositionInstruction as? RecordingPlaybackInstruction,
                      let slice = instruction.timeline.slice(at: request.compositionTime.seconds),
                      let screen = request.sourceFrame(byTrackID: instruction.screenTrackID),
                      let output = request.renderContext.newPixelBuffer() else {
                    throw ScreenRecordingExportError.unavailableMedia
                }
                let camera: CIImage?
                if let cameraID = instruction.cameraTrackID,
                   let range = instruction.cameraRanges[slice.index],
                   range.containsTime(request.compositionTime),
                   let buffer = request.sourceFrame(byTrackID: cameraID) {
                    camera = CIImage(cvPixelBuffer: buffer).transformed(by: instruction.cameraTransform)
                } else { camera = nil }
                let renderer = instruction.renderer
                let image = try renderer.render(
                    screen: CIImage(cvPixelBuffer: screen).transformed(by: instruction.screenTransform),
                    camera: camera, sourceTime: slice.sourceTime(at: request.compositionTime.seconds), slice: slice)
                renderer.context.render(image, to: output, bounds: renderer.canvas,
                                        colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                request.finish(withComposedVideoFrame: output)
            } catch { request.finish(with: error) }
        }
    }
}
