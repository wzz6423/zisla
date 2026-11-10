import AVFoundation
import Foundation
import Testing
import XCTest
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingPlaybackTests {
    @Test(arguments: [false, true])
    func pausingScrubbingAndReturningFromSourcePlaybackReusePreparedVoiceAudio(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        _ = try fixture.createTone()
        var source = project(fixture, multitrack: multitrack)
        source.microphoneFile = "tone.wav"
        source.edits.voiceEffects = .init(preset: .warm, amount: 0.8)
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        await model.previewTask?.value
        model.playTimeline()
        await model.operationTask?.value
        weak let prepared = model.activePlayer?.currentItem
        let sources = try await playbackSources(#require(prepared))
        let temporary = sources.filter { $0.deletingLastPathComponent() != fixture.directory }
        try #require(temporary.count == (multitrack ? 2 : 1), "The fixture must own processed PCM and, for multitrack, a playback clock")
        model.playTimeline()

        for start in [0.2, 0.05, 0.3, 0] {
            model.playSource()
            model.seekTimeline(to: start)
            await model.previewTask?.value
            model.playTimeline()
            await model.operationTask?.value

            #expect(model.isShowingTimelinePlayback && !model.isShowingSourcePlayback && !model.isBusy)
            #expect(try await playbackSources(#require(model.activePlayer?.currentItem)) == sources,
                "Resuming an unchanged timeline must reuse its PCM and playback clock instead of processing the whole recording again")
            #expect(abs(try #require(model.activePlayer).currentTime().seconds - start) < 0.05,
                "Reused playback must seek to the edited output position")
            #expect(temporary.allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
                "Prepared audio must remain available while the timeline can resume")
            model.playTimeline()
        }
        #expect(model.project == source && !model.isDirty && !model.canUndo)
        #expect(try fixture.files() == ["screen.mp4", "tone.wav"])
    }

    @Test(arguments: [false, true])
    func playingFromTheScrubbedEndImmediatelyReturnsToTheFirstOutputFrame(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        let source = project(fixture, multitrack: multitrack)
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        model.seekTimeline(to: source.outputDuration)
        await model.previewTask?.value
        let original = model.project

        model.playTimeline()

        #expect(model.playbackTime == 0, "Clicking Play at the end must reset the output playhead immediately")
        #expect(model.currentTime == (multitrack ? 0 : 1), "The first output frame must use the first edited source range")
        await model.operationTask?.value
        #expect(model.isShowingTimelinePlayback && !model.isBusy)
        #expect(model.activePlayer?.rate == 1)
        #expect(model.project == original && !model.isDirty && !model.canUndo)
    }

    @Test(arguments: [false, true], [false, true])
    func naturalCompletionKeepsTheLastFrameAndTheNextClickRestartsPlayback(_ multitrack: Bool, _ fractionalEnd: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        var source = project(fixture, multitrack: false)
        _ = try fixture.createTone()
        source.microphoneFile = "tone.wav"
        source.edits.voiceEffects = .init(preset: .warm, amount: 0.8)
        if fractionalEnd { source.edits.segments[1].end = 0.500_005 }
        if multitrack { source.timeline = .migrating(source) }
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        await model.previewTask?.value
        model.playTimeline()
        await model.operationTask?.value
        let player = try #require(model.activePlayer)
        player.pause()
        let item = try #require(player.currentItem)
        let sources = try await playbackSources(item)
        let ended = XCTNSNotificationExpectation(name: .AVPlayerItemDidPlayToEndTime, object: item)
        let stopped = XCTestExpectation(description: "The model stopped on the last output frame")
        let subscription = model.$isShowingTimelinePlayback.dropFirst().filter { !$0 }.prefix(1).sink { _ in stopped.fulfill() }
        defer { subscription.cancel() }
        await player.seek(to: .init(seconds: source.outputDuration - 0.125, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        let completion = await XCTWaiter.fulfillment(of: [ended, stopped], timeout: 5)
        try #require(completion == .completed,
            "The fixture must reach the actual AVPlayer item end: player \(player.currentTime().seconds), item \(item.duration.seconds), output \(source.outputDuration), playing \(model.isShowingTimelinePlayback), rate \(player.rate)")

        #expect(!model.isShowingTimelinePlayback, "Natural completion must leave the transport ready to play again")
        #expect(model.playbackTime == source.outputDuration, "The playhead must stay on the last frame until Play is clicked")
        #expect(model.currentTime == (multitrack ? source.outputDuration : source.edits.segments.last!.end))
        model.playTimeline()
        #expect(model.playbackTime == 0 && model.currentTime == (multitrack ? 0 : 1))
        await model.operationTask?.value
        #expect(model.isShowingTimelinePlayback && model.activePlayer?.rate == 1,
            "One click after completion must restart, rather than only clear a stale playing state")
        #expect(try await playbackSources(#require(model.activePlayer?.currentItem)) == sources,
            "Natural completion must not require reprocessing unchanged voice audio")
    }

    @Test(arguments: [false, true])
    func playingAndPausingInTheMiddlePreservesTheOutputPosition(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        let source = project(fixture, multitrack: multitrack)
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        model.seekTimeline(to: 0.125)
        await model.previewTask?.value
        model.playTimeline()
        await model.operationTask?.value
        model.playTimeline()
        #expect(!model.isShowingTimelinePlayback)
        let paused = model.playbackTime
        #expect(paused >= 0.125 && paused < source.outputDuration)

        model.playTimeline()
        #expect(model.playbackTime == paused, "Resuming in the middle must not rewind")
        await model.operationTask?.value
        #expect(model.isShowingTimelinePlayback && model.activePlayer?.rate == 1)
    }

    @Test(arguments: [false, true])
    func sourcePlaybackAlsoRestartsAfterScrubbingToItsEnd(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(project(fixture, multitrack: multitrack), directory: fixture.directory)
        await model.previewTask?.value
        model.seekSource(to: model.sourceDuration)
        let player = try #require(model.player)
        let seeked = await player.seek(to: .init(seconds: model.sourceDuration, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero)
        #expect(seeked)
        #expect(player.currentTime().seconds == model.sourceDuration,
            "Source-end fixture: model \(model.currentTime), player \(player.currentTime().seconds), duration \(player.currentItem?.duration.seconds ?? -1), source \(model.sourceDuration)")
        let firstFrame = XCTestExpectation(description: "Source playback returned to its first frame")
        let observer = player.addPeriodicTimeObserver(forInterval: .init(value: 1, timescale: 100), queue: .main) { time in
            if time.seconds >= 0 && time.seconds < 0.5 { firstFrame.fulfill() }
        }
        defer { player.removeTimeObserver(observer) }

        model.seekSource(to: model.sourceDuration)
        model.playSource()

        #expect(model.currentTime == 0, "Source replay must start at zero, regardless of the selected trimmed clip")
        #expect(model.isShowingSourcePlayback && player.rate == 1)
        #expect(await XCTWaiter.fulfillment(of: [firstFrame], timeout: 5) == .completed)
    }

    @Test
    func failedReplayDoesNotLeaveTheStudioBusyOrModifyTheProject() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let source = project(fixture, multitrack: false)
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        model.seekTimeline(to: source.outputDuration)
        await model.previewTask?.value

        model.playTimeline()
        await model.operationTask?.value

        #expect(model.operationTask == nil && !model.isBusy && !model.isShowingTimelinePlayback)
        #expect(model.errorMessage != nil && model.project == source && !model.isDirty)
        #expect(try fixture.files().isEmpty, "A failed replay must not create media or staging files")
    }

    @Test(arguments: [false, true], [false, true])
    func replacingOrShuttingDownPlaybackReleasesItsItemAndTemporaryMedia(_ replace: Bool, _ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        _ = try fixture.createTone()
        var source = project(fixture, multitrack: multitrack)
        source.microphoneFile = "tone.wav"
        source.edits.voiceEffects = .init(preset: .warm, amount: 0.8)
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        await model.previewTask?.value
        model.playTimeline()
        await model.operationTask?.value
        weak let released = model.activePlayer?.currentItem
        try #require(released != nil)
        let temporary = try await playbackSources(#require(released))
            .filter { $0.deletingLastPathComponent() != fixture.directory }
        try #require(temporary.count == (multitrack ? 2 : 1))

        if replace {
            model.install(source, directory: fixture.directory)
            await model.previewTask?.value
        } else { model.shutdown() }
        await drainMainQueue()
        #expect(await releasedMedia(temporary), "AVFoundation must release obsolete playback media after draining its pending requests")

        #expect(released == nil, "Playback must release its previous item and end observer")
        #expect(temporary.allSatisfy { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) },
            "A replaced or closed project must release its processed PCM and playback clock")
        #expect(!model.isShowingTimelinePlayback)
    }

    @Test(arguments: [false, true])
    func voiceEditsUndoAndRedoReplacePreparedAudioWithoutKeepingPreviousMedia(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        _ = try fixture.createTone()
        var source = project(fixture, multitrack: multitrack)
        source.microphoneFile = "tone.wav"
        source.edits.voiceEffects = .init(preset: .warm, amount: 0.8)
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        await model.previewTask?.value
        model.playTimeline()
        await model.operationTask?.value
        var previousSources = try await playbackSources(#require(model.activePlayer?.currentItem))
        let warmEnergy = try await voiceEnergy(#require(model.activePlayer?.currentItem))
        model.playTimeline()

        for action in 0..<3 {
            if action == 0 { model.update { $0.edits.voiceEffects = .init(preset: .broadcast, amount: 0.8) } }
            else if action == 1 { model.undo() }
            else { model.redo() }
            await model.previewTask?.value
            #expect(await releasedMedia(previousSources.filter { $0.deletingLastPathComponent() != fixture.directory }))
            #expect(previousSources.filter { $0.deletingLastPathComponent() != fixture.directory }
                .allSatisfy { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) },
                "Edits, undo and redo must release the obsolete prepared media")
            model.seekTimeline(to: 0)
            model.playTimeline()
            await model.operationTask?.value
            let item = try #require(model.activePlayer?.currentItem)
            let sources = try await playbackSources(item)
            let energy = try await voiceEnergy(item)
            #expect(sources != previousSources, "Each changed effect must prepare new audio")
            #expect(model.isShowingTimelinePlayback && !model.isBusy && model.operationTask == nil)
            if action == 1 { #expect(abs(energy - warmEnergy) < 0.0001, "Undo must restore the original warm audio") }
            else { #expect(abs(energy - warmEnergy) > 0.003, "The broadcast effect must change the rendered audio") }
            previousSources = sources
            model.playTimeline()
        }
        #expect(model.isDirty && model.canUndo && !model.canRedo)
        #expect(try fixture.files() == ["screen.mp4", "tone.wav"])
    }

    @Test(arguments: [false, true])
    func savingACopyChangesPlaybackToTheNewDirectoryAndReleasesPreparedMedia(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        _ = try fixture.createTone()
        var source = project(fixture, multitrack: multitrack)
        source.microphoneFile = "tone.wav"
        source.edits.voiceEffects = .init(preset: .warm, amount: 0.8)
        let suiteName = "zisla-playback-copy-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let destination = fixture.root.appendingPathComponent("copy.zisla-recording", isDirectory: true)
        let model = ScreenRecordingStudioModel(projectStore: fixture.store,
            outputDirectoryStore: .init(defaults: defaults),
            presentExportPanel: { _, completion in completion(destination) })
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        await model.previewTask?.value
        model.playTimeline()
        await model.operationTask?.value
        let originalSources = try await playbackSources(#require(model.activePlayer?.currentItem))
        model.playTimeline()
        model.saveCopy()
        await model.operationTask?.value
        await model.previewTask?.value
        #expect(model.directory == destination && model.errorMessage == nil && !model.isBusy)
        #expect(await releasedMedia(originalSources.filter { $0.deletingLastPathComponent() != fixture.directory }))
        #expect(originalSources.filter { $0.deletingLastPathComponent() != fixture.directory }
            .allSatisfy { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) })
        model.playTimeline()
        await model.operationTask?.value
        let copiedSources = try await playbackSources(#require(model.activePlayer?.currentItem))
        #expect(copiedSources.contains(destination.appendingPathComponent("screen.mp4")))
        #expect(!copiedSources.contains(fixture.directory.appendingPathComponent("screen.mp4")),
            "The copy must own its playback after the original directory changes")
        #expect(model.isShowingTimelinePlayback && !model.isDirty && model.errorMessage == nil)
    }

    @Test(arguments: [false, true])
    func cancellingAResumeKeepsPreparedMediaAndAllowsAnotherPlay(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        let source = project(fixture, multitrack: multitrack)
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        await model.previewTask?.value
        model.playTimeline()
        await model.operationTask?.value
        let sources = try await playbackSources(#require(model.activePlayer?.currentItem))
        model.playTimeline()
        model.playTimeline()
        model.cancelOperation()
        await model.operationTask?.value
        #expect(model.operationTask == nil && !model.isBusy && !model.isShowingTimelinePlayback && model.errorMessage == nil)
        model.playTimeline()
        await model.operationTask?.value
        #expect(model.isShowingTimelinePlayback && model.activePlayer?.rate == 1)
        #expect(try await playbackSources(#require(model.activePlayer?.currentItem)) == sources)
    }

    @Test(arguments: [false, true], [false, true])
    func closingOrReplacingTheProjectDuringResumeDoesNotRestartTheOldItem(_ replace: Bool, _ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        let source = project(fixture, multitrack: multitrack)
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        await model.previewTask?.value
        model.playTimeline()
        await model.operationTask?.value
        weak let item = model.activePlayer?.currentItem
        let sources = try await playbackSources(#require(item))
        model.playTimeline()
        model.seekTimeline(to: 0.2)
        await model.previewTask?.value
        var interrupted = false
        let subscription = model.$playbackTime.dropFirst().prefix(1).sink { _ in
            interrupted = true
            if replace { model.install(source, directory: fixture.directory) }
            else { model.shutdown() }
        }
        defer { subscription.cancel() }
        model.playTimeline()
        await model.operationTask?.value
        await model.previewTask?.value
        #expect(interrupted, "The close or replacement must occur after resuming starts")
        #expect(!model.isBusy && model.operationTask == nil && !model.isShowingTimelinePlayback)
        #expect(model.errorMessage == nil && model.project == source && !model.isDirty)
        #expect(await releasedMedia(sources.filter { $0.deletingLastPathComponent() != fixture.directory }))
        #expect(item == nil, "A cancelled seek must not restart or retain the obsolete playback item")
    }

    private func project(_ fixture: RecordingMultitrackTestFixture, multitrack: Bool) -> ScreenRecordingProject {
        var source = fixture.project()
        source.edits.segments = [.init(start: 1, end: 1.5, speed: 2), .init(start: 0, end: 0.5, speed: 2)]
        if multitrack { source.timeline = .migrating(source) }
        return source
    }

    private func drainMainQueue() async {
        for _ in 0..<4 {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    private func playbackSources(_ item: AVPlayerItem) async throws -> Set<URL> {
        var urls: Set<URL> = []
        for track in try await item.asset.load(.tracks) {
            for segment in try await track.load(.segments) {
                if let segment = segment as? AVCompositionTrackSegment, let url = segment.sourceURL { urls.insert(url) }
            }
        }
        return urls
    }

    private func voiceEnergy(_ item: AVPlayerItem) async throws -> Double {
        let sources = try await playbackSources(item)
        let url = try #require(sources.first { $0.pathExtension == "mov" })
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        return (0..<Int(buffer.frameLength)).reduce(0) { $0 + abs(Double(channel[$1])) } / Double(buffer.frameLength)
    }

    private func releasedMedia(_ urls: Set<URL>) async -> Bool {
        let released = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) }
        }, object: nil)
        return await XCTWaiter.fulfillment(of: [released], timeout: 5) == .completed
    }
}
