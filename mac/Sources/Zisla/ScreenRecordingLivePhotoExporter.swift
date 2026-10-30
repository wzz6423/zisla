import AVFoundation
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZislaCore

enum RecordingLivePhotoExportError: LocalizedError, Equatable, Sendable {
    case durationExceeded
    case cannotCreate

    var errorDescription: String? {
        switch self {
        case .durationExceeded: AppLocalization.text("Live Photo 最长支持 3 秒，请缩短时间线")
        case .cannotCreate: AppLocalization.text("无法生成 Live Photo")
        }
    }
}

enum ScreenRecordingLivePhotoExporter {
    static let photoName = "photo.jpg"
    static let videoName = "video.mov"

    static func run(project: ScreenRecordingProject, directory: URL, destination: URL,
                    configuration: RecordingExportConfiguration,
                    checkpoint: @escaping @Sendable (RecordingExportCheckpoint) throws -> Void,
                    progress: @escaping @Sendable (Double) async -> Void) async throws {
        try Task.checkCancellation()
        try project.validate()
        guard configuration.format == .livePhoto else { throw ScreenRecordingExportError.invalidConfiguration }
        guard RecordingLivePhotoPolicy.supports(duration: project.outputDuration) else {
            throw RecordingLivePhotoExportError.durationExceeded
        }
        let schedule = try RecordingExportFrameSchedule(duration: project.outputDuration, configuration: configuration)
        let target = try await validateDestination(destination, directory: directory)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".zisla-live-photo-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let pair = staging.appendingPathComponent("pair.livephoto", isDirectory: true)
        try FileManager.default.createDirectory(at: pair, withIntermediateDirectories: false)
        let rendered = staging.appendingPathComponent("rendered.mov")
        var movieConfiguration = configuration
        movieConfiguration.format = .mov
        try await RecordingExportJob.run(project: project, directory: directory, destination: rendered,
            configuration: movieConfiguration, checkpoint: checkpoint,
            resolveFFmpeg: { try ScreenRecordingFFmpegTranscoder.resolveExecutable() },
            progress: { await progress($0 * 0.75) })
        try Task.checkCancellation()
        let identifier = UUID().uuidString
        let photoTime = schedule.time(at: schedule.frameCount / 2)
        let markerDuration = min(1.0 / Double(schedule.frameRate), project.outputDuration - photoTime.seconds)
        try await writePhoto(movie: rendered, destination: pair.appendingPathComponent(photoName),
            time: photoTime, identifier: identifier)
        try await RecordingLivePhotoMovieWriter.run(input: rendered, output: pair.appendingPathComponent(videoName),
            identifier: identifier, photoTime: photoTime, markerDuration: markerDuration,
            duration: project.outputDuration, checkpoint: checkpoint) { await progress(0.75 + $0 * 0.23) }
        try checkpoint(.beforeCommit)
        try Task.checkCancellation()
        _ = try await validateDestination(target, directory: directory)
        let replacing = FileManager.default.fileExists(atPath: target.path)
        let flags = replacing ? UInt32(RENAME_SWAP) : UInt32(RENAME_EXCL)
        guard Darwin.renamex_np(pair.path, target.path, flags) == 0 else {
            throw ScreenRecordingExportError.invalidDestination
        }
        await progress(1)
    }

    private static func writePhoto(movie: URL, destination: URL, time: CMTime, identifier: String) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: time).image
        try Task.checkCancellation()
        guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RecordingLivePhotoExportError.cannotCreate
        }
        CGImageDestinationAddImage(writer, image, [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier],
            kCGImageDestinationLossyCompressionQuality: 0.95,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw RecordingLivePhotoExportError.cannotCreate }
    }

    private static func validateDestination(_ destination: URL, directory: URL) async throws -> URL {
        guard destination.isFileURL, destination.pathExtension.lowercased() == RecordingExportFormat.livePhoto.fileExtension else {
            throw ScreenRecordingExportError.invalidDestination
        }
        let parent = destination.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let target = parent.appendingPathComponent(destination.lastPathComponent)
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
        guard target.path != root, !target.path.hasPrefix(root + "/") else {
            throw ScreenRecordingExportError.invalidDestination
        }
        if FileManager.default.fileExists(atPath: target.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil {
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  Set(try FileManager.default.contentsOfDirectory(atPath: target.path)) == [photoName, videoName] else {
                throw ScreenRecordingExportError.invalidDestination
            }
            for name in [photoName, videoName] {
                let file = target.appendingPathComponent(name)
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw ScreenRecordingExportError.invalidDestination
                }
            }
            let photoURL = target.appendingPathComponent(photoName)
            guard let source = CGImageSourceCreateWithURL(photoURL as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                  let maker = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any],
                  let identifier = maker["17"] as? String, UUID(uuidString: identifier) != nil else {
                throw ScreenRecordingExportError.invalidDestination
            }
            let metadata = try await AVURLAsset(url: target.appendingPathComponent(videoName)).load(.metadata)
            let match = metadata.first { $0.identifier == .quickTimeMetadataContentIdentifier }
            guard try await match?.load(.stringValue) == identifier else {
                throw ScreenRecordingExportError.invalidDestination
            }
        }
        return target
    }
}

private enum RecordingLivePhotoMovieWriter {
    static func run(input: URL, output: URL, identifier: String, photoTime: CMTime,
                    markerDuration: Double, duration: Double,
                    checkpoint: @escaping @Sendable (RecordingExportCheckpoint) throws -> Void,
                    progress: @escaping @Sendable (Double) async -> Void) async throws {
        let asset = AVURLAsset(url: input)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let contentIdentifier = AVMutableMetadataItem()
        contentIdentifier.identifier = .quickTimeMetadataContentIdentifier
        contentIdentifier.value = identifier as NSString
        writer.metadata = [contentIdentifier]
        var streams: [(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput, sample: CMSampleBuffer?)] = []
        for track in try await asset.load(.tracks) {
            let mediaType = track.mediaType
            guard mediaType == .video || mediaType == .audio else { continue }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let input = AVAssetWriterInput(mediaType: mediaType, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else { throw RecordingLivePhotoExportError.cannotCreate }
            reader.add(output)
            writer.add(input)
            streams.append((output, input, nil))
        }
        let stillTime = AVMutableMetadataItem()
        stillTime.keySpace = .quickTimeMetadata
        stillTime.key = "com.apple.quicktime.still-image-time" as NSString
        stillTime.value = NSNumber(value: Int8(0))
        stillTime.dataType = kCMMetadataBaseDataType_SInt8 as String
        let group = AVTimedMetadataGroup(items: [stillTime], timeRange: .init(start: photoTime,
            duration: CMTime(seconds: markerDuration, preferredTimescale: 60_000)))
        guard let format = group.copyFormatDescription() else { throw RecordingLivePhotoExportError.cannotCreate }
        let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: format)
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        guard writer.canAdd(metadataInput) else { throw RecordingLivePhotoExportError.cannotCreate }
        writer.add(metadataInput)
        defer {
            reader.cancelReading()
            if writer.status == .writing { writer.cancelWriting() }
        }
        guard writer.startWriting(), reader.startReading() else { throw RecordingLivePhotoExportError.cannotCreate }
        writer.startSession(atSourceTime: .zero)
        while !metadataInput.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing else { throw RecordingLivePhotoExportError.cannotCreate }
            try await Task.sleep(for: .milliseconds(4))
        }
        guard adaptor.append(group) else { throw RecordingLivePhotoExportError.cannotCreate }
        metadataInput.markAsFinished()
        for index in streams.indices {
            streams[index].sample = streams[index].output.copyNextSampleBuffer()
        }
        var count = 0
        while let index = streams.indices.filter({ streams[$0].sample != nil }).min(by: {
            streams[$0].sample!.presentationTimeStamp < streams[$1].sample!.presentationTimeStamp
        }) {
            try Task.checkCancellation()
            let stream = streams[index]
            while !stream.input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw RecordingLivePhotoExportError.cannotCreate }
                try await Task.sleep(for: .milliseconds(4))
            }
            if stream.input.mediaType == .audio { try checkpoint(.audioSample(count)) }
            guard stream.input.append(stream.sample!) else { throw RecordingLivePhotoExportError.cannotCreate }
            await progress(min(1, stream.sample!.presentationTimeStamp.seconds / duration))
            streams[index].sample = stream.output.copyNextSampleBuffer()
            if streams[index].sample == nil { streams[index].input.markAsFinished() }
            count += 1
        }
        guard reader.status == .completed else { throw RecordingLivePhotoExportError.cannotCreate }
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 60_000))
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw RecordingLivePhotoExportError.cannotCreate }
        await progress(1)
    }
}
