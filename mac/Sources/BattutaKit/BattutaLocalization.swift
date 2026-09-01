import Foundation

extension String {
    var localized: String {
        // BattutaKit 使用中文作为默认语言，简化本地化
        self
    }
}

enum AppLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
}

enum L10n {
    static var locale: Locale { Locale(identifier: "zh-Hans") }

    static func locale(for preference: AppLanguagePreference) -> Locale {
        switch preference {
        case .system: Locale.current
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }

    static func configure(for _: AppLanguagePreference) {}

    static func tr(_ key: String) -> String {
        key
    }

    static func format(_ format: String, _ arguments: CVarArg...) -> String {
        String(format: format, arguments: arguments)
    }
}
