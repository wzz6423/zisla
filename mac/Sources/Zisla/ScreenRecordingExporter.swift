import AVFoundation
import Combine
import CoreImage
import Darwin
import Foundation
import ZislaCore
import ZislaKit

enum RecordingExportCheckpoint: Equatable, Sendable {
    case beforeRead
    case beforeWrite
    case frame(Int)
    case audioSample(Int)
    case beforeCommit
}

@MainActor
final class ScreenRecordingExporter: ObservableObject {
    @Published private(set) var progress = 0.0
    @Published private(set) var isExporting = false
    private var task: Task<Void, any Error>?
    private let checkpoint: @Sendable (RecordingExportCheckpoint) throws -> Void

    init(checkpoint: @escaping @Sendable (RecordingExportCheckpoint) throws -> Void = { _ in }) {
        self.checkpoint = checkpoint
    }

    func export(project: ScreenRecordingProject, directory: URL, to destination: URL,
                configuration: RecordingExportConfiguration) async throws {
        guard !isExporting else { throw ScreenRecordingExportError.exportInProgress }
        try Task.checkCancellation()
        progress = 0
        isExporting = true
        let checkpoint = self.checkpoint
        let worker = Task.detached(priority: .userInitiated) { [self] in
            try await RecordingExportJob.run(project: project, directory: directory, destination: destination,
                                             configuration: configuration, checkpoint: checkpoint) { value in
                await MainActor.run { self.progress = value }
            }
        }
        task = worker
        defer { task = nil; isExporting = false }
        try await withTaskCancellationHandler {
            try await worker.value
            progress = 1
        } onCancel: { worker.cancel() }
    }

    func cancel() { task?.cancel() }

    func playbackItem(project: ScreenRecordingProject, directory: URL) async throws -> AVPlayerItem {
        try Task.checkCancellation()
        if project.timeline != nil { return try await multitrackPlaybackItem(project: project, directory: directory) }
        let timeline = try RecordingExportTimeline(project: project)
        let media = try await RecordingExportMedia.prepare(project: project, directory: directory, timeline: timeline)
        let composition = media.video.composition
        let duration = CMTime(seconds: timeline.duration, preferredTimescale: 60_000)
        let cameraTrack: AVMutableCompositionTrack?
        if let camera = media.camera {
            guard let track = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw ScreenRecordingExportError.unavailableMedia
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: camera.track, at: .zero)
            cameraTrack = track
        } else { cameraTrack = nil }
        var audioTracks: [AVMutableCompositionTrack] = []
        for source in media.audioTracks {
            try Task.checkCancellation()
            guard let track = composition.addMutableTrack(withMediaType: .audio,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw ScreenRecordingExportError.unavailableMedia
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
            audioTracks.append(track)
        }
        try Task.checkCancellation()
        let item = AVPlayerItem(asset: composition)
        let original = try RecordingExportRenderer.outputSize(source: media.sourceSize, edits: project.edits,
                                                              resolution: .source)
        let scale = min(1, 1_280 / max(original.width, original.height))
        let size = CGSize(width: max(2, (original.width * scale / 2).rounded(.down) * 2),
                          height: max(2, (original.height * scale / 2).rounded(.down) * 2))
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = RecordingPlaybackCompositor.self
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [try RecordingPlaybackInstruction(
            project: project, media: media, cameraTrackID: cameraTrack?.trackID, size: size)]
        item.videoComposition = videoComposition
        if !audioTracks.isEmpty { item.audioMix = media.audioMix(for: audioTracks) }
        item.audioTimePitchAlgorithm = .spectral
        return item
    }

    func preview(project: ScreenRecordingProject, directory: URL, sourceTime: Double,
                 maximumSize: CGSize) async throws -> CGImage {
        if project.timeline != nil {
            let scene = try await multitrackPreview(project: project, directory: directory, time: sourceTime, maximumSize: maximumSize)
            return try scene.image(project: project)
        }
        try project.validate()
        guard sourceTime.isFinite, sourceTime >= 0, sourceTime <= project.duration,
              maximumSize.width.isFinite, maximumSize.height.isFinite,
              maximumSize.width >= 2, maximumSize.height >= 2 else {
            throw ScreenRecordingExportError.invalidConfiguration
        }
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let store = ScreenRecordingProjectStore(root: directory)
            let asset = AVURLAsset(url: try store.mediaURL(project.videoFile, in: directory))
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw ScreenRecordingExportError.unavailableMedia
            }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let source = CGRect(origin: .zero, size: natural).applying(transform).size
            let original = try RecordingExportRenderer.outputSize(source: source, edits: project.edits,
                                                                  resolution: .source)
            let scale = min(1, min(maximumSize.width / original.width, maximumSize.height / original.height))
            let size = CGSize(width: max(2, (original.width * scale / 2).rounded(.down) * 2),
                              height: max(2, (original.height * scale / 2).rounded(.down) * 2))
            let renderer = try RecordingExportRenderer(project: project, size: size)
            let time = CMTime(seconds: min(sourceTime, max(0, project.duration - 1.0 / 60_000)),
                              preferredTimescale: 60_000)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let screen = try await generator.image(at: time).image
            let camera: CGImage?
            if let file = project.cameraFile {
                let cameraAsset = AVURLAsset(url: try store.mediaURL(file, in: directory))
                guard let cameraTrack = try await cameraAsset.loadTracks(withMediaType: .video).first else {
                    throw ScreenRecordingExportError.unavailableMedia
                }
                let range = try await RecordingExportMedia.availableRange(of: cameraTrack)
                if time >= range.start, time < range.end {
                    let generator = AVAssetImageGenerator(asset: cameraAsset)
                    generator.appliesPreferredTrackTransform = true
                    generator.requestedTimeToleranceBefore = .zero
                    generator.requestedTimeToleranceAfter = .zero
                    camera = try await generator.image(at: time).image
                } else { camera = nil }
            } else { camera = nil }
            try Task.checkCancellation()
            return try renderer.image(screen: CIImage(cgImage: screen), camera: camera.map(CIImage.init(cgImage:)),
                                      sourceTime: sourceTime)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }
}

enum RecordingExportJob {
    static func run(project: ScreenRecordingProject, directory: URL, destination: URL,
                    configuration: RecordingExportConfiguration,
                    checkpoint: @escaping @Sendable (RecordingExportCheckpoint) throws -> Void,
                    progress: @escaping @Sendable (Double) async -> Void) async throws {
        if project.timeline != nil {
            try await RecordingMultitrackExportJob.run(project: project, directory: directory, destination: destination,
                configuration: configuration, checkpoint: checkpoint, progress: progress)
            return
        }
        let timeline = try RecordingExportTimeline(project: project)
        let schedule = try RecordingExportFrameSchedule(duration: timeline.duration, configuration: configuration)
        let target = try validateDestination(destination, directory: directory)
        try Task.checkCancellation()
        try checkpoint(.beforeRead)
        try Task.checkCancellation()
        let media = try await RecordingExportMedia.prepare(project: project, directory: directory, timeline: timeline)
        let size = try RecordingExportRenderer.outputSize(source: media.sourceSize, edits: project.edits,
                                                         resolution: configuration.resolution)
        let renderer = try RecordingExportRenderer(project: project, size: size)
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".zisla-recording-export-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let temporary = staging.appendingPathComponent("output.\(configuration.format.rawValue)")
        try checkpoint(.beforeWrite)
        try Task.checkCancellation()
        if configuration.format == .mp4 {
            let writer = try RecordingExportMP4Writer(url: temporary, media: media, renderer: renderer,
                                                      schedule: schedule, checkpoint: checkpoint)
            try await writer.run(progress: progress)
        } else {
            let primary = try RecordingExportFrameReader(media: media.video)
            let camera = try media.camera.map(RecordingExportFrameReader.init)
            defer { primary.cancel(); camera?.cancel() }
            let writer = try RecordingExportGIFWriter(url: temporary, size: size, frameRate: schedule.frameRate,
                                                       duration: timeline.duration)
            for index in 0..<schedule.frameCount {
                try Task.checkCancellation()
                try checkpoint(.frame(index))
                try Task.checkCancellation()
                let time = schedule.time(at: index)
                guard let slice = timeline.slice(at: time.seconds),
                      let screen = try primary.frame(at: time, slice: slice, useFirstFrame: true) else {
                    throw ScreenRecordingExportError.unavailableMedia
                }
                let cameraImage = try camera?.frame(at: time, slice: slice, useFirstFrame: false)
                try autoreleasepool {
                    let image = try renderer.image(screen: screen, camera: cameraImage,
                                                   sourceTime: slice.sourceTime(at: time.seconds), slice: slice)
                    try writer.append(image)
                }
                if index.isMultiple(of: max(1, schedule.frameRate / 10)) {
                    await progress(Double(index + 1) / Double(schedule.frameCount) * 0.98)
                }
            }
            try writer.finish()
        }
        try checkpoint(.beforeCommit)
        try Task.checkCancellation()
        _ = try validateDestination(target, directory: directory)
        guard Darwin.rename(temporary.path, target.path) == 0 else {
            throw ScreenRecordingExportError.invalidDestination
        }
        await progress(1)
    }

    static func validateDestination(_ destination: URL, directory: URL) throws -> URL {
        guard destination.isFileURL else { throw ScreenRecordingExportError.invalidDestination }
        let parent = destination.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let target = parent.appendingPathComponent(destination.lastPathComponent)
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
        guard target.path != root, !target.path.hasPrefix(root + "/") else {
            throw ScreenRecordingExportError.invalidDestination
        }
        if FileManager.default.fileExists(atPath: target.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil {
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw ScreenRecordingExportError.invalidDestination
            }
        }
        return target
    }
}

final class RecordingExportFrameReader {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let transform: CGAffineTransform
    private let ranges: [CMTimeRange?]
    private var currentSlice: Int?
    private var next: CMSampleBuffer?
    private var current: CVPixelBuffer?

    init(media: RecordingExportMediaTrack) throws {
        reader = try AVAssetReader(asset: media.composition)
        output = AVAssetReaderTrackOutput(track: media.track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        transform = media.transform
        ranges = media.availableRanges
        guard reader.canAdd(output) else { throw ScreenRecordingExportError.unavailableMedia }
        reader.add(output)
        guard reader.startReading() else { throw ScreenRecordingExportError.unavailableMedia }
        next = output.copyNextSampleBuffer()
    }

    deinit { reader.cancelReading() }

    func frame(at time: CMTime, slice: RecordingExportSlice, useFirstFrame: Bool) throws -> CIImage? {
        guard let range = ranges[slice.index], time < range.end,
              useFirstFrame || time >= range.start else { current = nil; return nil }
        if currentSlice != slice.index {
            currentSlice = slice.index
            current = nil
            while let sample = next, sample.presentationTimeStamp < range.start {
                next = output.copyNextSampleBuffer()
            }
        }
        while let sample = next, sample.presentationTimeStamp <= time, sample.presentationTimeStamp < range.end {
            current = sample.imageBuffer
            next = output.copyNextSampleBuffer()
        }
        if current == nil, let sample = next,
           sample.presentationTimeStamp >= range.start, sample.presentationTimeStamp < range.end {
            // At a VFR cut, consume the first available frame even if it is just after the grid timestamp.
            current = sample.imageBuffer
            next = output.copyNextSampleBuffer()
        }
        if reader.status == .failed { throw ScreenRecordingExportError.unavailableMedia }
        return current.map { RecordingExportRenderer.normalized(CIImage(cvPixelBuffer: $0).transformed(by: transform)) }
    }

    func cancel() { reader.cancelReading() }
}

private final class RecordingExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    private var failure: (any Error)?

    func cancel() { lock.withLock { requested = true } }
    func fail(_ error: any Error) { lock.withLock { failure = error } }
    func check() throws {
        try lock.withLock {
            if let failure { throw failure }
            if requested { throw CancellationError() }
        }
        try Task.checkCancellation()
    }
}

final class RecordingExportMP4Writer: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let frames: any RecordingExportFrameProviding
    private let audioReader: AVAssetReader?
    private let audioOutput: AVAssetReaderAudioMixOutput?
    private let audioInput: AVAssetWriterInput?
    private let duration: Double
    private let schedule: RecordingExportFrameSchedule
    private let checkpoint: @Sendable (RecordingExportCheckpoint) throws -> Void
    private let cancellation = RecordingExportCancellation()

    convenience init(url: URL, media: RecordingExportMedia, renderer: RecordingExportRenderer,
                     schedule: RecordingExportFrameSchedule,
                     checkpoint: @escaping @Sendable (RecordingExportCheckpoint) throws -> Void) throws {
        try self.init(url: url, frames: RecordingLegacyExportFrames(media: media, renderer: renderer),
            audioComposition: media.audioComposition, audioTracks: media.audioTracks,
            audioMix: media.audioMix(for: media.audioTracks), duration: media.timeline.duration,
            adjustsSpeed: media.timeline.slices.contains { $0.speed != 1 }, schedule: schedule, checkpoint: checkpoint)
    }

    init(url: URL, frames: any RecordingExportFrameProviding, audioComposition: AVMutableComposition?,
         audioTracks: [AVMutableCompositionTrack], audioMix: AVAudioMix, duration: Double, adjustsSpeed: Bool,
         schedule: RecordingExportFrameSchedule,
         checkpoint: @escaping @Sendable (RecordingExportCheckpoint) throws -> Void) throws {
        self.frames = frames
        self.duration = duration
        self.schedule = schedule
        self.checkpoint = checkpoint
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = Int(frames.canvas.width)
        let height = Int(frames.canvas.height)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: max(width, height) > 4_096 ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(80_000_000, max(250_000, width * height * schedule.frameRate / 5)),
                AVVideoExpectedSourceFrameRateKey: schedule.frameRate,
                AVVideoMaxKeyFrameIntervalKey: schedule.frameRate * 2,
                AVVideoAllowFrameReorderingKey: false,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ])
        guard writer.canAdd(videoInput) else { throw ScreenRecordingExportError.encoderFailure }
        writer.add(videoInput)
        if let composition = audioComposition, !audioTracks.isEmpty {
            let reader = try AVAssetReader(asset: composition)
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.audioMix = audioMix
            if adjustsSpeed { output.audioTimePitchAlgorithm = .spectral }
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw ScreenRecordingExportError.unavailableMedia }
            reader.add(output)
            reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration,
                                                                         preferredTimescale: 60_000))
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw ScreenRecordingExportError.encoderFailure }
            writer.add(input)
            audioReader = reader
            audioOutput = output
            audioInput = input
        } else { audioReader = nil; audioOutput = nil; audioInput = nil }
    }

    func run(progress: @escaping @Sendable (Double) async -> Void) async throws {
        try await withTaskCancellationHandler {
            defer {
                frames.cancel()
                audioReader?.cancelReading()
                if writer.status == .writing { writer.cancelWriting() }
            }
            guard writer.startWriting() else { throw ScreenRecordingExportError.encoderFailure }
            writer.startSession(atSourceTime: .zero)
            if let audioReader, !audioReader.startReading() { throw ScreenRecordingExportError.unavailableMedia }
            let audio = Task.detached(priority: .userInitiated) { [self] in
                do { try await writeAudio() }
                catch { cancellation.fail(error); throw error }
            }
            do {
                for index in 0..<schedule.frameCount {
                    try cancellation.check()
                    try checkpoint(.frame(index))
                    try await ready(videoInput)
                    let time = schedule.time(at: index)
                    try autoreleasepool {
                        guard let pool = adaptor.pixelBufferPool else { throw ScreenRecordingExportError.cannotRender }
                        var buffer: CVPixelBuffer?
                        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                              let buffer else { throw ScreenRecordingExportError.cannotRender }
                        let image = try frames.render(at: time)
                        frames.context.render(image, to: buffer, bounds: frames.canvas,
                                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                        guard adaptor.append(buffer, withPresentationTime: time) else {
                            throw ScreenRecordingExportError.encoderFailure
                        }
                    }
                    if index.isMultiple(of: max(1, schedule.frameRate / 10)) {
                        await progress(Double(index + 1) / Double(schedule.frameCount) * 0.95)
                    }
                }
                videoInput.markAsFinished()
                try await audio.value
                try cancellation.check()
                writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 60_000))
                await writer.finishWriting()
                try cancellation.check()
                guard writer.status == .completed else { throw ScreenRecordingExportError.encoderFailure }
            } catch {
                cancellation.cancel()
                audio.cancel()
                writer.cancelWriting()
                _ = try? await audio.value
                throw error
            }
        } onCancel: { [self] in
            cancellation.cancel()
            writer.cancelWriting()
        }
    }

    private func writeAudio() async throws {
        guard let audioInput, let audioOutput, let audioReader else { return }
        var index = 0
        while true {
            try cancellation.check()
            try await ready(audioInput)
            guard let sample = audioOutput.copyNextSampleBuffer() else {
                guard audioReader.status != .failed else { throw ScreenRecordingExportError.unavailableMedia }
                audioInput.markAsFinished()
                return
            }
            try checkpoint(.audioSample(index))
            guard audioInput.append(sample) else { throw ScreenRecordingExportError.encoderFailure }
            index += 1
        }
    }

    private func ready(_ input: AVAssetWriterInput) async throws {
        while !input.isReadyForMoreMediaData {
            try cancellation.check()
            guard writer.status == .writing else { throw ScreenRecordingExportError.encoderFailure }
            try await Task.sleep(for: .milliseconds(4))
        }
        try cancellation.check()
    }
}
