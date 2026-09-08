import Foundation
import Testing
@testable import Zisla

struct PersistentPetProviderContractTests {
    @Test
    func persistentPetProviderRequiresSpriteBeforeCreatingItsHostView() throws {
        let source = try Self.appSource()
        let providerStart = try #require(source.range(of: "persistentContentViewProvider:"))
        let providerEnd = try #require(
            source[providerStart.upperBound...].range(of: "persistentPanelFrameProvider:")
        )
        let provider = source[providerStart.lowerBound..<providerEnd.lowerBound]
        let spriteGuard = try #require(
            provider.range(of: "guard let petController, petController.sprite != nil else { return nil }")
        )
        let petView = try #require(provider.range(of: "CollapsedPetView("))
        let hostingView = try #require(provider.range(of: "NSHostingView("))

        #expect(spriteGuard.lowerBound < petView.lowerBound)
        #expect(spriteGuard.lowerBound < hostingView.lowerBound)
    }

    private static func appSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/ZislaApp.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
