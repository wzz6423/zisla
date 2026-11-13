import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct ClipboardAssistantSettingsActionsTests {
    @Test(arguments: ClipboardAssistantKind.allCases)
    func menuSelectionPromotesAnyActionAndPreservesTheRemainingOrder(kind: ClipboardAssistantKind) {
        let defaults = ClipboardAssistantActionOrder.defaults(for: kind)
        for action in defaults {
            var settings = FeatureSettings.default
            let binding = Binding(get: { settings }, set: { settings = $0 })
            SettingsView.setPrimaryClipboardAssistantAction(action, for: kind, settings: binding)
            let selectedOrder = [action] + defaults.filter { $0 != action }
            #expect(settings.clipboardAssistantActionOrders[kind] == selectedOrder)
            var expected = FeatureSettings.default
            expected.clipboardAssistantActionOrders[kind] = selectedOrder
            #expect(settings == expected, "Selecting a default for \(kind) must not change other settings")
            SettingsView.setPrimaryClipboardAssistantAction(action, for: kind, settings: binding)
            #expect(settings == expected, "Selecting the current default must not duplicate actions")
        }
    }

    @Test(arguments: [nil, [], [.translate, .translate, .repairAndOpenApp]] as [[ClipboardAssistantActionKind]?])
    func menuSelectionNormalizesSavedOrdersAndChangesTheExecutableDefault(saved: [ClipboardAssistantActionKind]?) throws {
        var settings = FeatureSettings.default
        settings.clipboardAssistantActionOrders[.text] = saved
        let binding = Binding(get: { settings }, set: { settings = $0 })
        SettingsView.setPrimaryClipboardAssistantAction(.share, for: .text, settings: binding)
        settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        let order = try #require(settings.clipboardAssistantActionOrders[.text])
        #expect(order.first == .share)
        #expect(order.count == ClipboardAssistantActionOrder.defaults(for: .text).count)
        #expect(Set(order) == Set(ClipboardAssistantActionOrder.defaults(for: .text)))
        #expect(ClipboardAssistantActionOrder.ordered(Self.textActions, for: .text,
            using: settings.clipboardAssistantActionOrders).first == .share)
    }

    @Test(arguments: ClipboardAssistantKind.allCases)
    func anyActionCanMoveAcrossTheFirstPosition(kind: ClipboardAssistantKind) {
        let defaults = ClipboardAssistantActionOrder.defaults(for: kind)
        for (index, action) in defaults.enumerated() {
            var settings = FeatureSettings.default
            let binding = Binding(get: { settings }, set: { settings = $0 })
            for _ in 0..<index {
                SettingsView.moveClipboardAssistantAction(action, for: kind, by: -1, settings: binding)
            }
            #expect(settings.clipboardAssistantActionOrders[kind] == [action] + defaults.filter { $0 != action },
                    "Moving \(action) to the first position must preserve every other \(kind) action")
            var expected = FeatureSettings.default
            expected.clipboardAssistantActionOrders[kind] = settings.clipboardAssistantActionOrders[kind]
            #expect(settings == expected, "Reordering \(kind) must not change other settings")
        }
    }

    @Test
    func movingTheFirstActionDownChangesTheExecutableDefault() throws {
        var settings = FeatureSettings.default
        let binding = Binding(get: { settings }, set: { settings = $0 })
        SettingsView.moveClipboardAssistantAction(.search, for: .text, by: 1, settings: binding)
        #expect(settings.clipboardAssistantActionOrders[.text]?.first == .saveText)
        let actions = ClipboardAssistantActionOrder.ordered(Self.textActions, for: .text,
            using: settings.clipboardAssistantActionOrders)
        #expect(actions.first == .saveText("fixture"))
        #expect(Set(actions.map(\.identifier)) == Set(Self.textActions.map(\.identifier)))
    }

    @Test
    func boundaryAndUnavailableMovesDoNotChangeSettings() {
        var settings = FeatureSettings.default
        let original = settings
        let binding = Binding(get: { settings }, set: { settings = $0 })
        SettingsView.moveClipboardAssistantAction(.search, for: .text, by: -1, settings: binding)
        SettingsView.moveClipboardAssistantAction(.share, for: .text, by: 1, settings: binding)
        SettingsView.moveClipboardAssistantAction(.repairAndOpenApp, for: .text, by: -1, settings: binding)
        for offset in [-1, 1] {
            SettingsView.moveClipboardAssistantAction(.repairAndOpenApp, for: .appCannotOpen,
                by: offset, settings: binding)
        }
        #expect(settings == original)
    }

    @Test(arguments: [nil, [], [.translate, .translate, .repairAndOpenApp]] as [[ClipboardAssistantActionKind]?])
    func movesReuseExistingNormalization(saved: [ClipboardAssistantActionKind]?) {
        var settings = FeatureSettings.default
        settings.clipboardAssistantActionOrders[.text] = saved
        let binding = Binding(get: { settings }, set: { settings = $0 })
        let action: ClipboardAssistantActionKind = saved?.isEmpty == false ? .search : .saveText
        SettingsView.moveClipboardAssistantAction(action, for: .text, by: -1, settings: binding)
        let order = settings.clipboardAssistantActionOrders[.text] ?? []
        #expect(order.first == action)
        #expect(order.count == ClipboardAssistantActionOrder.defaults(for: .text).count)
        #expect(Set(order) == Set(ClipboardAssistantActionOrder.defaults(for: .text)))
    }

    @Test
    func disablingAndReopeningRetainsTheReorderedDefault() throws {
        var settings = FeatureSettings.default
        let binding = Binding(get: { settings }, set: { settings = $0 })
        for _ in 1..<Self.textActions.count {
            SettingsView.moveClipboardAssistantAction(.share, for: .text, by: -1, settings: binding)
        }
        let savedOrder = settings.clipboardAssistantActionOrders[.text]
        settings.clipboardAssistantEnabledKinds.remove(.text)
        settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(!settings.clipboardAssistantEnabledKinds.contains(.text))
        #expect(settings.clipboardAssistantActionOrders[.text] == savedOrder)
        settings.clipboardAssistantEnabledKinds.insert(.text)
        settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(settings.clipboardAssistantEnabledKinds.contains(.text))
        #expect(settings.clipboardAssistantActionOrders[.text] == savedOrder)
        #expect(ClipboardAssistantActionOrder.ordered(Self.textActions, for: .text,
            using: settings.clipboardAssistantActionOrders).first == .share)
    }

    @Test(arguments: AppLanguage.allCases)
    func theFirstActionHasALocalizedSecondaryDefaultSuffix(language: AppLanguage) throws {
        let packageRoot = Self.settingsViewSourceURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let tableURL = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let suffix = try #require(table["（默认）"], "\(language.rawValue) is missing the default-action suffix")
        #expect(!suffix.isEmpty)
        #expect(AppLocalization.string("（默认）", locale: language.locale) == suffix)
        if language != .simplifiedChinese { #expect(suffix != "（默认）") }
    }

    private static let textActions: [ClipboardAssistantAction] = [
        .search("fixture"), .saveText("fixture"), .translate("fixture"),
        .addToQuickNote, .sendToTeleprompter, .share,
    ]

    private static var settingsViewSourceURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/SettingsView.swift")
    }
}
