import Combine
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
    func sameTrackFromAnotherApplicationDoesNotReusePreviousArtwork() {
        let previous = snapshot(
            sourceBundleIdentifier: "com.tencent.QQMusicMac",
            sourcePID: 1,
            sourceIconData: Data([0x01])
        )
        let update = NowPlayingSnapshot(
            title: previous.title,
            artist: previous.artist,
            album: nil,
            artworkData: nil,
            duration: previous.duration,
            elapsedTime: 10,
            isPlaying: true,
            sourceBundleIdentifier: "com.apple.Music",
            sourcePID: 2,
            sourceIconData: nil
        )

        let merged = NowPlayingService.mergingMetadata(update, previous: previous)

        #expect(merged.artworkData == nil)
        #expect(merged.sourceIconData == nil)
    }

    @Test
    func updateWithoutSourceIdentityDoesNotReusePreviousArtwork() {
        let previous = snapshot(
            sourceBundleIdentifier: "com.tencent.QQMusicMac",
            sourcePID: 1,
            sourceIconData: Data([0x01])
        )
        let update = NowPlayingSnapshot(
            title: previous.title,
            artist: previous.artist,
            album: nil,
            artworkData: nil,
            duration: previous.duration,
            elapsedTime: 10,
            isPlaying: true,
            sourceBundleIdentifier: nil,
            sourcePID: nil,
            sourceIconData: nil
        )

        let merged = NowPlayingService.mergingMetadata(update, previous: previous)

        #expect(merged.artworkData == nil)
        #expect(merged.sourceIconData == nil)
    }

    @Test
    func sameApplicationWithReplacementProcessDoesNotReuseMetadata() {
        let previous = snapshot(
            sourceBundleIdentifier: "com.tencent.QQMusicMac",
            sourcePID: 1,
            sourceIconData: Data([0x01])
        )
        let update = NowPlayingSnapshot(
            title: previous.title,
            artist: previous.artist,
            album: nil,
            artworkData: nil,
            duration: previous.duration,
            elapsedTime: 10,
            isPlaying: true,
            sourceBundleIdentifier: "com.tencent.QQMusicMac",
            sourcePID: 2,
            sourceIconData: nil
        )

        let merged = NowPlayingService.mergingMetadata(update, previous: previous)

        #expect(merged.artworkData == nil)
        #expect(merged.sourceIconData == nil)
    }

    @Test
    func artworkRefreshRejectsAResponseWithAStaleOrMissingSource() {
        let expected = NowPlayingService.ArtworkRefreshIdentity(
            snapshot(
                sourceBundleIdentifier: "com.tencent.QQMusicMac",
                sourcePID: 1,
                sourceIconData: nil
            )
        )
        let missingSource = NowPlayingService.ArtworkRefreshIdentity(
            snapshot(
                sourceBundleIdentifier: nil,
                sourcePID: nil,
                sourceIconData: nil
            )
        )

        #expect(!expected.matches(
            NowPlayingSnapshot(
                title: "同一首歌",
                artist: "同一位歌手",
                album: nil,
                artworkData: Data([0x03]),
                duration: 180,
                elapsedTime: 10,
                isPlaying: true,
                sourceBundleIdentifier: nil,
                sourcePID: nil
            )
        ))
        #expect(!expected.matches(
            NowPlayingSnapshot(
                title: "同一首歌",
                artist: "同一位歌手",
                album: nil,
                artworkData: Data([0x03]),
                duration: 180,
                elapsedTime: 10,
                isPlaying: true,
                sourceBundleIdentifier: "com.apple.Music",
                sourcePID: 2
            )
        ))
        #expect(missingSource.matches(
            NowPlayingSnapshot(
                title: "同一首歌",
                artist: "同一位歌手",
                album: nil,
                artworkData: Data([0x03]),
                duration: 180,
                elapsedTime: 10,
                isPlaying: true
            )
        ))
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

    @Test
    func audioFallbackDoesNotReusePreviouslyResolvedLyrics() {
        let service = NowPlayingService()
        let lyrics = SyncedLyrics(lines: [.init(time: 0, text: "上一首歌词")])
        var previous = NowPlayingSnapshot(
            title: "芒果TV",
            artist: "正在播放音频",
            album: nil,
            artworkData: nil,
            duration: nil,
            elapsedTime: nil,
            isPlaying: true,
            sourceBundleIdentifier: "com.hunantv.imgo",
            lyrics: lyrics
        )
        service.applyLyrics(to: &previous)
        #expect(service.resolvedLyrics == lyrics)

        var fallback = NowPlayingSnapshot(
            title: "芒果TV",
            artist: "正在播放音频",
            album: nil,
            artworkData: nil,
            duration: nil,
            elapsedTime: nil,
            isPlaying: true,
            sourceBundleIdentifier: "com.hunantv.imgo",
            supportsControls: false
        )
        service.applyLyrics(to: &fallback)

        #expect(service.resolvedLyrics == nil)
        #expect(fallback.lyrics == nil)
    }

    @Test
    func publishingAudioFallbackClearsLyricsBeforeNotifyingObservers() {
        let service = NowPlayingService()
        let lyrics = SyncedLyrics(lines: [.init(time: 0, text: "上一首歌词")])
        var previous = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 1,
            sourceIconData: nil,
            lyrics: lyrics
        )
        service.applyLyrics(to: &previous)
        service.publishSnapshot(previous)
        var lyricsWhenPublished: [SyncedLyrics?] = []
        let observation = service.$snapshot.dropFirst().sink { _ in
            lyricsWhenPublished.append(service.resolvedLyrics)
        }
        defer { observation.cancel() }

        service.publishSnapshot(audioFallback())

        #expect(service.snapshot?.title == "Google Chrome")
        #expect(service.snapshot?.supportsControls == false)
        #expect(service.snapshot?.lyrics == nil)
        #expect(service.resolvedLyrics == nil)
        #expect(lyricsWhenPublished == [nil])
    }

    @Test
    func publishingNoMediaClearsPreviouslyResolvedLyrics() {
        let service = NowPlayingService()
        var previous = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 1,
            sourceIconData: nil,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "上一首歌词")])
        )
        service.applyLyrics(to: &previous)
        service.publishSnapshot(previous)

        service.publishSnapshot(nil)

        #expect(service.snapshot == nil)
        #expect(service.resolvedLyrics == nil)
    }

    @Test
    func publishingSameTrackKeepsItsLyricsThroughPauseAndResume() {
        let service = NowPlayingService()
        let lyrics = SyncedLyrics(lines: [.init(time: 0, text: "当前歌词")])
        var current = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 1,
            sourceIconData: nil,
            lyrics: lyrics
        )
        service.applyLyrics(to: &current)
        service.publishSnapshot(current)

        current.lyrics = nil
        current.isPlaying = false
        service.publishSnapshot(current)
        #expect(service.snapshot?.lyrics == lyrics)
        #expect(service.snapshot?.isPlaying == false)

        current.isPlaying = true
        service.publishSnapshot(current)
        #expect(service.snapshot?.lyrics == lyrics)
        #expect(service.snapshot?.isPlaying == true)
    }

    @Test(arguments: [false, true])
    func publishingMediaWithoutLyricsIdentityDiscardsEmbeddedLyrics(supportsControls: Bool) {
        let service = NowPlayingService()
        var invalid = audioFallback()
        invalid.supportsControls = supportsControls
        invalid.artist = supportsControls ? "" : invalid.artist
        invalid.lyrics = SyncedLyrics(lines: [.init(time: 0, text: "不属于当前媒体的歌词")])

        service.publishSnapshot(invalid)

        #expect(service.snapshot?.lyrics == nil)
        #expect(service.resolvedLyrics == nil)
        #expect(service.lyricsTask == nil)
    }

    @Test(arguments: [false, true], [false, true])
    func lateLyricsResponseCannotRestoreLyricsAfterMediaChanges(noMedia: Bool, hasLyrics: Bool) async throws {
        let provider = DeferredLyricsProvider()
        let service = NowPlayingService(loadLyrics: { _, _, _ in
            await provider.load()
        })
        var previous = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 1,
            sourceIconData: nil
        )
        service.applyLyrics(to: &previous)
        service.publishSnapshot(previous)
        let request = try #require(service.lyricsTask)
        await provider.waitForRequest()

        service.publishSnapshot(noMedia ? nil : audioFallback())
        let expected = service.snapshot
        #expect(request.isCancelled)
        await provider.complete(with: LyricsSearchResult(
            lyrics: hasLyrics ? SyncedLyrics(lines: [.init(time: 0, text: "延迟返回的旧歌词")]) : nil,
            artistName: hasLyrics ? "上一首歌手" : nil
        ))
        await request.value

        #expect(service.snapshot == expected)
        #expect(service.resolvedLyrics == nil)
        #expect(service.lyricsTask == nil)
    }

    @Test
    func publishingAnotherSongAfterAudioFallbackUsesItsOwnLyrics() {
        let service = NowPlayingService()
        service.publishSnapshot(audioFallback())
        let lyrics = SyncedLyrics(lines: [.init(time: 0, text: "新歌曲歌词")])
        let current = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 1,
            sourceIconData: nil,
            lyrics: lyrics
        )

        service.publishSnapshot(current)

        #expect(service.snapshot?.lyrics == lyrics)
        #expect(service.resolvedLyrics == lyrics)
    }

    private func audioFallback() -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: "Google Chrome",
            artist: "正在播放音频",
            album: nil,
            artworkData: nil,
            duration: nil,
            elapsedTime: nil,
            isPlaying: true,
            sourceBundleIdentifier: "com.google.Chrome",
            supportsControls: false
        )
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

private actor DeferredLyricsProvider {
    private var response: CheckedContinuation<LyricsSearchResult, Never>?
    private var requestWaiter: CheckedContinuation<Void, Never>?

    func load() async -> LyricsSearchResult {
        await withCheckedContinuation { continuation in
            response = continuation
            requestWaiter?.resume()
            requestWaiter = nil
        }
    }

    func waitForRequest() async {
        if response != nil { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func complete(with result: LyricsSearchResult) {
        response?.resume(returning: result)
        response = nil
    }
}
