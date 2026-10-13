import Foundation
import Testing
import ZislaCore

@testable import Zisla

/// Missing catalog entries silently fall back to Chinese, so validate every language table.
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
    func nonChineseTableProvidesConcreteTranslations() throws {
        let english = try #require(Self.stringsTable(for: .english))
        #expect(english["应用程序"] == "Applications")
        #expect(english["打开应用"] == "Open App")
    }

    @Test
    func quickActionsNameAndFolderActionTranslateEveryLanguage() throws {
        let detailKey = "复制、浏览器下载或 AirDrop 接收完成后显示下一步操作"

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

    @Test
    func saveFileLocationSettingTranslatesEveryLanguage() throws {
        let key = "每次保存文件时选择位置"
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let table = try #require(
                Self.stringsTable(for: language),
                "无法解析 \(language.rawValue) 的 Localizable.strings"
            )
            let value = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != key, "\(language.rawValue) 未翻译「\(key)」")
            }
            #expect(table["每次保存图片时选择位置"] == nil)
        }
        let english = try #require(Self.stringsTable(for: .english))
        #expect(english[key] == "Choose a location whenever saving a file")
    }

    @Test
    func downloadFolderActionSettingTranslatesEveryLanguage() throws {
        let title = "下载与 AirDrop 完成提示"
        let detail = "完成后显示“打开文件夹”快捷操作"

        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let table = try #require(
                Self.stringsTable(for: language),
                "无法解析 \(language.rawValue) 的 Localizable.strings"
            )
            for key in [title, detail] {
                let value = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, language: language) == value)
                if language != .simplifiedChinese && language != .traditionalChinese {
                    #expect(value != key, "\(language.rawValue) 未翻译「\(key)」")
                }
            }
        }
        let english = try #require(Self.stringsTable(for: .english))
        #expect(english[title] == "Download and AirDrop Completion Prompts")
        #expect(english[detail] == "Show an Open Folder quick action when a file finishes")
    }

    @Test
    func foreignTextSettingNamesZislaGlobalLanguageInEveryLanguage() throws {
        let key = "非 Zisla 全局语言文本"
        let englishValue = "Text Not in Zisla’s Global Language"
        #expect(AppLanguage.allCases.count == 17)

        for language in AppLanguage.allCases {
            let table = try #require(Self.stringsTable(for: language))
            let value = try #require(table[key], "\(language.rawValue) is missing the app-language recognition title")
            #expect(value.contains("Zisla"))
            #expect(AppLocalization.string(key, language: language) == value)
            #expect(table["非当前系统语言文本"] == nil)
            if language != .simplifiedChinese {
                #expect(value != key, "\(language.rawValue) must translate the app-language recognition title")
            }
            if language != .english {
                #expect(value != englishValue, "\(language.rawValue) must not use the English fallback")
            }
        }

        #expect(AppLocalization.string(key, language: .english) == englishValue)
        #expect(AppLocalization.string(key, language: .traditionalChinese) == "非 Zisla 全域語言文字")
    }

    @Test
    func shellCommandActionAndLaunchFailureTranslateInEveryLanguage() throws {
        let actionKey = ClipboardAssistantToastView.actionLabel(.runShellCommand("pwd"))
        #expect(actionKey == "前台执行")
        let backgroundKey = ClipboardAssistantToastView.actionLabel(.runShellCommandInBackground("pwd"))
        #expect(backgroundKey == "后台执行")
        let failureKey = "无法在终端运行命令"
        let backgroundFailureKey = "无法在后台运行命令"
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let table = try #require(Self.stringsTable(for: language))
            for key in [actionKey, backgroundKey, failureKey, backgroundFailureKey, "Shell 命令"] {
                let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, language: language) == value)
                if language != .simplifiedChinese {
                    #expect(value != key)
                }
                if language != .english {
                    #expect(value != AppLocalization.string(key, language: .english))
                }
            }
        }
        #expect(AppLocalization.string(actionKey, language: .english) == "Run in Foreground")
        #expect(AppLocalization.string(actionKey, language: .traditionalChinese) == "前景執行")
        #expect(AppLocalization.string(actionKey, language: .arabic) == "تشغيل في المقدمة")
        #expect(AppLocalization.string(backgroundKey, language: .english) == "Run in Background")
    }

    @Test
    func automationPermissionExplainsTerminalCommandsInEveryLanguage() throws {
        let key = "NSAppleEventsUsageDescription"
        var descriptions: [AppLanguage: String] = [:]
        for language in AppLanguage.allCases {
            let url = Self.localizationURL
                .appendingPathComponent("\(language.rawValue).lproj/InfoPlist.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            let value = try #require(table[key], "\(language.rawValue) is missing the automation permission purpose")
            #expect(value.contains("Mail.app"))
            #expect(value.contains("Terminal"))
            #expect(value.contains("iTerm"))
            descriptions[language] = value
        }
        #expect(descriptions.count == 17)
        #expect(Set(descriptions.values).count == 17)
        #expect(descriptions[.english]?.hasSuffix("It also runs commands you choose in Terminal or iTerm.") == true)
        #expect(descriptions[.simplifiedChinese]?.hasSuffix("还可在 Terminal 或 iTerm 中运行你选择的命令。") == true)
        let infoURL = Self.packageRootURL.appendingPathComponent("Resources/Info.plist")
        let info = try #require(NSDictionary(contentsOf: infoURL))
        #expect(info[key] as? String == descriptions[.simplifiedChinese])
    }

    private static func stringsTable(for language: AppLanguage) -> [String: String]? {
        let url = localizationURL
            .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        return NSDictionary(contentsOf: url) as? [String: String]
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
