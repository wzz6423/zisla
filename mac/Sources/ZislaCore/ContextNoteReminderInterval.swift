import Foundation

public enum ContextNoteReminderInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case off = 0
    case oneHour = 60
    case oneAndAHalfHours = 90
    case threeHours = 180
    case sixHours = 360
    case twelveHours = 720
    case oneDay = 1_440
    case twoDays = 2_880
    case threeDays = 4_320

    public var id: Int { rawValue }
    public var duration: TimeInterval { TimeInterval(rawValue) * 60 }

    public var localizationKey: String {
        switch self {
        case .off: "不主动提醒"
        case .oneHour: "每 1 小时"
        case .oneAndAHalfHours: "每 1.5 小时"
        case .threeHours: "每 3 小时"
        case .sixHours: "每 6 小时"
        case .twelveHours: "每 12 小时"
        case .oneDay: "每 1 天"
        case .twoDays: "每 2 天"
        case .threeDays: "每 3 天"
        }
    }
}
