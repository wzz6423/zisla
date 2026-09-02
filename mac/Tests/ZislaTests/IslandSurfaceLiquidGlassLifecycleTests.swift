import Foundation
import Testing
@testable import Zisla

/// Guards the native Glass refresh seam used after an expanded surface changes size.
struct IslandSurfaceLiquidGlassLifecycleTests {
    @Test
    func resizingAnExpandedShellRenewsItsCompositingState() throws {
        let source = try Self.source(of: "IslandSurface.swift")

        #expect(source.contains("private var lastLaidOutSize: CGSize = .zero"))
        #expect(source.contains("override func layout()"))
        #expect(source.contains("bounds.size != lastLaidOutSize"))
        #expect(source.contains("self.window?.displayIfNeeded()"))
    }

    @Test
    func glassRefreshKeepsTheExistingRevealRefreshSchedule() throws {
        let source = try Self.source(of: "IslandSurface.swift")
        let refreshStart = try #require(source.range(of: "private func scheduleRevealRefreshes()"))
        let refreshEnd = try #require(source[refreshStart.upperBound...].range(of: "\n    }"))
        let refresh = source[refreshStart.lowerBound..<refreshEnd.upperBound]

        #expect(refresh.contains("delay: 0"))
        #expect(refresh.contains("delay: 0.24"))
    }

    private static func source(of fileName: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla")
            .appendingPathComponent(fileName)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
