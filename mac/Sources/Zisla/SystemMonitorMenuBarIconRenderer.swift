import AppKit
import CoreGraphics
import CoreText
import ZislaCore

// Modified for Zisla; source revision and adaptation details are in ThirdPartyLicenses/README.md.
enum SystemMonitorMenuBarIconRenderer {
    static let centerSymbolBasePointSize: CGFloat = 38

    /// Anchored to the artwork's centre, not the canvas midpoint: the vector
    /// art is drawn on a 119-unit box centred at 59.5, so `canvas.midX` (60.0)
    /// puts every SF Symbol half a unit right of it. See issue #30.
    private static let wifiSymbolCenter = CGPoint(
        x: SystemMonitorMenuBarIconGeometry.artworkCenterX,
        y: 64.0
    )

    /// Unified optical alpha for all inactive tracks (battery groove, Wi-Fi muted signal, volume hidden dots).
    private static let inactiveTrackAlpha: CGFloat = 0.22
    private static let bluetoothBlueOnLightBackground = CGColor(
        red: 0, green: 102.0 / 255.0, blue: 204.0 / 255.0, alpha: 1
    )
    private static let bluetoothBlueOnDarkBackground = CGColor(
        red: 77.0 / 255.0, green: 163.0 / 255.0, blue: 1, alpha: 1
    )

    static func image(
        status: MenuBarIconStatus,
        configuration: SystemMonitorCombinedIconAppearance,
        foreground: NSColor? = nil
    ) -> NSImage? {
        let configuration = configuration.normalized
        let size = CGFloat(configuration.iconSize)
        let options = MenuBarIconBatteryOptions(appearance: configuration)
        let connectionOptions = MenuBarIconConnectionOptions(appearance: configuration)
        let volumeOptions = MenuBarIconVolumeOptions(appearance: configuration)
        if let foreground {
            guard let rendered = render(
                menuBarStatus: status,
                size: size,
                scale: 2,
                foreground: foreground.usingColorSpace(.deviceRGB)?.cgColor ?? CGColor(gray: 1, alpha: 1),
                options: options,
                connectionOptions: connectionOptions,
                volumeOptions: volumeOptions
            ) else { return nil }
            return NSImage(cgImage: rendered, size: NSSize(width: size, height: size))
        }
        return dynamicImage(
            menuBarStatus: status,
            size: size,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions
        )
    }

    private static func dynamicImage(
        menuBarStatus: MenuBarIconStatus,
        size: CGFloat,
        options: MenuBarIconBatteryOptions,
        connectionOptions: MenuBarIconConnectionOptions,
        volumeOptions: MenuBarIconVolumeOptions
    ) -> NSImage {
        // Resolve colors while AppKit draws into each menu bar. A pre-rendered
        // bitmap would keep the first display's light or dark foreground.
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                ?? CGColor(gray: 1, alpha: 1)
            let criticalColor = NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                ?? Self.defaultCriticalColor

            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(
                menuBarStatus: menuBarStatus,
                options: options,
                connectionOptions: connectionOptions,
                volumeOptions: volumeOptions,
                in: context,
                size: size,
                foreground: foreground,
                criticalColor: criticalColor
            )
            return true
        }
    }

    static func render(
        menuBarStatus: MenuBarIconStatus,
        size: CGFloat,
        scale: CGFloat,
        foreground: CGColor,
        criticalColor: CGColor? = nil,
        options: MenuBarIconBatteryOptions,
        connectionOptions: MenuBarIconConnectionOptions,
        volumeOptions: MenuBarIconVolumeOptions
    ) -> CGImage? {
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }

        let pixelLength = (size * scale).rounded(.up)
        guard pixelLength.isFinite,
              let pixelDimension = Int(exactly: pixelLength),
              pixelDimension > 0,
              pixelDimension <= Int.max / 4
        else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: pixelDimension,
            height: pixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: pixelDimension * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        draw(
            menuBarStatus: menuBarStatus,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            in: context,
            size: size,
            foreground: foreground,
            criticalColor: criticalColor ?? defaultCriticalColor
        )
        return context.makeImage()
    }

    private static func draw(
        menuBarStatus: MenuBarIconStatus,
        options: MenuBarIconBatteryOptions,
        connectionOptions: MenuBarIconConnectionOptions,
        volumeOptions: MenuBarIconVolumeOptions,
        in context: CGContext,
        size: CGFloat,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / SystemMonitorMenuBarIconGeometry.canvas.width
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: scale, y: -scale)

        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawBattery(
            menuBarStatus.battery,
            options: options,
            in: context,
            foreground: foreground,
            criticalColor: criticalColor
        )
        if MenuBarIconMappings.shouldReplaceNetworkIcon(status: menuBarStatus),
           let headphones = menuBarStatus.headphones {
            drawBluetoothAudioDevice(
                headphones.source,
                options: menuBarStatus.headphoneOptions,
                in: context,
                foreground: foreground
            )
        } else {
            drawWiFi(
                menuBarStatus.wifi,
                options: connectionOptions,
                in: context,
                foreground: foreground
            )
        }
        drawVolume(
            menuBarStatus.volume,
            options: volumeOptions,
            in: context,
            foreground: foreground,
            usesBluetoothColor: menuBarStatus.headphoneOptions.usesVolumeColor
                && menuBarStatus.headphones?.device.isBluetoothAudio == true
                && menuBarStatus.headphones?.isVolumeMetric == true
        )
    }

    private static func drawBattery(
        _ battery: MenuBarIconBatteryStatus,
        options: MenuBarIconBatteryOptions,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        let gapContent = MenuBarIconMappings.batteryGapContent(battery, options: options)
        let hasTopGap = gapContent != .empty
        let topGapWidth = switch gapContent {
        case .bolt, .plug: SystemMonitorMenuBarIconGeometry.batteryChargingBoltTopGapWidth
        case .percentage, .empty: SystemMonitorMenuBarIconGeometry.batteryValueTopGapWidth
        }

        context.setLineWidth(8 * CGFloat(options.ringStrokeScale))
        context.setStrokeColor(foreground.copy(alpha: inactiveTrackAlpha) ?? foreground)
        context.addPath(SystemMonitorMenuBarIconGeometry.batteryTrack(
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        ))
        context.strokePath()

        let role = battery.isLowPowerMode || options.usesStatusColors
            ? MenuBarIconMappings.batteryColorRole(
                battery,
                criticalThreshold: options.criticalThreshold
            )
            : .foreground
        let arcColor = color(
            for: role,
            foreground: foreground,
            criticalColor: criticalColor
        )

        context.setStrokeColor(arcColor)
        context.addPath(SystemMonitorMenuBarIconGeometry.batteryFill(
            progress: MenuBarIconMappings.batteryProgress(battery),
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        ))
        context.strokePath()

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 0.75),
            blur: 0.75,
            color: CGColor(gray: 0, alpha: 0.38)
        )
        defer { context.restoreGState() }

        let indicatorScale = batteryChargingBoltScale(textScale: options.textScale)

        switch gapContent {
        case .bolt:
            let baseBolt = SystemMonitorMenuBarIconGeometry.batteryChargingBolt(scale: indicatorScale)
            context.setFillColor(foreground)
            context.addPath(baseBolt)
            context.fillPath()
        case .plug:
            drawBatteryPlug(
                boltScale: indicatorScale,
                foreground: foreground,
                in: context
            )
        case .percentage:
            drawBatteryPercentage(
                battery.percentage,
                color: foreground,
                fontSize: batteryValueFontSize(scale: options.textScale),
                in: context
            )
        case .empty:
            break
        }
    }

    /// Draws the plug at the bolt's optical size and center, so the arc's top
    /// gap reads the same whichever indicator is showing.
    private static func drawBatteryPlug(
        boltScale: CGFloat,
        foreground: CGColor,
        in context: CGContext
    ) {
        let boltHeight = SystemMonitorMenuBarIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        let targetHeight = boltHeight * boltScale * SystemMonitorMenuBarIconGeometry.batteryPlugHeightScale
        guard targetHeight.isFinite, targetHeight > 0 else { return }

        drawOfficialSymbol(
            name: SystemMonitorMenuBarIconGeometry.batteryPlugSymbolName,
            pointSize: batteryPlugPointSize(targetHeight: targetHeight),
            center: SystemMonitorMenuBarIconGeometry.batteryTopIndicatorCenter(boltScale: boltScale),
            foreground: foreground,
            in: context
        )
    }

    private static func color(
        for role: MenuBarIconBatteryColorRole,
        foreground: CGColor,
        criticalColor: CGColor
    ) -> CGColor {
        switch role {
        case .foreground:
            foreground
        case .critical:
            criticalColor
        case .charging:
            if usesDarkStatusPalette(foreground: foreground) {
                CGColor(red: 31.0 / 255.0, green: 143.0 / 255.0, blue: 61.0 / 255.0, alpha: 1)
            } else {
                CGColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1)
            }
        case .lowPower:
            if usesDarkStatusPalette(foreground: foreground) {
                CGColor(red: 201.0 / 255.0, green: 151.0 / 255.0, blue: 0, alpha: 1)
            } else {
                CGColor(red: 242.0 / 255.0, green: 185.0 / 255.0, blue: 0, alpha: 1)
            }
        }
    }

    private static func usesDarkStatusPalette(foreground: CGColor) -> Bool {
        guard let color = NSColor(cgColor: foreground)?.usingColorSpace(.deviceRGB) else {
            return false
        }
        return color.brightnessComponent < 0.5
    }

    private static func bluetoothColor(foreground: CGColor) -> CGColor {
        usesDarkStatusPalette(foreground: foreground)
            ? bluetoothBlueOnLightBackground
            : bluetoothBlueOnDarkBackground
    }

    private static func drawBluetoothAudioDevice(
        _ source: MenuBarIconHeadphoneSource,
        options: SystemMonitorHeadphoneOptions,
        in context: CGContext,
        foreground: CGColor
    ) {
        let tint = bluetoothColor(foreground: foreground)
        let pointSize = centerSymbolPointSize(for: options.symbolScale)
        let scale = pointSize / centerSymbolBasePointSize
        let maxDimension = 42 * scale

        switch source {
        case let .symbol(name):
            drawOfficialSymbol(name: name, pointSize: pointSize, foreground: tint, in: context)
        case let .image(url):
            guard let image = NSImage(contentsOf: url) else {
                drawOfficialSymbol(name: "headphones", pointSize: pointSize, foreground: tint, in: context)
                return
            }
            drawTintedImage(image, maxDimension: maxDimension, center: wifiSymbolCenter, tint: tint, in: context)
        }
    }

    private static func drawTintedImage(
        _ image: NSImage,
        maxDimension: CGFloat,
        center: CGPoint,
        tint: CGColor,
        in context: CGContext
    ) {
        let sourceSize = image.size
        guard sourceSize.width.isFinite, sourceSize.height.isFinite,
              sourceSize.width > 0, sourceSize.height > 0 else { return }
        let scale = min(maxDimension / sourceSize.width, maxDimension / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let targetRect = CGRect(
            x: center.x - size.width / 2, y: -(center.y + size.height / 2),
            width: size.width, height: size.height
        )
        context.saveGState()
        defer { context.restoreGState() }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        context.scaleBy(x: 1, y: -1)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        image.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1)
        context.setFillColor(tint)
        context.setBlendMode(.sourceIn)
        context.fill(targetRect)
        context.endTransparencyLayer()
    }
    private static func drawBatteryPercentage(
        _ percentage: Int,
        color: CGColor,
        fontSize: CGFloat,
        in context: CGContext
    ) {
        let font = batteryValueFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: -fontSize * 0.04,
            .foregroundColor: NSColor(cgColor: color) ?? .white
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: String(percentage), attributes: attributes)
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let baseline = SystemMonitorMenuBarIconGeometry.batteryValueBaseline(fontSize: fontSize)

        context.setFillColor(color)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: baseline.x - width / 2, y: baseline.y)
        CTLineDraw(line, context)
    }
    private static func batteryValueFontSize(scale: Double) -> CGFloat {
        SystemMonitorMenuBarIconGeometry.batteryValueBaseFontSize * CGFloat(scale)
    }

    static func batteryChargingBoltScale(textScale: Double) -> CGFloat {
        let boltHeight = SystemMonitorMenuBarIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        let targetHeight = batteryTopIndicatorHeight(textScale: textScale)
        guard boltHeight.isFinite, boltHeight > 0, targetHeight > 0 else {
            return CGFloat(textScale / MenuBarIconBatteryOptions.defaultTextScale)
                * SystemMonitorMenuBarIconGeometry.batteryChargingBoltCalibration
        }
        return targetHeight / boltHeight
    }

    /// Height shared by every top-gap glyph. The bolt is calibrated to match the
    /// percentage numerals, and the plug matches the bolt.
    private static func batteryTopIndicatorHeight(textScale: Double) -> CGFloat {
        let fontSize = batteryValueFontSize(scale: textScale)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: "100",
                attributes: [.font: batteryValueFont(size: fontSize)]
            )
        )
        let glyphHeight = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).height
        guard glyphHeight.isFinite, glyphHeight > 0 else {
            return SystemMonitorMenuBarIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
                * CGFloat(textScale / MenuBarIconBatteryOptions.defaultTextScale)
                * SystemMonitorMenuBarIconGeometry.batteryChargingBoltCalibration
        }
        return CGFloat(glyphHeight) * SystemMonitorMenuBarIconGeometry.batteryChargingBoltCalibration
    }

    /// Glyph height per point of symbol size, measured once. SF Symbols report
    /// sizes rounded to whole points, so this reference size stays large enough
    /// for the rounding to be negligible.
    private static let batteryPlugHeightPerPoint: CGFloat = {
        let referencePointSize: CGFloat = 200
        guard let height = configuredSymbol(
            name: SystemMonitorMenuBarIconGeometry.batteryPlugSymbolName,
            pointSize: referencePointSize,
            foreground: .labelColor
        )?.size.height, height.isFinite, height > 0 else {
            return 1.34
        }
        return height / referencePointSize
    }()

    private static func batteryPlugPointSize(targetHeight: CGFloat) -> CGFloat {
        let fallbackPointSize: CGFloat = 38
        let pointSize = targetHeight / batteryPlugHeightPerPoint
        return pointSize.isFinite && pointSize > 0 ? pointSize : fallbackPointSize
    }

    private static var defaultCriticalColor: CGColor {
        CGColor(red: 255.0 / 255.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
    }

    private static func batteryValueFont(size: CGFloat) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = fallback.fontDescriptor.withDesign(.rounded) else {
            return fallback
        }
        return NSFont(descriptor: descriptor, size: size) ?? fallback
    }
    private static func drawWiFi(
        _ wifi: MenuBarIconWiFiStatus,
        options: MenuBarIconConnectionOptions,
        in context: CGContext,
        foreground: CGColor
    ) {
        let symbolPointSize = centerSymbolPointSize(for: options.wifiScale)

        switch wifi.state {
        case .connected:
            drawStandardWiFi(wifi, wifiScale: options.wifiScale, in: context, foreground: foreground)
        case .notAssociated:
            drawOfficialSymbol(
                name: "wifi",
                variableValue: 0.0,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        case .off, .unavailable:
            drawOfficialSymbol(
                name: "wifi.slash",
                variableValue: 1.0,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        }
    }

    static func centerSymbolPointSize(for wifiScale: Double) -> CGFloat {
        guard wifiScale.isFinite, wifiScale > 0 else {
            return centerSymbolBasePointSize
        }
        return centerSymbolBasePointSize * CGFloat(wifiScale)
    }

    private static func drawStandardWiFi(
        _ wifi: MenuBarIconWiFiStatus,
        wifiScale: Double = 1.0,
        in context: CGContext,
        foreground: CGColor
    ) {
        let symbolPointSize = centerSymbolPointSize(for: wifiScale)
        let bars = MenuBarIconMappings.wifiBars(rssi: wifi.rssi)
        if bars == 0 {
            let mutedColor = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
            drawOfficialSymbol(
                name: "wifi",
                variableValue: 0.0,
                pointSize: symbolPointSize,
                foreground: mutedColor,
                in: context
            )
        } else {
            let variableValue: Double = switch bars {
            case 3: 1.0
            case 2: 0.66
            case 1: 0.33
            default: 0.0
            }
            drawOfficialSymbol(
                name: "wifi",
                variableValue: variableValue,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        }
    }

    private static func drawOfficialSymbol(
        name: String,
        variableValue: Double = 1.0,
        pointSize: CGFloat,
        center: CGPoint = wifiSymbolCenter,
        foreground: CGColor,
        in context: CGContext
    ) {
        guard let symbol = configuredSymbol(
            name: name,
            variableValue: variableValue,
            pointSize: pointSize,
            foreground: NSColor(cgColor: foreground) ?? .labelColor
        ) else { return }

        context.saveGState()
        defer { context.restoreGState() }

        let gc = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = gc

        context.scaleBy(x: 1, y: -1)

        let targetRect = CGRect(
            x: center.x - symbol.size.width / 2,
            y: -(center.y + symbol.size.height / 2),
            width: symbol.size.width,
            height: symbol.size.height
        )
        symbol.draw(in: targetRect)
    }

    private static func configuredSymbol(
        name: String,
        variableValue: Double = 1.0,
        pointSize: CGFloat,
        foreground: NSColor
    ) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(hierarchicalColor: foreground))

        return NSImage(
            systemSymbolName: name,
            variableValue: variableValue,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config)
    }
    private static func drawVolume(
        _ volume: MenuBarIconVolumeStatus,
        options: MenuBarIconVolumeOptions,
        in context: CGContext,
        foreground: CGColor,
        usesBluetoothColor: Bool
    ) {
        let hiddenColor = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
        let activeColor = usesBluetoothColor ? bluetoothColor(foreground: foreground) : foreground

        switch options.displayStyle {
        case .dots:
            let level = MenuBarIconMappings.volumeSteps(scalar: volume.scalar, isMuted: volume.isMuted) ?? 0
            let radius = SystemMonitorMenuBarIconGeometry.volumeDotRadius * CGFloat(options.dotRadiusScale)
            for (index, point) in SystemMonitorMenuBarIconGeometry.volumeDots().enumerated() {
                context.setFillColor(index < level ? activeColor : hiddenColor)
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }
        case .arc:
            // Continuous arc bounded between Dot 0 (left, ~122°) and Dot 3 (right, ~59°)
            context.setLineWidth(7 * CGFloat(options.ringStrokeScale))
            context.setLineCap(.round)
            context.setStrokeColor(hiddenColor)
            context.addPath(SystemMonitorMenuBarIconGeometry.volumeArcTrack())
            context.strokePath()

            guard !volume.isMuted, let scalar = volume.scalar, scalar > 0 else { return }
            context.setStrokeColor(activeColor)
            context.addPath(SystemMonitorMenuBarIconGeometry.volumeArcFill(progress: scalar))
            context.strokePath()
        }
    }
}
