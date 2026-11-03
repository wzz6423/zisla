import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct HeadphoneConnectionNoticeTests {
    @Test(arguments: IslandEdge.allCases, [false, true]) @MainActor
    func customCompactConnectionUsesTheExistingHeadphoneGlyph(edge: IslandEdge, reduceMotion: Bool) throws {
        for symbol in [nil, "headphones"] as [String?] {
            for metadata in [nil, [HeadphoneConnection.productIDMetadataKey: "invalid"],
                [HeadphoneConnection.productIDMetadataKey: String(UInt32.max)]] as [[String: String]?] {
                let notice = IslandNotice(id: "headphone-connection", title: "AirPods Pro", style: .headphone,
                    symbolName: symbol, metadata: metadata)
                let presentation = CompactPillStatusPresentation(priority: .transient, notice: notice, text: "")
                let size = edge.isVertical ? CGSize(width: 32, height: 48) : CGSize(width: 48, height: 32)
                func bitmap(_ content: some View) throws -> NSBitmapImageRep {
                    let renderer = ImageRenderer(content: content
                        .frame(width: size.width, height: size.height)
                        .background(.black)
                        .environment(\._accessibilityReduceMotion, reduceMotion)
                        .transaction { $0.disablesAnimations = true })
                    renderer.scale = 2
                    return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                }
                let actual = try bitmap(CompactPillStatusContent(presentation: presentation, text: "",
                    edge: edge, visualizationStyle: .waveform, item: nil))
                let expected = try bitmap(HeadphoneGlyph(productID: notice.headphoneProductID, isPresented: !reduceMotion,
                    isSingleUnit: symbol == "headphones", reduceMotion: reduceMotion)
                    .frame(width: 24, height: 24)
                    .frame(width: edge.isVertical ? 32 : 24, height: edge.isVertical ? 24 : 32)
                    .padding(edge.isVertical ? .vertical : .horizontal, 12))
                var differences = 0
                var foreground = 0
                for y in 0..<actual.pixelsHigh {
                    for x in 0..<actual.pixelsWide {
                        let a = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        let b = try #require(expected.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        let redDifference = abs(a.redComponent - b.redComponent)
                        let greenDifference = abs(a.greenComponent - b.greenComponent)
                        let blueDifference = abs(a.blueComponent - b.blueComponent)
                        if max(redDifference, greenDifference, blueDifference) > 0.01 { differences += 1 }
                        if max(a.redComponent, a.greenComponent, a.blueComponent) > 0.25 { foreground += 1 }
                    }
                }
                #expect(foreground > 10, "A connection without a system asset must retain a visible headphone icon")
                #expect(differences == 0,
                    "The custom pill must reuse the headphone glyph for \(edge), symbol \(symbol ?? "nil"), metadata \(String(describing: metadata)), reduceMotion \(reduceMotion)")
            }
        }
    }

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

        let notice = IslandNotice(id: "headphone-connection", title: "AirPods Pro", style: .headphone,
            metadata: [HeadphoneConnection.productIDMetadataKey: String(0x2027)])
        #expect(notice.headphoneProductID == 0x2027)
        let asset = try #require(locator.asset(for: notice.headphoneProductID))
        #expect(asset.imageURL.lastPathComponent == "B788.icns")
        #expect(asset.animationURL?.lastPathComponent == "Banner-PID-8231-Loop.mov")
        #expect(locator.asset(for: nil) == nil)
        #expect(locator.asset(for: 0x2028) == nil)
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

}
