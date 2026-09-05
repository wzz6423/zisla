import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AppLanguageStoreTests {
    @Test @MainActor
    func defaultsToSimplifiedChineseAndPersistsEnglish() throws {
        let suiteName = "Zisla.AppLanguageStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppLanguageStore(defaults: defaults, key: "language")
        #expect(store.language == .simplifiedChinese)

        store.language = .english
        #expect(defaults.string(forKey: "language") == AppLanguage.english.rawValue)

        let restored = AppLanguageStore(defaults: defaults, key: "language")
        #expect(restored.language == .english)
    }

    @Test @MainActor
    func invalidPersistedLanguageFallsBackToSimplifiedChinese() throws {
        let suiteName = "Zisla.AppLanguageStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unsupported", forKey: "language")

        let store = AppLanguageStore(defaults: defaults, key: "language")
        #expect(store.language == .simplifiedChinese)
    }

    @Test @MainActor
    func allLanguagesHaveValidLocales() throws {
        for language in AppLanguage.allCases {
            let locale = language.locale
            #expect(locale.identifier == language.rawValue)
        }
    }

    @Test @MainActor
    func persistsAndRestoresAllNewLanguages() throws {
        let newLanguages: [AppLanguage] = [
            .japanese, .korean, .french, .german, .spanish, .brazilianPortuguese,
            .traditionalChinese, .italian, .dutch, .russian, .arabic, .thai, .indonesian, .vietnamese, .turkish
        ]

        for language in newLanguages {
            let suiteName = "Zisla.AppLanguageStoreTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let store = AppLanguageStore(defaults: defaults, key: "language")
            store.language = language

            #expect(defaults.string(forKey: "language") == language.rawValue)

            let restored = AppLanguageStore(defaults: defaults, key: "language")
            #expect(restored.language == language)
        }
    }

    @Test @MainActor
    func verifyNewLanguageRawValues() throws {
        #expect(AppLanguage.japanese.rawValue == "ja")
        #expect(AppLanguage.korean.rawValue == "ko")
        #expect(AppLanguage.french.rawValue == "fr")
        #expect(AppLanguage.german.rawValue == "de")
        #expect(AppLanguage.spanish.rawValue == "es")
        #expect(AppLanguage.brazilianPortuguese.rawValue == "pt-BR")
        #expect(AppLanguage.traditionalChinese.rawValue == "zh-Hant")
        #expect(AppLanguage.italian.rawValue == "it")
        #expect(AppLanguage.dutch.rawValue == "nl")
        #expect(AppLanguage.russian.rawValue == "ru")
        #expect(AppLanguage.arabic.rawValue == "ar")
        #expect(AppLanguage.thai.rawValue == "th")
        #expect(AppLanguage.indonesian.rawValue == "id")
        #expect(AppLanguage.vietnamese.rawValue == "vi")
        #expect(AppLanguage.turkish.rawValue == "tr")
    }

    @Test @MainActor
    func arabicIsRightToLeft() throws {
        #expect(AppLanguage.arabic.isRightToLeft == true)
    }

    @Test @MainActor
    func nonArabicLanguagesAreLeftToRight() throws {
        let ltrLanguages: [AppLanguage] = [
            .simplifiedChinese, .traditionalChinese, .english, .japanese, .korean,
            .french, .german, .spanish, .brazilianPortuguese, .italian, .dutch,
            .russian, .thai, .indonesian, .vietnamese, .turkish
        ]

        for language in ltrLanguages {
            #expect(language.isRightToLeft == false)
        }
    }
}
