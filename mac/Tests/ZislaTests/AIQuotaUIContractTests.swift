import Foundation
import Testing
import ZislaCore

struct AIQuotaUIContractTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/" + path), encoding: .utf8)
    }

    @Test
    func quotaControlsAndWindowLabelsAreTranslatedInAllSeventeenLanguages() throws {
        let literal = try NSRegularExpression(pattern: #""([^"\n]+)""#)
        var keys: Set<String> = ["访问密钥 ID", "秘密访问密钥"]
        for path in ["Zisla/AIQuotaViews.swift", "ZislaCore/AIQuotaConfiguration.swift", "ZislaKit/AIQuotaResponseParser.swift"] {
            let text = try source(path)
            for match in literal.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(match.range(at: 1), in: text)!])
                if key.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }), !key.contains("\\(") { keys.insert(key) }
            }
        }
        #expect(keys.count >= 62)
        #expect(AppLanguage.allCases.count == 17)
        let placeholders = try NSRegularExpression(pattern: #"%(?:ld|@|\d*\.?\d*[fd])"#)
        func tokens(_ text: String) -> [String] {
            placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                String(text[Range($0.range, in: text)!])
            }.sorted()
        }
        for language in AppLanguage.allCases {
            let path = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: path) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "Missing \(language.rawValue): \(key)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(tokens(key) == tokens(value), "Placeholder mismatch: \(language.rawValue), \(key)")
                #expect(AppLocalization.string(key, language: language) == value)
            }
        }
        #expect(AppLocalization.string("余额与额度", language: .english) == "Balance and quota")
        #expect(AppLocalization.string("额度", language: .arabic) == "الحصة")
    }

    @Test
    func quotaPanelPrecedesRunningSessionsAndPreservesTheExistingCharts() throws {
        let view = try source("Zisla/AIProgressModuleView.swift")
        let quota = try #require(view.range(of: "AIQuotaPanel(monitor: model.aiQuotaMonitor"))
        let tasks = try #require(view.range(of: "runningTasks", range: quota.upperBound..<view.endIndex))
        let between = view[quota.upperBound..<tasks.lowerBound]
        #expect(between.contains(".frame(height: 144, alignment: .top)"))
        #expect(between.contains("Divider()"))
        #expect(view.contains("weeks: 24"))
        #expect(view.contains("usageSummary(endingAt: .now)"))
        let model = try source("Zisla/AppModel.swift")
        #expect(model.contains("static let ai = keyboardSound"))
        #expect(model.contains("configurations.filter(\\.isEnabled).map"))
        #expect(model.contains("AIQuotaProviderReader(configuration: $0, credentials: aiQuotaStore.credentials"))
        #expect(model.contains("aiQuotaMonitor.stop()"))
        #expect(model.contains("aiQuotaNotice.stop()"))
        #expect(model.contains("settings.aiProgressEnabled && settings.sideNoticesEnabled"))
    }

    @Test
    func configurationSupportsSecureEntryAndBothNotchAndBarUseQuotaWings() throws {
        let editor = try source("Zisla/AIQuotaViews.swift")
        #expect(editor.contains("AIQuotaProvider.allCases"))
        #expect(editor.contains(".sheet(item: $editing)"))
        #expect(editor.contains("SecureField(AppLocalization.text"))
        #expect(editor.contains("store.save(configuration, credential:"))
        #expect(editor.contains("NSWindow("))
        let side = try source("Zisla/SideNoticeView.swift")
        let quotaBranch = try #require(side.range(of: "else if let quotaNotice = presentation.activeTransientNotice"))
        let mediaBranch = try #require(side.range(of: "else if let mediaNotice = presentation.activeMediaNotice"))
        #expect(quotaBranch.lowerBound < mediaBranch.lowerBound)
        #expect(side.contains("CompactTransientWing(notice: transientNotice, side: .left"))
        #expect(side.contains("CompactTransientWing(notice: transientNotice, side: .right"))
        #expect(side.contains("AIQuotaIcon(providerID: notice.metadata?[\"providerID\"]"))
        #expect(side.contains("Text(notice.metadata?[\"remaining\"] ?? notice.title)"))
    }
}
