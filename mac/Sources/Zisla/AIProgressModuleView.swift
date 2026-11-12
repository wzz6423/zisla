import AppKit
import Charts
import ZislaCore
import ZislaKit
import SwiftUI

struct AIProgressModuleView: View {
    @ObservedObject private var monitor: AIStateMonitor
    @State private var selectedUsageDate: Date?

    /// Both columns push their content this far below the header. The trend chart's topmost
    /// Y-axis tick is drawn above its plot frame, so a tighter gap lets it collide with the title.
    private static let sectionSpacing: CGFloat = 12

    init(monitor: AIStateMonitor) {
        _monitor = ObservedObject(wrappedValue: monitor)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 12) {
                runningTasks
                    .frame(width: (proxy.size.width - 24) * 0.48)
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                Hairline()

                ScrollView(.vertical) {
                    usageSummary(endingAt: .now)
                        .padding(.horizontal, NSScroller.scrollerWidth(for: .mini, scrollerStyle: .overlay))
                }
                .thinScrollChrome(scrollerStyle: .overlay)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
        return VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            Label(AppLocalization.text("Token 消耗趋势"), systemImage: "chart.xyaxis.line")
                .font(.system(size: 11, weight: .semibold))

            UsageTrendChart(series: series, selectedDate: $selectedUsageDate)
                .frame(height: 128)
            UsageHeatmap(weeks: usageCalendar(endingAt: date), selectedDate: $selectedUsageDate)
            if let selectedUsageDate {
                DailyModelUsageList(day: AIUsageHistoryPresentation.selectedDay(in: AIUsageHistory(
                    usageSamples: monitor.state.usageSamples, modelUsageSamples: monitor.state.modelUsageSamples), date: selectedUsageDate))
            }
        }
    }

    @ViewBuilder
    private var runningTasks: some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            HStack {
                Label(AppLocalization.text("运行任务"), systemImage: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text("\(activeTasks.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if activeTasks.isEmpty {
                EmptyState(symbol: "checkmark.circle", title: AppLocalization.text("暂无活动任务"))
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
                .thinScrollChrome(visibleWhenScrollable: false)
                .environment(\.defaultMinListRowHeight, 38)
            }
        }
    }

}

struct DailyModelUsageList: View {
    var day: AIDailyModelUsage
    @Environment(\.locale) private var locale

    struct ProviderGroup: Identifiable {
        var provider: AIProvider?
        var models: [AIModelUsage]
        var id: String { provider?.rawValue ?? "" }
        var identity: AIMascotIdentity? { provider.map { AIMascotIdentity(provider: $0, taskID: "") } }

        func name(locale: Locale = AppLocalization.currentLanguage.locale) -> String {
            provider.map(AIMascotLibrary.providerDisplayName(for:))
                ?? AppLocalization.string("未分类", locale: locale)
        }
    }

    /// Codex usage belongs to ChatGPT; merge identical models only within that display brand.
    static func providerGroups(_ models: [AIModelUsage]) -> [ProviderGroup] {
        Dictionary(grouping: models, by: { $0.provider == .codex ? .gpt : $0.provider }).map { provider, records in
            var combined: [String?: AIModelUsage] = [:]
            for record in records {
                let name = AIUsageAnalytics.normalizedModel(record.model)
                var model = combined[name] ?? AIModelUsage(provider: provider, model: name, inputTokens: 0, outputTokens: 0)
                model.inputTokens = AIUsageTokenMath.adding(model.inputTokens, record.inputTokens)
                model.outputTokens = AIUsageTokenMath.adding(model.outputTokens, record.outputTokens)
                combined[name] = model
            }
            return ProviderGroup(provider: provider, models: combined.values.sorted {
                $0.totalTokens != $1.totalTokens ? $0.totalTokens > $1.totalTokens : $0.id < $1.id
            })
        }.sorted { lhs, rhs in
            let leftTotal = lhs.models.reduce(0) { AIUsageTokenMath.adding($0, $1.totalTokens) }
            let rightTotal = rhs.models.reduce(0) { AIUsageTokenMath.adding($0, $1.totalTokens) }
            return leftTotal != rightTotal ? leftTotal > rightTotal : lhs.id < rhs.id
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Label(AppLocalization.string("每日模型用量", locale: locale), systemImage: "list.bullet.rectangle")
                .font(.system(size: 11, weight: .semibold))
            if day.models.isEmpty {
                Text(day.date, format: .dateTime.year().month().day())
                    .font(.islandMicro(weight: .semibold, design: .monospaced))
                EmptyState(symbol: "chart.bar", title: AppLocalization.string("暂无模型用量", locale: locale))
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(day.date, format: .dateTime.year().month().day())
                            Spacer(minLength: 4)
                            Text("\(AIUsageAnalytics.formatTokenAxisValue(day.totalTokens)) Token")
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.date, format: .dateTime.year().month().day())
                            Text("\(AIUsageAnalytics.formatTokenAxisValue(day.totalTokens)) Token")
                        }
                    }
                    .font(.islandMicro(weight: .semibold, design: .monospaced))
                    ForEach(Self.providerGroups(day.models)) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                if let identity = group.identity {
                                    AIMascotView(identity: identity, size: 13)
                                }
                                Text(group.name(locale: locale)).font(.system(size: 11, weight: .semibold))
                            }
                            ForEach(group.models) { model in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(Self.modelName(model, locale: locale))
                                        .font(.system(size: 10, weight: .medium))
                                        .fitsSingleLine()
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .help(Self.modelName(model, locale: locale))
                                    Text(Self.tokenBreakdown(model, locale: locale))
                                        .font(.islandMicro(design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .fitsSingleLine()
                                        .layoutPriority(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Hairline()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Unknown models remain explicit because retained daily totals cannot reconstruct their attribution.
    static func modelName(_ usage: AIModelUsage, locale: Locale = AppLocalization.currentLanguage.locale) -> String {
        usage.model ?? AppLocalization.string("未知模型", locale: locale)
    }

    /// Model counts use millions consistently while retaining nonzero sub-million usage.
    static func tokenBreakdown(_ usage: AIModelUsage, locale: Locale = AppLocalization.currentLanguage.locale) -> String {
        let format = FloatingPointFormatStyle<Double>.number.grouping(.never).precision(.fractionLength(0...6)).locale(locale)
        return AppLocalization.format("输入 %@ · 输出 %@", locale: locale,
            [(Double(usage.inputTokens) / 1_000_000).formatted(format) + " M",
             (Double(usage.outputTokens) / 1_000_000).formatted(format) + " M"])
    }
}

struct UsageTrendChart: View {
    var series: [UsageBreakdownPoint]
    @Binding var selectedDate: Date?
    var domain: ClosedRange<Date>?
    @Environment(\.locale) private var locale

    init(series: [UsageBreakdownPoint], selectedDate: Binding<Date?> = .constant(nil), domain: ClosedRange<Date>? = nil) {
        self.series = series
        _selectedDate = selectedDate
        self.domain = domain
    }

    private var yScale: AIUsageAnalytics.TokenAxisScale {
        AIUsageAnalytics.tokenAxisScale(values: series.map(\.totalTokens), desiredCount: 5)
    }

    private var hasUsage: Bool {
        series.contains { $0.totalTokens > 0 }
    }

    private var xDomain: ClosedRange<Date> {
        if let domain { return domain }
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

    var body: some View {
        Group {
            if !series.isEmpty {
                chart
            } else {
                EmptyState(symbol: "chart.line.downtrend.xyaxis", title: AppLocalization.text("暂无 Token 用量"))
            }
        }
        .accessibilityLabel(AppLocalization.string(hasUsage ? "Token 消耗趋势" : "暂无 AI token 用量", locale: locale))
    }

    private var chart: some View {
        let scale = yScale
        return Chart {
            ForEach(series, id: \.timestamp) { point in
                AreaMark(
                    x: .value(AppLocalization.text("时间"), point.timestamp),
                    y: .value(AppLocalization.text("总 Token"), point.totalTokens)
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
                    x: .value(AppLocalization.text("时间"), point.timestamp),
                    y: .value(AppLocalization.text("总 Token"), point.totalTokens)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if let selectedDate, selectedDate >= xDomain.lowerBound, selectedDate < xDomain.upperBound {
                let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                let midpoint = selectedDate.addingTimeInterval(nextDay.timeIntervalSince(selectedDate) / 2)
                RuleMark(x: .value(AppLocalization.text("时间"), midpoint))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                if let selected = series.first(where: { Calendar.current.isDate($0.timestamp, inSameDayAs: selectedDate) }) {
                    PointMark(x: .value(AppLocalization.text("时间"), selected.timestamp),
                        y: .value(AppLocalization.text("总 Token"), selected.totalTokens))
                        .foregroundStyle(Color.blue)
                        .symbolSize(30)
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...scale.upperBound, type: scale.chartScaleType)
        .chartYAxis {
            AxisMarks(position: .leading, values: scale.ticks) { value in
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
        .chartXAxis(.hidden)
        .chartPlotStyle { plot in
            plot.padding(.bottom, 14)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    ForEach(dateLabels, id: \.timestamp) { point in
                        if let x = proxy.position(forX: point.timestamp) {
                            Text(point.timestamp, format: .dateTime.month(.twoDigits).day(.twoDigits))
                                .font(.islandMicro(design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .alignmentGuide(HorizontalAlignment.center) { size in
                                    min(frame.minX + x, max(size.width / 2,
                                        frame.minX + x + size.width - geometry.size.width))
                                }
                                .frame(width: 0, alignment: .center)
                                .position(x: frame.minX + x, y: frame.maxY + 8)
                        }
                    }
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in
                            guard frame.contains(tap.location),
                                  let date: Date = proxy.value(atX: tap.location.x - frame.minX),
                                  let day = Self.selectionDate(at: date, domain: xDomain) else { return }
                            selectedDate = day
                        })
                }
            }
        }
    }

    private var dateLabels: [UsageBreakdownPoint] {
        guard series.count > 7 else { return series }
        let strideCount = max(1, Int(ceil(Double(series.count - 1) / 4)))
        return series.enumerated().filter { $0.offset % strideCount == 0 || $0.offset == series.count - 1 }.map(\.element)
    }

    /// Chart coordinates select their calendar day even when a long-range trend omits intermediate points.
    static func selectionDate(at date: Date, domain: ClosedRange<Date>, calendar: Calendar = .current) -> Date? {
        guard date >= domain.lowerBound, date < domain.upperBound else { return nil }
        return calendar.startOfDay(for: date)
    }
}

private extension AIUsageAnalytics.TokenAxisScale {
    /// `slopeAtZero` keeps the zero baseline finite so idle days still render on the log branch.
    var chartScaleType: ScaleType {
        switch kind {
        case .linear: .linear
        case .symmetricLog: .symmetricLog(slopeAtZero: 0.000_001)
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
            .help(AppLocalization.text("在 %@ 中打开会话", task.title))
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
                        .fitsSingleLine()
                    if let failureReason {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(failureReason)
                                .fitsSingleLine()
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
                        .fitsSingleLine()
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
                        .fitsSingleLine()
                        .layoutPriority(1)

                    Spacer(minLength: 2)
                    if task.status == .error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.red)
                            .help(failureReason ?? AppLocalization.text("任务失败"))
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
                .help(failureReason ?? AppLocalization.text("任务失败"))
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
        parts.append(AppLocalization.text("开始 %@", startTimeText(startedAt)))
        if let processIdentifier = task.processIdentifier {
            parts.append("PID \(processIdentifier)")
        }
        parts.append(AppLocalization.text("运行 %@", elapsedText(from: startedAt, to: now)))
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
        return days > 0 ? AppLocalization.text("%ld天 %@", days, clock) : clock
    }

    private var providerColor: Color {
        ProviderBrand.color(for: task.provider)
    }

    private var failureReason: String? {
        guard task.status == .error else { return nil }
        return task.failureReason ?? AppLocalization.text("任务失败，未提供详细原因")
    }
}

struct UsageHeatmap: View {
    enum Layout { case calendar, days }

    var weeks: [[ContributionDay?]]
    @Binding var selectedDate: Date?
    var cellSize: CGFloat?
    var layout: Layout
    @Environment(\.locale) private var locale

    private let gap: CGFloat = 1.5

    init(weeks: [[ContributionDay?]], selectedDate: Binding<Date?> = .constant(nil), cellSize: CGFloat? = nil,
        layout: Layout = .calendar) {
        self.weeks = weeks
        _selectedDate = selectedDate
        self.cellSize = cellSize
        self.layout = layout
    }

    private var fixedGridWidth: CGFloat? {
        if layout == .days { return nil }
        return cellSize.map { CGFloat(weeks.count) * $0 + CGFloat(max(0, weeks.count - 1)) * gap }
    }

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
            if layout == .days {
                HStack(spacing: gap) {
                    ForEach(weeks.flatMap { $0 }.compactMap { $0 }, id: \.date) { day in
                        VStack(spacing: 3) {
                            UsageCalendarCell(day: day, intensity: intensity(for: day.tokens),
                                isSelected: isSelected(day), select: { selectedDate = $0 })
                                .frame(width: cellSize, height: cellSize)
                            Button { selectedDate = day.date } label: {
                                Text(day.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                                    .font(.islandMicro(design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            .buttonStyle(.plain)
                            .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                calendarGrid
            }

            HStack(spacing: 4) {
                Text(AppLocalization.text("少"))
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
                Text(AppLocalization.text("多 · %@", maxLabel))
                    .font(.islandMicro(design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let selectedDay {
                HStack(spacing: 4) {
                    Text(selectedDay.date, format: .dateTime.year().month().day())
                    Text("· \(AIUsageAnalytics.formatTokenAxisValue(selectedDay.tokens)) Token")
                    Spacer(minLength: 0)
                }
                .font(.islandMicro(design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: fixedGridWidth.map { max(240, $0) }, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.string("AI token 用量热力图", locale: locale))
    }

    private var calendarGrid: some View {
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
            .frame(width: fixedGridWidth, height: cellSize.map { $0 * 7 + gap * 6 }, alignment: .leading)

            GeometryReader { proxy in
                let width = cellWidth(in: fixedGridWidth ?? proxy.size.width)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(weeks.indices, id: \.self) { index in
                        let label = monthLabel(in: weeks[index])
                        let remainingWidth = proxy.size.width - CGFloat(index) * (width + gap)
                        Text(label ?? "")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.75))
                            .fixedSize(horizontal: true, vertical: false)
                            .alignmentGuide(.leading) { dimensions in
                                max(0, dimensions.width - remainingWidth)
                            }
                            .frame(width: width, alignment: .leading)
                            .opacity(label == nil ? 0 : 1)
                    }
                }
            }
            .frame(width: fixedGridWidth.map { max(240, $0) }, height: 13)
        }
    }

    private func isSelected(_ day: ContributionDay?) -> Bool {
        guard let day, let selectedDate else { return false }
        return Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
    }

    private var gridAspectRatio: CGFloat {
        guard !weeks.isEmpty else { return 1 }
        if let cellSize, let fixedGridWidth { return fixedGridWidth / (cellSize * 7 + gap * 6) }
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
        return AppLocalization.text("%ld月", Calendar.current.component(.month, from: date))
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
