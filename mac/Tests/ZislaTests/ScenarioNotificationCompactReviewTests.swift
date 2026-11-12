import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct ScenarioNotificationCompactReviewTests {
    @Test(arguments: AppLanguage.allCases, ["top", "bottom", "left", "right", "camera-pill", "camera-notch"])
    func publishedReviewHasALocalizedActionInsideEveryCompactLayout(language: AppLanguage, placement: String) async throws {
        let fixture = try Fixture(language: language, placement: placement)
        defer { fixture.close() }
        await fixture.layout()
        let button = try #require(fixture.element("scenarioReview.open"),
            "The actual collapsed content must expose its published review")
        let expected = AppLocalization.format("已延后 %ld 条提示", locale: language.locale, [1])
            + " · " + AppLocalization.string("点击回顾", language: language)
        #expect(button.value(forKey: "accessibilityLabel") as? String == expected)
        let accessible = try #require(button as? any NSAccessibilityElementProtocol)
        let frame = accessible.accessibilityFrame()
        #expect(fixture.window.frame.insetBy(dx: -0.5, dy: -0.5).contains(frame))
        #expect(frame.width > 20 && frame.height > 20)
        #expect(fixture.view.selectedCompactStatusPriority == .transient)
        #expect(fixture.view.recordingOperationNotice == nil)
        #expect(fixture.base.queue.scenarioReview(displayIdentifier: "other-display").isEmpty)
        fixture.base.queue.dismissScenarioReview(displayIdentifier: fixture.scope)
        await fixture.layout()
        #expect(fixture.element("scenarioReview.open") == nil)
        #expect(fixture.view.selectedCompactStatusPriority == .media,
            "Dismissing the review must restore the existing live compact status")
        #expect(fixture.base.queue.left.map(\.id) == ["media-active-left"])
    }

    @Test
    func pressingTheCollapsedEntryOpensOnlyItsDisplayReviewAndClearingItRemovesTheEntry() async throws {
        let fixture = try Fixture(language: .english, placement: "top")
        defer { fixture.close() }
        var settings = fixture.base.settings.settings.notificationScenarios
        settings.rules.screenRecording.ordinary = .show
        settings.displayOverrides["other-display"] = .init()
        fixture.base.queue.configureNotificationScenarios(settings)
        fixture.base.queue.setNotificationScenarios([.screenRecording])
        fixture.base.queue.recordScenarioEvent(.init(id: "other-arrival", title: "Other display arrival"))
        fixture.base.queue.releaseScenarioEventVisibility(id: "other-arrival")
        fixture.base.queue.setNotificationScenarios([])
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(fixture.window.frame) })
        fixture.window.alphaValue = 0
        fixture.window.orderFrontRegardless()
        await fixture.layout()
        let button = try #require(fixture.element("scenarioReview.open"))
        func press(_ element: NSObject) throws -> Bool {
            let selector = NSSelectorFromString("accessibilityPerformPress")
            try #require(element.responds(to: selector))
            // SwiftUI AX nodes expose the selector without declaring NSAccessibilityProtocol.
            let action = unsafeBitCast(element.method(for: selector),
                to: (@convention(c) (NSObject, Selector) -> Bool).self)
            return action(element, selector)
        }
        #expect(try press(button))
        await fixture.layout()
        let reviewWindow = try #require(NSApplication.shared.windows.first {
            $0 !== fixture.window && $0.contentView.flatMap { fixture.element("scenarioReview.clear", in: $0) } != nil
        }, "The press must present the actual review contents for this display")
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(reviewWindow.frame) })
        let reviewHost = try #require(reviewWindow.contentView)
        let labels = fixture.descendants(reviewHost).flatMap { element in
            ["accessibilityLabel", "accessibilityValue"].compactMap { key -> String? in
                element.responds(to: NSSelectorFromString(key)) ? element.value(forKey: key) as? String : nil
            }
        }
        #expect(labels.contains("Recording arrival"))
        #expect(!labels.contains("Other display arrival"))
        let clear = try #require(fixture.element("scenarioReview.clear", in: reviewHost))
        #expect(try press(clear))
        await fixture.layout()
        #expect(fixture.base.queue.scenarioReview(displayIdentifier: fixture.scope).isEmpty)
        #expect(fixture.base.queue.scenarioReview(displayIdentifier: "other-display").map(\.title) == ["Other display arrival"])
        #expect(fixture.element("scenarioReview.open") == nil)
        reviewWindow.close()
    }

    @MainActor
    private final class Fixture {
        let base: StatusIconDestinationIntegrationTests.IconFixture
        let window: NSPanel
        let host: NSView
        let view: CompactStatusBarView
        let scope: String
        let releaseAccessibility: @MainActor () -> Void

        init(language: AppLanguage, placement: String) throws {
            let edge = IslandEdge(rawValue: placement) ?? .top
            base = try .init(edge: edge)
            releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
            base.language.language = language
            base.settings.settings.sideNoticesEnabled = true
            base.settings.settings.islandShowMoreInformation = true
            base.settings.settings.islandAppIconEnabled = false
            base.settings.settings.collapsedProgressGlowEnabled = false
            let camera = placement.hasPrefix("camera-")
            if camera { base.settings.settings.islandPlacement = IslandPlacement() }
            base.settings.settings.islandLayoutStyle = placement == "camera-notch" ? .notch : .pill
            base.settings.settings.notificationScenarios = .init(enabled: true)
            var screen = base.screen
            if camera {
                screen.safeAreaInsets = ScreenInsets(top: 32)
                screen.auxiliaryTopLeftArea = CGRect(x: screen.frame.minX, y: screen.frame.maxY - 32,
                    width: (screen.frame.width - 185) / 2, height: 32)
                screen.auxiliaryTopRightArea = CGRect(x: screen.frame.midX + 185 / 2, y: screen.frame.maxY - 32,
                    width: (screen.frame.width - 185) / 2, height: 32)
            }
            scope = screen.notificationScopeIdentifier
            base.queue.configureNotificationScenarios(base.settings.settings.notificationScenarios,
                displayIdentifiers: [scope, "other-display"])
            base.queue.enqueue(.init(id: "media-active-left", title: "Music", side: .left), expiresAfter: nil)
            base.queue.setNotificationScenarios([.screenRecording])
            base.queue.recordScenarioEvent(.init(id: "recording-arrival", title: "Recording arrival"))
            base.queue.releaseScenarioEventVisibility(id: "recording-arrival")
            base.queue.setNotificationScenarios([])
            _ = try #require(base.queue.scenarioReviewNotice(displayIdentifier: scope))
            base.queue.dismissScenarioReview(displayIdentifier: "other-display")
            let state = SideNoticeDisplayState()
            state.statusIcons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "31%", image: nil,
                style: .detailed), tooltip: "CPU")]
            state.notificationScopeIdentifier = scope
            state.placementMode = camera ? .camera : .custom
            state.islandEdge = edge
            state.compactWingHeight = 32
            state.compactBarCenterInset = camera ? 185 : 0
            let content = CompactStatusBarView(queue: base.queue, displayState: state, media: base.media,
                browserDownloads: base.downloads, settingsStore: base.settings, resultSweep: base.sweep,
                pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: base.defaults), onStatusHidden: {})
            view = content
            let notices = base.presenter.compactPresentationNotices(on: scope)
            let configuration = base.presenter.compactConfiguration(for: notices, at: .now)
            let size: CGSize
            if camera {
                size = try #require(SideNoticeLayoutEngine().compactBarFrame(for: screen, notices: notices,
                    settings: base.settings.settings)).size
            } else {
                size = ScreenLayoutEngine(configuration: configuration).layout(for: screen).collapsedFrame.size
            }
            base.presenter.stop()
            window = NSPanel(contentRect: CGRect(origin: CGPoint(x: -100_000, y: -100_000), size: size),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: content
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
                .environment(\._accessibilityReduceMotion, true)
                .frame(width: size.width, height: size.height))
            hosting.sizingOptions = []
            host = hosting
            window.contentView = host
        }

        func layout() async {
            for _ in 0..<3 {
                window.contentView?.layoutSubtreeIfNeeded()
                window.contentView?.displayIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }

        func descendants(_ object: NSObject) -> [NSObject] {
            let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
            return [object] + children.flatMap(descendants)
        }

        func element(_ identifier: String, in root: NSObject? = nil) -> NSObject? {
            return descendants(root ?? host).first {
                $0.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                    && $0.value(forKey: "accessibilityIdentifier") as? String == identifier
            }
        }

        func close() {
            window.close()
            releaseAccessibility()
            base.close()
        }
    }
}
