import Foundation
import ZislaCore

enum VoiceHistoryFormatting {
    static func durationText(_ duration: TimeInterval) -> String {
        let duration = max(0, duration)
        if duration < 60 {
            return AppLocalization.text("%ld 秒", Int(duration.rounded()))
        }
        if duration < 3_600 {
            return AppLocalization.text("%.1f 分钟", duration / 60)
        }
        return AppLocalization.text("%.1f 小时", duration / 3_600)
    }
}
