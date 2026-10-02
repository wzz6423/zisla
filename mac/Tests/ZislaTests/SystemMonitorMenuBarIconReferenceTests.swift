import AppKit
import CoreGraphics
import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite("Menu bar icon reference: 2b0571a51c70fab0f1176db1eb0c32a8d7f2b4ad")
struct SystemMonitorMenuBarIconReferenceTests {
    @Test
    func batteryArcMatchesOriginalSVGEndpointsAndProgress() {
        #expect(SystemMonitorMenuBarIconGeometry.canvas == CGRect(x: 0, y: 0, width: 120, height: 120))
        #expect(SystemMonitorMenuBarIconGeometry.artworkCenterX == 59.5)
        let start = SystemMonitorMenuBarIconGeometry.batteryPoint(forProgress: 0)
        let end = SystemMonitorMenuBarIconGeometry.batteryPoint(forProgress: 1)
        #expect(abs(start.x - 15.5) < 1e-10)
        #expect(abs(start.y - 88.25) < 1e-10)
        #expect(abs(end.x - 103.5) < 1e-10)
        #expect(abs(end.y - 88.25) < 1e-10)
        for progress in [0.0, 0.125, 0.25, 0.5, 0.75, 1] {
            let angle = (148.69008689281117 + 242.6198262143777 * progress) * .pi / 180
            let point = SystemMonitorMenuBarIconGeometry.batteryPoint(forProgress: progress)
            #expect(abs(point.x - (59.5 + 51.5 * cos(angle))) < 1e-10)
            #expect(abs(point.y - (61.48715261785473 + 51.5 * sin(angle))) < 1e-10)
            #expect(Self.elements(SystemMonitorMenuBarIconGeometry.batteryFill(progress: progress))
                == Self.elements(Self.batteryPath(progress: progress)))
        }
        #expect(Self.elements(SystemMonitorMenuBarIconGeometry.batteryTrack())
            == Self.elements(Self.batteryPath(progress: 1)))
    }

    @Test
    func batteryTopGapsRetainOriginalSVGSegments() {
        #expect(SystemMonitorMenuBarIconGeometry.batteryChargingBoltTopGapWidth == 50)
        #expect(SystemMonitorMenuBarIconGeometry.batteryValueTopGapWidth == 64)
        for width in [CGFloat(50), 64] {
            let gapFraction = Double(width / (51.5 * (242.6198262143777 * .pi / 180)))
            let gapStart = (1 - gapFraction) / 2
            let gapEnd = 1 - gapStart
            for progress in [0, 0.25, gapStart, 0.5, gapEnd, 0.75, 1] {
                let actual = SystemMonitorMenuBarIconGeometry.batteryFill(
                    progress: progress, hasTopGap: true, topGapWidth: width
                )
                #expect(Self.elements(actual) == Self.elements(Self.batteryPath(progress: progress, gapWidth: width)))
            }
            #expect(Self.elements(SystemMonitorMenuBarIconGeometry.batteryTrack(hasTopGap: true, topGapWidth: width))
                == Self.elements(Self.batteryPath(progress: 1, gapWidth: width)))
            #expect(SystemMonitorMenuBarIconGeometry.batteryFill(progress: 0.5, hasTopGap: true, topGapWidth: width)
                == SystemMonitorMenuBarIconGeometry.batteryFill(progress: gapStart, hasTopGap: true, topGapWidth: width))
        }
    }

    @Test
    func bottomDotsAndArcRetainOriginalCoordinates() {
        #expect(SystemMonitorMenuBarIconGeometry.volumeDots() == Self.referenceDots)
        #expect(SystemMonitorMenuBarIconGeometry.volumeDotRadius == 5.5)
        #expect(SystemMonitorMenuBarIconGeometry.volumeArcStartAngle == 121.82 * .pi / 180)
        #expect(SystemMonitorMenuBarIconGeometry.volumeArcEndAngle == 59.12 * .pi / 180)
        #expect(Self.elements(SystemMonitorMenuBarIconGeometry.volumeArcTrack())
            == Self.elements(Self.indicatorPath(progress: 1)))
        for progress in [0.0, 0.125, 0.25, 0.5, 0.75, 1] {
            #expect(Self.elements(SystemMonitorMenuBarIconGeometry.volumeArcFill(progress: progress))
                == Self.elements(Self.indicatorPath(progress: progress)))
        }
    }

    @Test
    func officialWiFiProportionsAndSignalThresholdsMatchReference() {
        #expect(SystemMonitorMenuBarIconRenderer.centerSymbolBasePointSize == 38)
        for scale in [1.0, 1.3, 1.8] {
            #expect(SystemMonitorMenuBarIconRenderer.centerSymbolPointSize(for: scale) == 38 * CGFloat(scale))
        }
        for (rssi, bars) in [(Int?.none, 0), (-89, 0), (-88, 1), (-79, 1), (-78, 2), (-61, 2), (-60, 3), (-50, 3)] {
            #expect(MenuBarIconMappings.wifiBars(rssi: rssi) == bars)
        }
        for (scalar, steps) in [(Double?.none, Int?.none), (0, 0), (0.25, 1), (0.2501, 2), (0.5, 2), (0.5001, 3), (0.75, 3), (0.7501, 4), (1, 4)] {
            #expect(MenuBarIconMappings.volumeSteps(scalar: scalar, isMuted: false) == steps)
        }
    }

    @Test @MainActor
    func pixelsMatchIndependentSVGAndOfficialWiFiReference() throws {
        let wifiCases: [(MenuBarWiFiState, ReferenceSymbol)] = [
            (.connected(strength: 0.2), ReferenceSymbol(name: "wifi", value: 0, alpha: 0.22)),
            (.connected(strength: 0.24), ReferenceSymbol(name: "wifi", value: 0.33)),
            (.connected(strength: 0.44), ReferenceSymbol(name: "wifi", value: 0.66)),
            (.connected(strength: 1), ReferenceSymbol(name: "wifi", value: 1)),
            (.personalHotspot, ReferenceSymbol(name: "personalhotspot", value: 1)),
            (.disconnected, ReferenceSymbol(name: "wifi", value: 0)),
            (.off, ReferenceSymbol(name: "wifi.slash", value: 1)),
            (.unavailable, ReferenceSymbol(name: "wifi.slash", value: 1)),
        ]
        for (wifi, symbol) in wifiCases {
            for wifiScale in [1.0, 1.8] {
                for scale in [CGFloat(1), 2] {
                    let appearance = SystemMonitorCombinedIconAppearance(
                        ringStrokeStyle: .regular, showsBatteryPercentage: false,
                        showsChargingIndicator: false, showsPercentageWhenConnected: false,
                        usesStatusColors: false, wifiScale: wifiScale
                    )
                    let status = Self.status(batteryLevel: 0.5, wifi: wifi, level: 0.5)
                    let actual = try Self.render(status, appearance: appearance, size: 22, scale: scale)
                    let reference = try Self.referenceImage(size: 22, scale: scale, progress: 0.5,
                        strokeScale: 1.25, style: .dots, level: 0.5, symbol: symbol, wifiScale: wifiScale)
                    #expect(try Self.pixels(actual) == Self.pixels(reference), "SF Symbol mismatch: \(symbol.name), \(symbol.value), \(wifiScale)x at \(scale)x")
                }
            }
        }
        for strokeStyle in SystemMonitorMenuBarRingStrokeStyle.allCases {
            let strokeScale: Double = switch strokeStyle {
            case .light: 1
            case .regular: 1.25
            case .bold: 1.5
            }
            for style in SystemMonitorMenuBarIndicatorStyle.allCases {
                for progress in [0.0, 0.25, 0.5, 1] {
                    for level in [0.0, 0.25, 0.5001, 1] {
                        let appearance = SystemMonitorCombinedIconAppearance(
                            ringStrokeStyle: strokeStyle, indicatorStyle: style,
                            showsBatteryPercentage: false, showsChargingIndicator: false,
                            showsPercentageWhenConnected: false, usesStatusColors: false, wifiScale: 1
                        )
                        let actual = try Self.render(Self.status(batteryLevel: progress, wifi: .connected(strength: 1), level: level),
                            appearance: appearance, size: 22, scale: 2)
                        let reference = try Self.referenceImage(size: 22, scale: 2, progress: progress,
                            strokeScale: strokeScale, style: style, level: level, symbol: ReferenceSymbol(name: "wifi", value: 1))
                        #expect(try Self.pixels(actual) == Self.pixels(reference), "SVG raster mismatch: \(strokeStyle), \(style), battery \(progress), indicator \(level)")
                    }
                }
            }
        }
    }

    private struct PathElement: Equatable {
        let type: Int
        let points: [CGPoint]
    }

    private struct ReferenceSymbol {
        let name: String
        let value: Double
        var alpha: CGFloat = 1
    }

    private static let referenceDots = [
        CGPoint(x: 33, y: 104.2), CGPoint(x: 50.5, y: 111.2),
        CGPoint(x: 68.5, y: 111.7), CGPoint(x: 86, y: 105.8),
    ]

    private static func elements(_ path: CGPath) -> [PathElement] {
        var result: [PathElement] = []
        path.applyWithBlock { element in
            let count: Int = switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            case .closeSubpath: 0
            @unknown default: -1
            }
            result.append(PathElement(type: Int(element.pointee.type.rawValue),
                points: count >= 0 ? Array(UnsafeBufferPointer(start: element.pointee.points, count: count)) : []))
        }
        return result
    }

    private static func batteryPath(progress: Double, gapWidth: CGFloat = 0) -> CGPath {
        let start: CGFloat = 148.69008689281117 * .pi / 180
        let sweep: CGFloat = 242.6198262143777 * .pi / 180
        let path = CGMutablePath()
        guard progress > 0 else { return path }
        let gap = Double(gapWidth / (51.5 * sweep))
        let intervals: [(Double, Double)] = gapWidth > 0
            ? [(0, min(progress, (1 - gap) / 2)), ((1 + gap) / 2, progress)]
            : [(0, progress)]
        for (lower, upper) in intervals where upper > lower {
            let segment = CGMutablePath()
            segment.addArc(center: CGPoint(x: 59.5, y: 61.48715261785473), radius: 51.5,
                startAngle: start + sweep * lower, endAngle: start + sweep * upper, clockwise: false)
            path.addPath(segment)
        }
        return path
    }

    private static func indicatorPath(progress: Double) -> CGPath {
        let path = CGMutablePath()
        guard progress > 0 else { return path }
        let start: CGFloat = 121.82 * .pi / 180
        let end: CGFloat = 59.12 * .pi / 180
        path.addArc(center: CGPoint(x: 59.5, y: 61.48715261785473), radius: 51.5,
            startAngle: start, endAngle: start - (start - end) * progress, clockwise: true)
        return path
    }

    private static func status(batteryLevel: Double, wifi: MenuBarWiFiState, level: Double) -> MenuBarIconStatus {
        MenuBarIconStatus(battery: BatterySnapshot(level: batteryLevel, isCharging: false,
            isPluggedIn: false, isCharged: false, timeRemainingMinutes: nil), wifi: wifi, level: level)
    }

    @MainActor
    private static func render(_ status: MenuBarIconStatus, appearance: SystemMonitorCombinedIconAppearance,
        size: CGFloat, scale: CGFloat) throws -> CGImage {
        try #require(SystemMonitorMenuBarIconRenderer.render(menuBarStatus: status, size: size, scale: scale,
            foreground: CGColor(red: 0, green: 0, blue: 0, alpha: 1), options: MenuBarIconBatteryOptions(appearance: appearance),
            connectionOptions: MenuBarIconConnectionOptions(appearance: appearance), volumeOptions: MenuBarIconVolumeOptions(appearance: appearance)))
    }

    @MainActor
    private static func referenceImage(size: CGFloat, scale: CGFloat, progress: Double, strokeScale: Double,
        style: SystemMonitorMenuBarIndicatorStyle, level: Double, symbol: ReferenceSymbol, wifiScale: Double = 1) throws -> CGImage {
        let dimension = Int((size * scale).rounded(.up))
        let context = try #require(CGContext(data: nil, width: dimension, height: dimension, bitsPerComponent: 8,
            bytesPerRow: dimension * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: size / 120, y: -size / 120)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let foreground = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let inactive = try #require(foreground.copy(alpha: 0.22))
        context.setLineWidth(8 * strokeScale)
        context.setStrokeColor(inactive)
        context.addPath(Self.batteryPath(progress: 1))
        context.strokePath()
        context.setStrokeColor(foreground)
        context.addPath(Self.batteryPath(progress: progress))
        context.strokePath()
        let symbolColor = try #require(foreground.copy(alpha: symbol.alpha))
        let symbolForeground = try #require(NSColor(cgColor: symbolColor))
        let configuration = NSImage.SymbolConfiguration(pointSize: 38 * wifiScale, weight: .semibold)
            .applying(.init(hierarchicalColor: symbolForeground))
        let image = try #require(NSImage(systemSymbolName: symbol.name, variableValue: symbol.value,
            accessibilityDescription: nil)?.withSymbolConfiguration(configuration))
        context.saveGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        context.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect(x: 59.5 - image.size.width / 2, y: -(64 + image.size.height / 2),
            width: image.size.width, height: image.size.height))
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
        switch style {
        case .dots:
            let steps = Int(ceil(level * 4))
            let radius = 5.5 * (1 + (strokeScale - 1) * 0.5)
            for (index, point) in Self.referenceDots.enumerated() {
                context.setFillColor(index < steps ? foreground : inactive)
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            }
        case .arc:
            context.setLineWidth(7 * strokeScale)
            context.setStrokeColor(inactive)
            context.addPath(Self.indicatorPath(progress: 1))
            context.strokePath()
            if level > 0 {
                context.setStrokeColor(foreground)
                context.addPath(Self.indicatorPath(progress: level))
                context.strokePath()
            }
        }
        return try #require(context.makeImage())
    }

    private static func pixels(_ image: CGImage) throws -> Data {
        try #require(image.dataProvider?.data) as Data
    }
}
