import Foundation
import ZislaCore
import ZislaKit

struct SystemMonitorHeadphoneRow: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let levels: [NoticeBatteryLevel]

    func summary(locale: Locale) -> String {
        let readings = levels.map {
            "\(BatteryLocalization.metadataText($0.label, locale: locale)) \($0.level.map { "\($0)%" } ?? "--")"
        }.joined(separator: " · ")
        return "\(name): \(readings)"
    }
}

enum SystemMonitorHeadphonePresentation {
    static func rows(statuses: [HeadphoneConnection], showsBatteryLevels: Bool) -> [SystemMonitorHeadphoneRow] {
        guard showsBatteryLevels else { return [] }
        var seen: Set<UInt32> = []
        return statuses.compactMap { status in
            guard status.device.isHeadphones, seen.insert(status.device.id).inserted else { return nil }
            let levels: [NoticeBatteryLevel]
            if status.device.isAirPodsMax {
                levels = [NoticeBatteryLevel(label: "耳机", level: status.battery?.mainLevel)]
            } else {
                levels = status.battery?.noticeLevels ?? [NoticeBatteryLevel(label: "耳机", level: nil)]
            }
            return SystemMonitorHeadphoneRow(id: status.device.id, name: status.device.name, levels: levels)
        }
    }
}
