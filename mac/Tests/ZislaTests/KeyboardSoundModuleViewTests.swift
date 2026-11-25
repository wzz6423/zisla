import AVFAudio
import AppKit
import Foundation
import CoreGraphics
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit

@testable import Zisla
@testable import KeyboardKit

@Suite(.serialized)
struct KeyboardSoundModuleViewTests {
    @Test(arguments: AppLanguage.allCases, [CGSize(width: 340, height: 220), CGSize(width: 720, height: 401)])
    @MainActor
    func missingTypingStatsMatchTheCenteredEmptyState(language: AppLanguage, size: CGSize) async throws {
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let key = "暂无可显示的输入统计"
        let tableURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let title = try #require(table[key], "The empty-state title must exist in \(language.rawValue)")
        #expect(!title.isEmpty)
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            KeyboardSoundModuleView.content(summary: nil, voiceStatistics: nil)
                .frame(width: size.width, height: size.height)
            EmptyState(symbol: "chart.xyaxis.line", title: title)
                .padding(12)
                .frame(width: size.width, height: size.height)
        }
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let window = NSWindow(contentRect: .init(x: -100_000, y: -100_000, width: size.width * 2, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let bounds = window.convertToScreen(host.convert(host.bounds, to: nil))
        let titles = accessibilityObjects(host).filter { value($0, "accessibilityValue") as? String == title }
            .compactMap { $0 as? any NSAccessibilityElementProtocol }
        #expect(titles.count == 2, "The module and reference must both expose the translated title")
        let frames = titles.map { $0.accessibilityFrame() }
        let moduleFrame = try #require(frames.first { $0.midX < bounds.midX })
        let referenceFrame = try #require(frames.first { $0.midX > bounds.midX })
        #expect(abs(moduleFrame.midX - (bounds.minX + size.width / 2)) < 1,
                "The missing-data title must be horizontally centered: \(moduleFrame)")
        #expect(abs(moduleFrame.midY - referenceFrame.midY) < 1,
                "The missing-data title must match the shared empty state's vertical center: \(moduleFrame), \(referenceFrame)")
        #expect(bounds.insetBy(dx: -1, dy: -1).contains(moduleFrame))
        #expect(!window.isVisible)
    }

    @Test(arguments: [(Int64(0), false), (42, false), (0, true), (42, true)],
          [String?.none, "1", "0", "", "true", "01", " 1", "1 "])
    @MainActor
    func typingStatsAppearAndDisappearWithoutLeavingScrollContent(
        scenario: (characterCount: Int64, isDebugBuild: Bool), overrideValue: String?
    ) async throws {
        let (characterCount, isDebugBuild) = scenario
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let summary = KeyboardTypingStatsSummary(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastInputAt: nil,
            todayCharacterCount: characterCount,
            todayPeakCharactersPerSecond: 0,
            todayActiveSeconds: 0,
            todayActiveMinuteBuckets: 0,
            todayTopApplication: nil,
            todayKeyPressCount: characterCount,
            allTimeKeyPressCount: characterCount,
            applications: [],
            history: [],
            timelineRange: "day",
            recentBuckets: [],
            applicationTimelines: [],
            todayKeyCounts: [:],
            allTimeKeyCounts: [:]
        )
        let environment = overrideValue.map { ["ZISLA_DEBUG_IGNORE_KEYBOARD_STATS": $0] } ?? [:]
        let content = { (snapshot: KeyboardTypingStatsSummary?) in
            KeyboardSoundModuleView.content(summary: snapshot, voiceStatistics: nil,
                                            environment: environment, isDebugBuild: isDebugBuild)
                .frame(width: 720, height: 401)
        }
        let host = NSHostingView(rootView: content(nil))
        host.sizingOptions = []
        let window = NSWindow(contentRect: .init(x: -100_000, y: -100_000, width: 720, height: 401),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for snapshot in [nil, summary, nil] as [KeyboardTypingStatsSummary?] {
            host.rootView = content(snapshot)
            for _ in 0..<4 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
            let objects = accessibilityObjects(host)
            let hasEmptyTitle = objects.contains {
                value($0, "accessibilityValue") as? String == AppLocalization.text("暂无可显示的输入统计")
            }
            let hasScrollArea = objects.contains {
                value($0, "accessibilityRole") as? String == NSAccessibility.Role.scrollArea.rawValue
            }
            let showsDashboard = snapshot != nil && !(isDebugBuild && overrideValue == "1")
            #expect(hasEmptyTitle == !showsDashboard,
                    "Only unavailable statistics or an exact debug opt-in must show the empty state")
            #expect(hasScrollArea == showsDashboard,
                    "Only a displayed statistics dashboard must own a scroll area")
            if showsDashboard {
                #expect(objects.contains {
                    value($0, "accessibilityLabel") as? String == AppLocalization.text("今日按键")
                }, "The dashboard must keep its keyboard count label")
                #expect(objects.contains {
                    value($0, "accessibilityValue") as? String == characterCount.formatted(.number)
                },
                "Zero and populated summaries must retain their recorded counts")
            }
        }
        #expect(summary.todayCharacterCount == characterCount)
        #expect(!window.isVisible)
    }

    @Test(.serialized, arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    @MainActor
    func keyboardMenusAndSwitchesKeepNativeMediumHeight(language: AppLanguage) async throws {
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer {
            UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain)
            L10n.configure(for: .system)
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-keyboard-control-size-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "KeyboardControlSize.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in ["enabled", "typingStatsEnabled", "launchAtLoginEnabled"] {
            defaults.set(false, forKey: key)
        }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let previousAppearance = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = previousAppearance }
        let model = KeyboardAppModel(
            settings: AppSettings(defaults: defaults),
            permission: InputMonitoringPermissionManager(defaults: defaults),
            updates: UpdateController(client: GitHubReleaseClient { _ in
                throw GitHubReleaseClientError.invalidResponse
            }, defaults: defaults),
            soundPackLibrary: SoundPackLibrary(rootURL: directory.appendingPathComponent("packs"), bundledPackRootURL: nil),
            typingStats: TypingStatsModel(persistence: TypingStatsStore(databaseURL: directory.appendingPathComponent("stats.sqlite3"))),
            startsServices: false
        )
        defer { model.stop() }
        let host = NSHostingView(rootView: VStack(spacing: 0) {
            HStack {
                Picker("Reference", selection: Binding.constant(0)) { Text("Medium").tag(0) }
                    .labelsHidden().pickerStyle(.menu).controlSize(.regular)
                    .accessibilityIdentifier("reference-menu")
                Toggle("Reference", isOn: .constant(true))
                    .labelsHidden().toggleStyle(.switch).controlSize(.regular)
                    .accessibilityIdentifier("reference-switch")
            }
            MenuBarView(model: model)
        }
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let panel = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 360, height: 920),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        defer { panel.contentView = nil; panel.close() }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let controls = accessibilityObjects(host)
        let referenceMenuObject = controls.first {
            value($0, "accessibilityIdentifier") as? String == "reference-menu"
        }
        let referenceMenu = try #require(referenceMenuObject as? any NSAccessibilityElementProtocol)
        let referenceSwitchObject = controls.first {
            value($0, "accessibilityIdentifier") as? String == "reference-switch"
        }
        let referenceSwitch = try #require(referenceSwitchObject as? any NSAccessibilityElementProtocol)
        #expect(referenceMenu.accessibilityFrame().height > 0 && referenceSwitch.accessibilityFrame().height > 0)
        let menus = controls.filter {
            value($0, "accessibilityRole") as? String == NSAccessibility.Role.popUpButton.rawValue
                && value($0, "accessibilityIdentifier") as? String != "reference-menu"
        }
        #expect(menus.count == 3, "The production keyboard menu must expose sound, language and appearance selectors")
        for menu in menus {
            let element = try #require(menu as? any NSAccessibilityElementProtocol)
            #expect(abs(element.accessibilityFrame().height - referenceMenu.accessibilityFrame().height) < 0.5,
                    "Every keyboard selector must match the native medium height")
        }
        let switches = controls.filter {
            value($0, "accessibilitySubrole") as? String == "AXToggle"
                && value($0, "accessibilityIdentifier") as? String != "reference-switch"
        }.compactMap { $0 as? any NSAccessibilityElementProtocol }
        #expect(switches.count == 3)
        for control in switches {
            #expect(abs(control.accessibilityFrame().height - referenceSwitch.accessibilityFrame().height) < 0.5)
        }
        #expect(model.monitoringState == .stopped)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("stats.sqlite3").path))
        #expect(!panel.isVisible && !panel.isKeyWindow)
    }

    @Test(arguments: [false, true]) @MainActor
    func existingSoundMenusKeepMediumHeightInsideCompactEditorRows(perKey: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-sound-editor-controls-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SoundPackLibrary(rootURL: directory.appendingPathComponent("packs"), bundledPackRootURL: nil)
        let editor = SoundPackEditorModel(library: library, initialSelectionID: "fixture",
                                          temporaryCacheParentURL: directory, onLibraryDidChange: { _ in }, previewAudioAt: { _ in })
        await editor.createBlank()
        if perKey {
            editor.mappingMode = .perKey
            for phase in [KeySoundPhase.press, .release] {
                editor.setExistingAsset(SoundPackAssetID("fixture"), slot: .key(editor.selectedKeyID), phase: phase)
            }
        }
        let release = EnhancedAccessibilityTestScope.acquire()
        defer { release() }
        let host = NSHostingView(rootView: VStack {
            Menu(AppLocalization.text("已有音频")) { Button("Fixture") {} }
                .controlSize(.regular).accessibilityIdentifier("reference-sound-menu")
            SoundPackEditorView(editor: editor)
        })
        host.sizingOptions = []
        let panel = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 1_240, height: 900),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        defer { panel.contentView = nil; panel.close() }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let menus = accessibilityObjects(host).filter {
            value($0, "accessibilityRole") as? String == NSAccessibility.Role.menuButton.rawValue
        }
        let referenceObject = menus.first { value($0, "accessibilityIdentifier") as? String == "reference-sound-menu" }
        let reference = try #require(referenceObject as? any NSAccessibilityElementProtocol)
        let referenceWidth = reference.accessibilityFrame().width
        let choices = menus.filter {
            value($0, "accessibilityIdentifier") as? String != "reference-sound-menu"
                && abs((($0 as? any NSAccessibilityElementProtocol)?.accessibilityFrame().width ?? 0) - referenceWidth) < 3
        }
        #expect(choices.count == 2)
        for choice in choices {
            let element = try #require(choice as? any NSAccessibilityElementProtocol)
            #expect(abs(element.accessibilityFrame().height - reference.accessibilityFrame().height) < 0.5,
                    "Imported-audio selectors must remain medium sized in both mapping modes")
        }
        #expect(!panel.isVisible && !editor.isWorking)
        #expect(await editor.prepareForClosing())
    }

    @Test
    @MainActor
    func idleKeyboardServicesDoNotConstructAudioEngine() throws {
        let suiteName = "Zisla.KeyboardSoundModuleViewTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "enabled")
        defaults.set(false, forKey: "typingStatsEnabled")

        var constructionCount = 0
        let audioEngine = KeyboardAudioEngine(makeEngine: {
            constructionCount += 1
            return AVAudioEngine()
        })
        let model = KeyboardAppModel(
            settings: AppSettings(defaults: defaults),
            audioEngine: audioEngine,
            startsServices: false
        )

        model.startServicesIfNeeded()
        #expect(constructionCount == 0)
        model.stop()
    }

    @Test
    @MainActor
    func rightCommandFlagsChangedPreservesPresses() {
        let rightCommand = UInt16(54)
        #expect(
            KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: CGEventFlags(rawValue: 0x0000_0000_0000_0010),
                pressedModifierKeyCodes: []
            )
        )
        #expect(
            !KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: CGEventFlags(rawValue: 0x0000_0000_0000_0008),
                pressedModifierKeyCodes: [rightCommand]
            )
        )
        #expect(
            KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: .maskCommand,
                pressedModifierKeyCodes: []
            )
        )
        #expect(
            !KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: .maskCommand,
                pressedModifierKeyCodes: [rightCommand]
            )
        )
    }

    @Test
    func islandKeyboardModuleFollowsAIMonitor() throws {
        let modules = IslandModule.allCases
        let aiIndex = try #require(modules.firstIndex(of: .aiMonitor))
        let keyboardIndex = try #require(modules.firstIndex(of: .keyboardSound))
        #expect(keyboardIndex == modules.index(after: aiIndex))
    }

    @Test(arguments: [
        (CGFloat(560), false, false, false),
        (CGFloat(560), true, false, false),
        (CGFloat(560), true, true, false),
        (CGFloat(560), true, true, true),
        (CGFloat(752), true, true, true),
        (CGFloat(980), true, true, true),
    ], AppLanguage.allCases)
    @MainActor
    func statisticsStayWithinTheViewportWithoutHorizontalScrolling(
        scenario: (width: CGFloat, hasSummary: Bool, hasInput: Bool, hasVoice: Bool),
        language: AppLanguage
    ) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }

        let date = Date(timeIntervalSince1970: 1_795_000_000)
        let name = String(repeating: "Long application name ", count: 12)
        let buckets = scenario.hasInput ? (0..<12).map { index in
            KeyboardTypingStatsTrendPoint(id: index, start: date.addingTimeInterval(Double(index) * 300),
                                          characterCount: Int64(index * 1_000))
        } : []
        let summary = scenario.hasSummary ? KeyboardTypingStatsSummary(
            generatedAt: date, lastInputAt: scenario.hasInput ? date : nil,
            todayCharacterCount: scenario.hasInput ? 9_999_999_999 : 0,
            todayPeakCharactersPerSecond: scenario.hasInput ? 123 : 0,
            todayActiveSeconds: scenario.hasInput ? 18_000 : 0,
            todayActiveMinuteBuckets: scenario.hasInput ? 300 : 0,
            todayTopApplication: scenario.hasInput ? name : nil,
            todayKeyPressCount: scenario.hasInput ? 9_999_999_999 : 0,
            allTimeKeyPressCount: scenario.hasInput ? 99_999_999_999 : 0,
            applications: scenario.hasInput ? [KeyboardTypingStatsApplicationSummary(
                id: "fixture", name: name, characterCount: 9_999_999_999,
                activeMinuteBuckets: 300, peakCharactersPerSecond: 123
            )] : [],
            history: scenario.hasInput ? (0..<14).map { index in
                KeyboardTypingStatsDaySummary(id: "day-\(index)",
                                              date: date.addingTimeInterval(-Double(index) * 86_400),
                                              characterCount: Int64(index * 1_000), peakCharactersPerSecond: 123, activeMinuteBuckets: 300)
            } : [],
            timelineRange: "1h", recentBuckets: buckets,
            applicationTimelines: scenario.hasInput
                ? [KeyboardTypingStatsApplicationTimeline(id: "fixture", name: name, buckets: buckets)] : [],
            todayKeyCounts: scenario.hasInput ? [0: 123_456] : [:],
            allTimeKeyCounts: scenario.hasInput ? [0: 999_999] : [:]
        ) : nil
        let voiceStatistics = scenario.hasVoice ? VoiceHistoryStatistics(
            totalWordCount: 30_540, totalDuration: 13_680, wordsPerMinute: 133, savedTime: 32_040
        ) : nil
        let content = { (statistics: VoiceHistoryStatistics?) in
            KeyboardSoundModuleView.content(summary: summary, voiceStatistics: statistics, environment: [:])
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        }
        let host = NSHostingView(rootView: content(voiceStatistics))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -100_000, y: -100_000, width: scenario.width, height: 160),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }

        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        host.layoutSubtreeIfNeeded()
        let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
        if !scenario.hasSummary {
            #expect(scrolls.isEmpty, "Unavailable statistics must keep the centered empty state without a scroll area")
            #expect(!window.isVisible && !window.isKeyWindow)
            return
        }
        let scroll = try #require(scrolls.first)
        let document = try #require(scroll.documentView)
        let firstFrame = scroll.convert(document.bounds, from: document)
        try #require(firstFrame.width > 0)
        let centerOffset = firstFrame.midX - scroll.bounds.midX
        let scrollbarInset = scroll.bounds.width - firstFrame.width
        func settle() async {
            for _ in 0..<8 {
                host.layoutSubtreeIfNeeded()
                let frame = scroll.convert(document.bounds, from: document)
                #expect(abs(frame.midX - scroll.bounds.midX - centerOffset) < 0.5,
                        "Mounting, resizing and refreshing statistics must not add a horizontal shift")
                #expect(abs(scroll.bounds.width - frame.width - scrollbarInset) < 0.5,
                        "Scrollbar visibility must keep the statistics viewport width stable")
                #expect(abs(scroll.contentView.bounds.minX) < 0.5,
                        "Statistics must keep their horizontal scroll origin")
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }
        await settle()
        if scenario.hasVoice {
            for statistics in [nil, voiceStatistics] as [VoiceHistoryStatistics?] {
                host.rootView = content(statistics)
                await settle()
            }
        }

        for height: CGFloat in [160, 900, 160] {
            scroll.scrollerStyle = .legacy
            window.setContentSize(CGSize(width: scenario.width, height: height))
            await settle()
            #expect(document.frame.width <= scroll.contentView.bounds.width + 0.5,
                    "Statistics must fit the viewport at \(scenario.width)×\(height) in \(language.rawValue)")
            for delta: CGFloat in [-80, 80] {
                var shifted = scroll.contentView.bounds
                shifted.origin.x += delta
                #expect(abs(scroll.contentView.constrainBoundsRect(shifted).minX
                            - scroll.contentView.bounds.minX) < 0.5,
                "Horizontal trackpad movement must not shift keyboard statistics")
            }
            #expect(scroll.horizontalScrollElasticity == .none)
            if scenario.hasSummary && height == 160 {
                try #require(document.frame.height > scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: CGPoint(x: 0,
                                                      y: document.frame.height - scroll.contentView.bounds.height))
                scroll.reflectScrolledClipView(scroll.contentView)
                await settle()
                #expect(scroll.contentView.bounds.minY > 0,
                        "Vertical scrolling must still reach the complete keyboard statistics")
                let heatmap = try #require(accessibilityObjects(host).first {
                    value($0, "accessibilityLabel") as? String == AppLocalization.text("键盘按键热力图")
                } as? any NSAccessibilityElementProtocol)
                let frame = document.convert(window.convertFromScreen(heatmap.accessibilityFrame()), from: nil)
                #expect(frame.minX >= -0.5 && frame.maxX <= scroll.contentView.bounds.width + 0.5,
                        "The full keyboard heatmap must stay inside the horizontal viewport")
                #expect(frame.maxY <= scroll.contentView.bounds.maxY + 0.5,
                        "Vertical scrolling must reveal the bottom of the complete keyboard heatmap")
                let scroller = try #require(scroll.verticalScroller)
                let track = window.convertToScreen(scroller.convert(scroller.bounds, to: nil))
                #expect(!heatmap.accessibilityFrame().intersects(track),
                        "The vertical scrollbar must not cover the keyboard heatmap")
            }
        }
        #expect(!window.isVisible && !window.isKeyWindow)
    }

    @Test
    @MainActor
    func dashboardChartAxesPinWindowEndpointsAndToday() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let bucketSeconds: TimeInterval = 900
        let buckets = (0..<4).map { index in
            KeyboardTypingStatsTrendPoint(
                id: index,
                start: start.addingTimeInterval(bucketSeconds * Double(index)),
                characterCount: Int64(index)
            )
        }

        let trendDomain = try #require(KeyboardTypingStatsDashboardView.trendAxisDomain(for: buckets))
        #expect(trendDomain.lowerBound == start)
        #expect(trendDomain.upperBound == start.addingTimeInterval(bucketSeconds * 4))
        let trendDates = KeyboardTypingStatsDashboardView.trendAxisDates(for: buckets)
        #expect(trendDates.first == trendDomain.lowerBound)
        #expect(trendDates.last == trendDomain.upperBound)
        #expect(KeyboardTypingStatsDashboardView.chartXAxisLabelPadding > 0)
        #expect(KeyboardTypingStatsDashboardView.trendAxisDomain(for: Array(buckets.prefix(1))) == nil)
        #expect(KeyboardTypingStatsDashboardView.trendCharacterCountUpperBound(for: buckets) == 3)
        #expect(KeyboardTypingStatsDashboardView.trendCharacterCountUpperBound(for: []) == 1)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = calendar.startOfDay(for: now)
        let firstHistoryDate = try #require(calendar.date(byAdding: .day, value: -13, to: today))
        let staleHistoryDate = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let history = [
            KeyboardTypingStatsDaySummary(
                id: "first",
                date: firstHistoryDate,
                characterCount: 10,
                peakCharactersPerSecond: 2,
                activeMinuteBuckets: 1
            ),
            KeyboardTypingStatsDaySummary(
                id: "stale",
                date: staleHistoryDate,
                characterCount: 20,
                peakCharactersPerSecond: 3,
                activeMinuteBuckets: 2
            ),
        ]

        let historyDomain = KeyboardTypingStatsDashboardView.historyAxisDomain(
            for: history,
            now: now,
            calendar: calendar
        )
        #expect(historyDomain.lowerBound == firstHistoryDate)
        #expect(historyDomain.upperBound == today)
        let historyDates = KeyboardTypingStatsDashboardView.historyAxisDates(
            for: history,
            now: now,
            calendar: calendar
        )
        #expect(historyDates.last == today)
        #expect(historyDates.contains(today))
        let expectedHistoryAxisDates = try [
            #require(calendar.date(byAdding: .day, value: -12, to: today)),
            #require(calendar.date(byAdding: .day, value: -9, to: today)),
            #require(calendar.date(byAdding: .day, value: -6, to: today)),
            #require(calendar.date(byAdding: .day, value: -3, to: today)),
            today,
        ]
        #expect(historyDates == expectedHistoryAxisDates)
        let historyDayIntervals = zip(historyDates, historyDates.dropFirst()).map {
            calendar.dateComponents([.day], from: $0, to: $1).day
        }
        #expect(historyDayIntervals == [3, 3, 3, 3])
    }

    @Test
    @MainActor
    func dashboardHistoryYAxisUsesCharacterCountMaximum() {
        let history = [
            KeyboardTypingStatsDaySummary(
                id: "first",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                characterCount: 8_000,
                peakCharactersPerSecond: 80_000,
                activeMinuteBuckets: 1
            ),
            KeyboardTypingStatsDaySummary(
                id: "second",
                date: Date(timeIntervalSince1970: 1_700_086_400),
                characterCount: 12_345,
                peakCharactersPerSecond: 120_000,
                activeMinuteBuckets: 1
            ),
        ]
        let zeroHistory = [
            KeyboardTypingStatsDaySummary(
                id: "zero",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                characterCount: 0,
                peakCharactersPerSecond: 1,
                activeMinuteBuckets: 0
            ),
        ]

        #expect(KeyboardTypingStatsDashboardView.historyCharacterCountUpperBound(for: history) == 12_345)
        #expect(KeyboardTypingStatsDashboardView.historyCharacterCountUpperBound(for: zeroHistory) == 1)
        #expect(KeyboardTypingStatsDashboardView.historyCharacterCountUpperBound(for: []) == 1)
    }

    @Test
    func dashboardCompactCountTextUsesKAndWBoundaries() {
        #expect(KeyboardTypingStatsDashboardView.compactCountText(-1) == "0")
        #expect(KeyboardTypingStatsDashboardView.compactCountText(999) == "999")
        #expect(KeyboardTypingStatsDashboardView.compactCountText(1_000) == "1k")
        #expect(KeyboardTypingStatsDashboardView.compactCountText(7_468) == "7.5k")
        #expect(KeyboardTypingStatsDashboardView.compactCountText(10_000) == "1w")
        #expect(KeyboardTypingStatsDashboardView.compactCountText(19_240) == "1.9w")
    }

    @Test
    @MainActor
    func applicationTimelineAxisAlignsWithBucketCells() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let step: TimeInterval = 900
        let buckets = (0..<96).map { index in
            KeyboardTypingStatsTrendPoint(
                id: index,
                start: start.addingTimeInterval(step * Double(index)),
                characterCount: Int64(index)
            )
        }
        let width: CGFloat = 240
        let spacing = KeyboardTypingStatsDashboardView.timelineBucketSpacing
        let ticks = KeyboardTypingStatsDashboardView.timelineAxisTicks(
            buckets: buckets,
            width: width
        )

        #expect(ticks.count == 3)

        let count = CGFloat(buckets.count)
        let cellWidth = (width - spacing * (count - 1)) / count
        let pitch = cellWidth + spacing

        // All ticks land on bucket boundaries: first edge, middle edge, and last edge.
        #expect(abs(ticks[0].x - 0) < 0.001)
        #expect(abs(ticks[1].x - 48 * pitch) < 0.001)
        #expect(abs(ticks[2].x - width) < 0.001)
        #expect(cellWidth > 0)

        #expect(ticks[0].date == start)
        #expect(ticks[1].date == start.addingTimeInterval(step * 48))
        #expect(ticks[2].date == start.addingTimeInterval(step * 96))

        // Time-to-pixel mapping must stay linear so labels remain aligned with buckets.
        let span = ticks[2].date.timeIntervalSince(ticks[0].date)
        for tick in ticks {
            let expected = CGFloat(tick.date.timeIntervalSince(ticks[0].date) / span) * width
            #expect(abs(tick.x - expected) < 1)
        }

        #expect(ticks[0].anchor == .leading)
        #expect(ticks[1].anchor == .center)
        #expect(ticks[2].anchor == .trailing)

        // Do not draw ticks without enough data or layout width.
        #expect(
            KeyboardTypingStatsDashboardView
                .timelineAxisTicks(buckets: Array(buckets.prefix(1)), width: width)
                .isEmpty
        )
        #expect(KeyboardTypingStatsDashboardView.timelineAxisTicks(buckets: buckets, width: 0).isEmpty)
    }

    @MainActor private func accessibilityObjects(_ object: NSObject) -> [NSObject] {
        [object] + (value(object, "accessibilityChildren") as? [NSObject] ?? []).flatMap(accessibilityObjects)
    }

    @MainActor private func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
}
