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

/// Format-text variant of `AppLocalizedText` for parameterized strings.
struct AppLocalizedFormatText: View {
    let key: String
    let arguments: [CVarArg]

    @Environment(\.locale) private var locale

    init(_ key: String, _ arguments: CVarArg...) {
        self.key = key
        self.arguments = arguments
    }

    var body: some View {
        Text(AppLocalization.format(key, locale: locale, arguments))
    }
}

enum AppLocalization {
    static func string(_ key: String, language: AppLanguage) -> String {
        string(key, locale: language.locale)
    }

    static func string(_ key: String, locale: Locale) -> String {
        for identifier in localeIdentifiers(for: locale) {
            if let bundle = localizationBundles[identifier] {
                return bundle.localizedString(forKey: key, value: key, table: "Localizable")
            }
        }
        return key
    }

    /// Localizes `key` and formats it with `arguments` (keys use printf-style placeholders).
    static func format(_ key: String, locale: Locale, _ arguments: [CVarArg]) -> String {
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
