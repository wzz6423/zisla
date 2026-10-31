import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

struct StatusIconDestinationIntegrationTests {
    @Test @MainActor
    func globalBindingPersistsWithoutChangingTheIndividualFeatureSelections() throws {
        let suite = "StatusIconDestinationIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
        defer {
            store.flushPendingChanges()
            defaults.removePersistentDomain(forName: suite)
        }
        store.settings.systemMonitorMenuBarMetrics = [.gpu, .fan]
        store.settings.systemMonitorMenuBarLayout = .both
        store.settings.systemMonitorMenuBarTopRow = [.network]
        store.settings.systemMonitorMenuBarBottomRow = [.cpu, .memory]
        store.settings.systemMonitorMenuBarCombinedIconEnabled = true
        store.settings.menuBarAppIconEnabled = true
        let original = store.settings
        let binding = Binding(get: { store.settings }, set: { store.settings = $0 })
        for destination in StatusIconDestination.allCases {
            binding.statusIconDestination.wrappedValue = destination
            store.flushPendingChanges()
            let reloaded = FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .release)
            #expect(reloaded.settings == store.settings)
            var expected = original
            expected.statusIconDestination = destination
            #expect(reloaded.settings == expected)
        }
    }

    @Test @MainActor
    func aDamagedDestinationDoesNotResetTheStoreAndTheNextWriteRepairsOnlyThatField() throws {
        let suite = "StatusIconDestinationRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var original = FeatureSettings.default
        original.mediaEnabled = false
        original.systemMonitorEnabled = false
        original.menuBarAppIconEnabled = false
        original.sideNoticesEnabled = false
        original.systemMonitorMenuBarMetrics = [.gpu, .fan]
        original.systemMonitorMenuBarLayout = .none
        original.systemMonitorMenuBarCombinedIconAppearance.iconSize = 36
        let invalidValues: [Any] = ["future-destination", true, 5, [String](), [String: String]()]
        for value in invalidValues {
            var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            payload["statusIconDestination"] = value
            defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: "feature-settings-v1")
            let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
            #expect(store.settings == original)
            store.settings.statusIconDestination = .island
            store.flushPendingChanges()
            var expected = original
            expected.statusIconDestination = .island
            #expect(FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .release).settings == expected)
        }
    }

    @Test
    func allDestinationLabelsAreUniqueAndTranslatedInEveryLanguage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        #expect(source.components(separatedBy: "status-icon-destination-selection").count == 2)
        #expect(source.contains("settingsStore.settings.effectiveStatusIconDestination"))
        let keys = ["图标显示位置", "常驻监控图标", "关闭后不影响已启用的监控图标"]
            + StatusIconDestination.allCases.map(\.menuTitle)
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let url = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let source = try String(contentsOf: url, encoding: .utf8)
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue) missing \(key)")
                #expect(!value.isEmpty)
                let expression = try NSRegularExpression(pattern: "^\\s*\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*=", options: .anchorsMatchLines)
                #expect(expression.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)) == 1)
                #expect(AppLocalization.string(key, locale: language.locale) == value)
            }
        }
        #expect(AppLocalization.string("状态栏", locale: Locale(identifier: "en")) == "Menu Bar")
        #expect(AppLocalization.string("灵动岛", locale: Locale(identifier: "ar")) == "الجزيرة الديناميكية")
    }

    @Test
    func iconDestinationAndExistingMonitorSearchesReachTheirVisibleRows() {
        let settings = FeatureSettings.default
        let locale = Locale(identifier: "zh-Hans")
        #expect(SettingsSearchIndex.results(for: "图标显示位置", settings: settings, locale: locale).contains {
            $0.section == .features && $0.anchor == .row("图标显示位置")
        })
        for query in ["常驻监控图标", "菜单栏常驻"] {
            #expect(SettingsSearchIndex.results(for: query, settings: settings, locale: locale).contains {
                $0.section == .info && $0.anchor == .row("常驻监控图标")
            })
        }
    }

    @Test @MainActor
    func routingMovesEveryEnabledIconAndPreservesTheirMenuAndReadings() throws {
        let application = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let stacked = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let combined = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let metrics = SystemMonitorMenuBarMetric.allCases.map { metric in
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = "\(SystemMonitorMenuBarPresentation.label(for: metric)) --"
            return (metric, item, "--")
        }
        let items = [application, stacked, combined] + metrics.map { $0.1 }
        items.forEach { $0.isVisible = false }
        defer { items.forEach { NSStatusBar.system.removeStatusItem($0) } }
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings", action: nil, keyEquivalent: "")
        application.menu = menu
        for item in [stacked, combined] + metrics.map({ $0.1 }) {
            item.button?.target = application
            item.button?.action = #selector(NSObject.description)
        }
        let readings = [IslandStatusIcon.Reading(metric: .cpu, text: "20%"),
                        IslandStatusIcon.Reading(metric: .memory, text: "2 GB/8 GB")]
        stacked.button?.image = SystemMonitorMenuBarImageRenderer.stacked(rows: ["C 20%", "M 2 GB/8 GB"], style: .compact)
        combined.button?.image = SystemMonitorMenuBarImageRenderer.combinedIcon(battery: nil, wifi: .off, level: nil,
            foreground: .white, configuration: SystemMonitorCombinedIconAppearance(iconSize: 36))
        for style in SystemMonitorMenuBarDisplayStyle.allCases {
            let titles = metrics.map { metric, item, compact in
                (metric, item, style == .detailed ? "\(SystemMonitorMenuBarPresentation.label(for: metric)) \(compact)" : compact)
            }
            let icons = IslandStatusIconRouting.update(destination: .island, application: application,
                metrics: titles, stacked: stacked, readings: readings, combined: combined, style: style)
            #expect(items.allSatisfy { !$0.isVisible })
            #expect(icons.map(\.id) == ["status-icon-combined", "status-icon-application"]
                + SystemMonitorMenuBarMetric.allCases.map { "status-icon-\($0.rawValue)" }
                + ["status-icon-stacked"])
            for icon in icons {
                if case let .metric(_, text, _, _) = icon.content { #expect(text == "--") }
            }
            #expect(icons.first?.size(edge: .left) == CGSize(width: 36, height: 36))
            let stackedIcon = try #require(icons.first { $0.id == "status-icon-stacked" })
            let expectedStackedHeight = readings.reduce(CGFloat(8)) { $0 + IslandStatusIcon.readingSize($1.text).height }
            #expect(stackedIcon.size(edge: .left) == CGSize(width: 32, height: expectedStackedHeight))
            let withoutCombined = IslandStatusIconRouting.update(destination: .island, application: application,
                metrics: titles, stacked: stacked, readings: readings, combined: nil, style: style)
            #expect(withoutCombined.map(\.id) == ["status-icon-application"]
                + SystemMonitorMenuBarMetric.allCases.map { "status-icon-\($0.rawValue)" }
                + ["status-icon-stacked"])
            #expect(application.menu === menu)
            #expect(IslandStatusIconRouting.update(destination: .menuBar, application: application,
                metrics: metrics, stacked: stacked, readings: readings, combined: combined, style: style).isEmpty)
            #expect(items.allSatisfy { $0.isVisible })
            #expect(application.menu === menu)
            #expect(([stacked, combined] + metrics.map({ $0.1 })).allSatisfy {
                $0.button?.target === application && $0.button?.action == #selector(NSObject.description)
            })
        }
        #expect(IslandStatusIconRouting.update(destination: .island, application: nil, metrics: [],
            stacked: nil, readings: [], combined: nil, style: .compact).isEmpty)
    }

    @Test @MainActor
    func detailedNetworkIconsRetainBothTransferRatesAndCompactIconsKeepTheirOriginalReading() throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { NSStatusBar.system.removeStatusItem(item) }
        item.button?.title = "Network ↓12 MB/s ↑7 MB/s"
        for style in SystemMonitorMenuBarDisplayStyle.allCases {
            let title = style == .detailed ? "Network ↓12 MB/s ↑7 MB/s" : "↓12 MB/s"
            let icons = IslandStatusIconRouting.update(destination: .island, application: nil,
                metrics: [(.network, item, title)], stacked: nil, readings: [], combined: nil, style: style)
            guard case let .metric(metric, text, _, selectedStyle) = try #require(icons.first).content else {
                Issue.record("The selected network metric must remain an individual icon")
                return
            }
            #expect(metric == .network && selectedStyle == style)
            #expect(text == (style == .detailed ? "↓12 MB/s ↑7 MB/s" : "↓12 MB/s"))
        }
    }

    @Test @MainActor
    func islandTooltipsKeepReadingsWithoutOfferingMenuBarClickActions() throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { NSStatusBar.system.removeStatusItem(item) }
        item.button?.title = "CPU 20%"
        let action = AppLocalization.text("点击打开系统监控")
        let tooltip = "CPU: 20%\n\(action)"
        item.button?.toolTip = tooltip
        let icons = IslandStatusIconRouting.update(destination: .island, application: nil,
            metrics: [(.cpu, item, "20%")], stacked: item, readings: [], combined: item, style: .detailed)
        #expect(icons.count == 3)
        #expect(icons.allSatisfy { $0.tooltip == "CPU: 20%" })
        #expect(item.button?.toolTip == tooltip, "Moving an icon must preserve its original menu bar behavior")
    }

    @Test @MainActor
    func theIslandLogoKeepsAnimatingWhileMonitorOnlyStripsPauseTheirTimeline() throws {
        let fixture = try IconFixture(edge: .left)
        defer { fixture.close() }
        let state = SideNoticeDisplayState()
        state.placementMode = .custom
        state.islandEdge = .left
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            onStatusHidden: {})
        state.statusIcons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        #expect(view.pausesCompactTimeline)
        state.statusIcons.append(IslandStatusIcon(id: "app", content: .application, tooltip: "zisla"))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(!view.pausesCompactTimeline, "The application logo must continue to use its existing animation clock")
        }
        state.statusIcons.removeAll()
        state.placementMode = .camera
        #expect(view.pausesCompactTimeline)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func iconImagesAndVerticalReadingsRenderInsideTheMeasuredStrip(edge: IslandEdge) async throws {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 72, height: 72, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 72, height: 72))
        let image = NSImage(cgImage: try #require(context.makeImage()), size: NSSize(width: 36, height: 36))
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU"),
                     IslandStatusIcon(id: "combined", content: .combined(image), tooltip: "Monitor")]
        let size = try #require(IslandStatusIconLayout.size(icons: icons, edge: edge))
        let bitmap = try await renderOffscreen(IslandStatusIconStrip(icons: icons, edge: edge, date: .distantPast), size: size)
        var redPixels = 0
        var textPixels = 0
        var redBounds = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                if color.redComponent > 0.5 && color.greenComponent < 0.2 {
                    redPixels += 1
                    redBounds = redBounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 { textPixels += 1 }
            }
        }
        let pixelsPerPoint = CGFloat(bitmap.pixelsWide * bitmap.pixelsHigh) / (size.width * size.height)
        #expect(CGFloat(redPixels) / pixelsPerPoint > 1000, "The original-color combined icon must render at its configured 36pt size")
        #expect(CGFloat(textPixels) / pixelsPerPoint > 5, "The CPU reading must remain visible next to or below its symbol")
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        let endInset = edge.isVertical ? CGFloat(bitmap.pixelsHigh) - redBounds.maxY
            : CGFloat(bitmap.pixelsWide) - redBounds.maxX
        let crossInset = edge.isVertical ? min(redBounds.minX, CGFloat(bitmap.pixelsWide) - redBounds.maxX)
            : min(redBounds.minY, CGFloat(bitmap.pixelsHigh) - redBounds.maxY)
        #expect(endInset / scale >= 7.5, "The last icon must leave eight points at the end of the strip")
        #expect(crossInset / scale >= 3.5, "The widest icon must leave four points on both cross-axis sides")
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func missingMonitorImagesKeepTheirReadingsOrPlaceholderVisible(edge: IslandEdge) async throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { NSStatusBar.system.removeStatusItem(item) }
        item.button?.image = nil
        item.button?.toolTip = nil
        let readings = [IslandStatusIcon.Reading(metric: .cpu, text: "20%")]
        let icons = IslandStatusIconRouting.update(destination: .island, application: nil,
            metrics: [(.cpu, item, "20%")], stacked: item, readings: readings, combined: item, style: .compact)
        #expect(icons.map(\.tooltip) == ["zisla", "20%", "20%"])
        for icon in icons {
            let size = try #require(IslandStatusIconLayout.size(icons: [icon], edge: edge))
            #expect(size.width >= 24 && size.height >= 24)
            if case .combined = icon.content { #expect(size == (edge.isVertical ? CGSize(width: 32, height: 40) : CGSize(width: 40, height: 32))) }
            let bitmap = try await renderOffscreen(IslandStatusIconStrip(icons: [icon], edge: edge, date: .distantPast), size: size)
            var foregroundPixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color = try #require(bitmap.colorAt(x: x, y: y))
                    if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 { foregroundPixels += 1 }
                }
            }
            #expect(foregroundPixels > 5, "\(icon.id) must stay visible if AppKit cannot supply its image")
        }
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func theCompactPanelPublishesIconsAndRestoresThemAfterAnActivity(edge: IslandEdge) async throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        let application = NSApplication.shared
        let existingWindows = Set(application.windows.map(ObjectIdentifier.init))
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        fixture.presenter.setStatusIcons(icons)
        fixture.presenter.setScreenLocked(false)
        let host = try #require(application.windows.filter { !existingWindows.contains(ObjectIdentifier($0)) }
            .compactMap { $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>> }.first)
        let state = host.rootView.content.displayState
        #expect(state.statusIcons.map(\.id) == ["cpu"])
        #expect(state.islandEdge == edge)
        let size = try #require(IslandStatusIconLayout.size(icons: icons, edge: edge))
        #expect(host.window?.frame.size == size)
        #expect(host.window?.ignoresMouseEvents == true, "Persistent icons must not activate the app or open a module")
        let actual = try await renderOffscreen(host.rootView.content.statusBarContent(at: .distantPast), size: size)
        let expected = try await renderOffscreen(IslandStatusIconStrip(icons: icons, edge: edge, date: .distantPast)
            .clipShape(CompactIslandShape(layoutStyle: .pill)), size: size)
        var changed = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = try #require(actual.colorAt(x: x, y: y))
                let b = try #require(expected.colorAt(x: x, y: y))
                if abs(a.redComponent - b.redComponent) > 0.02 { changed += 1 }
            }
        }
        #expect(changed == 0, "The compact panel must display the same monitor symbols and readings as the measured strip")
        fixture.queue.enqueue(IslandNotice(id: "ai-active-test", title: "Codex"), expiresAfter: nil)
        fixture.presenter.setStatusIcons(icons)
        #expect(state.statusIcons.isEmpty)
        #expect(host.window?.ignoresMouseEvents == false, "Activities keep their existing swipe interaction")
        fixture.queue.removeAll()
        fixture.presenter.setStatusIcons(icons)
        #expect(state.statusIcons.map(\.id) == ["cpu"])
        #expect(host.window?.ignoresMouseEvents == true)
        fixture.presenter.setStatusIcons([])
        #expect(state.statusIcons.isEmpty)
        #expect(host.window?.frame.size == CGSize(width: 24, height: 24))
        fixture.presenter.stop()
        #expect(host.window?.isVisible != true)
    }

    @Test(arguments: [IslandEdge.top, .bottom]) @MainActor
    func compactAndStackedImagesKeepTheirMenuBarAppearanceAndOrderInRTLLanguages(edge: IslandEdge) async throws {
        let metricImage = try #require(SystemMonitorMenuBarImageRenderer.stacked(rows: ["C 20%"], style: .compact))
        let image = try #require(SystemMonitorMenuBarImageRenderer.stacked(rows: ["C 20%", "M 2 GB/8 GB"], style: .compact))
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: metricImage, style: .compact), tooltip: "CPU"),
                     IslandStatusIcon(id: "stacked", content: .stacked(image: image,
                         readings: [.init(metric: .cpu, text: "20%"), .init(metric: .memory, text: "2 GB/8 GB")]), tooltip: "Monitors")]
        let size = try #require(IslandStatusIconLayout.size(icons: icons, edge: edge))
        #expect(size == CGSize(width: metricImage.size.width + image.size.width + 24, height: 32))
        let actual = try await renderOffscreen(IslandStatusIconStrip(icons: icons, edge: edge, date: .distantPast)
            .frame(width: size.width, height: size.height)
            .environment(\.layoutDirection, .rightToLeft), size: size)
        let expected = try await renderOffscreen(HStack(spacing: 8) {
            Image(nsImage: metricImage).renderingMode(.template).frame(width: metricImage.size.width, height: 24)
            Image(nsImage: image).renderingMode(.template).frame(width: image.size.width, height: 24)
        }.padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(.white), size: size)
        var changed = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = try #require(actual.colorAt(x: x, y: y))
                let b = try #require(expected.colorAt(x: x, y: y))
                if abs(a.redComponent - b.redComponent) > 0.02 { changed += 1 }
            }
        }
        #expect(changed == 0, "Compact and stacked images must preserve their original readings and image orientation")
    }

    @Test @MainActor
    func hiddenPlaybackDoesNotDrawItsProgressOverTheMonitorIcons() async throws {
        let fixture = try IconFixture(edge: .left)
        defer { fixture.close() }
        let date = Date(timeIntervalSince1970: 100)
        fixture.queue.enqueue(IslandNotice(id: "media-active-left", title: "Music"), expiresAfter: nil)
        fixture.media.publishSnapshot(NowPlayingSnapshot(title: "Music", artist: "Artist", album: nil, artworkData: nil,
            duration: 100, elapsedTime: 50, timestamp: date, isPlaying: true))
        fixture.settings.settings.collapsedProgressGlowEnabled = true
        let state = SideNoticeDisplayState()
        state.islandEdge = .left
        state.placementMode = .custom
        state.compactWingHeight = 32
        state.compactStatusHidden = true
        state.statusIcons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        let size = try #require(IslandStatusIconLayout.size(icons: state.statusIcons, edge: .left))
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep, onStatusHidden: {})
        let actual = try await renderOffscreen(view.statusBarContent(at: date), size: size)
        let expected = try await renderOffscreen(IslandStatusIconStrip(icons: state.statusIcons, edge: .left, date: date)
            .clipShape(CompactIslandShape(layoutStyle: .pill)), size: size)
        var changed = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = try #require(actual.colorAt(x: x, y: y))
                let b = try #require(expected.colorAt(x: x, y: y))
                if abs(a.redComponent - b.redComponent) > 0.02 { changed += 1 }
            }
        }
        #expect(changed == 0, "A dismissed playback activity must not leave its progress glow over the persistent monitor icons")
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func monitorCountChangesTheLongAxisAndRestoresTheIdleCircle(edge: IslandEdge) throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU"),
                     IslandStatusIcon(id: "memory", content: .metric(.memory, text: "2 GB/8 GB", image: nil, style: .detailed), tooltip: "Memory")]
        let idle = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: []))
        #expect(idle.size == CGSize(width: 24, height: 24))
        fixture.presenter.setStatusIcons(Array(icons.prefix(1)))
        let first = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: []))
        fixture.presenter.setStatusIcons(icons)
        let more = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: []))
        #expect((edge.isVertical ? more.height : more.width) > (edge.isVertical ? first.height : first.width))
        #expect((edge.isVertical ? more.width : more.height) == (edge.isVertical ? 40 : 32))
        #expect(fixture.screen.frame.contains(more))
        let pet = try #require(CollapsedPetLayout.petFrame(for: ScreenLayoutEngine(configuration:
            fixture.presenter.compactConfiguration(for: [], at: .now)).layout(for: fixture.screen), side: .left))
        #expect(!pet.intersects(more))
        fixture.presenter.setStatusIcons(Array(icons.prefix(1)))
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: []) == first)
        fixture.presenter.setStatusIcons([])
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: []) == idle)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func monitorPetAnchorsUseThePublishedFrameEvenWhenAnActivityIsHidden(edge: IslandEdge) throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        fixture.presenter.setStatusIcons([IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")])
        let layout = ScreenLayoutEngine(configuration: fixture.presenter.compactConfiguration(for: [], at: .now)).layout(for: fixture.screen)
        let notices = [IslandNotice(id: "voice-processing-left", title: "Voice", detail: "A previous activity is hidden")]
        let frame = try #require(SideNoticeLayoutEngine().compactBarFrame(for: layout, notices: notices, settings: fixture.settings.settings))
        #expect(frame == layout.collapsedFrame, "The pet must use the published monitor frame instead of recalculating a dismissed activity")
        for side in [PetSide.left, .right] {
            let pet = try #require(CollapsedPetLayout.petFrame(for: layout, compactBarFrame: frame, side: side))
            #expect(!pet.intersects(layout.collapsedFrame))
        }
        fixture.settings.settings.statusIconDestination = .menuBar
        let activity = try #require(SideNoticeLayoutEngine().compactBarFrame(for: layout, notices: notices, settings: fixture.settings.settings))
        #expect(activity != layout.collapsedFrame)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func combinedIconSizeAndCoordinatorUpdatesUseTheSameCollapsedFrame(edge: IslandEdge) throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        let coordinator = OverlayCoordinator(contentView: NSView(),
            layoutEngine: ScreenLayoutEngine(configuration: fixture.settings.settings.islandScreenConfiguration))
        defer { coordinator.stop() }
        coordinator.screenSnapshotProvider = { [fixture] in [fixture.screen] }
        coordinator.updateScreens([fixture.screen])
        coordinator.selectActiveDisplay(at: CGPoint(x: fixture.screen.frame.midX, y: fixture.screen.frame.midY))
        fixture.presenter.onCompactLayoutChanged = { displayID, detailed, length, size in
            guard coordinator.activeDisplayID == displayID else { return }
            coordinator.updateCompactStatus(expandsForDetailedStatus: detailed, compactStatusLength: length, statusIconSize: size)
        }
        for pointSize in [16.0, 36.0] {
            let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(battery: nil, wifi: .off, level: nil,
                foreground: .white, configuration: SystemMonitorCombinedIconAppearance(iconSize: pointSize)))
            fixture.presenter.setStatusIcons([IslandStatusIcon(id: "combined", content: .combined(image), tooltip: "Monitor")])
            let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: []))
            let thickness = edge.isVertical ? frame.width : frame.height
            let expectedThickness = max(CGFloat(24), CGFloat(pointSize) + 8)
            #expect(thickness == expectedThickness)
            #expect(coordinator.activeLayout?.collapsedFrame == frame)
            coordinator.updateCompactStatus(expandsForDetailedStatus: false)
            #expect(coordinator.activeLayout?.collapsedFrame.size == CGSize(width: 24, height: 24))
            fixture.presenter.publishCompactLayout(on: fixture.screen.displayID)
            #expect(coordinator.activeLayout?.collapsedFrame == frame, "A screen switch must republish the current icon dimensions")
        }
        fixture.presenter.setStatusIcons([])
        #expect(coordinator.activeLayout?.collapsedFrame.size == CGSize(width: 24, height: 24))
    }

    @Test @MainActor
    func activitiesAndTemporarySuppressionRestoreTheSameMonitorLayout() throws {
        let fixture = try IconFixture(edge: .left)
        defer { fixture.close() }
        fixture.presenter.setStatusIcons([IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "30%", image: nil, style: .detailed), tooltip: "CPU")])
        let idle = fixture.presenter.compactConfiguration(for: [], at: .now)
        #expect(idle.statusIconSize != nil)
        let notice = IslandNotice(id: "ai-active-test", title: "Codex")
        #expect(fixture.presenter.compactConfiguration(for: [notice], at: .now).statusIconSize == nil)
        #expect(fixture.presenter.compactConfiguration(for: [notice], at: .now, statusHidden: true) == idle)
        fixture.presenter.setVoiceRecording(true)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.presenter.setVoiceRecording(false)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now) == idle)
        fixture.presenter.setTransientNoticePresented(true, message: "Done")
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.presenter.setTransientNoticePresented(false)
        fixture.presenter.setTransientNoticePresented(true)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.presenter.setTransientNoticePresented(false)
        fixture.sweep.receive(previous: .running,
            task: AIProgressTask(id: "test", provider: .codex, title: "Test", progress: nil, status: .succeeded, updatedAt: .now),
            observedSince: .distantFuture, settings: fixture.settings.settings)
        #expect(fixture.sweep.current != nil)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.sweep.cancel()
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now) == idle)
        fixture.presenter.setScreenshotActive(true)
        fixture.presenter.setScreenshotActive(false)
        fixture.presenter.setIslandExpanded(true)
        fixture.presenter.setIslandExpanded(false)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now) == idle)
        fixture.settings.settings.statusIconDestination = .menuBar
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.settings.settings.statusIconDestination = .island
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now) == idle)
        fixture.presenter.stop()
        fixture.presenter.setStatusIcons([])
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
    }

    @MainActor
    private func renderOffscreen(_ content: some View, size: CGSize) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).background(.black))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 20000, y: 0), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let cachedBitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: cachedBitmap)
        #expect(host.bounds.size == size && window.alphaValue == 0)
        return try #require(cachedBitmap.converting(to: .sRGB, renderingIntent: .default))
    }

    @Test @MainActor
    func cameraRoutesOnlyToTheMenuBarAndReturningToTheSideRestoresThePreference() throws {
        let fixture = try IconFixture(edge: .right)
        defer { fixture.close() }
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        fixture.presenter.setStatusIcons(icons)
        let side = fixture.presenter.compactConfiguration(for: [], at: .now)
        #expect(side.statusIconSize != nil)
        fixture.settings.settings.islandPlacement = IslandPlacement()
        #expect(fixture.settings.settings.effectiveStatusIconDestination == .menuBar)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        #expect(fixture.settings.settings.statusIconDestination == .island)
        fixture.settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: .right)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now) == side)
        fixture.settings.settings.islandLayoutStyle = .notch
        #expect(fixture.settings.settings.effectiveStatusIconDestination == .menuBar)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.settings.settings.islandLayoutStyle = .pill
        fixture.presenter.setStatusIcons([IslandStatusIcon(id: "network", content: .metric(.network,
            text: String(repeating: "1", count: 1000), image: nil, style: .detailed), tooltip: "Network")])
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: []))
        #expect(frame.height == fixture.screen.frame.height - 16)
        #expect(fixture.screen.frame.contains(frame))
    }

    @MainActor
    private final class IconFixture {
        let suite = "StatusIconPresentation.\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: FeatureSettingsStore
        let language: AppLanguageStore
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController()
        let media = NowPlayingService(loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) })
        let downloads = BrowserDownloadMonitor(directories: [], eventPaths: [])
        let screen = ScreenSnapshot(displayID: 7, frame: CGRect(x: 20000, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 20000, y: 0, width: 1440, height: 876))
        lazy var presenter = SideNoticePresenter(queue: queue, resultSweep: sweep, media: media,
            browserDownloads: downloads, settingsStore: settings, languageStore: language, isScreenLocked: true,
            screenSnapshotProvider: { [unowned self] in [screen] })

        init(edge: IslandEdge) throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            settings = FeatureSettingsStore(defaults: defaults)
            language = AppLanguageStore(defaults: defaults)
            settings.settings.islandLayoutStyle = .pill
            settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
            settings.settings.statusIconDestination = .island
            settings.settings.sideNoticesEnabled = false
            settings.settings.islandNotchBackground = .black
        }

        func close() {
            presenter.stop()
            queue.removeAll()
            sweep.cancel()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
