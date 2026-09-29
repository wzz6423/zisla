import Foundation
import Testing
@testable import ZislaCore

struct ClipboardShellCommandSettingsTests {
    @Test
    func shellCommandsHaveTheirOwnCategoryAndUniversalActions() throws {
        let shell = try #require(ClipboardAssistantKind(rawValue: "shellCommand"))
        #expect(ClipboardAssistantKind.allCases.contains(shell))
        #expect(ClipboardAssistantActionOrder.defaults(for: shell).map(\.rawValue) == [
            "runShellCommand", "runShellCommandInBackground", "search", "saveText",
            "addToQuickNote", "sendToTeleprompter", "share",
        ])
        for kind in ClipboardAssistantKind.allCases where kind != shell {
            #expect(!ClipboardAssistantActionOrder.defaults(for: kind).map(\.rawValue).contains("runShellCommand"))
        }
        #expect(ClipboardAssistantActionOrder.defaults(for: .code) == [.saveText, .addToQuickNote, .sendToTeleprompter, .share])
    }

    @Test
    func previousKindSelectionUpgradesOnceAndRespectsOptOut() throws {
        let shell = try #require(ClipboardAssistantKind(rawValue: "shellCommand"))
        let data = Data(#"{"clipboardAssistantKindSetVersion":2,"clipboardAssistantEnabledKinds":["url"],"clipboardAssistantConversionDefaultApplied":true,"clipboardAssistantAppDefaultApplied":true}"#.utf8)
        var restored = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(restored.clipboardAssistantEnabledKinds == [.url, shell])
        #expect(restored.clipboardAssistantKindSetVersion == 3)
        restored.clipboardAssistantEnabledKinds.remove(shell)
        let reopened = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(restored))
        #expect(reopened.clipboardAssistantEnabledKinds == [.url])
        let allKinds = try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"clipboardAssistantKindSetVersion":2,"clipboardAssistantEnabledKinds":[]}"#.utf8))
        #expect(allKinds.clipboardAssistantEnabledKinds.isEmpty)
    }

    @Test
    func customSearchOrBackgroundPrioritySurvivesRestart() throws {
        let shell = try #require(ClipboardAssistantKind(rawValue: "shellCommand"))
        let background = try #require(ClipboardAssistantActionKind(rawValue: "runShellCommandInBackground"))
        for primary in [ClipboardAssistantActionKind.search, background] {
            var settings = FeatureSettings.default
            settings.clipboardAssistantActionOrders[shell] = ClipboardAssistantActionOrder.normalized([primary], for: shell)
            let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
            #expect(restored.clipboardAssistantActionOrders[shell] == settings.clipboardAssistantActionOrders[shell])
            #expect(restored.clipboardAssistantActionOrders[shell]?.first == primary)
            let ordered = ClipboardAssistantActionOrder.ordered(
                [.runShellCommand("pwd"), .runShellCommandInBackground("pwd"), .search("pwd")],
                for: shell, using: restored.clipboardAssistantActionOrders
            )
            #expect(ordered.first == (primary == .search ? .search("pwd") : .runShellCommandInBackground("pwd")))
        }
    }
}
