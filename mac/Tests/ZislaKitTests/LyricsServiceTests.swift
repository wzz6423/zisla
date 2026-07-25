import Foundation
import Testing

@testable import ZislaKit

struct LyricsServiceTests {
    @Test
    func lrcParserBuildsTimelineAndSwitchesCurrentLine() throws {
        let lyrics = try #require(SyncedLyrics.parse(
            """
            [ar:Artist]
            [00:01.50]第一句
            [00:03.250][00:05.25]重复句
            [01:02]最后一句
            """
        ))

        #expect(lyrics.lines.count == 4)
        #expect(lyrics.currentLine(at: 1.49) == nil)
        #expect(lyrics.currentLine(at: 1.5) == "第一句")
        #expect(lyrics.currentLine(at: 4) == "重复句")
        #expect(lyrics.currentLine(at: 62) == "最后一句")
    }

    @Test
    func lrclibSelectionRequiresNormalizedExactMetadata() throws {
        let data = Data(
            """
            [
              {
                "trackName": "Song Name",
                "artistName": "The Artist",
                "duration": 180.4,
                "syncedLyrics": "[00:01.00]正确歌词"
              },
              {
                "trackName": "Song Name (Live)",
                "artistName": "The Artist",
                "duration": 180.2,
                "syncedLyrics": "[00:01.00]错误版本"
              }
            ]
            """.utf8
        )

        let selected = try LyricsService.selectLyrics(
            from: data,
            title: " song-name ",
            artist: "THE ARTIST",
            duration: 181
        )
        let lyrics = try #require(selected)

        #expect(lyrics.currentLine(at: 2) == "正确歌词")
    }

    @Test
    func lrclibSelectionRejectsDurationMismatch() throws {
        let data = Data(
            """
            [
              {
                "trackName": "Song",
                "artistName": "Artist",
                "duration": 240,
                "syncedLyrics": "[00:01.00]其他版本"
              }
            ]
            """.utf8
        )

        let lyrics = try LyricsService.selectLyrics(
            from: data,
            title: "Song",
            artist: "Artist",
            duration: 180
        )

        #expect(lyrics == nil)
    }

    @Test
    func lrclibMultiArtistMatchReturnsFullArtistName() throws {
        // MediaRemote 只返回首位歌手 "Gareth.T"，
        // LRCLIB 返回完整歌手 "Gareth.T, Tray"。
        let data = Data(
            """
            [
              {
                "trackName": "合作曲目",
                "artistName": "Gareth.T, Tray",
                "duration": 200,
                "syncedLyrics": "[00:01.00]合唱歌词"
              }
            ]
            """.utf8
        )

        let result = try LyricsService.selectLyricsTrack(
            from: data,
            title: "合作曲目",
            artist: "Gareth.T",
            duration: 200
        )
        let lyrics = try #require(result.lyrics)

        #expect(lyrics.currentLine(at: 2) == "合唱歌词")
        #expect(result.artistName == "Gareth.T, Tray")
    }

    @Test
    func artistMatchesHandlesMultiArtistSeparators() {
        #expect(LyricsService.artistMatches("A, B", query: LyricsService.normalized("A")))
        #expect(LyricsService.artistMatches("A & B", query: LyricsService.normalized("B")))
        #expect(LyricsService.artistMatches("A/B", query: LyricsService.normalized("A")))
        #expect(!LyricsService.artistMatches("A", query: LyricsService.normalized("B")))
    }

    @Test
    func mediaRemoteEmbeddedLyricsAreParsedBeforeFallback() throws {
        let dictionary: NSDictionary = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Track",
            "kMRMediaRemoteNowPlayingInfoArtist": "Artist",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 1),
            "kMRMediaRemoteNowPlayingInfoLyrics": "[00:02.00]内嵌歌词",
        ]

        let snapshot = try #require(NowPlayingService.parse(dictionary))

        #expect(snapshot.lyrics?.currentLine(at: 3) == "内嵌歌词")
    }

    @Test
    func netEaseFallbackSelectsExactChineseTrackAndParsesSyncedLyrics() throws {
        let searchData = Data(
            """
            {
              "result": {
                "songs": [
                  {
                    "id": 2026303431,
                    "name": "国际孤独等级",
                    "duration": 193747,
                    "artists": [{"name": "Gareth.T"}]
                  },
                  {
                    "id": 2601894020,
                    "name": "国际孤独等级 (翻唱版)",
                    "duration": 193746,
                    "artists": [{"name": "音乐休憩站"}]
                  }
                ]
              }
            }
            """.utf8
        )
        let lyricData = Data(
            """
            {
              "code": 200,
              "lrc": {
                "lyric": "[00:00.05]不怕寂寞\\n[00:02.80]沉迷手机就过\\n[00:07.06]喜欢孤独"
              }
            }
            """.utf8
        )

        let selectedSongID = try LyricsService.selectNetEaseSongID(
            from: searchData,
            title: "国际孤独等级",
            artist: "Gareth.T",
            duration: 193
        )
        let parsedLyrics = try LyricsService.parseNetEaseLyrics(from: lyricData)
        let songID = try #require(selectedSongID)
        let lyrics = try #require(parsedLyrics)

        #expect(songID == 2026303431)
        #expect(lyrics.currentLine(at: 3) == "沉迷手机就过")
    }
}
