import Foundation
import ZislaCore

enum VoiceHistoryFormatting {
    static func duration(_ duration: TimeInterval) -> (value: String, unit: String, text: String) {
        let duration = max(0, duration)
        let locale = AppLocalization.currentLanguage.locale
        if duration < 60 {
            let seconds = Int(duration.rounded())
            return (
                seconds.formatted(.number.locale(locale)),
                AppLocalization.text("秒"),
                AppLocalization.text("%ld 秒", seconds)
            )
        }
        if duration < 3_600 {
            return (
                String(format: "%.1f", locale: locale, duration / 60),
                AppLocalization.text("分钟"),
                AppLocalization.text("%.1f 分钟", duration / 60)
            )
        }
        return (
            String(format: "%.1f", locale: locale, duration / 3_600),
            AppLocalization.text("小时"),
            AppLocalization.text("%.1f 小时", duration / 3_600)
        )
    }
}
