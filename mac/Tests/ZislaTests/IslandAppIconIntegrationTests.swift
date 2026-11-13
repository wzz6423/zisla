import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct IslandAppIconIntegrationTests {
    @Test
    func informationPageLogoControlUsesTheSavedSettingAndAllLanguages() throws {
        let source = try String(contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"),
            encoding: .utf8)
        let start = try #require(source.range(of: "    private var infoContent: some View {"))
        let end = try #require(source.range(of: "    private var dailyBriefingContent:", range: start.upperBound..<source.endIndex))
        let section = String(source[start.lowerBound..<end.lowerBound])
        let call = try NSRegularExpression(
            pattern: #"featureToggle\("([^"]+)"[^\n]*keyPath: \\\.islandAppIconEnabled\)"#
        )
        let match = try #require(call.firstMatch(in: section, range: NSRange(section.startIndex..., in: section)),
            "The information page must bind the logo switch to its own persisted preference")
        let range = try #require(Range(match.range(at: 1), in: section))
        let key = String(section[range])
        #expect(key == "显示应用标识")
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let url = Self.packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            let value = try #require(table[key], "\(language.rawValue) missing the logo setting")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            if language != .simplifiedChinese { #expect(value != key) }
            if language != .english { #expect(value != "Show App Logo") }
        }
        #expect(AppLocalization.string(key, locale: Locale(identifier: "en")) == "Show App Logo")
        #expect(AppLocalization.string(key, locale: Locale(identifier: "ar")) == "عرض شعار التطبيق")
        let applicationSource = try String(contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/ZislaApp.swift"),
            encoding: .utf8)
        let routingCall = try NSRegularExpression(pattern:
            #"IslandStatusIconRouting\.update\([\s\S]*?islandAppIconEnabled:\s*settings\.islandAppIconEnabled\)"#)
        #expect(routingCall.firstMatch(in: applicationSource,
            range: NSRange(applicationSource.startIndex..., in: applicationSource)) != nil,
            "Changing the saved preference must feed the production icon routing call")
    }

    @Test(arguments: AppLanguage.allCases)
    func logoControlRemainsSearchableWhenOtherInformationFeaturesAreOff(language: AppLanguage) {
        var settings = FeatureSettings(mediaEnabled: false, systemMonitorEnabled: false, lockScreenInfoEnabled: false,
            sideNoticesEnabled: false, userCareEnabled: false, islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom))
        settings.dailyBriefing.enabled = false
        for showsLogo in [false, true] {
            settings.islandAppIconEnabled = showsLogo
            #expect(SettingsSection.info.isVisible(settings: settings))
            let matches = SettingsSearchIndex.results(for: AppLocalization.string("显示应用标识", locale: language.locale),
                settings: settings, locale: language.locale)
            #expect(matches.first?.section == .info)
            #expect(matches.first?.anchor == .row("显示应用标识"))
        }
        settings.islandPlacement.mode = .camera
        #expect(!SettingsSearchIndex.items(settings: settings).contains { $0.title == "显示应用标识" })
        settings.islandPlacement.mode = .custom
        settings.islandLayoutStyle = .notch
        #expect(!SettingsSearchIndex.items(settings: settings).contains { $0.title == "显示应用标识" })
    }

    @Test(arguments: SystemMonitorMenuBarDisplayStyle.allCases) @MainActor
    func hidingTheLogoPreservesMonitoringAndTheSystemMenuBarEntry(style: SystemMonitorMenuBarDisplayStyle) throws {
        let application = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let combined = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let metric = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let stacked = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let items = [application, combined, metric, stacked]
        items.forEach { $0.isVisible = false }
        defer { items.forEach { NSStatusBar.system.removeStatusItem($0) } }
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings", action: nil, keyEquivalent: ",")
        application.menu = menu
        metric.button?.target = application
        metric.button?.action = #selector(NSObject.description)
        let image = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        combined.button?.image = image
        let readings = [IslandStatusIcon.Reading(metric: .cpu, text: "93%"),
                        IslandStatusIcon.Reading(metric: .gpu, text: "22%")]
        let title = style == .detailed ? "\(SystemMonitorMenuBarPresentation.label(for: .cpu)) 93%" : "93%"
        let metrics = [(SystemMonitorMenuBarMetric.cpu, metric, title)]
        let visible = IslandStatusIconRouting.update(destination: .island, application: application,
            metrics: metrics, stacked: stacked, readings: readings, combined: combined, style: style,
            islandAppIconEnabled: true)
        let hidden = IslandStatusIconRouting.update(destination: .island, application: application,
            metrics: metrics, stacked: stacked, readings: readings, combined: combined, style: style,
            islandAppIconEnabled: false)
        #expect(visible.map(\.id) == ["status-icon-application"] + hidden.map(\.id))
        #expect(hidden.map(\.id) == ["status-icon-combined", "status-icon-cpu", "status-icon-stacked"])
        #expect(hidden.allSatisfy { $0.isSystemMonitor })
        #expect(items.allSatisfy { !$0.isVisible })
        if case let .metric(_, text, _, routedStyle) = hidden[1].content {
            #expect(text == "93%" && routedStyle == style)
        } else { Issue.record("The CPU reading must retain its own content") }
        if case let .stacked(_, routedReadings) = hidden[2].content {
            #expect(routedReadings.map(\.text) == ["93%", "22%"])
        } else { Issue.record("The merged monitor must retain both readings") }
        #expect(IslandStatusIconRouting.update(destination: .menuBar, application: application, metrics: metrics,
            stacked: stacked, readings: readings, combined: combined, style: style,
            islandAppIconEnabled: false).isEmpty)
        #expect(items.allSatisfy { $0.isVisible })
        #expect(application.menu === menu)
        #expect(metric.button?.target === application && metric.button?.action == #selector(NSObject.description))
        #expect(IslandStatusIconRouting.update(destination: .island, application: nil, metrics: [],
            stacked: nil, readings: [], combined: nil, style: style, islandAppIconEnabled: false).isEmpty)
    }

    @Test(arguments: [false, true], [false, true]) @MainActor
    func islandLogoIsIndependentOfTheSystemMenuBarIconWithAndWithoutMonitoring(
        showsMenuBarIcon: Bool, showsIslandLogo: Bool
    ) throws {
        let application = showsMenuBarIcon ? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) : nil
        let monitor = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let items = [application, monitor].compactMap { $0 }
        items.forEach { $0.isVisible = false }
        defer { items.forEach { NSStatusBar.system.removeStatusItem($0) } }
        let settings = FeatureSettings(menuBarAppIconEnabled: showsMenuBarIcon, islandAppIconEnabled: showsIslandLogo,
            islandLayoutStyle: .pill, islandPlacement: IslandPlacement(mode: .custom))
        for hasMonitor in [false, true] {
            monitor.isVisible = false
            let icons = IslandStatusIconRouting.update(destination: settings.effectiveStatusIconDestination,
                application: application, metrics: [], stacked: nil, readings: [],
                combined: hasMonitor ? monitor : nil, style: .compact, islandAppIconEnabled: settings.islandAppIconEnabled)
            #expect(icons.map(\.id) == (showsIslandLogo ? ["status-icon-application"] : [])
                + (hasMonitor ? ["status-icon-combined"] : []))
            #expect(items.allSatisfy { !$0.isVisible })
            #expect(settings.menuBarAppIconEnabled == showsMenuBarIcon)
            #expect(settings.islandAppIconEnabled == showsIslandLogo)
            #expect(IslandStatusIconRouting.update(destination: .menuBar, application: application,
                metrics: [], stacked: nil, readings: [], combined: hasMonitor ? monitor : nil,
                style: .compact, islandAppIconEnabled: settings.islandAppIconEnabled).isEmpty)
            #expect((application?.isVisible ?? false) == showsMenuBarIcon)
            #expect(monitor.isVisible == hasMonitor)
        }
    }

    @Test(arguments: IslandEdge.allCases, [LayoutDirection.leftToRight, .rightToLeft]) @MainActor
    func logoOptOutRemovesItsPixelsAndReservedSlotWhilePreservingTheMonitor(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let application = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let monitor = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        application.isVisible = false
        monitor.isVisible = false
        defer {
            NSStatusBar.system.removeStatusItem(application)
            NSStatusBar.system.removeStatusItem(monitor)
        }
        monitor.button?.image = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let date = Date(timeIntervalSince1970: 100)
        var frames: [Bool: NSBitmapImageRep] = [:]
        var dimensions: [Bool: CGSize] = [:]
        for showsLogo in [false, true] {
            let settings = FeatureSettings(islandAppIconEnabled: showsLogo, islandLayoutStyle: .pill,
                islandPlacement: IslandPlacement(mode: .custom, edge: edge))
            let icons = IslandStatusIconRouting.update(destination: settings.effectiveStatusIconDestination,
                application: application, metrics: [], stacked: nil, readings: [], combined: monitor,
                style: .compact, islandAppIconEnabled: settings.islandAppIconEnabled)
            let layout = try #require(FloatingIslandInformationLayout(notices: [], icons: icons,
                settings: settings, item: nil, at: date))
            #expect(layout.icons.map(\.id) == (showsLogo
                ? ["status-icon-application", "status-icon-combined"] : ["status-icon-combined"]))
            frames[showsLogo] = try await StatusIconDestinationIntegrationTests().renderOffscreen(FloatingIslandInformationView(layout: layout,
                visualizationStyle: .waveform, item: nil, date: date)
                .environment(\.layoutDirection, direction), size: layout.size)
            dimensions[showsLogo] = layout.size
        }
        let shown = try #require(frames[true])
        let hidden = try #require(frames[false])
        let shownSize = try #require(dimensions[true])
        let hiddenSize = try #require(dimensions[false])
        let logoSize = IslandStatusIcon(id: "logo", content: .application, tooltip: "zisla").size(edge: edge)
        let removedLength = (edge.isVertical ? logoSize.height : logoSize.width) + 8
        #expect((edge.isVertical ? shownSize.height - hiddenSize.height : shownSize.width - hiddenSize.width) == removedLength)
        let shownPixels = try pixelCounts(shown)
        let hiddenPixels = try pixelCounts(hidden)
        #expect(shownPixels.white > 5, "The enabled application mark must contribute visible pixels")
        #expect(hiddenPixels.white == 0, "Opting out must remove the application mark")
        #expect(shownPixels.red > 100 && hiddenPixels.red > 100, "Monitoring must remain visible with either logo choice")
    }

    @Test(arguments: IslandEdge.allCases, [false, true]) @MainActor
    func idleAndHiddenActivitiesHonorTheLogoChoiceWithoutRunningTheParticleClock(
        edge: IslandEdge, hidesActivity: Bool
    ) throws {
        let fixture = try StatusIconDestinationIntegrationTests.IconFixture(edge: edge)
        defer {
            fixture.media.stop()
            fixture.downloads.stop()
            fixture.close()
        }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.collapsedProgressGlowEnabled = false
        let state = SideNoticeDisplayState()
        state.islandEdge = edge
        state.placementMode = .custom
        state.compactWingHeight = 24
        state.compactStatusHidden = hidesActivity
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        if hidesActivity {
            fixture.queue.enqueue(IslandNotice(id: "toolbox-reminder-logo-setting", title: "Reminder"), expiresAfter: nil)
        }
        let date = Date(timeIntervalSince1970: 100)
        let size = edge.isVertical ? CGSize(width: 24, height: 80) : CGSize(width: 80, height: 24)
        let enabled = try pixels(view.statusBarContent(at: date)
            .frame(width: size.width, height: size.height))
        #expect(enabled.contains { $0 > 0 })
        #expect(!view.pausesCompactTimeline)
        fixture.settings.settings.islandAppIconEnabled = false
        let disabled = try pixels(view.statusBarContent(at: date)
            .frame(width: size.width, height: size.height))
        #expect(disabled.allSatisfy { $0 == 0 }, "Opting out must also hide the idle fallback mark")
        #expect(view.pausesCompactTimeline, "A hidden mark must stop its idle animation clock")
        fixture.settings.settings.islandAppIconEnabled = true
        #expect(try pixels(view.statusBarContent(at: date)
            .frame(width: size.width, height: size.height)) == enabled)
    }

    @MainActor
    private func pixelCounts(_ bitmap: NSBitmapImageRep) throws -> (red: Int, white: Int) {
        var red = 0
        var white = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.redComponent > 0.8 && color.greenComponent < 0.2 && color.blueComponent < 0.2 { red += 1 }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.03 { white += 1 }
            }
        }
        return (red, white)
    }

    @MainActor
    private func pixels<V: View>(_ view: V) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view.background(.black))
        renderer.scale = 2
        renderer.colorMode = .linear
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return try (0..<bitmap.pixelsHigh).flatMap { y in
            try (0..<bitmap.pixelsWide).map { x in
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                return UInt8((color.redComponent * 255).rounded())
            }
        }
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
