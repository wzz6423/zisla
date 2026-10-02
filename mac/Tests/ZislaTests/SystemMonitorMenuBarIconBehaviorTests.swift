import AppKit
import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct SystemMonitorMenuBarIconBehaviorTests {
    @Test(arguments: [false, true])
    func connectedHeaderRemainsCenteredAfterEnlargingPercentage(showsPercentage: Bool) throws {
        for percentage in showsPercentage ? [0, 1, 9, 70, 100] : [100] {
            for textScale in [1.62, 1.88, 1.98] {
                var snapshot = battery(charging: true, pluggedIn: true)
                snapshot.level = Double(percentage) / 100
                let appearance = SystemMonitorCombinedIconAppearance(
                    showsBatteryPercentage: showsPercentage,
                    usesStatusColors: true, batteryTextScale: textScale
                )
                let image = try #require(SystemMonitorMenuBarIconRenderer.render(
                    menuBarStatus: MenuBarIconStatus(battery: snapshot, wifi: .off, level: nil),
                    size: 120, scale: 2, foreground: NSColor.white.cgColor,
                    options: MenuBarIconBatteryOptions(appearance: appearance),
                    connectionOptions: MenuBarIconConnectionOptions(appearance: appearance),
                    volumeOptions: MenuBarIconVolumeOptions(appearance: appearance)
                ))
                let bitmap = NSBitmapImageRep(cgImage: image)
                var columns: [Int] = []
                for y in 0..<64 {
                    for x in 0..<bitmap.pixelsWide {
                        let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                        if color.alphaComponent > 0.8, color.redComponent > 0.9,
                           color.greenComponent > 0.9, color.blueComponent > 0.9 {
                            columns.append(x)
                        }
                    }
                }
                let center = Double(try #require(columns.min()) + #require(columns.max())) / 2
                #expect(abs(center - 119) <= 3,
                    "Header is off center: \(percentage), \(textScale), pixel center \(center)")
            }
        }
    }

    @Test
    func largerConnectedNumbersPreserveTheOriginalBatteryArc() throws {
        for charging in [false, true] {
            for textScale in [1.62, 1.88, 1.98] {
                for stroke in SystemMonitorMenuBarRingStrokeStyle.allCases {
                    var snapshot = battery(charging: charging, pluggedIn: true)
                    snapshot.level = 1
                    let appearance = SystemMonitorCombinedIconAppearance(
                        ringStrokeStyle: stroke, usesStatusColors: true, batteryTextScale: textScale
                    )
                    let actual = try #require(SystemMonitorMenuBarIconRenderer.render(
                        menuBarStatus: MenuBarIconStatus(battery: snapshot, wifi: .off, level: nil),
                        size: 120, scale: 2, foreground: NSColor.white.cgColor,
                        options: MenuBarIconBatteryOptions(appearance: appearance),
                        connectionOptions: MenuBarIconConnectionOptions(appearance: appearance),
                        volumeOptions: MenuBarIconVolumeOptions(appearance: appearance)
                    ))
                    let expected = try #require(CGContext(
                        data: nil, width: 240, height: 240, bitsPerComponent: 8, bytesPerRow: 960,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ))
                    expected.translateBy(x: 0, y: 240)
                    expected.scaleBy(x: 2, y: -2)
                    expected.setLineWidth(8 * stroke.scale)
                    expected.setLineCap(.round)
                    let gap = 103 * asin((35 * textScale / 1.98 + 4 * stroke.scale + 6) / 51.5)
                    expected.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
                    expected.addPath(SystemMonitorMenuBarIconGeometry.batteryTrack(hasTopGap: true, topGapWidth: gap))
                    expected.strokePath()
                    expected.setStrokeColor(CGColor(red: 52.0 / 255, green: 199.0 / 255, blue: 89.0 / 255, alpha: 1))
                    expected.addPath(SystemMonitorMenuBarIconGeometry.batteryFill(
                        progress: 1, hasTopGap: true, topGapWidth: gap
                    ))
                    expected.strokePath()
                    func coloredPixels(_ image: CGImage) throws -> Set<Int> {
                        let bitmap = NSBitmapImageRep(cgImage: image)
                        var result = Set<Int>()
                        for y in 0..<240 {
                            for x in 0..<bitmap.pixelsWide {
                                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                                if color.alphaComponent > 0.5,
                                   color.greenComponent > color.redComponent + 0.2,
                                   color.greenComponent > color.blueComponent + 0.2 {
                                    result.insert(y * bitmap.pixelsWide + x)
                                }
                            }
                        }
                        return result
                    }
                    let actualPixels = try coloredPixels(actual)
                    let expectedPixels = try coloredPixels(#require(expected.makeImage()))
                    #expect(actualPixels.count > expectedPixels.count, "The shoulders must recover previously unused space")
                }
            }
        }
    }

    @Test
    func topIndicatorUsesPercentageAndBoltStates() throws {
        var appearance = SystemMonitorCombinedIconAppearance(
            showsBatteryPercentage: true, showsChargingIndicator: true,
            showsPercentageWhenConnected: false, usesStatusColors: false
        )
        let percentage = try bitmap(battery: battery(), appearance: appearance)
        let charging = try bitmap(battery: battery(charging: true, pluggedIn: true), appearance: appearance)
        let plugged = try bitmap(battery: battery(pluggedIn: true), appearance: appearance)
        #expect(percentage != charging)
        #expect(charging != plugged)
        #expect(percentage != plugged)
        appearance.showsPercentageWhenConnected = true
        #expect(try bitmap(battery: battery(pluggedIn: true), appearance: appearance) == charging)
        #expect(try bitmap(battery: battery(charging: true, pluggedIn: true), appearance: appearance) == charging)
    }

    @Test(arguments: [0.7, 1.0], [false, true])
    func connectedBatteryUsesTheSameLightningAsCharging(level: Double, showsPercentage: Bool) throws {
        let appearance = SystemMonitorCombinedIconAppearance(
            showsBatteryPercentage: showsPercentage, showsChargingIndicator: true,
            showsPercentageWhenConnected: true, usesStatusColors: true
        )
        var connected = battery(pluggedIn: true)
        connected.level = level
        connected.isCharged = level == 1
        var charging = connected
        charging.isCharging = true
        charging.isCharged = false
        #expect(try bitmap(battery: connected, appearance: appearance)
            == bitmap(battery: charging, appearance: appearance),
            "External power must retain the lightning glyph after charging finishes")
    }

    @Test
    func chargingHeaderHonorsIndependentValueAndIndicatorSwitches() {
        for charging in [false, true] {
            for value in [false, true] {
                for indicator in [false, true] {
                    for connectedValue in [false, true] {
                        let appearance = SystemMonitorCombinedIconAppearance(
                            showsBatteryPercentage: value, showsChargingIndicator: indicator,
                            showsPercentageWhenConnected: connectedValue
                        )
                        let status = MenuBarIconStatus(battery: battery(charging: charging, pluggedIn: true), wifi: .off, level: nil)
                        let expected: MenuBarIconBatteryGapContent
                        if indicator {
                            expected = charging
                                ? (value ? .boltAndPercentage : .bolt)
                                : (value && connectedValue ? .boltAndPercentage : .bolt)
                        } else {
                            expected = value ? .percentage : .empty
                        }
                        #expect(MenuBarIconMappings.batteryGapContent(status.battery,
                            options: MenuBarIconBatteryOptions(appearance: appearance)) == expected)
                    }
                }
            }
        }
    }

    @Test
    func batteryHeaderPixelsStaySeparatedFromRingAcrossSizes() throws {
        for charging in [false, true] {
            for (percentage, indicator) in [0, 1, 9, 70, 100].flatMap({ value in [false, true].map { (value, $0) } }) {
                for step in 0...18 {
                    let textScale = 1.62 + Double(step) * 0.02
                    for stroke in SystemMonitorMenuBarRingStrokeStyle.allCases {
                        var snapshot = battery(charging: charging, pluggedIn: true)
                        snapshot.level = Double(percentage) / 100
                        let appearance = SystemMonitorCombinedIconAppearance(
                            ringStrokeStyle: stroke, showsBatteryPercentage: true,
                            showsChargingIndicator: indicator, showsPercentageWhenConnected: true,
                            usesStatusColors: true, batteryTextScale: textScale
                        )
                        let status = MenuBarIconStatus(battery: snapshot, wifi: .off, level: nil)
                        let image = try #require(SystemMonitorMenuBarIconRenderer.render(
                            menuBarStatus: status, size: 22, scale: 2,
                            foreground: NSColor.white.cgColor,
                            options: MenuBarIconBatteryOptions(appearance: appearance),
                            connectionOptions: MenuBarIconConnectionOptions(appearance: appearance),
                            volumeOptions: MenuBarIconVolumeOptions(appearance: appearance)
                        ))
                        let rep = NSBitmapImageRep(cgImage: image)
                        var header: [CGPoint] = []
                        var ring: [CGPoint] = []
                        for y in 0..<18 {
                            for x in 0..<rep.pixelsWide {
                                let color = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                                if color.alphaComponent > 0.5 {
                                    if color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9 && y < 13 {
                                        header.append(CGPoint(x: x, y: y))
                                    } else if color.greenComponent > color.blueComponent + 0.2 || color.redComponent > color.blueComponent + 0.2 {
                                        ring.append(CGPoint(x: x, y: y))
                                    }
                                }
                            }
                        }
                        #expect(header.count > 8)
                        let headerWidth = (header.map(\.x).max() ?? 0) - (header.map(\.x).min() ?? 0)
                        #expect(headerWidth <= 29, "Header must fit inside the ring rather than erase its upper half")
                        if indicator && percentage == 100 {
                            #expect(header.filter { $0.x < 16 }.count > 3, "Power glyph must remain visible left of 100")
                            #expect(header.filter { $0.x > 22 }.count > 5, "Percentage must remain visible right of the power glyph")
                        }
                        for glyph in header {
                            #expect(glyph.x > 0 && glyph.x < CGFloat(rep.pixelsWide - 1))
                            for arc in ring {
                                #expect(hypot(glyph.x - arc.x, glyph.y - arc.y) >= sqrt(2),
                                    "Header touches ring: \(percentage), charging \(charging), indicator \(indicator), \(textScale), \(stroke), glyph \(glyph), arc \(arc)")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test
    func chargingGlyphAndPercentageGrowTogetherWithTextSlider() throws {
        for charging in [false, true] {
            for percentage in [9, 70, 100] {
                var bounds: [(glyph: CGRect, value: CGRect)] = []
                for textScale in [1.62, 1.88, 1.98] {
                    var snapshot = battery(charging: charging, pluggedIn: true)
                    snapshot.level = Double(percentage) / 100
                    let appearance = SystemMonitorCombinedIconAppearance(
                        showsBatteryPercentage: true, showsChargingIndicator: true,
                        showsPercentageWhenConnected: true, usesStatusColors: true,
                        batteryTextScale: textScale, wifiScale: 1
                    )
                    let image = try #require(SystemMonitorMenuBarIconRenderer.render(
                        menuBarStatus: MenuBarIconStatus(battery: snapshot, wifi: .off, level: nil),
                        size: 120, scale: 2, foreground: NSColor.white.cgColor,
                        options: MenuBarIconBatteryOptions(appearance: appearance),
                        connectionOptions: MenuBarIconConnectionOptions(appearance: appearance),
                        volumeOptions: MenuBarIconVolumeOptions(appearance: appearance)
                    ))
                    let rep = NSBitmapImageRep(cgImage: image)
                    var columns: [Int: [Int]] = [:]
                    for y in 0..<92 {
                        for x in 0..<rep.pixelsWide {
                            let color = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                            if color.alphaComponent > 0.8 && color.redComponent > 0.9
                                && color.greenComponent > 0.9 && color.blueComponent > 0.9 {
                                columns[x, default: []].append(y)
                            }
                        }
                    }
                    let first = try #require(columns.keys.min())
                    let separator = try #require((first..<rep.pixelsWide).first { columns[$0] == nil })
                    func inkBounds(_ selected: [Int]) throws -> CGRect {
                        let xs = selected.filter { columns[$0] != nil }
                        let ys = xs.flatMap { columns[$0] ?? [] }
                        let minX = try #require(xs.min())
                        let minY = try #require(ys.min())
                        let maxX = try #require(xs.max())
                        let maxY = try #require(ys.max())
                        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                    }
                    let glyph = try inkBounds(Array(first..<separator))
                    let value = try inkBounds(Array(separator..<rep.pixelsWide))
                    #expect(glyph.maxX < value.minX, "Charging glyph and percentage must have separate ink bounds")
                    #expect(value.height >= 42 * textScale / 1.98,
                        "Connected percentage is too small: \(percentage), \(charging), \(textScale), height \(value.height)")
                    #expect(glyph.minY > 0, "Power glyph must not clip against the top of the icon")
                    bounds.append((glyph, value))
                }
                #expect(bounds[1].glyph.height > bounds[0].glyph.height * 1.1,
                    "Charging glyph must grow when the slider moves from 1.62 to 1.88")
                #expect(bounds[1].value.height > bounds[0].value.height * 1.1,
                    "Percentage must grow together with its charging glyph")
                #expect(bounds[2].glyph.height > bounds[1].glyph.height)
                #expect(bounds[2].value.height > bounds[1].value.height)
            }
        }
    }

    @Test
    func disablingIndicatorsKeepsContinuousBatteryTrack() throws {
        var appearance = SystemMonitorCombinedIconAppearance(
            showsBatteryPercentage: false, showsChargingIndicator: false,
            showsPercentageWhenConnected: false
        )
        let plain = try bitmap(battery: battery(), appearance: appearance)
        appearance.showsBatteryPercentage = true
        #expect(try bitmap(battery: battery(), appearance: appearance) != plain)
        appearance.showsBatteryPercentage = false
        appearance.showsChargingIndicator = true
        #expect(try bitmap(battery: battery(pluggedIn: true), appearance: appearance) != plain)
        appearance.showsChargingIndicator = false
        appearance.usesStatusColors = false
        #expect(try bitmap(battery: battery(pluggedIn: true), appearance: appearance) == plain)
    }

    @Test
    func missingBatteryDoesNotInventPercentageOrChargingGlyphs() throws {
        let plain = try bitmap(battery: nil, appearance: SystemMonitorCombinedIconAppearance())
        let configured = try bitmap(battery: nil, appearance: SystemMonitorCombinedIconAppearance(
            showsBatteryPercentage: true, showsChargingIndicator: true
        ))
        #expect(plain == configured)
        for level in [Double.nan, .infinity] {
            var snapshot = battery(charging: true, pluggedIn: true)
            snapshot.level = level
            #expect(try bitmap(battery: snapshot, appearance: SystemMonitorCombinedIconAppearance(
                showsBatteryPercentage: true, showsChargingIndicator: true
            )) == configured)
        }
    }

    @Test
    func continuousBottomArcIsNotFourStepQuantized() throws {
        let dots = SystemMonitorCombinedIconAppearance(indicatorStyle: .dots)
        let arc = SystemMonitorCombinedIconAppearance(indicatorStyle: .arc)
        #expect(try bitmap(level: 0.1, appearance: dots) == bitmap(level: 0.2, appearance: dots))
        #expect(try bitmap(level: 0.1, appearance: arc) != bitmap(level: 0.2, appearance: arc))
        #expect(try bitmap(level: 0.5, appearance: dots) != bitmap(level: 0.5, appearance: arc))
        #expect(try bitmap(level: nil, appearance: arc) == bitmap(level: 0, appearance: arc))
    }

    @Test
    func originalStrokeStylesAndSymbolScalesChangeRendering() throws {
        var appearance = SystemMonitorCombinedIconAppearance()
        var styles: [Data] = []
        for style in SystemMonitorMenuBarRingStrokeStyle.allCases {
            appearance.ringStrokeStyle = style
            styles.append(try bitmap(battery: battery(), level: 1, appearance: appearance))
        }
        #expect(Set(styles).count == 3)
        let standard = try bitmap(battery: battery(), appearance: appearance)
        appearance.wifiScale = 1.8
        #expect(try bitmap(battery: battery(), appearance: appearance) != standard)
        appearance.wifiScale = 1
        appearance.showsBatteryPercentage = true
        appearance.batteryTextScale = 1.62
        let small = try bitmap(battery: battery(), appearance: appearance)
        appearance.batteryTextScale = 1.98
        #expect(try bitmap(battery: battery(), appearance: appearance) != small)
    }

    @Test
    func personalHotspotUsesDistinctChainArtworkAtEveryNetworkScale() throws {
        let status = MenuBarIconStatus(battery: nil, wifi: .personalHotspot, level: nil)
        #expect(status.wifi.state == .personalHotspot)
        #expect(status.wifi.rssi == nil)
        for scale in [1.0, 1.3, 1.8] {
            let appearance = SystemMonitorCombinedIconAppearance(wifiScale: scale)
            let hotspot = try bitmap(wifi: .personalHotspot, appearance: appearance)
            for wifi in [MenuBarWiFiState.connected(strength: 1), .disconnected, .off, .unavailable] {
                #expect(hotspot != (try bitmap(wifi: wifi, appearance: appearance)))
            }
        }
    }

    @Test
    func personalHotspotRetainsConnectedHeadphoneReplacementPriority() {
        let status = MenuBarIconStatus(
            battery: nil, wifi: .personalHotspot, level: nil,
            headphones: MenuBarIconHeadphoneStatus(
                device: AudioOutputDevice(id: 1, name: "AirPods Pro", isBluetoothAudio: true),
                productID: nil, isVolumeMetric: false
            ),
            headphoneOptions: SystemMonitorHeadphoneOptions(
                replacesNetworkIcon: true, prioritizesNetworkErrors: true
            )
        )
        #expect(MenuBarIconMappings.shouldReplaceNetworkIcon(status: status))
    }

    @Test
    func normalizedSizeProducesBoundedRetinaBitmaps() throws {
        for (requested, expected) in [(0.0, 16), (36.0, 36), (10000.0, 36), (Double.nan, 26)] {
            var appearance = SystemMonitorCombinedIconAppearance()
            appearance.iconSize = requested
            let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: nil, wifi: .off, level: 1, foreground: .black, configuration: appearance
            ))
            #expect(image.size.width == CGFloat(expected))
            let data = try #require(image.tiffRepresentation)
            let representation = try #require(NSBitmapImageRep(data: data))
            #expect(representation.pixelsWide == expected * 2)
            #expect(representation.pixelsHigh == expected * 2)
        }
    }

    @Test
    func lowPowerColorRemainsYellowWithMonochromePreference() throws {
        var snapshot = battery(charging: true, pluggedIn: true)
        snapshot.level = 0.1
        snapshot.isLowPowerMode = true
        let appearance = SystemMonitorCombinedIconAppearance(usesStatusColors: false)
        for foreground in [NSColor.black, .white] {
            let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: snapshot, wifi: .connected(strength: 1), level: 0,
                foreground: foreground, configuration: appearance
            ))
            let data = try #require(image.tiffRepresentation)
            let representation = try #require(NSBitmapImageRep(data: data))
            var yellow = 0
            for horizontal in 0..<representation.pixelsWide {
                for vertical in 0..<representation.pixelsHigh {
                    guard let color = representation.colorAt(x: horizontal, y: vertical)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.alphaComponent > 0.5 && color.redComponent > 0.6
                        && color.greenComponent > 0.5 && color.blueComponent < 0.1 {
                        yellow += 1
                    }
                }
            }
            #expect(yellow > 8)
        }
    }

    @Test
    func lazyImageResolvesColorsInEachDrawingAppearance() throws {
        let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: nil, wifi: .connected(strength: 1), level: 1
        ))
        let light = try draw(image, appearance: .aqua)
        let dark = try draw(image, appearance: .darkAqua)
        #expect(light != dark)
        #expect(!image.isTemplate)
    }

    private func bitmap(
        battery: BatterySnapshot? = nil,
        wifi: MenuBarWiFiState = .connected(strength: 1),
        level: Double? = 0.5,
        appearance: SystemMonitorCombinedIconAppearance
    ) throws -> Data {
        let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: battery, wifi: wifi, level: level,
            foreground: .black, configuration: appearance
        ))
        return try #require(image.tiffRepresentation)
    }

    private func draw(_ image: NSImage, appearance: NSAppearance.Name) throws -> Data {
        let representation = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let graphicsContext = try #require(NSGraphicsContext(bitmapImageRep: representation))
        let drawingAppearance = try #require(NSAppearance(named: appearance))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphicsContext
        drawingAppearance.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(x: 0, y: 0, width: 44, height: 44))
        }
        return try #require(representation.representation(using: .png, properties: [:]))
    }

    private func battery(charging: Bool = false, pluggedIn: Bool = false) -> BatterySnapshot {
        BatterySnapshot(level: 0.7, isCharging: charging, isPluggedIn: pluggedIn, isCharged: false, timeRemainingMinutes: nil)
    }
}
