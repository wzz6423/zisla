import Foundation
import Testing
import ZislaCore
import ZislaKit

struct MeetingLocalizationTests {
    private static let keys = ["会议倒计时", "会议进行中", "加入会议", "加入会议：%@ · %@", "会议便签",
        "新建会议便签", "关联现有便签", "取消便签关联", "会议已不可加入，请刷新日程", "无法打开会议链接",
        "无法关联会议便签", "日历"]

    @Test(arguments: AppLanguage.allCases)
    func everyLanguageContainsMeetingCopyAndPreservesFormatArguments(language: AppLanguage) throws {
        let table = try Self.table(language)
        let english = try Self.table(.english)
        for key in Self.keys {
            let value = try #require(table[key], "Missing \(language.rawValue): \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            #expect(value.components(separatedBy: "%@").count - 1 == (key == "加入会议：%@ · %@" ? 2 : 0))
            if language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != key)
            }
            if language != .english && language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != english[key])
            }
        }
        let message = AppLocalization.format("加入会议：%@ · %@", locale: language.locale, ["Fixture", "05:00"])
        #expect(message.contains("Fixture") && message.contains("05:00"))
        #expect(!message.contains("%@"))
    }

    @Test
    func chineseEnglishAndArabicRenderTheirOwnMeetingStatus() {
        #expect(AppLocalization.string("会议进行中", language: .simplifiedChinese) == "会议进行中")
        #expect(AppLocalization.string("会议进行中", language: .traditionalChinese) == "會議進行中")
        #expect(AppLocalization.string("会议进行中", language: .english) == "Meeting in progress")
        #expect(AppLocalization.string("会议进行中", language: .arabic) == "الاجتماع جارٍ")
        #expect(AppLocalization.string("加入会议", language: .arabic) == "الانضمام إلى الاجتماع")
    }

    private static func table(_ language: AppLanguage) throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        return try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }
}
