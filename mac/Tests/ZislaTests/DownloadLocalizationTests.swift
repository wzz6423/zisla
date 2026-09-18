import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct DownloadLocalizationTests {
    private static let keys = [
        "自动选择",
        "刷新格式",
        "需要 FFmpeg 才能选择格式",
        "选择格式",
        "不使用浏览器 Cookies",
        "浏览器 Cookies",
        "使用 %@ Cookies",
        "%.0f FPS",
        "正在读取格式",
        "未找到可用格式",
        "选择浏览器 Cookies 后重试",
        "抖音返回 HTTP 403，需要近期浏览器 Cookies。请选择 Safari、Chrome 或 Firefox 后重试；无需登录。",
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
    func downloadSourcesQueryEveryNewLocalizationKey() throws {
        let sources = try [
            Self.source("Zisla/DownloadModuleView.swift"),
            Self.source("Zisla/AppModel.swift"),
            Self.source("ZislaCore/DownloadOutput.swift"),
        ].map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for key in Self.keys {
            #expect(sources.contains("\"\(key)\""), "Source no longer queries \(key)")
        }
    }

    @Test
    func downloadModuleKeepsTheFormatControlsInsideItsDedicatedLayout() throws {
        let source = try String(contentsOf: Self.source("Zisla/DownloadModuleView.swift"), encoding: .utf8)

        #expect(source.contains(".frame(height: 170)"))
        #expect(IslandModuleLayout.download.islandSize.height > IslandModuleLayout.toolbox.islandSize.height)
    }

    @Test
    func downloadFormatControlRowUsesLeadingAlignment() throws {
        let source = try String(contentsOf: Self.source("Zisla/DownloadModuleView.swift"), encoding: .utf8)
        let picker = try #require(source.range(of: "IslandOutlinedPicker("))
        let controlRowStart = try #require(source.range(
            of: "HStack(spacing: 10)",
            options: .backwards,
            range: source.startIndex..<picker.lowerBound
        ))
        let controlRowEnd = try #require(source.range(
            of: "HStack(spacing: 10)",
            range: picker.upperBound..<source.endIndex
        ))
        let controlRow = source[controlRowStart.lowerBound..<controlRowEnd.lowerBound]

        #expect(controlRow.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
    }

    @Test
    func downloadModelClearsAnUnavailableBrowserCookieSourceBeforeRetrying() throws {
        let source = try String(contentsOf: Self.source("Zisla/AppModel.swift"), encoding: .utf8)
        let downloadRetry = try #require(source.range(of: "if Self.shouldRetryWithoutBrowserCookies("))
        let retryBody = source[downloadRetry.lowerBound...]
        let formatProbe = try #require(source.range(of: "private func failDownloadFormatProbe"))
        let probeBody = source[formatProbe.lowerBound...]

        #expect(retryBody.contains("browserCookieSource: request.browserCookieSource"))
        #expect(retryBody.contains("self.downloadBrowserCookieSource == request.browserCookieSource"))
        #expect(retryBody.contains("self.downloadBrowserCookieSource = nil"))
        #expect(retryBody.contains("self.startDownload()"))
        #expect(probeBody.contains("browserCookieSource: cookieSource"))
        #expect(probeBody.contains("downloadBrowserCookieSource = nil"))
        #expect(probeBody.contains("refreshDownloadFormats()"))
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

    private static func source(_ relativePath: String) -> URL {
        packageRootURL.appendingPathComponent("Sources/\(relativePath)")
    }

    private static var packageRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
