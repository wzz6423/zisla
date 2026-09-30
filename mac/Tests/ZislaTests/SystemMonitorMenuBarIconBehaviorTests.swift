import AppKit
import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct SystemMonitorMenuBarIconBehaviorTests {
    @Test
    func topIndicatorUsesPercentageBoltAndPlugStates() throws {
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
        #expect(try bitmap(battery: battery(pluggedIn: true), appearance: appearance) != percentage)
        #expect(try bitmap(battery: battery(charging: true, pluggedIn: true), appearance: appearance) == charging)
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
                                : (value && connectedValue ? .plugAndPercentage : .plug)
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
            for (percentage, indicator) in [0, 9, 70, 100].flatMap({ value in [false, true].map { (value, $0) } }) {
                for textScale in [1.62, 1.8, 1.98] {
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
                            for x in 0..<44 {
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
                        #expect(headerWidth <= 26, "Header must fit inside the ring rather than erase its upper half")
                        if indicator && percentage == 100 {
                            #expect(header.filter { $0.x < 16 }.count > 3, "Power glyph must remain visible left of 100")
                            #expect(header.filter { $0.x > 22 }.count > 5, "Percentage must remain visible right of the power glyph")
                        }
                        for glyph in header {
                            #expect(glyph.x > 0 && glyph.x < 43)
                            for arc in ring {
                                #expect(hypot(glyph.x - arc.x, glyph.y - arc.y) >= 2,
                                    "Header touches ring: \(percentage), \(charging), \(textScale), \(stroke)")
                            }
                        }
                    }
                }
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
    func normalizedSizeProducesBoundedRetinaBitmaps() throws {
        for (requested, expected) in [(0.0, 16), (36.0, 36), (10000.0, 36), (Double.nan, 24)] {
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
        level: Double? = 0.5,
        appearance: SystemMonitorCombinedIconAppearance
    ) throws -> Data {
        let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: battery, wifi: .connected(strength: 1), level: level,
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
