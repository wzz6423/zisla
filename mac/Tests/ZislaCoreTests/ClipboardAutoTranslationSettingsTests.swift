import Foundation
import Testing
@testable import ZislaCore

struct ClipboardAutoTranslationSettingsTests {
    @Test
    func automaticTranslationIsAnOptInForeignLanguageAction() {
        let defaults = ClipboardAssistantActionOrder.defaults(for: .nonSystemLanguageText)
        #expect(Array(defaults.prefix(2)) == [.translate, .autoTranslate])
        #expect(defaults.map(\.rawValue).contains("autoTranslate"))
        #expect(!ClipboardAssistantActionOrder.defaults(for: .text).map(\.rawValue).contains("autoTranslate"))
        for kind in ClipboardAssistantKind.allCases where kind != .nonSystemLanguageText {
            #expect(!ClipboardAssistantActionOrder.normalized([], for: kind).contains(.autoTranslate))
        }
    }

    @Test
    func oldOrderKeepsBrowserTranslationAndNewSelectionSurvivesRestart() throws {
        let legacy = Data(#"{"clipboardAssistantActionOrders":["chineseText",["translate","search","saveText","addToQuickNote","sendToTeleprompter","share"]]}"#.utf8)
        var settings = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(settings.clipboardAssistantActionOrders[.nonSystemLanguageText] == ClipboardAssistantActionOrder.defaults(for: .nonSystemLanguageText))
        let automatic = try #require(ClipboardAssistantActionKind(rawValue: "autoTranslate"))
        settings.clipboardAssistantActionOrders[.nonSystemLanguageText] = [automatic, .translate]
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.clipboardAssistantActionOrders[.nonSystemLanguageText]?.first == automatic)
        #expect(restored.clipboardAssistantActionOrders[.nonSystemLanguageText]?.filter { $0 == automatic }.count == 1)
    }

    @Test(arguments: [false, true])
    func savedDefaultPlacesAutomaticTranslationImmediatelyAfterBrowserTranslation(alreadyAppended: Bool) throws {
        let defaults = ClipboardAssistantActionOrder.defaults(for: .nonSystemLanguageText)
        let previous = defaults.filter { $0 != .autoTranslate } + (alreadyAppended ? [.autoTranslate] : [])
        var saved = FeatureSettings()
        saved.clipboardAssistantActionOrders[.nonSystemLanguageText] = previous
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(saved))
        #expect(restored.clipboardAssistantActionOrders[.nonSystemLanguageText] == defaults)
        let reopened = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(restored))
        #expect(reopened.clipboardAssistantActionOrders == restored.clipboardAssistantActionOrders)
        let actions: [ClipboardAssistantAction] = [.search("source"), .autoTranslate("source"), .translate("source"), .share]
        #expect(ClipboardAssistantActionOrder.ordered(actions, for: .nonSystemLanguageText, using: restored.clipboardAssistantActionOrders)
            == [.translate("source"), .autoTranslate("source"), .search("source"), .share])
    }

    @Test
    func upgradingACustomOrderInsertsTheNewActionBesideTranslation() {
        let previous: [ClipboardAssistantActionKind] = [.search, .translate, .share, .saveText]
        let upgraded = ClipboardAssistantActionOrder.normalized(previous, for: .nonSystemLanguageText)
        #expect(upgraded == [.search, .translate, .autoTranslate, .share, .saveText, .addToQuickNote, .sendToTeleprompter])
        #expect(ClipboardAssistantActionOrder.normalized(upgraded, for: .nonSystemLanguageText) == upgraded)
    }

    @Test
    func explicitlyReorderedAutomaticTranslationKeepsItsSavedPosition() throws {
        let custom: [ClipboardAssistantActionKind] = [.search, .autoTranslate, .translate, .share, .saveText, .addToQuickNote, .sendToTeleprompter]
        let settings = FeatureSettings(clipboardAssistantActionOrders: [.nonSystemLanguageText: custom])
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.clipboardAssistantActionOrders[.nonSystemLanguageText] == custom)
    }
}
