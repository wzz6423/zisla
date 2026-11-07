import AVFoundation
import Foundation
import Testing
import XCTest
import ZislaCore
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingPlaybackTests {
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

    @Test(arguments: [false, true])
    func replacingOrShuttingDownPlaybackReleasesItsEndedItem(_ replace: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        let source = project(fixture, multitrack: false)
        let model = try fixture.model()
        defer { model.shutdown() }
        model.install(source, directory: fixture.directory)
        await model.previewTask?.value
        model.playTimeline()
        await model.operationTask?.value
        weak let released = model.activePlayer?.currentItem
        try #require(released != nil)

        if replace {
            model.playTimeline()
            model.playTimeline()
            await model.operationTask?.value
        } else { model.shutdown() }
        await drainMainQueue()

        #expect(released == nil, "Playback must release its previous item and end observer")
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
}
