import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct ToolboxTimerLayoutTests {
    @Test(arguments: [0, 1, 2, 4])
    func timerCountKeepsTheOriginalLeftWidthAndRightActionsPosition(additionalTimers: Int) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for _ in 0..<additionalTimers { fixture.service.addCountdown() }
        let host = fixture.host(HStack(alignment: .top, spacing: 10) {
            ToolboxTimerPanel(service: fixture.service)
                .frame(height: 136)
            Text("Tools")
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("toolbox.layout.right")
        }, size: CGSize(width: 776, height: 136))
        await fixture.layout()
        let scroll = try #require(Self.scrollView(in: host))
        let right = try #require(Self.element("toolbox.layout.right", in: host) as? any NSAccessibilityElementProtocol)
        let window = try #require(fixture.window)
        #expect(abs(scroll.frame.width - 236) < 0.5)
        #expect(abs(right.accessibilityFrame().minX - window.frame.minX - 246) < 0.5,
                "Adding countdowns must not move the right toolbox actions")
        #expect(scroll.frame.height == 136)
        let document = try #require(scroll.documentView)
        if additionalTimers > 1 {
            #expect(document.frame.height > scroll.contentView.bounds.height)
        } else {
            #expect(abs(document.frame.height - 136) < 0.5,
                    "One or two timers must fill the left panel without an empty lower region")
        }
    }

    @Test(arguments: [2, 4])
    func unmatchedLastCardFillsItsRowAndStartsWithAPlayIcon(additionalTimers: Int) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for _ in 0..<additionalTimers { fixture.service.addCountdown() }
        let id = try #require(fixture.service.countdowns.last?.id)
        let host = fixture.host(ToolboxTimerPanel(service: fixture.service), size: CGSize(width: 236, height: 136))
        await fixture.layout()
        let scroll = try #require(Self.scrollView(in: host))
        let document = try #require(scroll.documentView)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: document.frame.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        await fixture.layout()
        let card = try #require(Self.element("toolbox.timer.\(id)", in: host) as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let window = try #require(fixture.window).frame
        #expect(abs(card.width - scroll.contentView.bounds.width) < 0.5,
                "The unmatched timer must span the entire final row")
        #expect(abs(card.minX - window.minX) < 0.5)
        let button = try #require(Self.element("toolbox.toggleTimer.\(id)", in: host))
        let frame = try #require(button as? any NSAccessibilityElementProtocol).accessibilityFrame()
        #expect(abs(frame.width - 24) < 0.5 && abs(frame.height - 24) < 0.5,
                "Idle timers must use the same compact icon button as paused and running timers")
        _ = button.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(fixture.service.countdowns.first { $0.id == id }?.engine.phase == .running)
    }

    @Test
    func twoCardsFillThePanelAndSeparateTheClockFromCompleteControls() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let id = fixture.service.addCountdown(name: "Tea", duration: 3723)
        fixture.service.toggleCountdown(id: id)
        let host = fixture.host(ToolboxTimerPanel(service: fixture.service), size: CGSize(width: 236, height: 136))
        await fixture.layout()
        let first = try #require(Self.element("toolbox.timer.pomodoro", in: host) as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let second = try #require(Self.element("toolbox.timer.\(id)", in: host) as? any NSAccessibilityElementProtocol).accessibilityFrame()
        #expect(abs(first.height - 136) < 0.5 && abs(second.height - 136) < 0.5)
        #expect(abs(first.minY - second.minY) < 0.5)
        #expect(first.maxX <= second.minX)
        let clock = try #require(Self.element("toolbox.timerClock.\(id)", in: host) as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let toggle = try #require(Self.element("toolbox.toggleTimer.\(id)", in: host) as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let cancel = try #require(Self.element("toolbox.cancelTimer.\(id)", in: host) as? any NSAccessibilityElementProtocol).accessibilityFrame()
        #expect(clock.minY > toggle.maxY && clock.minY > cancel.maxY)
        #expect(toggle.width >= 23 && toggle.height >= 23 && cancel.width >= 23 && cancel.height >= 23)
        #expect(!toggle.intersects(cancel))
        #expect(second.insetBy(dx: -0.5, dy: -0.5).contains(clock))
        #expect(second.insetBy(dx: -0.5, dy: -0.5).contains(toggle))
        #expect(second.insetBy(dx: -0.5, dy: -0.5).contains(cancel))
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.compactMap { scrollView(in: $0) }.first
    }

    private static func element(_ identifier: String, in host: NSView) -> NSObject? {
        func descendants(_ object: NSObject) -> [NSObject] {
            let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
            return [object] + children.flatMap(descendants)
        }
        return descendants(host).first {
            $0.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                && $0.value(forKey: "accessibilityIdentifier") as? String == identifier
        }
    }

    @MainActor
    private final class Fixture {
        private let suite = "ToolboxTimerLayoutTests.\(UUID().uuidString)"
        private let defaults: UserDefaults
        private let releaseAccessibility: @MainActor () -> Void
        let service: PomodoroService
        var window: NSPanel?

        init() throws {
            let defaults = try #require(UserDefaults(suiteName: suite))
            self.defaults = defaults
            service = PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults,
                                      completionSoundHandler: {}, now: { Date(timeIntervalSince1970: 10000) })
            releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        }

        func host<Content: View>(_ content: Content, size: CGSize) -> NSHostingView<Content> {
            let window = NSPanel(contentRect: CGRect(origin: CGPoint(x: -100000, y: -100000), size: size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: content)
            host.sizingOptions = []
            window.contentView = host
            self.window = window
            return host
        }

        func layout() async {
            for _ in 0..<3 {
                window?.contentView?.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }

        func close() {
            service.stop()
            window?.close()
            releaseAccessibility()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
