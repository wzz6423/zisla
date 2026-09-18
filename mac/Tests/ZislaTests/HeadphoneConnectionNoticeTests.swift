import Foundation
import Testing

@testable import Zisla

struct HeadphoneConnectionNoticeTests {
    @Test
    func headphoneGlyphUsesSystemDeviceAssetsInsteadOfAnAirPodsSymbol() throws {
        let source = try String(contentsOf: Self.sideNoticeViewSourceURL, encoding: .utf8)
        let glyph = try Self.sourceSlice(
            in: source,
            from: "private struct HeadphoneGlyph: View",
            to: "private struct HeadphoneBatteryLevels: View"
        )

        #expect(glyph.contains("HeadphoneSystemAssetLocator.system.asset(for: productID)"))
        #expect(glyph.contains("HeadphoneConnectionAnimation(url: animationURL)"))
        #expect(glyph.contains("Image(nsImage: image)"))
        #expect(!glyph.contains("airpods.pro"))
        #expect(!glyph.contains(".symbolEffect("))
    }

    @Test
    func headphoneAssetLocatorUsesSystemImageAndAnimationPaths() throws {
        let source = try String(contentsOf: Self.sideNoticeViewSourceURL, encoding: .utf8)

        #expect(source.contains("let imageName = imageName(for: productID)"))
        #expect(source.contains("Banner-PID-\\(productID)-Loop.mov"))
    }

    @Test
    func headphoneSystemAssetsResolveStaticAndAnimatedResources() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-headphone-assets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let imageResources = temporaryDirectory.appendingPathComponent("CoreBluetoothUI")
        let animationResources = temporaryDirectory.appendingPathComponent("BluetoothUIService")
        try FileManager.default.createDirectory(at: imageResources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: animationResources, withIntermediateDirectories: true)
        let assetPaths = ["0x2027": ["ImageName": "B788.icns"]]
        let assetPathsData = try PropertyListSerialization.data(
            fromPropertyList: assetPaths,
            format: .xml,
            options: 0
        )
        try assetPathsData.write(to: imageResources.appendingPathComponent("AssetPaths-B788.plist"))
        FileManager.default.createFile(
            atPath: imageResources.appendingPathComponent("B788.icns").path,
            contents: Data()
        )
        let animationDirectory = animationResources
            .appendingPathComponent("Banner-PID-8231-mov", isDirectory: true)
        try FileManager.default.createDirectory(at: animationDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: animationDirectory.appendingPathComponent("Banner-PID-8231-Loop.mov").path,
            contents: Data()
        )

        let locator = HeadphoneSystemAssetLocator(
            coreBluetoothUIResourcesURL: imageResources,
            bluetoothUIServiceResourcesURL: animationResources
        )

        let asset = try #require(locator.asset(for: 0x2027))
        #expect(asset.imageURL.lastPathComponent == "B788.icns")
        #expect(asset.animationURL?.lastPathComponent == "Banner-PID-8231-Loop.mov")
        #expect(locator.asset(for: nil) == nil)
    }

    @Test
    func headphonePresentationPassesProductIDAndRespectsReduceMotion() throws {
        let source = try String(contentsOf: Self.sideNoticeViewSourceURL, encoding: .utf8)
        let detail = try Self.sourceSlice(
            in: source,
            from: "private struct HeadphoneConnectionNotice: View",
            to: "struct HeadphoneSystemAsset: Equatable, Sendable"
        )
        let compact = try Self.sourceSlice(
            in: source,
            from: "private struct CompactHeadphoneConnectionBar: View",
            to: "private struct CompactFocusTransitionBar: View"
        )

        for presentation in [detail, compact] {
            #expect(presentation.contains("productID: notice.headphoneProductID"))
            #expect(presentation.contains("reduceMotion: reduceMotion"))
        }

        let glyph = try Self.sourceSlice(
            in: source,
            from: "private struct HeadphoneGlyph: View",
            to: "private struct HeadphoneBatteryLevels: View"
        )
        #expect(glyph.contains("if !reduceMotion, let animationURL = asset.animationURL"))

        let appModelSource = try String(contentsOf: Self.appModelSourceURL, encoding: .utf8)
        #expect(appModelSource.contains("HeadphoneConnection.productIDMetadataKey: String($0)"))
    }

    private static var sideNoticeViewSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/SideNoticeView.swift")
    }

    private static var appModelSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/AppModel.swift")
    }

    private static func sourceSlice(
        in source: String,
        from start: String,
        to end: String
    ) throws -> Substring {
        let startRange = try #require(source.range(of: start))
        let endRange = try #require(source[startRange.upperBound...].range(of: end))
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
}
