import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct CollapsedProgressGlowTests {
    @Test
    func playbackProgressAdvancesFromElapsedTime() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let snapshot = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            duration: 200,
            elapsedTime: 40,
            timestamp: timestamp,
            isPlaying: true
        )

        #expect(CollapsedProgress.playbackFraction(for: snapshot, at: timestamp.addingTimeInterval(20)) == 0.3)
    }

    @Test
    func playbackProgressRejectsUnavailableOrInvalidDuration() {
        let base = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            duration: 0,
            elapsedTime: 20,
            isPlaying: true
        )

        #expect(CollapsedProgress.playbackFraction(for: base, at: .now) == nil)
        #expect(CollapsedProgress.playbackFraction(
            for: NowPlayingSnapshot(
                title: base.title,
                artist: base.artist,
                album: nil,
                artworkData: nil,
                duration: 100,
                elapsedTime: nil,
                isPlaying: true
            ),
            at: .now
        ) == nil)
        #expect(CollapsedProgress.playbackFraction(
            for: NowPlayingSnapshot(
                title: base.title,
                artist: base.artist,
                album: nil,
                artworkData: nil,
                duration: 100,
                elapsedTime: 20,
                isPlaying: false
            ),
            at: .now
        ) == nil)
    }

    @Test
    func playbackProgressClampsAtTrackEnd() {
        let snapshot = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            duration: 100,
            elapsedTime: 140,
            isPlaying: true
        )

        #expect(CollapsedProgress.playbackFraction(for: snapshot, at: .now) == 1)
    }

    @Test
    func dismissalProgressCountsDownAndClampsAtBounds() {
        let deadline = Date(timeIntervalSince1970: 1_010)

        #expect(CollapsedProgress.remainingFraction(
            until: deadline,
            totalDuration: 20,
            at: Date(timeIntervalSince1970: 1_000)
        ) == 0.5)
        #expect(CollapsedProgress.remainingFraction(until: deadline, totalDuration: 20, at: deadline) == 0)
        #expect(CollapsedProgress.remainingFraction(
            until: deadline,
            totalDuration: 20,
            at: Date(timeIntervalSince1970: 990)
        ) == 1)
        #expect(CollapsedProgress.remainingFraction(until: deadline, totalDuration: nil, at: .now) == nil)
    }

    @Test
    func progressSegmentsSkipThePhysicalNotchWithoutPausingAtTheCenter() {
        let halfway = CollapsedProgress.segmentWidths(
            progress: 0.5,
            totalWidth: 500,
            centerInset: 200
        )
        #expect(halfway.leading == 150)
        #expect(halfway.trailing == 0)
        #expect(halfway.side == 150)
        #expect(halfway.centerInset == 200)

        let pastCenter = CollapsedProgress.segmentWidths(
            progress: 0.75,
            totalWidth: 500,
            centerInset: 200
        )
        #expect(pastCenter.leading == 150)
        #expect(pastCenter.trailing == 75)

        let continuous = CollapsedProgress.segmentWidths(
            progress: 0.25,
            totalWidth: 500,
            centerInset: 0
        )
        #expect(continuous.leading == 125)
        #expect(continuous.trailing == 0)
        #expect(continuous.side == 500)

        let clamped = CollapsedProgress.segmentWidths(
            progress: 2,
            totalWidth: 100,
            centerInset: 200
        )
        #expect(clamped.leading == 0)
        #expect(clamped.trailing == 0)
        #expect(clamped.side == 0)
        #expect(clamped.centerInset == 100)

        let negative = CollapsedProgress.segmentWidths(
            progress: -1,
            totalWidth: 100,
            centerInset: -20
        )
        #expect(negative.leading == 0)
        #expect(negative.trailing == 0)
        #expect(negative.side == 100)
        #expect(negative.centerInset == 0)
    }

    @Test
    func progressGlowLocalizationKeysExistForEveryLanguage() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let localizationRoot = packageRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Localization", isDirectory: true)
        let keys = [
            "提示条进度光效",
            "在收起态提示条边沿显示播放、下载和自动关闭进度",
        ]

        for language in AppLanguage.allCases {
            let url = localizationRoot
                .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
                .appendingPathComponent("Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if language != .simplifiedChinese {
                    #expect(value != key, "\(language.rawValue) 未翻译「\(key)」")
                }
            }
        }
    }

    @Test
    func collapsedNoticeGlowUsesPlaybackDownloadAndDismissalProgressSources() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Zisla/SideNoticeView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("CollapsedProgress.playbackFraction"))
        #expect(source.contains("browserDownloadNotice?.progress"))
        #expect(source.contains("videoDownloadNotice?.progress"))
        #expect(source.contains("settingsStore.settings.collapsedProgressGlowEnabled"))
        #expect(source.contains("CollapsedProgressGlow("))
        #expect(source.contains("centerInset: displayState.compactBarCenterInset"))
        #expect(source.contains("MediaWaveformView.tintColor(for: artworkData)"))
        #expect(source.contains("compactStatusBackgroundFill"))
        #expect(source.contains("Color.clear\n                        .frame(width: centerInset)"))

        let waveformSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Zisla/MediaWaveformView.swift"),
            encoding: .utf8
        )
        #expect(waveformSource.contains("tint = Self.tintColor(for: artworkData)"))
        #expect(waveformSource.contains("ArtworkWaveformColor.color(from: artworkData)"))
    }
}
