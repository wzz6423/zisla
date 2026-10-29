import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

struct MediaArtworkGlowTests {
    @Test
    func strongerSpectrumMakesTheGlowBrighterAndWider() {
        let quiet = state(levels: [0.1, 0.2, 0.1])
        let loud = state(levels: [0.7, 0.9, 0.8])

        #expect(quiet.energy > 0)
        #expect(loud.energy > quiet.energy)
        #expect(loud.opacity > quiet.opacity)
        #expect(loud.spread > quiet.spread)
        #expect(loud.animates)
    }

    @Test
    func silenceAndInaudiblePlaybackHaveTheSameStaticAccent() {
        let empty = state(levels: [])
        let silent = state(levels: [0, 0, 0])
        let inaudible = state(levels: [1, 1, 1], isAudible: false)

        #expect(empty.energy == 0)
        #expect(silent.energy == 0)
        #expect(inaudible.energy == 0)
        #expect(empty.opacity == silent.opacity)
        #expect(silent.opacity == inaudible.opacity)
        #expect(!empty.animates && !silent.animates && !inaudible.animates)
    }

    @Test
    func invalidBandsAreSilentAndOutOfRangeBandsAreClamped() {
        let invalid = state(levels: [.nan, .infinity, -.infinity, -4])
        let mixed = state(levels: [.nan, .infinity, -.infinity, -4, 2])
        let saturated = state(levels: [2, Float.greatestFiniteMagnitude])

        #expect(invalid.energy == 0)
        #expect(!invalid.animates)
        #expect(abs(mixed.energy - sqrt(1.0 / 5)) < 0.000_001)
        #expect(mixed.opacity.isFinite && mixed.spread.isFinite)
        #expect(saturated.energy == 1)
    }

    @Test
    func pausingStopsObservationAndRemovesAudioDrivenMotion() {
        let paused = state(levels: [1, 1, 1], isActive: false)

        #expect(!paused.observesSpectrum)
        #expect(!paused.animates)
        #expect(paused.energy == 0)
        #expect(paused.opacity > 0)
    }

    @Test
    func hiddenArtworkHasNoGlowOrSpectrumObservation() {
        let hidden = state(levels: [1, 1, 1], isVisible: false)

        #expect(!hidden.observesSpectrum)
        #expect(!hidden.animates)
        #expect(hidden.energy == 0)
        #expect(hidden.opacity == 0)
    }

    @Test
    func reducedMotionFreezesTheGlowForEverySpectrum() {
        let quiet = state(levels: [0.1], reduceMotion: true)
        let loud = state(levels: [1], reduceMotion: true)

        #expect(!loud.observesSpectrum)
        #expect(!loud.animates)
        #expect(loud.energy == 0)
        #expect(quiet == loud)
    }

    @Test
    func reducedTransparencyUsesAnOpaqueStaticAccent() {
        let reduced = state(levels: [1, 1, 1], reduceTransparency: true)

        #expect(reduced.usesSolidColor)
        #expect(!reduced.observesSpectrum)
        #expect(!reduced.animates)
        #expect(reduced.energy == 0)
        #expect(reduced.opacity == 1)
    }

    @Test @MainActor
    func renderedGlowIsConcentratedBelowTheArtworkAndRespondsToEnergy() throws {
        let quiet = try renderedField(state(levels: [0.1]))
        let loud = try renderedField(state(levels: [0.9]))
        let quietPixels = try redPixels(quiet)
        let loudPixels = try redPixels(loud)
        let midpoint = loudPixels.count / 2

        #expect(loudPixels.reduce(0, +) > quietPixels.reduce(0, +) * 1.2)
        #expect(loudPixels.suffix(from: midpoint).reduce(0, +) > loudPixels.prefix(midpoint).reduce(0, +) * 2)
        #expect(loudPixels.filter { $0 > 0.025 }.count > quietPixels.filter { $0 > 0.025 }.count)
    }

    @Test @MainActor
    func softGlowSpillsBelowTheArtworkWithoutAHardEdge() throws {
        let bitmap = try renderedField(state(levels: [0.9]))
        let pixels = try redPixels(bitmap)
        let artworkBottom = 18 + 54
        let below = pixels.dropFirst(artworkBottom * bitmap.pixelsWide)

        #expect(below.filter { $0 > 0.05 }.count > 1_000,
                "The glowing field must remain visible below the artwork, rather than being hidden behind it")
        for y in 0..<bitmap.pixelsHigh {
            for x in 1..<bitmap.pixelsWide {
                let current = pixels[y * bitmap.pixelsWide + x]
                let previous = pixels[y * bitmap.pixelsWide + x - 1]
                #expect(abs(current - previous) < 0.08,
                        "The glow must blend into its backdrop without a hard ellipse edge")
            }
        }
    }

    @Test @MainActor
    func reducedTransparencyRendersOnlyASmallOpaqueAccentBelowTheArtwork() throws {
        let bitmap = try renderedField(state(levels: [1], reduceTransparency: true))
        let pixels = try redPixels(bitmap)
        let lit = pixels.indices.filter { pixels[$0] > 0.1 }

        #expect(!lit.isEmpty)
        #expect(lit.count <= 108, "Reduced transparency must draw the narrow accent instead of a blurred field")
        #expect(lit.allSatisfy { $0 / bitmap.pixelsWide >= 18 + 54 },
                "The opaque accent must be under the cover art")
        #expect(lit.allSatisfy { pixels[$0] > 0.98 },
                "The accent must retain opaque contrast under reduced transparency")
        let columns = Set(lit.map { $0 % bitmap.pixelsWide })
        #expect(columns.count <= 36,
                "The opaque accent must remain narrower than the cover art")
    }

    @Test @MainActor
    func pausedArtworkKeepsAVisibleStaticAccent() throws {
        let bitmap = try renderedField(state(levels: [1], isActive: false))
        let pixels = try redPixels(bitmap)

        #expect(pixels.dropFirst((18 + 54) * bitmap.pixelsWide).contains { $0 > 0.025 },
                "Pausing must freeze the glow rather than removing its static accent")
    }

    @Test(arguments: MediaVisualizationStyle.allCases)
    @MainActor
    func compactArtworkKeepsItsSquareFrameWithoutReservedMediaSpace(style: MediaVisualizationStyle) throws {
        let artwork = try solidArtwork(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1))
        let view = CompactMediaArtwork(
            artworkData: artwork, size: 24, visualizationStyle: style, isActive: false
        )
        let renderer = ImageRenderer(content: view.background(.black))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))

        #expect(bitmap.pixelsWide == 24 && bitmap.pixelsHigh == 24,
                "Compact artwork must not reserve a second wing or a camera gap")
        let center = try #require(bitmap.colorAt(x: 12, y: 12)?.usingColorSpace(.deviceRGB))
        #expect(center.blueComponent > center.redComponent)
    }

    @Test @MainActor
    func compactArtworkUsesTheAlbumBeforeTheSourceIconAndRecoversFromInvalidArt() throws {
        let artwork = try solidArtwork(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1))
        let sourceIcon = try solidArtwork(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
        func pixel(_ data: Data?) throws -> NSColor {
            let renderer = ImageRenderer(content: CompactMediaArtwork(
                artworkData: data, sourceIconData: sourceIcon, size: 24,
                visualizationStyle: .waveform, isActive: false
            ).background(.black))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            return try #require(bitmap.colorAt(x: 12, y: 12)?.usingColorSpace(.deviceRGB))
        }

        let album = try pixel(artwork)
        #expect(album.blueComponent > album.redComponent)
        for missing in [Optional<Data>.none, Data([0])] {
            let restored = try pixel(missing)
            #expect(restored.redComponent > restored.blueComponent)
        }
    }

    @Test @MainActor
    func compactArtworkShowsAnIconWhenImagesAreMissing() throws {
        let bitmap = try rendered(CompactMediaArtwork(
            artworkData: nil, symbol: "music.note", size: 24,
            visualizationStyle: .waveform, isActive: false
        ))

        #expect(try redPixels(bitmap).contains { $0 > 0.1 },
                "A missing image must still render the source symbol")
    }

    @Test @MainActor
    func compactGlowAddsOnlyTheBottomAccentAndDisappearsWhenHidden() throws {
        let artwork = try solidArtwork(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
        func pixels(_ style: MediaVisualizationStyle, visible: Bool = true) throws -> [Double] {
            try redPixels(rendered(CompactMediaArtwork(
                artworkData: artwork, size: 24, visualizationStyle: style,
                isActive: false, isVisible: visible
            )))
        }
        let waveform = try pixels(.waveform)
        let glow = try pixels(.glow)
        let hiddenGlow = try pixels(.glow, visible: false)
        let bottom = (18 + 24) * 60

        #expect(glow.suffix(from: bottom).reduce(0, +) > waveform.suffix(from: bottom).reduce(0, +),
                "Glow mode must display its accent immediately under the compact cover")
        #expect(hiddenGlow == waveform, "Hiding the glow must not create a second empty media area")
    }

    @Test @MainActor
    func reducedMotionFieldMatchesPausedArtworkWithoutOpeningAudioCapture() throws {
        let paused = MediaArtworkGlow(artworkData: nil, width: 54, height: 54, isActive: false)
        let reduced = MediaArtworkGlowField(
            tint: MediaWaveformView.tintColor(for: nil, sampleBottomEdge: true),
            width: 54,
            height: 54,
            state: state(levels: [1], reduceMotion: true)
        )

        #expect(try redPixels(rendered(paused)) == redPixels(rendered(reduced)))
    }

    @Test @MainActor
    func hiddenComponentDoesNotRenderAnAccent() throws {
        let view = MediaArtworkGlow(
            artworkData: nil, width: 54, height: 54, isActive: true, isVisible: false
        )

        #expect(try redPixels(rendered(view)).allSatisfy { $0 == 0 })
    }

    @Test @MainActor
    func bottomEdgeColorAndWaveformColorUseSeparateCaches() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 20,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        let blue = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        for y in 0..<20 {
            for x in 0..<20 {
                bitmap.setColor(y < 15 ? red : blue, atX: x, y: y)
            }
        }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let waveform = MediaWaveformView.tintColor(for: data)
        let bottom = MediaWaveformView.tintColor(for: data, sampleBottomEdge: true)
        let waveformColor = try #require(NSColor(waveform).usingColorSpace(.deviceRGB))
        let bottomColor = try #require(NSColor(bottom).usingColorSpace(.deviceRGB))

        #expect(waveformColor.redComponent > waveformColor.blueComponent)
        #expect(bottomColor.blueComponent > bottomColor.redComponent)
        #expect(MediaWaveformView.tintColor(for: Data(data)) == waveform)
        #expect(MediaWaveformView.tintColor(for: Data(data), sampleBottomEdge: true) == bottom)
        #expect(MediaArtworkImageCache.image(from: data) === MediaArtworkImageCache.image(from: Data(data)))
    }

    @Test @MainActor
    func missingAndInvalidArtworkKeepTheExistingFallbackColor() {
        let fallback = MediaWaveformView.tintColor(for: nil)

        #expect(MediaWaveformView.tintColor(for: nil, sampleBottomEdge: true) == fallback)
        #expect(MediaWaveformView.tintColor(for: Data([0]), sampleBottomEdge: true) == fallback)
        #expect(MediaWaveformView.tintColor(for: Data([0])) == fallback)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZISLA_RUN_RESOURCE_TESTS"] == "1"))
    @MainActor
    func repeatedArtworkColorQueriesStayWithinTheInteractiveBudget() throws {
        let side = 768
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        _ = MediaWaveformView.tintColor(for: data, sampleBottomEdge: true)
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<1_000 {
            _ = MediaWaveformView.tintColor(for: data, sampleBottomEdge: true)
        }
        let duration = ProcessInfo.processInfo.systemUptime - start

        #expect(duration < 0.2,
                "A thousand repeated artwork queries must fit in 200 ms; measured \(duration) seconds")
    }

    private func state(
        levels: [Float], isActive: Bool = true, isVisible: Bool = true,
        isAudible: Bool = true, reduceMotion: Bool = false, reduceTransparency: Bool = false
    ) -> MediaArtworkGlowState {
        MediaArtworkGlowState(
            levels: levels, isActive: isActive, isVisible: isVisible, isAudible: isAudible,
            reduceMotion: reduceMotion, reduceTransparency: reduceTransparency
        )
    }

    @MainActor
    private func renderedField(_ state: MediaArtworkGlowState) throws -> NSBitmapImageRep {
        try rendered(MediaArtworkGlowField(tint: .red, width: 54, height: 54, state: state))
    }

    @MainActor
    private func rendered(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.padding(18).background(.black))
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    private func redPixels(_ bitmap: NSBitmapImageRep) throws -> [Double] {
        try (0..<bitmap.pixelsHigh).flatMap { y in
            try (0..<bitmap.pixelsWide).map { x in
                Double(try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)).redComponent)
            }
        }
    }

    @MainActor
    private func solidArtwork(_ color: NSColor) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        for y in 0..<24 {
            for x in 0..<24 {
                bitmap.setColor(color, atX: x, y: y)
            }
        }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
