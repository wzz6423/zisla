import Foundation
import Testing

/// The app must own exactly one `SPUUpdater`. A second one downloads the same version through its
/// own feed, and whichever download finishes last wins the pending install — observed in the field
/// as a single-architecture install being replaced by the universal build. Only `SparkleUpdateController`
/// rewrites the feed for the running architecture, so it has to stay the sole updater in the process.
struct SparkleSingleUpdaterTests {
    @Test
    func onlySparkleUpdateControllerConstructsAnUpdater() throws {
        let owners = try Self.swiftSourcePaths()
            .filter { try Self.source(at: $0).contains("SPUUpdater(") }
            .sorted()

        #expect(owners == ["Zisla/SparkleUpdateController.swift"])
    }

    @Test
    func keyboardKitDoesNotImportSparkle() throws {
        let importers = try Self.swiftSourcePaths()
            .filter { $0.hasPrefix("KeyboardKit/") }
            .filter { try Self.source(at: $0).contains("import Sparkle") }
            .sorted()

        #expect(importers.isEmpty)
    }

    /// Dropping the link-time dependency is what makes the regression impossible rather than merely absent.
    @Test
    func keyboardKitTargetDoesNotDependOnSparkle() throws {
        let manifest = try String(
            contentsOf: Self.macDirectory.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        // Anchored on the dependency list so it cannot match the same name in `products:`.
        let dependencies = try #require(
            manifest.range(
                of: #"name: "KeyboardKit",\n\s*dependencies: \[[^\]]*\]"#,
                options: .regularExpression
            )
        )

        #expect(!manifest[dependencies].contains("Sparkle"))
    }

    private static let macDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let sourcesDirectory = macDirectory.appendingPathComponent("Sources")

    /// Paths relative to `mac/Sources`, so assertions read like the layout on disk.
    private static func swiftSourcePaths() throws -> [String] {
        let root = sourcesDirectory.standardizedFileURL
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { $0.standardizedFileURL.path.replacingOccurrences(of: root.path + "/", with: "") }
    }

    private static func source(at relativePath: String) throws -> String {
        try String(contentsOf: sourcesDirectory.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
