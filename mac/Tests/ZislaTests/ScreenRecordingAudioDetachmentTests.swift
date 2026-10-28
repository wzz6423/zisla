import AVFoundation
import CoreImage
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingAudioDetachmentTests {
    @Test func realProbeRejectsSilentVideoDespiteLegacyAudioMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        let project = fixture.project()
        #expect(RecordingMultitrackTimeline.migrating(project).assets[0].hasAudio)
        #expect(try await ScreenRecordingAudioDetachment.audioRanges(at: fixture.videoURL).isEmpty)
        #expect(try await ScreenRecordingAudioDetachment.prepare(project: project, directory: fixture.directory,
            clipID: project.edits.segments[0].id.uuidString) == nil)
        #expect(try fixture.files() == ["screen.mp4"])
    }

    @Test func detachingRecordingPreservesBothSourcesAndTheAuthoredTrimSpeedAndVolume() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(withAudio: true)
        try fixture.createTone(name: "microphone.wav", frequency: 880)
        var original = fixture.project(microphone: true)
        original.edits.segments = [.init(start: 0, end: 0.25), .init(start: 0.5, end: 1.5, speed: 2)]
        original.edits.screenAudioVolume = 0.4
        original.edits.microphoneVolume = 0.7
        let selected = original.edits.segments[1].id.uuidString
        let beforeFiles = try fixture.files()
        let detached = try #require(try await ScreenRecordingAudioDetachment.prepare(project: original,
            directory: fixture.directory, clipID: selected))
        let timeline = try #require(detached.timeline)
        let audio = timeline.clips.filter { $0.content.trackKind == .audio }

        #expect(detached.version == 2)
        #expect(timeline.clips.first { $0.id == selected }?.audioEnabled == false)
        #expect(timeline.clips.first { $0.id == original.edits.segments[0].id.uuidString }?.audioEnabled == true)
        #expect(audio.count == 2)
        #expect(audio.allSatisfy { $0.start == 0.25 && $0.sourceStart == 0.5 && $0.sourceEnd == 1.5 && $0.speed == 2 })
        #expect(Set(audio.map(\.volume)) == [0.4, 0.7])
        #expect(Set(audio.map(\.trackID)).count == 2)
        #expect(timeline.assets.filter { $0.kind == .audio }.map(\.file) == ["microphone.wav"])
        #expect(detached.edits == original.edits)
        #expect(try fixture.files() == beforeFiles, "Detaching must not transcode, copy, or remove source media")
        try detached.validate()
    }

    @Test func importedVideoDetachesAtItsOwnGainWithoutTheRecordingMicrophone() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(withAudio: true)
        var original = fixture.project(microphone: true)
        original.edits.screenAudioVolume = 0.3
        original.edits.microphoneVolume = 0.8
        var timeline = RecordingMultitrackTimeline.migrating(original)
        let trackID = timeline.addTrack(.video)
        timeline.tracks[timeline.tracks.count - 1].isMuted = true
        let imported = RecordingTimelineClip(trackID: trackID, content: .video(original.id),
            start: 3, sourceStart: 0.5, sourceEnd: 1.5, speed: 0.5, volume: 0.35)
        timeline.assets[0].hasAudio = false
        timeline.clips.append(imported)
        original.version = 2
        original.timeline = timeline
        let detached = try #require(try await ScreenRecordingAudioDetachment.prepare(project: original,
            directory: fixture.directory, clipID: imported.id))
        let result = try #require(detached.timeline)
        let audio = try #require(result.clips.first { $0.content.trackKind == .audio })

        #expect(result.assets.count == 1 && result.assets[0].hasAudio)
        #expect(audio.start == 3 && audio.sourceStart == 0.5 && audio.sourceEnd == 1.5 && audio.speed == 0.5)
        #expect(audio.volume == 0.35)
        #expect(result.tracks.first { $0.id == audio.trackID }?.isMuted == true)
        #expect(result.clips.filter { $0.content.trackKind == .audio }.count == 1)
    }

    @Test func microphoneOnlyRecordingDetachesOnceWithoutInventingSystemAudio() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo()
        try fixture.createTone(name: "microphone.wav", frequency: 880)
        let original = fixture.project(microphone: true)
        let selected = original.edits.segments[0].id.uuidString
        let detached = try #require(try await ScreenRecordingAudioDetachment.prepare(project: original,
            directory: fixture.directory, clipID: selected))
        let audio = try #require(detached.timeline?.clips.first { $0.content.trackKind == .audio })
        #expect(detached.timeline?.clips.filter { $0.content.trackKind == .audio }.count == 1)
        #expect(detached.timeline?.assets.first { $0.id == audio.content.assetID }?.file == "microphone.wav")
        #expect(audio.volume == 1, "Legacy default microphone gain must remain unchanged")
        #expect(try await ScreenRecordingAudioDetachment.prepare(project: detached,
            directory: fixture.directory, clipID: selected, probe: { _ in
                throw ScreenRecordingExportError.encoderFailure
            }) == nil)
    }

    @Test func delayedOrShortAudioRetainsItsOutputAlignment() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([1]).write(to: fixture.videoURL)
        var project = fixture.project()
        var timeline = RecordingMultitrackTimeline.migrating(project)
        timeline.clips[0].start = 3.5
        timeline.clips[0].sourceStart = 0.2
        timeline.clips[0].sourceEnd = 1.8
        timeline.clips[0].speed = 2
        project.version = 2
        project.timeline = timeline
        let detached = try #require(try await ScreenRecordingAudioDetachment.prepare(project: project,
            directory: fixture.directory, clipID: timeline.clips[0].id, probe: { _ in [0.4..<1.4] }))
        let audio = try #require(detached.timeline?.clips.first { $0.content.trackKind == .audio })
        #expect(abs(audio.start - 3.6) < 0.000_001)
        #expect(audio.sourceStart == 0.4 && audio.sourceEnd == 1.4 && audio.speed == 2)
        #expect(try await ScreenRecordingAudioDetachment.prepare(project: project,
            directory: fixture.directory, clipID: timeline.clips[0].id, probe: { _ in [1.9..<2] }) == nil)
    }

    @Test func missingSelectionAndDisabledAudioDoNotReadMediaOrChangeTheTimeline() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var project = fixture.project()
        #expect(try await ScreenRecordingAudioDetachment.prepare(project: project,
            directory: fixture.directory, clipID: "missing") == nil)
        project.timeline = RecordingMultitrackTimeline.migrating(project)
        project.version = 2
        project.timeline?.clips[0].audioEnabled = false
        #expect(try await ScreenRecordingAudioDetachment.prepare(project: project,
            directory: fixture.directory, clipID: project.edits.segments[0].id.uuidString) == nil)
        project.timeline?.clips[0].audioEnabled = true
        project.timeline?.clips[0].content = .audio(project.id)
        project.timeline?.tracks[0].kind = .audio
        #expect(try await ScreenRecordingAudioDetachment.prepare(project: project,
            directory: fixture.directory, clipID: project.edits.segments[0].id.uuidString) == nil)
        #expect(try fixture.files().isEmpty)
    }

    @Test func invalidInputAndTrackCapacityFailBeforeReturningAnEdit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var project = fixture.project()
        project.edits.microphoneVolume = .nan
        await #expect(throws: ScreenRecordingProjectError.invalidProject) {
            try await ScreenRecordingAudioDetachment.prepare(project: project,
                directory: fixture.directory, clipID: "missing")
        }
        project.edits.microphoneVolume = nil
        project.version = 2
        project.timeline = RecordingMultitrackTimeline.migrating(project)
        for _ in 0..<255 { project.timeline?.addTrack(.audio) }
        try project.validate()
        try Data([1]).write(to: fixture.videoURL)
        await #expect(throws: ScreenRecordingProjectError.invalidProject) {
            try await ScreenRecordingAudioDetachment.prepare(project: project, directory: fixture.directory,
                clipID: project.edits.segments[0].id.uuidString, probe: { _ in [0..<2] })
        }
        #expect(try fixture.files() == ["screen.mp4"])
    }

    @Test func unreadableSecondSourceDoesNotPartiallyDetachOrWriteMedia() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([1]).write(to: fixture.videoURL)
        try Data([2]).write(to: fixture.directory.appendingPathComponent("microphone.wav"))
        let original = fixture.project(microphone: true)
        let store = ScreenRecordingProjectStore(root: fixture.root)
        try store.save(original, in: fixture.directory)
        let snapshot = try Data(contentsOf: fixture.directory.appendingPathComponent("project.json"))
        await #expect(throws: ScreenRecordingExportError.unavailableMedia) {
            try await ScreenRecordingAudioDetachment.prepare(project: original, directory: fixture.directory,
                clipID: original.edits.segments[0].id.uuidString, probe: { url in
                    if url.lastPathComponent == "microphone.wav" { throw ScreenRecordingExportError.unavailableMedia }
                    return [0..<2]
                })
        }
        #expect(try store.load(from: fixture.directory) == original)
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("project.json")) == snapshot)
        #expect(try fixture.files() == ["microphone.wav", "project.json", "screen.mp4"])
    }

    @Test(arguments: [false, true])
    func cancellationAfterAnUncooperativeProbeNeverReturnsAnEdit(_ microphone: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([1]).write(to: fixture.videoURL)
        if microphone { try Data([2]).write(to: fixture.directory.appendingPathComponent("microphone.wav")) }
        let original = fixture.project(microphone: microphone)
        let gate = ProbeGate()
        let task = Task {
            try await ScreenRecordingAudioDetachment.prepare(project: original, directory: fixture.directory,
                clipID: original.edits.segments[0].id.uuidString, probe: { url in
                    if microphone, url.lastPathComponent == "screen.mp4" { return [0..<2] }
                    return try await gate.wait()
                })
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fixture.files() == (microphone ? ["microphone.wav", "screen.mp4"] : ["screen.mp4"]))
    }

    @Test func cancellationBeforePreparationDoesNotTouchMissingMedia() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let project = fixture.project()
        let gate = ProbeGate()
        let task = Task {
            _ = try await gate.wait()
            return try await ScreenRecordingAudioDetachment.prepare(project: project, directory: fixture.directory,
                clipID: project.edits.segments[0].id.uuidString)
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fixture.files().isEmpty)
    }

    @Test func microphoneWithoutAnAudioTrackDoesNotCreateAnEmptyClip() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([1]).write(to: fixture.videoURL)
        try Data([2]).write(to: fixture.directory.appendingPathComponent("microphone.wav"))
        let project = fixture.project(microphone: true)
        let detached = try #require(try await ScreenRecordingAudioDetachment.prepare(project: project,
            directory: fixture.directory, clipID: project.edits.segments[0].id.uuidString, probe: { url in
                url.lastPathComponent == "screen.mp4" ? [0..<2] : []
            }))
        #expect(detached.timeline?.assets.count == 1)
        #expect(detached.timeline?.clips.filter { $0.content.trackKind == .audio }.count == 1)
    }

    @Test func mediaSymlinkCannotEscapeTheProjectDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside.mp4")
        try Data([1]).write(to: outside)
        try FileManager.default.createSymbolicLink(at: fixture.videoURL, withDestinationURL: outside)
        let project = fixture.project()
        await #expect(throws: ScreenRecordingProjectError.unsafeMediaPath) {
            try await ScreenRecordingAudioDetachment.prepare(project: project, directory: fixture.directory,
                clipID: project.edits.segments[0].id.uuidString, probe: { _ in [0..<2] })
        }
        #expect(try Data(contentsOf: outside) == Data([1]))
        #expect(try fixture.files() == ["screen.mp4"])
    }

    @Test func detachedSourcesSurviveSaveReopenCopyAndOneStepUndoRedo() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(withAudio: true)
        try fixture.createTone(name: "microphone.wav", frequency: 880)
        let original = fixture.project(microphone: true)
        let store = ScreenRecordingProjectStore(root: fixture.root)
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(original, directory: fixture.directory)
        model.detachTimelineAudio(original.edits.segments[0].id.uuidString)
        await model.operationTask?.value
        let replacement = try #require(model.project)
        #expect(replacement.timeline?.clips.filter { $0.content.trackKind == .audio }.count == 2)
        #expect(model.canUndo && model.isDirty && !model.isBusy)
        model.undo()
        #expect(model.project == original && !model.canUndo && model.canRedo)
        model.redo()
        #expect(model.project == replacement && model.canUndo && !model.canRedo)
        try store.save(replacement, in: fixture.directory)
        #expect(try store.load(from: fixture.directory) == replacement)
        let destination = fixture.root.appendingPathComponent("copy.zisla-recording")
        try store.copy(replacement, from: fixture.directory, to: destination)
        #expect(try store.load(from: destination) == replacement)
        for name in replacement.mediaFiles {
            #expect(try Data(contentsOf: destination.appendingPathComponent(name))
                == Data(contentsOf: fixture.directory.appendingPathComponent(name)))
        }
    }

    @Test func independentAudioEditsAndDeletionUndoWithoutReenablingTheVideo() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([1]).write(to: fixture.videoURL)
        let original = fixture.project()
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(original, directory: fixture.directory)
        let selected = original.edits.segments[0].id.uuidString
        model.detachTimelineAudio(selected, probe: { _ in [0..<2] })
        await model.operationTask?.value
        let detached = try #require(model.project)
        let audioID = try #require(detached.timeline?.clips.first { $0.content.trackKind == .audio }?.id)
        model.moveTimelineClip(audioID, to: 0.75)
        let moved = try #require(model.project)
        #expect(moved.timeline?.clips.first { $0.id == audioID }?.start == 0.75)
        model.updateTimelineClip(audioID) { $0.sourceStart = 0.5; $0.sourceEnd = 1.5; $0.speed = 2; $0.volume = 0.25 }
        let trimmed = try #require(model.project)
        #expect(trimmed.timeline?.clips.first { $0.id == audioID }?.duration == 0.5)
        #expect(trimmed.timeline?.clips.first { $0.id == audioID }?.volume == 0.25)
        model.deleteTimelineClip(audioID)
        #expect(model.project?.timeline?.clips.contains { $0.id == audioID } == false)
        #expect(model.project?.timeline?.clips.first { $0.id == selected }?.audioEnabled == false)
        for expected in [trimmed, moved, detached, original] { model.undo(); #expect(model.project == expected) }
        for expected in [detached, moved, trimmed] { model.redo(); #expect(model.project == expected) }
    }

    enum LifecycleAction: CaseIterable, Sendable { case cancel, shutdown, replaceProject, replaceDirectory }

    @Test(arguments: LifecycleAction.allCases, [false, true])
    func lateAudioProbeCannotPublishAnEditOrErrorAfterItsOperationIsInvalidated(_ action: LifecycleAction,
                                                                              _ failure: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([1]).write(to: fixture.videoURL)
        let original = fixture.project()
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(original, directory: fixture.directory)
        await model.previewTask?.value
        let gate = ProbeGate()
        model.detachTimelineAudio(original.edits.segments[0].id.uuidString, probe: { _ in try await gate.wait() })
        let operation = try #require(model.operationTask)
        await gate.waitUntilEntered()
        #expect(model.isBusy)
        switch action {
        case .cancel: model.cancelOperation()
        case .shutdown: model.shutdown()
        case .replaceProject:
            var replacement = original
            replacement.name = "Different project"
            model.install(replacement, directory: fixture.directory)
        case .replaceDirectory:
            let replacement = fixture.root.appendingPathComponent("different.zisla-recording")
            try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false)
            try Data([1]).write(to: replacement.appendingPathComponent("screen.mp4"))
            model.install(original, directory: replacement)
        }
        let current = model.project
        await model.previewTask?.value
        if failure { await gate.reject() } else { await gate.release() }
        await operation.value
        #expect(model.project == current && !model.isDirty && !model.canUndo)
        #expect(model.errorMessage == nil, "A cancelled or stale task must not put an error on the active project")
        #expect(!model.isBusy && model.operationTask == nil)
    }

    @Test func detachingRepeatedOccurrencesReusesTheMicrophoneAsset() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([1]).write(to: fixture.videoURL)
        try Data([2]).write(to: fixture.directory.appendingPathComponent("microphone.wav"))
        var project = fixture.project(microphone: true)
        project.edits.segments = [.init(start: 0, end: 1), .init(start: 0.5, end: 1.5)]
        let selected = project.edits.segments.map { $0.id.uuidString }
        for id in selected {
            project = try #require(try await ScreenRecordingAudioDetachment.prepare(project: project,
                directory: fixture.directory, clipID: id, probe: { _ in [0..<2] }))
        }
        let timeline = try #require(project.timeline)
        #expect(timeline.assets.count == 2)
        #expect(timeline.clips.filter { $0.content.trackKind == .audio }.count == 4)
        #expect(timeline.clips.filter { $0.content.trackKind == .video }.allSatisfy { !$0.audioEnabled })
    }

    @Test func firstEmbeddedAudioTrackMatchesTheExistingPlaybackSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideoWithTwoAudioTracks()
        let asset = AVURLAsset(url: fixture.videoURL)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 2)
        let ranges = try await ScreenRecordingAudioDetachment.audioRanges(at: fixture.videoURL)
        let end = try #require(ranges.map(\.upperBound).max())
        #expect(end > 0.45 && end < 0.6, "The longer second track must not extend the audible source")
        var project = fixture.project()
        let detached = try #require(try await ScreenRecordingAudioDetachment.prepare(project: project,
            directory: fixture.directory, clipID: project.edits.segments[0].id.uuidString))
        #expect(detached.timeline?.clips.first { $0.content.trackKind == .audio }?.sourceEnd == end)
        let exporter = ScreenRecordingExporter()
        let preview = try await exporter.playbackItem(project: detached, directory: fixture.directory)
        let previewSamples = try await Self.audioSamples(preview.asset, mix: preview.audioMix)
        let destination = fixture.root.appendingPathComponent("first-track.mp4")
        try await exporter.export(project: detached, directory: fixture.directory, to: destination,
            configuration: .init(resolution: .source, frameRate: 4))
        let exported = try await Self.audioSamples(AVURLAsset(url: destination))
        for samples in [previewSamples, exported] {
            #expect(Self.toneEnergy(samples, frequency: 440, range: 0.1..<0.4) > 0.004)
            #expect(Self.toneEnergy(samples, frequency: 880, range: 0.1..<0.4) < 0.000_001)
            #expect(Self.toneEnergy(samples, frequency: 440, range: 0.75..<1.25) < 0.000_001)
            #expect(Self.toneEnergy(samples, frequency: 880, range: 0.75..<1.25) < 0.000_001)
        }
        project.edits.segments = [.init(start: 0.75, end: 1.5)]
        #expect(try await ScreenRecordingAudioDetachment.prepare(project: project,
            directory: fixture.directory, clipID: project.edits.segments[0].id.uuidString) == nil)
    }

    @Test func boundedTimingPropertiesKeepDetachedSamplesAtTheSameOutputTime() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([1]).write(to: fixture.videoURL)
        var seed: UInt64 = 7_301
        for _ in 0..<48 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let speed = [0.1, 0.5, 1, 2, 8][Int((seed >> 32) % 5)]
            let offset = Double(seed % 100) / 10
            var project = fixture.project()
            var timeline = RecordingMultitrackTimeline.migrating(project)
            timeline.clips[0].start = offset
            timeline.clips[0].sourceStart = 0.25
            timeline.clips[0].sourceEnd = 1.75
            timeline.clips[0].speed = speed
            timeline.clips[0].volume = Double(seed % 11) / 10
            project.version = 2
            project.timeline = timeline
            let detached = try #require(try await ScreenRecordingAudioDetachment.prepare(project: project,
                directory: fixture.directory, clipID: timeline.clips[0].id, probe: { _ in [0.5..<1.5] }))
            let audio = try #require(detached.timeline?.clips.first { $0.content.trackKind == .audio })
            for sourceTime in [0.5, 1, 1.5] {
                let originalTime = offset + (sourceTime - 0.25) / speed
                let detachedTime = audio.start + (sourceTime - audio.sourceStart) / audio.speed
                #expect(abs(originalTime - detachedTime) < 0.000_001)
            }
            #expect(audio.volume == timeline.clips[0].volume)
            try detached.validate()
            #expect(try JSONDecoder().decode(ScreenRecordingProject.self,
                from: JSONEncoder().encode(detached)) == detached)
        }
    }

    @Test(arguments: [0.5, 1.0, 2.0], [false, true])
    func realPreviewAndMP4PreserveBothGainsWithoutDoublePlayingDetachedSources(_ speed: Double,
                                                                            _ customGain: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(withAudio: true)
        try fixture.createTone(name: "microphone.wav", frequency: 880)
        var project = fixture.project(microphone: true)
        project.edits.segments = [.init(start: 0.5, end: 1.5, speed: speed)]
        if customGain {
            project.edits.screenAudioVolume = 0.3
            project.edits.microphoneVolume = 0.6
        }
        let exporter = ScreenRecordingExporter()
        let before = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let baseline = try await Self.audioSamples(before.asset, mix: before.audioMix)
        let detached = try #require(try await ScreenRecordingAudioDetachment.prepare(project: project,
            directory: fixture.directory, clipID: project.edits.segments[0].id.uuidString))
        let preview = try await exporter.playbackItem(project: detached, directory: fixture.directory)
        let previewSamples = try await Self.audioSamples(preview.asset, mix: preview.audioMix)
        let destination = fixture.root.appendingPathComponent("detached.mp4")
        try await exporter.export(project: detached, directory: fixture.directory, to: destination,
            configuration: .init(resolution: .source, frameRate: 4))
        let exported = try await Self.audioSamples(AVURLAsset(url: destination))
        let range = 0.1..<(project.outputDuration - 0.1)
        for frequency in [440.0, 880.0] {
            let energy = Self.toneEnergy(baseline, frequency: frequency, range: range)
            #expect(energy > 0.000_1)
            for samples in [previewSamples, exported] {
                let ratio = Self.toneEnergy(samples, frequency: frequency, range: range) / energy
                #expect((0.8...1.2).contains(ratio), "Detachment must preserve gain, not add or multiply the original sound")
            }
        }
    }

    @Test func realPreviewAndMP4UseTheMovedTrimmedAudioClipAndItsOwnGain() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(withAudio: true)
        try fixture.createTone(name: "microphone.wav", frequency: 880)
        let original = fixture.project(microphone: true)
        var project = try #require(try await ScreenRecordingAudioDetachment.prepare(project: original,
            directory: fixture.directory, clipID: original.edits.segments[0].id.uuidString))
        var timeline = try #require(project.timeline)
        let systemIndex = try #require(timeline.clips.firstIndex { $0.content == .audio(project.id) })
        timeline.clips[systemIndex].start = 0.5
        timeline.clips[systemIndex].sourceStart = 0.2
        timeline.clips[systemIndex].sourceEnd = 0.8
        timeline.clips[systemIndex].volume = 0.25
        let microphoneID = try #require(timeline.assets.first { $0.file == "microphone.wav" }?.id)
        timeline.clips.removeAll { $0.content == .audio(microphoneID) }
        project.timeline = timeline
        let exporter = ScreenRecordingExporter()
        let preview = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let previewSamples = try await Self.audioSamples(preview.asset, mix: preview.audioMix)
        let destination = fixture.root.appendingPathComponent("edited-audio.mp4")
        try await exporter.export(project: project, directory: fixture.directory, to: destination,
            configuration: .init(resolution: .source, frameRate: 4))
        let exported = try await Self.audioSamples(AVURLAsset(url: destination))
        for samples in [previewSamples, exported] {
            #expect(Self.toneEnergy(samples, frequency: 440, range: 0.1..<0.4) < 0.000_001)
            #expect((0.000_2...0.000_6).contains(Self.toneEnergy(samples, frequency: 440, range: 0.65..<0.95)))
            #expect(Self.toneEnergy(samples, frequency: 440, range: 1.3..<1.7) < 0.000_001)
            #expect(Self.toneEnergy(samples, frequency: 880, range: 0.65..<0.95) < 0.000_001,
                "Deleting the microphone clip must not revive the source video's microphone")
        }
        for trackMuted in [false, true] {
            var muted = timeline
            if trackMuted {
                let trackIndex = try #require(muted.tracks.firstIndex { $0.id == muted.clips[systemIndex].trackID })
                muted.tracks[trackIndex].isMuted = true
            } else {
                muted.clips[systemIndex].audioEnabled = false
            }
            project.timeline = muted
            let silent = try await exporter.playbackItem(project: project, directory: fixture.directory)
            #expect(try await silent.asset.loadTracks(withMediaType: .audio).isEmpty)
            let destination = fixture.root.appendingPathComponent("muted-\(trackMuted).mp4")
            try await exporter.export(project: project, directory: fixture.directory, to: destination,
                configuration: .init(resolution: .source, frameRate: 4))
            #expect(try await AVURLAsset(url: destination).loadTracks(withMediaType: .audio).isEmpty)
        }
        timeline.clips.removeAll { $0.content.trackKind == .audio }
        project.timeline = timeline
        let silent = try await exporter.playbackItem(project: project, directory: fixture.directory)
        #expect(try await silent.asset.loadTracks(withMediaType: .audio).isEmpty)
        let silentDestination = fixture.root.appendingPathComponent("deleted-audio.mp4")
        try await exporter.export(project: project, directory: fixture.directory, to: silentDestination,
            configuration: .init(resolution: .source, frameRate: 4))
        #expect(try await AVURLAsset(url: silentDestination).loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func realPreviewAndMP4KeepAdjacentAudioGainsConstantAndLeaveGapsSilent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.createVideo(withAudio: true)
        let original = fixture.project()
        var project = try #require(try await ScreenRecordingAudioDetachment.prepare(project: original,
            directory: fixture.directory, clipID: original.edits.segments[0].id.uuidString))
        var timeline = try #require(project.timeline)
        let audio = try #require(timeline.clips.first { $0.content.trackKind == .audio })
        timeline.clips.removeAll { $0.content.trackKind == .audio }
        for (start, gain) in [(0.0, 0.25), (0.5, 0.75), (1.5, 0.5)] {
            timeline.clips.append(.init(trackID: audio.trackID, content: audio.content, start: start,
                sourceStart: 0.25, sourceEnd: 0.75, volume: gain))
        }
        project.timeline = timeline
        let exporter = ScreenRecordingExporter()
        let preview = try await exporter.playbackItem(project: project, directory: fixture.directory)
        let previewSamples = try await Self.audioSamples(preview.asset, mix: preview.audioMix)
        let destination = fixture.root.appendingPathComponent("adjacent-audio.mp4")
        try await exporter.export(project: project, directory: fixture.directory, to: destination,
            configuration: .init(resolution: .source, frameRate: 4))
        let exported = try await Self.audioSamples(AVURLAsset(url: destination))
        for samples in [previewSamples, exported] {
            for (start, gain) in [(0.0, 0.25), (0.5, 0.75), (1.5, 0.5)] {
                let expected = pow(0.15 * gain / 2, 2)
                for window in [(start + 0.1)..<(start + 0.2), (start + 0.3)..<(start + 0.4)] {
                    let ratio = Self.toneEnergy(samples, frequency: 440, range: window) / expected
                    #expect((0.8...1.2).contains(ratio), "Each audio clip must keep its gain through the whole clip")
                }
            }
            #expect(Self.toneEnergy(samples, frequency: 440, range: 1.15..<1.35) < 0.000_001)
        }
    }

    private static func audioSamples(_ asset: AVAsset, mix: AVAudioMix? = nil) async throws -> [Float] {
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = mix
        output.audioTimePitchAlgorithm = .spectral
        reader.add(output)
        #expect(reader.startReading())
        defer { reader.cancelReading() }
        var samples = [Float](repeating: 0, count: Int((duration * 48_000).rounded(.up)))
        while let buffer = output.copyNextSampleBuffer() {
            let block = try #require(buffer.dataBuffer)
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            var values = [Float](repeating: 0, count: count)
            let result = values.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 4, destination: $0.baseAddress!)
            }
            #expect(result == kCMBlockBufferNoErr)
            let description = try #require(buffer.formatDescription.flatMap(CMAudioFormatDescriptionGetStreamBasicDescription))
            let channels = Int(description.pointee.mChannelsPerFrame)
            try #require(channels > 0)
            let start = Int((buffer.presentationTimeStamp.seconds * 48_000).rounded())
            for frame in 0..<(count / channels) where samples.indices.contains(start + frame) {
                let offset = frame * channels
                samples[start + frame] = values[offset..<(offset + channels)].reduce(0, +) / Float(channels)
            }
        }
        #expect(reader.status == .completed)
        return samples
    }

    private static func toneEnergy(_ samples: [Float], frequency: Double, range: Range<Double>) -> Double {
        let window = samples.dropFirst(Int(range.lowerBound * 48_000)).prefix(Int((range.upperBound - range.lowerBound) * 48_000))
        var real = 0.0
        var imaginary = 0.0
        for (index, sample) in window.enumerated() {
            let phase = 2 * Double.pi * frequency * Double(index) / 48_000
            real += Double(sample) * cos(phase)
            imaginary += Double(sample) * sin(phase)
        }
        return (real * real + imaginary * imaginary) / Double(max(1, window.count * window.count))
    }

    private actor ProbeGate {
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
        func reject() { continuation?.resume(throwing: ScreenRecordingExportError.unavailableMedia); continuation = nil }
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let directory: URL
        var videoURL: URL { directory.appendingPathComponent("screen.mp4") }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-detach-audio-tests-\(UUID())")
            directory = root.appendingPathComponent("fixture.zisla-recording")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
        func files() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() }

        func project(microphone: Bool = false) -> ScreenRecordingProject {
            var project = ScreenRecordingProject(name: "Audio fixture", videoFile: "screen.mp4",
                microphoneFile: microphone ? "microphone.wav" : nil, duration: 2, width: 64, height: 48)
            project.version = 1
            project.edits.background = .none
            project.edits.padding = 0
            project.edits.cornerRadius = 0
            project.edits.shadow = 0
            return project
        }

        func model() throws -> ScreenRecordingStudioModel {
            let image = try #require(CIContext().createCGImage(CIImage(color: CIColor(red: 0, green: 0, blue: 0)),
                from: CGRect(x: 0, y: 0, width: 64, height: 48)))
            return ScreenRecordingStudioModel(projectStore: ScreenRecordingProjectStore(root: root),
                renderPreview: { _, _, _ in image })
        }

        func createTone(name: String, frequency: Double) throws {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
            let settings: [String: Any] = name.hasSuffix(".m4a") ? [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000,
            ] : format.settings
            let file = try AVAudioFile(forWriting: directory.appendingPathComponent(name), settings: settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
            buffer.frameLength = 96_000
            let channel = try #require(buffer.floatChannelData?[0])
            for index in 0..<96_000 { channel[index] = Float(0.15 * sin(2 * .pi * frequency * Double(index) / 48_000)) }
            try file.write(from: buffer)
        }

        func createVideo(withAudio: Bool = false) async throws {
            let plain = directory.appendingPathComponent(withAudio ? "plain.mp4" : "screen.mp4")
            let writer = try AVAssetWriter(outputURL: plain, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
            ])
            writer.add(input)
            #expect(writer.startWriting())
            writer.startSession(atSourceTime: .zero)
            let context = CIContext()
            let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.7))
                .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
            for index in 0..<8 {
                while !input.isReadyForMoreMediaData { await Task.yield() }
                var buffer: CVPixelBuffer?
                #expect(CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer) == kCVReturnSuccess)
                context.render(image, to: try #require(buffer))
                #expect(adaptor.append(try #require(buffer), withPresentationTime: .init(value: Int64(index), timescale: 4)))
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: .init(seconds: 2, preferredTimescale: 600))
            await writer.finishWriting()
            #expect(writer.status == .completed)
            if withAudio {
                try createTone(name: "system.m4a", frequency: 440)
                try await NativeMediaMuxer().mux(videoURL: plain,
                    audioURL: directory.appendingPathComponent("system.m4a"), outputURL: videoURL)
                try FileManager.default.removeItem(at: plain)
                try FileManager.default.removeItem(at: directory.appendingPathComponent("system.m4a"))
            }
        }

        func createVideoWithTwoAudioTracks() async throws {
            try await createVideo()
            try createTone(name: "first.m4a", frequency: 440)
            try createTone(name: "second.m4a", frequency: 880)
            let screen = AVURLAsset(url: videoURL)
            let first = AVURLAsset(url: directory.appendingPathComponent("first.m4a"))
            let second = AVURLAsset(url: directory.appendingPathComponent("second.m4a"))
            let composition = AVMutableComposition()
            let video = try #require(try await screen.loadTracks(withMediaType: .video).first)
            let destinationVideo = try #require(composition.addMutableTrack(withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid))
            try destinationVideo.insertTimeRange(.init(start: .zero, duration: .init(seconds: 2, preferredTimescale: 600)),
                of: video, at: .zero)
            for (asset, duration) in [(first, 0.5), (second, 2.0)] {
                let source = try #require(try await asset.loadTracks(withMediaType: .audio).first)
                let destination = try #require(composition.addMutableTrack(withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid))
                try destination.insertTimeRange(.init(start: .zero,
                    duration: .init(seconds: duration, preferredTimescale: 600)), of: source, at: .zero)
            }
            let output = directory.appendingPathComponent("two-tracks.mp4")
            let session = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
            session.outputURL = output
            session.outputFileType = .mp4
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
            #expect(session.status == .completed)
            withExtendedLifetime([screen, first, second]) {}
            try FileManager.default.removeItem(at: videoURL)
            try FileManager.default.moveItem(at: output, to: videoURL)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("first.m4a"))
            try FileManager.default.removeItem(at: directory.appendingPathComponent("second.m4a"))
        }
    }
}
