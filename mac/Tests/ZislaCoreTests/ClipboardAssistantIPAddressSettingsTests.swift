import Foundation
import Testing
import ZislaCore

struct ClipboardAssistantIPAddressSettingsTests {
    @Test
    func IPKindHasStableIdentityAndDefaultActions() throws {
        #expect(ClipboardAssistantKind.ipAddress.rawValue == "ipAddress")
        #expect(try JSONDecoder().decode(ClipboardAssistantKind.self, from: Data(#""ipAddress""#.utf8)) == .ipAddress)
        #expect(ClipboardAssistantKind.allCases.filter { $0 == .ipAddress }.count == 1)
        #expect(ClipboardAssistantKind.ipAddress.symbolName == "network")
        #expect(FeatureSettings.default.clipboardAssistantEnabledKinds.contains(.ipAddress))
        #expect(FeatureSettings.clipboardAssistantKindSetVersionCurrent == 4)
        #expect(ClipboardAssistantActionOrder.defaults(for: .ipAddress) == [.openURL, .copyText, .addToQuickNote, .share])
        #expect(FeatureSettings.default.clipboardAssistantActionOrders[.ipAddress] == [.openURL, .copyText, .addToQuickNote, .share])
    }

    @Test
    func versionThreeAddsOnlyIPAndOptOutSurvivesRepeatedRestart() throws {
        let payload = Data(#"{"clipboardAssistantKindSetVersion":3,"clipboardAssistantEnabledKinds":["url","text"],"clipboardAssistantConversionDefaultApplied":true,"clipboardAssistantAppDefaultApplied":true}"#.utf8)
        var settings = try JSONDecoder().decode(FeatureSettings.self, from: payload)
        #expect(settings.clipboardAssistantEnabledKinds == [.url, .text, .ipAddress])
        #expect(settings.clipboardAssistantKindSetVersion == 4)
        let migrated = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(migrated.clipboardAssistantEnabledKinds == settings.clipboardAssistantEnabledKinds)
        settings.clipboardAssistantEnabledKinds.remove(.ipAddress)
        for _ in 0..<2 {
            settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
            #expect(settings.clipboardAssistantEnabledKinds == [.url, .text])
            #expect(settings.clipboardAssistantKindSetVersion == 4)
        }
    }

    @Test
    func currentVersionRespectsAnExplicitIPOptOut() throws {
        let payload = Data(#"{"clipboardAssistantKindSetVersion":4,"clipboardAssistantEnabledKinds":["url"],"clipboardAssistantConversionDefaultApplied":true,"clipboardAssistantAppDefaultApplied":true}"#.utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: payload)
        #expect(settings.clipboardAssistantEnabledKinds == [.url])
    }

    @Test(arguments: [0, 3, 4])
    func emptyKindSelectionKeepsItsAllKindsMeaning(version: Int) throws {
        let payload = Data("{\"clipboardAssistantKindSetVersion\":\(version),\"clipboardAssistantEnabledKinds\":[]}".utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: payload)
        #expect(settings.clipboardAssistantEnabledKinds.isEmpty)
        #expect(settings.clipboardAssistantKindSetVersion == 4)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.clipboardAssistantEnabledKinds.isEmpty)
    }

    @Test
    func IPUpgradePreservesExistingAndNewCustomActionOrders() throws {
        var settings = FeatureSettings.default
        settings.clipboardAssistantKindSetVersion = 3
        settings.clipboardAssistantEnabledKinds = [.url, .text]
        settings.clipboardAssistantActionOrders.removeValue(forKey: .ipAddress)
        let urlOrder: [ClipboardAssistantActionKind] = [.share, .openURL, .addToQuickNote, .openDownload]
        let textOrder: [ClipboardAssistantActionKind] = [.saveText, .translate, .search, .addToQuickNote, .sendToTeleprompter, .share]
        settings.clipboardAssistantActionOrders[.url] = urlOrder
        settings.clipboardAssistantActionOrders[.text] = textOrder
        var upgraded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(upgraded.clipboardAssistantActionOrders[.url] == urlOrder)
        #expect(upgraded.clipboardAssistantActionOrders[.text] == textOrder)
        #expect(upgraded.clipboardAssistantActionOrders[.ipAddress] == [.openURL, .copyText, .addToQuickNote, .share])
        let ipOrder: [ClipboardAssistantActionKind] = [.share, .copyText, .addToQuickNote, .openURL]
        upgraded.clipboardAssistantActionOrders[.ipAddress] = ipOrder
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(upgraded))
        #expect(restored.clipboardAssistantActionOrders[.ipAddress] == ipOrder)
        #expect(restored.clipboardAssistantActionOrders[.url] == urlOrder)
        #expect(restored.clipboardAssistantActionOrders[.text] == textOrder)
    }

    @Test(arguments: [ClipboardAssistantActionKind.openURL, .copyText])
    func IPPrimaryActionSurvivesRestart(primary: ClipboardAssistantActionKind) throws {
        let address = "8.8.8.8"
        let url = try #require(URL(string: "https://ipinfo.io/8.8.8.8"))
        let lookup = ClipboardAssistantAction.openService(service: .ipInfo, url: url)
        var settings = FeatureSettings.default
        settings.clipboardAssistantActionOrders[.ipAddress] = ClipboardAssistantActionOrder.normalized(
            [primary], for: .ipAddress
        )
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        let actions = ClipboardAssistantActionOrder.ordered(
            [lookup, .copyText(address), .addToQuickNote, .share],
            for: .ipAddress, using: restored.clipboardAssistantActionOrders
        )
        #expect(actions.first?.kind == primary)
        #expect(actions.contains(lookup))
        #expect(actions.contains(.copyText(address)))
    }
}
