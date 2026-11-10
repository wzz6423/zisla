import AppKit
import Foundation
import Testing
import ZislaCore
@testable import Zisla

struct AIAccountBalanceLocalizationTests {
    static let keys = ["%@ 积分", "%@ 重置", "Codex 账户额度", "Qoder 中国", "Qoder 监控地区", "TRAE 中国", "不限额度", "中国区",
        "仅查询所选地区，已保存的其他地区凭据会保留", "仅编辑预测额度，模型余额需要网站登录凭据", "代码补全", "低额度提醒",
        "供应商未提供已验证的本地额度查询接口", "其他位置常驻额度", "剩余额度不高于 20% 时提醒，耗尽后也会提醒", "可用预算", "可用额度", "各供应商额度",
        "团队额度", "国际区", "完整样式最多显示两行真实额度", "展示额度", "打开账户页，在开发者工具的 Network 中复制额度请求的 Cookie 请求头",
        "收起态额度样式", "无法保存额度查询凭据，请检查 Cookie 格式或存储权限", "暂不支持额度查询", "未登录", "模型额度", "每日额度", "每月额度", "滚动额度",
        "由所连接账户计费", "登录凭据不可用", "登录已过期", "监控额度", "积分余额", "粘贴网站 Cookie", "编辑预测", "网站额度凭据", "聊天额度", "账户上限",
        "账户剩余额度", "选择灵动岛其他位置时显示额度，多个账户自动轮播", "采样于 %@", "需要网站登录凭据，桌面登录暂不能用于额度查询", "需要额度查询凭据",
        "额外预算", "额度响应格式已变化", "额度服务暂不可用", "额度查询凭据已保存", "额度查询凭据已清除", "额度查询限流", "高级请求"]

    // Country names and borrowed terms can have the same spelling in different languages.
    private static let sharedTranslations: [AppLanguage: [String: String]] = [
        .japanese: ["Qoder 中国": "Qoder 中国", "TRAE 中国": "TRAE 中国"],
        .german: ["Qoder 中国": "Qoder China", "TRAE 中国": "TRAE China", "中国区": "China"],
        .spanish: ["Qoder 中国": "Qoder China", "TRAE 中国": "TRAE China", "中国区": "China"],
        .brazilianPortuguese: ["Qoder 中国": "Qoder China", "TRAE 中国": "TRAE China", "中国区": "China"],
        .dutch: ["Qoder 中国": "Qoder China", "TRAE 中国": "TRAE China", "中国区": "China",
            "%@ 积分": "%@ credits", "额外预算": "Extra budget"]
    ]

    @Test(arguments: AppLanguage.allCases)
    func allBalanceCopyRendersRequestedLanguageAndPreservesPlaceholders(language: AppLanguage) throws {
        let table = try self.table(language), english = try self.table(.english)
        #expect(AppLanguage.allCases.count == 17 && Self.keys.count == 53)
        for key in Self.keys {
            let translation = try #require(table[key], "Missing \(language.rawValue) key \(key)")
            #expect(!translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(AppLocalization.string(key, language: language) == translation)
            #expect(translation.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
            if let expected = Self.sharedTranslations[language]?[key] {
                #expect(translation == expected)
            } else {
                if language != .simplifiedChinese && language != .traditionalChinese { #expect(translation != key) }
                if language != .english && language != .simplifiedChinese && language != .traditionalChinese {
                    #expect(translation != english[key], "\(language.rawValue) must not copy English for \(key)")
                }
            }
        }
        let credits = AIAccountQuotaWindow(id: "credits", kind: .credits, remaining: 10, unit: .credits)
        let localizedNumber = Double(10).formatted(.number.precision(.fractionLength(0...2)).locale(language.locale))
        #expect(credits.value(language: language) == AppLocalization.format("%@ 积分", locale: language.locale, [localizedNumber]))
        let rolling = AIAccountQuotaWindow(id: "rolling", kind: .rolling, remainingPercent: 10)
        #expect(rolling.label(language: language) == table["滚动额度"])
        let name = AIAccountQuotaWindow(id: "overall", kind: .all, remainingPercent: 10, nameKey: "账户上限")
        #expect(name.label(language: language) == table["账户上限"])
        let gpt = AIAccountBalance(id: "gpt", providers: [.gpt], status: .available, windows: [rolling])
        #expect(gpt.providerTitle(language: language) == "GPT · " + (table["Codex 账户额度"] ?? ""))
        #expect(language.isRightToLeft == (language == .arabic))
    }

    @Test func expectedEnglishTraditionalAndArabicSourcesRemainExplicit() {
        #expect(AppLocalization.string("Codex 账户额度", language: .english) == "Codex account quota")
        #expect(AppLocalization.string("账户剩余额度", language: .traditionalChinese) == "帳戶剩餘額度")
        #expect(AppLocalization.string("账户剩余额度", language: .arabic) == "الحصة المتبقية للحساب")
    }

    @Test func runtimeBalanceCopyAndIndirectTitlesAreAllIncludedInTheLocaleContract() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sourcePaths = ["Sources/ZislaCore/AIAccountBalance.swift", "Sources/ZislaKit/AIAccountBalanceParser.swift",
            "Sources/ZislaKit/AIAccountBalanceCookieStore.swift", "Sources/ZislaKit/AIAccountBalanceService.swift",
            "Sources/Zisla/AIAccountBalanceCookieInput.swift", "Sources/Zisla/AIAccountBalanceView.swift",
            "Sources/Zisla/DailyBriefingAIAccountBalanceSection.swift"]
        let expression = try NSRegularExpression(pattern: #""([^"\\\n]*)""#)
        let chinese = try NSRegularExpression(pattern: #"[\u4e00-\u9fff]"#)
        var discovered: Set<String> = []
        var texts = try sourcePaths.map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        let start = try #require(settings.range(of: "featureToggle(\"低额度提醒\""))
        let end = try #require(settings.range(of: "featureToggle(\"AI 任务结果扫光\""))
        texts.append(String(settings[start.lowerBound..<end.lowerBound]))
        for text in texts {
            let value = text as NSString
            for match in expression.matches(in: text, range: NSRange(location: 0, length: value.length)) {
                let key = value.substring(with: match.range(at: 1))
                if chinese.firstMatch(in: key, range: NSRange(location: 0, length: (key as NSString).length)) != nil { discovered.insert(key) }
            }
        }
        let existingKeys: Set<String> = ["全部", "%@ 次", "每周额度", "保存", "清除"]
        #expect(discovered.subtracting(existingKeys) == Set(Self.keys),
            "Every runtime label, parser-provided localizable name, and indirect enum title must be covered by all languages")
    }

    private func table(_ language: AppLanguage) throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try #require(NSDictionary(contentsOf: root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")) as? [String: String])
    }
}
