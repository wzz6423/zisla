import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct DailyBriefingReport: Sendable {
    var day: DailyBriefingDay
    var generatedAt: Date
    var typing: DailyBriefingTyping?
    var allDeviceSeconds: TimeInterval?
    var notificationCount: Int? = nil
    var aiUsage: AIDailyModelUsage? = nil
    var selectedContent: Set<DailyBriefingContent> = DailyBriefingContent.defaultSelection
    var calendar = DailyBriefingDay.calendar

    /// Uses deterministic fixture data so previews remain independent of local activity and accounts.
    static func example(at date: Date = Date(), selectedContent: Set<DailyBriefingContent> = DailyBriefingContent.defaultSelection) -> Self {
        let calendar = DailyBriefingDay.calendar
        let start = calendar.startOfDay(for: date)
        var day = DailyBriefingDay(date: date, calendar: calendar)
        day.firstActivity = start.addingTimeInterval(9 * 3600 + 12 * 60)
        day.lastActivity = start.addingTimeInterval(21 * 3600 + 36 * 60)
        day.observedFrom = start.addingTimeInterval(9 * 3600)
        day.observedThrough = day.lastActivity
        day.hourlySeconds = [0, 0, 0, 0, 0, 0, 0, 0, 0, 1800, 3000, 2700, 900, 2100, 3300, 2700, 2400, 1800, 600, 900, 1500, 600, 0, 0]
        day.applications = [
            "com.apple.dt.Xcode": .init(name: "Xcode", category: .work, seconds: 11700),
            "com.apple.Terminal": .init(name: "Terminal", category: .work, seconds: 3600),
            "com.apple.Notes": .init(name: "Notes", category: .work, seconds: 2400),
            "com.apple.Music": .init(name: "Music", category: .leisure, seconds: 2400),
            "org.mozilla.firefox": .init(name: "Firefox", category: .leisure, seconds: 1200),
            "com.apple.MobileSMS": .init(name: "Messages", category: .leisure, seconds: 600),
            "com.apple.Safari": .init(name: "Safari", category: .other, seconds: 600),
            "com.apple.finder": .init(name: "Finder", category: .other, seconds: 600),
            "com.apple.Preview": .init(name: "Preview", category: .other, seconds: 600),
            "com.apple.iCal": .init(name: "Calendar", category: .other, seconds: 300),
            "com.apple.systempreferences": .init(name: "System Settings", category: .other, seconds: 300),
        ]
        day.listeningSeconds = 8100
        day.expansionCount = 42
        day.peakPower = .init(value: 48.6, date: start.addingTimeInterval(14 * 3600 + 23 * 60))
        day.peakFan = .init(value: 2460, date: start.addingTimeInterval(14 * 3600 + 24 * 60))
        day.minimumBattery = 0.32
        day.maximumBattery = 1
        var activity = DailyBriefingActivityTotals()
        for (event, count) in [
            (DailyBriefingActivity.clipboardCaptured, 34), (.clipboardReused, 12),
            (.shelfItemsAdded, 9), (.shelfItemsCopied, 6), (.pomodoroStarted, 5),
            (.noteCreated, 3), (.noteSaved, 7), (.noteDeleted, 1),
            (.quickNoteCreated, 2), (.quickNoteSaved, 4), (.quickNoteDeleted, 1), (.unlocked, 8),
        ] {
            activity.record(event, count: count)
        }
        activity.record(.pomodoroCompleted, count: 3, focusSeconds: 4500)
        day.activity = activity
        day.hourlyKeyPresses = [nil, nil, nil, nil, nil, nil, nil, nil, nil, 1200, 1800, 1600, nil, 1700, 2300, 1900, 1500, 1200, 600, 700, 900, 500, nil, nil]
        day.powerSamples = (0..<144).compactMap { index in
            let sampleDate = start.addingTimeInterval(9 * 3600 + Double(index) * 300)
            guard calendar.component(.hour, from: sampleDate) != 12 else { return nil }
            let phase = Double(index)
            let watts = 24 + 7 * sin(phase / 14) + 3 * cos(phase / 5)
            return DailyBriefingPowerSample(date: sampleDate, averageWatts: watts)
        }
        return Self(day: day, generatedAt: day.lastActivity!, typing: .init(characters: 12846, topApplication: "Xcode", peakHour: 14),
            allDeviceSeconds: 31500, notificationCount: 87,
            aiUsage: AIDailyModelUsage(date: start, inputTokens: 180_000, outputTokens: 32_000, models: [
                AIModelUsage(provider: .codex, model: "gpt-6.1-sol", inputTokens: 120_000, outputTokens: 20_000),
                AIModelUsage(provider: .claude, model: "claude-sonnet-4-5", inputTokens: 60_000, outputTokens: 12_000),
            ]), selectedContent: selectedContent)
    }
}

struct DailyBriefingPoster: View {
    let report: DailyBriefingReport
    let template: DailyBriefingTemplate
    let language: AppLanguage
    private(set) var displayedContent: Set<DailyBriefingContent> = []

    init(report: DailyBriefingReport, template: DailyBriefingTemplate, language: AppLanguage) {
        self.report = report
        self.template = template
        self.language = language
        displayedContent = Set(DailyBriefingContent.allCases.filter {
            report.selectedContent.contains($0) && hasData($0)
        })
    }

    private var locale: Locale { language.locale }
    private var ink: Color { template == .midnight || template == .terminal ? Color(white: 0.94) : Color(red: 0.13, green: 0.16, blue: 0.15) }
    private var background: Color {
        switch template {
        case .minimal: Color.white
        case .paper: Color(red: 0.97, green: 0.95, blue: 0.90)
        case .midnight: Color(red: 0.075, green: 0.09, blue: 0.16)
        case .forest: Color(red: 0.92, green: 0.95, blue: 0.90)
        case .sunrise: Color(red: 1, green: 0.95, blue: 0.88)
        case .terminal: Color(red: 0.055, green: 0.12, blue: 0.14)
        case .coastal: Color(red: 0.92, green: 0.97, blue: 0.99)
        case .blossom: Color(red: 1, green: 0.94, blue: 0.96)
        }
    }
    private var accent: Color {
        switch template {
        case .minimal: Color(red: 0.89, green: 0.34, blue: 0.16)
        case .paper: Color(red: 0.52, green: 0.26, blue: 0.18)
        case .midnight: Color(red: 0.67, green: 0.70, blue: 1)
        case .forest: Color(red: 0.20, green: 0.40, blue: 0.29)
        case .sunrise: Color(red: 0.80, green: 0.30, blue: 0.14)
        case .terminal: Color(red: 0.41, green: 0.90, blue: 0.73)
        case .coastal: Color(red: 0.19, green: 0.45, blue: 0.63)
        case .blossom: Color(red: 0.68, green: 0.34, blue: 0.46)
        }
    }

    private struct MetricItem: Identifiable {
        let id: DailyBriefingContent
        let value: String
    }

    private static let primaryMetrics: [DailyBriefingContent] = [
        .characters, .topTypingApplication, .peakTypingHour, .islandOpenings,
        .listeningTime, .peakPower, .batteryRange, .peakFan,
    ]
    private var primaryMetricItems: [MetricItem] { metricItems(for: Self.primaryMetrics) }
    private var additionalMetricItems: [MetricItem] {
        metricItems(for: DailyBriefingContent.allCases.filter { $0.isDetailMetric && !Self.primaryMetrics.contains($0) })
    }
    private var hasHero: Bool { [DailyBriefingContent.localUsage, .firstActivity, .lastActivity, .allDevicesUsage].contains(where: displayedContent.contains) }
    private var hasCategories: Bool { [DailyBriefingContent.workTime, .leisureTime, .otherTime].contains(where: displayedContent.contains) }
    private var hasUsageData: Bool {
        report.day.hourlySeconds.count == 24 && report.day.hourlySeconds.allSatisfy { $0.isFinite && $0 >= 0 }
            && (report.day.observedFrom != nil || report.day.activeSeconds > 0)
    }

    private var keyPressChart: DailyBriefingKeyPressChart {
        DailyBriefingKeyPressChart(hourlyCounts: report.day.hourlyKeyPresses, language: language, accent: accent, ink: ink)
    }
    private var powerChart: DailyBriefingPowerChart {
        DailyBriefingPowerChart(samples: report.day.powerSamples, day: report.day.date, calendar: report.calendar,
            language: language, accent: accent, ink: ink)
    }

    /// Suppresses empty sections so selecting a metric does not reserve blank poster space.
    private func hasData(_ content: DailyBriefingContent) -> Bool {
        switch content {
        case .hourlyUsage: return hasUsageData
        case .applicationUsage: return !DailyBriefingApplicationChart.rows(for: report.day.applications, language: language).isEmpty
        case .keyPressTrend: return keyPressChart.hasData
        case .powerTrend: return powerChart.hasData
        case .aiModelUsage: return report.aiUsage?.totalTokens ?? 0 > 0
        default: return value(for: content) != nil
        }
    }

    private func metricItems(for contents: [DailyBriefingContent]) -> [MetricItem] {
        contents.compactMap { content in
            guard displayedContent.contains(content), let value = value(for: content) else { return nil }
            return MetricItem(id: content, value: value)
        }
    }

    /// Returns detail values only when the source observation exists; missing readings remain omitted.
    func value(for content: DailyBriefingContent) -> String? {
        switch content {
        case .localUsage: return hasUsageData ? durationValue(report.day.activeSeconds) : nil
        case .firstActivity: return report.day.firstActivity.map(time)
        case .lastActivity: return report.day.lastActivity.map(time)
        case .allDevicesUsage: return durationValue(report.allDeviceSeconds)
        case .workTime, .leisureTime, .otherTime:
            guard hasUsageData, let category = content.category else { return nil }
            return durationValue(report.day.seconds(in: category))
        case .characters: return report.typing.map { $0.characters.formatted(.number.locale(locale)) }
        case .topTypingApplication:
            return report.typing?.topApplication.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        case .peakTypingHour:
            return report.typing?.peakHour.flatMap {
                report.calendar.date(bySettingHour: $0, minute: 0, second: 0, of: report.day.date)
            }.map(time)
        case .islandOpenings:
            guard report.day.activity != nil || hasUsageData || report.day.expansionCount > 0 else { return nil }
            return report.day.expansionCount.formatted(.number.locale(locale))
        case .listeningTime: return durationValue(report.day.listeningSeconds)
        case .peakPower: return report.day.peakPower.map { peak($0, unit: "W") }
        case .batteryRange: return batteryRange
        case .peakFan: return report.day.peakFan.map { peak($0, unit: "RPM") }
        case .notificationCount: return report.notificationCount.map { $0.formatted(.number.locale(locale)) }
        case .completedFocusTime: return durationValue(report.day.activity?.completedFocusSeconds)
        case .hourlyUsage, .applicationUsage, .keyPressTrend, .powerTrend, .aiModelUsage: return nil
        default:
            return content.activity.flatMap { event in
                report.day.activity.map { $0.count(for: event).formatted(.number.locale(locale)) }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            header
            composition
            if !additionalMetricItems.isEmpty {
                metrics(additionalMetricItems, columns: template == .blossom ? 4 : 3)
            }
            if displayedContent.contains(.applicationUsage) {
                DailyBriefingApplicationChart(applications: report.day.applications, language: language,
                    accent: accent, ink: ink, formatDuration: duration)
            }
            if displayedContent.contains(.aiModelUsage), let usage = report.aiUsage {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(localized("AI 模型用量")).font(.system(size: 18, weight: .semibold))
                        Spacer(minLength: 12)
                        Text("\(AIUsageAnalytics.formatTokenAxisValue(usage.totalTokens)) Token").monospacedDigit()
                    }
                    ForEach(usage.models) { model in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(DailyModelUsageList.modelName(model, language: language))
                                .font(.system(size: 17, weight: .medium))
                            Text(DailyModelUsageList.tokenBreakdown(model, language: language))
                                .font(.system(size: 15).monospacedDigit()).foregroundStyle(ink.opacity(0.65))
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if displayedContent.contains(.keyPressTrend) || displayedContent.contains(.powerTrend) {
                HStack(alignment: .top, spacing: 40) {
                    if displayedContent.contains(.keyPressTrend) { keyPressChart }
                    if displayedContent.contains(.powerTrend) { powerChart }
                }
            }
            footer
        }
        .padding(56)
        .frame(width: 900, alignment: .leading)
        .foregroundStyle(ink)
        .background(background)
        .fontDesign(template == .paper ? .serif : template == .terminal ? .monospaced : .default)
        .environment(\.locale, locale)
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("zisla").font(.system(size: 22, weight: .bold)).tracking(3)
                Text(localized("每日简报")).font(.system(size: template == .paper ? 44 : 32, weight: .semibold))
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 8) {
                Text(report.day.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: report.calendar, timeZone: report.calendar.timeZone)))
                    .font(.system(size: 19, weight: .medium))
            }
        }
        .padding(.bottom, 24)
        .overlay(alignment: .bottom) { Rectangle().fill(accent).frame(height: template == .sunrise ? 5 : 1) }
    }

    @ViewBuilder
    private var composition: some View {
        switch template {
        case .minimal:
            if hasHero { hero }
            if displayedContent.contains(.hourlyUsage) { activityChart }
            if hasCategories { categories }
            if !primaryMetricItems.isEmpty { metrics(primaryMetricItems, columns: 3) }
        case .paper:
            if hasHero { hero }
            if hasCategories || displayedContent.contains(.hourlyUsage) {
                HStack(alignment: .top, spacing: 40) {
                    if hasCategories { categories }
                    if displayedContent.contains(.hourlyUsage) { activityChart }
                }
            }
            if !primaryMetricItems.isEmpty { metrics(primaryMetricItems, columns: 2) }
        case .midnight:
            if hasHero { hero.padding(28).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 24)) }
            if !primaryMetricItems.isEmpty { metrics(primaryMetricItems, columns: 3) }
            if displayedContent.contains(.hourlyUsage) { activityChart }
            if hasCategories { categories }
        case .forest:
            if hasHero || hasCategories {
                HStack(alignment: .top, spacing: 32) {
                    if hasHero { hero }
                    if hasCategories { categories.frame(width: hasHero ? 240 : nil) }
                }
            }
            if displayedContent.contains(.hourlyUsage) { activityChart }
            if !primaryMetricItems.isEmpty { metrics(primaryMetricItems, columns: 2) }
        case .sunrise:
            if displayedContent.contains(.hourlyUsage) { activityChart }
            if hasHero { hero }
            if hasCategories { categories }
            if !primaryMetricItems.isEmpty { metrics(primaryMetricItems, columns: 3) }
        case .terminal:
            if hasHero { hero }
            if hasCategories { categories }
            if !primaryMetricItems.isEmpty { metrics(primaryMetricItems, columns: 2) }
            if displayedContent.contains(.hourlyUsage) { activityChart }
        case .coastal:
            if hasHero { hero.padding(28).background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20)) }
            if displayedContent.contains(.hourlyUsage) || hasCategories || !primaryMetricItems.isEmpty {
                HStack(alignment: .top, spacing: 32) {
                    if displayedContent.contains(.hourlyUsage) || hasCategories {
                        VStack(alignment: .leading, spacing: 32) {
                            if displayedContent.contains(.hourlyUsage) { activityChart }
                            if hasCategories { categories }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if !primaryMetricItems.isEmpty { metrics(primaryMetricItems, columns: 2).frame(maxWidth: .infinity) }
                }
            }
        case .blossom:
            if hasHero { hero.padding(28).background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 28)) }
            if !primaryMetricItems.isEmpty {
                metrics(primaryMetricItems, columns: 4)
                    .padding(24)
                    .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
            }
            if displayedContent.contains(.hourlyUsage) || hasCategories {
                HStack(alignment: .top, spacing: 40) {
                    if displayedContent.contains(.hourlyUsage) { activityChart }
                    if hasCategories { categories.frame(width: displayedContent.contains(.hourlyUsage) ? 240 : nil) }
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            if displayedContent.contains(.localUsage), let value = value(for: .localUsage) {
                Text(localized("本机使用时间")).font(.system(size: 21, weight: .medium)).foregroundStyle(ink.opacity(0.68))
                Text(value).font(.system(size: template == .forest ? 64 : 84, weight: .light))
                    .tracking(-2).lineLimit(1).minimumScaleFactor(0.55)
            }
            let row = [DailyBriefingContent.firstActivity, .lastActivity, .allDevicesUsage]
                .filter { displayedContent.contains($0) && (template != .forest || $0 != .allDevicesUsage) }
            if !row.isEmpty {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(row) { content in
                        if let value = value(for: content) { metric(content.title, value) }
                    }
                }
            }
            if template == .forest, displayedContent.contains(.allDevicesUsage), let value = value(for: .allDevicesUsage) {
                metric(DailyBriefingContent.allDevicesUsage.title, value)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localized("每小时使用时间")).font(.system(size: 18, weight: .semibold))
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<24, id: \.self) { hour in
                        RoundedRectangle(cornerRadius: template == .terminal ? 0 : 3)
                            .fill(report.day.hourlySeconds[hour] > 0 ? accent : ink.opacity(0.09))
                            .frame(height: max(3, min(1, report.day.hourlySeconds[hour] / 3600) * geometry.size.height))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: template == .paper ? 150 : 120)
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    if hour != 0 { Spacer() }
                    Text(hour.formatted(.number.locale(locale))).font(.system(size: 14).monospacedDigit())
                }
            }
            .foregroundStyle(ink.opacity(0.55))
        }
        .accessibilityLabel(localized("每小时使用时间"))
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach([DailyBriefingContent.workTime, .leisureTime, .otherTime].filter(displayedContent.contains)) { content in
                if let category = content.category, let value = value(for: content) {
                    categoryRow(content.title, value: value, seconds: report.day.seconds(in: category),
                        opacity: category == .work ? 1 : category == .leisure ? 0.65 : 0.35)
                }
            }
        }
    }

    private func categoryRow(_ title: String, value: String, seconds: Double, opacity: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(localized(title))
                Spacer(minLength: 12)
                Text(value).monospacedDigit()
            }
            .font(.system(size: 17))
            GeometryReader { geometry in
                Capsule().fill(ink.opacity(0.07))
                Capsule().fill(accent.opacity(opacity))
                    .frame(width: geometry.size.width * min(1, seconds / max(1, report.day.activeSeconds)))
            }
            .frame(height: 5)
        }
    }

    private func metrics(_ items: [MetricItem], columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: min(columns, items.count)), alignment: .leading, spacing: 24) {
            ForEach(items) { item in metric(item.id.title, item.value) }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized(title)).font(.system(size: 16)).foregroundStyle(ink.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            Text(value).font(.system(size: 24, weight: .medium)).lineLimit(2).minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text(localized("截至") + "  " + time(report.generatedAt))
        }
        .font(.system(size: 13).monospacedDigit())
        .foregroundStyle(ink.opacity(0.6))
        .padding(.top, 24)
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.18)).frame(height: 1) }
    }

    private var batteryRange: String? {
        guard let low = report.day.minimumBattery, let high = report.day.maximumBattery else { return nil }
        return low.formatted(.percent.precision(.fractionLength(0)).locale(locale)) + " – " + high.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    private func peak(_ peak: DailyBriefingPeak, unit: String) -> String {
        return peak.value.formatted(.number.precision(.fractionLength(unit == "W" ? 1 : 0)).locale(locale)) + " \(unit)\n" + time(peak.date)
    }

    private func localized(_ key: String) -> String { AppLocalization.string(key, language: language) }

    private func time(_ date: Date) -> String {
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: report.calendar, timeZone: report.calendar.timeZone))
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = report.calendar
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter.string(from: seconds)!
    }

    private func durationValue(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        return duration(seconds)
    }
}

@MainActor
enum DailyBriefingRenderer {
    static func image(report: DailyBriefingReport, template: DailyBriefingTemplate, language: AppLanguage, scale: Double = 2) throws -> CGImage {
        let renderer = ImageRenderer(content: DailyBriefingPoster(report: report, template: template, language: language))
        renderer.scale = scale
        renderer.isOpaque = true
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    static func png(report: DailyBriefingReport, template: DailyBriefingTemplate, language: AppLanguage) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: try image(report: report, template: template, language: language))
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
