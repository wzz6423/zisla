import AppKit
import Foundation
import Speech
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingMultitrackEditingTests {
    @Test func firstMultitrackEditMigratesOnceAndUndoRestoresTheOriginalV1Manifest() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        var original = fixture.project()
        original.version = 1
        original.edits.segments = [.init(start: 1, end: 2, speed: 2), .init(start: 0, end: 1)]
        original.captions = [.init(start: 1.25, end: 1.75, text: "Repeated")]
        model.install(original, directory: fixture.directory)
        #expect(model.timeline?.clips.count == 3 && model.project?.timeline == nil && !model.isDirty)
        model.addTimelineTrack(.image)
        let edited = try #require(model.project)
        #expect(edited.version == 2 && edited.timeline?.tracks.last?.kind == .image)
        #expect(edited.edits.segments == original.edits.segments && edited.captions == original.captions)
        #expect(model.canUndo && model.isDirty)
        model.undo()
        #expect(model.project == original && model.canRedo)
        model.redo()
        #expect(model.project == edited)
        let before = model.project
        model.addTimelineTrack(.audio)
        #expect(model.timeline?.clips == before?.timeline?.clips, "A second edit must not migrate repeated overlays twice")
    }

    @Test func importedAssetsStayInTheLibraryUntilUserAddsEachToAnIndependentTrack() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let video = try await fixture.createVideo()
        let image = try fixture.createImage()
        let audio = try fixture.createTone()
        let original = fixture.project()
        model.install(original, directory: fixture.directory)
        model.importMedia([video, image, audio])
        let task = try #require(model.operationTask)
        await task.value
        let imported = try #require(model.project)
        let assets = Array(try #require(imported.timeline).assets.dropFirst())
        #expect(assets.map(\.kind) == [.video, .image, .audio])
        #expect(imported.timeline?.clips.map(\.id) == original.edits.segments.map { $0.id.uuidString })
        #expect(imported.timeline?.tracks.count == 1 && imported.outputDuration == original.outputDuration)
        #expect(model.canEdit && model.isDirty && model.canUndo)
        model.undo()
        #expect(model.project == original)
        model.redo()
        #expect(model.project == imported)
        for asset in assets { #expect(model.addAssetToTimeline(asset.id, at: 0) != nil) }
        #expect(model.timeline?.tracks.map(\.kind) == [.video, .video, .image, .audio])
        #expect(model.timeline?.clips.count == 4 && model.timeline?.assets == imported.timeline?.assets)
        try model.save()
        #expect(try fixture.store.load(from: fixture.directory) == model.project)
    }

    @Test func newLibraryProjectSavesWithNoClipsAndBecomesExportableAfterAnExplicitAdd() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let image = try fixture.createImage()
        model.importMedia([image])
        await model.operationTask?.value
        let library = try #require(model.project)
        let directory = try #require(model.directory)
        #expect(library.videoFile.isEmpty && library.timeline?.clips.isEmpty == true && library.timeline?.tracks.isEmpty == true)
        #expect(!model.canExport && model.canEdit && !model.isDirty)
        #expect(try fixture.store.load(from: directory) == library)
        #expect(model.addAssetToTimeline(try #require(library.timeline?.assets.first?.id), at: 1) != nil)
        #expect(model.canExport && model.project?.outputDuration == 6)
        model.undo()
        #expect(model.project == library && !model.canExport)
    }

    @Test(arguments: [false, true])
    func failedBatchImportRollsBackAllCopiedFilesAndPreservesThePreviousManifest(_ newProject: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let image = try fixture.createImage()
        let invalid = fixture.directory.appendingPathComponent("corrupt.png")
        try Data([1, 2, 3]).write(to: invalid)
        let video = fixture.directory.appendingPathComponent("screen.mp4")
        try Data([9]).write(to: video)
        let project = fixture.project()
        try fixture.store.save(project, in: fixture.directory)
        let files = try fixture.files()
        let directories = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        await #expect(throws: Error.self) {
            _ = try await RecordingMediaImporter.prepare(urls: [image, invalid], project: newProject ? nil : project,
                directory: newProject ? nil : fixture.directory, store: fixture.store)
        }
        #expect(try fixture.files() == files)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == directories)
        #expect(try fixture.store.load(from: fixture.directory) == project)
        #expect(try Data(contentsOf: invalid) == Data([1, 2, 3]))
    }

    @Test(arguments: [false, true])
    func cancellationAfterFirstCopiedAssetRemovesOnlyThisImportsFiles(_ newProject: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let image = try fixture.createImage()
        let second = try fixture.createImage("second.png")
        try Data([9]).write(to: fixture.directory.appendingPathComponent("screen.mp4"))
        let project = fixture.project()
        try fixture.store.save(project, in: fixture.directory)
        let files = try fixture.files()
        let directories = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        let checkpoint = ImportCheckpoint()
        await #expect(throws: CancellationError.self) {
            _ = try await RecordingMediaImporter.prepare(urls: [image, second], project: newProject ? nil : project,
                directory: newProject ? nil : fixture.directory, store: fixture.store, checkCancellation: {
                    try checkpoint.check()
                })
        }
        #expect(checkpoint.count == 3, "Cancellation must be injected after the first media has been decoded and copied")
        #expect(try fixture.files() == files)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == directories)
        #expect(try fixture.store.load(from: fixture.directory) == project)
    }

    @Test func duplicateAndSplitTextHaveIndependentContentAndAllEditsUndoAtomically() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        model.install(fixture.project(), directory: fixture.directory)
        let annotationID = try #require(model.addTimelineText())
        let clip = try #require(model.selectedTimelineClip)
        let duplicateID = try #require(model.duplicateTimelineClip(clip.id))
        let duplicate = try #require(model.timeline?.clips.first { $0.id == duplicateID })
        guard case let .annotation(copyID) = duplicate.content else { Issue.record("Text duplication must keep text content"); return }
        #expect(copyID != annotationID && duplicate.start == clip.end)
        model.update { project in
            if let index = project.edits.annotations?.firstIndex(where: { $0.id == copyID }) { project.edits.annotations?[index].text = "Copy" }
        }
        #expect(model.project?.edits.annotations?.first { $0.id == annotationID }?.text != "Copy")
        let beforeSplit = try #require(model.project)
        let tailID = try #require(model.splitTimelineClip(duplicateID, at: duplicate.start + 1))
        let tail = try #require(model.timeline?.clips.first { $0.id == tailID })
        #expect(tail.content != duplicate.content && tail.start == duplicate.start + 1)
        model.deleteTimelineClip(tailID)
        #expect(model.timeline?.clips.contains { $0.id == tailID } == false)
        model.undo()
        #expect(model.timeline?.clips.contains { $0.id == tailID } == true)
        model.undo()
        #expect(model.project == beforeSplit)
        model.redo()
        #expect(model.timeline?.clips.count == beforeSplit.timeline!.clips.count + 1)
    }

    @Test func trackOrderVisibilityMuteMoveTrimAndInvalidEditsPreserveTheLibraryAndRedo() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        model.install(fixture.project(), directory: fixture.directory)
        model.addTimelineTrack(.video)
        let initial = try #require(model.project)
        let clip = try #require(model.timeline?.clips.first)
        let secondTrack = try #require(model.timeline?.tracks.last?.id)
        model.moveTimelineClip(clip.id, to: 3, trackID: secondTrack)
        model.updateTimelineClip(clip.id) { $0.sourceStart = 0.25; $0.sourceEnd = 1.5; $0.speed = 2 }
        let edited = try #require(model.selectedTimelineClip)
        #expect(edited.start == 3 && edited.duration == 0.625 && edited.trackID == secondTrack)
        model.updateTimelineTrack(secondTrack) { $0.isHidden = true; $0.isMuted = true }
        #expect(model.timeline?.visibleClips(at: 3.2).isEmpty == true)
        model.moveTimelineTrack(secondTrack, by: -1)
        #expect(model.timeline?.tracks.first?.id == secondTrack)
        #expect(model.timeline?.assets == initial.timeline?.assets)
        model.undo()
        let valid = model.project
        #expect(model.canRedo)
        model.updateTimelineClip(clip.id) { $0.sourceEnd = 200 }
        #expect(model.project == valid && model.canRedo)
        model.moveTimelineClip("missing", to: 0)
        model.updateTimelineTrack("missing") { $0.name = "Changed" }
        #expect(model.project == valid && model.canRedo)
    }

    @Test func canvasSelectionRetainsTheSelectedOccurrenceAndSeeksMovedOverlaysOnOutputTime() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        var project = fixture.project()
        project.captions = [.init(start: 0, end: 1, text: "Caption")]
        project.edits.segments = [.init(start: 0, end: 1), .init(start: 0, end: 1)]
        project.timeline = .migrating(project)
        let content = RecordingTimelineContent.caption(project.captions[0].id)
        let copies = try #require(project.timeline?.clips.filter { $0.content == content })
        model.install(project, directory: fixture.directory)
        model.selectedTimelineClipID = copies[1].id
        model.selectCanvasTimelineContent(content)
        #expect(model.selectedTimelineClipID == copies[1].id)
        model.selectedTimelineClipID = nil
        model.seekTimeline(to: 1.25)
        model.selectCanvasTimelineContent(content)
        #expect(model.selectedTimelineClipID == copies[1].id)
        model.moveTimelineClip(copies[1].id, to: 7)
        model.seekOverlay(content, sourceStart: 0)
        #expect(model.playbackTime == 7 && model.currentTime == 7)
        let annotationID = try #require(model.addOverlayAnnotation(.rectangle))
        let captionID = try #require(model.addOverlayCaption())
        #expect(model.project?.edits.annotations?.first { $0.id == annotationID }?.start == 7)
        #expect(model.project?.captions.first { $0.id == captionID }?.start == 7)
        #expect(model.timeline?.clips.first { $0.content == .caption(captionID) }?.start == 7)
        model.seekTimeline(to: model.project!.outputDuration)
        let unchanged = model.project
        #expect(model.addOverlayCaption() == nil && model.addOverlayAnnotation(.text) == nil && model.project == unchanged)
    }

    @Test func cuttingAMovedCaptionTrimsOnlyVideoClipsOnItsOutputRangeAndSupportsUndo() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        var project = fixture.project()
        project.captions = [.init(start: 0, end: 0.5, text: "Caption")]
        var timeline = RecordingMultitrackTimeline.migrating(project)
        timeline.clips[0].start = 3
        timeline.clips[0].speed = 0.5
        let captionIndex = try #require(timeline.clips.firstIndex { $0.content == .caption(project.captions[0].id) })
        timeline.clips[captionIndex].start = 4
        timeline.clips[captionIndex].sourceStart = 0
        timeline.clips[captionIndex].sourceEnd = 1
        timeline.clips[captionIndex].speed = 1
        project.timeline = timeline
        model.install(project, directory: fixture.directory)
        model.selectedTimelineClipID = timeline.clips[captionIndex].id
        model.cutCaption(project.captions[0].id)
        let edited = try #require(model.project)
        let video = try #require(edited.timeline?.clips.filter { $0.content.trackKind == .video })
        #expect(video.count == 2 && video.map(\.start) == [3, 5])
        #expect(video[0].sourceEnd == 0.5 && video[1].sourceStart == 1 && video[1].sourceEnd == 2)
        #expect(video.allSatisfy { $0.speed == 0.5 } && edited.edits.segments == project.edits.segments)
        #expect(edited.timeline?.clips.first { $0.content == .caption(project.captions[0].id) } == timeline.clips[captionIndex])
        model.undo()
        #expect(model.project == project)
        model.redo()
        #expect(model.project == edited)
    }

    @Test func aLateCancelledAudioTaskCannotClearTheNextProjectsBusyState() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        try Data([1]).write(to: fixture.directory.appendingPathComponent("screen.mp4"))
        let firstGate = AudioGate()
        let secondGate = AudioGate()
        model.install(fixture.project(), directory: fixture.directory)
        model.detachTimelineAudio(try #require(model.selectedTimelineClipID), probe: { _ in try await firstGate.wait() })
        let oldTask = try #require(model.operationTask)
        await firstGate.waitUntilEntered()
        var next = fixture.project()
        next.id = UUID()
        next.name = "Next project"
        model.install(next, directory: fixture.directory)
        #expect(model.canEdit)
        model.detachTimelineAudio(try #require(model.selectedTimelineClipID), probe: { _ in try await secondGate.wait() })
        let newTask = try #require(model.operationTask)
        await secondGate.waitUntilEntered()
        await firstGate.release()
        await oldTask.value
        #expect(model.isBusy && model.operationTask != nil && model.project == next,
            "An obsolete task must not unlock the editor while the new project's operation is pending")
        await secondGate.release()
        await newTask.value
        #expect(model.canEdit && model.operationTask == nil && model.project?.timeline?.clips.count == 2)
    }

    @Test func libraryCaptionGenerationUsesTheSelectedMediaAndRetimesOnlyItsSelectedClip() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let audio = try fixture.createTone()
        _ = try fixture.createImage()
        var recognized: URL?
        let transcriber = ScreenRecordingTranscriber(dependencies: .init(authorizationStatus: { .authorized },
            requestAuthorization: { _ in }, onDeviceAvailable: { _ in true }, recognize: { url, _, complete in
                recognized = url
                complete(.success([.init(start: 0.5, end: 1.5, text: "Selected source")]))
                return {}
            }, scheduleDeadline: { _ in {} }))
        let model = ScreenRecordingStudioModel(transcriber: transcriber, projectStore: fixture.store)
        defer { model.shutdown() }
        let sound = RecordingMediaAsset(name: "Sound", file: "tone.wav", kind: .audio, duration: 2)
        let image = RecordingMediaAsset(name: "Image", file: "picture.png", kind: .image, duration: 5, width: 64, height: 48)
        var project = fixture.project()
        project.videoFile = ""
        project.edits.segments = []
        project.timeline = .init(assets: [image, sound], tracks: [.init(id: "audio", kind: .audio)], clips: [
            .init(id: "first", trackID: "audio", content: .audio(sound.id), start: 0, sourceEnd: 2),
            .init(id: "selected", trackID: "audio", content: .audio(sound.id), start: 7, sourceStart: 0.25, sourceEnd: 1.75, speed: 2),
        ])
        model.install(project, directory: fixture.directory)
        #expect(!model.canGenerateCaptions)
        model.generateCaptions()
        #expect(model.operationTask == nil && recognized == nil)
        model.selectTimelineClip("selected")
        #expect(model.canGenerateCaptions)
        model.generateCaptions()
        await model.operationTask?.value
        let caption = try #require(model.project?.captions.first)
        #expect(recognized == audio)
        #expect(caption.start == 7.125 && caption.end == 7.625)
        #expect(model.project?.captions.count == 1 && model.timeline?.clips.first { $0.content == .caption(caption.id) }?.start == 7.125)
        model.undo()
        #expect(model.project == project)
    }

    @Test func recordedTimelineCaptionGenerationKeepsMicrophonePriorityAfterMigration() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let microphone = try fixture.createTone("microphone.wav")
        var recognized: URL?
        let transcriber = ScreenRecordingTranscriber(dependencies: .init(authorizationStatus: { .authorized },
            requestAuthorization: { _ in }, onDeviceAvailable: { _ in true }, recognize: { url, _, complete in
                recognized = url
                complete(.success([.init(start: 0.25, end: 0.75, text: "Microphone")]))
                return {}
            }, scheduleDeadline: { _ in {} }))
        let model = ScreenRecordingStudioModel(transcriber: transcriber, projectStore: fixture.store)
        defer { model.shutdown() }
        var project = fixture.project()
        project.microphoneFile = "microphone.wav"
        project.timeline = .migrating(project)
        model.install(project, directory: fixture.directory)
        model.generateCaptions()
        await model.operationTask?.value
        #expect(recognized == microphone && model.project?.captions.first?.text == "Microphone")
    }

    private final class ImportCheckpoint: @unchecked Sendable {
        private let lock = NSLock()
        private var checks = 0
        var count: Int { lock.withLock { checks } }
        func check() throws {
            let value = lock.withLock { checks += 1; return checks }
            if value == 3 { throw CancellationError() }
        }
    }

    private actor AudioGate {
        private var continuation: CheckedContinuation<[Range<Double>], Error>?
        private var entered = false
        private var waiter: CheckedContinuation<Void, Never>?
        func wait() async throws -> [Range<Double>] {
            entered = true
            waiter?.resume()
            waiter = nil
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { waiter = $0 }
        }
        func release() { continuation?.resume(returning: [0..<2]); continuation = nil }
    }
}
