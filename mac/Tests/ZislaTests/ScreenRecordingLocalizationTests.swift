import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct ScreenRecordingLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func recordingKeysUseRequestedLanguage(language: AppLanguage) throws {
        let keys = try Self.runtimeKeys()
        let requiredKeys: Set<String> = [
            "录屏工作室", "全屏录制", "暂停或继续录制", "启用录屏", "恢复默认快捷键",
            "录制屏幕、编辑视频与保存项目。", "打开录屏工作室", "留白", "起点（秒）",
            "片段 %d · 缩放 %d · 字幕 %d", "录屏项目数据无效", "录屏文件写入超时",
            "AI 未返回有效的剪辑计划，未应用任何修改", "字幕在本机转写，不上传录音",
            "正在播放原始素材",
            "预览与导出使用相同的画面效果",
            "录屏控制条", "保存位置", "更改保存位置", "选择录屏保存目录",
            "圆角", "圆形摄像头", "矩形",
            "系统声音音量", "麦克风音量", "显示摄像头", "画布比例", "背景颜色", "标注",
        ]
        #expect(requiredKeys.isSubset(of: keys), "The recording source scan missed runtime keys")
        #expect(keys.isDisjoint(with: ["pause.fill", "play.fill", "record.circle", "source."]))
        #expect(AppLanguage.allCases.count == 17)

        let table = try Self.table(language: language)
        for key in keys {
            let translation = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(Self.placeholders(translation) == Self.placeholders(key),
                    "\(language.rawValue) changed the placeholders in \(key)")
            #expect(AppLocalization.string(key, locale: language.locale) == translation,
                    "\(language.rawValue) resolved the wrong language for \(key)")
        }

        if language != .english && language != .simplifiedChinese {
            let english = try Self.table(language: .english)
            for key in ["仅在生成方案时发送指令和部分字幕，原始视频留在本机", "字幕在本机转写，不上传录音",
                        "录屏正在进行，请先停止当前录制", "预览与导出使用相同的画面效果"] {
                #expect(table[key] != english[key], "\(language.rawValue) copied the English text for \(key)")
            }
        }
    }

    @Test
    func recordingOutputAndSettingsSearchUseEnglishAndArabic() throws {
        #expect(AppLocalization.string("录屏工作室", locale: Locale(identifier: "en")) == "Screen Recording Studio")
        #expect(AppLocalization.string("录屏工作室", locale: Locale(identifier: "ar")) == "استوديو تسجيل الشاشة")
        #expect(AppLocalization.string("生成字幕", locale: Locale(identifier: "en")) == "Generate Captions")
        #expect(AppLocalization.string("生成字幕", locale: Locale(identifier: "ar")) == "إنشاء الترجمات النصية")
        #expect(AppLocalization.format("片段 %d · 缩放 %d · 字幕 %d", locale: Locale(identifier: "en"),
                                       [2, 3, 4]) == "Segments 2 · Zooms 3 · Captions 4")
        #expect(AppLocalization.format("输出时长：%@", locale: Locale(identifier: "ar"),
                                       ["00:42"]) == "مدة الناتج: \u{2068}00:42\u{2069}")
        #expect(AppLanguage.allCases.filter(\.isRightToLeft) == [.arabic])

        var settings = FeatureSettings.default
        settings.screenRecordingEnabled = true
        for language in [AppLanguage.english, .arabic] {
            let query = AppLocalization.string(RecordingShortcutAction.studio.title, locale: language.locale)
            let results = SettingsSearchIndex.results(for: query, settings: settings, locale: language.locale)
            #expect(results.contains { $0.section == .recording && $0.title == RecordingShortcutAction.studio.title })
            let item = try #require(results.first { $0.section == .recording && $0.title == RecordingShortcutAction.studio.title })
            #expect(item.anchor.localized(locale: language.locale) == .row(query))
        }

        let studio = try Self.source("Sources/Zisla/ScreenRecordingStudioView.swift")
        #expect(studio.contains("languageStore.language.isRightToLeft ? .rightToLeft : .leftToRight"))
    }

    @Test(arguments: AppLanguage.allCases)
    func recordingPermissionDescriptionsCoverEveryLanguage(language: AppLanguage) throws {
        let descriptions = try Self.table(language: language, name: "InfoPlist")
        let english = try Self.table(language: .english, name: "InfoPlist")
        let source = try Data(contentsOf: Self.packageURL.appendingPathComponent("Resources/Info.plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: source, format: nil) as? [String: Any])
        let localizedLanguages = try #require(info["CFBundleLocalizations"] as? [String])
        #expect(Set(localizedLanguages) == Set(AppLanguage.allCases.map(\.rawValue)))
        for key in Self.permissionKeys {
            let value = try #require(descriptions[key], "\(language.rawValue) is missing \(key)")
            #expect(value.contains("zisla"))
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(Self.placeholders(value).isEmpty)
            if language == .simplifiedChinese {
                #expect(value == (info[key] as? String), "\(key) must match the permission description in Info.plist")
            } else if language != .english {
                #expect(value != english[key], "\(language.rawValue) copied the English permission description")
            }
        }
        if language == .english {
            #expect(descriptions["NSAudioCaptureUsageDescription"]?.contains("enable system audio for screen recording") == true)
            #expect(descriptions["NSCameraUsageDescription"]?.contains("camera overlay for screen recording") == true)
            #expect(descriptions["NSMicrophoneUsageDescription"]?.contains("enable the microphone for screen recording") == true)
            #expect(descriptions["NSSpeechRecognitionUsageDescription"]?.contains("transcribes locally") == true)
        }
    }

    @Test
    func sourceScannerKeepsNestedLabelsAndIgnoresSymbolsAndFormattingArguments() throws {
        let source = #"""
        AppLocalization.text(model.ready ? "继续录制" : model.failed ? "录屏已取消" : "暂停录制")
        AppLocalization.text(model.isBusy ? "录屏正在导出，请等待或取消" : "导出录屏"), systemImage: "record.circle"
        AppLocalization.text("录屏失败：%@", AppLocalization.text("取消"))
        AppLocalization.text("片段 %d", source.id + "source.")
        """#
        #expect(try Self.localizedKeys(source) == ["继续录制", "录屏已取消", "暂停录制",
            "录屏正在导出，请等待或取消", "导出录屏", "录屏失败：%@", "取消", "片段 %d"])
    }

    private static let permissionKeys = [
        "NSAudioCaptureUsageDescription", "NSCameraUsageDescription",
        "NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription",
    ]

    private static func runtimeKeys() throws -> Set<String> {
        let directory = packageURL.appendingPathComponent("Sources/Zisla")
        var paths = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("ScreenRecording") && $0.pathExtension == "swift" }
        paths += [packageURL.appendingPathComponent("Sources/ZislaCore/ScreenRecordingModels.swift"),
                  packageURL.appendingPathComponent("Sources/ZislaKit/ScreenRecordingProjectStore.swift")]
        var keys = Set(RecordingCaptureMode.allCases.map(\.title))
        keys.formUnion(RecordingBackground.allCases.map(\.title))
        keys.formUnion(RecordingCameraPosition.allCases.map(\.title))
        keys.formUnion(RecordingExportResolution.allCases.map(\.title))
        keys.formUnion(RecordingShortcutAction.allCases.map(\.title))
        keys.formUnion(RecordingCanvasAspectRatio.allCases.map(\.title))
        keys.formUnion(RecordingAnnotationKind.allCases.map(\.title))
        keys.formUnion([SettingsSection.recording.title, SettingsSection.recording.subtitle])

        for path in paths {
            let text = try String(contentsOf: path, encoding: .utf8)
            keys.formUnion(try localizedKeys(text))
            keys.formUnion(try captures(#"(?:parameter|timeField|zoomField|cropField|audioParameter|numberField)\(\s*"([^"\\]+)""#, in: text))
            keys.formUnion(try captures(#"ScreenRecordingColorPicker\(title:\s*"([^"\\]+)""#, in: text))
            if path.lastPathComponent == "ScreenRecordingModels.swift" {
                keys.formUnion(try captures(#"return "([^"\\]+)""#, in: text))
            }
        }

        let settings = try source("Sources/Zisla/SettingsView.swift")
        let start = try #require(settings.range(of: "if input.selection == .features || input.selection == .recording {"))
        let end = try #require(settings.range(of: "if input.selection == .features || input.selection == .screenshot {",
                                              range: start.upperBound..<settings.endIndex))
        let group = String(settings[start.lowerBound..<end.lowerBound])
        keys.formUnion(try localizedKeys(group))
        keys.formUnion(try captures(#"(?:settingsGroup|featureToggle)\("([^"\\]+)""#, in: group))
        keys.formUnion(try captures(#"(?:title|detail): "([^"\\]+)""#, in: group))
        let conflictStart = try #require(settings.range(of: "private var currentRecordingHotkeyConflict:"))
        let conflictEnd = try #require(settings.range(of: "private func updateScreenshotHotkey(",
                                                     range: conflictStart.upperBound..<settings.endIndex))
        keys.formUnion(try localizedKeys(String(settings[conflictStart.lowerBound..<conflictEnd.lowerBound])))

        var enabled = FeatureSettings.default
        enabled.screenRecordingEnabled = true
        keys.formUnion(SettingsSearchIndex.items(settings: enabled).filter { $0.section == .recording }.map(\.title))
        let toolbox = try source("Sources/Zisla/ToolboxModuleView.swift")
        keys.formUnion(try captures(#"AppLocalization\.text\("(录屏|打开录屏工作室)""#, in: toolbox))
        let menu = try source("Sources/Zisla/ZislaApp.swift")
        keys.formUnion(try captures(#"localized\("(录屏|录屏工作室)""#, in: menu))
        return keys
    }

    private static func localizedKeys(_ source: String) throws -> Set<String> {
        let calls = try NSRegularExpression(pattern: #"AppLocalization\.(?:text|string|format)\s*\("#)
        var keys: Set<String> = []
        for match in calls.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let range = try #require(Range(match.range, in: source))
            let start = range.upperBound
            var end = start
            var depth = 0
            var quoted = false
            var escaped = false
            while end < source.endIndex {
                let character = source[end]
                if quoted {
                    if escaped { escaped = false }
                    else if character == "\\" { escaped = true }
                    else if character == "\"" { quoted = false }
                } else if character == "\"" {
                    quoted = true
                } else if "([{".contains(character) {
                    depth += 1
                } else if ")]}".contains(character) {
                    if depth == 0 { break }
                    depth -= 1
                } else if character == "," && depth == 0 {
                    break
                }
                end = source.index(after: end)
            }
            keys.formUnion(try captures(#""((?:[^"\\]|\\.)*)""#, in: String(source[start..<end])))
        }
        return keys
    }

    private static func captures(_ pattern: String, in source: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
    }

    private static func placeholders(_ source: String) -> [String] {
        source.matches(of: /%(?:\d+\$)?(?:\.[0-9]+)?(?:ld|@|d|f)/).map { String($0.output) }
    }

    private static func table(language: AppLanguage, name: String = "Localizable") throws -> [String: String] {
        try #require(NSDictionary(contentsOf: packageURL.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/\(name).strings")) as? [String: String])
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: packageURL.appendingPathComponent(path), encoding: .utf8)
    }

    private static var packageURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
