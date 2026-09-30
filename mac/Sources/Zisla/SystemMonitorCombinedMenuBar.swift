import AppKit
import ZislaCore
import ZislaKit

enum SystemMonitorCombinedMenuBarPresentation {
    static func rows(
        top: [SystemMonitorMenuBarMetric],
        bottom: [SystemMonitorMenuBarMetric],
        snapshot: SystemMetricsSnapshot?,
        style: SystemMonitorMenuBarDisplayStyle
    ) -> [String] {
        SystemMonitorMenuBarRows.normalized(top: top, bottom: bottom).map { metrics in
            metrics.map { metric in
                let label = style == .compact ? shortLabel(metric) : SystemMonitorMenuBarPresentation.label(for: metric)
                return "\(label) \(value(metric, snapshot: snapshot))"
            }.joined(separator: "  ")
        }
    }

    static func shortLabel(_ metric: SystemMonitorMenuBarMetric) -> String {
        switch metric {
        case .cpu: "C"
        case .gpu: "G"
        case .memory: "M"
        case .disk: "D"
        case .network: "N"
        case .fan: "F"
        }
    }

    static func value(_ metric: SystemMonitorMenuBarMetric, snapshot: SystemMetricsSnapshot?) -> String {
        guard let snapshot else { return "--" }
        switch metric {
        case .cpu:
            return percent(snapshot.cpu.usage)
        case .gpu:
            guard case let .available(gpu) = snapshot.gpu else { return "--" }
            return percent(gpu.usage)
        case .memory:
            return SystemMonitorMemoryPresentation.usageText(
                usedBytes: snapshot.memory.usedBytes, totalBytes: snapshot.memory.totalBytes
            )
        case .disk:
            guard snapshot.disk.totalBytes > 0 else { return "--" }
            return percent(Double(snapshot.disk.usedBytes) / Double(snapshot.disk.totalBytes))
        case .network:
            return "↓\(rate(snapshot.network.receiveBytesPerSecond)) ↑\(rate(snapshot.network.sendBytesPerSecond))"
        case .fan:
            guard case let .available(readings, _) = snapshot.fan, !readings.isEmpty else { return "--" }
            return readings.map { speed in
                guard speed.isFinite, speed >= 0, speed < Double(Int.max) else { return "--" }
                return String(Int(speed.rounded()))
            }.joined(separator: " ")
        }
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }

    private static func rate(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value < Double(Int64.max) else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) + "/s"
    }

    static func level(
        metric: SystemMonitorCombinedIconMetric,
        snapshot: SystemMetricsSnapshot?,
        levels: MenuBarSystemLevels
    ) -> Double? {
        let value: Double?
        switch metric {
        case .cpu:
            value = snapshot?.cpu.usage
        case .gpu:
            if case let .available(gpu) = snapshot?.gpu { value = gpu.usage } else { value = nil }
        case .memory:
            if let memory = snapshot?.memory {
                value = SystemMonitorMemoryPresentation.usageRatio(usedBytes: memory.usedBytes, totalBytes: memory.totalBytes)
            } else { value = nil }
        case .volume:
            value = levels.volume
        case .brightness:
            value = levels.brightness
        }
        guard let value, value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    static func batteryColor(_ battery: BatterySnapshot?, foreground: NSColor) -> NSColor {
        guard let battery else { return foreground.withAlphaComponent(0.35) }
        if battery.isLowPowerMode { return .systemYellow }
        if battery.level <= 0.2 { return .systemRed }
        if battery.isCharging || battery.isCharged { return .systemGreen }
        return foreground
    }
}

enum SystemMonitorMenuBarImageRenderer {
    static func stacked(rows: [String], style: SystemMonitorMenuBarDisplayStyle) -> NSImage? {
        let font = NSFont.monospacedDigitSystemFont(ofSize: style == .compact ? 9 : 10, weight: .medium)
        let width = ceil(rows.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0) + 4
        let image = bitmap(size: NSSize(width: max(24, width), height: 22)) { size in
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            for (index, row) in rows.prefix(2).enumerated() {
                (row as NSString).draw(
                    in: NSRect(x: 0, y: index == 0 ? 11 : 0, width: size.width, height: 12),
                    withAttributes: [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph]
                )
            }
        }
        image?.isTemplate = true
        image?.accessibilityDescription = rows.joined(separator: ", ")
        return image
    }

    static func combinedIcon(
        battery: BatterySnapshot?,
        wifi: MenuBarWiFiState,
        level: Double?,
        foreground: NSColor
    ) -> NSImage? {
        bitmap(size: NSSize(width: 22, height: 22)) { _ in
            let center = NSPoint(x: 11, y: 12)
            let track = NSBezierPath(ovalIn: NSRect(x: 3, y: 4, width: 16, height: 16))
            track.lineWidth = 1.5
            foreground.withAlphaComponent(0.25).setStroke()
            track.stroke()
            if let battery, battery.level.isFinite {
                let progress = NSBezierPath()
                progress.lineWidth = 1.6
                progress.lineCapStyle = .round
                progress.appendArc(
                    withCenter: center, radius: 8, startAngle: 90,
                    endAngle: 90 - 360 * min(1, max(0, battery.level)), clockwise: true
                )
                SystemMonitorCombinedMenuBarPresentation.batteryColor(battery, foreground: foreground).setStroke()
                progress.stroke()
            }

            let strength: Double?
            if case let .connected(value) = wifi { strength = value } else { strength = nil }
            foreground.setFill()
            NSBezierPath(ovalIn: NSRect(x: 10.3, y: 8.1, width: 1.4, height: 1.4)).fill()
            for (index, radius) in [CGFloat(2.7), 4.4].enumerated() {
                let arc = NSBezierPath()
                arc.lineWidth = 1.25
                arc.lineCapStyle = .round
                arc.appendArc(withCenter: NSPoint(x: 11, y: 8.8), radius: radius, startAngle: 40, endAngle: 140)
                (strength.map { $0 > Double(index) * 0.5 } == true ? foreground : foreground.withAlphaComponent(0.25)).setStroke()
                arc.stroke()
            }
            if strength == nil {
                let slash = NSBezierPath()
                slash.lineWidth = 1.2
                slash.move(to: NSPoint(x: 7, y: 14))
                slash.line(to: NSPoint(x: 15, y: 7.5))
                foreground.setStroke()
                slash.stroke()
            }

            let bar = NSRect(x: 2, y: 0.5, width: 18, height: 2)
            foreground.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
            if let level, level.isFinite {
                foreground.setFill()
                NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: bar.width * min(1, max(0, level)), height: bar.height), xRadius: 1, yRadius: 1).fill()
            } else {
                foreground.setFill()
                for position in [CGFloat(4), 10, 16] {
                    NSBezierPath(ovalIn: NSRect(x: position, y: bar.minY, width: 2, height: 2)).fill()
                }
            }
        }
    }

    private static func bitmap(size: NSSize, draw: (NSSize) -> Void) -> NSImage? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
        representation.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        draw(size)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }
}
