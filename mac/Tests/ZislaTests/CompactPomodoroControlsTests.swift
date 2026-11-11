import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
struct CompactPomodoroControlsTests {
    @Test(arguments: IslandEdge.allCases, [false, true])
    func customCountdownControlsPauseResumeAndResetWithoutCompleting(
        edge: IslandEdge, moreInformation: Bool
    ) async throws {
        let fixture = try Fixture(edge: edge, moreInformation: moreInformation)
        defer { fixture.close() }
        fixture.base.settings.settings.collapsedProgressGlowEnabled = true
        fixture.service.start()
        fixture.now += 25
        fixture.service.tick()
        var notice = try #require(fixture.base.queue.right.first)
        notice.progress = 0.25
        fixture.base.queue.updateIfPresent(notice)
        await fixture.layout()
        try fixture.press("pomodoro.toggleStartPause")
        await fixture.layout()
        #expect(fixture.service.phase == .paused)
        let paused = fixture.service.focusCountdownNotice(for: .right)
        fixture.now += 1_000
        fixture.service.tick()
        #expect(fixture.service.focusCountdownNotice(for: .right).detail == paused.detail)
        #expect(fixture.service.focusCountdownNotice(for: .right).progress == 0.25)
        #expect(try fixture.label("pomodoro.toggleStartPause") == AppLocalization.string("继续", language: .english))
        try fixture.press("pomodoro.toggleStartPause")
        await fixture.layout()
        #expect(fixture.service.phase == .running)
        fixture.now += 25
        fixture.service.tick()
        #expect(fixture.service.focusCountdownNotice(for: .right).progress == 0.5)
        try fixture.press("pomodoro.reset")
        await fixture.layout()
        #expect(fixture.service.phase == .idle && fixture.service.mode == .focus)
        #expect(fixture.service.displayClockWithHours == "00:01:40")
        #expect(fixture.notifications == 0 && fixture.sounds == 0,
            "Quick controls must never fabricate a completed focus session")
        #expect(!fixture.window.isVisible)
    }

    @Test(arguments: AppLanguage.allCases, IslandLayoutStyle.allCases.flatMap { style in
        ["00:01:40", "100:00:00"].map { (style, $0) }
    })
    func controlsUseTheRequestedLanguageAndCameraGap(language: AppLanguage, scenario: (IslandLayoutStyle, String)) async throws {
        let (style, countdown) = scenario
        let fixture = try Fixture(edge: .top, moreInformation: false, language: language, camera: true,
            countdown: countdown, style: style)
        defer { fixture.close() }
        fixture.service.start()
        fixture.base.settings.settings.collapsedProgressGlowEnabled = true
        var notice = try #require(fixture.base.queue.right.first)
        notice.progress = 0.25
        fixture.base.queue.updateIfPresent(notice)
        await fixture.layout()
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let tableURL = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        for key in ["暂停", "继续", "重置番茄钟"] {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
        }
        #expect(try fixture.label("pomodoro.toggleStartPause") == table["暂停"])
        #expect(try fixture.label("pomodoro.reset") == table["重置番茄钟"])
        for identifier in ["pomodoro.toggleStartPause", "pomodoro.reset", "pomodoro.countdown", "pomodoro.clock"] {
            let button = try #require(fixture.element(identifier) as? any NSAccessibilityElementProtocol)
            let frame = button.accessibilityFrame()
            let windowFrame = fixture.window.frame
            let centerGap = CGRect(x: windowFrame.midX - 185 / 2, y: windowFrame.minY,
                width: 185, height: windowFrame.height)
            #expect(windowFrame.insetBy(dx: -0.5, dy: -0.5).contains(frame))
            #expect(!frame.intersects(centerGap), "Pomodoro controls and time must stay outside the physical camera gap")
            if identifier == "pomodoro.countdown" || identifier == "pomodoro.clock" {
                #expect(frame.maxX <= centerGap.minX, "The clock and countdown must stay on the left of the camera")
            } else {
                #expect(frame.minX >= centerGap.maxX, "The quick controls must stay on the right of the camera")
                #expect(frame.width >= 23 && frame.height >= 23)
            }
        }
        let clock = try #require(fixture.element("pomodoro.clock") as? any NSAccessibilityElementProtocol)
        let time = try #require(fixture.element("pomodoro.countdown") as? any NSAccessibilityElementProtocol)
        #expect(clock.accessibilityFrame().maxX + 5.5 <= time.accessibilityFrame().minX,
            "The clock must precede the complete countdown with the existing 6pt gap")
        let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        let rounded = try #require(font.fontDescriptor.withDesign(.rounded))
        let measuredFont = try #require(NSFont(descriptor: rounded, size: 14))
        let textWidth = (countdown as NSString).size(withAttributes: [.font: measuredFont]).width
        #expect(time.accessibilityFrame().width + 0.5 >= textWidth,
            "The left wing must fit the complete time at its normal font size, including three-digit hours")
        #expect(fixture.element("pomodoro.countdown")?.value(forKey: "accessibilityValue") as? String == "Focus \(countdown)")
        try fixture.press("pomodoro.toggleStartPause")
        await fixture.layout()
        #expect(try fixture.label("pomodoro.toggleStartPause") == table["继续"])
    }

    @Test(arguments: IslandEdge.allCases, [AppLanguage.english, .arabic])
    func compactPillButtonsRemainInsideTheirAllocatedRow(edge: IslandEdge, language: AppLanguage) async throws {
        let fixture = try Fixture(edge: edge, moreInformation: false, language: language)
        defer { fixture.close() }
        await fixture.layout()
        let toggle = try #require(fixture.element("pomodoro.toggleStartPause") as? any NSAccessibilityElementProtocol)
        let reset = try #require(fixture.element("pomodoro.reset") as? any NSAccessibilityElementProtocol)
        let first = toggle.accessibilityFrame()
        let second = reset.accessibilityFrame()
        #expect(fixture.window.frame.insetBy(dx: -0.5, dy: -0.5).contains(first))
        #expect(fixture.window.frame.insetBy(dx: -0.5, dy: -0.5).contains(second))
        #expect(first.width >= 23 && first.height >= 23 && second.width >= 23 && second.height >= 23)
        #expect(!first.intersects(second))
        if edge.isVertical {
            #expect(first.maxY <= fixture.window.frame.midY && second.maxY <= first.minY,
                "Vertical pills must place the controls after the clock and time")
        } else {
            #expect(first.minX >= fixture.window.frame.midX && second.minX >= first.maxX,
                "Horizontal pills must keep the controls on the physical right in every language")
        }
    }

    @MainActor
    private final class Fixture {
        let base: StatusIconDestinationIntegrationTests.IconFixture
        let window: NSPanel
        let host: NSView
        let releaseAccessibility: @MainActor () -> Void
        private let clock = Clock()
        let service: PomodoroService
        var now: Date {
            get { clock.date }
            set { clock.date = newValue }
        }
        var notifications: Int { clock.notifications }
        var sounds: Int { clock.sounds }

        private final class Clock {
            var date = Date(timeIntervalSince1970: 100)
            var notifications = 0
            var sounds = 0
        }

        init(edge: IslandEdge, moreInformation: Bool, language: AppLanguage = .english,
             camera: Bool = false, countdown: String = "00:01:40", style: IslandLayoutStyle = .pill) throws {
            base = try .init(edge: edge)
            releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
            base.settings.settings.sideNoticesEnabled = true
            base.settings.settings.islandShowMoreInformation = moreInformation
            base.settings.settings.collapsedProgressGlowEnabled = false
            base.settings.settings.islandAppIconEnabled = false
            base.settings.settings.islandLayoutStyle = style
            if camera { base.settings.settings.islandPlacement = IslandPlacement() }
            let state = SideNoticeDisplayState()
            state.placementMode = camera ? .camera : .custom
            state.islandEdge = edge
            state.compactWingHeight = 32
            state.compactBarCenterInset = camera ? 185 : 0
            let notice = IslandNotice(id: "focus-countdown-controls", title: "Focus", detail: countdown, progress: 0)
            base.queue.enqueue(notice, expiresAfter: nil)
            var screen = base.screen
            if camera {
                screen.safeAreaInsets = ScreenInsets(top: 32)
                screen.auxiliaryTopLeftArea = CGRect(x: screen.frame.minX, y: screen.frame.maxY - 32,
                    width: (screen.frame.width - 185) / 2, height: 32)
                screen.auxiliaryTopRightArea = CGRect(x: screen.frame.midX + 185 / 2, y: screen.frame.maxY - 32,
                    width: (screen.frame.width - 185) / 2, height: 32)
            }
            let size = try #require(SideNoticeLayoutEngine().compactBarFrame(
                for: screen, notices: [notice], settings: base.settings.settings)).size
            window = NSPanel(contentRect: CGRect(origin: CGPoint(x: -100_000, y: -100_000), size: size),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            service = PomodoroService(notificationRequestHandler: { [clock] _ in clock.notifications += 1 },
                defaults: base.defaults, completionSoundHandler: { [clock] in clock.sounds += 1 },
                language: { language }, now: { [clock] in clock.date })
            let content = CompactStatusBarView(queue: base.queue, displayState: state, media: base.media,
                browserDownloads: base.downloads, settingsStore: base.settings, resultSweep: base.sweep,
                pomodoro: service, onStatusHidden: {})
            let hosting = NSHostingView(rootView: content
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
                .environment(\._accessibilityReduceMotion, true)
                .frame(width: size.width, height: size.height))
            hosting.sizingOptions = []
            host = hosting
            window.contentView = host
            service.setFocusDuration(100)
        }

        func layout() async {
            for _ in 0..<3 {
                window.contentView?.layoutSubtreeIfNeeded()
                window.contentView?.displayIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }

        func element(_ identifier: String) -> NSObject? {
            func descendants(_ object: NSObject) -> [NSObject] {
                let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                    ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
                return [object] + children.flatMap(descendants)
            }
            return window.contentView.flatMap { descendants($0).first {
                $0.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                    && $0.value(forKey: "accessibilityIdentifier") as? String == identifier
            } }
        }

        func label(_ identifier: String) throws -> String {
            try #require(element(identifier)?.value(forKey: "accessibilityLabel") as? String)
        }

        func press(_ identifier: String) throws {
            let button = try #require(element(identifier))
            let action = NSSelectorFromString("accessibilityPerformPress")
            try #require(button.responds(to: action))
            _ = button.perform(action)
        }

        func close() {
            service.stop()
            window.close()
            releaseAccessibility()
            base.close()
        }
    }
}
