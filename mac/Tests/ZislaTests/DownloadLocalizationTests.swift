import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct DownloadLocalizationTests {
    private static let keys = [
        "自动选择",
        "刷新格式",
        "需要 FFmpeg 才能选择格式",
        "选择格式",
        "不使用浏览器 Cookies",
        "浏览器 Cookies",
        "未检测到可用浏览器 Cookies",
        "使用 %@ Cookies",
        "%.0f FPS",
        "正在读取格式",
        "未找到可用格式",
        "选择浏览器 Cookies 后重试",
        "抖音返回 HTTP 403，需要近期浏览器 Cookies。请选择可用的浏览器 Cookies 后重试；无需登录。",
        "无法读取浏览器 Cookies。请在「系统设置 → 隐私与安全性 → 完全磁盘访问」中允许 zisla，然后重启应用重试。",
        "授权磁盘访问",
        "无法读取下载格式",
    ]

    @Test
    func everyLanguageTranslatesDownloadFormatKeys() throws {
        for language in AppLanguage.allCases {
            let table = try #require(
                Self.stringsTable(for: language),
                "Could not parse \(language.rawValue) Localizable.strings"
            )
            for key in Self.keys {
                let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(
                    Self.placeholders(in: value) == Self.placeholders(in: key),
                    "\(language.rawValue) has incompatible placeholders for \(key)"
                )
            }
        }
    }

    @Test
    func downloadLayoutIsTallerThanTheToolbox() {
        #expect(IslandModuleLayout.download.islandSize.height > IslandModuleLayout.toolbox.islandSize.height)
    }

    @Test
    func cookieAccessGuidanceIsRecognizedInEveryLanguageWithoutTreatingNetworkErrorsAsPermissions() {
        for language in AppLanguage.allCases {
            let message = AppLocalization.string(
                "无法读取浏览器 Cookies。请在「系统设置 → 隐私与安全性 → 完全磁盘访问」中允许 zisla，然后重启应用重试。",
                language: language
            )
            #expect(DownloadFailureDiagnostics.requiresBrowserCookieAccess(message))
        }
        #expect(!DownloadFailureDiagnostics.requiresBrowserCookieAccess(""))
        #expect(!DownloadFailureDiagnostics.requiresBrowserCookieAccess("ERROR: HTTP Error 403: Forbidden"))
        #expect(!DownloadFailureDiagnostics.requiresBrowserCookieAccess("ERROR: Fresh cookies are needed"))
    }

    /// Explicit locales keep this regression independent of the user's persisted interface language.
    @Test(arguments: AppLanguage.allCases) @MainActor
    func missingDownloaderGuidanceUsesTheRequestedLocale(language: AppLanguage) throws {
        let error = YTDLPResolverError.executableNotFound(searched: [])
        let key = try #require(error.errorDescription)
        let expected = try #require(Self.stringsTable(for: language)?[key])
        let message = AppModel.downloadErrorText(error, locale: language.locale)
        #expect(message == expected)
        #expect(message.contains(AppLocalization.string(SettingsSection.download.title, language: language)))
        if language != .simplifiedChinese {
            #expect(message != key)
        }
    }

    /// Tool output may match a catalog key, but translating it would conceal the diagnostic actually emitted.
    @Test(arguments: AppLanguage.allCases) @MainActor
    func externalDownloadDiagnosticsRemainUnchanged(language: AppLanguage) {
        for diagnostic in ["ERROR: HTTP Error 403: Forbidden", "下载失败"] {
            let error = DownloadServiceError.processFailed(exitCode: 1, diagnostic: diagnostic)
            #expect(AppModel.downloadErrorText(error, locale: language.locale) == diagnostic)
        }
        for diagnostic in ["", "Synthetic download failure", "下载失败"] {
            let error = NSError(domain: "DownloadLocalizationTests", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: diagnostic])
            #expect(AppModel.downloadErrorText(error, locale: language.locale) == diagnostic)
        }
    }

    private static func stringsTable(for language: AppLanguage) -> [String: String]? {
        NSDictionary(contentsOf: packageRootURL
            .appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings"))
            as? [String: String]
    }

    private static func placeholders(in value: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"%(?:ld|@|\d*\.?\d*[fd])"#) else {
            return []
        }
        return expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
            .sorted()
    }

    private static var packageRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
