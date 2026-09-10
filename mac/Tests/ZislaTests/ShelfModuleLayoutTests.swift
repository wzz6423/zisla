import Foundation
import Testing

@testable import Zisla

struct ShelfModuleLayoutTests {
    @Test
    func shelfContentHeightMatchesItsOuterLayout() throws {
        let outerLayout = IslandModuleLayout.resolved(for: .shelf, dashboardCardCount: 0)
        let expectedContentHeight = outerLayout.islandSize.height
            - 121
            - IslandSurfaceGeometry.moduleInset * 2

        #expect(outerLayout == IslandModuleLayout.shelf)
        #expect(outerLayout == IslandModuleLayout.clipboard)
        #expect(IslandModuleLayout.shelfContentHeight == 355)
        #expect(outerLayout.islandSize.height == 500)
        #expect(outerLayout.panelSize.height == 504)
        #expect(expectedContentHeight == IslandModuleLayout.shelfContentHeight)

        let source = try String(contentsOf: Self.shelfSourceURL, encoding: .utf8)
        #expect(source.contains(".frame(height: IslandModuleLayout.shelfContentHeight)"))
        #expect(!source.contains(".frame(height: 320)"))
    }

    private static let shelfSourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zisla/ShelfModuleView.swift")
}
