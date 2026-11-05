import AppKit
import SwiftUI
import Testing
import WebKit
import XCTest

@testable import Zisla
@testable import ZislaKit
@testable import KeyboardKit

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
        ThinScrollChrome.apply(to: scrollView, visibleWhenScrollable: false)
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

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua], [LayoutDirection.leftToRight, .rightToLeft]) @MainActor
    func swiftUIOverflowingGridRendersAThreePointKnob(appearanceName: NSAppearance.Name, direction: LayoutDirection) async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearanceName)
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
            .thinScrollChrome()
            .background(appearanceName == .darkAqua ? Color.black : Color.white)
            .environment(\.colorScheme, appearanceName == .darkAqua ? .dark : .light)
            .environment(\.layoutDirection, direction)
        )
        host.sizingOptions = []
        window.contentView = host

        var scrollView: NSScrollView?
        // Parallel rendering must not consume a wall-clock deadline before layout can run.
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            var pending = [host as NSView]
            while let view = pending.popLast() {
                if let scroll = view as? NSScrollView { scrollView = scroll }
                pending.append(contentsOf: view.subviews)
            }
            scrollView?.tile()
            if let scrollView {
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            if let scroller = scrollView?.verticalScroller as? ThinScroller,
               scroller.knobProportion > 0, scroller.knobProportion < 1,
               scroller.bounds.contains(scroller.rect(for: .knob)) { break }
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }

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
                let contrast = appearanceName == .darkAqua ? color.redComponent : 1 - color.redComponent
                if contrast * color.alphaComponent > 0.1 { visibleColumns.insert(x) }
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

        ThinScrollChrome.apply(to: scrollView)
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

    @Test @MainActor
    func reappliesVisibleChromeAfterNativeScrollConfigurationChanges() throws {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 400))
        scrollView.documentView = document
        let host = ThinScrollChromeHost(visibleWhenScrollable: true)
        document.addSubview(host)
        host.applyIfNeeded()
        #expect(scrollView.verticalScroller is ThinScroller)

        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = false
        scrollView.hasVerticalScroller = false
        host.applyIfNeeded()
        scrollView.tile()

        #expect(scrollView.scrollerStyle == .legacy)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.hasVerticalScroller)
        #expect(scrollView.verticalScroller is ThinScroller)
        #expect(scrollView.documentView === document)
        #expect(document.frame.height == 400)
    }

    @Test @MainActor
    func nativeStyleChangesRestoreTheThinScrollbarWithoutAnotherLayout() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 400))
        scroll.documentView = document
        let host = ThinScrollChromeHost(visibleWhenScrollable: true)
        document.addSubview(host)
        host.applyIfNeeded()
        for _ in 0..<4 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        scroll.scrollerStyle = .overlay
        for _ in 0..<8 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            if scroll.scrollerStyle == .legacy { break }
        }
        #expect(scroll.scrollerStyle == .legacy)
        #expect(scroll.verticalScroller is ThinScroller)
        #expect(scroll.documentView === document)
    }

    @Test @MainActor
    func nestedChromeConfiguresItsLocalScrollViewWithoutChangingTheOuterScroller() throws {
        let outer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        outer.hasVerticalScroller = true
        outer.scrollerStyle = .overlay
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        outer.documentView = document
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 160))
        document.addSubview(wrapper)
        let inner = NSScrollView(frame: wrapper.bounds)
        inner.hasVerticalScroller = true
        inner.scrollerStyle = .overlay
        inner.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
        wrapper.addSubview(inner)
        let host = ThinScrollChromeHost(visibleWhenScrollable: true)
        wrapper.addSubview(host)
        let originalOuterScroller = try #require(outer.verticalScroller)

        host.applyIfNeeded()
        inner.tile()

        #expect(inner.verticalScroller is ThinScroller)
        #expect(inner.scrollerStyle == .legacy)
        #expect(outer.verticalScroller === originalOuterScroller)
        #expect(outer.scrollerStyle == .overlay)
    }

    @Test @MainActor
    func movingTheConfiguratorBetweenScrollViewsPreservesOffsetsAndReleasesItAfterDetaching() throws {
        let first = NSScrollView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
        let second = NSScrollView(frame: first.frame)
        for scroll in [first, second] {
            scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 400))
            scroll.contentView.scroll(to: CGPoint(x: 0, y: 120))
        }
        let firstDocument = try #require(first.documentView)
        let secondDocument = try #require(second.documentView)
        weak var releasedHost: ThinScrollChromeHost?
        try autoreleasepool {
            let host = ThinScrollChromeHost(visibleWhenScrollable: true)
            releasedHost = host
            firstDocument.addSubview(host)
            host.applyIfNeeded()
            let firstScroller = try #require(first.verticalScroller)
            let firstOffset = first.contentView.bounds.origin

            secondDocument.addSubview(host)
            let secondOffset = second.contentView.bounds.origin
            host.applyIfNeeded()
            #expect(second.verticalScroller is ThinScroller)
            #expect(first.verticalScroller === firstScroller)
            #expect(first.contentView.bounds.origin == firstOffset)
            #expect(second.contentView.bounds.origin == secondOffset)
            host.removeFromSuperview()
        }
        #expect(releasedHost == nil, "Deferred styling must not retain a detached page")
        #expect(first.documentView === firstDocument && second.documentView === secondDocument)
    }

    @Test(arguments: [false, true]) @MainActor
    func independentListOrTextEditorAndSummaryPanesKeepTheirOwnThinScrollbars(usesTextEditor: Bool) async throws {
        let text = (0..<80).map { "Fixture line \($0)" }.joined(separator: "\n")
        let host = NSHostingView(rootView: HStack {
            Group {
                if usesTextEditor {
                    TextEditor(text: .constant(text))
                        .thinScrollChrome()
                } else {
                    List(0..<80, id: \.self) { Text("Fixture row \($0)") }
                        .thinScrollChrome()
                }
            }
            ScrollView { Color.gray.frame(height: 800) }
                .thinScrollChrome()
        })
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 160),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        let scrolls = descendants(in: host).compactMap { $0 as? NSScrollView }
        #expect(scrolls.count == 2)
        for scroll in scrolls {
            let scroller = try #require(scroll.verticalScroller as? ThinScroller)
            #expect(scroll.scrollerStyle == .legacy)
            #expect(!scroller.isHidden)
            let document = try #require(scroll.documentView)
            scroll.contentView.scroll(to: CGPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            #expect(scroll.contentView.bounds.minY > 0)
        }
        if usesTextEditor {
            #expect(descendants(in: host).compactMap { $0 as? NSTextView }.first?.string == text)
        }
        #expect(!window.isVisible)
    }

    @Test(arguments: [false, true]) @MainActor
    func keyboardOverviewAndHeatmapUseThinScrollbars(heatmap: Bool) async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let snapshot = TypingStatsSnapshot(generatedAt: now, lastInputAt: nil,
            today: TypingDaySummary(dateKey: "2030-03-17", date: now, characterCount: 0, peakCPS: 0,
                activeMinuteBuckets: 0, activeSeconds: 0, topAppName: nil, lastUpdatedAt: nil),
            timelineRange: .oneHour, recentBuckets: [], apps: [], recentAppTimelines: [], history: [],
            todayKeyCounts: [:], allTimeKeyCounts: [:])
        let host = NSHostingView(rootView: Group {
            if heatmap {
                TypingStatsKeyboardView(snapshot: snapshot)
            } else {
                TypingStatsOverviewView(snapshot: snapshot, selectedRange: .oneHour, onSelectRange: { _ in })
            }
        })
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        var scrollView: NSScrollView?
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat {
            host.layoutSubtreeIfNeeded()
            scrollView = descendants(in: host).compactMap { $0 as? NSScrollView }.first
            if let scrollView {
                scrollView.tile()
                scrollView.reflectScrolledClipView(scrollView.contentView)
                if let scroller = scrollView.verticalScroller as? ThinScroller,
                   scrollView.scrollerStyle == .legacy,
                   scroller.knobProportion > 0, scroller.knobProportion < 1,
                   !scroller.isHidden { break }
            }
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        } while ContinuousClock.now < deadline
        let scroll = try #require(scrollView)
        let scroller = try #require(scroll.verticalScroller as? ThinScroller)
        #expect(scroll.scrollerStyle == .legacy)
        #expect(scroller.knobProportion > 0 && scroller.knobProportion < 1)
        #expect(!scroller.isHidden)
        #expect(!window.isVisible)
    }

    @Test(arguments: ["", "Short preview", String(repeating: "Preview paragraph\n\n", count: 80)], [false, true]) @MainActor
    func markdownPreviewScrollbarsStayThinForEmptyShortAndOverflowingDocuments(source: String, releaseNotes: Bool) async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        defer { webView.stopLoading() }
        let finished = XCTestExpectation(description: "The local Markdown preview finishes loading")
        let observation = webView.observe(\.isLoading, options: .new) { _, change in
            if change.newValue == false { finished.fulfill() }
        }
        defer { observation.invalidate() }
        let html = releaseNotes
            ? ReleaseNotesHTML.document(markdown: source, language: .english)
            : MarkdownHTMLRenderer.html(from: source)
        webView.loadHTMLString(html, baseURL: nil)
        try #require(await XCTWaiter.fulfillment(of: [finished], timeout: 10) == .completed)
        let width = try await webView.evaluateJavaScript("getComputedStyle(document.documentElement, '::-webkit-scrollbar').width")
        #expect(width as? String == "3px")
        _ = try await webView.evaluateJavaScript("window.scrollTo(0, 150)")
        #expect(try await webView.evaluateJavaScript("window.scrollY") as? Double == (source.count > 100 ? 150 : 0))
    }

    @MainActor
    private func descendants(in view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }
}
