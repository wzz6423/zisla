import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct HeadphoneConnectionNoticeTests {
    @Test @MainActor
    func externalCompactHeadphoneRingsRemainInsideThePanel() throws {
        let notice = Self.headphoneNotice()
        let engine = SideNoticeLayoutEngine()
        for menuHeight in [CGFloat(18), 22, 24, 25, 28, 32, 34, 48] {
            let screen = ScreenSnapshot(displayID: 7,
                frame: CGRect(x: 1_512, y: -120, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 1_512, y: -120, width: 1_440, height: 900),
                menuBarHeightFallback: menuHeight)
            let frame = try #require(engine.compactBarFrame(for: screen, notices: [notice], settings: FeatureSettings()))
            for scale in [CGFloat(1), 1.5, 2, 3] {
                let bitmap = try Self.compactHeadphoneBitmap(notice: notice, size: frame.size, centerInset: 0, scale: scale,
                    locale: Locale(identifier: "zh_Hans"))
                let bounds = Self.batteryRingBounds(bitmap)
                #expect(bounds.count == 3)
                for ring in bounds {
                    #expect(ring.minY >= 1, "Menu height \(menuHeight), scale \(scale): top stroke must not touch the panel clip")
                    #expect(ring.maxY < CGFloat(bitmap.pixelsHigh))
                    #expect(abs(ring.width - ring.height) <= 1, "Menu height \(menuHeight), scale \(scale): full battery rings must stay circular")
                }
            }
        }
    }

    @Test @MainActor
    func defaultCompactWingHeightProvidesCompleteHeadphoneRings() throws {
        let bitmap = try Self.compactHeadphoneBitmap(notice: Self.headphoneNotice(),
            size: CGSize(width: 240, height: 34), centerInset: 0, scale: 2)
        let bounds = Self.batteryRingBounds(bitmap)
        #expect(bounds.count == 3)
        for ring in bounds {
            #expect(ring.minY >= 1)
            #expect(abs(ring.width - ring.height) <= 1)
        }
    }

    @Test
    func headphoneGlyphPrefersSystemAssetsAndRestoresFallbackSymbolEffect() throws {
        let source = try String(contentsOf: Self.sideNoticeViewSourceURL, encoding: .utf8)
        let glyph = try Self.sourceSlice(
            in: source,
            from: "private struct HeadphoneGlyph: View",
            to: "private struct HeadphoneBatteryLevels: View"
        )

        #expect(glyph.contains("HeadphoneSystemAssetLocator.system.asset(for: productID)"))
        #expect(glyph.contains("HeadphoneConnectionAnimation(url: animationURL)"))
        #expect(glyph.contains("Image(nsImage: image)"))
        #expect(glyph.contains("Image(systemName: isSingleUnit ? \"headphones\" : \"airpods.pro\")"))
        #expect(glyph.contains(".bounce.up.byLayer"))
        #expect(glyph.contains("value: isPresented"))
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
        #expect(locator.asset(for: 0x2028) == nil)
    }

    @Test
    func headphonePresentationPassesProductIDAndRestoresFallbackMotion() throws {
        let source = try String(contentsOf: Self.sideNoticeViewSourceURL, encoding: .utf8)
        let detail = try Self.sourceSlice(
            in: source,
            from: "private struct HeadphoneConnectionNotice: View",
            to: "struct HeadphoneSystemAsset: Equatable, Sendable"
        )
        let compact = try Self.sourceSlice(
            in: source,
            from: "struct CompactHeadphoneConnectionBar: View",
            to: "private struct CompactFocusTransitionBar: View"
        )

        for presentation in [detail, compact] {
            #expect(presentation.contains("@State private var isPresented = false"))
            #expect(presentation.contains("productID: notice.headphoneProductID"))
            #expect(presentation.contains("isPresented: isPresented"))
            #expect(presentation.contains("reduceMotion: reduceMotion"))
            #expect(presentation.contains("guard !reduceMotion else { return }"))
            #expect(presentation.contains("isPresented = true"))
            #expect(!presentation.contains("withAnimation"))
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

    private static func headphoneNotice() -> IslandNotice {
        IslandNotice(id: "headphone-connection", title: "AirPods Pro", detail: "已连接", side: .left,
            style: .headphone, batteryLevels: [
                NoticeBatteryLevel(label: "左", level: 100),
                NoticeBatteryLevel(label: "右", level: 100),
                NoticeBatteryLevel(label: "盒", level: 100),
            ])
    }

    @MainActor
    private static func compactHeadphoneBitmap(notice: IslandNotice, size: CGSize, centerInset: CGFloat,
        scale: CGFloat, locale: Locale = Locale(identifier: "en_US_POSIX")) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: CompactHeadphoneConnectionBar(
            notice: notice, height: size.height, centerInset: centerInset
        )
            .frame(width: size.width, height: size.height)
            .background(.black)
            .clipped()
            .transaction { $0.disablesAnimations = true }
            .environment(\.colorScheme, .dark)
            .environment(\.locale, locale))
        renderer.scale = scale
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    private static func batteryRingBounds(_ bitmap: NSBitmapImageRep) -> [CGRect] {
        var rings: [CGRect] = []
        var current: CGRect?
        for horizontal in 0..<bitmap.pixelsWide {
            var column: CGRect?
            for vertical in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: horizontal, y: vertical)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5, color.greenComponent > 0.4,
                      color.greenComponent > color.redComponent * 1.5,
                      color.greenComponent > color.blueComponent * 1.5 else { continue }
                let pixel = CGRect(x: horizontal, y: vertical, width: 1, height: 1)
                column = column.map { $0.union(pixel) } ?? pixel
            }
            if let column {
                current = current.map { $0.union(column) } ?? column
            } else if let completed = current {
                rings.append(completed)
                current = nil
            }
        }
        if let completed = current { rings.append(completed) }
        return rings
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
