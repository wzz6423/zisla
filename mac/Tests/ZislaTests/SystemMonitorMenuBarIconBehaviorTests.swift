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
        #expect(try bitmap(battery: battery(pluggedIn: true), appearance: appearance) == percentage)
        #expect(try bitmap(battery: battery(charging: true, pluggedIn: true), appearance: appearance) == charging)
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
        for (requested, expected) in [(0.0, 16), (36.0, 36), (10000.0, 36), (Double.nan, 22)] {
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
