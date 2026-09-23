import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct IslandClipboardFeatureLocalizationTests {
    @Test
    func everyLanguageContainsTheNewRuntimeLabels() throws {
        let sourceFiles = [
            "Zisla/AppModel.swift", "Zisla/ShelfModuleView.swift",
            "Zisla/SettingsView.swift", "Zisla/CalendarItemEditor.swift",
        ]
        let sources = try sourceFiles.map {
            try String(contentsOf: packageRoot.appendingPathComponent("Sources/\($0)"), encoding: .utf8)
        }.joined(separator: "\n")
        let interfaceKeys = [
            "粘贴内容到中转站", "复制全部内容", "搜索中转内容", "无符合条件的内容",
            "剪贴板没有可暂存的内容", "中转站支持文件、链接或文本",
            "地址", "航班", "火车车次", "快递单号", "会议日程",
            "会议地点", "日程备注", "结束时间",
        ]
        for key in interfaceKeys {
            #expect(sources.contains("\"\(key)\""), "Runtime source no longer uses \(key)")
        }
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

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
