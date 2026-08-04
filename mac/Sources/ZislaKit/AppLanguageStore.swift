import Combine
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

    public var locale: Locale {
        Locale(identifier: rawValue)
    }

    public var isRightToLeft: Bool {
        self == .arabic
    }
}

@MainActor
public final class AppLanguageStore: ObservableObject {
    public static let defaultKey = "zisla.interface-language"

    @Published public var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: key)
        }
    }

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = AppLanguageStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
        language = AppLanguage(rawValue: defaults.string(forKey: key) ?? "") ?? .simplifiedChinese
    }
}
