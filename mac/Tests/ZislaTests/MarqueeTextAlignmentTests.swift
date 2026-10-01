import AppKit
import SwiftUI
import Testing

@testable import Zisla

@Suite(.serialized)
struct MarqueeTextAlignmentTests {
    @Test @MainActor
    func fittingLyricsAlignToTheRightWithoutMovingTheViewport() async throws {
        let leading = try await pixels(text: "歌词", alignment: .leading)
        let trailing = try await pixels(text: "歌词", alignment: .trailing)
        #expect(try #require(leading.columns.first) < 5)
        #expect(try #require(trailing.columns.last) >= 175)
        #expect(trailing.columns.count == leading.columns.count)
        #expect(try #require(trailing.columns.first) > 130)
    }

    @Test @MainActor
    func defaultAlignmentRemainsLeading() async throws {
        #expect(MarqueeText("歌词", font: .system(size: 14)).staticAlignment == .leading)
        let columns = try await pixels(text: "歌词").columns
        #expect(try #require(columns.first) < 5)
        #expect(try #require(columns.last) < 50)
    }

    @Test(arguments: [0.0, 0.5, 1.0]) @MainActor
    func overflowingLyricsKeepTheSameLeftwardScrollViewport(progress: Double) async throws {
        let text = "开始 ABCDEFGHIJKLMNOPQRSTUVWXYZ 结束"
        let leading = try await pixels(text: text, alignment: .leading, progress: progress)
        let trailing = try await pixels(text: text, alignment: .trailing, progress: progress)
        #expect(!leading.columns.isEmpty)
        #expect(trailing == leading)
    }

    @Test @MainActor
    func subpointOverflowKeepsTheStaticLeadingBoundary() async throws {
        let text = "开始 ABCDEFGHIJKLMNOPQRSTUVWXYZ 结束"
        let probe = NSHostingView(rootView: Text(text).font(.system(size: 14)).fixedSize())
        let width = probe.fittingSize.width - 1
        let leading = try await pixels(text: text, alignment: .leading, width: width)
        let trailing = try await pixels(text: text, alignment: .trailing, width: width)
        #expect(!leading.columns.isEmpty)
        #expect(trailing == leading)
    }

    @Test @MainActor
    func emptyLyricsDrawNothing() async throws {
        #expect(try await pixels(text: "", alignment: .trailing).columns.isEmpty)
    }

    @Test
    func onlyTheUnnotchedDetailBarOptsIntoRightAlignment() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/SideNoticeView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.components(separatedBy: "staticAlignment:").count == 2)
        #expect(source.contains("staticAlignment: centerInset > 0 ? .leading : .trailing"))
    }

    private struct Raster: Equatable {
        let columns: [Int]
        let intensities: [UInt8]
    }

    @MainActor
    private func pixels(
        text: String,
        alignment: Alignment? = nil,
        progress: Double? = nil,
        width: CGFloat = 180
    ) async throws -> Raster {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 30),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let marquee = MarqueeText(
            text, font: .system(size: 14), textColor: .white,
            pointsPerSecond: 0, repeats: false, scrollProgress: progress,
            clipsOverflowWhenStatic: true, staticAlignment: alignment ?? .leading
        )
        let host = NSHostingView(rootView: marquee
            .frame(width: width, height: 30)
            .background(Color.black)
            .environment(\.layoutDirection, .leftToRight))
        host.sizingOptions = []
        window.contentView = host
        // Flush the width probes and their SwiftUI state updates without showing a window.
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = Double(bitmap.pixelsWide) / width
        var columns = Set<Int>()
        var intensities: [UInt8] = []
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                intensities.append(UInt8((color.redComponent * color.alphaComponent * 255).rounded()))
                if color.redComponent * color.alphaComponent > 0.2 {
                    columns.insert(Int(Double(x) / scale))
                }
            }
        }
        #expect(!window.isVisible)
        return Raster(columns: columns.sorted(), intensities: intensities)
    }
}
