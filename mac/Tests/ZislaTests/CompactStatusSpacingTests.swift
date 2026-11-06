import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

extension StatusIconDestinationIntegrationTests {
    @Test(arguments: IslandEdge.allCases, [LayoutDirection.leftToRight, .rightToLeft]) @MainActor
    func monitorReadingsKeepTheirEndInsetWhenTheApplicationLogoIsEnabled(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let combined = spacingImage(color: .red, size: 36)
        for rows in [["C 15%", "G 0%"], ["C 100%", "G 100%"], []] {
            let image = rows.isEmpty ? nil : try #require(SystemMonitorMenuBarImageRenderer.stacked(
                rows: rows, style: .compact))
            let monitor = [
                IslandStatusIcon(id: "combined", content: .combined(combined), tooltip: "Combined"),
                IslandStatusIcon(id: "stacked", content: .stacked(image: image,
                    readings: [.init(metric: .cpu, text: "15%"), .init(metric: .gpu, text: "0%")]),
                    tooltip: rows.joined(separator: ", ")),
            ]
            var endInsets: [CGFloat] = []
            for showsApplication in [false, true] {
                let icons = (showsApplication
                    ? [IslandStatusIcon(id: "application", content: .application, tooltip: "zisla")] : []) + monitor
                let size = try #require(IslandStatusIconLayout.size(icons: icons, edge: edge))
                let bitmap = try await renderOffscreen(IslandStatusIconStrip(icons: icons, edge: edge,
                    date: .distantPast).environment(\.layoutDirection, direction)
                    .environment(\._accessibilityReduceMotion, true), size: size)
                let combinedBounds = try spacingPixelBounds(bitmap, size: size, edge: edge) {
                    $0.redComponent > 0.7 && $0.greenComponent < 0.2 && $0.blueComponent < 0.2
                }
                let readingBounds = try spacingPixelBounds(bitmap, size: size, edge: edge) {
                    min($0.redComponent, $0.greenComponent, $0.blueComponent) > 0.4
                }
                let combinedStart = edge.isVertical ? combinedBounds.minY : combinedBounds.minX
                #expect(abs(combinedStart - (showsApplication ? 40 : 8)) <= 0.5,
                        "The 18pt logo must occupy its existing 24pt slot, without shifting its spare width to the monitor's end")
                #expect(abs(combinedBounds.width - 36) <= 0.5 && abs(combinedBounds.height - 36) <= 0.5,
                        "Reserving icon slots must preserve the combined image's configured size")
                let endInset = (edge.isVertical ? size.height - readingBounds.maxY : size.width - readingBounds.maxX)
                endInsets.append(endInset)
                #expect(endInset >= 7.5, "The normal 8pt outer inset must remain visible")
                if !rows.isEmpty {
                    #expect(endInset <= 16,
                            "Real readings must leave only the normal inset and their own transparent image margin")
                }
            }
            #expect(abs(endInsets[0] - endInsets[1]) <= 0.5,
                    "Turning on the application logo must not add blank space after the final CPU/GPU reading")
            #expect(image?.accessibilityDescription == (rows.isEmpty ? nil : rows.joined(separator: ", ")),
                    "Spacing changes must preserve both original monitor rows")
        }
    }

    @Test(arguments: IslandEdge.allCases, [LayoutDirection.leftToRight, .rightToLeft]) @MainActor
    func monitorAndAIShareOneNormalGapWithoutCroppingReadingsOrTheCount(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.collapsedProgressGlowEnabled = false
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let image = try #require(SystemMonitorMenuBarImageRenderer.stacked(rows: ["C 15%", "G 0%"], style: .compact))
        let monitors = [
            IslandStatusIcon(id: "combined", content: .combined(spacingImage(color: .red, size: 36)), tooltip: "Combined"),
            IslandStatusIcon(id: "stacked", content: .stacked(image: image,
                readings: [.init(metric: .cpu, text: "15%"), .init(metric: .gpu, text: "0%")]), tooltip: "C 15%, G 0%"),
        ]
        let notices = (1...2).map { IslandNotice(id: "ai-active-openai-\($0)", title: "AI") }
        notices.forEach { fixture.queue.enqueue($0, expiresAfter: nil) }
        let state = SideNoticeDisplayState()
        state.islandEdge = edge
        state.placementMode = .custom
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            onStatusHidden: {})
        for showsApplication in [false, true] {
            let icons = (showsApplication
                ? [IslandStatusIcon(id: "application", content: .application, tooltip: "zisla")] : []) + monitors
            state.statusIcons = icons
            let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons,
                settings: fixture.settings.settings, item: nil, at: date))
            state.compactWingHeight = edge.isVertical ? layout.size.width : layout.size.height
            let bitmap = try await renderOffscreen(view
                .environment(\.layoutDirection, direction)
                .environment(\._accessibilityReduceMotion, true), size: layout.size)
            let iconSize = try #require(layout.iconSize)
            let iconLength = edge.isVertical ? iconSize.height : iconSize.width
            let length = edge.isVertical ? layout.size.height : layout.size.width
            let forward = edge.isVertical || direction == .leftToRight
            let monitorRange = forward ? CGFloat(0)..<iconLength : (length - iconLength)..<length
            let aiRange = forward ? iconLength..<length : CGFloat(0)..<(length - iconLength)
            let monitorBounds = try spacingPixelBounds(bitmap, size: layout.size, edge: edge, range: monitorRange) {
                max($0.redComponent, $0.greenComponent, $0.blueComponent) > 0.03
            }
            let aiBounds = try spacingPixelBounds(bitmap, size: layout.size, edge: edge, range: aiRange) {
                min($0.redComponent, $0.greenComponent, $0.blueComponent) > 0.4
            }
            let gap = edge.isVertical ? aiBounds.minY - monitorBounds.maxY
                : forward ? aiBounds.minX - monitorBounds.maxX : monitorBounds.minX - aiBounds.maxX
            #expect(gap >= 7.5 && gap <= 18,
                    "The monitor and AI must share the 8pt interface gap, plus only their actual glyph margins; observed \(gap)pt")
            let endInset = edge.isVertical ? length - aiBounds.maxY
                : forward ? length - aiBounds.maxX : aiBounds.minX
            #expect(endInset >= 11.5 && endInset <= 18,
                    "Removing a shared leading inset must preserve the task count's normal trailing inset")
            let countRange = forward ? (length - 22)..<(length - 12) : CGFloat(12)..<22
            _ = try spacingPixelBounds(bitmap, size: layout.size, edge: edge, range: countRange) {
                min($0.redComponent, $0.greenComponent, $0.blueComponent) > 0.4
            }
            #expect(layout.primary.first?.text == "2" && layout.primary.first?.presentation.aiCount == 2)
            #expect(fixture.queue.right == notices && fixture.queue.left.isEmpty,
                    "Rendering compact spacing must not consume AI notices")
        }
        #expect(image.accessibilityDescription == "C 15%, G 0%" && image.isTemplate)
    }

    @Test(arguments: IslandEdge.allCases, [LayoutDirection.leftToRight, .rightToLeft]) @MainActor
    func adjacentStatusItemsShareTheirInsetAndStandaloneStatusKeepsItsOuterInsets(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var settings = FeatureSettings(statusIconDestination: .island, islandShowMoreInformation: true,
            islandLayoutStyle: .pill, islandPlacement: IslandPlacement(mode: .custom, edge: edge))
        settings.collapsedProgressGlowEnabled = false
        let ai = IslandNotice(id: "ai-active-openai-1", title: "AI")
        let reminder = IslandNotice(id: "toolbox-reminder-left", title: "Awake", detail: "30:00",
            artworkData: spacingImage(color: .blue, size: 24).tiffRepresentation)
        for notices in [[ai], [ai, reminder]] {
            let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: [],
                settings: settings, item: nil, at: date))
            let bitmap = try await renderOffscreen(FloatingIslandInformationView(layout: layout,
                visualizationStyle: .waveform, item: nil, date: date)
                .environment(\.colorScheme, .dark)
                .environment(\.layoutDirection, direction)
                .environment(\._accessibilityReduceMotion, true), size: layout.size)
            let first = try #require(layout.primary.first)
            let length = edge.isVertical ? layout.size.height : layout.size.width
            let forward = edge.isVertical || direction == .leftToRight
            let aiRange = forward ? CGFloat(0)..<first.length : (length - first.length)..<length
            let aiBounds = try spacingPixelBounds(bitmap, size: layout.size, edge: edge, range: aiRange) {
                min($0.redComponent, $0.greenComponent, $0.blueComponent) > 0.4
            }
            let leading = edge.isVertical ? aiBounds.minY : forward ? aiBounds.minX : length - aiBounds.maxX
            #expect(leading >= 11.5 && leading <= 18, "A standalone leading status must retain its 12pt outer inset")
            if notices.count == 1 {
                let trailing = edge.isVertical ? length - aiBounds.maxY
                    : forward ? length - aiBounds.maxX : aiBounds.minX
                #expect(trailing >= 11.5 && trailing <= 18, "The standalone task count must retain its trailing inset")
            } else {
                let reminderBounds = try spacingPixelBounds(bitmap, size: layout.size, edge: edge) {
                    $0.blueComponent > 0.7 && $0.redComponent < 0.2 && $0.greenComponent < 0.2
                }
                let gap = edge.isVertical ? reminderBounds.minY - aiBounds.maxY
                    : forward ? reminderBounds.minX - aiBounds.maxX : aiBounds.minX - reminderBounds.maxX
                #expect(gap >= 11.5 && gap <= 18,
                        "Adjacent status items must share one 12pt inset instead of adding two; observed \(gap)pt")
            }
        }
    }

    @MainActor
    private func spacingImage(color: NSColor, size: CGFloat) -> NSImage {
        NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    private func spacingPixelBounds(_ bitmap: NSBitmapImageRep, size: CGSize, edge: IslandEdge,
                                    range: Range<CGFloat>? = nil, matches: (NSColor) -> Bool) throws -> CGRect {
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        var bounds = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let axis = CGFloat(edge.isVertical ? y : x) / scale
                if let range, !range.contains(axis) { continue }
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if matches(color) {
                    bounds = bounds.union(CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale,
                        width: 1 / scale, height: 1 / scale))
                }
            }
        }
        return try #require(bounds.isNull ? nil : bounds,
                            "The actual reading, logo, task count, or monitor image must render in its visible slot")
    }
}
