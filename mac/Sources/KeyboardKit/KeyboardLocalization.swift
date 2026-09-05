import Foundation
import ZislaCore
import ZislaKit

/// Language override for the Keyboard windows. Stored raw values stay compatible with the
/// three-option era: "system" plus the `AppLanguage` codes "en" and "zh-Hans".
enum AppLanguagePreference: RawRepresentable, CaseIterable, Identifiable, Hashable, Sendable {
    case system
    case explicit(AppLanguage)

    static let allCases: [AppLanguagePreference] = [.system] + AppLanguage.allCases.map(Self.explicit)

    init?(rawValue: String) {
        if rawValue == "system" {
            self = .system
        } else if let language = AppLanguage(rawValue: rawValue) {
            self = .explicit(language)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .system: "system"
        case .explicit(let language): language.rawValue
        }
    }

    var id: String { rawValue }

    var localizationIdentifier: String? {
        switch self {
        case .system: nil
        case .explicit(let language): language.rawValue
        }
    }

    /// Endonyms are used verbatim so a language name never gets translated into another language.
    var displayName: String {
        switch self {
        case .system: AppLocalization.text("跟随系统")
        case .explicit(let language): language.nativeDisplayName
        }
    }
}

enum L10n {
    private struct State {
        let languagePreference: AppLanguagePreference
        let resolvedLocalization: String
        let bundle: Bundle
        let locale: Locale
    }

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var state: State

        init(state: State) {
            self.state = state
        }

        func replace(with state: State) {
            lock.lock()
            self.state = state
            lock.unlock()
        }

        func current() -> State {
            lock.lock()
            defer { lock.unlock() }
            return state
        }
    }

    private static let fallbackLocalization = "en"
    private static let storage = Storage(state: makeState(for: .system))

    static func configure(for preference: AppLanguagePreference) {
        storage.replace(with: makeState(for: preference))
    }

    static func refreshSystemLocalizationIfNeeded() -> Bool {
        let previous = currentState()
        guard previous.languagePreference == .system else { return false }
        let refreshed = makeState(for: .system)
        guard refreshed.resolvedLocalization != previous.resolvedLocalization else {
            return false
        }
        storage.replace(with: refreshed)
        return true
    }

    static func tr(_ key: String) -> String {
        let shared = AppLocalization.text(key)
        if shared != key { return shared }
        let snapshot = currentState()
        return snapshot.bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ format: String, _ arguments: CVarArg...) -> String {
        let snapshot = currentState()
        let shared = AppLocalization.text(format)
        let template = shared != format
            ? shared
            : snapshot.bundle.localizedString(forKey: format, value: format, table: nil)
        return String(format: template, locale: snapshot.locale, arguments: arguments)
    }

    static func locale(for preference: AppLanguagePreference) -> Locale {
        makeState(for: preference).locale
    }

    static var locale: Locale {
        currentState().locale
    }

    /// Keyboard windows live inside Zisla, so ".system" follows the app-wide language picker
    /// instead of the OS preference; only an explicit override keeps its own localization.
    private static func currentState() -> State {
        let snapshot = storage.current()
        guard snapshot.languagePreference == .system else { return snapshot }
        let expected = canonicalLocalizationIdentifier(AppLocalization.currentLanguage.rawValue)
        guard expected != snapshot.resolvedLocalization else { return snapshot }
        let refreshed = makeState(for: .system)
        storage.replace(with: refreshed)
        return refreshed
    }

    private static func makeState(for preference: AppLanguagePreference) -> State {
        let resolvedLocalization = resolvedLocalizationIdentifier(for: preference)
        return State(
            languagePreference: preference,
            resolvedLocalization: resolvedLocalization,
            bundle: localizedBundle(for: resolvedLocalization),
            locale: preference == .system
                ? AppLocalization.currentLanguage.locale
                : locale(for: resolvedLocalization)
        )
    }

    private static func resolvedLocalizationIdentifier(
        for preference: AppLanguagePreference
    ) -> String {
        if let localization = preference.localizationIdentifier {
            return localization
        }

        return canonicalLocalizationIdentifier(AppLocalization.currentLanguage.rawValue)
    }

    private static func canonicalLocalizationIdentifier(_ identifier: String?) -> String {
        guard let identifier, let language = AppLanguage(rawValue: identifier) else {
            return fallbackLocalization
        }
        return language.rawValue
    }

    /// Only zh-Hans and en ship a Keyboard catalog; other languages resolve through the shared
    /// table and fall back to en here for any key that has not been merged into it yet.
    private static func localizedBundle(for localization: String) -> Bundle {
        for candidate in [localization, fallbackLocalization] {
            guard let url = Bundle.module.url(
                forResource: candidate,
                withExtension: "lproj",
                subdirectory: "Keyboard"
            ), let bundle = Bundle(url: url) else { continue }
            return bundle
        }
        return .main
    }

    private static func locale(for localization: String) -> Locale {
        (AppLanguage(rawValue: localization) ?? .english).locale
    }
}

extension String {
    var localized: String {
        L10n.tr(self)
    }
}
