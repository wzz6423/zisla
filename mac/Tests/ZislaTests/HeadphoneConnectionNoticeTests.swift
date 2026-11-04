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
                    edge: edge, visualizationStyle: .waveform, item: nil, date: .now))
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

    @Test(arguments: [false, true], [IslandLayoutStyle.notch, .pill]) @MainActor
    func compactConnectionDisplaysTheFullDeviceNameAndTighterOuterInsets(physical: Bool, style: IslandLayoutStyle) throws {
        for batteryCount in 1...3 {
            var notice = Self.headphoneNotice()
            notice.title = "我的 AirPods Pro"
            notice.batteryLevels = Array(try #require(notice.batteryLevels).prefix(batteryCount))
            let screen = ScreenSnapshot(displayID: 42,
                frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
                safeAreaInsets: ScreenInsets(top: physical ? 32 : 0),
                auxiliaryTopLeftArea: physical ? CGRect(x: 0, y: 950, width: 716, height: 32) : nil,
                auxiliaryTopRightArea: physical ? CGRect(x: 796, y: 950, width: 716, height: 32) : nil)
            let engine = SideNoticeLayoutEngine()
            let settings = FeatureSettings(islandLayoutStyle: style)
            let layout = ScreenLayoutEngine(configuration: settings.islandScreenConfiguration).layout(for: screen)
            let frame = try #require(engine.compactBarFrame(for: screen, notices: [notice], settings: settings))
            let locale = Locale(identifier: "zh-Hans")
            let centerInset = style == .pill ? max(120, layout.centerOcclusionWidth)
                : physical ? layout.topology.anchorFrame.width : 0
            let titleWidth = ceil((notice.title as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
            ]).width)
            let detailWidth = ceil((BatteryLocalization.metadataText(notice.detail ?? "已连接", locale: locale) as NSString)
                .size(withAttributes: [.font: NSFont.systemFont(ofSize: 8, weight: .medium)]).width)
            let identityWidth = 42 + 8 + max(titleWidth, detailWidth)
            let batteryWidth = CGFloat(20 * batteryCount + 4 * (batteryCount - 1))
            let naturalWidth = centerInset > 0 ? centerInset + (max(identityWidth, batteryWidth) + 6 + 4) * 2
                : identityWidth + 8 + batteryWidth + 6 * 2
            try #require(naturalWidth < 480,
                "The natural-font fixture must fit below the compact limit before comparing its pixels")
            #expect(frame.width == naturalWidth)
            let bitmap = try Self.compactHeadphoneBitmap(notice: notice, size: frame.size,
                centerInset: centerInset, scale: 2, locale: locale)
            let referenceRenderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize(horizontal: true, vertical: false)
                Text(BatteryLocalization.metadataText(notice.detail ?? "已连接", locale: locale))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
                .frame(width: titleWidth, height: frame.height, alignment: .leading)
                .background(.black)
                .environment(\.colorScheme, .dark)
                .environment(\.locale, locale))
            referenceRenderer.scale = 2
            let reference = NSBitmapImageRep(cgImage: try #require(referenceRenderer.cgImage))
            var differences = 0
            let titleOrigin = 6 + 42 + 8
            for y in 0..<reference.pixelsHigh {
                for x in 0..<reference.pixelsWide {
                    let actual = try #require(bitmap.colorAt(x: titleOrigin * 2 + x, y: y)?.usingColorSpace(.sRGB))
                    let expected = try #require(reference.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if abs(actual.redComponent - expected.redComponent) > 0.02 { differences += 1 }
                }
            }
            #expect(differences == 0,
                "The complete name must keep its natural font size before the compact limit is reached")
            let lastRing = try #require(Self.batteryRingBounds(bitmap).last)
            let trailingInset = CGFloat(bitmap.pixelsWide) - lastRing.maxX
            #expect((10...13).contains(trailingInset), "The battery row must end about 6pt inside the island")
        }
    }

    @Test @MainActor
    func batteryCountChangesTheContinuousHeadphoneRowWidth() throws {
        let screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 876))
        let engine = SideNoticeLayoutEngine()
        var notice = Self.headphoneNotice()
        notice.title = "三年后的 AirPods Pro 第二代"
        let three = try #require(engine.compactBarFrame(for: screen, notices: [notice], settings: FeatureSettings()))
        notice.batteryLevels = Array(try #require(notice.batteryLevels).prefix(1))
        let one = try #require(engine.compactBarFrame(for: screen, notices: [notice], settings: FeatureSettings()))
        #expect(three.width - one.width == 48,
            "The row must reserve two 20pt rings and their 4pt gaps only when they are present")
        let bitmap = try Self.compactHeadphoneBitmap(notice: notice, size: one.size, centerInset: 0,
            scale: 2, locale: Locale(identifier: "zh-Hans"))
        #expect(Self.batteryRingBounds(bitmap).count == 1)
    }

    @Test @MainActor
    func missingBatteryLevelsAndSingleUnitOnlyReserveTheirDisplayedRings() throws {
        let screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 876))
        let engine = SideNoticeLayoutEngine()
        var notice = Self.headphoneNotice()
        notice.title = "三年后的 AirPods Pro 第二代"
        let three = try #require(engine.compactBarFrame(for: screen, notices: [notice], settings: FeatureSettings()))
        notice.batteryLevels = []
        let empty = try #require(engine.compactBarFrame(for: screen, notices: [notice], settings: FeatureSettings()))
        notice.batteryLevels = nil
        let unknown = try #require(engine.compactBarFrame(for: screen, notices: [notice], settings: FeatureSettings()))
        #expect(empty == unknown)
        #expect(three.width - unknown.width == 24, "An unknown pair retains two rings without a spare case slot")
        notice.symbolName = "headphones"
        let single = try #require(engine.compactBarFrame(for: screen, notices: [notice], settings: FeatureSettings()))
        #expect(unknown.width - single.width == 24, "A single-unit headset needs one battery ring")
        notice.batteryLevels = Self.headphoneNotice().batteryLevels
        notice.batteryLevels?.append(NoticeBatteryLevel(label: "Extra", level: 100))
        #expect(engine.compactBarFrame(for: screen, notices: [notice], settings: FeatureSettings()) == single,
            "A single-unit headset must not reserve extra component slots")
        let bitmap = try Self.compactHeadphoneBitmap(notice: notice, size: single.size, centerInset: 0,
            scale: 2, locale: Locale(identifier: "zh-Hans"))
        #expect(Self.batteryRingBounds(bitmap).count == 1)
        notice.symbolName = nil
        #expect(engine.compactBarFrame(for: screen, notices: [notice], settings: FeatureSettings()) == three,
            "Only the three components rendered by the existing row may change its width")
    }

    @Test(arguments: AppLanguage.allCases) @MainActor
    func compactHeadphoneSizingIncludesTheLocalizedConnectionDetail(language: AppLanguage) throws {
        let locale = language.locale
        let connected = AppLocalization.string("已连接", locale: locale)
        let connectingWidth = ceil((connected as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .medium)
        ]).width)
        let notice = IslandNotice(id: "headphone-localized", title: "", style: .headphone)
        let measured = CompactHeadphoneConnectionLayout(notice: notice, locale: locale)
        #expect(measured.identityWidth == 42 + 8 + connectingWidth)
        let size = CGSize(width: measured.length(centerWidth: 0), height: 36)
        let actual = try Self.compactHeadphoneBitmap(notice: notice, size: size, centerInset: 0, scale: 2, locale: locale)
        let referenceRenderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 1) {
            Text("").font(.system(size: 10, weight: .semibold))
            Text(connected).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
        }
            .frame(width: connectingWidth, height: size.height, alignment: .leading)
            .background(.black)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, locale))
        referenceRenderer.scale = 2
        let reference = NSBitmapImageRep(cgImage: try #require(referenceRenderer.cgImage))
        var differences = 0
        for y in 0..<reference.pixelsHigh {
            for x in 0..<reference.pixelsWide {
                let value = try #require(actual.colorAt(x: 56 * 2 + x, y: y)?.usingColorSpace(.sRGB))
                let expected = try #require(reference.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if abs(value.redComponent - expected.redComponent) > 0.02 { differences += 1 }
            }
        }
        #expect(differences == 0, "The localized connection detail must retain its natural width for \(language)")
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
