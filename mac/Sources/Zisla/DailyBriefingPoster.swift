import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct DailyBriefingReport: Sendable {
    var day: DailyBriefingDay
    var generatedAt: Date
    var typing: DailyBriefingTyping?
    var allDeviceSeconds: TimeInterval?
    var usesSystemScreenTime = false
    var calendar = DailyBriefingDay.calendar

    static func example(at date: Date = Date()) -> Self {
        let calendar = DailyBriefingDay.calendar
        let start = calendar.startOfDay(for: date)
        var day = DailyBriefingDay(date: date, calendar: calendar)
        day.firstActivity = start.addingTimeInterval(9 * 3600 + 12 * 60)
        day.lastActivity = start.addingTimeInterval(21 * 3600 + 36 * 60)
        day.observedFrom = day.firstActivity
        day.observedThrough = day.lastActivity
        day.hourlySeconds = [0, 0, 0, 0, 0, 0, 0, 0, 0, 1800, 3000, 2700, 900, 2100, 3300, 2700, 2400, 1800, 600, 900, 1500, 600, 0, 0]
        day.applications = [
            "work": .init(name: "Xcode", category: .work, seconds: 17700),
            "leisure": .init(name: "Music", category: .leisure, seconds: 4200),
            "other": .init(name: "Safari", category: .other, seconds: 2400),
        ]
        day.listeningSeconds = 8100
        day.expansionCount = 42
        day.peakPower = .init(value: 48.6, date: start.addingTimeInterval(14 * 3600 + 23 * 60))
        day.peakFan = .init(value: 2460, date: start.addingTimeInterval(14 * 3600 + 24 * 60))
        day.minimumBattery = 0.32
        day.maximumBattery = 1
        return Self(day: day, generatedAt: day.lastActivity!, typing: .init(characters: 12846, topApplication: "Xcode", peakHour: 14), allDeviceSeconds: 31500)
    }
}

struct DailyBriefingPoster: View {
    let report: DailyBriefingReport
    let template: DailyBriefingTemplate
    let language: AppLanguage

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
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            header
            composition
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
            hero
            activityChart
            categories
            metrics(columns: 3)
        case .paper:
            hero
            HStack(alignment: .top, spacing: 40) {
                categories
                activityChart
            }
            metrics(columns: 2)
        case .midnight:
            hero.padding(28).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
            metrics(columns: 3)
            activityChart
            categories
        case .forest:
            HStack(alignment: .top, spacing: 32) {
                hero
                categories.frame(width: 240)
            }
            activityChart
            metrics(columns: 2)
        case .sunrise:
            activityChart
            hero
            categories
            metrics(columns: 3)
        case .terminal:
            hero
            categories
            metrics(columns: 2)
            activityChart
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(localized("本机使用时间")).font(.system(size: 21, weight: .medium)).foregroundStyle(ink.opacity(0.68))
            Text(duration(report.day.activeSeconds)).font(.system(size: template == .forest ? 64 : 84, weight: .light))
                .tracking(-2).lineLimit(1).minimumScaleFactor(0.55)
            HStack(alignment: .top, spacing: 28) {
                metric("首次使用", time(report.day.firstActivity))
                metric("最后使用", time(report.day.lastActivity))
                if template != .forest { metric("所有设备", report.allDeviceSeconds.map(duration) ?? localized("未获取")) }
            }
            if template == .forest { metric("所有设备", report.allDeviceSeconds.map(duration) ?? localized("未获取")) }
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
            category("工作", seconds: report.day.seconds(in: .work), opacity: 1)
            category("休闲娱乐", seconds: report.day.seconds(in: .leisure), opacity: 0.65)
            category("其他", seconds: report.day.seconds(in: .other), opacity: 0.35)
        }
    }

    private func category(_ title: String, seconds: Double, opacity: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(localized(title))
                Spacer(minLength: 12)
                Text(duration(seconds)).monospacedDigit()
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

    private func metrics(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns), alignment: .leading, spacing: 24) {
            metric("输入字符", report.typing.map { $0.characters.formatted(.number.locale(locale)) } ?? localized("未获取"))
            metric("输入最多的应用", report.typing?.topApplication ?? "—")
            metric("输入高峰", report.typing?.peakHour.map { hour in
                time(report.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: report.day.date))
            } ?? "—")
            metric("展开次数", report.day.expansionCount.formatted(.number.locale(locale)))
            metric("听歌时长", report.day.listeningSeconds.map(duration) ?? localized("未获取"))
            metric("功率峰值", peak(report.day.peakPower, unit: "W"))
            metric("电量范围", batteryRange)
            metric("风扇峰值", peak(report.day.peakFan, unit: "RPM"))
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
        VStack(alignment: .leading, spacing: 12) {
            Text(localized(report.usesSystemScreenTime ? "本机时长来自系统屏幕使用时间" : "本机时长来自 Zisla 活跃记录"))
                .font(.system(size: 15, weight: .medium))
            Text(localized("仅含已记录或已同步的数据。工作与娱乐按应用分类，浏览器归入其他。未获取的指标不计为零。"))
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(localized("记录时段") + "  " + time(report.day.observedFrom) + " – " + time(report.day.observedThrough))
                Spacer()
                Text(localized("截至") + "  " + time(report.generatedAt))
            }
            .font(.system(size: 13).monospacedDigit())
        }
        .foregroundStyle(ink.opacity(0.6))
        .padding(.top, 24)
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.18)).frame(height: 1) }
    }

    private var batteryRange: String {
        guard let low = report.day.minimumBattery, let high = report.day.maximumBattery else { return localized("未获取") }
        return low.formatted(.percent.precision(.fractionLength(0)).locale(locale)) + " – " + high.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    private func peak(_ peak: DailyBriefingPeak?, unit: String) -> String {
        guard let peak else { return localized("未获取") }
        return peak.value.formatted(.number.precision(.fractionLength(unit == "W" ? 1 : 0)).locale(locale)) + " \(unit)\n" + time(peak.date)
    }

    private func localized(_ key: String) -> String { AppLocalization.string(key, language: language) }

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: report.calendar, timeZone: report.calendar.timeZone))
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = report.calendar
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter.string(from: max(0, seconds)) ?? "—"
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
