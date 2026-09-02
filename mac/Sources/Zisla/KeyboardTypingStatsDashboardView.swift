import Charts
import KeyboardKit
import SwiftUI

/// Zisla-native presentation for keyboard statistics. It intentionally uses the app design tokens
/// instead of embedding KeyboardKit's standalone statistics window.
struct KeyboardTypingStatsDashboardView: View {
    let summary: KeyboardTypingStatsSummary

    private var accent: Color { Color.accentColor }

    var body: some View {
        compactDashboard
        .foregroundStyle(.primary)
    }

    private var compactDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricsGrid
            activityPanels
            keyboardPanel
            applicationPanel
        }
    }

    private var activityPanels: some View {
        HStack(alignment: .top, spacing: 10) {
            trendPanel
                .frame(maxWidth: .infinity, alignment: .top)
            historyPanel
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var metricsGrid: some View {
        HStack(spacing: 8) {
            compactMetricCard(
                symbol: "character.cursor.ibeam",
                title: "今日字符",
                value: summary.todayCharacterCount.formatted(.number),
                detail: "按键估算"
            )
            compactMetricCard(
                symbol: "app.fill",
                title: "最多应用",
                value: summary.todayTopApplication ?? "暂无",
                detail: summary.applications.first.map {
                    "\($0.characterCount.formatted(.number)) 字符"
                } ?? "暂无输入"
            )
            compactMetricCard(
                symbol: "bolt.fill",
                title: "今日峰值",
                value: summary.todayPeakCharactersPerSecond.formatted(.number),
                unit: "字/秒",
                detail: lastInputText
            )
            compactMetricCard(
                symbol: "clock.fill",
                title: "活跃时间",
                value: durationText(summary.todayActiveSeconds),
                detail: "\(summary.todayActiveMinuteBuckets.formatted(.number)) 分钟"
            )
        }
    }

    private func compactMetricCard(
        symbol: String,
        title: String,
        value: String,
        unit: String? = nil,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let unit {
                    Text(unit)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .statsPanel(padding: 0)
    }

    private var trendPanel: some View {
        statsPanel(title: "输入趋势", symbol: "waveform.path.ecg") {
            chartView
                .frame(height: 110)
        }
    }

    private var chartView: some View {
        Chart(summary.recentBuckets) { bucket in
            BarMark(
                x: .value("时间", bucket.start),
                y: .value("字符数", bucket.characterCount)
            )
            .foregroundStyle(accent.opacity(0.16))
            .cornerRadius(2)
            LineMark(
                x: .value("时间", bucket.start),
                y: .value("字符数", bucket.characterCount)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(accent)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(Color.dividerSubtle)
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(Color.dividerSubtle)
                AxisValueLabel()
            }
        }
        .accessibilityLabel("输入趋势")
    }

    private var historyPanel: some View {
        statsPanel(title: "历史", symbol: "calendar") {
            Chart(summary.history) { day in
                LineMark(
                    x: .value("日期", day.date, unit: .day),
                    y: .value("字符数", day.characterCount),
                    series: .value("系列", "字符数")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                LineMark(
                    x: .value("日期", day.date, unit: .day),
                    y: .value("峰值", day.peakCharactersPerSecond),
                    series: .value("系列", "峰值")
                )
                .foregroundStyle(Color.zislaInfo)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) {
                    AxisGridLine().foregroundStyle(Color.dividerSubtle)
                    AxisValueLabel(format: .dateTime.month(.twoDigits).day(.twoDigits))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Color.dividerSubtle)
                    AxisValueLabel()
                }
            }
            .frame(height: 110)
        }
    }

    private var keyboardPanel: some View {
        statsPanel(title: "键盘", symbol: "keyboard") {
            HStack(spacing: 8) {
                keyboardCount("今日按键", summary.todayKeyPressCount)
                keyboardCount("累计按键", summary.allTimeKeyPressCount)
                Spacer()
            }
            KeyboardHeatmapView(
                todayCounts: summary.todayKeyCounts,
                allTimeCounts: summary.allTimeKeyCounts
            )
            .frame(height: 270)
        }
    }

    private func keyboardCount(_ title: String, _ count: Int64) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(count.formatted(.number))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
    }

    private var applicationPanel: some View {
        statsPanel(title: "应用时间线", symbol: "app.fill") {
            if summary.applicationTimelines.isEmpty {
                Text("记录输入后会在这里展示应用时间线。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(summary.applicationTimelines) { timeline in
                        HStack(spacing: 8) {
                            Text(timeline.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .frame(width: 110, alignment: .leading)
                            GeometryReader { proxy in
                                HStack(alignment: .bottom, spacing: Self.timelineBucketSpacing) {
                                    ForEach(timeline.buckets) { bucket in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(accent.opacity(bucket.characterCount > 0 ? 0.72 : 0.08))
                                            .frame(height: max(4, proxy.size.height * CGFloat(min(1, Double(bucket.characterCount) / Double(max(1, timeline.buckets.map(\.characterCount).max() ?? 1))))))
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            }
                            .frame(height: 24)
                            Text(timeline.buckets.reduce(0) { $0 + $1.characterCount }.formatted(.number))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                    timelineAxis
                }
            }
        }
    }

    /// Anchor ticks to the bucket geometry (first edge, middle edge, and last edge)
    /// instead of evenly spacing labels, which drifts when the bucket count is odd.
    struct TimelineAxisTick {
        let date: Date
        let x: CGFloat
        let anchor: Alignment
    }

    /// Shared by the application bars and axis so both use the same bucket spacing.
    static let timelineBucketSpacing: CGFloat = 1

    static func timelineAxisTicks(
        buckets: [KeyboardTypingStatsTrendPoint],
        width: CGFloat,
        spacing: CGFloat = timelineBucketSpacing
    ) -> [TimelineAxisTick] {
        guard buckets.count > 1, width > 0 else { return [] }

        let count = CGFloat(buckets.count)
        let cellWidth = max(0, (width - spacing * (count - 1)) / count)
        let pitch = cellWidth + spacing
        let middleIndex = buckets.count / 2
        // Derive the final boundary from adjacent starts instead of duplicating bucketSeconds here.
        let step = buckets[1].start.timeIntervalSince(buckets[0].start)

        // Keep all ticks on time boundaries: bucket starts and the final end boundary.
        // Using a bucket center while labeling its start would create a semantic offset.
        return [
            TimelineAxisTick(date: buckets[0].start, x: 0, anchor: .leading),
            TimelineAxisTick(
                date: buckets[middleIndex].start,
                x: CGFloat(middleIndex) * pitch,
                anchor: .center
            ),
            TimelineAxisTick(
                date: buckets[buckets.count - 1].start.addingTimeInterval(step),
                x: CGFloat(buckets.count - 1) * pitch + cellWidth,
                anchor: .trailing
            ),
        ]
    }

    private var timelineAxis: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 110, height: 1)
            GeometryReader { proxy in
                let ticks = Self.timelineAxisTicks(
                    buckets: summary.applicationTimelines.first?.buckets ?? [],
                    width: proxy.size.width
                )
                ZStack(alignment: .topLeading) {
                    ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                        Rectangle()
                            .fill(Color.dividerSubtle)
                            .frame(width: 1, height: 3)
                            .offset(x: min(max(0, tick.x - 0.5), max(0, proxy.size.width - 1)))
                    }
                    ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                        Text(timelineAxisLabel(tick.date))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .frame(width: 0, alignment: tick.anchor)
                            .offset(x: tick.x, y: 4)
                    }
                }
                .frame(width: proxy.size.width, alignment: .topLeading)
            }
            .frame(height: 14)
            Color.clear.frame(width: 52, height: 1)
        }
        .accessibilityHidden(true)
    }

    private func timelineAxisLabel(_ date: Date) -> String {
        switch summary.timelineRange {
        case "7d":
            // A seven-day window needs the date to distinguish repeated times of day.
            return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)))
        case "24h", "6h", "1h":
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        default:
            return date.formatted(.dateTime.hour().minute())
        }
    }

    private func statsPanel<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            content()
        }
        .statsPanel()
    }

    private var lastInputText: String {
        guard let date = summary.lastInputAt else { return "暂无输入" }
        return "最近输入 \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func durationText(_ seconds: Int64) -> String {
        let minutes = max(0, seconds) / 60
        if minutes >= 60 { return "\(minutes / 60) 小时 \(minutes % 60) 分" }
        return "\(minutes) 分钟"
    }
}

private struct KeyboardHeatmapView: View {
    let todayCounts: [UInt16: Int64]
    let allTimeCounts: [UInt16: Int64]
    var compact = false

    private var accent: Color { Color.accentColor }

    private struct Key: Identifiable {
        let id: String
        let label: String
        let keyCode: UInt16?
        let widthUnits: CGFloat
        let systemImage: String?

        init(
            _ id: String,
            _ label: String,
            _ keyCode: UInt16?,
            widthUnits: CGFloat = 1,
            systemImage: String? = nil
        ) {
            self.id = id
            self.label = label
            self.keyCode = keyCode
            self.widthUnits = widthUnits
            self.systemImage = systemImage
        }
    }

    private let rows: [[Key]] = [
        [
            Key("escape", "esc", 53, widthUnits: 1.5),
            Key("f1", "F1", 122), Key("f2", "F2", 120), Key("f3", "F3", 99),
            Key("f4", "F4", 118), Key("f5", "F5", 96), Key("f6", "F6", 97),
            Key("f7", "F7", 98), Key("f8", "F8", 100), Key("f9", "F9", 101),
            Key("f10", "F10", 109), Key("f11", "F11", 103), Key("f12", "F12", 111),
            Key("lock", "", nil, systemImage: "lock.fill"),
        ],
        [
            Key("backquote", "`", 50), Key("digit1", "1", 18), Key("digit2", "2", 19),
            Key("digit3", "3", 20), Key("digit4", "4", 21), Key("digit5", "5", 23),
            Key("digit6", "6", 22), Key("digit7", "7", 26), Key("digit8", "8", 28),
            Key("digit9", "9", 25), Key("digit0", "0", 29), Key("minus", "-", 27),
            Key("equal", "=", 24), Key("backspace", "delete", 51, widthUnits: 1.5),
        ],
        [
            Key("tab", "tab", 48, widthUnits: 1.5), Key("q", "Q", 12), Key("w", "W", 13),
            Key("e", "E", 14), Key("r", "R", 15), Key("t", "T", 17), Key("y", "Y", 16),
            Key("u", "U", 32), Key("i", "I", 34), Key("o", "O", 31), Key("p", "P", 35),
            Key("leftBracket", "[", 33), Key("rightBracket", "]", 30), Key("backslash", "\\", 42),
        ],
        [
            Key("capsLock", "caps", 57, widthUnits: 1.75), Key("a", "A", 0), Key("s", "S", 1),
            Key("d", "D", 2), Key("f", "F", 3), Key("g", "G", 5), Key("h", "H", 4),
            Key("j", "J", 38), Key("k", "K", 40), Key("l", "L", 37), Key("semicolon", ";", 41),
            Key("quote", "'", 39), Key("enter", "return", 36, widthUnits: 1.75),
        ],
        [
            Key("leftShift", "shift", 56, widthUnits: 2.25), Key("z", "Z", 6), Key("x", "X", 7),
            Key("c", "C", 8), Key("v", "V", 9), Key("b", "B", 11), Key("n", "N", 45),
            Key("m", "M", 46), Key("comma", ",", 43), Key("period", ".", 47),
            Key("slash", "/", 44), Key("rightShift", "shift", 60, widthUnits: 2.25),
        ],
        [
            Key("function", "fn", 63), Key("leftControl", "control", 59), Key("leftOption", "option", 58),
            Key("leftCommand", "⌘", 55, widthUnits: 1.25), Key("space", "space", 49, widthUnits: 5),
            Key("rightCommand", "⌘", 54, widthUnits: 1.25), Key("rightOption", "option", 61),
            Key("leftArrow", "←", 123), Key("upArrow", "↑", 126), Key("downArrow", "↓", 125),
            Key("rightArrow", "→", 124),
        ],
    ]

    private var maximum: Int64 { max(1, todayCounts.values.max() ?? 0) }

    var body: some View {
        GeometryReader { proxy in
            let keyGap: CGFloat = compact ? 3 : 5
            let rowGap: CGFloat = compact ? 3 : 6
            VStack(spacing: rowGap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let totalUnits = row.reduce(CGFloat.zero) { $0 + $1.widthUnits }
                    let totalGaps = keyGap * CGFloat(max(0, row.count - 1))
                    let unit = max(1, (proxy.size.width - totalGaps) / totalUnits)
                    HStack(spacing: keyGap) {
                        ForEach(row) { key in
                            keycap(key, unit: unit)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: CGFloat(rows.count) * (compact ? 22 : 38) + CGFloat(rows.count - 1) * (compact ? 3 : 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("键盘按键热力图")
    }

    private func keycap(_ key: Key, unit: CGFloat) -> some View {
        let todayCount = key.keyCode.map { todayCounts[$0, default: 0] } ?? 0
        let allTimeCount = key.keyCode.map { allTimeCounts[$0, default: 0] } ?? 0
        let fillOpacity = key.keyCode == nil
            ? 0.08
            : 0.08 + 0.68 * Double(todayCount) / Double(maximum)

        return VStack(spacing: 2) {
            if let systemImage = key.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 8 : 10, weight: .semibold))
            } else {
                Text(key.label)
                    .font(.system(size: compact ? 8 : 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            if !compact, key.keyCode != nil {
                Text("\(todayCount.formatted(.number)) / \(allTimeCount.formatted(.number))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: max(10, unit * key.widthUnits), height: compact ? 22 : 38)
        .background(
            accent.opacity(fillOpacity),
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.strokeCard, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(key.systemImage == nil ? key.label : "锁定")
        .accessibilityValue(key.keyCode.map { _ in "今日 \(todayCount.formatted(.number))，累计 \(allTimeCount.formatted(.number))" } ?? "")
    }
}

private extension View {
    func statsPanel(padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(Color.fillCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.strokeCard, lineWidth: 0.7)
            }
    }
}
