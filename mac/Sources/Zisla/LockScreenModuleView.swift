import ZislaCore
import ZislaKit
import SwiftUI

struct LockScreenModuleView: View {
    @ObservedObject var model: AppModel

    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let date = context.date
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(solarDateText(for: date))
                            .font(.system(size: 15, weight: .bold))
                        Text(lunarDateText(for: date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    batteryStatus
                }

                HStack(spacing: 16) {
                    weatherStatus
                    Divider().frame(height: 28)
                    Text(lockScreenMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var batteryStatus: some View {
        Group {
            if let battery = model.battery.snapshot {
                statusItem(
                    symbol: battery.symbolName,
                    title: BatteryLocalization.string("电量", locale: locale),
                    value: "\(battery.percentInt)% · \(batteryDetail(battery))"
                )
            } else {
                statusItem(
                    symbol: "battery.0",
                    title: BatteryLocalization.string("电量", locale: locale),
                    value: BatteryLocalization.string("未检测到内置电池", locale: locale)
                )
            }
        }
    }

    private var weatherStatus: some View {
        Group {
            if model.settingsStore.settings.weatherEnabled, let weather = model.weather {
                statusItem(
                    symbol: weather.condition.symbolName,
                    title: weather.locationName ?? "当前位置",
                    value: "\(Int(weather.temperature.rounded()))° · \(weather.condition.summary)"
                )
            } else {
                statusItem(symbol: "cloud.slash", title: "天气", value: "等待天气数据")
            }
        }
    }

    private func statusItem(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
        }
    }

    private func batteryDetail(_ battery: BatterySnapshot) -> String {
        BatteryLocalization.detailStatusText(battery, locale: locale)
    }

    private func solarDateText(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day, .weekday], from: date)
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"].map(AppLocalization.text)
        let weekday = components.weekday.flatMap { weekdays.indices.contains($0 - 1) ? weekdays[$0 - 1] : nil }
            ?? ""
        return AppLocalization.text("%ld年%ld月%ld日 %@", components.year ?? 0, components.month ?? 0, components.day ?? 0, weekday)
    }

    private func lunarDateText(for date: Date) -> String {
        LunarCalendar.components(from: date)?.fullText ?? AppLocalization.text("农历日期未知")
    }

    private var lockScreenMessage: String {
        let message = model.settingsStore.settings.lockScreenMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "未设置锁屏文字" : "“\(message)”"
    }
}
