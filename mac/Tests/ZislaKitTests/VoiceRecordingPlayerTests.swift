import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct VoiceRecordingPlayerTests {
    @Test
    func preparesAndStartsRequestedRecording() {
        let audioPlayer = StubVoiceAudioPlayer()
        var openedURL: URL?
        let player = VoiceRecordingPlayer { url in
            openedURL = url
            return audioPlayer
        }
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/voice.caf")

        let started = player.play(id: id, url: url)

        #expect(started)
        #expect(openedURL == url)
        #expect(audioPlayer.prepareCallCount == 1)
        #expect(audioPlayer.playCallCount == 1)
        #expect(player.activeRecordingID == id)
    }

    @Test
    func failedPreparationDoesNotPublishPlayingState() {
        let audioPlayer = StubVoiceAudioPlayer()
        audioPlayer.canPrepare = false
        let player = VoiceRecordingPlayer { _ in audioPlayer }

        let started = player.play(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/unplayable.caf")
        )

        #expect(!started)
        #expect(audioPlayer.prepareCallCount == 1)
        #expect(audioPlayer.playCallCount == 0)
        #expect(player.activeRecordingID == nil)
    }

    @Test
    func startingAnotherRecordingStopsThePreviousPlayer() {
        let first = StubVoiceAudioPlayer()
        let second = StubVoiceAudioPlayer()
        var players: [StubVoiceAudioPlayer] = [first, second]
        let player = VoiceRecordingPlayer { _ in players.removeFirst() }

        #expect(player.play(id: UUID(), url: URL(fileURLWithPath: "/tmp/first.caf")))
        let secondID = UUID()
        #expect(player.play(id: secondID, url: URL(fileURLWithPath: "/tmp/second.caf")))

        #expect(first.stopCallCount == 1)
        #expect(second.stopCallCount == 0)
        #expect(player.activeRecordingID == secondID)
    }
}

@MainActor
private final class StubVoiceAudioPlayer: VoiceAudioPlaying {
    var canPrepare = true
    var canPlay = true
    private(set) var prepareCallCount = 0
    private(set) var playCallCount = 0
    private(set) var stopCallCount = 0

    func prepareToPlay() -> Bool {
        prepareCallCount += 1
        return canPrepare
    }

    func play() -> Bool {
        playCallCount += 1
        return canPlay
    }

    func stop() {
        stopCallCount += 1
    }
}
