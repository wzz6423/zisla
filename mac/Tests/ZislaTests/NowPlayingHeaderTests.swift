import Testing

@testable import Zisla
@testable import ZislaKit

struct NowPlayingHeaderTests {
    @Test
    func mediaScrubTrackDistinguishesOtherwiseIdenticalSourceApplications() {
        let first = NowPlayingSnapshot(
            title: "同名曲目",
            artist: "同一艺人",
            album: nil,
            artworkData: nil,
            duration: 180,
            elapsedTime: 30,
            isPlaying: true,
            sourceBundleIdentifier: "com.apple.Music"
        )
        let second = NowPlayingSnapshot(
            title: "同名曲目",
            artist: "同一艺人",
            album: nil,
            artworkData: nil,
            duration: 180,
            elapsedTime: 30,
            isPlaying: true,
            sourceBundleIdentifier: "com.apple.podcasts"
        )

        #expect(MediaScrubTrack(first) != MediaScrubTrack(second))
    }
}
