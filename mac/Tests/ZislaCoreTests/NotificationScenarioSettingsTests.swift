import Foundation
import Testing
@testable import ZislaCore

struct NotificationScenarioSettingsTests {
    @Test(arguments: ["{}", #"{"notificationScenarios":null}"#, #"{"notificationScenarios":{}}"#])
    func legacyConfigurationsKeepEveryNoticeVisible(json: String) throws {
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        #expect(!settings.notificationScenarios.enabled)
        #expect(!settings.notificationScenarios.automaticallyDetectsMeetings)
        for scenario in NotificationScenario.allCases {
            for importance in [ScenarioNoticeImportance.ordinary, .waiting, .failure, .safety, .lowBattery] {
                #expect(settings.notificationScenarios.behavior(for: importance, scenarios: [scenario]) == .show)
            }
        }
    }

    @Test
    func rulesAndStableDisplayOverridesRoundTripWithoutChangingOtherPreferences() throws {
        let rules = NotificationScenarioRules(focus: .init(ordinary: .mute, keepsImportant: false),
            meeting: .init(ordinary: .show), screenRecording: .init(ordinary: .deferUntilEnd))
        let settings = FeatureSettings(sideNoticesEnabled: false,
            notificationScenarios: .init(enabled: true, automaticallyDetectsMeetings: true,
                rules: rules, displayOverrides: ["display-uuid": .init()]), userCareEnabled: false)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
        #expect(!restored.sideNoticesEnabled && !restored.userCareEnabled)
        #expect(restored.notificationScenarios.displayOverrides["display-uuid"] == .init())
    }

    @Test(arguments: [#""enabled":"true""#, #""automaticallyDetectsMeetings":1"#,
        #""rules":{"focus":{"ordinary":"hide"}}"#, #""rules":{"meeting":{"keepsImportant":[]}}"#,
        #""displayOverrides":[]"#])
    func invalidRulesFailInsteadOfSilentlyEnablingSuppression(fields: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: Data("{\"notificationScenarios\":{\(fields)}}".utf8))
        }
    }

    @Test
    func incompleteOptInSettingsUseExplicitDefaults() throws {
        let data = Data(#"{"notificationScenarios":{"enabled":true,"rules":{"meeting":{}}}}"#.utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data).notificationScenarios
        #expect(settings.enabled && !settings.automaticallyDetectsMeetings)
        #expect(settings.rules == .init() && settings.displayOverrides.isEmpty)
        #expect(settings.behavior(for: .ordinary, scenarios: [.meeting]) == .deferUntilEnd)
        #expect(settings.behavior(for: .waiting, scenarios: [.meeting]) == .show)
    }

    @Test
    func overlappingScenesUseTheMostRestrictiveApplicableRulePerDisplay() {
        let settings = NotificationScenarioSettings(enabled: true,
            rules: .init(focus: .init(ordinary: .deferUntilEnd), meeting: .init(ordinary: .mute),
                screenRecording: .init(ordinary: .show)),
            displayOverrides: ["showing": .init(focus: .init(ordinary: .show), meeting: .init(ordinary: .show))])
        #expect(settings.behavior(for: .ordinary, scenarios: []) == .show)
        #expect(settings.behavior(for: .ordinary, scenarios: [.focus, .screenRecording]) == .deferUntilEnd)
        #expect(settings.behavior(for: .ordinary, scenarios: [.focus, .meeting]) == .mute)
        #expect(settings.behavior(for: .ordinary, scenarios: [.focus, .meeting], displayIdentifier: "showing") == .show)
        #expect(settings.behavior(for: .ordinary, scenarios: [.meeting], displayIdentifier: "unknown") == .mute)
        #expect(settings.behavior(for: .waiting, scenarios: [.focus, .meeting]) == .show)
    }

    @Test(arguments: NotificationScenario.allCases)
    func importantNoticesRemainVisibleOnlyWhenThatScenePreservesThem(scenario: NotificationScenario) {
        var settings = NotificationScenarioSettings(enabled: true)
        for importance in [ScenarioNoticeImportance.waiting, .failure, .safety, .lowBattery] {
            #expect(settings.behavior(for: importance, scenarios: [scenario]) == .show)
            settings.rules[scenario].keepsImportant = false
            #expect(settings.behavior(for: importance, scenarios: [scenario]) == .deferUntilEnd)
            settings.rules[scenario].ordinary = .mute
            #expect(settings.behavior(for: importance, scenarios: [scenario]) == .mute)
            settings.rules[scenario] = .init()
        }
    }

    @Test
    func noticeClassificationUsesActualSourceStatusInsteadOfOrdinaryInfo() {
        #expect(ScenarioNoticeImportance(notice: .init(id: "ai-active-codex", title: "Working", kind: .info)) == .ordinary)
        #expect(ScenarioNoticeImportance(notice: .init(id: "ai-active-codex", title: "Blocked", kind: .warning)) == .waiting)
        #expect(ScenarioNoticeImportance(notice: .init(id: "ai-active-codex", title: "Failed", kind: .error)) == .failure)
        #expect(ScenarioNoticeImportance(notice: .init(id: "permission", title: "Permission", kind: .warning)) == .safety)
        #expect(ScenarioNoticeImportance(notice: .init(id: "battery-low:keyboard", title: "Battery", kind: .warning)) == .lowBattery)
        #expect(ScenarioNoticeImportance(notice: .init(id: "result", title: "Done", kind: .success)) == .ordinary)
    }
}
