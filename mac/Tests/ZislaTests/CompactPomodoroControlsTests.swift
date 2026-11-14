import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
struct CompactPomodoroControlsTests {
    @Test(arguments: IslandEdge.allCases, [0, 1, 8])
    func hoveringQuickControlsKeepsTheCountdownClickable(edge: IslandEdge, iconCount: Int) async throws {
        let base = try StatusIconDestinationIntegrationTests.IconFixture(edge: edge)
        defer { base.close() }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        base.reducesMotion = true
        base.language.language = .english
        base.settings.settings.sideNoticesEnabled = true
        base.settings.settings.islandShowMoreInformation = iconCount > 0
        base.settings.settings.islandAppIconEnabled = false
        let notice = IslandNotice(id: "focus-countdown-hover", title: "Focus", detail: "00:12:30")
        base.queue.enqueue(notice, expiresAfter: nil)
        let icons = (0..<iconCount).map { IslandStatusIcon(id: "cpu-\($0)",
            content: .metric(.cpu, text: "31%", image: nil, style: .detailed), tooltip: "CPU") }
        base.presenter.setStatusIcons(icons)
        let coordinator = OverlayCoordinator(contentView: NSView(),
            layoutEngine: ScreenLayoutEngine(configuration: base.presenter.compactConfiguration(
                for: [notice], at: Date(timeIntervalSince1970: 100))))
        coordinator.screenSnapshotProvider = { [base] in [base.screen] }
        let outside = CGPoint(x: base.screen.frame.minX - 100, y: base.screen.frame.minY - 100)
        coordinator.pointerLocationProvider = { outside }
        coordinator.collapsedControlContainsPoint = { [base] in base.presenter.containsCompactPomodoroControl(at: $0) }
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.selectActiveDisplay(at: CGPoint(x: base.screen.frame.midX, y: base.screen.frame.midY))
        var expanded = false
        coordinator.onVisibilityChanged = {
            expanded = $0
            base.presenter.setIslandExpanded($0)
        }
        base.presenter.setScreenLocked(false)
        let host = try #require(NSApplication.shared.windows.compactMap {
            $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>>
        }.first { $0.rootView.content.settingsStore === base.settings })
        let window = try #require(host.window)
        let service = host.rootView.content.pomodoro
        defer { service.stop() }
        service.start()
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        for (identifier, expectedPhase) in [("pomodoro.toggleStartPause", PomodoroPhase.paused),
                                          ("pomodoro.toggleStartPause", .running), ("pomodoro.reset", .idle)] {
            let button = try #require(Self.element(identifier, in: host))
            let accessible = try #require(button as? any NSAccessibilityElementProtocol)
            let frame = accessible.accessibilityFrame()
            let point = CGPoint(x: frame.midX, y: frame.midY)
            let target = try #require(host.hitTest(host.convert(window.convertPoint(fromScreen: point), from: nil)))
            #expect(!(target is CompactPomodoroControlRegionView),
                "Measuring a button must not intercept its mouse events")
            let pill = try #require(coordinator.activeLayout).collapsedFrame
            #expect(try #require(coordinator.activeLayout).containsTrigger(point))
            let entry = edge.isVertical ? CGPoint(x: pill.minX + 0.5, y: point.y)
                : CGPoint(x: point.x, y: pill.minY + 0.5)
            coordinator.handlePointer(at: entry)
            #expect(!expanded, "The pointer must be able to reach a button across the pill's padding")
            coordinator.handlePointer(at: point)
            #expect(!expanded, "Hovering a Pomodoro button must not replace it with the expanded island")
            #expect(window.isVisible && !window.ignoresMouseEvents,
                "The countdown panel must stay available to receive the click")
            _ = button.perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(service.phase == expectedPhase)
        }
        coordinator.handlePointer(at: outside)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let first = try #require(Self.element("pomodoro.toggleStartPause", in: host)
            as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let second = try #require(Self.element("pomodoro.reset", in: host)
            as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let gap = edge.isVertical ? CGPoint(x: first.midX, y: (first.minY + second.maxY) / 2)
            : CGPoint(x: (first.maxX + second.minX) / 2, y: first.midY)
        #expect(base.presenter.containsCompactPomodoroControl(at: gap))
        coordinator.handlePointer(at: gap)
        #expect(!expanded, "The space between the buttons belongs to the protected countdown region")
        let besideButton = edge.isVertical ? CGPoint(x: first.midX, y: first.maxY + 0.5)
            : CGPoint(x: first.minX - 0.5, y: first.midY)
        #expect(base.presenter.containsCompactPomodoroControl(at: besideButton))
        coordinator.handlePointer(at: besideButton)
        #expect(!expanded, "Approaching the buttons through neighboring countdown content must not expand")
        let pill = try #require(coordinator.activeLayout).collapsedFrame
        let outerEdge = edge.isVertical ? CGPoint(x: first.midX, y: pill.minY)
            : CGPoint(x: pill.maxX, y: first.midY)
        #expect(base.presenter.containsCompactPomodoroControl(at: outerEdge))
        coordinator.handlePointer(at: outerEdge)
        #expect(!expanded, "The outer edge and trailing padding must be protected before reaching a button")
        if iconCount == 0 {
            for point in [CGPoint(x: pill.minX, y: pill.midY), CGPoint(x: pill.midX, y: pill.maxY),
                          CGPoint(x: pill.midX, y: pill.minY)] {
                coordinator.handlePointer(at: point)
                #expect(!expanded, "The complete standalone countdown pill must stay collapsed")
            }
        } else {
            let icon = try #require(Self.element("cpu-0", in: host) as? any NSAccessibilityElementProtocol)
            let frame = icon.accessibilityFrame()
            coordinator.handlePointer(at: CGPoint(x: frame.midX, y: frame.midY))
            #expect(expanded, "Other status icons must retain hover expansion")
            #expect(!base.presenter.containsCompactPomodoroControl(at: gap),
                "Hidden countdown regions must not suppress an expanded island")
        }
        coordinator.handlePointer(at: outside)
        #expect(!expanded && window.isVisible)
        #expect(base.queue.right == [notice], "Quick controls must not consume the countdown notice")
        base.queue.removeAll()
        base.queue.enqueue(IslandNotice(id: "ai-active-hover-scope", title: "AI"), expiresAfter: nil)
        base.presenter.setStatusIcons(icons)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let status = try #require(host.rootView.content.displayState.compactLayout).frame
        let statusPoint = CGPoint(x: status.midX, y: status.midY)
        coordinator.handlePointer(at: statusPoint)
        #expect(expanded, "Replacing the countdown with another status must restore hover expansion")
        coordinator.handlePointer(at: outside)
    }

    @Test(arguments: IslandEdge.allCases)
    func quickControlRegionsFollowTheWindowAndDisappearWithTheCountdown(edge: IslandEdge) async throws {
        let fixture = try Fixture(edge: edge, moreInformation: false)
        defer { fixture.close() }
        fixture.base.reducesMotion = true
        fixture.base.presenter.setScreenLocked(false)
        let host = try #require(NSApplication.shared.windows.compactMap {
            $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>>
        }.first { $0.rootView.content.settingsStore === fixture.base.settings })
        let window = try #require(host.window)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let button = try #require(Self.element("pomodoro.reset", in: host) as? any NSAccessibilityElementProtocol)
        let frame = button.accessibilityFrame()
        let point = CGPoint(x: frame.midX, y: frame.midY)
        #expect(fixture.base.presenter.containsCompactPomodoroControl(at: point))
        #expect(!fixture.base.presenter.containsCompactPomodoroControl(at: CGPoint(x: CGFloat.nan, y: CGFloat.infinity)))
        window.setFrameOrigin(CGPoint(x: window.frame.minX + 1_000, y: window.frame.minY - 1_000))
        let moved = CGPoint(x: point.x + 1_000, y: point.y - 1_000)
        #expect(!fixture.base.presenter.containsCompactPomodoroControl(at: point))
        #expect(fixture.base.presenter.containsCompactPomodoroControl(at: moved),
            "The exclusion must follow the rendered button after moving the island")
        window.ignoresMouseEvents = true
        #expect(!fixture.base.presenter.containsCompactPomodoroControl(at: moved),
            "A passive panel must not reserve a clickable area")
        window.ignoresMouseEvents = false
        fixture.base.queue.removeAll()
        fixture.base.presenter.setStatusIcons([])
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        #expect(!fixture.base.presenter.containsCompactPomodoroControl(at: moved),
            "Removing the countdown must release its former button area")
        fixture.base.presenter.stop()
        #expect(!fixture.base.presenter.containsCompactPomodoroControl(at: moved))
    }

    @Test(arguments: IslandLayoutStyle.allCases)
    func cameraCountdownWingsStayCollapsedWhileTheCenterExpands(style: IslandLayoutStyle) async throws {
        let fixture = try Fixture(edge: .top, moreInformation: false, camera: true, style: style)
        defer { fixture.close() }
        fixture.base.reducesMotion = true
        let presenter = SideNoticePresenter(queue: fixture.base.queue, resultSweep: fixture.base.sweep,
            media: fixture.base.media, pomodoro: fixture.service, browserDownloads: fixture.base.downloads,
            settingsStore: fixture.base.settings, languageStore: fixture.base.language, isScreenLocked: true,
            reduceMotion: { true }, screenSnapshotProvider: { [fixture] in [fixture.screen] })
        defer { presenter.stop() }
        let notice = try #require(fixture.base.queue.right.first)
        let coordinator = OverlayCoordinator(contentView: NSView(),
            layoutEngine: ScreenLayoutEngine(configuration: presenter.compactConfiguration(
                for: [notice], at: Date(timeIntervalSince1970: 100))))
        coordinator.screenSnapshotProvider = { [fixture] in [fixture.screen] }
        let outside = CGPoint(x: fixture.screen.frame.minX - 100, y: fixture.screen.frame.minY - 100)
        coordinator.pointerLocationProvider = { outside }
        coordinator.collapsedControlContainsPoint = { presenter.containsCompactPomodoroControl(at: $0) }
        coordinator.start()
        defer { coordinator.stop() }
        var expanded = false
        coordinator.onVisibilityChanged = {
            expanded = $0
            presenter.setIslandExpanded($0)
        }
        presenter.setScreenLocked(false)
        let host = try #require(NSApplication.shared.windows.compactMap {
            $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>>
        }.first { $0.rootView.content.settingsStore === fixture.base.settings })
        let window = try #require(host.window)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let frame = try #require(host.rootView.content.displayState.compactLayout).frame
        for point in [CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: frame.minX + 1, y: frame.minY),
                      CGPoint(x: frame.maxX, y: frame.midY), CGPoint(x: frame.maxX - 1, y: frame.maxY)] {
            #expect(presenter.containsCompactPomodoroControl(at: point),
                "Countdown wings must protect their complete outer padding")
            coordinator.handlePointer(at: point)
            #expect(!expanded)
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        #expect(!presenter.containsCompactPomodoroControl(at: center),
            "The camera gap must remain available for normal hover expansion")
        coordinator.handlePointer(at: center)
        #expect(expanded)
        coordinator.handlePointer(at: outside)
        #expect(!expanded && window.isVisible)
        fixture.base.queue.removeAll()
        fixture.base.queue.enqueue(IslandNotice(id: "ai-active-camera-scope", title: "AI"), expiresAfter: nil)
        presenter.setStatusIcons([])
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let status = try #require(host.rootView.content.displayState.compactLayout).frame
        #expect(!presenter.containsCompactPomodoroControl(at: CGPoint(x: status.minX + 1, y: status.midY)),
            "Camera wings showing another status must not retain a countdown exclusion")
    }

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
        let base: StatusIconDestinationIntegrationTests.IconFixture
        let screen: ScreenSnapshot
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
            var snapshot = base.screen
            if camera {
                snapshot.safeAreaInsets = ScreenInsets(top: 32)
                snapshot.auxiliaryTopLeftArea = CGRect(x: snapshot.frame.minX, y: snapshot.frame.maxY - 32,
                    width: (snapshot.frame.width - 185) / 2, height: 32)
                snapshot.auxiliaryTopRightArea = CGRect(x: snapshot.frame.midX + 185 / 2, y: snapshot.frame.maxY - 32,
                    width: (snapshot.frame.width - 185) / 2, height: 32)
            }
            screen = snapshot
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
            CompactPomodoroControlsTests.element(identifier, in: host)
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
