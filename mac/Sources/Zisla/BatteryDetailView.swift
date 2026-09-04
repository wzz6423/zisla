import SwiftUI
import ZislaKit

struct LocalPowerFlowPresentation: Equatable {
    enum Mode: Equatable {
        case pluggedIn
        case onBattery
    }

    enum BatteryRoute: Equatable {
        case charging
        case supplying
        case idle
        case unavailable
    }

    enum Topology: Equatable {
        case batteryToMac
        case adapterSplit
        case adapterAndBatteryMerge
        case adapterToMac
    }

    let mode: Mode
    let topology: Topology
    let inputWatts: Double?
    let inputIsRated: Bool
    let batteryWatts: Double?
    let systemWatts: Double?
    let batteryRoute: BatteryRoute

    init(battery: BatterySnapshot) {
        if battery.isPluggedIn {
            mode = .pluggedIn
            inputWatts = battery.adapterWatts ?? battery.adapterRatedWatts
            inputIsRated = battery.adapterWatts == nil && battery.adapterRatedWatts != nil
            systemWatts = battery.systemLoadWatts

            if let flow = battery.batteryFlowWatts {
                batteryWatts = abs(flow)
                if abs(flow) < 0.05 {
                    batteryRoute = .idle
                    topology = .adapterToMac
                } else {
                    batteryRoute = flow > 0 ? .charging : .supplying
                    topology = flow > 0 ? .adapterSplit : .adapterAndBatteryMerge
                }
            } else if battery.isCharging, let power = battery.powerWatts {
                batteryWatts = power
                batteryRoute = .charging
                topology = .adapterSplit
            } else {
                batteryWatts = nil
                batteryRoute = .unavailable
                topology = .adapterToMac
            }
        } else {
            mode = .onBattery
            topology = .batteryToMac
            let power = battery.powerWatts ?? battery.batteryFlowWatts.map { abs($0) }
            inputWatts = power
            inputIsRated = false
            batteryWatts = nil
            systemWatts = power
            batteryRoute = .supplying
        }
    }
}

struct BatteryHistoryPresentation: Equatable {
    let text: String?

    init(
        battery: BatterySnapshot,
        lastFullyChargedAt: Date?,
        lastUnpluggedAt: Date?,
        now: Date
    ) {
        guard !battery.isCharging else {
            text = nil
            return
        }

        let parts = [
            lastFullyChargedAt.map { "上次充满 \(Self.durationText(from: $0, to: now))" },
            lastUnpluggedAt.map { "已脱电使用 \(Self.durationText(from: $0, to: now))" }
        ].compactMap { $0 }
        text = parts.isEmpty ? nil : parts.joined(separator: "，")
    }

    static func durationText(from start: Date, to end: Date) -> String {
        let totalSeconds = max(0, Int(end.timeIntervalSince(start)))
        return durationText(forMinutes: totalSeconds / 60)
    }

    static func durationText(forMinutes minutes: Int) -> String {
        let normalizedMinutes = max(0, minutes)
        let hours = normalizedMinutes / 60
        let remainder = normalizedMinutes % 60
        if hours > 0 { return "\(hours)小时\(remainder)分" }
        return "\(remainder)分钟"
    }
}

private struct LocalPowerFlowView: View {
    let battery: BatterySnapshot

    private var presentation: LocalPowerFlowPresentation {
        LocalPowerFlowPresentation(battery: battery)
    }

    var body: some View {
        Group {
            switch presentation.topology {
            case .batteryToMac:
                onBatteryFlow
            case .adapterSplit:
                chargingSplitFlow
            case .adapterAndBatteryMerge:
                batteryAssistFlow
            case .adapterToMac:
                adapterPassThroughFlow
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var chargingSplitFlow: some View {
        HStack(spacing: 8) {
            endpointNode(
                symbol: "powerplug.fill",
                value: wattsText(presentation.inputWatts, wholeIfExact: true),
                caption: presentation.inputIsRated ? "充电器额定" : "充电器输入",
                tint: .zislaWarning
            )
            .frame(width: 84)

            ZStack {
                branchLane(
                    .upper,
                    tint: .zislaWarning,
                    endTint: batteryRouteTint,
                    upperFraction: chargingBranchFraction
                )
                branchLane(
                    .lower,
                    tint: .zislaWarning,
                    endTint: .zislaInfo,
                    upperFraction: chargingBranchFraction
                )

                GeometryReader { proxy in
                    routeLabel(
                        watts: presentation.batteryWatts,
                        title: batteryRouteTitle
                    )
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * chargingBranchFraction / 2
                    )
                    routeLabel(
                        watts: presentation.systemWatts,
                        title: "系统使用"
                    )
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * (1 + chargingBranchFraction) / 2
                    )
                }
            }

            GeometryReader { proxy in
                let availableHeight = proxy.size.height - 8
                let upperHeight = availableHeight * chargingBranchFraction
                VStack(spacing: 8) {
                    endpointNode(
                        symbol: battery.symbolName,
                        value: "\(battery.percentInt)%",
                        caption: batteryRouteTitle,
                        tint: batteryRouteTint
                    )
                    .frame(height: upperHeight)
                    endpointNode(
                        symbol: "laptopcomputer",
                        value: nil,
                        caption: "本机 Mac",
                        tint: .zislaInfo
                    )
                    .frame(height: availableHeight - upperHeight)
                }
            }
            .frame(width: 88)
        }
        .frame(height: 176)
    }

    private var batteryAssistFlow: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                let availableHeight = proxy.size.height - 8
                let upperHeight = availableHeight * assistInputFraction
                VStack(spacing: 8) {
                    endpointNode(
                        symbol: "powerplug.fill",
                        value: wattsText(presentation.inputWatts, wholeIfExact: true),
                        caption: presentation.inputIsRated ? "充电器额定" : "充电器输入",
                        tint: .zislaWarning
                    )
                    .frame(height: upperHeight)
                    endpointNode(
                        symbol: battery.symbolName,
                        value: "\(battery.percentInt)%",
                        caption: "电池供电",
                        tint: .zislaWarning
                    )
                    .frame(height: availableHeight - upperHeight)
                }
            }
            .frame(width: 88)

            ZStack {
                branchLane(
                    .upper,
                    tint: .zislaInfo,
                    endTint: .zislaWarning,
                    upperFraction: assistInputFraction
                )
                .scaleEffect(x: -1, y: 1)
                branchLane(
                    .lower,
                    tint: .zislaInfo,
                    endTint: .zislaWarning,
                    upperFraction: assistInputFraction
                )
                .scaleEffect(x: -1, y: 1)

                GeometryReader { proxy in
                    routeLabel(
                        watts: presentation.inputWatts,
                        title: presentation.inputIsRated ? "充电器额定" : "充电器输入"
                    )
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * assistInputFraction / 2
                    )
                    routeLabel(
                        watts: presentation.batteryWatts,
                        title: "电池供电"
                    )
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * (1 + assistInputFraction) / 2
                    )
                }
            }

            endpointNode(
                symbol: "laptopcomputer",
                value: wattsText(presentation.systemWatts),
                caption: "系统使用",
                tint: .zislaInfo
            )
            .frame(width: 84)
        }
        .frame(height: 176)
    }

    private var adapterPassThroughFlow: some View {
        HStack(spacing: 8) {
            endpointNode(
                symbol: "powerplug.fill",
                value: wattsText(presentation.inputWatts, wholeIfExact: true),
                caption: presentation.inputIsRated ? "充电器额定" : "充电器输入",
                tint: .zislaWarning
            )
            .frame(width: 84)

            simpleRouteLane(
                watts: presentation.systemWatts,
                title: "系统使用",
                startTint: presentation.systemWatts == nil ? .secondary : .zislaWarning,
                endTint: presentation.systemWatts == nil ? .secondary : .zislaInfo
            )

            endpointNode(
                symbol: "laptopcomputer",
                value: nil,
                caption: "本机 Mac",
                tint: .zislaInfo
            )
            .frame(width: 84)
        }
        .frame(height: 96)
    }

    private var onBatteryFlow: some View {
        HStack(spacing: 8) {
            endpointNode(
                symbol: battery.symbolName,
                value: "\(battery.percentInt)%",
                caption: "电池供电",
                tint: batteryLevelTint
            )
            .frame(width: 84)

            simpleRouteLane(
                watts: presentation.systemWatts,
                title: "电池供电",
                startTint: .zislaWarning,
                endTint: .zislaInfo
            )

            endpointNode(
                symbol: "laptopcomputer",
                value: nil,
                caption: "本机 Mac",
                tint: .zislaInfo
            )
            .frame(width: 84)
        }
        .frame(height: 96)
    }

    private func simpleRouteLane(
        watts: Double?,
        title: String,
        startTint: Color,
        endTint: Color
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [startTint.opacity(0.28), endTint.opacity(0.14)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.strokeCard, lineWidth: 0.5)
            routeLabel(watts: watts, title: title)
        }
    }

    private func endpointNode(
        symbol: String,
        value: String?,
        caption: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .frame(height: 24)
            if let value {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(caption)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fillCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.strokeCard, lineWidth: 0.5)
        }
    }

    private func routeLabel(watts: Double?, title: String) -> some View {
        VStack(spacing: 2) {
            Text(wattsText(watts))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
    }

    private func branchLane(
        _ lane: PowerBranchLaneShape.Lane,
        tint: Color,
        endTint: Color,
        upperFraction: Double
    ) -> some View {
        PowerBranchLaneShape(lane: lane, upperFraction: upperFraction)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.30), endTint.opacity(0.16)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay {
                PowerBranchLaneShape(lane: lane, upperFraction: upperFraction)
                    .stroke(Color.strokeCard, lineWidth: 0.5)
            }
    }

    private var chargingBranchFraction: Double {
        guard let batteryWatts = presentation.batteryWatts,
              let systemWatts = presentation.systemWatts,
              batteryWatts + systemWatts > 0
        else {
            return 0.5
        }
        return min(max(batteryWatts / (batteryWatts + systemWatts), 0.35), 0.65)
    }

    private var assistInputFraction: Double {
        guard !presentation.inputIsRated,
              let inputWatts = presentation.inputWatts,
              let batteryWatts = presentation.batteryWatts,
              inputWatts + batteryWatts > 0
        else {
            return 0.5
        }
        return min(max(inputWatts / (inputWatts + batteryWatts), 0.35), 0.65)
    }

    private var batteryRouteTitle: String {
        switch presentation.batteryRoute {
        case .charging: "充入电池"
        case .supplying: "电池供电"
        case .idle: "电池未参与"
        case .unavailable: "电池功率"
        }
    }

    private var batteryRouteTint: Color {
        switch presentation.batteryRoute {
        case .charging: .zislaSuccess
        case .supplying: .zislaWarning
        case .idle: .secondary
        case .unavailable: batteryLevelTint
        }
    }

    private var batteryLevelTint: Color {
        if battery.level < 0.15 { return .zislaError }
        if battery.level < 0.30 { return .zislaWarning }
        return .zislaSuccess
    }

    private func wattsText(_ watts: Double?, wholeIfExact: Bool = false) -> String {
        guard let watts else { return "-- W" }
        if wholeIfExact, abs(watts.rounded() - watts) < 0.15 {
            return String(format: "%.0f W", watts)
        }
        if abs(watts) < 10 {
            return String(format: "%.2f W", watts)
        }
        return String(format: "%.1f W", watts)
    }

    private var accessibilityText: String {
        let inputKind = presentation.inputIsRated ? "充电器额定功率" : "充电器实时输入"
        switch presentation.topology {
        case .batteryToMac:
            return "本机功率流，电池\(battery.percentInt)%，系统使用\(wattsText(presentation.systemWatts))"
        case .adapterSplit:
            return "本机功率流，\(inputKind)\(wattsText(presentation.inputWatts))，电池\(battery.percentInt)%，\(batteryRouteTitle)\(wattsText(presentation.batteryWatts))，系统使用\(wattsText(presentation.systemWatts))"
        case .adapterAndBatteryMerge:
            return "本机功率流，\(inputKind)\(wattsText(presentation.inputWatts))，电池\(battery.percentInt)%供电\(wattsText(presentation.batteryWatts))，合流后系统使用\(wattsText(presentation.systemWatts))"
        case .adapterToMac:
            return "本机功率流，\(inputKind)\(wattsText(presentation.inputWatts))，电池\(battery.percentInt)%，\(batteryRouteTitle)，系统使用\(wattsText(presentation.systemWatts))"
        }
    }
}

private struct PowerBranchLaneShape: Shape {
    enum Lane {
        case upper
        case lower
    }

    let lane: Lane
    let upperFraction: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(8, rect.width * 0.08)
        let gap = min(28, rect.height * 0.18)
        let splitY = rect.minY + rect.height * min(max(upperFraction, 0.35), 0.65)
        let upperBottom = splitY - gap / 2
        let lowerTop = splitY + gap / 2
        let junctionX = rect.minX + rect.width * 0.18
        var path = Path()

        switch lane {
        case .upper:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: upperBottom - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: upperBottom),
                control: CGPoint(x: rect.maxX, y: upperBottom)
            )
            path.addCurve(
                to: CGPoint(x: junctionX, y: splitY),
                control1: CGPoint(x: rect.minX + rect.width * 0.62, y: upperBottom),
                control2: CGPoint(x: rect.minX + rect.width * 0.36, y: splitY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: splitY))
            path.closeSubpath()
        case .lower:
            path.move(to: CGPoint(x: rect.minX, y: splitY))
            path.addLine(to: CGPoint(x: junctionX, y: splitY))
            path.addCurve(
                to: CGPoint(x: rect.maxX - radius, y: lowerTop),
                control1: CGPoint(x: rect.minX + rect.width * 0.36, y: splitY),
                control2: CGPoint(x: rect.minX + rect.width * 0.62, y: lowerTop)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: lowerTop + radius),
                control: CGPoint(x: rect.maxX, y: lowerTop)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

struct BatteryDetailView: View {
    @ObservedObject var batteryMonitor: BatteryMonitor
    @ObservedObject var networkMonitor: NetworkBatteryMonitor
    var onContentHeightChange: (CGFloat) -> Void = { _ in }

    @State private var contentHeight = IslandModuleLayout.batteryMaximumContentHeight

    private var deviceCardShape: UnevenRoundedRectangle {
        IslandSurfaceGeometry.moduleContentShape(
            cornerRadius: IslandSurfaceGeometry.nestedBottomCornerRadius(
                inset: IslandSurfaceGeometry.moduleInset
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let battery = batteryMonitor.snapshot {
                    localBatterySection(battery)
                } else {
                    noLocalBatterySection
                }
                deviceSection
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ContentHeightPreferenceKey.self,
                                value: geometry.frame(in: .named("batteryContent")).maxY
                            )
                        }
                    }
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
            .coordinateSpace(name: "batteryContent")
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: min(contentHeight, IslandModuleLayout.batteryMaximumContentHeight))
        .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
            onContentHeightChange(height)
        }
        .onAppear {
            batteryMonitor.refresh()
            networkMonitor.start()
        }
        .onDisappear {
            networkMonitor.stop()
        }
    }

    private struct ContentHeightPreferenceKey: PreferenceKey {
        static let defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private func localBatterySection(_ battery: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("本机电池", systemImage: "laptopcomputer")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                batteryHistoryView(for: battery)
                Text(statusText(battery))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: battery.symbolName)
                        .foregroundStyle(batteryLevelTint(battery.level))
                    Text("\(battery.percentInt)%")
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                if battery.isLowPowerMode {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.zislaSuccess)
                        .help("低电量模式已开启")
                }
            }

            LocalPowerFlowView(battery: battery)
            metricGrid(battery)

            if let minutes = battery.timeRemainingMinutes {
                overviewRow(
                    symbol: "clock",
                    label: battery.isCharging ? "距离充满" : "预计可用",
                    value: timeRemainingText(minutes)
                )
                .padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private func batteryHistoryView(for battery: BatterySnapshot) -> some View {
        if !battery.isCharging,
           batteryMonitor.lastFullyChargedAt != nil || batteryMonitor.lastUnpluggedAt != nil {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let presentation = BatteryHistoryPresentation(
                    battery: battery,
                    lastFullyChargedAt: batteryMonitor.lastFullyChargedAt,
                    lastUnpluggedAt: batteryMonitor.lastUnpluggedAt,
                    now: context.date
                )
                if let text = presentation.text {
                    Text(text)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
            }
        }
    }

    private func metricGrid(_ battery: BatterySnapshot) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            metricTile(
                title: "健康度",
                value: battery.healthPercent.map { "\($0)%" } ?? "--",
                symbol: "heart.fill",
                tint: battery.healthPercent.map(healthTint) ?? .secondary
            )
            metricTile(
                title: "循环次数",
                value: battery.cycleCount.map(String.init) ?? "--",
                symbol: "arrow.triangle.2.circlepath"
            )
            metricTile(
                title: "温度",
                value: battery.temperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "--",
                symbol: "thermometer.medium"
            )
            metricTile(
                title: "最大容量",
                value: battery.maxCapacityMAh.map { "\($0) mAh" } ?? "--",
                symbol: "battery.100percent"
            )
            metricTile(
                title: "设计容量",
                value: battery.designCapacityMAh.map { "\($0) mAh" } ?? "--",
                symbol: "ruler"
            )
            metricTile(
                title: "当前电量",
                value: battery.currentCapacityMAh.map { "\($0) mAh" } ?? "--",
                symbol: "battery.50percent"
            )
            metricTile(
                title: "电流",
                value: battery.currentMilliamps.map { String(format: "%.2f A", $0 / 1_000) } ?? "--",
                symbol: "waveform.path.ecg"
            )
            metricTile(
                title: "电压",
                value: battery.voltageVolts.map { String(format: "%.2f V", $0) } ?? "--",
                symbol: "bolt.circle"
            )
            metricTile(
                title: "充电器额定",
                value: battery.adapterRatedWatts.map { String(format: "%.0f W", $0) } ?? "--",
                symbol: "powerplug.fill"
            )
        }
    }

    private func metricTile(
        title: String,
        value: String,
        symbol: String,
        tint: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Color.fillCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.strokeCard.opacity(0.5), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)")
    }

    private var deviceSection: some View {
        let devices = networkMonitor.devices

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("设备电量", systemImage: "rectangle.stack.badge.person.crop")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if networkMonitor.isScanning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 24, height: 24)
                } else {
                    Button {
                        networkMonitor.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("刷新设备电量")
                    .accessibilityLabel("刷新设备电量")
                }
            }

            if devices.isEmpty {
                ContentUnavailableView(
                    "未发现其他设备",
                    systemImage: "battery.0percent",
                    description: Text("当前没有 macOS 可读取的蓝牙设备或已信任的 Apple 移动设备")
                )
                .frame(maxWidth: .infinity, minHeight: 112)
            } else if devices.count <= 2 {
                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        deviceRow(device)
                        if index < devices.count - 1 {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .background(Color.fillCard)
                .clipShape(deviceCardShape)
                .overlay {
                    deviceCardShape
                        .strokeBorder(Color.strokeCard, lineWidth: 0.5)
                }
            } else {
                VStack(spacing: 8) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(pairedDevices(from: devices), id: \.id) { device in
                            deviceCard(device)
                        }
                    }

                    if let unpairedDevice = unpairedDevice(from: devices) {
                        deviceRow(unpairedDevice)
                            .frame(minHeight: 64)
                            .background(Color.fillCard)
                            .clipShape(deviceCardShape)
                            .overlay {
                                deviceCardShape
                                    .strokeBorder(Color.strokeCard, lineWidth: 0.5)
                            }
                    }
                }
            }
        }
    }

    private func pairedDevices(from devices: [NetworkBatteryDevice]) -> ArraySlice<NetworkBatteryDevice> {
        devices.dropLast(devices.count.isMultiple(of: 2) ? 0 : 1)
    }

    private func unpairedDevice(from devices: [NetworkBatteryDevice]) -> NetworkBatteryDevice? {
        devices.count.isMultiple(of: 2) ? nil : devices.last
    }

    private func deviceRow(_ device: NetworkBatteryDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.deviceType.symbolName)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(device.name)
                HStack(spacing: 4) {
                    Image(systemName: device.source.symbolName)
                        .font(.system(size: 8, weight: .semibold))
                    Text(deviceSubtitle(device))
                        .lineLimit(1)
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !device.components.isEmpty {
                Text(componentText(device.components))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .help(componentText(device.components))
            }

            HStack(spacing: 5) {
                Image(systemName: device.batterySymbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(batteryLevelTint(device.batteryLevel))
                Text("\(device.batteryPercentInt)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 50)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(deviceAccessibilityLabel(device))
    }

    private func deviceCard(_ device: NetworkBatteryDevice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: device.deviceType.symbolName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(device.name)

                HStack(spacing: 4) {
                    Image(systemName: device.source.symbolName)
                        .font(.system(size: 8, weight: .semibold))
                    Text(deviceSubtitle(device))
                        .lineLimit(1)
                }
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

                if !device.components.isEmpty {
                    Text(componentText(device.components))
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .help(componentText(device.components))
                }
            }

            Spacer(minLength: 4)

            VStack(spacing: 3) {
                Image(systemName: device.batterySymbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(batteryLevelTint(device.batteryLevel))
                Text("\(device.batteryPercentInt)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Color.fillCard)
        .clipShape(deviceCardShape)
        .overlay {
            deviceCardShape
                .strokeBorder(Color.strokeCard, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(deviceAccessibilityLabel(device))
    }

    private var noLocalBatterySection: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("此 Mac 无内置电池")
                    .font(.system(size: 12, weight: .semibold))
                Text("仍会显示可读取电量的蓝牙设备和已信任的 Apple 移动设备")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.fillCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.strokeCard, lineWidth: 0.5)
        }
    }

    private func overviewRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func statusText(_ battery: BatterySnapshot) -> String {
        if battery.isCharged { return "已充满" }
        if battery.isCharging { return "充电中" }
        if battery.isPluggedIn { return "电源已接通" }
        return "使用电池"
    }

    private func deviceSubtitle(_ device: NetworkBatteryDevice) -> String {
        var parts = [device.source.displayName, device.deviceType.displayName]
        if let parentName = device.parentName {
            parts.append("通过 \(parentName)")
        }
        if let detail = device.connectionDetail {
            parts.append(detail)
        }
        return parts.joined(separator: " · ")
    }

    private func componentText(_ components: [BatteryLevelComponent]) -> String {
        components
            .map { "\($0.kind.displayName) \($0.percentInt)%" }
            .joined(separator: " · ")
    }

    private func deviceAccessibilityLabel(_ device: NetworkBatteryDevice) -> String {
        var parts = [device.name, "\(device.batteryPercentInt)%"]
        if device.isCharging {
            parts.append("正在充电")
        }
        if !device.components.isEmpty {
            parts.append(componentText(device.components))
        }
        return parts.joined(separator: "，")
    }

    private func timeRemainingText(_ minutes: Int) -> String {
        BatteryHistoryPresentation.durationText(forMinutes: minutes)
    }

    private func batteryLevelTint(_ level: Double) -> Color {
        if level < 0.15 { return .zislaError }
        if level < 0.30 { return .zislaWarning }
        return .zislaSuccess
    }

    private func healthTint(_ health: Int) -> Color {
        if health < 70 { return .zislaError }
        if health < 85 { return .zislaWarning }
        return .zislaSuccess
    }
}
