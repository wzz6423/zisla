import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@MainActor
@Suite(.serialized)
struct SettingsSplitViewTests {
    @Test
    func nativeToolbarSeparatesSidebarAndDetailControls() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        await fixture.layout()
        let split = try fixture.controller()
        let toolbar = try #require(fixture.window.toolbar)
        #expect(toolbar.items.map(\.itemIdentifier) == [
            .flexibleSpace, SettingsSplitViewController.sidebarIdentifier,
            .sidebarTrackingSeparator, SettingsSplitViewController.navigationIdentifier, .flexibleSpace,
        ])
        let separator = try #require(toolbar.items[2] as? NSTrackingSeparatorToolbarItem)
        #expect(separator.splitView === split.splitView)
        #expect(separator.dividerIndex == 0)
        #expect(split.splitView.isVertical)
        #expect(split.splitViewItems[0].behavior == .sidebar)
        let navigation = try fixture.navigationButtons()
        #expect(navigation.back.bezelStyle == .texturedRounded)
        #expect(navigation.forward.bezelStyle == .texturedRounded)
        #expect(navigation.back.accessibilityIdentifier() == "settings-history-back")
        #expect(navigation.forward.accessibilityIdentifier() == "settings-history-forward")
        #expect(!fixture.window.isVisible)
    }

    @Test
    func nativeHistoryButtonsRestoreSearchAnchorsAndVoicePagesAndSkipDisabledFeatures() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        await fixture.layout()
        let buttons = try fixture.navigationButtons()
        fixture.input.settingsQuery = "PDF"
        #expect(!buttons.back.isEnabled && !buttons.forward.isEnabled)
        buttons.back.performClick(nil)
        #expect(fixture.input.settingsQuery == "PDF")

        fixture.input.select(.voice, searchTarget: .group("本地模型"))
        fixture.input.voicePage = .history
        fixture.input.select(.features)
        await fixture.layout()
        #expect(buttons.back.isEnabled && !buttons.forward.isEnabled)
        buttons.back.performClick(nil)
        await fixture.layout()
        #expect(fixture.input.selection == .voice)
        #expect(fixture.input.voicePage == .history)
        #expect(fixture.input.searchTarget == nil)
        #expect(buttons.forward.isEnabled)
        buttons.back.performClick(nil)
        await fixture.layout()
        #expect(fixture.input.voicePage == .settings)
        #expect(fixture.input.searchTarget == .group("本地模型"))

        fixture.state.settings.voiceInputEnabled = false
        await fixture.layout()
        buttons.back.performClick(nil)
        await fixture.layout()
        #expect(fixture.input.selection == .general)
        #expect(!buttons.back.isEnabled && buttons.forward.isEnabled)
        buttons.forward.performClick(nil)
        await fixture.layout()
        #expect(fixture.input.selection == .features)
        #expect(!buttons.forward.isEnabled)
    }

    @Test
    func nativeCollapseExpandsDetailAndPreservesSharedInputs() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.input.select(.voice)
        fixture.input.voicePage = .history
        fixture.input.settingsQuery = "语音"
        fixture.input.weatherQuery = "上海"
        await fixture.layout()
        let split = try fixture.controller()
        let sidebar = split.splitViewItems[0]
        let originalSidebarWidth = sidebar.viewController.view.frame.width
        #expect(abs(originalSidebarWidth - 250) < 1)
        let originalDetailWidth = split.splitViewItems[1].viewController.view.frame.width
        let originalWindowFrame = fixture.window.frame
        let toggle = try #require(fixture.window.toolbar?.items.first {
            $0.itemIdentifier == SettingsSplitViewController.sidebarIdentifier
        })
        #expect(toggle.target as? NSSplitViewController === split)
        let action = try #require(toggle.action)
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                #expect(NSApp.sendAction(action, to: toggle.target, from: toggle))
            } completionHandler: {
                continuation.resume()
            }
        }
        await fixture.layout()
        #expect(!fixture.input.isSidebarVisible)
        #expect(split.splitViewItems[1].viewController.view.frame.width > originalDetailWidth + 200)
        #expect(fixture.window.frame == originalWindowFrame)
        #expect(fixture.input.selection == .voice && fixture.input.voicePage == .history)
        #expect(fixture.input.settingsQuery == "语音" && fixture.input.weatherQuery == "上海")

        fixture.input.isSidebarVisible = true
        await fixture.layout()
        #expect(!sidebar.isCollapsed)
        #expect(abs(sidebar.viewController.view.frame.width - originalSidebarWidth) < 1)
        #expect(fixture.input.settingsQuery == "语音")
        let buttons = try fixture.navigationButtons()
        buttons.back.performClick(nil)
        await fixture.layout()
        #expect(fixture.input.voicePage == .settings)
        #expect(fixture.input.weatherQuery == "上海")
    }

    @Test
    func toolbarAndBothHostingPanesRefreshAllLanguageAndAccessibilityEnvironments() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            fixture.state.language = language
            await fixture.layout()
            let toolbar = try #require(fixture.window.toolbar)
            let toggle = try #require(toolbar.items.first {
                $0.itemIdentifier == SettingsSplitViewController.sidebarIdentifier
            })
            let buttons = try fixture.navigationButtons()
            let table = try #require(NSDictionary(contentsOf: Self.packageRoot.appendingPathComponent(
                "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
            )) as? [String: String])
            for key in ["隐藏侧边栏", "显示侧边栏", "后退", "前进", "设置", "zisla 设置"] {
                #expect(!(try #require(table[key])).isEmpty, "Missing toolbar translation: \(language.rawValue)/\(key)")
            }
            #expect(toggle.label == table["隐藏侧边栏"])
            #expect(toggle.toolTip == table["隐藏侧边栏"])
            #expect(buttons.back.toolTip == table["后退"])
            #expect(buttons.back.accessibilityLabel() == table["后退"])
            #expect(buttons.forward.accessibilityLabel() == table["前进"])
            #expect(fixture.window.title == table["zisla 设置"])
            let split = try fixture.controller()
            let probe = try #require(fixture.descendants(in: split.splitViewItems[1].viewController.view)
                .compactMap { $0 as? EnvironmentProbe }.first)
            #expect(probe.locale == language.locale)
            #expect(probe.direction == (language.isRightToLeft ? .rightToLeft : .leftToRight))
            #expect(probe.colorScheme == .dark && probe.isEnabled == false)
            #expect(probe.reduceMotion == NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            let field = try #require(fixture.descendants(in: split.splitViewItems[0].viewController.view)
                .compactMap { $0 as? NSTextField }.first)
            #expect(field.placeholderString == AppLocalization.string("搜索设置", language: language))
            split.splitViewItems[0].isCollapsed = true
            await fixture.layout()
            #expect(toggle.label == table["显示侧边栏"])
            fixture.input.isSidebarVisible = true
        }
    }

    @Test
    func productionSidebarShowsOverflowScrollerWithoutOverlappingRowsAndHidesItWhenContentFits() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        await fixture.layout()
        let split = try fixture.controller()
        let sidebarHost = split.splitViewItems[0].viewController.view
        let scroll = try #require(fixture.descendants(in: sidebarHost).compactMap { $0 as? NSScrollView }.first)
        let scroller = try #require(scroll.verticalScroller as? ThinScroller)
        #expect(scroll.scrollerStyle == .legacy && !scroller.isHidden)
        #expect(scroller.knobProportion > 0 && scroller.knobProportion < 1)
        let track = scroller.convert(scroller.bounds, to: sidebarHost)
        let bitmap = try #require(sidebarHost.bitmapImageRepForCachingDisplay(in: sidebarHost.bounds))
        sidebarHost.cacheDisplay(in: sidebarHost.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / sidebarHost.bounds.width
        var selectedRowColumns = Set<Int>()
        var selectedRowPixels = Set<Int>()
        for y in 0..<bitmap.pixelsHigh {
            var blueColumns = [Int]()
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.blueComponent > 0.6,
                   color.blueComponent > color.redComponent + 0.2,
                   color.blueComponent > color.greenComponent + 0.15 {
                    blueColumns.append(x)
                }
            }
            if let first = blueColumns.first, let last = blueColumns.last,
               CGFloat(last - first) > sidebarHost.bounds.width * scale / 2 {
                selectedRowColumns.formUnion(blueColumns)
                selectedRowPixels.insert(y)
            }
        }
        let rowRightEdge = CGFloat(try #require(selectedRowColumns.max()) + 1) / scale
        #expect(CGFloat(selectedRowPixels.count) / scale >= 24, "The real selected row must render a visible background")
        #expect(track.minX - rowRightEdge >= 5, "The selected row must leave a visible gap before the scrollbar track")

        fixture.state.settings.keyboardEnabled = false
        fixture.state.settings.clipboardAssistantEnabled = false
        fixture.state.settings.screenshotEnabled = false
        fixture.state.settings.pdfToolsEnabled = false
        fixture.state.settings.mediaEnabled = false
        fixture.state.settings.systemMonitorEnabled = false
        fixture.state.settings.lockScreenInfoEnabled = false
        fixture.state.settings.sideNoticesEnabled = false
        fixture.state.settings.mailEnabled = false
        fixture.state.settings.aiProgressEnabled = false
        fixture.state.settings.voiceInputEnabled = false
        fixture.state.settings.petEnabled = false
        fixture.state.settings.downloaderEnabled = false
        fixture.state.settings.weatherEnabled = false
        fixture.state.settings.updateChecksEnabled = false
        fixture.state.settings.recommendedToolsEnabled = false
        fixture.state.height = 680
        await fixture.layout()
        #expect(scroller.isHidden, "A short sidebar must not keep an empty scroll track")
        #expect(!fixture.window.isVisible)
    }

    @Test
    func reparentingAndRemovingTheSplitReleasesOwnedToolbarWithoutClearingAnotherToolbar() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        await fixture.layout()
        weak var split = try fixture.controller()
        let firstWindow = fixture.window
        let oldToolbar = try #require(firstWindow.toolbar)
        firstWindow.contentViewController = nil
        #expect(firstWindow.toolbar == nil)
        let nextWindow = Fixture.makeWindow()
        nextWindow.contentViewController = fixture.host
        nextWindow.setContentSize(NSSize(width: 960, height: fixture.state.height))
        fixture.window = nextWindow
        defer { firstWindow.close() }
        await fixture.layout()
        #expect(nextWindow.toolbar === oldToolbar)
        #expect(try fixture.controller() === split)

        let replacement = NSToolbar(identifier: "external-test-toolbar")
        nextWindow.toolbar = replacement
        fixture.host.rootView = AnyView(EmptyView())
        await fixture.layout()
        #expect(nextWindow.toolbar === replacement, "Removing settings must not erase another owner's toolbar")
        #expect(split == nil, "The split controller and tracking separator must not form a retain cycle")
        #expect(!firstWindow.isVisible && !nextWindow.isVisible)
    }

    @MainActor
    private final class State: ObservableObject {
        @Published var settings = FeatureSettings.default
        @Published var language = AppLanguage.english
        @Published var height: CGFloat = 400

        init() {
            settings.voiceInputEnabled = true
        }
    }

    private struct Page: View {
        @ObservedObject var input: SettingsInput
        @ObservedObject var state: State
        @FocusState private var searchFocused: Bool

        var body: some View {
            SettingsSplitView(input: input, settings: state.settings, onNavigate: {
                input.navigate(backward: $0, settings: state.settings)
            }) {
                SettingsSidebar(
                    input: input, settings: state.settings, appVersion: "1.0",
                    settingsSearchFieldFocused: $searchFocused,
                    onSelect: { input.select($0) }, onSubmitSearch: {}
                )
            } detail: {
                EnvironmentProbeView()
            }
            .frame(width: 960, height: state.height)
            .environment(\.locale, state.language.locale)
            .environment(\.layoutDirection, state.language.isRightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.colorScheme, .dark)
            .environment(\.isEnabled, false)
        }
    }

    @MainActor
    private final class Fixture {
        let input = SettingsInput()
        let state = State()
        let host: NSHostingController<AnyView>
        var window: NSWindow

        init() {
            _ = NSApplication.shared
            host = NSHostingController(rootView: AnyView(Page(input: input, state: state)))
            window = Self.makeWindow()
            window.contentViewController = host
            window.setContentSize(NSSize(width: 960, height: state.height))
        }

        static func makeWindow() -> NSWindow {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 400),
                styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            return window
        }

        func close() {
            window.contentViewController = nil
            window.close()
        }

        func layout() async {
            for _ in 0..<20 {
                host.view.layoutSubtreeIfNeeded()
                host.view.displayIfNeeded()
                for scroll in descendants(in: host.view).compactMap({ $0 as? NSScrollView }) {
                    scroll.tile()
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }

        func descendants(in view: NSView) -> [NSView] {
            var result = [view]
            var index = 0
            while index < result.count {
                result.append(contentsOf: result[index].subviews)
                index += 1
            }
            return result
        }

        func controller() throws -> SettingsSplitViewController {
            let controllers = descendants(in: host.view).compactMap {
                ($0 as? NSSplitView)?.delegate as? SettingsSplitViewController
            }
            return try #require(controllers.first)
        }

        func navigationButtons() throws -> (back: NSButton, forward: NSButton) {
            let group = try #require(window.toolbar?.items.compactMap { $0 as? NSToolbarItemGroup }.first)
            return (try #require(group.subitems.first?.view as? NSButton),
                    try #require(group.subitems.last?.view as? NSButton))
        }
    }

    private final class EnvironmentProbe: NSView {
        var locale = Locale(identifier: "")
        var direction = LayoutDirection.leftToRight
        var colorScheme = ColorScheme.light
        var isEnabled = true
        var reduceMotion = false
    }

    private struct EnvironmentProbeView: NSViewRepresentable {
        func makeNSView(context: Context) -> EnvironmentProbe { EnvironmentProbe() }

        func updateNSView(_ nsView: EnvironmentProbe, context: Context) {
            nsView.locale = context.environment.locale
            nsView.direction = context.environment.layoutDirection
            nsView.colorScheme = context.environment.colorScheme
            nsView.isEnabled = context.environment.isEnabled
            nsView.reduceMotion = context.environment.accessibilityReduceMotion
        }
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
