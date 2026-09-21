import AppKit
import SwiftUI
import Testing

@testable import Zisla

struct ThinScrollChromeTests {
    @Test(arguments: [
        (false, NSScroller.Style.legacy), (true, .legacy),
        (false, .overlay), (true, .overlay),
    ], [NSAppearance.Name.aqua, .darkAqua]) @MainActor
    func thinKnobPaintsThreePointsAcrossAppearancesAndStyles(
        configuration: (horizontal: Bool, style: NSScroller.Style), appearanceName: NSAppearance.Name
    ) throws {
        let horizontal = configuration.horizontal
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
        scrollView.appearance = NSAppearance(named: appearanceName)
        scrollView.documentView = NSView(frame: NSRect(
            x: 0, y: 0, width: horizontal ? 800 : 140, height: horizontal ? 140 : 800
        ))
        scrollView.scrollerStyle = configuration.style
        scrollView.hasVerticalScroller = !horizontal
        scrollView.hasHorizontalScroller = horizontal
        ThinScrollChrome.apply(to: scrollView)
        scrollView.tile()

        let scroller = try #require(horizontal ? scrollView.horizontalScroller : scrollView.verticalScroller)
        scroller.doubleValue = 0.5
        let knob = scroller.rect(for: .knob)
        #expect(scroller.bounds.contains(knob), "The thin knob must remain inside the scroller's clipping bounds")
        if configuration.style == .legacy {
            // Overlay knobs do not accept hits while their native fade state is hidden.
            let hitPoint = scroller.convert(NSPoint(x: knob.midX, y: knob.midY), to: nil)
            #expect(scroller.testPart(hitPoint) == .knob)
        }
        #expect(scroller.rect(for: .noPart) == .zero)

        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(scroller.bounds.width),
            pixelsHigh: Int(scroller.bounds.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        scroller.bounds.fill(using: .copy)
        scroller.effectiveAppearance.performAsCurrentDrawingAppearance {
            scroller.drawKnob()
        }
        NSGraphicsContext.restoreGraphicsState()

        var visibleCrossAxisPixels = Set<Int>()
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let contrast = appearanceName == .darkAqua ? color.redComponent : 1 - color.redComponent
                if color.alphaComponent * contrast > 0.1 {
                    visibleCrossAxisPixels.insert(horizontal ? y : x)
                }
            }
        }
        #expect(visibleCrossAxisPixels.count == 3, "All three points of the knob must visibly contrast with the background")
    }

    @Test @MainActor
    func swiftUIOverflowingGridRendersAThreePointKnob() async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.close() }
        let host = NSHostingView(rootView:
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(0..<20) { _ in Color.gray.frame(height: 80) }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.visible)
            .thinScrollChrome(visibleWhenScrollable: true)
            .background(Color.black)
        )
        host.sizingOptions = []
        window.contentView = host

        var scrollView: NSScrollView?
        let deadline = Date().addingTimeInterval(1)
        repeat {
            host.layoutSubtreeIfNeeded()
            var pending = [host as NSView]
            while let view = pending.popLast() {
                if let scroll = view as? NSScrollView { scrollView = scroll }
                pending.append(contentsOf: view.subviews)
            }
            scrollView?.tile()
            if let scrollView {
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            if scrollView?.verticalScroller is ThinScroller { break }
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        } while Date() < deadline

        let scroller = try #require(scrollView?.verticalScroller as? ThinScroller)
        #expect(!scroller.isHidden)
        #expect(scroller.knobProportion > 0 && scroller.knobProportion < 1)
        #expect(scroller.bounds.contains(scroller.rect(for: .knob)))

        host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let track = scroller.convert(scroller.bounds, to: host)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        var visibleColumns = Set<Int>()
        for y in 0..<bitmap.pixelsHigh {
            for x in Int(track.minX * scale)..<Int(track.maxX * scale) {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.redComponent * color.alphaComponent > 0.1 { visibleColumns.insert(x) }
            }
        }
        #expect(visibleColumns.count == Int(3 * scale), "The hosted grid must render a visible 3pt knob, not just report an unhidden scroller")
        #expect(!window.isVisible)
    }

    @Test @MainActor
    func visibleWhenScrollableUsesVisibleLegacyThinScrollerForOverflowingContent() throws {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 200))
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = false

        ThinScrollChrome.apply(to: scrollView, visibleWhenScrollable: true)
        scrollView.tile()

        let scroller = try #require(scrollView.verticalScroller)
        #expect(scrollView.scrollerStyle == .legacy)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.hasVerticalScroller)
        #expect(scroller is ThinScroller)
        #expect(!scroller.isHidden)
        #expect(scroller.knobProportion < 1)
    }

    @Test @MainActor
    func visibleWhenScrollableHidesThinScrollerWhenContentFits() throws {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = false

        ThinScrollChrome.apply(to: scrollView, visibleWhenScrollable: true)
        scrollView.tile()

        let scroller = try #require(scrollView.verticalScroller)
        #expect(scrollView.scrollerStyle == .legacy)
        #expect(scrollView.autohidesScrollers)
        #expect(scroller is ThinScroller)
        #expect(scroller.isHidden)
    }
}
