import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct SettingsMediaLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func settingsPDFAndVolumeKeysResolveInEveryLanguage(language: AppLanguage) throws {
        let keys = try Self.sourceKeys()
        #expect(keys.count >= 96, "Runtime localization scan found only \(keys.count) keys")
        let table = try Self.table(for: language)
        let english = try Self.table(for: .english)
        let issues = try Self.catalogIssues(keys: keys, table: table, language: language, english: english)
        #expect(issues.isEmpty, "Incomplete catalog \(language.rawValue): \(issues.joined(separator: ", "))")

        for key in keys {
            if let value = table[key] {
                #expect(AppLocalization.string(key, locale: language.locale) == value)
            }
        }
        let applicationName = language.isRightToLeft ? "\u{2068}Demo App\u{2069}" : "Demo App"
        for key in ["%@ 的音量", "取消 %@ 的静音", "将 %@ 静音"] {
            let value = try #require(table[key])
            #expect(
                AppLocalization.format(key, locale: language.locale, ["Demo App"])
                    == value.replacingOccurrences(of: "%@", with: applicationName)
            )
        }
    }

    @Test
    func newLabelsUseRequestedLocales() {
        #expect(AppLanguage.allCases.count == 17)
        #expect(AppLocalization.string("应用音量混音器", language: .english) == "App Volume Mixer")
        #expect(AppLocalization.string("声音", language: .english) == "Sound")
        #expect(AppLocalization.string("在设置中合并、拆分、加密与转换 PDF。", language: .english)
            == "Merge, split, encrypt, and convert PDFs in Settings.")
        #expect(AppLocalization.string("应用音量混音器", language: .arabic) == "مازج صوت التطبيقات")
        #expect(AppLocalization.string("应用音量混音器", language: .traditionalChinese) == "應用程式音量混音器")
    }

    @Test(arguments: AppLanguage.allCases)
    func audioCapturePurposeExplainsMediaAndAppVolume(language: AppLanguage) throws {
        let table = try Self.table(for: language, name: "InfoPlist")
        let purpose = try #require(table["NSAudioCaptureUsageDescription"])
        #expect(!purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(purpose.contains("zisla"))
        #expect(!purpose.contains("%"))
        let terms = try #require(Self.audioPurposeTerms[language])
        for term in terms {
            #expect(purpose.contains(term), "Audio access must explain \(term) in \(language.rawValue)")
        }

        let english = try Self.table(for: .english, name: "InfoPlist")
        if language != .english {
            #expect(purpose != english["NSAudioCaptureUsageDescription"])
        } else {
            #expect(purpose.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) == nil)
        }
        if language == .simplifiedChinese {
            let plist = try #require(NSDictionary(contentsOf: Self.packageRoot.appendingPathComponent("Resources/Info.plist")))
            #expect(plist["NSAudioCaptureUsageDescription"] as? String == purpose)
        }
    }

    @Test
    func catalogValidationDetectsMissingEmptyAndDamagedTranslationsInCopies() throws {
        let original = try Self.table(for: .english)
        let key = "应用音量混音器"
        var missing = original
        missing.removeValue(forKey: key)
        #expect(try Self.catalogIssues(keys: [key], table: missing, language: .english, english: original)
            == ["Missing: \(key)"])

        var empty = original
        empty[key] = " \n "
        #expect(try Self.catalogIssues(keys: [key], table: empty, language: .english, english: original)
            == ["Empty: \(key)"])

        let formatKey = "%@ 的音量"
        var damaged = original
        damaged[formatKey] = "Volume for %ld"
        #expect(try Self.catalogIssues(keys: [formatKey], table: damaged, language: .english, english: original)
            == ["Placeholders: \(formatKey)"])

        var fallback = original
        fallback[key] = key
        #expect(try Self.catalogIssues(keys: [key], table: fallback, language: .english, english: original)
            == ["Chinese in English: \(key)"])

        var copied = try Self.table(for: .german)
        copied[key] = original[key]
        #expect(try Self.catalogIssues(keys: [key], table: copied, language: .german, english: original)
            == ["Copied English: \(key)"])
        #expect(original[key] == "App Volume Mixer")
    }

    private static func catalogIssues(
        keys: Set<String>, table: [String: String], language: AppLanguage, english: [String: String]
    ) throws -> [String] {
        let expression = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:ld|lu|lld|llu|@|\d*\.?\d*[fd])"#)
        func placeholders(_ text: String) -> [String] {
            expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        }
        return keys.sorted().compactMap { key in
            guard let value = table[key] else { return "Missing: \(key)" }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Empty: \(key)" }
            if placeholders(value) != placeholders(key) { return "Placeholders: \(key)" }
            if language == .english, value.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) != nil {
                return "Chinese in English: \(key)"
            }
            if language != .english, language != .simplifiedChinese, language != .traditionalChinese,
               newKeys.contains(key), value == english[key] {
                return "Copied English: \(key)"
            }
            return nil
        }
    }

    private static func sourceKeys() throws -> Set<String> {
        // Switch-produced labels and error keys also reach localization through indirect calls.
        let token = try NSRegularExpression(pattern: #"//[^\n]*|/\*[\s\S]*?\*/|"(?:[^"\\]|\\.)*""#)
        var keys = newKeys
        keys.formUnion(SettingsSectionGroup.allCases.map(\.title))
        keys.formUnion([SettingsSection.pdfTools.title, SettingsSection.pdfTools.subtitle])
        keys.formUnion(AppearanceMode.allCases.map(\.menuTitle))
        keys.formUnion(PDFToolOperation.allCases.flatMap { [$0.title, $0.detail, $0.actionTitle, $0.inputButtonTitle] })

        var sources: [String] = []
        for file in ["Zisla/PDFToolsModuleView", "Zisla/ApplicationVolumeMixerModuleView", "ZislaKit/ApplicationVolumeMixerService"] {
            sources.append(try String(contentsOf: packageRoot.appendingPathComponent("Sources/\(file).swift"), encoding: .utf8))
        }
        let settingsSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        let settingsCalls = try NSRegularExpression(
            pattern: #"(?s)private var generalContent:.*?(?=private func appearanceButton)|featureToggle\("(?:PDF 工具|应用音量混音器)"[^\n]*"#
        )
        for match in settingsCalls.matches(in: settingsSource, range: NSRange(settingsSource.startIndex..., in: settingsSource)) {
            if let range = Range(match.range, in: settingsSource) { sources.append(String(settingsSource[range])) }
        }
        for source in sources {
            for match in token.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range, in: source) else { continue }
                let literal = String(source[range])
                guard literal.first == "\"", literal.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) != nil else { continue }
                keys.insert(String(literal.dropFirst().dropLast()))
            }
        }
        return keys
    }

    private static let newKeys: Set<String> = [
        "隐藏侧边栏", "显示侧边栏", "后退", "前进",
        "基础功能", "声音", "网络与其他",
        "仅影响 zisla 的窗口与面板，不会更改 macOS 外观。",
        "在设置中合并、拆分、加密与转换 PDF。", "应用音量混音器",
        "在灵动岛分别调整应用的媒体音量。", "分别调整正在播放声音的应用",
        "应用音量需要 macOS 14.4 或更高版本", "暂无正在播放声音的应用",
        "播放音乐或视频后，应用会显示在这里。", "%@ 的音量", "取消 %@ 的静音", "将 %@ 静音",
        "等待应用音量控制生效", "音量调整未生效", "请允许音频录制以调整应用音量",
        "当前音频输出设备不可用", "无法调整应用音量，已恢复原始输出", "取消静音",
        "当前音频输出格式不支持应用音量调整",
    ]

    private static let audioPurposeTerms: [AppLanguage: [String]] = [
        .simplifiedChinese: ["播放媒体", "应用音量"],
        .traditionalChinese: ["播放媒體", "應用程式音量"],
        .english: ["media playback", "app's volume"],
        .japanese: ["メディアの再生", "アプリ音量"],
        .korean: ["미디어를 재생", "앱 음량"],
        .french: ["lecture de médias", "volume d’une app"],
        .german: ["Medienwiedergabe", "Lautstärke einer App"],
        .spanish: ["reproducción multimedia", "volumen de una app"],
        .brazilianPortuguese: ["reprodução de mídia", "volume de um app"],
        .italian: ["riproduzione multimediale", "volume di un’app"],
        .dutch: ["afspelen van media", "volume van een app"],
        .russian: ["воспроизведении медиа", "громкость приложения"],
        .arabic: ["تشغيل الوسائط", "مستوى صوت تطبيق"],
        .thai: ["ขณะเล่นสื่อ", "ระดับเสียงแอป"],
        .indonesian: ["media diputar", "volume aplikasi"],
        .vietnamese: ["khi phát nội dung", "âm lượng ứng dụng"],
        .turkish: ["medya oynatılırken", "uygulamanın ses düzeyini"],
    ]

    private static func table(for language: AppLanguage, name: String = "Localizable") throws -> [String: String] {
        let url = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/\(name).strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
