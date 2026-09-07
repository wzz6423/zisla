import AppKit
import Testing

@testable import Zisla
@testable import ZislaKit

struct NowPlayingHeaderTests {
    @Test
    func backgroundSoundSnapshotDisplaysSourceAndLocalizedSoundName() {
        let snapshot = MediaTextFormatting.backgroundSoundSnapshot(for: .rain)

        #expect(snapshot.isPlaying)
        #expect(!snapshot.supportsControls)
        #expect(MediaTextFormatting.titleArtistText(snapshot) == "背景音 · 雨声")
    }

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

@MainActor
struct MediaArtworkImageCacheTests {
    @Test
    func albumArtworkHasPriorityOverSourceIcon() throws {
        let artwork = try #require(makePNG(pixelSize: 32, color: .systemBlue))
        let sourceIcon = try #require(makePNG(pixelSize: 64, color: .systemRed))

        let image = try #require(
            MediaArtworkImageCache.image(from: artwork, fallback: sourceIcon)
        )

        #expect(image.size == NSSize(width: 32, height: 32))
    }

    @Test
    func sourceIconReplacesMissingOrInvalidArtwork() throws {
        let sourceIcon = try #require(makePNG(pixelSize: 64, color: .systemRed))
        let invalidArtworkData = Data([0x00])

        let missingArtwork = MediaArtworkImageCache.image(from: nil, fallback: sourceIcon)
        let invalidArtworkImage = MediaArtworkImageCache.image(
            from: invalidArtworkData,
            fallback: sourceIcon
        )

        #expect(missingArtwork?.size == NSSize(width: 64, height: 64))
        #expect(invalidArtworkImage?.size == NSSize(width: 64, height: 64))
        #expect(
            MediaArtworkImageCache.displayData(from: invalidArtworkData, fallback: sourceIcon)
                == sourceIcon
        )
    }

    @Test
    func missingArtworkAndSourceIconKeepThePlaceholderPath() {
        #expect(MediaArtworkImageCache.image(from: nil, fallback: nil) == nil)
    }

    private func makePNG(pixelSize: Int, color: NSColor) -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        bitmap.size = NSSize(width: pixelSize, height: pixelSize)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        color.setFill()
        NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()
        context.flushGraphics()
        return bitmap.representation(using: .png, properties: [:])
    }
}
