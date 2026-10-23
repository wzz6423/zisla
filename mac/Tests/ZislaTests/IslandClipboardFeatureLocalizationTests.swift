import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct IslandClipboardFeatureLocalizationTests {
    @Test
    func everyLanguageContainsTheNewRuntimeLabels() throws {
        let interfaceKeys = [
            "粘贴内容到中转站", "复制全部内容", "搜索中转内容", "无符合条件的内容",
            "剪贴板没有可暂存的内容", "中转站支持文件、链接或文本",
            "IP 地址", "地址", "航班", "火车车次", "快递单号", "会议日程",
            "会议地点", "日程备注", "结束时间",
        ]
        let serviceKeys = ClipboardAssistantService.allCases.map(\.localizedTitleKey)
        for language in AppLanguage.allCases {
            let tableURL = packageRoot.appendingPathComponent(
                "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
            )
            let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
            for key in interfaceKeys + serviceKeys {
                let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, language: language) == value)
            }
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func IPAddressLabelUsesTheRequestedLocale(language: AppLanguage) throws {
        let translations: [AppLanguage: String] = [
            .simplifiedChinese: "IP 地址", .traditionalChinese: "IP 位址", .english: "IP Address",
            .japanese: "IP アドレス", .korean: "IP 주소", .french: "Adresse IP", .german: "IP-Adresse",
            .spanish: "Dirección IP", .brazilianPortuguese: "Endereço IP", .italian: "Indirizzo IP",
            .dutch: "IP-adres", .russian: "IP-адрес", .arabic: "عنوان IP", .thai: "ที่อยู่ IP",
            .indonesian: "Alamat IP", .vietnamese: "Địa chỉ IP", .turkish: "IP Adresi",
        ]
        let expected = try #require(translations[language])
        #expect(AppLocalization.string("IP 地址", locale: language.locale) == expected)
    }

    @Test
    func serviceActionsDisplayTheirProviderAndCalendarActionsUseTheEditorLabel() throws {
        let url = try #require(URL(string: "https://example.com/"))
        for service in ClipboardAssistantService.allCases {
            #expect(ClipboardAssistantToastView.actionLabel(.openService(service: service, url: url))
                == service.localizedTitleKey)
        }
        let draft = ClipboardCalendarDraft(title: "Meeting", startDate: .distantPast, endDate: .distantFuture)
        #expect(ClipboardAssistantToastView.actionLabel(.editCalendarEvent(draft)) == "新建日程")
        #expect(AppLocalization.string("会议地点", language: .english) == "Meeting Location")
        #expect(AppLocalization.string("日程备注", language: .english) == "Event Notes")
    }

    @Test
    func IPLookupLabelsMatchTheToastAndSettingsWithoutChangingURLLabels() throws {
        let key = ClipboardAssistantService.ipInfo.localizedTitleKey
        let url = try #require(URL(string: "https://ipinfo.io/8.8.8.8"))
        #expect(key == "查询 IP 信息")
        #expect(ClipboardAssistantToastView.actionLabel(.openService(service: .ipInfo, url: url)) == key)
        #expect(SettingsView.clipboardAssistantActionTitle(.openURL, for: .ipAddress) == key)
        #expect(SettingsView.clipboardAssistantActionTitle(.openURL, for: .url) == "打开链接")
        #expect(SettingsView.clipboardAssistantActionTitle(.copyText, for: .ipAddress) == "复制结果")
        #expect(AppLocalization.string(key, language: .english) == "Look Up IP Info")
        #expect(AppLocalization.string(key, language: .arabic) == "الاستعلام عن معلومات IP")
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
