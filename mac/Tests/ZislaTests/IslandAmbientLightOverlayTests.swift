import Foundation
import Testing

/// The expanded island used to layer three additive white plusLighter overlays on top of the
/// smoked/regular glass: a drifting light field of soft orbs, a one-shot diagonal sheen, and a
/// hairline rim stroke. On the gray glass region they read as white blurry line-shaped patches
/// rather than ambience, breaking the "smooth gray gradient" the surface is meant to project.
/// These tests pin the two expanded-surface builders (frosted and transparent) so neither can
/// silently grow the overlays back.
struct IslandAmbientLightOverlayTests {
    @Test
    func expandedFrostedSurfaceHasNoWhiteAmbientOverlays() throws {
        let body = try Self.body(of: "IslandSurface.swift", variable: "frostedSurface")
        #expect(!body.contains("IslandLightField("))
        #expect(!body.contains("IslandSheenSweep("))
        #expect(!body.contains("IslandRimLight("))
    }

    @Test
    func expandedTransparentSurfaceHasNoWhiteAmbientOverlays() throws {
        let body = try Self.body(of: "IslandSurface.swift", variable: "transparentSurface")
        #expect(!body.contains("IslandLightField("))
        #expect(!body.contains("IslandSheenSweep("))
        #expect(!body.contains("IslandRimLight("))
    }

    private static func body(of fileName: String, variable: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla")
            .appendingPathComponent(fileName)
        let source = try String(contentsOf: url, encoding: .utf8)
        let pattern = "private var \(variable): some View {"
        let start = try #require(source.range(of: pattern))
        let remainder = source[start.upperBound...]
        // The builder ends at the next closing brace at column 4; the file is consistently indented
        // with four-space braces, so the first "\n    }\n" after the opening brace is the body's end.
        let end = try #require(remainder.range(of: "\n    }\n"))
        return String(remainder[..<end.lowerBound])
    }
}
