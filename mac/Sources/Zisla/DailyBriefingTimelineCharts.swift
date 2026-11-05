import Charts
import SwiftUI
import ZislaCore

struct DailyBriefingTimelinePoint: Identifiable, Equatable {
    let hour: Double
    let value: Double
    let segment: Int

    var id: Double { hour }
}

struct DailyBriefingKeyPressChart: View {
    let hourlyCounts: [Int64?]?
    let language: AppLanguage
    let accent: Color
    let ink: Color

    var points: [DailyBriefingTimelinePoint]? {
        guard let hourlyCounts, hourlyCounts.count == 24,
              hourlyCounts.compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else { return nil }
        var previousHour: Int?
        var segment = 0
        return hourlyCounts.enumerated().compactMap { hour, count in
            guard let count else { return nil }
            if let previousHour, hour > previousHour + 1 { segment += 1 }
            previousHour = hour
            return DailyBriefingTimelinePoint(hour: Double(hour), value: Double(count), segment: segment)
        }
    }

    var hasData: Bool { points?.isEmpty == false }

    var body: some View {
        DailyBriefingTimelinePlot(
            title: AppLocalization.string("键盘敲击走势", language: language),
            points: points,
            domain: 0...24,
            ticks: [0, 6, 12, 18, 24],
            timeLabel: { $0.formatted(.number.locale(language.locale)) },
            unitSuffix: "",
            language: language,
            accent: accent,
            ink: ink
        )
    }
}

struct DailyBriefingPowerChart: View {
    let samples: [DailyBriefingPowerSample]?
    let day: Date
    let calendar: Calendar
    let language: AppLanguage
    let accent: Color
    let ink: Color

    var dayInterval: DateInterval { calendar.dateInterval(of: .day, for: day)! }
    var domain: ClosedRange<Double> { 0...(dayInterval.duration / 3600) }

    var points: [DailyBriefingTimelinePoint]? {
        samples.map { samples in
            let interval = dayInterval
            let selected = samples.filter {
                $0.date >= interval.start && $0.date < interval.end
                    && $0.averageWatts.isFinite && $0.averageWatts >= 0 && $0.sampleCount > 0
            }
                .sorted { $0.date < $1.date }
            var previousDate: Date?
            var segment = 0
            return selected.map { sample in
                if let previousDate, sample.date.timeIntervalSince(previousDate) > 300 { segment += 1 }
                previousDate = sample.date
                return DailyBriefingTimelinePoint(
                    hour: sample.date.timeIntervalSince(interval.start) / 3600,
                    value: sample.averageWatts,
                    segment: segment
                )
            }
        }
    }

    var hasData: Bool { points?.isEmpty == false }

    var ticks: [Double] {
        [0, 6, 12, 18].map { hour in
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayInterval.start)!
                .timeIntervalSince(dayInterval.start) / 3600
        } + [domain.upperBound]
    }

    func timeLabel(_ hour: Double) -> String {
        dayInterval.start.addingTimeInterval(hour * 3600).formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: language.locale,
                calendar: calendar, timeZone: calendar.timeZone)
        )
    }

    var body: some View {
        DailyBriefingTimelinePlot(
            title: AppLocalization.string("功率走势", language: language),
            points: points,
            domain: domain,
            ticks: ticks,
            timeLabel: timeLabel,
            unitSuffix: " W",
            language: language,
            accent: accent,
            ink: ink
        )
    }
}

private struct DailyBriefingTimelinePlot: View {
    let title: String
    let points: [DailyBriefingTimelinePoint]?
    let domain: ClosedRange<Double>
    let ticks: [Double]
    let timeLabel: (Double) -> String
    let unitSuffix: String
    let language: AppLanguage
    let accent: Color
    let ink: Color

    var body: some View {
        if let points, !points.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                Text(title).font(.system(size: 18, weight: .semibold))
                let segmentCounts = Dictionary(grouping: points, by: \.segment).mapValues(\.count)
                Chart(points) { point in
                    LineMark(
                        x: .value(AppLocalization.string("时间", language: language), point.hour),
                        y: .value(title, point.value),
                        series: .value("Segment", point.segment)
                    )
                    .foregroundStyle(accent)
                    if segmentCounts[point.segment] == 1 {
                        PointMark(x: .value(AppLocalization.string("时间", language: language), point.hour), y: .value(title, point.value))
                            .foregroundStyle(accent)
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: 0...max(1, points.map(\.value).max()!))
                .chartXAxis {
                    AxisMarks(values: ticks) { value in
                        AxisGridLine().foregroundStyle(ink.opacity(0.07))
                        AxisValueLabel {
                            if let hour = value.as(Double.self) {
                                Text(timeLabel(hour)).font(.system(size: 12)).foregroundStyle(ink.opacity(0.55))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(ink.opacity(0.07))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.notation(.compactName)
                                    .precision(.fractionLength(0...1)).locale(language.locale)) + unitSuffix)
                                    .font(.system(size: 12)).foregroundStyle(ink.opacity(0.55))
                            }
                        }
                    }
                }
                .frame(height: 170)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .accessibilityLabel(title)
        }
    }
}
