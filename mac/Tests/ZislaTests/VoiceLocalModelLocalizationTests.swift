import Foundation
import Testing
import ZislaCore
import ZislaKit

struct VoiceLocalModelLocalizationTests {
    @Test
    func localConfigurationKeysAreTranslatedAndRenderedInAllLanguages() throws {
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/AIAgentModuleView.swift"), encoding: .utf8)
        let rowStart = try #require(source.range(of: "private struct AILocalModelConfigurationRow"))
        let service = try String(contentsOf: root.appendingPathComponent("Sources/ZislaKit/LMStudioService.swift"), encoding: .utf8)
        let row = String(source[rowStart.lowerBound...]) + service
        let regex = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)""#)
        let keys = Set(regex.matches(in: row, range: NSRange(row.startIndex..., in: row)).compactMap {
            Range($0.range(at: 1), in: row).map { String(row[$0]) }
        })
        #expect(keys.contains("API Key（可选）"))
        #expect(keys.contains("默认无需 API Key；仅在本地服务启用认证时填写。"))
        #expect(keys.contains("未发现模型，请先在本地服务中下载或加载模型。"))
        #expect(keys.contains("启动 LM Studio 服务"))
        #expect(keys.contains("思考"))
        #expect(keys.contains("默认关闭以加快语音整理。开启后允许模型思考，可能提高准确性，但会增加等待时间。"))
        #expect(keys.contains("未找到 LM Studio CLI。请在 LM Studio 中启动 API 服务后重试。"))
        #expect(AppLanguage.allCases.count == 17)
        let english = try table(for: .english)

        for language in AppLanguage.allCases {
            let translations = try table(for: language)
            for key in keys {
                let value = try #require(translations[key], "Missing \(language.rawValue) translation for \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, locale: language.locale) == value)
                #expect(placeholders(value) == placeholders(key))
                if newKeys.contains(key), language != .english, language != .simplifiedChinese {
                    #expect(value != english[key], "Translation must not silently copy English")
                }
            }
        }
        #expect(AppLocalization.string("启动 LM Studio 服务", locale: Locale(identifier: "en")) == "Start LM Studio server")
        #expect(AppLocalization.string("思考", locale: Locale(identifier: "en")) == "Thinking")
        #expect(AppLocalization.string("思考", locale: Locale(identifier: "ar")) == "التفكير")
        #expect(AppLocalization.string("默认关闭以加快语音整理。开启后允许模型思考，可能提高准确性，但会增加等待时间。", locale: Locale(identifier: "zh-Hant")) == "預設關閉以加快語音整理。開啟後允許模型思考，可能提高準確性，但會增加等待時間。")
    }

    private let newKeys: Set<String> = [
        "本地服务", "选择已发现的模型", "API Key（可选）",
        "默认无需 API Key；仅在本地服务启用认证时填写。",
        "未发现模型，请先在本地服务中下载或加载模型。",
        "未找到 LM Studio CLI。请在 LM Studio 中启动 API 服务后重试。",
        "LM Studio 操作失败，请在 LM Studio 中检查本地服务后重试。",
        "LM Studio API 无法连接。请启动服务或检查地址和端口。",
        "启动 LM Studio 服务",
        "思考",
        "默认关闭以加快语音整理。开启后允许模型思考，可能提高准确性，但会增加等待时间。",
    ]

    private func placeholders(_ value: String) -> [String] {
        value.matches(of: /%(?:\d+\$)?(?:\.[0-9]+)?(?:ld|@|d|f)/).map { String($0.output) }.sorted()
    }

    private func table(for language: AppLanguage) throws -> [String: String] {
        let path = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: path) as? [String: String])
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
