import Foundation

public enum SystemUptime {
    public static func displayText(for uptime: TimeInterval) -> String {
        let totalMinutes = uptime.isFinite ? max(0, Int(uptime) / 60) : 0
        let days = totalMinutes / 1_440
        let hours = totalMinutes % 1_440 / 60
        let minutes = totalMinutes % 60
        return "开机时间： \(days)天 \(hours)小时 \(minutes)分钟"
    }
}
