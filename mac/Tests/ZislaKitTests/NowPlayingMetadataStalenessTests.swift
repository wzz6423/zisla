import AppKit
import Combine
import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct NowPlayingMetadataStalenessTests {
    enum IconRecoverySource: CaseIterable {
        case remote, pidOnly, frameworkPID, audioFallback
    }

    @Test(arguments: IconRecoverySource.allCases)
    func iconRecoveryUpdatesOnlyTheCurrentMediaWithoutAnotherRemoteEvent(sourceKind: IconRecoverySource) async throws {
        let clock = ApplicationIconRetryClock()
        var availableIcon: NSImage?
        let cache = ApplicationIconDataCache(
            genericIcons: [],
            waitForRetry: { try await clock.wait() },
            applicationURL: { _ in URL(fileURLWithPath: "/test/player.app") },
            fileIcon: { _ in availableIcon },
            runningApplication: { _ in ("com.example.player", availableIcon) }
        )
        let bundleIdentifier = sourceKind == .pidOnly || sourceKind == .frameworkPID
            ? nil : "com.example.player"
        _ = cache.data(
            forApplication: bundleIdentifier ?? "pid:2000101",
            bundleIdentifier: bundleIdentifier,
            processIdentifier: 2_000_101
        )
        let remote = snapshot(
            sourceBundleIdentifier: bundleIdentifier,
            sourcePID: sourceKind == .frameworkPID ? nil : 2_000_101,
            sourceIconData: Data([0x01]),
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "当前歌词")])
        )
        let service = NowPlayingService(
            loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) },
            initialRemoteSnapshot: sourceKind == .audioFallback ? nil : remote,
            initialRemotePID: sourceKind == .frameworkPID ? 2_000_101 : nil,
            systemAudioIsAudible: sourceKind == .audioFallback,
            iconCache: cache
        )
        defer { service.stop() }
        let sources = sourceKind == .audioFallback
            ? [audioSource(id: "player", pid: 2_000_101, icon: nil)] : []
        service.registerApplicationIconObserver(from: sources)
        service.resolveSnapshot(from: sources)
        let previous = try #require(service.snapshot)
        await clock.scheduled(1)
        var notifications = NotificationCenter.default.notifications(
            named: ApplicationIconDataCache.didCacheIconNotification,
            object: cache
        ).makeAsyncIterator()

        availableIcon = iconImage()
        try clock.advance()
        _ = try #require(await notifications.next())
        let icon = try #require(cache.data(
            forApplication: bundleIdentifier ?? "pid:2000101",
            bundleIdentifier: bundleIdentifier,
            processIdentifier: 2_000_101
        ))

        var updated = try #require(service.snapshot)
        #expect(updated.sourceIconData == icon)
        #expect(updated.sourceIconData != previous.sourceIconData)
        updated.sourceIconData = previous.sourceIconData
        #expect(updated == previous)
    }

    @Test
    func iconNotificationsIgnoreUnrelatedSourcesMalformedKeysAndPausedMedia() throws {
        let cache = emptyIconCache()
        let remote = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 2_000_101,
            sourceIconData: Data([0x01]),
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "当前歌词")])
        )
        let service = NowPlayingService(
            loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) },
            initialRemoteSnapshot: remote,
            iconCache: cache
        )
        defer { service.stop() }
        service.publishSnapshot(remote)
        service.registerApplicationIconObserver(from: [])
        var updates: [NowPlayingSnapshot?] = []
        let observation = service.$snapshot.dropFirst().sink { updates.append($0) }
        defer { observation.cancel() }

        NotificationCenter.default.post(
            name: ApplicationIconDataCache.didCacheIconNotification,
            object: cache,
            userInfo: ["cacheKey": "com.example.other"]
        )
        NotificationCenter.default.post(
            name: ApplicationIconDataCache.didCacheIconNotification,
            object: cache
        )
        NotificationCenter.default.post(
            name: ApplicationIconDataCache.didCacheIconNotification,
            object: emptyIconCache(),
            userInfo: ["cacheKey": "com.example.player"]
        )
        #expect(service.snapshot == remote)
        #expect(updates.isEmpty)

        let paused = try #require(MediaRemoteAdapterClient.decodeNowPlayingInfo(Data("""
        {"title":"同一首歌","artist":"同一位歌手","playing":false,
         "processIdentifier":2000101,"bundleIdentifier":"com.example.player"}
        """.utf8)))
        service.consumeAdapterPayload(paused, from: [])
        updates.removeAll()
        NotificationCenter.default.post(
            name: ApplicationIconDataCache.didCacheIconNotification,
            object: cache,
            userInfo: ["cacheKey": "com.example.player"]
        )

        #expect(service.snapshot == nil)
        #expect(service.resolvedLyrics == nil)
        #expect(updates.isEmpty)
    }

    @Test
    func iconNotificationsFromPreviousSourcesOrClearedMediaCannotRestoreOldMetadata() throws {
        let cache = emptyIconCache()
        let remote = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 2_000_101,
            sourceIconData: Data([0x01]),
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "当前歌词")])
        )
        let service = NowPlayingService(
            loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) },
            initialRemoteSnapshot: remote,
            iconCache: cache
        )
        defer { service.stop() }
        service.publishSnapshot(remote)
        service.registerApplicationIconObserver(from: [])
        let resumed = try #require(MediaRemoteAdapterClient.decodeNowPlayingInfo(Data("""
        {"title":"重新播放的新曲目","artist":"新歌手","playing":true,
         "processIdentifier":2000102,"bundleIdentifier":"com.example.browser"}
        """.utf8)))
        service.consumeAdapterPayload(resumed, from: [])
        let previous = service.snapshot
        var updates: [NowPlayingSnapshot?] = []
        let observation = service.$snapshot.dropFirst().sink { updates.append($0) }
        defer { observation.cancel() }

        NotificationCenter.default.post(
            name: ApplicationIconDataCache.didCacheIconNotification,
            object: cache,
            userInfo: ["cacheKey": "com.example.player"]
        )

        #expect(service.snapshot == previous)
        #expect(updates.isEmpty)
        NotificationCenter.default.post(
            name: ApplicationIconDataCache.didCacheIconNotification,
            object: cache,
            userInfo: ["cacheKey": "com.example.browser"]
        )
        #expect(updates.count == 1)
        #expect(service.snapshot == previous)

        let empty = try #require(MediaRemoteAdapterClient.decodeNowPlayingInfo(Data("{}".utf8)))
        service.consumeAdapterPayload(empty, from: [])
        updates.removeAll()
        NotificationCenter.default.post(
            name: ApplicationIconDataCache.didCacheIconNotification,
            object: cache,
            userInfo: ["cacheKey": "com.example.browser"]
        )
        #expect(service.snapshot == nil)
        #expect(service.resolvedLyrics == nil)
        #expect(updates.isEmpty)
    }

    enum MediaClearAction: CaseIterable {
        case stop, pause, emptyPayload
    }

    @Test(arguments: MediaClearAction.allCases)
    func clearingMediaCancelsPendingIconRecoveryEvenWhenTheDependencyCompletesLate(action: MediaClearAction) async throws {
        let clock = ApplicationIconRetryClock(honorsCancellation: false)
        var availableIcon: NSImage?
        let cache = ApplicationIconDataCache(
            genericIcons: [],
            waitForRetry: { try await clock.wait() },
            applicationURL: { _ in URL(fileURLWithPath: "/test/player.app") },
            fileIcon: { _ in availableIcon },
            runningApplication: { _ in nil }
        )
        let remote = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 2_000_101,
            sourceIconData: nil,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "当前歌词")])
        )
        let service = NowPlayingService(
            loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) },
            initialRemoteSnapshot: remote,
            iconCache: cache
        )
        defer { service.stop() }
        var notifications: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: ApplicationIconDataCache.didCacheIconNotification,
            object: cache,
            queue: .main
        ) { notification in
            let key = notification.userInfo?["cacheKey"] as? String
            MainActor.assumeIsolated {
                if let key { notifications.append(key) }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        service.registerApplicationIconObserver(from: [])
        service.resolveSnapshot(from: [])
        await clock.scheduled(1)

        switch action {
        case .stop:
            service.stop()
        case .pause:
            var paused = remote
            paused.isPlaying = false
            service.publishSnapshot(paused)
        case .emptyPayload:
            let empty = try #require(MediaRemoteAdapterClient.decodeNowPlayingInfo(Data("{}".utf8)))
            service.consumeAdapterPayload(empty, from: [])
        }
        availableIcon = iconImage()
        try clock.advance()
        await clock.completed(1)

        #expect(service.snapshot == nil)
        #expect(service.resolvedLyrics == nil)
        #expect(notifications.isEmpty)
    }

    @Test
    func delayedEmptyPlaybackRefreshDoesNotClearMediaThatHasBecomeAudibleAgain() throws {
        let remote = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 2_000_101,
            sourceIconData: Data([0x01]),
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "当前歌词")])
        )
        let service = NowPlayingService(
            loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) },
            initialRemoteSnapshot: remote,
            systemAudioIsAudible: true,
            iconCache: emptyIconCache()
        )
        service.publishSnapshot(remote)
        let empty = try #require(MediaRemoteAdapterClient.decodeNowPlayingInfo(Data("{}".utf8)))

        service.consumePlaybackRefresh(empty, from: [])

        #expect(service.snapshot == remote)
        #expect(service.resolvedLyrics == remote.lyrics)
    }

    @Test
    func anEmptyPlaybackRefreshClearsPreviousMediaAndCanRecover() throws {
        let remote = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 2_000_101,
            sourceIconData: Data([0x01]),
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "当前歌词")])
        )
        let service = NowPlayingService(
            loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) },
            initialRemoteSnapshot: remote,
            iconCache: emptyIconCache()
        )
        service.publishSnapshot(remote)
        let empty = try #require(MediaRemoteAdapterClient.decodeNowPlayingInfo(Data("{}".utf8)))

        service.consumePlaybackRefresh(empty, from: [])
        #expect(service.snapshot == nil)
        #expect(service.resolvedLyrics == nil)
        #expect(service.lyricsTask == nil)
        service.resolveSnapshot(from: [])
        #expect(service.snapshot == nil)

        let resumed = try #require(MediaRemoteAdapterClient.decodeNowPlayingInfo(Data("""
        {"title":"新曲目","artist":"新歌手","playing":true,
         "processIdentifier":2000101,"bundleIdentifier":"com.example.player"}
        """.utf8)))
        service.consumeAdapterPayload(resumed, from: [])

        #expect(service.snapshot?.title == "新曲目")
        #expect(service.snapshot?.artist == "新歌手")
        #expect(service.snapshot?.sourceIconData == nil)
        #expect(service.snapshot?.artworkData == nil)
        #expect(service.snapshot?.lyrics == nil)
        #expect(service.resolvedLyrics == nil)
    }

    @Test
    func playbackRefreshReadFailureDoesNotClearAValidPlayingTrack() {
        let remote = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 2_000_101,
            sourceIconData: Data([0x01]),
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "当前歌词")])
        )
        let service = NowPlayingService(
            loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) },
            initialRemoteSnapshot: remote,
            iconCache: emptyIconCache()
        )
        service.publishSnapshot(remote)

        service.consumePlaybackRefresh(nil, from: [])
        service.resolveSnapshot(from: [])

        #expect(service.snapshot == remote)
        #expect(service.resolvedLyrics == remote.lyrics)
    }

    @Test(arguments: [false, true])
    func conflictingAudioSourceDiscardsTheEntireRemoteTrack(isAudible: Bool) {
        let oldLyrics = SyncedLyrics(lines: [.init(time: 0, text: "上一首歌词")])
        let old = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 2_000_101,
            sourceIconData: Data([0x01]),
            lyrics: oldLyrics
        )
        let service = NowPlayingService(
            loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) },
            initialRemoteSnapshot: old,
            systemAudioIsAudible: isAudible,
            iconCache: emptyIconCache()
        )
        service.publishSnapshot(old)
        let current = audioSource(id: "browser", pid: 2_000_102, icon: Data([0x03]))

        service.resolveSnapshot(from: [current])
        service.resolveSnapshot(from: [current])

        if isAudible {
            #expect(service.snapshot?.title == current.applicationName)
            #expect(service.snapshot?.artist != old.artist)
            #expect(service.snapshot?.sourceBundleIdentifier == current.bundleIdentifier)
            #expect(service.snapshot?.sourceIconData == current.iconData)
            #expect(service.snapshot?.supportsControls == false)
            #expect(service.snapshot?.artworkData == nil)
            #expect(service.snapshot?.album == nil)
            #expect(service.snapshot?.duration == nil)
            #expect(service.snapshot?.elapsedTime == nil)
            #expect(service.snapshot?.lyrics == nil)
        } else {
            #expect(service.snapshot == nil)
        }
        #expect(service.resolvedLyrics == nil)
        #expect(service.lyricsTask == nil)
        service.resolveSnapshot(from: [])
        #expect(service.snapshot == nil)
        #expect(service.resolvedLyrics == nil)
    }

    @Test(arguments: [false, true])
    func remoteTrackNeverBorrowsUnrelatedAudioSourceIdentity(hasRemoteIdentity: Bool) {
        let remote = snapshot(
            sourceBundleIdentifier: hasRemoteIdentity ? "com.example.player" : nil,
            sourcePID: hasRemoteIdentity ? 2_000_101 : nil,
            sourceIconData: nil,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "当前歌词")])
        )
        let service = NowPlayingService(
            loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) },
            initialRemoteSnapshot: remote,
            iconCache: emptyIconCache()
        )
        let frontmost = audioSource(id: "browser", pid: 2_000_102, icon: Data([0x03]))
        let background = audioSource(id: "meeting", pid: 2_000_103, icon: Data([0x04]))

        service.resolveSnapshot(from: [frontmost, background])

        #expect(service.snapshot?.title == remote.title)
        #expect(service.snapshot?.artist == remote.artist)
        #expect(service.snapshot?.sourceApplication == nil)
        #expect(service.snapshot?.sourceBundleIdentifier == remote.sourceBundleIdentifier)
        #expect(service.snapshot?.sourcePID == remote.sourcePID)
        #expect(service.snapshot?.sourceIconData == nil)
        #expect(service.snapshot?.artworkData == remote.artworkData)
        #expect(service.snapshot?.lyrics == remote.lyrics)
    }

    @Test
    func matchingAudioSourceDecoratesTheRemoteTrackWithoutChangingMetadata() {
        let source = audioSource(id: "player", pid: 2_000_101, icon: Data([0x03]))
        let remote = snapshot(
            sourceBundleIdentifier: source.bundleIdentifier,
            sourcePID: 2_000_101,
            sourceIconData: nil,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "当前歌词")])
        )
        let service = NowPlayingService(
            loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) },
            initialRemoteSnapshot: remote,
            iconCache: emptyIconCache()
        )

        service.resolveSnapshot(from: [source])

        #expect(service.snapshot?.title == remote.title)
        #expect(service.snapshot?.artist == remote.artist)
        #expect(service.snapshot?.sourceApplication == source.applicationName)
        #expect(service.snapshot?.sourceIconData == source.iconData)
        #expect(service.snapshot?.artworkData == remote.artworkData)
        #expect(service.snapshot?.lyrics == remote.lyrics)
    }

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
    func publishingPausedTrackClearsAllMediaBeforeNotifyingObserversAndCanResume() {
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
        var lyricsWhenPublished: [SyncedLyrics?] = []
        let observation = service.$snapshot.dropFirst().sink { _ in
            lyricsWhenPublished.append(service.resolvedLyrics)
        }
        defer { observation.cancel() }

        current.isPlaying = false
        service.publishSnapshot(current)
        #expect(service.snapshot == nil)
        #expect(service.resolvedLyrics == nil)
        #expect(service.lyricsTask == nil)
        #expect(lyricsWhenPublished == [nil])

        current.isPlaying = true
        service.publishSnapshot(current)
        #expect(service.snapshot?.lyrics == lyrics)
        #expect(service.snapshot?.isPlaying == true)
    }

    @Test(arguments: [false, true])
    func lateLyricsResponseCannotRestorePausedMedia(hasLyrics: Bool) async throws {
        let provider = DeferredLyricsProvider()
        let service = NowPlayingService(loadLyrics: { _, _, _ in
            await provider.load()
        })
        var current = snapshot(
            sourceBundleIdentifier: "com.example.player",
            sourcePID: 2_000_101,
            sourceIconData: Data([0x01])
        )
        service.publishSnapshot(current)
        let request = try #require(service.lyricsTask)
        await provider.waitForRequest()

        current.isPlaying = false
        service.publishSnapshot(current)
        #expect(request.isCancelled)
        await provider.complete(with: LyricsSearchResult(
            lyrics: hasLyrics ? SyncedLyrics(lines: [.init(time: 0, text: "延迟返回的旧歌词")]) : nil,
            artistName: hasLyrics ? "上一首歌手" : nil
        ))
        await request.value

        #expect(service.snapshot == nil)
        #expect(service.resolvedLyrics == nil)
        #expect(service.lyricsTask == nil)
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

    private func audioSource(id: String, pid: pid_t, icon: Data?) -> AudioPlaybackSource {
        AudioPlaybackSource(
            id: id,
            processIdentifiers: [pid],
            bundleIdentifier: "com.example.\(id)",
            applicationName: id,
            iconData: icon,
            isFrontmost: true
        )
    }

    private func emptyIconCache() -> ApplicationIconDataCache {
        ApplicationIconDataCache(
            genericIcons: [],
            waitForRetry: { throw CancellationError() },
            applicationURL: { _ in nil },
            fileIcon: { _ in nil },
            runningApplication: { _ in nil }
        )
    }

    private func iconImage() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1).setFill()
            rect.fill()
            return true
        }
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
