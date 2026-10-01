import AppKit
import SwiftUI
import Testing
import ZislaKit

@testable import Zisla

@Suite(.serialized)
struct DetailedMediaBarLayoutTests {
    @Test @MainActor
    func waveformFollowsShortLyricsWhileTheRightEdgeStaysFixed() async throws {
        let frames = try await render(texts: ["歌词", "这是一句歌词", "歌词"])
        let short = frames[0]
        let longer = frames[1]
        #expect(try #require(short.waveform.first) > 300)
        #expect(try #require(longer.waveform.first) < #require(short.waveform.first) - 40)
        for frame in frames {
            let gap = try #require(frame.lyrics.first) - #require(frame.waveform.last)
            #expect((7...11).contains(gap), "The waveform must stay beside the lyric, not at the left of its spare space")
            #expect(try #require(frame.lyrics.last) >= 371)
            #expect(try #require(frame.lyrics.last) < 375)
        }
        #expect(frames[2] == short, "Changing lines must also move the waveform back")
    }

    @Test @MainActor
    func switchingBetweenShortAndOverflowingLinesRestoresTheGroupPosition() async throws {
        let frames = try await render(texts: ["歌词", "开始 ABCDEFGHIJKLMNOPQRSTUVWXYZ 结束", "歌词"])
        #expect(try #require(frames[0].waveform.first) > 300)
        #expect((172...174).contains(try #require(frames[1].waveform.first)))
        #expect(frames[2] == frames[0])
    }

    @Test @MainActor
    func longLyricsKeepTheOriginalBoundaryAndProgressScroll() async throws {
        let frames = try await render(
            texts: Array(repeating: "开始 ABCDEFGHIJKLMNOPQRSTUVWXYZ 结束", count: 3),
            elapsedTimes: [0, 5, 10]
        )
        for frame in frames {
            #expect(try (172...174).contains(#require(frame.waveform.first)))
            #expect(try #require(frame.waveform.last) < 195)
            #expect(try #require(frame.lyrics.first) >= 200)
            #expect(try #require(frame.lyrics.last) < 375)
        }
        #expect(frames[0].waveform == frames[1].waveform)
        #expect(frames[1].waveform == frames[2].waveform)
        #expect(frames[0].lyrics != frames[1].lyrics)
        #expect(frames[1].lyrics != frames[2].lyrics)
    }

    @Test @MainActor
    func physicalNotchKeepsTheWaveformAndLyricsAtTheirOriginalPositions() async throws {
        let frames = try await render(texts: ["歌词", "这是一句歌词"], centerInset: 80, width: 400)
        for frame in frames {
            #expect(try (247...249).contains(#require(frame.waveform.first)))
            #expect((275...278).contains(try #require(frame.lyrics.first)))
        }
        #expect(frames[0].waveform == frames[1].waveform)
    }

    @Test @MainActor
    func emptyLyricsLeaveTheWaveformAtTheRightWithoutPaintingText() async throws {
        let frame = try #require(await render(texts: [""]).first)
        #expect(frame.lyrics.isEmpty)
        let waveformStart = try #require(frame.waveform.first)
        #expect((347...349).contains(waveformStart))
        #expect(try #require(frame.waveform.last) < 375)
    }

    private struct Raster: Equatable {
        let waveform: [Int]
        let lyrics: [Int]
    }

    @MainActor
    private func render(
        texts: [String],
        elapsedTimes: [Double]? = nil,
        centerInset: CGFloat = 0,
        width: CGFloat = 380
    ) async throws -> [Raster] {
        _ = NSApplication.shared
        let artwork = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        artwork.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
        let artworkData = try #require(artwork.tiffRepresentation)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 30),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        func view(text: String, elapsedTime: Double) -> some View {
            DetailedMediaBar(
                item: NowPlayingSnapshot(
                    title: "", artist: "", album: nil, artworkData: artworkData,
                    duration: 10, elapsedTime: elapsedTime, isPlaying: false
                ),
                lyrics: SyncedLyrics(lines: [.init(time: 0, text: text)]),
                height: 30, centerInset: centerInset
            )
            .frame(width: width, height: 30)
            .background(Color.black)
            .environment(\.layoutDirection, .leftToRight)
        }

        let host = NSHostingView(rootView: view(text: "", elapsedTime: 0))
        host.sizingOptions = []
        window.contentView = host
        var frames: [Raster] = []
        for (index, text) in texts.enumerated() {
            host.rootView = view(text: text, elapsedTime: elapsedTimes?[index] ?? 0)
            // Allow the marquee width probes to settle while the test window stays hidden.
            for _ in 0..<20 {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / width
            var waveform = Set<Int>()
            var lyrics = Set<Int>()
            for x in Int(150 * scale)..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    let column = Int(CGFloat(x) / scale)
                    if color.redComponent > 0.4 && color.greenComponent < 0.3 {
                        waveform.insert(column)
                    } else if color.greenComponent > 0.4 {
                        lyrics.insert(column)
                    }
                }
            }
            frames.append(Raster(waveform: waveform.sorted(), lyrics: lyrics.sorted()))
        }
        #expect(!window.isVisible)
        return frames
    }
}
