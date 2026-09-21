 import Foundation
import Testing

@testable import Zisla

struct IslandDashboardViewLayoutTests {
    @Test
    func dashboardCardsUseTheSharedFixedHeight() throws {
        let source = try String(contentsOf: Self.dashboardSourceURL, encoding: .utf8)

        #expect(source.contains("minHeight: IslandDashboardLayout.cardHeight"))
        #expect(source.contains("maxHeight: IslandDashboardLayout.cardHeight"))
        #expect(!source.contains("minHeight: 58"))
    }

    @Test
    func dashboardMediaCardOmitsPlaybackProgress() throws {
        let source = try String(contentsOf: Self.dashboardSourceURL, encoding: .utf8)
        let start = try #require(source.range(of: "    private var mediaCard: some View {"))
        let end = try #require(
            source.range(
                of: "    @ViewBuilder\n    private func mediaArtwork",
                range: start.lowerBound..<source.endIndex
            )
        )
        let mediaCard = source[start.lowerBound..<end.lowerBound]

        #expect(!mediaCard.contains("ProgressView"))
        #expect(!mediaCard.contains("TimelineView"))
    }

    @Test
    func dashboardCapsHeightAtKeyboardSurfaceHeightAndScrollsCards() throws {
        let layout = IslandModuleLayout.resolved(for: .dashboard, dashboardCardCount: 100)

        #expect(layout.islandSize.height == IslandModuleLayout.keyboardSound.islandSize.height)
        #expect(layout.panelSize.height == IslandModuleLayout.keyboardSound.panelSize.height)

        let source = try String(contentsOf: Self.dashboardSourceURL, encoding: .utf8)
        #expect(source.contains("ScrollView(.vertical)"))
    }

    @Test
    func dashboardScrollUsesSharedThinScrollChrome() throws {
        let source = try String(contentsOf: Self.dashboardSourceURL, encoding: .utf8)
        let bodyStart = try #require(source.range(of: "    var body: some View {"))
        let dynamicCards = try #require(
            source.range(
                of: "\n    private var dynamicCards",
                range: bodyStart.lowerBound..<source.endIndex
            )
        )
        let body = source[bodyStart.lowerBound..<dynamicCards.lowerBound]

        #expect(body.contains("ScrollView(.vertical)"))
        #expect(body.contains(".scrollIndicators(.visible)\n                .thinScrollChrome(visibleWhenScrollable: true)"))
    }

    private static let dashboardSourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zisla/IslandDashboardView.swift")
}
