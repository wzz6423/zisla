import Foundation
import ZislaKit

enum BatteryLocalization {
    static let defaultLocale = Locale(identifier: "zh-Hans")

    static func string(_ key: String, locale: Locale) -> String {
        AppLocalization.string(key, locale: locale)
    }

    static func format(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        AppLocalization.format(key, locale: locale, arguments)
    }

    static func number(_ format: String, locale: Locale, _ arguments: CVarArg...) -> String {
        String(format: format, locale: locale, arguments: arguments)
    }

    static func historyText(
        lastFullyChargedAt: Date?,
        lastUnpluggedAt: Date?,
        now: Date,
        locale: Locale
    ) -> String? {
        let fullyChargedDuration = lastFullyChargedAt.map {
            durationText(from: $0, to: now, locale: locale)
        }
        let unpluggedDuration = lastUnpluggedAt.map {
            durationText(from: $0, to: now, locale: locale)
        }

        switch (fullyChargedDuration, unpluggedDuration) {
        case let (fullyChargedDuration?, unpluggedDuration?):
            return format(
                "上次充满 %@，已脱电使用 %@",
                locale: locale,
                fullyChargedDuration,
                unpluggedDuration
            )
        case let (fullyChargedDuration?, nil):
            return format("上次充满 %@", locale: locale, fullyChargedDuration)
        case let (nil, unpluggedDuration?):
            return format("已脱电使用 %@", locale: locale, unpluggedDuration)
        case (nil, nil):
            return nil
        }
    }

    static func durationText(from start: Date, to end: Date, locale: Locale) -> String {
        let totalSeconds = max(0, Int(end.timeIntervalSince(start)))
        return durationText(forMinutes: totalSeconds / 60, locale: locale)
    }

    static func durationText(forMinutes minutes: Int, locale: Locale) -> String {
        let normalizedMinutes = max(0, minutes)
        let hours = normalizedMinutes / 60
        let remainder = normalizedMinutes % 60
        if hours > 0 {
            return format("%ld小时%ld分", locale: locale, hours, remainder)
        }
        return format("%ld分钟", locale: locale, remainder)
    }

    static func summaryStatusText(_ battery: BatterySnapshot, locale: Locale) -> String {
        if battery.isCharged { return string("已充满", locale: locale) }
        if battery.isCharging { return string("充电中", locale: locale) }
        if battery.isPluggedIn { return string("电源已接通", locale: locale) }
        return string("使用电池", locale: locale)
    }

    static func detailStatusText(_ battery: BatterySnapshot, locale: Locale) -> String {
        if battery.isCharging { return string("充电中", locale: locale) }
        if battery.isCharged { return string("已充满", locale: locale) }
        if battery.isPluggedIn { return string("电源已接通", locale: locale) }
        if let minutes = battery.timeRemainingMinutes {
            return format("剩余 %ld 分钟", locale: locale, minutes)
        }
        return string("电池供电", locale: locale)
    }

    static func sourceName(_ source: NetworkBatteryDevice.Source, locale: Locale) -> String {
        string(source.displayName, locale: locale)
    }

    static func deviceTypeName(_ deviceType: NetworkBatteryDevice.DeviceType, locale: Locale) -> String {
        string(deviceType.displayName, locale: locale)
    }

    static func componentName(_ kind: BatteryLevelComponent.Kind, locale: Locale) -> String {
        string(kind.displayName, locale: locale)
    }

    static func metadataText(_ value: String, locale: Locale) -> String {
        string(value, locale: locale)
    }
}
