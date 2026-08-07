import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct NowPlayingMetadataStalenessTests {
    @Test
    func sameTrackFromAnotherApplicationDoesNotReusePreviousIcon() {
        let previous = snapshot(
            sourceBundleIdentifier: "com.tencent.QQMusicMac",
            sourcePID: 1,
            sourceIconData: Data([0x01])
        )
        let update = snapshot(
            sourceBundleIdentifier: "com.apple.Music",
            sourcePID: 2,
            sourceIconData: nil
        )

        let merged = NowPlayingService.mergingMetadata(update, previous: previous)

        #expect(merged.sourceBundleIdentifier == "com.apple.Music")
        #expect(merged.sourceIconData == nil)
    }

    @Test
    func sameTrackRefreshFromSameApplicationKeepsPreviousIcon() {
        let icon = Data([0x01])
        let previous = snapshot(
            sourceBundleIdentifier: "com.tencent.QQMusicMac",
            sourcePID: 1,
            sourceIconData: icon
        )
        let update = snapshot(
            sourceBundleIdentifier: "com.tencent.QQMusicMac",
            sourcePID: 1,
            sourceIconData: nil
        )

        let merged = NowPlayingService.mergingMetadata(update, previous: previous)

        #expect(merged.sourceIconData == icon)
    }

    @Test
    func mediaWithoutLyricsIdentityClearsPreviouslyResolvedLyrics() {
        let service = NowPlayingService()
        let lyrics = SyncedLyrics(lines: [.init(time: 0, text: "上一首歌词")])
        var previous = snapshot(
            sourceBundleIdentifier: "com.tencent.QQMusicMac",
            sourcePID: 1,
            sourceIconData: nil,
            lyrics: lyrics
        )
        service.applyLyrics(to: &previous)

        var current = NowPlayingSnapshot(
            title: "计算机考研 操作系统",
            artist: "",
            album: nil,
            artworkData: Data([0x02]),
            duration: nil,
            elapsedTime: nil,
            isPlaying: true,
            sourceBundleIdentifier: "com.apple.podcasts"
        )
        service.applyLyrics(to: &current)

        #expect(service.resolvedLyrics == nil)
        #expect(current.lyrics == nil)
    }

    private func snapshot(
        sourceBundleIdentifier: String?,
        sourcePID: pid_t?,
        sourceIconData: Data?,
        lyrics: SyncedLyrics? = nil
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: "同一首歌",
            artist: "同一位歌手",
            album: nil,
            artworkData: Data([0x02]),
            duration: 180,
            elapsedTime: 10,
            isPlaying: true,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourcePID: sourcePID,
            sourceIconData: sourceIconData,
            lyrics: lyrics
        )
    }
}
