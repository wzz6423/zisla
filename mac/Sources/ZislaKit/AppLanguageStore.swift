import Combine
import Foundation
import ZislaCore

@MainActor
public final class AppLanguageStore: ObservableObject {
    public nonisolated static let defaultKey = AppLocalization.defaultsKey

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
