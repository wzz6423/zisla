import AVFoundation
import CoreImage
import Darwin
import Foundation
import ZislaCore

protocol RecordingExportFrameProviding: AnyObject {
    var canvas: CGRect { get }
    var context: CIContext { get }
    func render(at time: CMTime) throws -> CIImage
    func cancel()
}

final class RecordingLegacyExportFrames: RecordingExportFrameProviding {
    private let primary: RecordingExportFrameReader
    private let camera: RecordingExportFrameReader?
    private let renderer: RecordingExportRenderer
    private let timeline: RecordingExportTimeline
    var canvas: CGRect { renderer.canvas }
    var context: CIContext { renderer.context }

    init(media: RecordingExportMedia, renderer: RecordingExportRenderer) throws {
        self.renderer = renderer
        timeline = media.timeline
        primary = try RecordingExportFrameReader(media: media.video)
        camera = try media.camera.map(RecordingExportFrameReader.init)
    }

    func render(at time: CMTime) throws -> CIImage {
        guard let slice = timeline.slice(at: time.seconds),
              let screen = try primary.frame(at: time, slice: slice, useFirstFrame: true) else {
            throw ScreenRecordingExportError.unavailableMedia
        }
        return try renderer.render(screen: screen,
            camera: camera?.frame(at: time, slice: slice, useFirstFrame: false),
            sourceTime: slice.sourceTime(at: time.seconds), slice: slice)
    }

    func cancel() { primary.cancel(); camera?.cancel() }
}

final class RecordingMultitrackExportFrames: RecordingExportFrameProviding {
    let media: RecordingMultitrackMedia
    let renderer: RecordingMultitrackRenderer
    private var readers: [CMPersistentTrackID: Reader] = [:]
    var canvas: CGRect { renderer.canvas }
    var context: CIContext { renderer.context }

    init(media: RecordingMultitrackMedia, project: ScreenRecordingProject, directory: URL, size: CGSize) throws {
        self.media = media
        renderer = try RecordingMultitrackRenderer(project: project, directory: directory, size: size)
        for track in media.videoTracks { readers[track.trackID] = try Reader(composition: media.composition, track: track) }
    }

    func render(at time: CMTime) throws -> CIImage {
        var frames: [String: CIImage] = [:]
        for clip in renderer.index.clips(at: time.seconds) where clip.content.trackKind == .video {
            for key in [clip.id, clip.id + ".camera"] {
                if let layer = media.layers[key], let frame = try readers[layer.trackID]?.frame(at: time, layer: layer,
                    allowsLeadingFrame: key == clip.id) { frames[key] = frame }
            }
        }
        return try renderer.render(frames: frames, at: time.seconds)
    }

    func cancel() { for reader in readers.values { reader.cancel() } }

    private final class Reader {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        var currentKey: String?
        var current: CVPixelBuffer?
        var next: CMSampleBuffer?

        init(composition: AVMutableComposition, track: AVMutableCompositionTrack) throws {
            reader = try AVAssetReader(asset: composition)
            output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw ScreenRecordingExportError.unavailableMedia }
            reader.add(output)
            guard reader.startReading() else { throw ScreenRecordingExportError.unavailableMedia }
            next = output.copyNextSampleBuffer()
        }

        deinit { reader.cancelReading() }
        func cancel() { reader.cancelReading() }

        func frame(at time: CMTime, layer: RecordingMultitrackVideoLayer, allowsLeadingFrame: Bool) throws -> CIImage? {
            guard time < layer.range.end, allowsLeadingFrame || time >= layer.range.start else { return nil }
            if currentKey != layer.key {
                currentKey = layer.key
                current = nil
                while let sample = next, sample.presentationTimeStamp < layer.range.start { next = output.copyNextSampleBuffer() }
            }
            while let sample = next, sample.presentationTimeStamp <= time, sample.presentationTimeStamp < layer.range.end {
                current = sample.imageBuffer
                next = output.copyNextSampleBuffer()
            }
            if current == nil, let sample = next, sample.presentationTimeStamp >= layer.range.start,
               sample.presentationTimeStamp < layer.range.end {
                current = sample.imageBuffer
                next = output.copyNextSampleBuffer()
            }
            if reader.status == .failed { throw ScreenRecordingExportError.unavailableMedia }
            return current.map { RecordingExportRenderer.normalized(CIImage(cvPixelBuffer: $0).transformed(by: layer.transform)) }
        }
    }
}

enum RecordingMultitrackExportJob {
    static func run(project: ScreenRecordingProject, directory: URL, destination: URL,
                    configuration: RecordingExportConfiguration,
                    checkpoint: @escaping @Sendable (RecordingExportCheckpoint) throws -> Void,
                    progress: @escaping @Sendable (Double) async -> Void) async throws {
        try project.validate()
        guard project.outputDuration > 0 else { throw ScreenRecordingExportError.emptyTimeline }
        let schedule = try RecordingExportFrameSchedule(duration: project.outputDuration, configuration: configuration)
        let target = try RecordingExportJob.validateDestination(destination, directory: directory)
        try Task.checkCancellation()
        try checkpoint(.beforeRead)
        let media = try await RecordingMultitrackMedia.prepare(project: project, directory: directory)
        let size = try RecordingExportRenderer.outputSize(source: CGSize(width: project.width, height: project.height),
            edits: project.edits, resolution: configuration.resolution)
        let frames = try RecordingMultitrackExportFrames(media: media, project: project, directory: directory, size: size)
        defer { frames.cancel() }
        let staging = target.deletingLastPathComponent().appendingPathComponent(".zisla-recording-export-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let temporary = staging.appendingPathComponent("output." + configuration.format.rawValue)
        try checkpoint(.beforeWrite)
        try Task.checkCancellation()
        if configuration.format == .mp4 {
            let writer = try RecordingExportMP4Writer(url: temporary, frames: frames,
                audioComposition: media.composition, audioTracks: media.audioTracks, audioMix: media.audioMix,
                duration: media.duration, adjustsSpeed: media.adjustsSpeed, schedule: schedule, checkpoint: checkpoint)
            try await writer.run(progress: progress)
        } else {
            let writer = try RecordingExportGIFWriter(url: temporary, size: size, frameRate: schedule.frameRate, duration: media.duration)
            for index in 0..<schedule.frameCount {
                try Task.checkCancellation()
                try checkpoint(.frame(index))
                try autoreleasepool {
                    let rendered = try frames.render(at: schedule.time(at: index))
                    guard let image = frames.context.createCGImage(rendered, from: frames.canvas, format: .RGBA8,
                        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw ScreenRecordingExportError.cannotRender }
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
        _ = try RecordingExportJob.validateDestination(target, directory: directory)
        guard Darwin.rename(temporary.path, target.path) == 0 else { throw ScreenRecordingExportError.invalidDestination }
        await progress(1)
    }
}
