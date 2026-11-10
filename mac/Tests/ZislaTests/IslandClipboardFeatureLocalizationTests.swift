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
            "查询航班", "查询火车", "查询快递",
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

    @Test @MainActor
    func IPLookupLabelsMatchTheToastAndSettingsWithoutChangingURLLabels() throws {
        let key = ClipboardAssistantService.ipInfo.localizedTitleKey
        let url = try #require(URL(string: "https://ipinfo.io/8.8.8.8"))
        #expect(key == "查询 IP 信息")
        #expect(ClipboardAssistantToastView.actionLabel(.openService(service: .ipInfo, url: url)) == key)
        #expect(SettingsView.clipboardAssistantActionTitle(.lookupIP, for: .ipAddress) == key)
        #expect(SettingsView.clipboardAssistantActionTitle(.openURL, for: .url) == "打开链接")
        #expect(SettingsView.clipboardAssistantActionTitle(.copyText, for: .math) == "复制结果")
        #expect(AppLocalization.string(key, language: .english) == "Look Up IP Info")
        #expect(AppLocalization.string(key, language: .arabic) == "الاستعلام عن معلومات IP")
    }

    @Test(arguments: AppLanguage.allCases) @MainActor
    func specializedLookupLabelsUseTheRequestedLocale(language: AppLanguage) throws {
        let translations: [AppLanguage: [String]] = [
            .simplifiedChinese: ["查询航班", "查询火车", "查询快递"],
            .traditionalChinese: ["查詢航班", "查詢火車", "查詢快遞"],
            .english: ["Look Up Flight", "Look Up Train", "Track Package"],
            .japanese: ["フライトを検索", "列車を検索", "荷物を追跡"],
            .korean: ["항공편 조회", "열차 조회", "배송 조회"],
            .french: ["Rechercher un vol", "Rechercher un train", "Suivre un colis"],
            .german: ["Flug suchen", "Zug suchen", "Sendung verfolgen"],
            .spanish: ["Consultar vuelo", "Consultar tren", "Seguir paquete"],
            .brazilianPortuguese: ["Consultar voo", "Consultar trem", "Rastrear encomenda"],
            .italian: ["Cerca volo", "Cerca treno", "Traccia pacco"],
            .dutch: ["Vlucht opzoeken", "Trein opzoeken", "Pakket volgen"],
            .russian: ["Найти рейс", "Найти поезд", "Отследить посылку"],
            .arabic: ["الاستعلام عن رحلة طيران", "الاستعلام عن قطار", "تتبع الشحنة"],
            .thai: ["ค้นหาเที่ยวบิน", "ค้นหาขบวนรถไฟ", "ติดตามพัสดุ"],
            .indonesian: ["Cari penerbangan", "Cari kereta", "Lacak paket"],
            .vietnamese: ["Tra cứu chuyến bay", "Tra cứu tàu hỏa", "Theo dõi bưu kiện"],
            .turkish: ["Uçuş sorgula", "Tren sorgula", "Kargo takip et"],
        ]
        let expected = try #require(translations[language])
        let kinds: [ClipboardAssistantKind] = [.flight, .train, .tracking]
        let keys = kinds.map { SettingsView.clipboardAssistantActionTitle(.openURL, for: $0) }
        #expect(keys == ["查询航班", "查询火车", "查询快递"])
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"case \.(?:flight|train|tracking): \"(查询[^\"]+)\""#)
        let runtimeKeys = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[Range($0.range(at: 1), in: source)!])
        }
        #expect(runtimeKeys == keys)
        let tableURL = packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        for (key, value) in zip(keys, expected) {
            #expect(table[key] == value)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
        }
        for kind in kinds {
            #expect(SettingsView.clipboardAssistantActionTitle(.search, for: kind) == "搜索")
        }
        for kind in ClipboardAssistantKind.allCases where !kinds.contains(kind) {
            #expect(SettingsView.clipboardAssistantActionTitle(.openURL, for: kind) == "打开链接")
        }
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
