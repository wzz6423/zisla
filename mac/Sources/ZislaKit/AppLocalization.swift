import Foundation
import SwiftUI
import ZislaCore

public struct AppLanguageEnvironment<Content: View>: View {
    @ObservedObject var languageStore: AppLanguageStore
    let content: Content

    public init(languageStore: AppLanguageStore, content: Content) {
        self.languageStore = languageStore
        self.content = content
    }

    public var body: some View {
        content
            .environment(\.locale, languageStore.language.locale)
            .environment(\.layoutDirection, languageStore.language.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}

public struct AppLocalizedText: View {
    let key: String

    @Environment(\.locale) private var locale

    public init(_ key: String) {
        self.key = key
    }

    public var body: some View {
        Text(AppLocalization.string(key, locale: locale))
    }
}

/// Format-text variant of `AppLocalizedText` for parameterized strings.
public struct AppLocalizedFormatText: View {
    let key: String
    let arguments: [CVarArg]

    @Environment(\.locale) private var locale

    public init(_ key: String, _ arguments: CVarArg...) {
        self.key = key
        self.arguments = arguments
    }

    public var body: some View {
        Text(AppLocalization.format(key, locale: locale, arguments))
    }
}
