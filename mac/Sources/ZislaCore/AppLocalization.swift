import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Equatable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case brazilianPortuguese = "pt-BR"
    case italian = "it"
    case dutch = "nl"
    case russian = "ru"
    case arabic = "ar"
    case thai = "th"
    case indonesian = "id"
    case vietnamese = "vi"
    case turkish = "tr"

    /// Endonym for language pickers. Never routed through the localization table, otherwise the
    /// name of each language would itself get translated into the currently active language.
    public var nativeDisplayName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .brazilianPortuguese: "Português (Brasil)"
        case .italian: "Italiano"
        case .dutch: "Nederlands"
        case .russian: "Русский"
        case .arabic: "العربية"
        case .thai: "ไทย"
        case .indonesian: "Bahasa Indonesia"
        case .vietnamese: "Tiếng Việt"
        case .turkish: "Türkçe"
        }
    }

    public var locale: Locale {
        Locale(identifier: rawValue)
    }

    /// BCP-47-ish code used as the translation target for the clipboard assistant.
    public var translateTargetCode: String {
        switch self {
        case .simplifiedChinese: "zh-CN"
        case .traditionalChinese: "zh-TW"
        default: rawValue
        }
    }

    public var isRightToLeft: Bool {
        self == .arabic
    }
}

public enum AppLocalization {
    /// UserDefaults key holding the interface-language override. Declared here so ZislaCore can
    /// resolve the active language without depending on the SwiftUI-layer store.
    public static let defaultsKey = "zisla.interface-language"

    /// Interface language read back from `AppLanguageStore`'s persisted value, for call sites that
    /// cannot reach the SwiftUI environment (AppKit menus, notifications, plain-string formatting).
    public static var currentLanguage: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "")
            ?? .simplifiedChinese
    }

    /// Localizes `key` with `currentLanguage`.
    public static func text(_ key: String) -> String {
        string(key, language: currentLanguage)
    }

    /// Localizes and formats `key` with `currentLanguage`.
    public static func text(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, locale: currentLanguage.locale, arguments)
    }

    public static func string(_ key: String, language: AppLanguage) -> String {
        string(key, locale: language.locale)
    }

    public static func string(_ key: String, locale: Locale) -> String {
        for identifier in localeIdentifiers(for: locale) {
            if let bundle = localizationBundles[identifier] {
                return bundle.localizedString(forKey: key, value: key, table: "Localizable")
            }
        }
        return key
    }

    /// Localizes `key` and formats it with `arguments` (keys use printf-style placeholders).
    public static func format(_ key: String, locale: Locale, _ arguments: [CVarArg]) -> String {
        String(format: string(key, locale: locale), locale: locale, arguments: arguments)
    }

    private static let localizationBundles: [String: Bundle] = {
        var result: [String: Bundle] = [:]
        #if SWIFT_PACKAGE && !SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE
        let containers = [Bundle.module, Bundle.main]
        #else
        let containers = [Bundle.main]
        #endif
        for language in AppLanguage.allCases {
            for identifier in localeIdentifiers(for: language.locale)
            where result[identifier] == nil {
                if let bundle = containers.lazy.compactMap({ localizationBundle(in: $0, identifier: identifier) }).first {
                    result[identifier] = bundle
                }
            }
        }
        return result
    }()

    private static func localeIdentifiers(for locale: Locale) -> [String] {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let languageCode = identifier.split(separator: "-").first.map(String.init)
        return [identifier, languageCode].compactMap { $0 }
    }

    private static func localizationBundle(in container: Bundle, identifier: String) -> Bundle? {
        let url = container.url(forResource: identifier, withExtension: "lproj")
            ?? container.url(
                forResource: identifier,
                withExtension: "lproj",
                subdirectory: "Localization"
            )
        return url.flatMap(Bundle.init(url:))
    }
}
