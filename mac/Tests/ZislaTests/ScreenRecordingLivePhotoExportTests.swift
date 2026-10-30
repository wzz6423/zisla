import AVFoundation
import CoreImage
import ImageIO
import Photos
import Testing
import ZislaCore
@testable import Zisla

@MainActor
@Suite(.serialized, .timeLimit(.minutes(2)))
struct ScreenRecordingLivePhotoExportTests {
    @Test(arguments: [false, true])
    func exportsEditedFramesWithMatchedMetadataAndSystemRecognizableResources(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        try fixture.createTone()
        var project = fixture.project()
        project.microphoneFile = "tone.wav"
        project.edits.segments = [.init(start: 1, end: 2)]
        if multitrack {
            project.timeline = RecordingMultitrackTimeline.migrating(project)
            project.version = ScreenRecordingProject.currentVersion
        }
        let target = fixture.root.appendingPathComponent("Output.livephoto", isDirectory: true)
        let fractions = Fractions()
        try await ScreenRecordingLivePhotoExporter.run(project: project, directory: fixture.directory, destination: target,
            configuration: .init(format: .livePhoto, resolution: .source, frameRate: 30), checkpoint: { _ in }) {
                await fractions.append($0)
            }
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: target.path)) == ["photo.jpg", "video.mov"])
        let values = await fractions.values
        #expect(values == values.sorted() && values.last == 1 && values.contains { $0 > 0 && $0 < 1 })
        let resources = try await inspect(target)
        #expect(abs(resources.duration - 1) < 0.001)
        #expect(resources.audioCount == 1)
        #expect(resources.markerTime == 0.5 && resources.markerValue == 0)
        #expect(resources.markerType == kCMMetadataBaseDataType_SInt8 as String)
        #expect(resources.frames.count == 30)
        let photoPixel = try RecordingMultitrackTestFixture.pixel(resources.photo, x: 20, y: 20)
        #expect(photoPixel[2] > 180 && photoPixel[0] < 80, "The key photo must come from the trimmed blue half of the rendered timeline")
        for (_, image) in resources.frames {
            let pixel = try RecordingMultitrackTestFixture.pixel(image, x: 20, y: 20)
            #expect(pixel[2] > 180 && pixel[0] < 80, "The paired movie must preserve the final edited frames")
        }
        let live = try await requestLivePhoto(from: target)
        #expect(live.size == CGSize(width: 64, height: 48), "Photos must recognize the self-contained JPG/MOV resources without a library import")
        #expect(try noStagingFiles(in: fixture.root))
        #expect(try fixture.files() == ["screen.mp4", "tone.wav"])
    }

    @Test(arguments: [false, true])
    func theStudioExporterRoutesBothTimelineKindsToLivePhoto(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        var project = fixture.project()
        if multitrack {
            project.timeline = RecordingMultitrackTimeline.migrating(project)
            project.version = ScreenRecordingProject.currentVersion
        }
        let target = fixture.root.appendingPathComponent("From studio.livephoto", isDirectory: true)
        let exporter = ScreenRecordingExporter()
        try await exporter.export(project: project, directory: fixture.directory, to: target,
            configuration: .init(format: .livePhoto, resolution: .source))
        let resources = try await inspect(target)
        #expect(abs(resources.duration - 2) < 0.001)
        #expect(resources.frames.count == 60)
        #expect(exporter.progress == 1 && !exporter.isExporting)
        #expect(try noStagingFiles(in: fixture.root))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func rejectsNonfiniteProjectsBeforeAccessingMedia(_ duration: Double) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        var project = fixture.project()
        project.duration = duration
        let target = fixture.root.appendingPathComponent("Nonfinite.livephoto", isDirectory: true)
        await #expect(throws: ScreenRecordingProjectError.invalidProject) {
            try await ScreenRecordingLivePhotoExporter.run(project: project, directory: fixture.directory,
                destination: target, configuration: .init(format: .livePhoto, resolution: .source),
                checkpoint: { _ in Issue.record("Invalid projects must not access media") }, progress: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try noStagingFiles(in: fixture.root))
        #expect(try fixture.files().isEmpty)
    }

    @Test(arguments: [3.0, 6.0])
    func acceptsTheExactLimitAfterTrimmingOrSpeedingUp(_ sourceEnd: Double) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        try await fixture.createVideo(duration: 6)
        var project = ScreenRecordingProject(name: "Long source", videoFile: "screen.mp4", duration: 6, width: 64, height: 48)
        project.edits.showCursor = false
        project.edits.segments = [.init(start: 0, end: sourceEnd, speed: sourceEnd == 6 ? 2 : 1)]
        let target = fixture.root.appendingPathComponent("Boundary.livephoto", isDirectory: true)
        try await export(project, fixture: fixture, to: target)
        let resources = try await inspect(target)
        #expect(abs(resources.duration - 3) < 0.001)
        #expect(resources.frames.count == 90)
        #expect(resources.markerTime == 1.5)
        #expect(resources.audioCount == 0)
    }

    @Test func aShortSingleFrameClipKeepsItsMarkerInsideTheMovie() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        project.edits.segments = [.init(start: 0, end: 0.02)]
        let target = fixture.root.appendingPathComponent("Single frame.livephoto")
        try await export(project, fixture: fixture, to: target)
        let resources = try await inspect(target)
        #expect(abs(resources.duration - 0.02) < 0.001)
        #expect(resources.frames.count == 1 && resources.markerTime == 0)
        #expect(resources.markerTime + resources.markerDuration <= resources.duration)
        #expect(resources.markerDuration > 0)
    }

    @Test(arguments: [0.0, 3.0.nextUp, 3.001, 10.0])
    func refusesEmptyOrLongTimelinesBeforeReadingOrCreatingFiles(_ duration: Double) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        var project = ScreenRecordingProject(name: "Rejected", videoFile: "missing.mp4", duration: 10, width: 64, height: 48)
        project.edits.segments = duration == 0 ? [] : [.init(start: 0, end: duration)]
        let target = fixture.root.appendingPathComponent("Rejected.livephoto", isDirectory: true)
        await #expect(throws: RecordingLivePhotoExportError.durationExceeded) {
            try await ScreenRecordingLivePhotoExporter.run(project: project, directory: fixture.directory, destination: target,
                configuration: .init(format: .livePhoto, resolution: .source), checkpoint: { _ in
                    Issue.record("Unsupported Live Photo durations must not admit media reads or writes")
                }, progress: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try noStagingFiles(in: fixture.root))
        #expect(try fixture.files().isEmpty)
    }

    @Test func aLateSecondaryTrackCannotBeSilentlyTruncated() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        var project = fixture.project()
        var timeline = RecordingMultitrackTimeline.migrating(project)
        let track = timeline.addTrack()
        timeline.clips.append(.init(trackID: track, content: .video(project.id), start: 2, sourceEnd: 2))
        project.timeline = timeline
        project.version = ScreenRecordingProject.currentVersion
        #expect(project.outputDuration == 4)
        let target = fixture.root.appendingPathComponent("Too long.livephoto", isDirectory: true)
        await #expect(throws: RecordingLivePhotoExportError.durationExceeded) {
            try await export(project, fixture: fixture, to: target)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try noStagingFiles(in: fixture.root))
    }

    @Test(arguments: [false, true])
    func invalidFormatsAndFrameRatesCannotCreateOutput(_ invalidRate: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let target = fixture.root.appendingPathComponent("Invalid.livephoto")
        await #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
            try await ScreenRecordingLivePhotoExporter.run(project: fixture.project(), directory: fixture.directory,
                destination: target, configuration: .init(format: invalidRate ? .livePhoto : .mp4,
                    resolution: .source, frameRate: invalidRate ? 0 : 30), checkpoint: { _ in
                        Issue.record("Invalid export options must not admit media operations")
                    }, progress: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try noStagingFiles(in: fixture.root))
    }

    @Test(arguments: [false, true])
    func failuresAndCancellationBeforeCommitPreserveTheOldPair(_ cancelled: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        let project = fixture.project()
        let target = fixture.root.appendingPathComponent("Existing.livephoto", isDirectory: true)
        try await export(project, fixture: fixture, to: target)
        let originalPhoto = try Data(contentsOf: target.appendingPathComponent("photo.jpg"))
        let originalMovie = try Data(contentsOf: target.appendingPathComponent("video.mov"))
        do {
            try await ScreenRecordingLivePhotoExporter.run(project: project, directory: fixture.directory, destination: target,
                configuration: .init(format: .livePhoto, resolution: .source), checkpoint: { point in
                    if point == .beforeCommit {
                        if cancelled { throw CancellationError() }
                        throw CocoaError(.fileWriteOutOfSpace)
                    }
                }, progress: { _ in })
            Issue.record("The injected commit failure must propagate")
        } catch {
            if cancelled { #expect(error is CancellationError) }
            else { #expect((error as NSError).code == CocoaError.fileWriteOutOfSpace.rawValue) }
        }
        #expect(try Data(contentsOf: target.appendingPathComponent("photo.jpg")) == originalPhoto)
        #expect(try Data(contentsOf: target.appendingPathComponent("video.mov")) == originalMovie)
        #expect(try noStagingFiles(in: fixture.root))
    }

    @Test func replacementCommitsBothNewResourcesAsOneDirectory() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        var project = fixture.project()
        let target = fixture.root.appendingPathComponent("Replace.livephoto", isDirectory: true)
        try await export(project, fixture: fixture, to: target)
        let original = try await inspect(target)
        project.edits.segments = [.init(start: 1, end: 2)]
        try await export(project, fixture: fixture, to: target)
        let replacement = try await inspect(target)
        #expect(replacement.identifier != original.identifier)
        #expect(abs(replacement.duration - 1) < 0.001)
        #expect(try noStagingFiles(in: fixture.root))
    }

    @Test(arguments: ["project", "symlink", "ordinary-directory", "regular-file", "wrong-extension", "malformed-pair"])
    func rejectsUnsafeOrUnrelatedDestinationsWithoutReplacingThem(_ kind: String) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let original = Data("keep me".utf8)
        try original.write(to: outside.appendingPathComponent("unrelated.txt"))
        let target = kind == "project" ? fixture.directory.appendingPathComponent("Inside.livephoto")
            : fixture.root.appendingPathComponent(kind == "wrong-extension" ? "Wrong.mov" : "Unsafe.livephoto")
        if kind == "symlink" { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside) }
        else if kind == "ordinary-directory" { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
        else if kind == "regular-file" { try original.write(to: target) }
        else if kind == "malformed-pair" {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try original.write(to: target.appendingPathComponent("photo.jpg"))
            try original.write(to: target.appendingPathComponent("video.mov"))
        }
        await #expect(throws: ScreenRecordingExportError.invalidDestination) {
            try await export(fixture.project(), fixture: fixture, to: target)
        }
        #expect(try Data(contentsOf: outside.appendingPathComponent("unrelated.txt")) == original)
        if kind == "regular-file" { #expect(try Data(contentsOf: target) == original) }
        if kind == "symlink" { #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.path) == outside.path) }
        #expect(try noStagingFiles(in: fixture.root))
        #expect(try fixture.files().isEmpty)
    }

    @Test func sourceFailureAndTaskCancellationCleanOnlyTheirOwnTemporaryFiles() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let target = fixture.root.appendingPathComponent("Missing source.livephoto")
        do {
            try await export(fixture.project(), fixture: fixture, to: target)
            Issue.record("Missing source media must be reported")
        } catch { #expect(!(error is CancellationError)) }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try noStagingFiles(in: fixture.root))
        try await fixture.createVideo()
        let task = Task {
            try await ScreenRecordingLivePhotoExporter.run(project: fixture.project(), directory: fixture.directory, destination: target,
                configuration: .init(format: .livePhoto, resolution: .source), checkpoint: { point in
                    if point == .frame(3) { withUnsafeCurrentTask { $0?.cancel() } }
                }, progress: { _ in })
        }
        do { try await task.value; Issue.record("A cancelled render must not commit a Live Photo") }
        catch { #expect(error is CancellationError) }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try noStagingFiles(in: fixture.root))
        #expect(try fixture.files() == ["screen.mp4"])
    }

    @Test func aDestinationChangedDuringExportCannotReplaceAnUnrelatedDirectory() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        let target = fixture.root.appendingPathComponent("Changed.livephoto")
        let intruder = DestinationChange(target: target)
        await #expect(throws: ScreenRecordingExportError.invalidDestination) {
            try await ScreenRecordingLivePhotoExporter.run(project: fixture.project(), directory: fixture.directory,
                destination: target, configuration: .init(format: .livePhoto, resolution: .source), checkpoint: { _ in },
                progress: { fraction in
                    do { try await intruder.createUnrelatedDirectory(after: fraction) }
                    catch { Issue.record("The controlled destination change must succeed: \(error)") }
                })
        }
        #expect(try Data(contentsOf: target.appendingPathComponent("unrelated.txt")) == Data("keep me".utf8))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: target.path)) == ["unrelated.txt"])
        #expect(try noStagingFiles(in: fixture.root))
    }

    private func export(_ project: ScreenRecordingProject, fixture: RecordingMultitrackTestFixture, to target: URL) async throws {
        try await ScreenRecordingLivePhotoExporter.run(project: project, directory: fixture.directory, destination: target,
            configuration: .init(format: .livePhoto, resolution: .source), checkpoint: { _ in }, progress: { _ in })
    }

    private func noStagingFiles(in root: URL) throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy {
            !$0.hasPrefix(".zisla-live-photo-") && !$0.hasPrefix(".zisla-recording-export-")
        }
    }

    private struct Resources {
        let identifier: String
        let duration: Double
        let audioCount: Int
        let markerTime: Double
        let markerDuration: Double
        let markerValue: Int
        let markerType: String
        let photo: CGImage
        let frames: [(Double, CGImage)]
    }

    private func inspect(_ directory: URL) async throws -> Resources {
        let imageURL = directory.appendingPathComponent("photo.jpg")
        let source = try #require(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let maker = try #require(properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any])
        let identifier = try #require(maker["17"] as? String)
        #expect(UUID(uuidString: identifier) != nil)
        let photo = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let movie = AVURLAsset(url: directory.appendingPathComponent("video.mov"))
        let metadata = try await movie.load(.metadata)
        let contentIdentifier = try #require(metadata.first { $0.identifier == .quickTimeMetadataContentIdentifier })
        #expect(try await contentIdentifier.load(.stringValue) == identifier)
        let track = try #require(try await movie.loadTracks(withMediaType: .metadata).first)
        let reader = try AVAssetReader(asset: movie)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
        try #require(reader.startReading())
        defer { reader.cancelReading() }
        let group = try #require(adaptor.nextTimedMetadataGroup())
        let marker = try #require(group.items.first { $0.key as? String == "com.apple.quicktime.still-image-time" })
        let value = try #require(try await marker.load(.numberValue)?.intValue)
        let type = try #require(marker.dataType)
        #expect(adaptor.nextTimedMetadataGroup() == nil)
        return Resources(identifier: identifier, duration: try await movie.load(.duration).seconds,
            audioCount: try await movie.loadTracks(withMediaType: .audio).count, markerTime: group.timeRange.start.seconds,
            markerDuration: group.timeRange.duration.seconds,
            markerValue: value, markerType: type, photo: photo,
            frames: try await RecordingMultitrackTestFixture.decode(movie))
    }

    private func requestLivePhoto(from directory: URL) async throws -> PHLivePhoto {
        try await withCheckedThrowingContinuation { continuation in
            PHLivePhoto.request(withResourceFileURLs: [directory.appendingPathComponent("photo.jpg"),
                directory.appendingPathComponent("video.mov")], placeholderImage: nil, targetSize: .zero, contentMode: .aspectFit) {
                    photo, info in
                    if info[PHLivePhotoInfoIsDegradedKey] as? Bool == true { return }
                    if let photo { continuation.resume(returning: photo) }
                    else { continuation.resume(throwing: info[PHLivePhotoInfoErrorKey] as? Error ?? RecordingLivePhotoExportError.cannotCreate) }
                }
        }
    }

    private actor Fractions {
        var values: [Double] = []
        func append(_ value: Double) { values.append(value) }
    }

    private actor DestinationChange {
        let target: URL
        private var created = false
        init(target: URL) { self.target = target }
        func createUnrelatedDirectory(after fraction: Double) throws {
            guard fraction >= 0.98, !created else { return }
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try Data("keep me".utf8).write(to: target.appendingPathComponent("unrelated.txt"))
            created = true
        }
    }
}
