import AppKit
import SwiftUI
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

@MainActor
struct IslandStatusIcon: Identifiable {
    struct Reading {
        let metric: SystemMonitorMenuBarMetric
        let text: String
    }
    enum Content {
        case application
        case metric(SystemMonitorMenuBarMetric, text: String, image: NSImage?, style: SystemMonitorMenuBarDisplayStyle)
        case stacked(image: NSImage?, readings: [Reading])
        case combined(NSImage?)
    }
    let id: String
    let content: Content
    let tooltip: String

    func size(edge: IslandEdge) -> CGSize {
        switch content {
        case .application:
            return CGSize(width: 24, height: 24)
        case let .metric(_, text, image, style):
            if edge.isVertical { return Self.readingSize(text) }
            if style == .compact, let image { return CGSize(width: image.size.width, height: 24) }
            return CGSize(width: 24 + Self.textWidth(text), height: 24)
        case let .stacked(image, readings):
            if edge.isVertical {
                return CGSize(width: 32, height: readings.reduce(0) { $0 + Self.readingSize($1.text).height }
                    + CGFloat(readings.dropFirst().count) * 8)
            }
            return CGSize(width: image?.size.width ?? 24, height: 24)
        case let .combined(image):
            return image?.size ?? CGSize(width: 24, height: 24)
        }
    }

    static func readingSize(_ text: String) -> CGSize {
        CGSize(width: 32, height: 30 + CGFloat(CompactPillStatusPresentation.verticalTextRows(text,
            availableWidth: 32, availableHeight: CGFloat(text.count) * 14).count) * 14)
    }

    private static func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]).width)
    }
}

@MainActor
enum IslandStatusIconRouting {
    static func update(
        destination: StatusIconDestination,
        application: NSStatusItem?,
        metrics: [(SystemMonitorMenuBarMetric, NSStatusItem, String)],
        stacked: NSStatusItem?,
        readings: [IslandStatusIcon.Reading],
        combined: NSStatusItem?,
        style: SystemMonitorMenuBarDisplayStyle
    ) -> [IslandStatusIcon] {
        let items = [application, stacked, combined].compactMap { $0 } + metrics.map { $0.1 }
        items.forEach { $0.isVisible = destination == .menuBar }
        guard destination == .island else { return [] }
        var icons: [IslandStatusIcon] = []
        if application != nil {
            icons.append(IslandStatusIcon(id: "status-icon-application", content: .application, tooltip: "zisla"))
        }
        for (metric, item, title) in metrics {
            let text = style == .detailed
                ? String(title.dropFirst(SystemMonitorMenuBarPresentation.label(for: metric).count + 1))
                : title
            icons.append(IslandStatusIcon(id: "status-icon-\(metric.rawValue)",
                content: .metric(metric, text: text, image: item.button?.image, style: style),
                tooltip: (item.button?.toolTip ?? text)
                    .replacingOccurrences(of: AppLocalization.text("点击打开系统监控"), with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if let stacked {
            icons.append(IslandStatusIcon(id: "status-icon-stacked",
                content: .stacked(image: stacked.button?.image, readings: readings),
                tooltip: (stacked.button?.toolTip ?? readings.map(\.text).joined(separator: ", "))
                    .replacingOccurrences(of: AppLocalization.text("点击打开系统监控"), with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if let combined {
            icons.append(IslandStatusIcon(id: "status-icon-combined", content: .combined(combined.button?.image),
                tooltip: (combined.button?.toolTip ?? "zisla")
                    .replacingOccurrences(of: AppLocalization.text("点击打开系统监控"), with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return icons
    }
}

@MainActor
enum IslandStatusIconLayout {
    static func size(icons: [IslandStatusIcon], edge: IslandEdge) -> CGSize? {
        guard !icons.isEmpty else { return nil }
        let sizes = icons.map { $0.size(edge: edge) }
        let gaps = CGFloat(icons.count - 1) * 8 + 6
        if edge.isVertical {
            return CGSize(width: sizes.reduce(0) { max($0, $1.width) }, height: sizes.reduce(gaps) { $0 + $1.height })
        }
        return CGSize(width: sizes.reduce(gaps) { $0 + $1.width }, height: sizes.reduce(0) { max($0, $1.height) })
    }
}

struct IslandStatusIconStrip: View {
    let icons: [IslandStatusIcon]
    let edge: IslandEdge
    let date: Date

    var body: some View {
        iconContent
            .foregroundStyle(.white)
            .environment(\.layoutDirection, .leftToRight)
    }

    private var iconContent: some View {
        let layout = edge.isVertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(icons) { icon in
                iconView(icon)
                .accessibilityLabel(icon.tooltip)
                .accessibilityIdentifier(icon.id)
                .help(icon.tooltip)
            }
        }
        .padding(edge.isVertical ? .vertical : .horizontal, 3)
    }

    @ViewBuilder
    private func iconView(_ icon: IslandStatusIcon) -> some View {
        switch icon.content {
        case .application:
            IslandParticleLogo(side: 18, time: date.timeIntervalSinceReferenceDate)
        case let .metric(metric, text, image, style):
            if edge.isVertical {
                readingView(metric: metric, text: text)
            } else if style == .compact, let image {
                Image(nsImage: image).renderingMode(.template)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: metric.symbolName).frame(width: 18)
                    Text(text).font(.system(size: 12, weight: .medium)).monospacedDigit()
                }
            }
        case let .stacked(image, readings):
            if edge.isVertical {
                VStack(spacing: 8) {
                    ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                        readingView(metric: reading.metric, text: reading.text)
                    }
                }
            } else if let image {
                Image(nsImage: image).renderingMode(.template)
            } else {
                Text("--").font(.system(size: 12, design: .monospaced))
            }
        case let .combined(image):
            if let image { Image(nsImage: image).renderingMode(.original) }
            else { Text("--").font(.system(size: 12, design: .monospaced)) }
        }
    }

    private func readingView(metric: SystemMonitorMenuBarMetric, text: String) -> some View {
        let size = IslandStatusIcon.readingSize(text)
        return VStack(spacing: 6) {
            Image(systemName: metric.symbolName).font(.system(size: 14, weight: .medium))
                .frame(width: 24, height: 24)
            VerticalStatusText(text: text, availableWidth: size.width, availableHeight: size.height - 30)
        }
        .frame(width: size.width, height: size.height)
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
