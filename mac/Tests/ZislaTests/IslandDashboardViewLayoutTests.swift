 import Foundation
import Testing

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

    private static let dashboardSourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zisla/IslandDashboardView.swift")
}
