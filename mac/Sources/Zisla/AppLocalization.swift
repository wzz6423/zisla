import Foundation
import SwiftUI
import ZislaKit

struct AppLanguageEnvironment<Content: View>: View {
    @ObservedObject var languageStore: AppLanguageStore
    let content: Content

    var body: some View {
        content
            .environment(\.locale, languageStore.language.locale)
            .environment(\.layoutDirection, languageStore.language.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}

struct AppLocalizedText: View {
    let key: String

    @Environment(\.locale) private var locale

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(AppLocalization.string(key, locale: locale))
    }
}

enum AppLocalization {
    static func string(_ key: String, language: AppLanguage) -> String {
        string(key, locale: language.locale)
    }

    static func string(_ key: String, locale: Locale) -> String {
        for identifier in localeIdentifiers(for: locale) {
            for container in [Bundle.main, Bundle.module] {
                guard let bundle = localizationBundle(in: container, identifier: identifier) else {
                    continue
                }
                return bundle.localizedString(forKey: key, value: key, table: "Localizable")
            }
        }
        return key
    }

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
