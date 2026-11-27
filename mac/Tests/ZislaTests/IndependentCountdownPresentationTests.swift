import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct IndependentCountdownPresentationTests {
    @Test(arguments: IslandEdge.allCases)
    func countdownRowsStartAfterTheMonitoringRowAndUseTheEntireIsland(edge: IslandEdge) async throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let first = fixture.service.addCountdown(name: "Tea", duration: 60)
        let second = fixture.service.addCountdown(name: "Meeting", duration: 120)
        fixture.service.toggleCountdown(id: first)
        fixture.service.toggleCountdown(id: second)
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "31%", image: nil, style: .detailed), tooltip: "CPU")]
        let notices = fixture.service.countdownNotices(for: .right, limit: 2)
            + [IslandNotice(id: "ai-active-openai-layout", title: "AI")]
        let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons,
                                                                  settings: fixture.base.settings.settings, item: nil, at: fixture.date))
        #expect(layout.rowCount == 3)
        let host = fixture.host(FloatingIslandInformationView(layout: layout, visualizationStyle: .waveform, item: nil, date: fixture.date)
            .environmentObject(fixture.service), size: layout.size)
        await fixture.layout()
        let monitor = try #require(Self.element("cpu", in: host) as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let frames = try [first, second].map { id in
            try #require(Self.element("countdown.row.\(id)", in: host) as? any NSAccessibilityElementProtocol).accessibilityFrame()
        }
        let window = try #require(fixture.window).frame
        #expect(!monitor.intersects(frames[0]) && !monitor.intersects(frames[1]))
        #expect(!frames[0].intersects(frames[1]))
        for frame in frames {
            if edge.isVertical {
                #expect(abs(frame.height - window.height) < 1)
                #expect(abs(frame.minY - window.minY) < 1)
            } else {
                #expect(abs(frame.width - window.width) < 1)
                #expect(abs(frame.minX - window.minX) < 1)
            }
        }
        fixture.base.presenter.setStatusIcons(icons)
        #expect(layout.size == fixture.base.presenter.compactConfiguration(for: notices, at: fixture.date).statusIconSize)
    }

    @Test(arguments: IslandEdge.allCases, [false, true])
    func longNamesKeepTheFullClockOnEveryFloatingEdge(edge: IslandEdge, moreInformation: Bool) async throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let service = fixture.service
        let name = String(repeating: "Meeting preparation", count: 4)
        let id = service.addCountdown(name: name, duration: 3723)
        service.toggleCountdown(id: id)
        let notices = service.countdownNotices(for: .right)
        let settings = fixture.base.settings.settings
        let host: NSView
        if moreInformation {
            let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: [], settings: settings, item: nil, at: fixture.date))
            host = fixture.host(FloatingIslandInformationView(layout: layout, visualizationStyle: .waveform, item: nil, date: fixture.date)
                .environmentObject(service), size: layout.size)
        } else {
            let presentation = try #require(SideNoticeLayoutEngine().compactPillPresentations(for: notices, settings: settings).first)
            let length = presentation.length(thickness: 32, edge: edge)
            host = fixture.host(CompactPillStatusContent(presentation: presentation, text: presentation.text, edge: edge,
                                                         visualizationStyle: .waveform, item: nil, date: fixture.date).environmentObject(service),
                                size: edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32))
        }
        await fixture.layout()
        let clock = try #require(Self.element("countdown.time", in: host))
        #expect(clock.value(forKey: "accessibilityLabel") as? String == "01:02:03"
            || clock.value(forKey: "accessibilityValue") as? String == "01:02:03")
        let clockFrame = try #require(clock as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let label = try #require(Self.element("countdown.name", in: host))
        let nameFrame = try #require(label as? any NSAccessibilityElementProtocol).accessibilityFrame()
        #expect(!clockFrame.intersects(nameFrame))
        #expect(try #require(fixture.window).frame.insetBy(dx: -0.5, dy: -0.5).contains(clockFrame))
    }

    @Test
    func mergedFloatingTimerHasOneClockAndControlsTheCombinedCountdown() async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let service = fixture.service
        let first = service.addCountdown(name: "A", duration: 60)
        let second = service.addCountdown(name: "B", duration: 60)
        service.toggleCountdown(id: first)
        service.toggleCountdown(id: second)
        let layout = try #require(FloatingIslandInformationLayout(notices: service.countdownNotices(for: .right, limit: 2), icons: [],
                                                                  settings: fixture.base.settings.settings, item: nil, at: fixture.date))
        #expect(layout.countdowns.map(\.text) == ["A & B 00:01:00"])
        let host = fixture.host(FloatingIslandInformationView(layout: layout, visualizationStyle: .waveform, item: nil, date: fixture.date)
            .environmentObject(service), size: layout.size)
        await fixture.layout()
        let toggle = try #require(Self.element("countdown.\(first).toggleStartPause", in: host))
        _ = toggle.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(service.countdowns.allSatisfy { $0.engine.phase == .paused })
        _ = toggle.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(service.countdowns.allSatisfy { $0.engine.phase == .running })
        let cancel = try #require(Self.element("countdown.\(first).cancel", in: host))
        _ = cancel.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(service.countdowns.isEmpty)
    }

    @Test
    func addingTimersUsesTwoColumnsAndKeepsOverflowInsideTheLeftPanel() async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let service = fixture.service
        let host = fixture.host(ToolboxTimerPanel(service: service).environment(\.locale, AppLanguage.english.locale),
                                size: CGSize(width: 236, height: 136))
        await fixture.layout()
        let add = try #require(Self.element("toolbox.addTimer", in: host))
        _ = add.perform(NSSelectorFromString("accessibilityPerformPress"))
        await fixture.layout()
        let first = try #require(service.countdowns.first?.id)
        let firstName = try #require(Self.element("toolbox.renameTimer.pomodoro", in: host) as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let secondName = try #require(Self.element("toolbox.renameTimer.\(first)", in: host) as? any NSAccessibilityElementProtocol).accessibilityFrame()
        #expect(abs(firstName.midY - secondName.midY) < 1)
        #expect(firstName.maxX < secondName.minX)
        for _ in 0..<4 { service.addCountdown() }
        await fixture.layout()
        func scrollView(in view: NSView) -> NSScrollView? {
            (view as? NSScrollView) ?? view.subviews.compactMap { scrollView(in: $0) }.first
        }
        let scroll = try #require(scrollView(in: host))
        let document = try #require(scroll.documentView)
        #expect(scroll.frame.height <= 136)
        #expect(document.frame.height > scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: document.frame.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.minY > 0)
        #expect(try #require(fixture.window).frame.height == 136)
    }

    @Test(arguments: [false, true])
    func renamingATimerEntersAnEditableFieldAndKeepsItsRunningDeadline(independent: Bool) async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let service = fixture.service
        let id: UUID?
        if independent {
            let countdownID = service.addCountdown(name: "Tea", duration: 60)
            id = countdownID
            service.toggleCountdown(id: countdownID)
        } else {
            id = nil
            service.setName("Tea")
            service.start()
        }
        let identifier = id?.uuidString ?? "pomodoro"
        let deadline = independent ? service.countdowns.first?.engine.deadline : service.engine.deadline
        let host = fixture.host(ToolboxTimerCard(service: service, timerID: id, compact: true), size: CGSize(width: 115, height: 136))
        await fixture.layout()
        let rename = try #require(Self.element("toolbox.renameTimer.\(identifier)", in: host))
        _ = rename.perform(NSSelectorFromString("accessibilityPerformPress"))
        await fixture.layout()
        let field = try #require(Self.element("toolbox.timerName.\(identifier)", in: host))
        #expect(field.value(forKey: "accessibilityValue") as? String == "Tea")
        if independent {
            service.reset()
            await fixture.layout()
            #expect(Self.element("toolbox.timerName.\(identifier)", in: host) != nil)
        }
        func textField(in view: NSView) -> NSTextField? {
            (view as? NSTextField).flatMap { $0.isEditable ? $0 : nil }
                ?? view.subviews.compactMap { textField(in: $0) }.first
        }
        let input = try #require(textField(in: host))
        let window = try #require(fixture.window)
        try #require(window.makeFirstResponder(input))
        let editor = try #require(input.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("Meeting prep", replacementRange: editor.selectedRange())
        editor.insertNewline(nil)
        await fixture.layout()
        #expect((independent ? service.countdowns.first?.name : service.name) == "Meeting prep")
        #expect((independent ? service.countdowns.first?.engine.deadline : service.engine.deadline) == deadline)
    }

    @Test(arguments: ["complete", "reset", "group", "stop", "idle", "idle-reset", "idle-group", "idle-stop"], ["Writing", ""])
    func endingPomodoroWhileEditingCannotRestoreThePreviousSessionName(action: String, name: String) async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let service = fixture.service
        service.setFocusDuration(1)
        service.setName(name)
        if !action.hasPrefix("idle") { service.start() }
        let host = fixture.host(ToolboxTimerCard(service: service, timerID: nil, compact: false), size: CGSize(width: 236, height: 136))
        await fixture.layout()
        let rename = try #require(Self.element("toolbox.renameTimer.pomodoro", in: host))
        _ = rename.perform(NSSelectorFromString("accessibilityPerformPress"))
        await fixture.layout()
        let field = try #require(Self.element("toolbox.timerName.pomodoro", in: host))
        #expect(field.value(forKey: "accessibilityValue") as? String == name)
        if !action.hasPrefix("idle") {
            service.pause()
            await fixture.layout()
            #expect(Self.element("toolbox.timerName.pomodoro", in: host) != nil)
            service.start()
            await fixture.layout()
            #expect(Self.element("toolbox.timerName.pomodoro", in: host) != nil)
        } else {
            let other = service.addCountdown(name: "Tea", duration: 100)
            service.toggleCountdown(id: other)
            service.tick()
            await fixture.layout()
            #expect(Self.element("toolbox.timerName.pomodoro", in: host) != nil)
        }
        switch action {
        case "complete":
            fixture.date += 1
            service.tick()
        case "reset", "idle":
            let cancel = try #require(Self.element("toolbox.cancelTimer.pomodoro", in: host))
            _ = cancel.perform(NSSelectorFromString("accessibilityPerformPress"))
        case "idle-reset": service.reset()
        case "group", "idle-group": service.cancelCountdownGroup(["pomodoro"])
        default: service.stop()
        }
        await fixture.layout()
        #expect(Self.element("toolbox.timerName.pomodoro", in: host) == nil)
        #expect(Self.element("toolbox.renameTimer.pomodoro", in: host) != nil)
        #expect(service.name.isEmpty)
        service.start()
        #expect(service.name.isEmpty)
    }

    @Test(arguments: IslandEdge.allCases)
    func floatingTimersUseAtMostTwoRowsAndCoexistWithMonitoring(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let service = fixture.service
        let tea = service.addCountdown(name: "Tea", duration: 10)
        let meeting = service.addCountdown(name: "Meeting", duration: 20)
        let defaultTimer = service.addCountdown(duration: 30)
        for id in [tea, meeting, defaultTimer] { service.toggleCountdown(id: id) }
        let notices = service.countdownNotices(for: .left, limit: 3) + service.countdownNotices(for: .right, limit: 3)
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "31%", image: nil, style: .detailed), tooltip: "CPU")]
        let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons,
                                                                  settings: fixture.base.settings.settings, item: nil, at: fixture.date))
        #expect(layout.countdowns.count == 2)
        #expect(layout.countdowns.map(\.text) == ["Tea 00:00:10", "Meeting 00:00:20"])
        #expect(layout.icons.map(\.id) == ["cpu"])
        #expect(layout.primaryThickness == (edge.isVertical ? layout.iconSize?.width : layout.iconSize?.height))
        #expect((edge.isVertical ? layout.size.width : layout.size.height) == layout.primaryThickness + 64)
        #expect((edge.isVertical ? layout.size.height : layout.size.width)
            == max(layout.primaryLength, layout.countdownLength))
        #expect(!SideNoticePresenter.compactPanelIgnoresMouseEvents(statusIcons: icons, information: layout))
        service.cancelCountdown(id: tea)
        service.cancelCountdown(id: meeting)
        let unnamed = try #require(FloatingIslandInformationLayout(notices: service.countdownNotices(for: .right), icons: [],
                                                                   settings: fixture.base.settings.settings, item: nil, at: fixture.date))
        #expect(unnamed.countdowns.first?.text == "00:00:30")
        #expect(unnamed.primaryThickness == 0)
        #expect(unnamed.rowCount == 1)
        #expect((edge.isVertical ? unnamed.size.width : unnamed.size.height) == 32)
    }

    @Test(arguments: [AppLanguage.english, .arabic])
    func floatingButtonsOperateTheirOwnTimerAndRemainOnSeparateRows(language: AppLanguage) async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let service = fixture.service
        let first = service.addCountdown(name: "Tea", duration: 60)
        let second = service.addCountdown(name: "Meeting", duration: 120)
        service.toggleCountdown(id: first)
        service.toggleCountdown(id: second)
        let layout = try #require(FloatingIslandInformationLayout(notices: service.countdownNotices(for: .right, limit: 2), icons: [],
                                                                  settings: fixture.base.settings.settings, item: nil, at: fixture.date))
        let host = fixture.host(FloatingIslandInformationView(layout: layout, visualizationStyle: .waveform, item: nil, date: fixture.date)
            .environmentObject(service)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight), size: layout.size)
        await fixture.layout()
        let firstButton = try #require(Self.element("countdown.\(first).toggleStartPause", in: host))
        let secondButton = try #require(Self.element("countdown.\(second).toggleStartPause", in: host))
        let firstFrame = try #require(firstButton as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let secondFrame = try #require(secondButton as? any NSAccessibilityElementProtocol).accessibilityFrame()
        #expect(!firstFrame.intersects(secondFrame))
        #expect(firstFrame.width >= 23 && firstFrame.height >= 23)
        #expect(firstFrame.midY > secondFrame.midY)
        _ = firstButton.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(service.countdowns.first { $0.id == first }?.engine.phase == .paused)
        #expect(service.countdowns.first { $0.id == second }?.engine.phase == .running)
        let cancel = try #require(Self.element("countdown.\(second).cancel", in: host))
        #expect(cancel.value(forKey: "accessibilityLabel") as? String == AppLocalization.string("取消", language: language))
        _ = cancel.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(service.countdowns.map(\.id) == [first])
        #expect(service.phase == .idle)
    }

    @Test
    func singleCardKeepsItsHeightAndCompactCardKeepsNameTimeAndIconControls() async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let single = ToolboxTimerCard(service: fixture.service, timerID: nil, compact: false)
        let singleHost = fixture.host(single.environment(\.locale, AppLanguage.english.locale), size: CGSize(width: 236, height: 136))
        await fixture.layout()
        #expect(Self.element("toolbox.timerClock.pomodoro", in: singleHost) != nil)
        #expect(Self.element("toolbox.renameTimer.pomodoro", in: singleHost) != nil)
        let start = try #require(Self.element("toolbox.toggleTimer.pomodoro", in: singleHost))
        _ = start.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(fixture.service.phase == .running)
        let cancelPomodoro = try #require(Self.element("toolbox.cancelTimer.pomodoro", in: singleHost))
        _ = cancelPomodoro.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(fixture.service.phase == .idle)
        let id = fixture.service.addCountdown(name: "Tea", duration: 3723)
        let compact = ToolboxTimerCard(service: fixture.service, timerID: id, compact: true)
        let host = fixture.host(compact.environment(\.locale, AppLanguage.english.locale), size: CGSize(width: 115, height: 136))
        await fixture.layout()
        let toggle = try #require(Self.element("toolbox.toggleTimer.\(id)", in: host))
        let cancel = try #require(Self.element("toolbox.cancelTimer.\(id)", in: host))
        let clock = try #require(Self.element("toolbox.timerClock.\(id)", in: host))
        #expect(clock.value(forKey: "accessibilityLabel") as? String == "01:02:03")
        let toggleFrame = try #require(toggle as? any NSAccessibilityElementProtocol).accessibilityFrame()
        let cancelFrame = try #require(cancel as? any NSAccessibilityElementProtocol).accessibilityFrame()
        #expect(!toggleFrame.intersects(cancelFrame))
        #expect(try #require(fixture.window).frame.insetBy(dx: -0.5, dy: -0.5).contains(toggleFrame))
        #expect(try #require(fixture.window).frame.insetBy(dx: -0.5, dy: -0.5).contains(cancelFrame))
        _ = toggle.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(fixture.service.countdowns.first?.engine.phase == .running)
        _ = cancel.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(fixture.service.countdowns.isEmpty)
    }

    @Test
    func notchSelectsTheNearestTimerAfterTheQueueChangesOrder() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let first = fixture.service.addCountdown(name: "Tea", duration: 30)
        let second = fixture.service.addCountdown(name: "Meeting", duration: 60)
        fixture.service.toggleCountdown(id: first)
        fixture.service.toggleCountdown(id: second)
        AppModel.refreshFocusCountdownNotices(for: fixture.service, in: fixture.base.queue)
        fixture.service.toggleCountdown(id: first)
        AppModel.refreshFocusCountdownNotices(for: fixture.service, in: fixture.base.queue)
        #expect(fixture.base.queue.left.first?.title == "Tea")
        let selected = SideNoticeLayoutEngine().presentation(for: fixture.base.queue.left).activeFocusCountdownNotice
        #expect(selected?.title == "Meeting")
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
        let releaseAccessibility: @MainActor () -> Void
        private let clock = Clock()
        var date: Date {
            get { clock.date }
            set { clock.date = newValue }
        }
        lazy var service = PomodoroService(notificationRequestHandler: { _ in }, defaults: base.defaults,
                                           completionSoundHandler: {}, language: { .english }, now: { [clock] in clock.date })
        private final class Clock {
            var date = Date(timeIntervalSince1970: 10_000)
        }
        var window: NSPanel?

        init(edge: IslandEdge) throws {
            base = try .init(edge: edge)
            releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
            base.settings.settings.sideNoticesEnabled = true
            base.settings.settings.islandShowMoreInformation = true
        }

        func host<Content: View>(_ content: Content, size: CGSize) -> NSHostingView<Content> {
            window?.close()
            let window = NSPanel(contentRect: CGRect(origin: CGPoint(x: -100_000, y: -100_000), size: size),
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
            base.close()
        }
    }
}
