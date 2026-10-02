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

}

enum SystemMonitorMenuBarImageRenderer {
    static func stacked(rows: [String], style: SystemMonitorMenuBarDisplayStyle) -> NSImage? {
        let font = NSFont.monospacedDigitSystemFont(ofSize: style == .compact ? 9 : 10, weight: .medium)
        let width = ceil(rows.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0) + 2
        let image = bitmap(size: NSSize(width: max(24, width), height: 22)) { size in
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
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
        foreground: NSColor? = nil,
        configuration: SystemMonitorCombinedIconAppearance = SystemMonitorCombinedIconAppearance(),
        headphones: MenuBarIconHeadphoneStatus? = nil,
        headphoneOptions: SystemMonitorHeadphoneOptions = SystemMonitorHeadphoneOptions()
    ) -> NSImage? {
        SystemMonitorMenuBarIconRenderer.image(
            status: MenuBarIconStatus(
                battery: battery, wifi: wifi, level: level,
                headphones: headphones, headphoneOptions: headphoneOptions
            ),
            configuration: configuration,
            foreground: foreground
        )
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
