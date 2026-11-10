import Foundation
import Testing
import ZislaCore

struct ApplicationOpenRepairSettingsTests {
    @Test
    func systemFailureMonitoringDefaultsOffAndRoundTripsIndependently() throws {
        #expect(!FeatureSettings.default.applicationOpenFailureMonitoringEnabled)
        let legacy = try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8))
        #expect(!legacy.applicationOpenFailureMonitoringEnabled)
        for enabled in [false, true] {
            var settings = FeatureSettings.default
            settings.applicationOpenFailureMonitoringEnabled = enabled
            settings.clipboardAssistantEnabled = false
            let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
            #expect(restored.applicationOpenFailureMonitoringEnabled == enabled)
            #expect(!restored.clipboardAssistantEnabled)
            #expect(restored.clipboardAssistantEnabledKinds == settings.clipboardAssistantEnabledKinds)
        }
    }

    @Test
    func repairHasOneActionAndIsEnabledByDefault() throws {
        let kind = try #require(ClipboardAssistantKind(rawValue: "appCannotOpen"))
        #expect(ClipboardAssistantKind.allCases.filter { $0 == kind }.count == 1)
        #expect(FeatureSettings.default.clipboardAssistantEnabledKinds.contains(kind))
        #expect(ClipboardAssistantActionOrder.defaults(for: kind).map(\.rawValue) == ["repairAndOpenApp"])
        #expect(FeatureSettings.default.clipboardAssistantActionOrders[kind]?.map(\.rawValue) == ["repairAndOpenApp"])
    }

    @Test
    func versionFourEnablesRepairOnceWithoutRestoringOtherOptOuts() throws {
        let kind = try #require(ClipboardAssistantKind(rawValue: "appCannotOpen"))
        let data = Data(#"{"clipboardAssistantKindSetVersion":4,"clipboardAssistantEnabledKinds":["url"],"clipboardAssistantConversionDefaultApplied":true,"clipboardAssistantAppDefaultApplied":true}"#.utf8)
        var settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.clipboardAssistantEnabledKinds == [.url, kind])
        #expect(settings.clipboardAssistantKindSetVersion == 5)
        settings.clipboardAssistantEnabledKinds.remove(kind)
        for _ in 0..<2 {
            settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
            #expect(settings.clipboardAssistantEnabledKinds == [.url])
            #expect(settings.clipboardAssistantKindSetVersion == 5)
        }
    }

    @Test
    func emptySelectionKeepsItsAllKindsMeaning() throws {
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"clipboardAssistantKindSetVersion":4,"clipboardAssistantEnabledKinds":[]}"#.utf8))
        #expect(settings.clipboardAssistantEnabledKinds.isEmpty)
        #expect(settings.clipboardAssistantKindSetVersion == 5)
    }

    @Test
    func repairUpgradeKeepsCustomActions() throws {
        let kind = try #require(ClipboardAssistantKind(rawValue: "appCannotOpen"))
        var settings = FeatureSettings.default
        settings.clipboardAssistantKindSetVersion = 4
        settings.clipboardAssistantActionOrders[.url] = [.share, .openURL, .openDownload, .addToQuickNote]
        settings.clipboardAssistantActionOrders.removeValue(forKey: kind)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.clipboardAssistantActionOrders[.url] == settings.clipboardAssistantActionOrders[.url])
        #expect(restored.clipboardAssistantActionOrders[kind]?.map(\.rawValue) == ["repairAndOpenApp"])
    }
}
