import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct NowPlayingServiceTests {
    @Test
    func mediaRemoteDictionaryParsesMetadataAndPlaybackClock() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let artwork = Data([0x01, 0x02, 0x03])
        let dictionary: NSDictionary = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Track",
            "kMRMediaRemoteNowPlayingInfoArtist": "Artist",
            "kMRMediaRemoteNowPlayingInfoAlbum": "Album",
            "kMRMediaRemoteNowPlayingInfoDuration": NSNumber(value: 120),
            "kMRMediaRemoteNowPlayingInfoElapsedTime": NSNumber(value: 30),
            "kMRMediaRemoteNowPlayingInfoTimestamp": timestamp,
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 1),
            "kMRMediaRemoteNowPlayingInfoArtworkData": artwork,
            "kMRMediaRemoteNowPlayingInfoRepeatMode": NSNumber(value: 2),
            "kMRMediaRemoteNowPlayingInfoShuffleMode": NSNumber(value: 1),
            "kMRMediaRemoteNowPlayingInfoIsInWishList": NSNumber(value: true),
        ]

        let snapshot = try #require(NowPlayingService.parse(dictionary))

        #expect(snapshot.title == "Track")
        #expect(snapshot.artist == "Artist")
        #expect(snapshot.isPlaying)
        #expect(snapshot.artworkData == artwork)
        #expect(snapshot.elapsedTime(at: timestamp.addingTimeInterval(12)) == 42)
        #expect(snapshot.playbackMode == .repeatOne)
        #expect(snapshot.supportsPlaybackModeControl)
        #expect(snapshot.isFavorite == true)
        #expect(snapshot.favoriteControl == .wishList)
    }

    @Test
    func adapterPayloadParsesSystemNowPlayingMetadata() throws {
        let artwork = Data([0x01, 0x02, 0x03])
        let data = try #require(
            """
            {
              "type": "data",
              "diff": false,
              "payload": {
                "title": "国际孤独等级",
                "artist": "Gareth.T",
                "album": "国际孤独等级",
                "artworkData": "\(artwork.base64EncodedString())",
                "duration": 193,
                "elapsedTime": 67,
                "timestamp": "2026-07-20T23:22:03Z",
                "playing": true,
                "processIdentifier": 1339,
                "bundleIdentifier": "com.tencent.QQMusicMac",
                "repeatMode": 2,
                "shuffleMode": 1
              }
            }
            """.data(using: .utf8)
        )
        let event = try JSONDecoder().decode(MediaRemoteAdapterEvent.self, from: data)

        let snapshot = try #require(NowPlayingService.parseAdapter(event.payload))

        #expect(snapshot.title == "国际孤独等级")
        #expect(snapshot.artist == "Gareth.T")
        #expect(snapshot.artworkData == artwork)
        #expect(snapshot.isPlaying)
        #expect(snapshot.sourcePID == 1339)
        #expect(snapshot.sourceBundleIdentifier == "com.tencent.QQMusicMac")
        #expect(snapshot.playbackMode == .repeatOne)
        #expect(snapshot.supportsPlaybackModeControl)
    }

    @Test
    func adapterGetResponseDecodesArtworkPayload() throws {
        let artwork = Data([0x04, 0x05, 0x06])
        let data = try #require(
            """
            {
              "title": "自动切换后的曲目",
              "artist": "Artist",
              "artworkData": "\(artwork.base64EncodedString())",
              "duration": 180,
              "playing": true
            }
            """.data(using: .utf8)
        )

        let payload = try #require(MediaRemoteAdapterClient.decodeNowPlayingInfo(data))

        #expect(payload.title == "自动切换后的曲目")
        #expect(Data(base64Encoded: try #require(payload.artworkData)) == artwork)
    }

    @Test
    func mediaRemoteUsesAlbumAsPodcastAttributionWhenArtistIsMissing() throws {
        let dictionary: NSDictionary = [
            "kMRMediaRemoteNowPlayingInfoTitle": "本期节目",
            "kMRMediaRemoteNowPlayingInfoAlbum": "节目名称",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 1),
        ]

        let snapshot = try #require(NowPlayingService.parse(dictionary))

        #expect(snapshot.title == "本期节目")
        #expect(snapshot.artist == "节目名称")
    }

    @Test
    func sameTrackMetadataRefreshRetainsExistingArtwork() throws {
        let artwork = Data([0x01, 0x02, 0x03])
        let previous = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: "Album",
            artworkData: artwork,
            duration: 120,
            elapsedTime: 20,
            isPlaying: true
        )
        let refresh = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            duration: 120,
            elapsedTime: 21,
            isPlaying: true
        )

        let merged = NowPlayingService.mergingMetadata(refresh, previous: previous)

        #expect(merged.artworkData == artwork)
    }

    @Test
    func adapterVideoMediaTypeDecodesActorsFromArtist() throws {
        let data = try #require(
            """
            {
              "type": "data",
              "diff": false,
              "payload": {
                "title": "某部电影",
                "artist": "张三 / 李四",
                "album": "电影原声",
                "duration": 7200,
                "elapsedTime": 120,
                "playing": true,
                "processIdentifier": 4242,
                "bundleIdentifier": "com.apple.TV",
                "mediaType": "kMRMediaRemoteNowPlayingInfoTypeVideo"
              }
            }
            """.data(using: .utf8)
        )
        let event = try JSONDecoder().decode(MediaRemoteAdapterEvent.self, from: data)
        let snapshot = try #require(NowPlayingService.parseAdapter(event.payload))

        #expect(snapshot.isVideo)
        #expect(snapshot.title == "某部电影")
        #expect(snapshot.artist == "张三 / 李四")
        #expect(snapshot.sourceBundleIdentifier == "com.apple.TV")
    }

    @Test
    func videoAlbumIsNotUsedAsActorWhenArtistIsMissing() throws {
        let data = try #require(
            """
            {
              "type": "data",
              "diff": false,
              "payload": {
                "title": "某部电影",
                "album": "系列名称",
                "playing": true,
                "bundleIdentifier": "com.tencent.tenvideo",
                "mediaType": "kMRMediaRemoteNowPlayingInfoTypeVideo"
              }
            }
            """.data(using: .utf8)
        )
        let event = try JSONDecoder().decode(MediaRemoteAdapterEvent.self, from: data)
        let snapshot = try #require(NowPlayingService.parseAdapter(event.payload))

        #expect(snapshot.isVideo)
        #expect(snapshot.artist.isEmpty)
        #expect(snapshot.album == "系列名称")
    }

    @Test
    func appIdentityAloneIsNotTreatedAsVideo() throws {
        #expect(
            !NowPlayingService.isVideoMedia(
                mediaType: nil,
                isVideosApp: nil
            )
        )
        #expect(
            !NowPlayingService.isVideoMedia(
                mediaType: "",
                isVideosApp: false
            )
        )

        let data = try #require(
            """
            {
              "type": "data",
              "diff": false,
              "payload": {
                "title": "某剧集",
                "artist": "主演甲",
                "playing": true,
                "bundleIdentifier": "com.tencent.tenvideo"
              }
            }
            """.data(using: .utf8)
        )
        let event = try JSONDecoder().decode(MediaRemoteAdapterEvent.self, from: data)
        let snapshot = try #require(NowPlayingService.parseAdapter(event.payload))
        #expect(!snapshot.isVideo)
        #expect(snapshot.artist == "主演甲")
    }

    @Test
    func adapterIsVideosAppMarksVideoWithoutMediaType() throws {
        let data = try #require(
            """
            {
              "type": "data",
              "diff": false,
              "payload": {
                "title": "某剧集",
                "artist": "主演甲",
                "album": "节目名",
                "playing": true,
                "bundleIdentifier": "com.tencent.tenvideo",
                "isVideosApp": true
              }
            }
            """.data(using: .utf8)
        )
        let event = try JSONDecoder().decode(MediaRemoteAdapterEvent.self, from: data)
        let snapshot = try #require(NowPlayingService.parseAdapter(event.payload))
        #expect(snapshot.isVideo)
        #expect(snapshot.artist == "主演甲")
        #expect(snapshot.album == "节目名")
    }

    @Test
    func musicPayloadIsNotTreatedAsVideo() throws {
        #expect(
            !NowPlayingService.isVideoMedia(
                mediaType: "kMRMediaRemoteNowPlayingInfoTypeMusic",
                isVideosApp: nil
            )
        )
        #expect(
            !NowPlayingService.isVideoMedia(
                mediaType: nil,
                isVideosApp: false
            )
        )

        let data = try #require(
            """
            {
              "type": "data",
              "diff": false,
              "payload": {
                "title": "国际孤独等级",
                "artist": "Gareth.T",
                "playing": true,
                "bundleIdentifier": "com.tencent.QQMusicMac",
                "mediaType": "Music"
              }
            }
            """.data(using: .utf8)
        )
        let event = try JSONDecoder().decode(MediaRemoteAdapterEvent.self, from: data)
        let snapshot = try #require(NowPlayingService.parseAdapter(event.payload))
        #expect(!snapshot.isVideo)
        #expect(snapshot.artist == "Gareth.T")
        #expect(!snapshot.supportsPlaybackModeControl)
    }

    @Test
    func mediaRemoteDictionaryParsesVideoMediaTypeAndIsVideosApp() throws {
        let videoType: NSDictionary = [
            "kMRMediaRemoteNowPlayingInfoTitle": "剧集",
            "kMRMediaRemoteNowPlayingInfoArtist": "演员A",
            "kMRMediaRemoteNowPlayingInfoMediaType": "kMRMediaRemoteNowPlayingInfoTypeVideo",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 1),
        ]
        let typed = try #require(NowPlayingService.parse(videoType))
        #expect(typed.isVideo)
        #expect(typed.artist == "演员A")

        let videosApp: NSDictionary = [
            "kMRMediaRemoteNowPlayingInfoTitle": "剧集",
            "kMRMediaRemoteNowPlayingInfoArtist": "演员B",
            "kMRMediaRemoteNowPlayingInfoIsVideosApp": NSNumber(value: true),
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 1),
        ]
        let flagged = try #require(NowPlayingService.parse(videosApp))
        #expect(flagged.isVideo)
    }

    @Test
    func sameTrackMetadataRefreshRetainsSourceIconAndVideoFlag() {
        let icon = Data([0x0A, 0x0B])
        let previous = NowPlayingSnapshot(
            title: "剧集",
            artist: "演员",
            album: nil,
            artworkData: Data([0x01]),
            duration: 3600,
            elapsedTime: 10,
            isPlaying: true,
            isVideo: true,
            sourceIconData: icon
        )
        let refresh = NowPlayingSnapshot(
            title: "剧集",
            artist: "演员",
            album: nil,
            artworkData: nil,
            duration: 3600,
            elapsedTime: 12,
            isPlaying: false,
            isVideo: false,
            sourceIconData: nil
        )

        let merged = NowPlayingService.mergingMetadata(refresh, previous: previous)

        #expect(merged.sourceIconData == icon)
        #expect(merged.isVideo)
        #expect(merged.artworkData == Data([0x01]))
    }

    @Test
    func newTrackDoesNotReusePreviousArtwork() {
        let previous = NowPlayingSnapshot(
            title: "First",
            artist: "Artist",
            album: nil,
            artworkData: Data([0x01]),
            duration: 120,
            elapsedTime: 20,
            isPlaying: true
        )
        let refresh = NowPlayingSnapshot(
            title: "Second",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            duration: 180,
            elapsedTime: 0,
            isPlaying: true
        )

        let merged = NowPlayingService.mergingMetadata(refresh, previous: previous)

        #expect(merged.artworkData == nil)
    }

    @Test
    func sameTrackMetadataRefreshMergesLaterArtwork() {
        let artwork = Data([0x04, 0x05, 0x06])
        let previous = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            duration: 120,
            elapsedTime: 20,
            isPlaying: true
        )
        let refresh = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: "Album",
            artworkData: artwork,
            duration: 120,
            elapsedTime: 21,
            isPlaying: true
        )

        let merged = NowPlayingService.mergingMetadata(refresh, previous: previous)

        #expect(merged.artworkData == artwork)
    }

    @Test
    func playbackModesMapToVerifiedMediaRemoteValues() {
        #expect(NowPlayingPlaybackMode.sequential.mediaRemoteRepeatMode == 1)
        #expect(NowPlayingPlaybackMode.sequential.mediaRemoteShuffleMode == 1)
        #expect(NowPlayingPlaybackMode.repeatOne.mediaRemoteRepeatMode == 2)
        #expect(NowPlayingPlaybackMode.repeatOne.mediaRemoteShuffleMode == 1)
        #expect(NowPlayingPlaybackMode.random.mediaRemoteRepeatMode == 1)
        #expect(NowPlayingPlaybackMode.random.mediaRemoteShuffleMode == 3)
        #expect(NowPlayingService.playbackMode(repeatMode: 3, shuffleMode: 3) == .random)
    }

    @Test
    func cachedPlaybackModeDoesNotInventControlCapability() {
        var snapshot = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            duration: 120,
            elapsedTime: 30,
            isPlaying: true
        )

        snapshot.playbackMode = .random

        #expect(!snapshot.supportsPlaybackModeControl)
    }

    @Test
    func playbackModeAdapterCommandsMatchMediaRemoteModeValues() {
        #expect(
            NowPlayingService.playbackModeAdapterCommands(.sequential)
                == [["shuffle", "1"], ["repeat", "1"]]
        )
        #expect(
            NowPlayingService.playbackModeAdapterCommands(.repeatOne)
                == [["shuffle", "1"], ["repeat", "2"]]
        )
        #expect(
            NowPlayingService.playbackModeAdapterCommands(.random)
                == [["repeat", "1"], ["shuffle", "3"]]
        )

        for mode in NowPlayingPlaybackMode.allCases {
            let commands = NowPlayingService.playbackModeAdapterCommands(mode)
            #expect(commands.contains(where: { $0.first == "shuffle" }))
            #expect(commands.contains(where: { $0.first == "repeat" }))
            #expect(
                commands.contains {
                    $0 == ["shuffle", "\(mode.mediaRemoteShuffleMode)"]
                }
            )
            #expect(
                commands.contains {
                    $0 == ["repeat", "\(mode.mediaRemoteRepeatMode)"]
                }
            )
        }
    }

    @Test
    func mediaRemoteAdapterScriptRoutesShuffleAndRepeatThroughEnvEntryPoints() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = root.appendingPathComponent(
            "Resources/MediaRemoteAdapter/mediaremote-adapter.pl"
        )
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        for functionName in ["shuffle", "repeat"] {
            let pattern = #"(?s)elsif \(\$function_name eq "\#(functionName)"\).*?\}"#
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(script.startIndex..<script.endIndex, in: script)
            let match = try #require(regex.firstMatch(in: script, range: range))
            let block = try #require(Range(match.range, in: script).map { String(script[$0]) })
            #expect(block.contains("set_env_param($symbol_name, 0, \"mode\""))
            #expect(block.contains("$symbol_name = env_func($symbol_name)"))
        }
    }

    @Test
    func favoriteCommandsSupportAddingAndRemovingWishListItems() {
        #expect(
            NowPlayingService.favoriteCommand(isFavorite: false, control: .wishList)
                == .addTrackToWishList
        )
        #expect(
            NowPlayingService.favoriteCommand(isFavorite: true, control: .wishList)
                == .removeTrackFromWishList
        )
        #expect(
            NowPlayingService.favoriteCommand(isFavorite: true, control: .like) == .likeTrack
        )
    }

    @Test
    func advertisedFavoriteCapabilityIsAvailableBeforeItsStateArrives() throws {
        let data = try #require(
            """
            {
              "type": "data",
              "diff": false,
              "payload": {
                "title": "Track",
                "artist": "Artist",
                "playing": true,
                "supportsIsLiked": true
              }
            }
            """.data(using: .utf8)
        )
        let event = try JSONDecoder().decode(MediaRemoteAdapterEvent.self, from: data)
        let snapshot = try #require(NowPlayingService.parseAdapter(event.payload))

        #expect(snapshot.favoriteControl == .like)
        #expect(snapshot.isFavorite == nil)
    }

    @Test @MainActor
    func qqMusicAccessibilityLabelsExposeTheRealFavoriteState() {
        #expect(MediaAppSpecialist.favoriteState(for: ["从我喜欢删除"]) == true)
        #expect(MediaAppSpecialist.favoriteState(for: ["添加到我喜欢"]) == false)
        #expect(MediaAppSpecialist.favoriteState(for: ["取消收藏此歌曲"]) == true)
        #expect(MediaAppSpecialist.favoriteState(for: ["添加到收藏"]) == false)
        // QQ 音乐 11.7 菜单栏“播放控制”里的收藏菜单项实测文案。
        #expect(MediaAppSpecialist.favoriteState(for: ["取消喜欢"]) == true)
        #expect(MediaAppSpecialist.favoriteState(for: ["喜欢歌曲"]) == false)
        #expect(MediaAppSpecialist.favoriteState(for: ["播放", "下一首"]) == nil)
    }

    @Test @MainActor
    func qqMusicAccessibilityPermissionIsOnlyPromptedOncePerLaunch() {
        #expect(
            MediaAppSpecialist.shouldRequestAccessibilityPrompt(
                isTrusted: false,
                hasRequestedInCurrentLaunch: false
            )
        )
        #expect(
            !MediaAppSpecialist.shouldRequestAccessibilityPrompt(
                isTrusted: false,
                hasRequestedInCurrentLaunch: true
            )
        )
        #expect(
            !MediaAppSpecialist.shouldRequestAccessibilityPrompt(
                isTrusted: true,
                hasRequestedInCurrentLaunch: false
            )
        )
    }

    @Test @MainActor
    func qqMusicClickPointUsesFrameCenterAndRejectsInvalidSize() {
        let point = MediaAppSpecialist.clickPoint(
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 40, height: 20)
        )
        #expect(point == CGPoint(x: 120, y: 210))

        #expect(
            MediaAppSpecialist.clickPoint(
                position: CGPoint(x: 0, y: 0),
                size: CGSize(width: 0, height: 20)
            ) == nil
        )
        #expect(
            MediaAppSpecialist.clickPoint(
                position: CGPoint(x: 0, y: 0),
                size: CGSize(width: 20, height: -4)
            ) == nil
        )
        #expect(
            MediaAppSpecialist.clickPoint(
                position: CGPoint(x: CGFloat.nan, y: 0),
                size: CGSize(width: 10, height: 10)
            ) == nil
        )
    }

    @Test @MainActor
    func qqMusicPlayModeAndFavoriteLabelMatchingUsesAccessibilityCopy() {
        #expect(
            MediaAppSpecialist.matchesPlayModeLabels(["播放模式（顺序播放）"])
        )
        #expect(MediaAppSpecialist.matchesPlayModeLabels(["随机播放"]))
        #expect(MediaAppSpecialist.matchesPlayModeLabels(["列表循环"]))
        #expect(!MediaAppSpecialist.matchesPlayModeLabels(["播放", "下一首"]))
        #expect(!MediaAppSpecialist.matchesPlayModeLabels(["", "   "]))

        #expect(MediaAppSpecialist.matchesFavoriteLabels(["从我喜欢删除"]))
        #expect(MediaAppSpecialist.matchesFavoriteLabels(["添加到我喜欢"]))
        #expect(!MediaAppSpecialist.matchesFavoriteLabels(["播放模式（顺序播放）"]))
        #expect(!MediaAppSpecialist.matchesFavoriteLabels(["播放", "暂停"]))
    }

    @Test @MainActor
    func qqMusicMenuMappingsTargetPressableItems() {
        #expect(
            MediaAppSpecialist.qqMusicMenuLabels(for: .next)?.contains("下一首") == true
        )
        #expect(
            MediaAppSpecialist.qqMusicMenuLabels(for: .previous)?.contains("上一首") == true
        )
        #expect(
            MediaAppSpecialist.qqMusicFavoriteMenuLabels.contains("喜欢")
        )
        #expect(
            MediaAppSpecialist.qqMusicFavoriteMenuLabels.contains("取消喜欢")
        )
        #expect(
            MediaAppSpecialist.qqMusicFavoriteMenuLabels.contains("喜欢歌曲")
        )
        #expect(
            MediaAppSpecialist.qqMusicPlaybackModeMenuLabels(after: .sequential) == ["单曲循环"]
        )
        #expect(
            MediaAppSpecialist.qqMusicPlaybackModeMenuLabels(after: .repeatOne) == ["随机播放"]
        )
        #expect(
            MediaAppSpecialist.qqMusicPlaybackModeMenuLabels(after: .random) == ["顺序播放"]
        )
    }

    @Test
    func playbackCommandsProduceImmediateOptimisticState() {
        #expect(NowPlayingService.optimisticPlaybackValue(after: .play, current: false) == true)
        #expect(NowPlayingService.optimisticPlaybackValue(after: .pause, current: true) == false)
        #expect(
            NowPlayingService.optimisticPlaybackValue(after: .togglePlayPause, current: true)
                == false
        )
        #expect(NowPlayingService.optimisticPlaybackValue(after: .next, current: true) == nil)
    }

    @Test
    func favoriteStateMatchesTheSelectedRemoteControl() throws {
        let likedDictionary: NSDictionary = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Track",
            "kMRMediaRemoteNowPlayingInfoArtist": "Artist",
            "kMRMediaRemoteNowPlayingInfoIsLiked": NSNumber(value: true),
            "kMRMediaRemoteNowPlayingInfoSupportsWishlisting": NSNumber(value: true),
        ]
        let liked = try #require(NowPlayingService.parse(likedDictionary))
        #expect(liked.favoriteControl == .like)
        #expect(liked.isFavorite == true)

        let wishListDictionary: NSDictionary = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Track",
            "kMRMediaRemoteNowPlayingInfoArtist": "Artist",
            "kMRMediaRemoteNowPlayingInfoIsInWishList": NSNumber(value: false),
            "kMRMediaRemoteNowPlayingInfoIsLiked": NSNumber(value: true),
        ]
        let wishList = try #require(NowPlayingService.parse(wishListDictionary))
        #expect(wishList.favoriteControl == .wishList)
        #expect(wishList.isFavorite == false)
    }

    @Test
    func unknownFavoriteCapabilityDoesNotInventALikeControl() throws {
        let dictionary: NSDictionary = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Track",
            "kMRMediaRemoteNowPlayingInfoArtist": "Artist",
        ]

        let snapshot = try #require(NowPlayingService.parse(dictionary))

        #expect(snapshot.favoriteControl == nil)
        #expect(snapshot.isFavorite == nil)
    }

    @Test @MainActor
    func playerProfilesUseTheSupportedControlPathForEachApplication() throws {
        let specialist = MediaAppSpecialist.shared
        let appleMusic = try #require(specialist.profile(for: "com.apple.Music"))
        #expect(appleMusic.supportsFavorite)
        #expect(appleMusic.supportsFavoriteStateRead)
        #expect(appleMusic.supportsPlaybackControls)
        #expect(appleMusic.supportsPlaybackModeSet)
        #expect(!appleMusic.supportsPlaybackModeCycle)

        let spotify = try #require(specialist.profile(for: "com.spotify.client"))
        #expect(!spotify.supportsFavorite)
        #expect(spotify.supportsPlaybackControls)
        #expect(!spotify.supportsPlaybackModeSet)
        #expect(!spotify.supportsPlaybackModeCycle)

        let qqMusic = try #require(specialist.profile(for: "com.tencent.QQMusicMac"))
        #expect(qqMusic.supportsFavorite)
        #expect(qqMusic.supportsPlaybackModeCycle)
        #expect(!qqMusic.supportsPlaybackModeSet)
    }

    @Test @MainActor
    func appleMusicScriptsUseDocumentedFavoriteAndModeProperties() {
        let repeatOne = MediaAppSpecialist.appleMusicModeScript(for: .repeatOne)
        #expect(repeatOne.contains("shuffle enabled"))
        #expect(repeatOne.contains("song repeat"))
        #expect(repeatOne.contains("one"))
    }

    @Test
    func mediaSourcePreferenceFiltersOnlyTheSelectedPlayer() {
        #expect(NowPlayingService.matchesPreferredSource(nil, preference: .automatic))
        #expect(
            NowPlayingService.matchesPreferredSource(
                "com.apple.Music",
                preference: .appleMusic
            )
        )
        #expect(
            !NowPlayingService.matchesPreferredSource(
                "com.spotify.client",
                preference: .appleMusic
            )
        )
        #expect(
            NowPlayingService.matchesPreferredSource(
                "sh.cider.genten",
                preference: .cider
            )
        )
    }

    @Test
    func seekTimeIsClampedToTrackBounds() {
        #expect(NowPlayingService.clampedSeekTime(-4, duration: 180) == 0)
        #expect(NowPlayingService.clampedSeekTime(42, duration: 180) == 42)
        #expect(NowPlayingService.clampedSeekTime(240, duration: 180) == 180)
    }

    @Test
    func sourceApplicationSelectionPrefersPIDThenFallsBackToBundleIdentifier() {
        let candidates: [(pid: pid_t, bundleIdentifier: String?)] = [
            (pid: 77, bundleIdentifier: "com.example.music"),
            (pid: 1339, bundleIdentifier: "com.example.helper"),
        ]

        #expect(
            NowPlayingService.sourceApplicationIndex(
                sourcePID: 1339,
                sourceBundleIdentifier: "com.example.music",
                candidates: candidates
            ) == 1
        )
        #expect(
            NowPlayingService.sourceApplicationIndex(
                sourcePID: 404,
                sourceBundleIdentifier: "com.example.music",
                candidates: candidates
            ) == 0
        )
        #expect(
            NowPlayingService.sourceApplicationIndex(
                sourcePID: nil,
                sourceBundleIdentifier: nil,
                candidates: candidates
            ) == nil
        )
    }

    @Test
    func activeRemotePIDWinsOverFrontmostFallback() throws {
        let frontmost = source(id: "front", pid: 10, isFrontmost: true)
        let remote = source(id: "remote", pid: 20, isFrontmost: false)

        let selected = try #require(
            NowPlayingService.preferredSource(from: [frontmost, remote], remotePID: 20)
        )

        #expect(selected.id == "remote")
    }

    @Test
    func frontmostSourceWinsWhenMediaRemoteHasNoPID() throws {
        let background = source(id: "background", pid: 10, isFrontmost: false)
        let frontmost = source(id: "front", pid: 20, isFrontmost: true)

        let selected = try #require(
            NowPlayingService.preferredSource(from: [background, frontmost], remotePID: nil)
        )

        #expect(selected.id == "front")
    }

    @Test
    func soleCoreAudioSourceCorrectsConflictingMediaRemoteAttribution() throws {
        let bilibili = source(id: "bilibili", pid: 42, isFrontmost: true)

        let selected = try #require(
            NowPlayingService.audioSourceCorrectingRemoteAttribution(
                from: [bilibili],
                remotePID: 1339,
                remoteBundleIdentifier: "com.tencent.QQMusicMac"
            )
        )

        #expect(selected.id == "bilibili")
        #expect(
            NowPlayingService.audioSourceCorrectingRemoteAttribution(
                from: [bilibili],
                remotePID: 42,
                remoteBundleIdentifier: "test.bilibili"
            ) == nil
        )
    }

    @Test
    func multipleCoreAudioSourcesDoNotGuessRemoteAttribution() {
        let bilibili = source(id: "bilibili", pid: 42, isFrontmost: true)
        let qqMusic = source(id: "qqmusic", pid: 1339, isFrontmost: false)

        #expect(
            NowPlayingService.audioSourceCorrectingRemoteAttribution(
                from: [bilibili, qqMusic],
                remotePID: 1339,
                remoteBundleIdentifier: "com.tencent.QQMusicMac"
            ) == nil
        )
    }

    @Test
    func pausedRemoteSnapshotIsNotTreatedAsPlayingByAudioFallback() {
        let paused = NowPlayingSnapshot(
            title: "暂停的曲目",
            artist: "播放器",
            album: nil,
            artworkData: nil,
            duration: 120,
            elapsedTime: 30,
            isPlaying: false
        )

        #expect(
            !NowPlayingService.remotePlaybackIsActive(
                snapshot: paused,
                playbackState: .paused
            )
        )
    }

    @Test
    func metadataWithoutPlaybackQueryCanStillUsePlayingFlag() {
        let playing = NowPlayingSnapshot(
            title: "未接入控制的曲目",
            artist: "播放器",
            album: nil,
            artworkData: nil,
            duration: nil,
            elapsedTime: nil,
            isPlaying: true
        )

        #expect(
            NowPlayingService.remotePlaybackIsActive(
                snapshot: playing,
                playbackState: .unavailable
            )
        )
    }

    @Test
    func pendingRemoteQueryDoesNotFlashAudioFallback() {
        let source = source(id: "player", pid: 20, isFrontmost: true)

        #expect(
            !NowPlayingService.audioFallbackIsAllowed(
                source: source,
                remotePID: nil,
                playbackState: .pending,
                remotePIDPending: true
            )
        )
    }

    @Test
    func activeRemoteWithoutMetadataCanUseAudioFallback() {
        let source = source(id: "player", pid: 20, isFrontmost: true)

        #expect(
            NowPlayingService.audioFallbackIsAllowed(
                source: source,
                remotePID: 20,
                playbackState: .playing,
                remotePIDPending: false
            )
        )
    }

    @Test
    func pausedRemotePIDCannotReturnThroughAudioFallback() {
        let source = source(id: "player", pid: 20, isFrontmost: true)

        #expect(
            !NowPlayingService.audioFallbackIsAllowed(
                source: source,
                remotePID: 20,
                playbackState: .paused,
                remotePIDPending: false
            )
        )
    }

    @Test
    func pausedRemoteWithoutPIDCannotUseAmbiguousAudioFallback() {
        let source = source(id: "player", pid: 20, isFrontmost: true)

        #expect(
            !NowPlayingService.audioFallbackIsAllowed(
                source: source,
                remotePID: nil,
                playbackState: .paused,
                remotePIDPending: false
            )
        )
    }

    @Test
    func pausedPlayerRetainsMetadataWhenRemoteInfoBrieflyBecomesEmpty() {
        #expect(
            NowPlayingService.shouldRetainSnapshotAfterEmptyRemoteInfo(
                playbackState: .paused,
                previousPID: 20,
                currentPID: 20
            )
        )
        #expect(
            !NowPlayingService.shouldRetainSnapshotAfterEmptyRemoteInfo(
                playbackState: .playing,
                previousPID: 20,
                currentPID: 20
            )
        )
        #expect(
            !NowPlayingService.shouldRetainSnapshotAfterEmptyRemoteInfo(
                playbackState: .paused,
                previousPID: 20,
                currentPID: 30
            )
        )
        #expect(
            NowPlayingService.shouldRetainSnapshotAfterEmptyRemoteInfo(
                playbackState: .paused,
                previousPID: 20,
                currentPID: nil,
                activeProcessIdentifiers: [20]
            )
        )
        #expect(
            !NowPlayingService.shouldRetainSnapshotAfterEmptyRemoteInfo(
                playbackState: .paused,
                previousPID: nil,
                currentPID: nil
            )
        )
    }

    @Test
    func unrelatedAudioSourceCanFallbackWhenRemotePlayerIsPaused() {
        let source = source(id: "conference", pid: 30, isFrontmost: true)

        #expect(
            NowPlayingService.audioFallbackIsAllowed(
                source: source,
                remotePID: 20,
                playbackState: .paused,
                remotePIDPending: false
            )
        )
    }

    @Test
    func pausedRemoteWithStaleOutputsPrefersNewerFrontmostVideo() throws {
        // MediaRemote still points at paused QQ Music while Core Audio keeps both
        // output streams alive; sticky/frontmost may still mark the old player.
        let qqMusic = source(id: "qqmusic", pid: 1339, isFrontmost: true)
        let tencentVideo = source(id: "tencentvideo", pid: 1357, isFrontmost: false)

        let selected = try #require(
            NowPlayingService.preferredAudioFallbackSource(
                from: [qqMusic, tencentVideo],
                remotePID: 1339,
                playbackState: .paused,
                remotePIDPending: false
            )
        )

        #expect(selected.id == "tencentvideo")
        #expect(selected.processIdentifiers == [1357])
        #expect(
            !NowPlayingService.audioFallbackIsAllowed(
                source: qqMusic,
                remotePID: 1339,
                playbackState: .paused,
                remotePIDPending: false
            )
        )
    }

    @Test
    func pausedRemoteFallbackStillPrefersFrontmostAmongAllowedSources() throws {
        let background = source(id: "browser", pid: 40, isFrontmost: false)
        let frontmostVideo = source(id: "video", pid: 50, isFrontmost: true)

        let selected = try #require(
            NowPlayingService.preferredAudioFallbackSource(
                from: [background, frontmostVideo],
                remotePID: 1339,
                playbackState: .paused,
                remotePIDPending: false
            )
        )

        #expect(selected.id == "video")
    }

    @Test
    func repeatOnePlaybackClockWrapsAtTrackBoundary() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let snapshot = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            duration: 180,
            elapsedTime: 178,
            timestamp: timestamp,
            isPlaying: true,
            playbackMode: .repeatOne
        )

        #expect(snapshot.elapsedTime(at: timestamp.addingTimeInterval(2)) == 0)
        #expect(snapshot.elapsedTime(at: timestamp.addingTimeInterval(5)) == 3)
        #expect(snapshot.elapsedTime(at: timestamp.addingTimeInterval(185)) == 3)
    }

    @Test
    func sequentialPlaybackClockStillStopsAtTrackEnd() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let snapshot = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            duration: 180,
            elapsedTime: 178,
            timestamp: timestamp,
            isPlaying: true,
            playbackMode: .sequential
        )

        #expect(snapshot.elapsedTime(at: timestamp.addingTimeInterval(5)) == 180)
    }

    private func source(id: String, pid: pid_t, isFrontmost: Bool) -> AudioPlaybackSource {
        AudioPlaybackSource(
            id: id,
            processIdentifiers: [pid],
            bundleIdentifier: "test.\(id)",
            applicationName: id,
            iconData: nil,
            isFrontmost: isFrontmost
        )
    }
}
