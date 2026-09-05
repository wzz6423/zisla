import Foundation
import ZislaCore

public enum SystemUptime {
    public static func displayText(for uptime: TimeInterval) -> String {
        let totalMinutes = uptime.isFinite ? max(0, Int(uptime) / 60) : 0
        let days = totalMinutes / 1_440
        let hours = totalMinutes % 1_440 / 60
        let minutes = totalMinutes % 60
        return AppLocalization.text("开机时间： %ld天 %ld小时 %ld分钟", days, hours, minutes)
    }
}
