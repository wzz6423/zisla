import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct MonitorIntegrationLocalizationTests {
    @Test(arguments: AppLanguage.allCases) @MainActor
    func monitorInterfaceKeysResolveThroughEveryLanguageTable(language: AppLanguage) throws {
        let keys = try Self.sourceKeys()
        #expect(keys.count >= 100)
        let table = try Self.table(for: language)
        let issues = try Self.catalogIssues(keys: keys, table: table)
        #expect(issues.isEmpty, "Incomplete monitor catalog \(language.rawValue): \(issues.joined(separator: ", "))")
        for key in keys {
            if let value = table[key] {
                #expect(AppLocalization.string(key, locale: language.locale) == value)
            }
        }
    }

    @Test @MainActor
    func dynamicMonitorStatesProduceKeysCoveredByTheSourceScan() throws {
        let scannedKeys = try Self.sourceKeys()
        var runtimeKeys = Set(BatteryPowerMode.allCases.map(BatteryPowerModePresentation.titleKey))
        let errors: [BatteryPowerModeError?] = [
            nil, .stateUnavailable, .unsupportedMode, .authorizationCancelled,
            .authorizationDenied, .changeFailed, .verificationFailed, .timedOut,
        ]
        for error in errors {
            for isChanging in [false, true] {
                for powerSource in [nil, BatteryPowerSource.battery, .powerAdapter] {
                    let presentation = BatteryPowerModePresentation(
                        currentMode: nil,
                        powerSource: powerSource,
                        supportedModes: [],
                        isChanging: isChanging,
                        error: error
                    )
                    runtimeKeys.insert(presentation.titleKey)
                    if let key = presentation.messageKey { runtimeKeys.insert(key) }
                }
            }
        }
        let states: [SignificantEnergyState] = [
            .idle, .loading, .available([]), .unavailable(.unsupported),
            .unavailable(.permissionDenied), .unavailable(.invalidResponse), .unavailable(.readFailed),
        ]
        for state in states {
            if let key = SignificantEnergyView.messageKey(for: state) { runtimeKeys.insert(key) }
        }
        let wifiFailures: [WiFiNetworkFailure] = [
            .interfaceUnavailable, .scanFailed, .powerChangeFailed, .connectionFailed,
            .requiresSystemSettings, .networkUnavailable, .passwordRequired, .settingsUnavailable,
        ]
        runtimeKeys.formUnion(wifiFailures.map(\.messageKey))
        #expect(runtimeKeys.isSubset(of: scannedKeys))
    }

    @Test(arguments: AppLanguage.allCases)
    func locationPurposeExplainsNearbyNetworkAccessInEveryLanguage(language: AppLanguage) throws {
        let url = Self.packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/InfoPlist.strings"
        )
        let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
        let purpose = try #require(table["NSLocationWhenInUseUsageDescription"])
        let networkName = switch language {
        case .german: "WLAN"
        case .dutch: "wifi"
        default: "Wi-Fi"
        }
        #expect(purpose.contains(networkName), "Location access must explain Wi-Fi discovery in \(language.rawValue)")
        if language != .english {
            #expect(purpose != "zisla needs location access to show local weather, place names, and nearby Wi-Fi networks.")
        }
        if language == .simplifiedChinese {
            let plistURL = Self.packageRoot.appendingPathComponent("Resources/Info.plist")
            let plist = try #require(NSDictionary(contentsOf: plistURL) as? [String: Any])
            #expect(plist["NSLocationWhenInUseUsageDescription"] as? String == purpose)
        }
    }

    @Test @MainActor
    func catalogValidationDetectsMissingKeysAndDamagedPlaceholdersInCopies() throws {
        let keys = try Self.sourceKeys()
        let original = try Self.table(for: .english)
        let key = BatteryPowerModePresentation.titleKey(for: .highPower)
        #expect(keys.contains(key))
        var missing = original
        missing.removeValue(forKey: key)
        #expect(try Self.catalogIssues(keys: [key], table: missing) == ["Missing: \(key)"])
        #expect(original[key] != nil)

        let formatKey = try #require(keys.sorted().first { $0.contains("%@") })
        var damaged = original
        damaged[formatKey] = "Invalid translation"
        #expect(try Self.catalogIssues(keys: [formatKey], table: damaged) == ["Placeholders: \(formatKey)"])
    }

    private static func catalogIssues(keys: Set<String>, table: [String: String]) throws -> [String] {
        let placeholder = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:ld|lu|lld|llu|@|\d*\.?\d*[fd])"#)
        func placeholders(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                .sorted()
        }
        return keys.sorted().compactMap { key in
            guard let value = table[key] else { return "Missing: \(key)" }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Empty: \(key)" }
            if placeholders(value) != placeholders(key) { return "Placeholders: \(key)" }
            return nil
        }
    }

    private static func sourceKeys() throws -> Set<String> {
        // Include switch-produced message keys while excluding quoted examples in comments.
        let token = try NSRegularExpression(pattern: #"//[^\n]*|/\*[\s\S]*?\*/|"(?:[^"\\]|\\.)*""#)
        let files = [
            "Zisla/BatteryPowerModeButton", "Zisla/SignificantEnergyView", "Zisla/NetworkSwitchButton",
            "Zisla/SystemMonitorView", "Zisla/WiFiNetworkPanelView",
            "ZislaKit/WiFiNetworkService", "ZislaKit/SystemWiFiPanelController",
        ]
        var keys: Set<String> = ["Wi-Fi"]
        for file in files {
            let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/\(file).swift"), encoding: .utf8)
            for match in token.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range, in: source) else { continue }
                let literal = String(source[range])
                guard literal.first == "\"", literal.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) != nil else { continue }
                keys.insert(String(literal.dropFirst().dropLast()))
            }
        }
        return keys
    }

    private static func table(for language: AppLanguage) throws -> [String: String] {
        let url = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
