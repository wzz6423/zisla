import AppKit
import Testing

@testable import Zisla

struct ThinScrollChromeTests {
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
        #expect(ThinScroller.scrollerWidth(for: .mini, scrollerStyle: .legacy) == ThinScrollChrome.width)
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
