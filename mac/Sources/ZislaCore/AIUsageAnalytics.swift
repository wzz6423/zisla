import Foundation

/// 一个小时窗口的用量聚合。
public struct HourlyBucket: Equatable, Sendable {
    public var start: Date
    public var tokens: Int

    public init(start: Date, tokens: Int) {
        self.start = start
        self.tokens = tokens
    }
}

/// 用量趋势图上的一个采样点（时间戳 + token 数）。
public struct UsagePoint: Equatable, Sendable {
    public var timestamp: Date
    public var tokens: Int

    public init(timestamp: Date, tokens: Int) {
        self.timestamp = timestamp
        self.tokens = tokens
    }
}

/// 趋势图中一个自然日的输入、输出与总 token 明细。
public struct UsageBreakdownPoint: Equatable, Sendable {
    public var timestamp: Date
    public var inputTokens: Int
    public var outputTokens: Int

    public init(timestamp: Date, inputTokens: Int, outputTokens: Int) {
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    public var totalTokens: Int { inputTokens + outputTokens }
}

/// 累计用量多序列上的一个采样点（总量 / 输入 / 输出）。
public struct CumulativeUsagePoint: Equatable, Sendable {
    public var timestamp: Date
    public var totalTokens: Int
    public var inputTokens: Int
    public var outputTokens: Int

    public init(
        timestamp: Date,
        totalTokens: Int,
        inputTokens: Int,
        outputTokens: Int
    ) {
        self.timestamp = timestamp
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// 贡献日历中的单日单元（日期 + 当天 token 总量）。
public struct ContributionDay: Equatable, Sendable {
    public var date: Date
    public var tokens: Int

    public init(date: Date, tokens: Int) {
        self.date = date
        self.tokens = tokens
    }
}

/// 按 GitHub 风格贡献图阶梯划分的 token 用量强度（供 SwiftUI 上色）。
///
/// 阈值：0 / 50M / 100M / 150M / 200M。
/// `none` 表示无用量；`level4` 为 200M 及以上最深色。
public enum ContributionIntensity: Int, Equatable, Sendable, CaseIterable, Comparable {
    case none = 0
    case level1 = 1
    case level2 = 2
    case level3 = 3
    case level4 = 4

    public static let thresholds: [Int] = [
        0,
        50_000_000,
        100_000_000,
        150_000_000,
        200_000_000,
    ]

    public static func < (lhs: ContributionIntensity, rhs: ContributionIntensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 将 token 总量映射到公开强度分类。
    /// - 0：无用量
    /// - (0, 50M]：level1
    /// - (50M, 100M]：level2
    /// - (100M, 150M]：level3
    /// - (150M, +∞)（含 200M 及以上）：level4 最深
    public static func classify(tokens: Int) -> ContributionIntensity {
        if tokens <= 0 { return .none }
        if tokens <= thresholds[1] { return .level1 }
        if tokens <= thresholds[2] { return .level2 }
        if tokens <= thresholds[3] { return .level3 }
        return .level4
    }
}

public enum AIUsageAnalytics {
    /// 最近 `days` 个自然日（含 `end` 当天）的总、输入和输出 token 趋势。
    ///
    /// 零用量日期也保留在结果中，因此时间轴连续，曲线能真实落到零基线。
    public static func dailyUsageSeries(
        samples: [AIUsageSample],
        endingAt end: Date,
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [UsageBreakdownPoint] {
        guard days > 0 else { return [] }
        let endDay = calendar.startOfDay(for: end)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else {
            return []
        }

        var inputByDay: [Date: Int] = [:]
        var outputByDay: [Date: Int] = [:]
        for sample in samples where sample.timestamp <= end {
            let day = calendar.startOfDay(for: sample.timestamp)
            guard day >= startDay, day <= endDay else { continue }
            inputByDay[day, default: 0] += sample.inputTokens
            outputByDay[day, default: 0] += sample.outputTokens
        }

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }
            return UsageBreakdownPoint(
                timestamp: day,
                inputTokens: inputByDay[day, default: 0],
                outputTokens: outputByDay[day, default: 0]
            )
        }
    }

    /// 使用 5 日二项式加权 [1,4,6,4,1] 平滑日用量，供趋势曲线展示。
    /// 这样能让折线呈现圆润的流动感，避免单日尖峰或零值造成锐利起伏。
    /// 原始日汇总仍保留给热力图，避免单日缓存回填让折线产生不自然的陡降。
    public static func smoothedDailyUsageSeries(
        samples: [AIUsageSample],
        endingAt end: Date,
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [UsageBreakdownPoint] {
        let daily = dailyUsageSeries(
            samples: samples,
            endingAt: end,
            days: days,
            calendar: calendar
        )
        guard daily.count > 2 else { return daily }

        let weights = [1.0, 4.0, 6.0, 4.0, 1.0]
        let totalWeight = weights.reduce(0, +)
        let radius = weights.count / 2

        return daily.indices.map { index in
            var input = 0.0
            var output = 0.0
            for offset in -radius...radius {
                let sourceIndex = max(0, min(daily.count - 1, index + offset))
                let weight = weights[offset + radius]
                input += Double(daily[sourceIndex].inputTokens) * weight
                output += Double(daily[sourceIndex].outputTokens) * weight
            }
            return UsageBreakdownPoint(
                timestamp: daily[index].timestamp,
                inputTokens: Int((input / totalWeight).rounded()),
                outputTokens: Int((output / totalWeight).rounded())
            )
        }
    }

    /// 截至 end 的最近 `hours` 个滚动小时窗口，最老的桶在前、最新的在后。
    /// 每个桶为左闭右开区间 [start, start+1h)。
    public static func hourlySeries(
        samples: [AIUsageSample],
        endingAt end: Date,
        hours: Int,
        calendar: Calendar = .current
    ) -> [HourlyBucket] {
        guard hours > 0 else { return [] }
        let start = end.addingTimeInterval(-Double(hours) * 3_600)
        var tokens = Array(repeating: 0, count: hours)

        for sample in samples where sample.timestamp >= start && sample.timestamp < end {
            let index = Int(sample.timestamp.timeIntervalSince(start) / 3_600)
            guard index < hours else { continue }
            tokens[index] += sample.totalTokens
        }

        return tokens.enumerated().map { index, value in
            HourlyBucket(
                start: start.addingTimeInterval(Double(index) * 3_600),
                tokens: value
            )
        }
    }

    /// 截至 `end` 的最近历史用量采样，按时间升序，最多 `limit` 条。
    ///
    /// - 仅保留时间戳不晚于 `end`、且 token 总量为正的采样；忽略未来与零值。
    /// - 超出 `limit` 时保留最近的 `limit` 条（丢弃更早的）。
    /// - 在第一条实际采样前插入一个 `tokens == 0` 的基线点（时间戳早于首条采样），
    ///   使仅有一条历史用量时折线图仍能从零起画出上升趋势。基线点不计入 `limit`。
    /// - 无有效采样时返回空数组。
    public static func recentUsageSeries(
        samples: [AIUsageSample],
        endingAt end: Date,
        limit: Int
    ) -> [UsagePoint] {
        guard limit > 0 else { return [] }

        let recent = samples
            .filter { $0.timestamp <= end && $0.totalTokens > 0 }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(limit)

        guard let first = recent.first else { return [] }

        // 基线点比首条采样早 1 秒即可保证 x 轴严格递增，从而画出上升趋势。
        var points: [UsagePoint] = [UsagePoint(timestamp: first.timestamp.addingTimeInterval(-1), tokens: 0)]
        points.append(contentsOf: recent.map { UsagePoint(timestamp: $0.timestamp, tokens: $0.totalTokens) })
        return points
    }

    /// 截至 `end` 的累计用量曲线：每个真实时间点的 `tokens` 为「截至该点的历史累计总量」，
    /// 用于表达全历史总用量的增长趋势（区别于 `recentUsageSeries` 的单次 token）。
    ///
    /// - 仅纳入时间戳不晚于 `end`、且 token 总量为正的采样；忽略未来与零值。
    /// - 按时间升序排列；同一时间戳的多条采样合并为一个点（token 相加），不产生重复时间戳。
    /// - 在首个采样前插入一个 `tokens == 0` 的基线点（时间戳早于首条采样 1 秒），
    ///   使仅有一条历史用量时也能从零起画出上升趋势。
    /// - 每个真实时间点的 `tokens` 为截至该点的累计总量（前缀和）。
    /// - 若 `end` 晚于最后一个采样点，追加一个位于 `end`、`tokens` 为累计总量的终点，
    ///   使曲线延伸到当前时刻并保持在总量高度；`end` 恰为末点时不追加。
    /// - 无有效采样时返回空数组。
    public static func cumulativeUsageSeries(
        samples: [AIUsageSample],
        endingAt end: Date
    ) -> [UsagePoint] {
        let valid = samples
            .filter { $0.timestamp <= end && $0.totalTokens > 0 }
            .sorted { $0.timestamp < $1.timestamp }

        guard let first = valid.first else { return [] }

        var points: [UsagePoint] = [UsagePoint(timestamp: first.timestamp.addingTimeInterval(-1), tokens: 0)]
        var cumulative = 0
        var index = 0
        while index < valid.count {
            // 排序后同时间戳采样相邻，合并求和后累计到前缀和，输出单个点。
            let timestamp = valid[index].timestamp
            while index < valid.count, valid[index].timestamp == timestamp {
                cumulative += valid[index].totalTokens
                index += 1
            }
            points.append(UsagePoint(timestamp: timestamp, tokens: cumulative))
        }

        if let last = points.last, end > last.timestamp {
            points.append(UsagePoint(timestamp: end, tokens: cumulative))
        }
        return points
    }

    /// 截至 `end` 的累计多序列：每个时间点同时给出总量 / 输入 / 输出的历史累计。
    ///
    /// - 仅纳入时间戳不晚于 `end`、且 token 总量为正的采样；忽略未来与零值。
    /// - 按时间升序；同一时间戳的多条采样合并（input/output 分别相加）。
    /// - 首个采样前插入零基线点（时间戳早 1 秒）。
    /// - 若 `end` 晚于末点，追加终点并保持累计高度。
    /// - 无有效采样时返回空数组。
    public static func cumulativeDetailSeries(
        samples: [AIUsageSample],
        endingAt end: Date
    ) -> [CumulativeUsagePoint] {
        let valid = samples
            .filter { $0.timestamp <= end && $0.totalTokens > 0 }
            .sorted { $0.timestamp < $1.timestamp }

        guard let first = valid.first else { return [] }

        var points: [CumulativeUsagePoint] = [
            CumulativeUsagePoint(
                timestamp: first.timestamp.addingTimeInterval(-1),
                totalTokens: 0,
                inputTokens: 0,
                outputTokens: 0
            )
        ]
        var cumulativeInput = 0
        var cumulativeOutput = 0
        var index = 0
        while index < valid.count {
            let timestamp = valid[index].timestamp
            while index < valid.count, valid[index].timestamp == timestamp {
                cumulativeInput += max(0, valid[index].inputTokens)
                cumulativeOutput += max(0, valid[index].outputTokens)
                index += 1
            }
            points.append(
                CumulativeUsagePoint(
                    timestamp: timestamp,
                    totalTokens: cumulativeInput + cumulativeOutput,
                    inputTokens: cumulativeInput,
                    outputTokens: cumulativeOutput
                )
            )
        }

        if let last = points.last, end > last.timestamp {
            points.append(
                CumulativeUsagePoint(
                    timestamp: end,
                    totalTokens: cumulativeInput + cumulativeOutput,
                    inputTokens: cumulativeInput,
                    outputTokens: cumulativeOutput
                )
            )
        }
        return points
    }

    /// 为趋势图纵轴生成「漂亮」刻度（含 0 与覆盖 `maximum` 的上界）。
    ///
    /// - `maximum <= 0` 时返回 `[0, 1]`，保证 Chart 有合法 domain。
    /// - `desiredCount` 控制期望刻度数量（含两端），夹在 2...6。
    /// - 步长取 1/2/5×10^n，标签可用 `formatTokenAxisValue`。
    public static func tokenAxisTicks(maximum: Int, desiredCount: Int = 3) -> [Int] {
        let count = min(6, max(2, desiredCount))
        guard maximum > 0 else { return [0, 1] }

        let rawStep = Double(maximum) / Double(count - 1)
        let magnitude = pow(10.0, floor(log10(max(rawStep, 1))))
        let residual = rawStep / magnitude
        let niceResidual: Double
        if residual <= 1 {
            niceResidual = 1
        } else if residual <= 2 {
            niceResidual = 2
        } else if residual <= 5 {
            niceResidual = 5
        } else {
            niceResidual = 10
        }
        let step = max(1, Int((niceResidual * magnitude).rounded()))
        let upper = ((maximum + step - 1) / step) * step

        var ticks: [Int] = []
        var value = 0
        while value < upper {
            ticks.append(value)
            value += step
            if ticks.count > 8 { break }
        }
        if ticks.last != upper {
            ticks.append(upper)
        }
        if ticks.count == 1 {
            ticks.append(upper == 0 ? 1 : upper)
        }
        return ticks
    }

    /// 紧凑 token 纵轴标签（K / M / B），供 Chart 与测试共用。
    public static func formatTokenAxisValue(_ tokens: Int) -> String {
        let value = abs(tokens)
        let sign = tokens < 0 ? "-" : ""
        switch value {
        case 1_000_000_000...:
            let n = Double(value) / 1_000_000_000
            return sign + formatCompact(n) + "B"
        case 1_000_000...:
            let n = Double(value) / 1_000_000
            return sign + formatCompact(n) + "M"
        case 1_000...:
            let n = Double(value) / 1_000
            return sign + formatCompact(n) + "K"
        default:
            return sign + "\(value)"
        }
    }

    private static func formatCompact(_ n: Double) -> String {
        if n >= 100 {
            return "\(Int(n.rounded()))"
        }
        let tenths = (n * 10).rounded() / 10
        if tenths.rounded() == tenths {
            return "\(Int(tenths))"
        }
        return String(format: "%.1f", tenths)
    }

    /// 过去 7 天（含今天）× 24 小时的 token 热力图。外层索引 0 为最早的一天、6 为今天。
    public static func weekHeatmap(
        samples: [AIUsageSample],
        endingAt end: Date,
        calendar: Calendar = .current
    ) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        let startOfToday = calendar.startOfDay(for: end)
        for sample in samples where sample.timestamp <= end {
            let startOfSampleDay = calendar.startOfDay(for: sample.timestamp)
            guard
                let days = calendar.dateComponents([.day], from: startOfSampleDay, to: startOfToday).day,
                days >= 0, days < 7
            else { continue }
            let hour = calendar.component(.hour, from: sample.timestamp)
            guard hour >= 0, hour < 24 else { continue }
            grid[6 - days][hour] += sample.totalTokens
        }
        return grid
    }

    /// 以 26 个日历周为列、每列 7 天的贡献日历。
    ///
    /// - 列顺序：最老的一周在前，最近一周在后。
    /// - 行顺序：与 `Calendar` 的 `firstWeekday` 对齐（行 0 为周首日）。
    /// - 范围含 `endingAt` 当天；未来日期不出现（对应位置为 `nil`）。
    /// - 单元含日期（当天 00:00）与该日 token 总量。
    public static func contributionCalendar(
        samples: [AIUsageSample],
        endingAt end: Date,
        weeks: Int = 26,
        calendar: Calendar = .current
    ) -> [[ContributionDay?]] {
        guard weeks > 0 else { return [] }

        let endDay = calendar.startOfDay(for: end)
        // 以 endingAt 所在周为最后一列：找到该周起始日
        let weekday = calendar.component(.weekday, from: endDay)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        guard let lastWeekStart = calendar.date(byAdding: .day, value: -daysFromWeekStart, to: endDay) else {
            return []
        }
        guard let gridStart = calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: lastWeekStart) else {
            return []
        }

        var tokensByDay: [Date: Int] = [:]
        for sample in samples where sample.timestamp <= end {
            let day = calendar.startOfDay(for: sample.timestamp)
            guard day <= endDay else { continue }
            tokensByDay[day, default: 0] += sample.totalTokens
        }

        var grid: [[ContributionDay?]] = []
        grid.reserveCapacity(weeks)
        for week in 0..<weeks {
            var column: [ContributionDay?] = []
            column.reserveCapacity(7)
            for dayOffset in 0..<7 {
                let offset = week * 7 + dayOffset
                guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                    column.append(nil)
                    continue
                }
                // 不显示未来日期（严格晚于 endingAt 当天）
                if date > endDay {
                    column.append(nil)
                } else {
                    column.append(ContributionDay(date: date, tokens: tokensByDay[date] ?? 0))
                }
            }
            grid.append(column)
        }
        return grid
    }
}
