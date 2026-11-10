import Foundation
import Testing
import ZislaCore

struct ClipboardAssistantLookupSettingsTests {
    @Test(arguments: [ClipboardAssistantKind.flight, .train, .tracking])
    func serviceLookupIsTheDefaultAndSearchRemainsAvailable(_ kind: ClipboardAssistantKind) {
        let expected: [ClipboardAssistantActionKind] = [.openURL, .search, .copyText, .addToQuickNote, .share]
        #expect(ClipboardAssistantActionOrder.defaults(for: kind) == expected)
        #expect(FeatureSettings.default.clipboardAssistantActionOrders[kind] == expected)
    }

    @Test(arguments: [ClipboardAssistantKind.flight, .train])
    func formerSearchDefaultMigratesOnceAndLaterSearchChoicesSurviveRestart(_ kind: ClipboardAssistantKind) throws {
        let previousDefault: [ClipboardAssistantActionKind] = [.search, .openURL, .copyText, .addToQuickNote, .share]
        var previous = FeatureSettings.default
        previous.clipboardAssistantActionOrders[kind] = previousDefault
        previous.clipboardAssistantSearchEngine = .bing
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as? [String: Any])
        payload.removeValue(forKey: "clipboardAssistantServiceLookupDefaultApplied")
        var settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(settings.clipboardAssistantActionOrders[kind]?.first == .openURL)
        #expect(settings.clipboardAssistantSearchEngine == .bing)

        settings.clipboardAssistantActionOrders[kind] = previousDefault
        for _ in 0..<2 {
            settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
            #expect(settings.clipboardAssistantActionOrders[kind] == previousDefault,
                    "An explicit search priority must survive restarting after the upgrade")
        }
    }

    @Test(arguments: [ClipboardAssistantKind.flight, .train, .tracking])
    func legacyCustomPrioritiesArePreserved(_ kind: ClipboardAssistantKind) throws {
        let custom: [ClipboardAssistantActionKind] = [.search, .copyText, .openURL, .share, .addToQuickNote]
        var previous = FeatureSettings.default
        previous.clipboardAssistantActionOrders[kind] = custom
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as? [String: Any])
        payload.removeValue(forKey: "clipboardAssistantServiceLookupDefaultApplied")
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(settings.clipboardAssistantActionOrders[kind] == custom)
        let reopened = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(reopened.clipboardAssistantActionOrders == settings.clipboardAssistantActionOrders)
    }
}
