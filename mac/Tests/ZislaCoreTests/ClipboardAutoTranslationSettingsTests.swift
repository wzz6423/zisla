import Foundation
import Testing
@testable import ZislaCore

struct ClipboardAutoTranslationSettingsTests {
    @Test
    func automaticTranslationIsAnOptInForeignLanguageAction() {
        let defaults = ClipboardAssistantActionOrder.defaults(for: .nonSystemLanguageText)
        #expect(defaults.first == .translate)
        #expect(defaults.map(\.rawValue).contains("autoTranslate"))
        #expect(!ClipboardAssistantActionOrder.defaults(for: .text).map(\.rawValue).contains("autoTranslate"))
    }

    @Test
    func oldOrderKeepsBrowserTranslationAndNewSelectionSurvivesRestart() throws {
        let legacy = Data(#"{"clipboardAssistantActionOrders":["chineseText",["translate","search","saveText","addToQuickNote","sendToTeleprompter","share"]]}"#.utf8)
        var settings = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(settings.clipboardAssistantActionOrders[.nonSystemLanguageText]?.first == .translate)
        let automatic = try #require(ClipboardAssistantActionKind(rawValue: "autoTranslate"))
        settings.clipboardAssistantActionOrders[.nonSystemLanguageText] = [automatic, .translate]
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.clipboardAssistantActionOrders[.nonSystemLanguageText]?.first == automatic)
        #expect(restored.clipboardAssistantActionOrders[.nonSystemLanguageText]?.filter { $0 == automatic }.count == 1)
    }
}
