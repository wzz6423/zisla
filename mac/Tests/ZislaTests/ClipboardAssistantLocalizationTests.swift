import Foundation
import Testing
import ZislaCore

@testable import Zisla

/// 复制助手「应用程序」链路的文案与其它识别类型一致：任一语言缺 key 都会让界面
/// 静默退回中文原文，因此这里核对新增 key 在全部语言表中齐备，并断言源码确实
/// 在查询这些 key，避免测试与实际查询点脱节。
struct ClipboardAssistantLocalizationTests {
    private static let keys = ["应用程序", "打开应用", "无法打开应用"]

    @Test
    func everyLanguageTranslatesAssistantAppKeys() throws {
        for language in AppLanguage.allCases {
            let table = try #require(
                Self.stringsTable(for: language),
                "无法解析 \(language.rawValue) 的 Localizable.strings"
            )
            for key in Self.keys {
                let value = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
                #expect(!value.isEmpty, "\(language.rawValue) 的「\(key)」为空")
            }
        }
    }

    @Test
    func assistantSourcesQueryTheAppKeys() throws {
        let settings = try String(
            contentsOf: Self.sourceURL("Zisla/SettingsView.swift"), encoding: .utf8
        )
        #expect(settings.contains(#"case .app: "应用程序""#))
        #expect(settings.contains(#"case .openApp: "打开应用""#))

        let controller = try String(
            contentsOf: Self.sourceURL("Zisla/ClipboardAssistantWindowController.swift"),
            encoding: .utf8
        )
        #expect(controller.contains(#"case .openApp: "打开应用""#))

        let appModel = try String(
            contentsOf: Self.sourceURL("Zisla/AppModel.swift"), encoding: .utf8
        )
        #expect(appModel.contains(#"clipboardAssistantMessage("无法打开应用")"#))
    }

    @Test
    func nonChineseTableProvidesConcreteTranslations() throws {
        let english = try #require(Self.stringsTable(for: .english))
        #expect(english["应用程序"] == "Applications")
        #expect(english["打开应用"] == "Open App")
    }

    @Test
    func quickActionsNameAndFolderActionTranslateEveryLanguage() throws {
        let settings = try String(
            contentsOf: Self.sourceURL("Zisla/SettingsView.swift"), encoding: .utf8
        )
        let detailKey = "复制、浏览器下载或 AirDrop 接收完成后显示下一步操作"
        #expect(settings.contains("settingsGroup(\"快捷操作\")"))
        #expect(settings.contains("case .clipboardAssistant: \"快捷操作\""))
        #expect(settings.contains("detail: \"\(detailKey)\""))
        #expect(!settings.contains("\"复制助手\""))

        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let table = try #require(
                Self.stringsTable(for: language),
                "无法解析 \(language.rawValue) 的 Localizable.strings"
            )
            for key in ["快捷操作", detailKey, "打开文件夹"] {
                let value = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
                #expect(!value.isEmpty, "\(language.rawValue) 的「\(key)」为空")
                #expect(AppLocalization.string(key, language: language) == value)
                if language != .simplifiedChinese && language != .traditionalChinese {
                    #expect(value != key, "\(language.rawValue) 未翻译「\(key)」")
                }
            }
            #expect(table["复制助手"] == nil)
            #expect(table["复制后弹出识别结果和下一步操作"] == nil)
        }

        let english = try #require(Self.stringsTable(for: .english))
        #expect(english["快捷操作"] == "Quick Actions")
        #expect(english["打开文件夹"] == "Open Folder")
    }

    private static func stringsTable(for language: AppLanguage) -> [String: String]? {
        let url = localizationURL
            .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        return NSDictionary(contentsOf: url) as? [String: String]
    }

    private static func sourceURL(_ relativePath: String) -> URL {
        packageRootURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(relativePath)
    }

    private static var localizationURL: URL {
        packageRootURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Localization", isDirectory: true)
    }

    private static var packageRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
