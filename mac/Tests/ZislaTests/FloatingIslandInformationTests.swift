import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct FloatingIslandInformationTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private let notices = [
        IslandNotice(id: "ai-active-openai-1", title: "AI"),
        IslandNotice(id: "ai-active-openai-2", title: "AI"),
        IslandNotice(id: "media-active-left", title: "Music"),
        IslandNotice(id: "toolbox-reminder-left", title: "Awake", detail: "30:00"),
        IslandNotice(id: "toolbox-reminder-right", title: "Awake", detail: "30:00"),
    ]

    @Test(arguments: IslandEdge.allCases, MediaCompactStyle.allCases)
    func informationSharesTheFirstRowAndOnlyDetailedMusicGetsAnotherRow(edge: IslandEdge, style: MediaCompactStyle) throws {
        var settings = settings(edge: edge)
        settings.mediaCompactStyle = style
        settings.compactStatusPriority = CompactStatusPriority.normalized([.toolboxReminder, .media, .aiActivity])
        let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons(),
            settings: settings, item: nil, at: date))
        #expect(layout.icons.map(\.id) == ["combined", "cpu"])
        #expect(layout.primary.first?.presentation.priority == .aiActivity)
        #expect(layout.primary.first?.presentation.aiCount == 2)
        #expect(layout.primary.first?.text == "2")
        #expect(layout.primary.filter { $0.presentation.priority == .toolboxReminder }.count == 1)
        if style == .detailed {
            #expect(layout.primary.map(\.presentation.priority) == [.aiActivity, .toolboxReminder])
            #expect(layout.secondary?.presentation.isMedia == true)
        } else {
            #expect(layout.primary.map(\.presentation.priority) == [.aiActivity, .toolboxReminder, .media])
            #expect(layout.secondary == nil)
        }
        let thickness = edge.isVertical ? layout.size.width : layout.size.height
        #expect(thickness == layout.primaryThickness + (style == .detailed ? 32 : 0))
    }

    @Test
    func emptyInformationAndSpecialTakeoversUseTheExistingSurface() {
        let settings = settings()
        #expect(FloatingIslandInformationLayout(notices: [], icons: [], settings: settings, item: nil, at: date) == nil)
        for id in ["voice-processing-left", "screen-recording-operation-left"] {
            let takeover = IslandNotice(id: id, title: "Processing")
            #expect(FloatingIslandInformationLayout(notices: notices + [takeover], icons: icons(),
                settings: settings, item: nil, at: date) == nil)
        }
    }

    @Test
    func theSwitchAndPlacementGateTheLayoutWithoutDiscardingTheChoice() {
        var settings = settings()
        settings.islandShowMoreInformation = false
        #expect(FloatingIslandInformationLayout(notices: notices, icons: icons(),
            settings: settings, item: nil, at: date) == nil)
        settings.islandShowMoreInformation = true
        for style in IslandLayoutStyle.allCases {
            for mode in IslandPlacementMode.allCases {
                settings.islandLayoutStyle = style
                settings.islandPlacement.mode = mode
                let layout = FloatingIslandInformationLayout(notices: notices, icons: icons(),
                    settings: settings, item: nil, at: date)
                #expect((layout != nil) == (style == .pill && mode == .custom))
                #expect(settings.islandShowMoreInformation)
            }
        }
    }

    @Test
    func disabledNotificationsAndMonitorRoutingCannotLeakStaleContent() throws {
        var settings = settings()
        settings.sideNoticesEnabled = false
        var layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons(),
            settings: settings, item: nil, at: date))
        #expect(layout.primary.isEmpty && layout.secondary == nil)
        settings.systemMonitorEnabled = false
        #expect(FloatingIslandInformationLayout(notices: notices, icons: icons(),
            settings: settings, item: nil, at: date) == nil)
        settings.sideNoticesEnabled = true
        settings.systemMonitorEnabled = true
        settings.statusIconDestination = .menuBar
        layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons(),
            settings: settings, item: nil, at: date))
        #expect(layout.icons.isEmpty && layout.iconSize == nil)
        #expect(layout.primary.first?.presentation.priority == .aiActivity)
    }

    @Test(arguments: IslandEdge.allCases)
    func detailedMusicOnItsOwnDoesNotReserveAnEmptyFirstRow(edge: IslandEdge) throws {
        var settings = settings(edge: edge)
        settings.mediaCompactStyle = .detailed
        let layout = try #require(FloatingIslandInformationLayout(notices: [notices[2]], icons: [],
            settings: settings, item: nil, at: date))
        #expect(layout.primary.count == 1 && layout.primary.first?.presentation.isMedia == true)
        #expect(layout.secondary == nil)
        #expect((edge.isVertical ? layout.size.width : layout.size.height) == 32)
    }

    @Test
    func lyricsKeepUpdatingAndResizingWhileAIHasHigherPriority() throws {
        var settings = settings()
        settings.mediaCompactStyle = .detailed
        let item = NowPlayingSnapshot(title: "Song", artist: "Artist", album: nil, artworkData: nil,
            duration: 60, elapsedTime: 0, timestamp: date, isPlaying: true,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "Hi"),
                                       .init(time: 10, text: "A much longer lyric line that needs more room")]))
        let first = try #require(FloatingIslandInformationLayout(notices: notices, icons: [],
            settings: settings, item: item, at: date))
        let next = try #require(FloatingIslandInformationLayout(notices: notices, icons: [],
            settings: settings, item: item, at: date.addingTimeInterval(11)))
        #expect(first.secondary?.text == "Hi")
        #expect(next.secondary?.text == "A much longer lyric line that needs more room")
        #expect(try #require(next.secondary?.length) > #require(first.secondary?.length))
        #expect(first.primary.map(\.text) == next.primary.map(\.text))
        settings.mediaShowLyricsAndInfo = false
        let hidden = try #require(FloatingIslandInformationLayout(notices: notices, icons: [],
            settings: settings, item: item, at: date.addingTimeInterval(11)))
        #expect(hidden.secondary?.text == "")
    }

    @Test(arguments: IslandEdge.allCases)
    func oversizedInformationFitsWithinTheExistingLengthBudget(edge: IslandEdge) throws {
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu,
            text: String(repeating: "9", count: 1000), image: nil, style: .detailed), tooltip: "CPU")]
        let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons,
            settings: settings(edge: edge), item: nil, at: date))
        #expect((edge.isVertical ? layout.size.height : layout.size.width) == ScreenLayoutConfiguration.quickActionRowWidth)
        #expect(layout.primaryLength > ScreenLayoutConfiguration.quickActionRowWidth)
        #expect(layout.primary.count == 3)
    }

    @Test(arguments: [IslandEdge.left, .right])
    func verticalMonitorReadingsDoNotEnlargeTheAIIconOrItsSlot(edge: IslandEdge) throws {
        let monitor = NSImage(size: CGSize(width: 36, height: 36))
        let rows = try #require(SystemMonitorMenuBarImageRenderer.stacked(
            rows: ["CPU 100%", "GPU 32%"], style: .detailed))
        let icons = [
            IslandStatusIcon(id: "app", content: .application, tooltip: "zisla"),
            IslandStatusIcon(id: "combined", content: .combined(monitor), tooltip: "Monitor"),
            IslandStatusIcon(id: "stacked", content: .stacked(image: rows,
                readings: [.init(metric: .cpu, text: "100%"), .init(metric: .gpu, text: "32%")]),
                tooltip: "CPU 100%, GPU 32%"),
        ]
        let notices = (1...4).map { IslandNotice(id: "ai-active-openai-\($0)", title: "AI") }
        let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons,
            settings: settings(edge: edge), item: nil, at: date))
        let status = try #require(layout.primary.first)
        #expect(layout.size.width <= 48, "Vertical readings must fit the compact 40pt content width and side insets")
        #expect(status.length == 56, "The AI icon needs its 24pt slot, one 14pt count row, and normal insets")
        #expect(status.text == "4")

        let renderer = ImageRenderer(content: FloatingIslandInformationView(layout: layout,
            visualizationStyle: .waveform, item: nil, date: date)
            .frame(width: layout.size.width, height: layout.size.height)
            .environment(\._accessibilityReduceMotion, true)
            .environment(\.colorScheme, .dark)
            .background(.black))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let iconStart = try #require(layout.iconSize).height
        let iconEnd = iconStart + status.length - 32
        var iconBounds = CGRect.null
        var countPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                guard min(color.redComponent, color.greenComponent, color.blueComponent) > 0.4 else { continue }
                let pointY = CGFloat(y) / 2
                if pointY >= iconStart, pointY < iconEnd {
                    iconBounds = iconBounds.union(CGRect(x: CGFloat(x) / 2, y: pointY, width: 0.5, height: 0.5))
                }
                if pointY >= layout.size.height - 26, pointY < layout.size.height - 12 { countPixels += 1 }
            }
        }
        #expect(iconBounds.width > 16 && iconBounds.width <= 24)
        #expect(iconBounds.height > 16 && iconBounds.height <= 24)
        #expect(countPixels > 5, "The full AI count must remain below the compact icon")
    }

    @Test(arguments: [IslandEdge.top, .left])
    func informationRowsStayInsideTheAnimatedViewport(edge: IslandEdge) throws {
        var settings = settings(edge: edge)
        settings.mediaCompactStyle = .detailed
        let item = NowPlayingSnapshot(title: "A long song title", artist: "Artist", album: nil, artworkData: nil,
            duration: 60, elapsedTime: 0, timestamp: date, isPlaying: false,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "A long lyric line that fills the available row")]))
        let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons(),
            settings: settings, item: item, at: date))
        let viewportLength = 96
        let viewport = edge.isVertical ? CGSize(width: layout.size.width, height: CGFloat(viewportLength))
            : CGSize(width: CGFloat(viewportLength), height: layout.size.height)
        let canvas = edge.isVertical ? CGSize(width: viewport.width, height: 300)
            : CGSize(width: 300, height: viewport.height)
        let renderer = ImageRenderer(content: FloatingIslandInformationView(layout: layout,
            visualizationStyle: .waveform, item: item, date: date)
            .frame(width: viewport.width, height: viewport.height)
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .environment(\._accessibilityReduceMotion, true)
            .environment(\.layoutDirection, .leftToRight)
            .background(.black))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var insidePixels = 0
        var outsidePixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.2 {
                    if (edge.isVertical ? y : x) >= viewportLength {
                        outsidePixels += 1
                    } else {
                        insidePixels += 1
                    }
                }
            }
        }
        #expect(insidePixels > 10)
        #expect(outsidePixels == 0, "Leading-aligned rows must fit the current animated viewport")
    }

    @Test(arguments: AppLanguage.allCases)
    func informationSwitchIsLocalizedAndSearchableInTheInformationPage(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        let expression = try NSRegularExpression(pattern:
            #"featureToggle\(\s*"([^"]+)",\s*detail:\s*"([^"]+)",\s*symbol:\s*"rectangle.stack",\s*keyPath:\s*\\\.islandShowMoreInformation"#)
        let match = try #require(expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let keys = try (1...2).map { index in
            String(source[try #require(Range(match.range(at: index), in: source))])
        }
        #expect(keys == ["展示更多信息", "同时展示监控、AI、音乐与状态提示，详细音乐另起一行"])
        let table = try #require(NSDictionary(contentsOf: root.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings")) as? [String: String])
        for key in keys {
            let value = try #require(table[key])
            #expect(!value.isEmpty && !value.contains("%"))
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese { #expect(value != key) }
        }
        #expect(SettingsSearchIndex.results(for: AppLocalization.string(keys[0], language: language),
            settings: settings(), locale: language.locale).contains { $0.section == .info && $0.anchor == .row(keys[0]) })
        var unsupported = settings()
        unsupported.islandPlacement.mode = .camera
        #expect(!SettingsSearchIndex.items(settings: unsupported).contains { $0.title == keys[0] })
        #expect(AppLocalization.string(keys[0], language: .english) == "Show More Information")
        #expect(AppLocalization.string(keys[0], language: .arabic) == "عرض المزيد من المعلومات")
    }

    @Test
    func toolboxRemindersSurvivePlaybackOnlyWhenConcurrentInformationIsEnabled() {
        var settings = settings()
        #expect(AppModel.shouldPresentToolboxReminder(settings: settings, hasMedia: true))
        settings.islandShowMoreInformation = false
        #expect(!AppModel.shouldPresentToolboxReminder(settings: settings, hasMedia: true))
        #expect(AppModel.shouldPresentToolboxReminder(settings: settings, hasMedia: false))
        settings.islandShowMoreInformation = true
        settings.islandPlacement.mode = .camera
        #expect(!AppModel.shouldPresentToolboxReminder(settings: settings, hasMedia: true))
        settings.islandPlacement.mode = .custom
        settings.islandLayoutStyle = .notch
        #expect(!AppModel.shouldPresentToolboxReminder(settings: settings, hasMedia: true))
        settings.islandLayoutStyle = .pill
        for keyPath in [\FeatureSettings.toolboxEnabled, \.toolboxReminderEnabled, \.sideNoticesEnabled] {
            settings[keyPath: keyPath] = false
            #expect(!AppModel.shouldPresentToolboxReminder(settings: settings, hasMedia: true))
            #expect(!AppModel.shouldPresentToolboxReminder(settings: settings, hasMedia: false))
            settings[keyPath: keyPath] = true
        }
    }

    private func settings(edge: IslandEdge = .top) -> FeatureSettings {
        FeatureSettings(statusIconDestination: .island, islandShowMoreInformation: true,
            islandLayoutStyle: .pill, islandPlacement: IslandPlacement(mode: .custom, edge: edge))
    }

    private func icons() -> [IslandStatusIcon] {
        [IslandStatusIcon(id: "combined", content: .combined(nil), tooltip: "Combined"),
         IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
    }
}
