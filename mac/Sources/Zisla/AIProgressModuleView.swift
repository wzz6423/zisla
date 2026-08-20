import AppKit
import Charts
import ZislaCore
import ZislaKit
import SwiftUI

struct AIProgressModuleView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var monitor: AIStateMonitor

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _monitor = ObservedObject(wrappedValue: model.aiMonitor)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            HStack(alignment: .top, spacing: 12) {
                runningTasks
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Hairline()

                usageSummary(endingAt: context.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var activeTasks: [AIProgressTask] {
        monitor.state.tasks
            .filter(\.status.isActive)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func usageTrend(endingAt date: Date) -> [UsageBreakdownPoint] {
        AIUsageAnalytics.dailyUsageSeries(
            samples: monitor.state.usageSamples,
            endingAt: date,
            days: 7
        )
    }

    private func usageCalendar(endingAt date: Date) -> [[ContributionDay?]] {
        AIUsageAnalytics.contributionCalendar(
            samples: monitor.state.usageSamples,
            endingAt: date,
            weeks: 24
        )
    }

    private func usageSummary(endingAt date: Date) -> some View {
        let series = usageTrend(endingAt: date)
        return VStack(alignment: .leading, spacing: 5) {
            Label("Token 消耗趋势", systemImage: "chart.xyaxis.line")
                .font(.system(size: 11, weight: .semibold))

            UsageTrendChart(series: series)
                .frame(height: 106)
            UsageHeatmap(weeks: usageCalendar(endingAt: date))
        }
    }

    @ViewBuilder
    private var runningTasks: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label("运行任务", systemImage: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text("\(activeTasks.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if activeTasks.isEmpty {
                EmptyState(symbol: "checkmark.circle", title: "暂无活动任务")
            } else {
                List(activeTasks) { task in
                    TaskProgressRow(task: task)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.visible)
                .thinScrollChrome()
                .environment(\.defaultMinListRowHeight, 38)
            }
        }
    }

}

private struct UsageTrendChart: View {
    var series: [UsageBreakdownPoint]

    private var ticks: [Int] {
        AIUsageAnalytics.tokenAxisTicks(maximum: maximumTokens, desiredCount: 5)
    }

    private var maximumTokens: Int {
        let raw = max(series.map(\.totalTokens).max() ?? 0, 1)
        // Leave 15% headroom at the top so the curve does not touch or exceed the top axis edge
        return max(Int((Double(raw) * 1.15).rounded()), raw + 1)
    }

    private var hasUsage: Bool {
        series.contains { $0.totalTokens > 0 }
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = series.first?.timestamp, let last = series.last?.timestamp else {
            let now = Date()
            return now...now
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: first)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else {
            return first...last
        }
        return start...end
    }

    private var xAxisValues: [Date] {
        series.map(\.timestamp)
    }

    var body: some View {
        Group {
            if hasUsage {
                chart
            } else {
                EmptyState(symbol: "chart.line.downtrend.xyaxis", title: "暂无 Token 用量")
            }
        }
        .accessibilityLabel(hasUsage ? "最近七天 AI token 总量趋势" : "暂无 AI token 用量")
    }

    private var chart: some View {
        Chart(series, id: \.timestamp) { point in
            AreaMark(
                x: .value("时间", point.timestamp),
                y: .value("总 Token", point.totalTokens)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                .linearGradient(
                    colors: [Color.blue.opacity(0.28), Color.blue.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            LineMark(
                x: .value("时间", point.timestamp),
                y: .value("总 Token", point.totalTokens)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(Color.blue)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .chartXScale(domain: xDomain)
        // Preserve the zero baseline while keeping quieter days visible beside order-of-magnitude spikes.
        .chartYScale(domain: 0...(ticks.last ?? 1), type: .symmetricLog(slopeAtZero: 0.000_001))
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.12))
                AxisValueLabel {
                    if let tokens = value.as(Int.self) {
                        Text(AIUsageAnalytics.formatTokenAxisValue(tokens))
                            .font(.islandMicro(design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            .font(.islandMicro(design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct TaskProgressRow: View {
    var task: AIProgressTask

    var body: some View {
        if let sessionURL = task.sessionURL {
            Button {
                NSWorkspace.shared.open(sessionURL)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("在 \(task.title) 中打开会话")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 9) {
            AIMascotView(
                identity: AIMascotIdentity(provider: task.provider, taskID: task.id, title: task.title),
                size: 20
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(task.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if let failureReason {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(failureReason)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.red)
                        .help(failureReason)
                    }
                    Spacer()
                    Text(task.provider.rawValue.uppercased())
                        .font(.islandMicro(weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if task.sessionURL != nil {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                if let metadataText {
                    Text(metadataText)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                statusContent
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .leading)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }

    private var metadataText: String? {
        let values = [task.detail, task.effort]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusContent: some View {
        if let startedAt = task.startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 4) {
                    Text(statusTimeText(startedAt, context.date))
                        .font(.islandMicro(design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: 2)
                    if task.status == .error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.red)
                            .help(failureReason ?? "任务失败")
                    } else if let progress = task.progress {
                        ProgressView(value: progress)
                            .tint(providerColor)
                            .frame(width: 32)
                    } else {
                        ThinkingOrbView(
                            state: ThinkingOrbState.forTask(task),
                            size: 20,
                            speed: task.status == .blocked ? 0.65 : 1,
                            tint: .white,
                            accessibilityLabel: "AI 正在工作"
                        )
                    }
                }
                .frame(height: 20)
            }
        } else if task.status == .error {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.red)
                .help(failureReason ?? "任务失败")
        } else if let progress = task.progress {
            ProgressView(value: progress)
                .tint(providerColor)
        } else {
            ThinkingOrbView(
                state: ThinkingOrbState.forTask(task),
                size: 20,
                speed: task.status == .blocked ? 0.65 : 1,
                tint: .white,
                accessibilityLabel: "AI 正在工作"
            )
        }
    }

    private func statusTimeText(_ startedAt: Date, _ now: Date) -> String {
        var parts: [String] = []
        parts.append("开始 \(startTimeText(startedAt))")
        if let processIdentifier = task.processIdentifier {
            parts.append("PID \(processIdentifier)")
        }
        parts.append("运行 \(elapsedText(from: startedAt, to: now))")
        return parts.joined(separator: " · ")
    }

    private func startTimeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    private func elapsedText(from start: Date, to end: Date) -> String {
        let totalSeconds = max(0, Int(end.timeIntervalSince(start)))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds / 3_600) % 24
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        let clock = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        return days > 0 ? "\(days)天 \(clock)" : clock
    }

    private var providerColor: Color {
        ProviderBrand.color(for: task.provider)
    }

    private var failureReason: String? {
        guard task.status == .error else { return nil }
        return task.failureReason ?? "任务失败，未提供详细原因"
    }
}

private struct UsageHeatmap: View {
    var weeks: [[ContributionDay?]]

    private let gap: CGFloat = 1.5
    @State private var selectedDate: Date?

    /// Maximum single-day token count within the current window; intensity is normalized relative to it
    /// to avoid absolute thresholds (e.g., 50M/100M/…) always mapping most users to the lightest level.
    private var maxTokens: Int {
        weeks.flatMap { $0 }.compactMap { $0?.tokens }.max() ?? 0
    }

    private var maxLabel: String {
        AIUsageAnalytics.formatTokenAxisValue(maxTokens)
    }

    private var selectedDay: ContributionDay? {
        guard let selectedDate else { return nil }
        return weeks.flatMap { $0 }.compactMap { $0 }.first {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    private func intensity(for tokens: Int) -> ContributionIntensity {
        guard tokens > 0, maxTokens > 0 else { return .none }
        let fraction = Double(tokens) / Double(maxTokens)
        if fraction <= 0.25 { return .level1 }
        if fraction <= 0.5 { return .level2 }
        if fraction <= 0.75 { return .level3 }
        return .level4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                let width = cellWidth(in: proxy.size.width)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(weeks.indices, id: \.self) { weekIndex in
                        VStack(spacing: gap) {
                            ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                                UsageCalendarCell(
                                    day: weeks[weekIndex][dayIndex],
                                    intensity: intensity(for: weeks[weekIndex][dayIndex]?.tokens ?? 0),
                                    isSelected: isSelected(weeks[weekIndex][dayIndex]),
                                    select: { selectedDate = $0 }
                                )
                                .frame(width: width, height: width)
                            }
                        }
                    }
                }
            }
            .aspectRatio(gridAspectRatio, contentMode: .fit)

            GeometryReader { proxy in
                let width = cellWidth(in: proxy.size.width)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(weeks.indices, id: \.self) { index in
                        let label = monthLabel(in: weeks[index])
                        Text(label ?? "")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.75))
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: width, alignment: .leading)
                            .opacity(label == nil ? 0 : 1)
                    }
                }
            }
            .frame(height: 13)

            HStack(spacing: 4) {
                Text("少")
                    .font(.islandMicro())
                    .foregroundStyle(.secondary)
                ForEach(ContributionIntensity.allCases, id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(intensity.color)
                        .overlay {
                            if intensity == .none {
                                RoundedRectangle(cornerRadius: 1)
                                    .stroke(Color.primary.opacity(0.13), lineWidth: 0.5)
                            }
                        }
                        .frame(width: 7, height: 7)
                }
                Text("多 · \(maxLabel)")
                    .font(.islandMicro(design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if let selectedDay {
                    Text(selectedDay.date, format: .dateTime.year().month().day())
                    Text("· \(AIUsageAnalytics.formatTokenAxisValue(selectedDay.tokens)) Token")
                }
                Spacer(minLength: 0)
            }
            .font(.islandMicro(design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(height: 13, alignment: .leading)
        }
        .accessibilityLabel("最近二十四周 AI token 用量热力图")
    }

    private func isSelected(_ day: ContributionDay?) -> Bool {
        guard let selectedDate, let day else { return false }
        return Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
    }

    private var gridAspectRatio: CGFloat {
        guard !weeks.isEmpty else { return 1 }
        return CGFloat(weeks.count) / 7
    }

    private func cellWidth(in availableWidth: CGFloat) -> CGFloat {
        guard !weeks.isEmpty else { return 1 }
        return max(1, (availableWidth - CGFloat(weeks.count - 1) * gap) / CGFloat(weeks.count))
    }

    private func monthLabel(in week: [ContributionDay?]) -> String? {
        guard let date = week.compactMap({ $0?.date }).first(where: {
            Calendar.current.component(.day, from: $0) == 1
        }) else { return nil }
        return "\(Calendar.current.component(.month, from: date))月"
    }
}

private struct UsageCalendarCell: View {
    var day: ContributionDay?
    var intensity: ContributionIntensity
    var isSelected: Bool
    var select: (Date) -> Void

    var body: some View {
        if let day {
            Button {
                select(day.date)
            } label: {
                cell
            }
            .buttonStyle(.plain)
            .help("\(day.date.formatted(date: .long, time: .omitted)) · \(AIUsageAnalytics.formatTokenAxisValue(day.tokens)) Token")
            .accessibilityLabel("\(day.date.formatted(date: .long, time: .omitted))，\(AIUsageAnalytics.formatTokenAxisValue(day.tokens)) Token")
        } else {
            cell
                .accessibilityHidden(true)
        }
    }

    private var cell: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(intensity.color)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(Color.primary.opacity(0.9), lineWidth: 1)
                } else if day != nil, intensity == .none {
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
                }
            }
    }
}

private extension ContributionIntensity {
    var color: Color {
        switch self {
        case .none: .clear
        case .level1: Color.green.opacity(0.25)
        case .level2: Color.green.opacity(0.45)
        case .level3: Color.green.opacity(0.7)
        case .level4: Color.green
        }
    }
}
