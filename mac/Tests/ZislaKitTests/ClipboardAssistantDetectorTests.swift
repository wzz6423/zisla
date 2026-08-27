import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantDetectorTests {
    private let allKinds = Set(ClipboardAssistantKind.allCases)

    @Test
    func detectsPlainHTTPAndHTTPSURLs() {
        let detection = ClipboardAssistantDetector.detect(
            text: "https://example.com/path?q=1",
            enabledKinds: allKinds
        )
        #expect(detection?.kind == .url)
        #expect(detection?.title == "example.com")
        #expect(detection?.secondaryActions.isEmpty == true)
        if case .openURL(let url)? = detection?.action {
            #expect(url.absoluteString == "https://example.com/path?q=1")
        } else {
            Issue.record("URL action expected")
        }
    }

    @Test
    func offersDownloadForSupportedURLWhenEnabled() throws {
        let url = try #require(URL(string: "https://youtu.be/example"))
        let detection = ClipboardAssistantDetector.detect(
            text: url.absoluteString,
            enabledKinds: allKinds,
            offersDownload: true
        )

        #expect(detection?.action == .openURL(url))
        #expect(detection?.secondaryActions == [.openDownload(url)])
    }

    @Test
    func offersDownloadForBilibiliURLWhenEnabled() throws {
        let url = try #require(URL(string: "https://www.bilibili.com/video/BV1c7GA6kEqN/"))
        let detection = ClipboardAssistantDetector.detect(
            text: url.absoluteString,
            enabledKinds: allKinds,
            offersDownload: true
        )

        #expect(detection?.action == .openURL(url))
        #expect(detection?.secondaryActions == [.openDownload(url)])
    }

    @Test
    func doesNotTreatArbitraryWordsAsURL() {
        let detection = ClipboardAssistantDetector.detect(text: "hello world", enabledKinds: allKinds)
        #expect(detection?.kind != .url)
    }

    @Test
    func detectsExistingLocalFilePathWithTilde() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let fileURL = temporaryDirectory.appendingPathComponent("zisla-assistant-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let detection = ClipboardAssistantDetector.detect(
            text: fileURL.path,
            enabledKinds: allKinds
        )
        #expect(detection?.kind == .filePath)
        #expect(detection?.title == fileURL.lastPathComponent)
        if case .revealInFinder(let url)? = detection?.action {
            #expect(url == fileURL.standardizedFileURL)
        } else {
            Issue.record("reveal action expected")
        }
        #expect(detection?.secondaryActions == [.compress(fileURL.standardizedFileURL)])
    }

    @Test
    func unresolvablePathKeepsPathKindWithCopyAction() {
        // Temp files get cleaned up and other apps' containers are unreachable; the copied value is
        // still a path, so it must not fall through to the Chinese/plain text branch.
        let path = "/zisla-missing-root-\(UUID().uuidString)/VKTemp/01E3BE85-1731/图像.png"
        let detection = ClipboardAssistantDetector.detect(text: path, enabledKinds: allKinds)
        #expect(detection?.kind == .filePath)
        #expect(detection?.title == "图像.png")
        #expect(detection?.detail == .path(path))
        #expect(detection?.actions == [.copyText(path)])
    }

    @Test
    func missingFileInAnExistingFolderRevealsThatFolder() {
        let directory = FileManager.default.temporaryDirectory
        let missing = directory.appendingPathComponent("zisla-assistant-gone-\(UUID().uuidString).png")
        let detection = ClipboardAssistantDetector.detect(text: missing.path, enabledKinds: allKinds)
        #expect(detection?.kind == .filePath)
        if case .revealInFinder(let url)? = detection?.action {
            #expect(url.path == directory.path)
        } else {
            Issue.record("reveal action for the surviving parent directory expected")
        }
        #expect(detection?.secondaryActions == [.copyText(missing.path)])
    }

    @Test
    func rejectsValuesThatOnlyLookVaguelyLikePaths() {
        for text in ["/help", "hello world", "not/a/path"] {
            let detection = ClipboardAssistantDetector.detect(text: text, enabledKinds: allKinds)
            #expect(detection?.kind != .filePath, "expected \(text) not to read as a path")
        }
        // Whitespace in an unresolvable value means a command line, not a path.
        #expect(ClipboardAssistantDetector.filePathCandidate(from: "/usr/bin/env python3 main.py") == nil)
    }

    @Test
    func detectsEmailAddresses() {
        let detection = ClipboardAssistantDetector.detect(text: "someone@example.com", enabledKinds: allKinds)
        #expect(detection?.kind == .email)
        if case .composeMail(let address)? = detection?.action {
            #expect(address == "someone@example.com")
        } else {
            Issue.record("mail action expected")
        }
    }

    @Test
    func rejectsInvalidEmailShapes() {
        #expect(ClipboardAssistantDetector.isEmailAddress("not-an-email") == false)
        #expect(ClipboardAssistantDetector.isEmailAddress("a@b") == false)
        #expect(ClipboardAssistantDetector.isEmailAddress("@example.com") == false)
    }

    @Test
    func detectsPhoneNumbersWithNormalizedCopyAction() {
        let detection = ClipboardAssistantDetector.detect(text: "+86 138 0013 8000", enabledKinds: allKinds)
        #expect(detection?.kind == .phone)
        if case .copyText(let value)? = detection?.action {
            #expect(value == "+8613800138000")
        } else {
            Issue.record("normalized copy action expected")
        }
        if case .callPhone(let value)? = detection?.secondaryActions.first {
            #expect(value == "+8613800138000")
        } else {
            Issue.record("call action expected")
        }
    }

    @Test
    func phoneDetectionDoesNotSwallowShortMath() {
        // "10-3" is arithmetic, not a phone number.
        let detection = ClipboardAssistantDetector.detect(text: "10-3", enabledKinds: allKinds)
        #expect(detection?.kind == .math)
    }

    @Test
    func parsesHexColorsIncludingShortForm() {
        for text in ["#0166ef", "#168", "#0166EF"] {
            let detection = ClipboardAssistantDetector.parseColor(text)
            #expect(detection?.kind == .color, "expected \(text) to parse")
        }
        let detection = ClipboardAssistantDetector.parseColor("#0166ef")
        #expect(abs((detection?.colorComponents?.blue ?? 0) - (0xef / 255.0)) < 0.01)
        if case .copyText(let value)? = detection?.action {
            #expect(value == "#0166ef")
        } else {
            Issue.record("copy action expected")
        }
    }

    @Test
    func parsesRGBAndHSLFunctions() {
        let rgb = ClipboardAssistantDetector.parseColor("rgb(1, 102, 239)")
        #expect(rgb?.kind == .color)
        #expect(abs((rgb?.colorComponents?.green ?? 0) - (102 / 255.0)) < 0.01)

        let hsl = ClipboardAssistantDetector.parseColor("hsl(210, 100%, 50%)")
        #expect(hsl?.kind == .color)
        #expect(abs((hsl?.colorComponents?.red ?? 1)) < 0.02)

        #expect(ClipboardAssistantDetector.parseColor("rgb(999, 0, 0)") == nil)
        #expect(ClipboardAssistantDetector.parseColor("#12") == nil)
        #expect(ClipboardAssistantDetector.parseColor("plain text") == nil)
    }

    @Test
    func evaluatesArithmeticExpressions() {
        #expect(ClipboardAssistantDetector.evaluateArithmetic("99999*99999") == 9_999_800_001)
        #expect(ClipboardAssistantDetector.evaluateArithmetic("(1+2)*3") == 9)
        #expect(ClipboardAssistantDetector.evaluateArithmetic("10/4") == 2.5)
        #expect(ClipboardAssistantDetector.evaluateArithmetic("3 × 4 ÷ 2") == 6)
        #expect(ClipboardAssistantDetector.evaluateArithmetic("-5+2") == -3)
    }

    @Test
    func rejectsMalformedArithmeticWithoutCrashing() {
        #expect(ClipboardAssistantDetector.evaluateArithmetic("1++") == nil)
        #expect(ClipboardAssistantDetector.evaluateArithmetic("(") == nil)
        #expect(ClipboardAssistantDetector.evaluateArithmetic("(1+2") == nil)
        #expect(ClipboardAssistantDetector.evaluateArithmetic("abc+1") == nil)
        #expect(ClipboardAssistantDetector.evaluateArithmetic("10/0") == nil)
        #expect(ClipboardAssistantDetector.evaluateArithmetic("42") == nil)
        #expect(ClipboardAssistantDetector.evaluateArithmetic("") == nil)
    }

    @Test
    func formatsNumbersWithoutTrailingZeros() {
        #expect(ClipboardAssistantDetector.formatNumber(123456789) == "123456789")
        #expect(ClipboardAssistantDetector.formatNumber(2.5) == "2.5")
    }

    // MARK: - Date and time

    @Test
    func parsesISOStyleDates() {
        for text in ["2024-03-05", "2024/03/05", "2024年3月5日", "Mar 5, 2024"] {
            let parsed = ClipboardAssistantDetector.parseDateTime(text)
            #expect(parsed != nil, "expected \(text) to parse as a date")
        }
        let parsed = ClipboardAssistantDetector.parseDateTime("2024-03-05 14:30")
        #expect(parsed?.isDateOnly == false)
    }

    @Test
    func parsesTimeOfDayAsTimedEventOnToday() {
        let parsed = ClipboardAssistantDetector.parseDateTime("14:30")
        #expect(parsed?.isDateOnly == false)
        #expect(parsed != nil)
    }

    @Test
    func rejectsShortNumericTextAsDate() {
        // Short arithmetic must never become a calendar event.
        #expect(ClipboardAssistantDetector.parseDateTime("10-3") == nil)
        #expect(ClipboardAssistantDetector.parseDateTime("3.5") == nil)
        #expect(ClipboardAssistantDetector.parseDateTime("hello world") == nil)
        #expect(ClipboardAssistantDetector.parseDateTime("v1.2.3-beta") == nil)
    }

    @Test
    func dateTimeDetectionOffersCalendarAndCopyActions() {
        let detection = ClipboardAssistantDetector.detect(text: "2024-03-05", enabledKinds: allKinds)
        #expect(detection?.kind == .dateTime)
        #expect(detection?.actions.count == 2)
        if case .createCalendarEvent(_, let date, let isAllDay)? = detection?.action {
            #expect(isAllDay)
            let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
            #expect(components.year == 2024)
            #expect(components.month == 3)
            #expect(components.day == 5)
        } else {
            Issue.record("calendar action expected")
        }
        if case .copyText(let value)? = detection?.actions.last {
            #expect(value == "2024-03-05 00:00")
        } else {
            Issue.record("copy action expected")
        }
    }

    // MARK: - Chinese text

    @Test
    func detectsChineseTextWithTranslateAction() {
        let detection = ClipboardAssistantDetector.detect(text: "这是一段中文内容", enabledKinds: allKinds)
        #expect(detection?.kind == .chineseText)
        if case .translate(let text)? = detection?.action {
            #expect(text == "这是一段中文内容")
        } else {
            Issue.record("translate action expected")
        }
        if case .chineseCharacterCount(let count)? = detection?.detail {
            #expect(count == 8)
        } else {
            Issue.record("chinese character count detail expected")
        }
    }

    @Test
    func englishTextDoesNotBecomeChineseDetection() {
        let detection = ClipboardAssistantDetector.detect(text: "plain english words", enabledKinds: allKinds)
        #expect(detection?.kind == .text)
    }

    // MARK: - Code

    @Test
    func detectsMultiLineCodeSnippets() {
        let code = """
        func greet(name: String) -> String {
            return "Hello \\(name)"
        }
        """
        let detection = ClipboardAssistantDetector.detect(text: code, enabledKinds: allKinds)
        #expect(detection?.kind == .code)
        if case .codeLines(let lines)? = detection?.detail {
            #expect(lines == 3)
        } else {
            Issue.record("code line detail expected")
        }
        if case .saveText? = detection?.action {
            // Saved snippets keep the full source.
        } else {
            Issue.record("save action expected")
        }
    }

    @Test
    func singleLineImportIsCode() {
        let detection = ClipboardAssistantDetector.detect(text: "import Foundation", enabledKinds: allKinds)
        #expect(detection?.kind == .code)
    }

    @Test
    func ordinaryProseIsNotCode() {
        let prose = "This is just an ordinary sentence without any structure."
        let detection = ClipboardAssistantDetector.detect(text: prose, enabledKinds: allKinds)
        #expect(detection?.kind == .text)
    }

    @Test
    func detectsSnippetsWithoutStructuralPunctuation() {
        // Declarations, calls and imports carry no braces or semicolons, yet they are plainly code.
        for snippet in [
            "let count = 1\nlet total = count + 2",
            "print(\"hello\")",
            "const handler = buildHandler(config)",
            "x = compute(a, b)\ny = x * 2",
            "from pathlib import Path\np = Path.home()",
            ".card {\n  color: red;\n}",
            "SELECT name FROM users",
            "@State private var isOn = false",
            "viewModel.reload(force: true)",
            "{\"name\": \"zisla\", \"pinned\": true}",
            "<div class=\"row\">",
            "    total += price\n    count += 1",
        ] {
            let detection = ClipboardAssistantDetector.detect(text: snippet, enabledKinds: allKinds)
            #expect(detection?.kind == .code, "expected code for: \(snippet)")
        }
    }

    @Test
    func proseSharingKeywordsWithCodeStaysText() {
        for prose in [
            "Let me know: are we still meeting tomorrow?",
            "The report came from the finance team and needs a review",
            "We should print the invoice and file it away",
            "Send me the file: report.pdf when you get a chance",
        ] {
            let detection = ClipboardAssistantDetector.detect(text: prose, enabledKinds: allKinds)
            #expect(detection?.kind == .text, "expected text for: \(prose)")
        }

        let chinese = ClipboardAssistantDetector.detect(
            text: "从今天开始，我们要更认真地对待这件事情，不能再拖延了。",
            enabledKinds: allKinds
        )
        #expect(chinese?.kind == .chineseText)
    }

    @Test
    func chineseProgressTranscriptWithTechnicalFragmentsStaysText() {
        let prose = """
        进度 40%：按照项目的协作规则，我会先检查真实差异，再独立运行测试，不会直接照搬工具的结论。
        已在 8s 内运行 claude --model claude-opus-5 -p，并读取 /Users/example/project 下的文件。
        进度 42%：命令返回 403，后续由主线程继续；stream disconnected before completion: network error。
        已查看 1 张图像，也读取了文件并运行了命令。
        """

        let detection = ClipboardAssistantDetector.detect(text: prose, enabledKinds: allKinds)
        #expect(detection?.kind == .chineseText)
    }

    @Test
    func guessesUsefulFileExtensions() {
        #expect(ClipboardAssistantDetector.guessCodeFileExtension("#include <stdio.h>") == "cpp")
        #expect(ClipboardAssistantDetector.guessCodeFileExtension("def main():\n    pass") == "py")
        #expect(ClipboardAssistantDetector.guessCodeFileExtension("const x = () => 1;") == "js")
    }

    // MARK: - Plain text

    @Test
    func shortPlainTextSearchesAndTranslates() {
        let detection = ClipboardAssistantDetector.detect(text: "hello world", enabledKinds: allKinds)
        #expect(detection?.kind == .text)
        #expect(detection?.actions.count == 2)
        if case .search(let query)? = detection?.action {
            #expect(query == "hello world")
        } else {
            Issue.record("search action expected")
        }
        if case .translate? = detection?.actions.last {
            // Translate is offered as the secondary action.
        } else {
            Issue.record("translate secondary action expected")
        }
    }

    @Test
    func longPlainTextOffersSaveAction() {
        let longText = String(repeating: "word ", count: 20)
        let detection = ClipboardAssistantDetector.detect(text: longText, enabledKinds: allKinds)
        #expect(detection?.kind == .text)
        if case .saveText(let saved)? = detection?.action {
            #expect(saved == longText.trimmingCharacters(in: .whitespaces))
        } else {
            Issue.record("save action expected for content over \(ClipboardAssistantDefaults.saveableTextLength) characters")
        }
    }

    @Test
    func textDetailCarriesCharacterAndWordCounts() {
        let detection = ClipboardAssistantDetector.detect(text: "one two three", enabledKinds: allKinds)
        #expect(detection?.detail == .characterAndWordCount(characters: 13, words: 3))

        let preview = ClipboardAssistantDetector.previewText(String(repeating: "x", count: 200))
        #expect(preview.count == 121)
        #expect(preview.hasSuffix("…"))
    }

    @Test
    func disabledKindsAreSkippedInPriorityOrder() {
        let kinds: Set<ClipboardAssistantKind> = [.math, .text]
        let urlDetection = ClipboardAssistantDetector.detect(text: "https://example.com", enabledKinds: kinds)
        #expect(urlDetection?.kind == .text, "URL kind disabled → falls through to text")

        let mathDetection = ClipboardAssistantDetector.detect(text: "(1+2)*3", enabledKinds: kinds)
        #expect(mathDetection?.kind == .math)

        let noneDetection = ClipboardAssistantDetector.detect(text: "hello world", enabledKinds: [.email])
        #expect(noneDetection == nil)

        let chineseFallback = ClipboardAssistantDetector.detect(
            text: "这是中文",
            enabledKinds: [ClipboardAssistantKind.text]
        )
        #expect(chineseFallback?.kind == .text, "chinese kind disabled → falls through to plain text")
    }

    @Test
    func detectsFileReferenceContentSize() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let fileURL = temporaryDirectory.appendingPathComponent("zisla-assistant-\(UUID().uuidString).bin")
        try Data(repeating: 7, count: 2048).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try ClipboardHistoryContent.file(at: fileURL)
        let detection = ClipboardAssistantDetector.detect(content: content, enabledKinds: allKinds)
        #expect(detection?.kind == .file)
        #expect(detection?.title == fileURL.lastPathComponent)
        if case .fileSize(let bytes)? = detection?.detail {
            #expect(bytes == 2048)
        } else {
            Issue.record("file size detail expected")
        }
        #expect(detection?.secondaryActions == [.compress(fileURL.standardizedFileURL)])
    }

    @Test
    func imageDetectionReportsDimensionsOrReturnsNilForGarbage() {
        // 1×1 red PNG
        let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        guard let pngData = Data(base64Encoded: base64PNG) else {
            Issue.record("fixture decode failed")
            return
        }
        let detection = ClipboardAssistantDetector.detect(content: .image(pngData), enabledKinds: allKinds)
        #expect(detection?.kind == .image)
        #expect(detection?.title.contains("1 × 1") == true)
        if case .imageSize(let wide, let high, _)? = detection?.detail {
            #expect(wide == 1)
            #expect(high == 1)
        } else {
            Issue.record("image size detail expected")
        }

        let garbage = ClipboardAssistantDetector.detect(content: .image(Data([0x00, 0x01])), enabledKinds: allKinds)
        #expect(garbage == nil)
    }
}

struct ClipboardAssistantSearchEngineTests {
    @Test
    func buildsQueryURLsForEachEngine() throws {
        let google = try #require(ClipboardAssistantSearchEngine.google.queryURL(for: "swift ui"))
        #expect(google.absoluteString.hasPrefix("https://www.google.com/search?q="))

        let bing = try #require(ClipboardAssistantSearchEngine.bing.queryURL(for: "hello"))
        #expect(bing.host == "www.bing.com")

        let baidu = try #require(ClipboardAssistantSearchEngine.baidu.queryURL(for: "你好"))
        #expect(baidu.host == "www.baidu.com")
        #expect(baidu.query?.contains("wd=") == true)

        let duck = try #require(ClipboardAssistantSearchEngine.duckduckgo.queryURL(for: "duck"))
        #expect(duck.host == "duckduckgo.com")

        let sogou = try #require(ClipboardAssistantSearchEngine.sogou.queryURL(for: "hello"))
        #expect(sogou.host == "www.sogou.com")
        #expect(sogou.query?.contains("query=") == true)

        let quark = try #require(ClipboardAssistantSearchEngine.quark.queryURL(for: "hello"))
        #expect(quark.host == "quark.sm.cn")

        let so360 = try #require(ClipboardAssistantSearchEngine.so360.queryURL(for: "hello"))
        #expect(so360.host == "www.so.com")

        let brave = try #require(ClipboardAssistantSearchEngine.brave.queryURL(for: "hello"))
        #expect(brave.host == "search.brave.com")

        let yandex = try #require(ClipboardAssistantSearchEngine.yandex.queryURL(for: "hello"))
        #expect(yandex.host == "yandex.com")
        #expect(yandex.query?.contains("text=") == true)
    }

    @Test
    func encodesQueryParameters() throws {
        let url = try #require(ClipboardAssistantSearchEngine.google.queryURL(for: "a b&c=d"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try #require(components.queryItems)
        #expect(query.first(where: { $0.name == "q" })?.value == "a b&c=d")
    }

    @Test
    func buildsCustomQueryURLsAndRejectsNonWebURLs() throws {
        let templated = try #require(ClipboardAssistantSearchEngine.custom.queryURL(
            for: "a b&c=d",
            customURL: "https://search.example.com/search?term={query}"
        ))
        let templatedComponents = try #require(URLComponents(url: templated, resolvingAgainstBaseURL: false))
        #expect(templatedComponents.queryItems?.first(where: { $0.name == "term" })?.value == "a b&c=d")

        let appended = try #require(ClipboardAssistantSearchEngine.custom.queryURL(
            for: "zisla",
            customURL: "https://search.example.com/search?lang=zh"
        ))
        let appendedComponents = try #require(URLComponents(url: appended, resolvingAgainstBaseURL: false))
        #expect(appendedComponents.queryItems?.first(where: { $0.name == "lang" })?.value == "zh")
        #expect(appendedComponents.queryItems?.first(where: { $0.name == "q" })?.value == "zisla")

        #expect(ClipboardAssistantSearchEngine.custom.queryURL(
            for: "zisla",
            customURL: "file:///tmp/search"
        ) == nil)
    }

    @Test
    func buildsTranslateURLWithTargetLanguage() throws {
        let url = try #require(ClipboardAssistantTranslate.url(text: "你好", targetLanguageCode: "en"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        #expect(items.first(where: { $0.name == "tl" })?.value == "en")
        #expect(items.first(where: { $0.name == "sl" })?.value == "auto")

        // Chinese interface languages map onto Google's zh-CN code.
        let chinese = try #require(ClipboardAssistantTranslate.url(text: "hi", targetLanguageCode: "zh-CN"))
        #expect(chinese.absoluteString.contains("tl=zh-CN"))
    }

    @Test
    func choosesTranslationProviderByCountryCode() throws {
        #expect(ClipboardAssistantTranslate.provider(forCountryCode: "CN") == .baidu)
        #expect(ClipboardAssistantTranslate.provider(forCountryCode: " cn\n") == .baidu)
        #expect(ClipboardAssistantTranslate.provider(forCountryCode: "US") == .google)
        #expect(ClipboardAssistantTranslate.provider(forCountryCode: nil) == .google)

        let baidu = try #require(ClipboardAssistantTranslate.url(
            text: "hello & 你好",
            targetLanguageCode: "zh-CN",
            provider: .baidu
        ))
        let baiduComponents = try #require(URLComponents(url: baidu, resolvingAgainstBaseURL: false))
        let baiduItems = try #require(baiduComponents.queryItems)
        #expect(baidu.host == "fanyi.baidu.com")
        #expect(baiduItems.first(where: { $0.name == "query" })?.value == "hello & 你好")
        #expect(baiduItems.first(where: { $0.name == "lang" })?.value == "auto2zh")
        #expect(baiduComponents.fragment == "/")

        let traditionalChinese = try #require(ClipboardAssistantTranslate.url(
            text: "hello",
            targetLanguageCode: "zh-TW",
            provider: .baidu
        ))
        #expect(traditionalChinese.query?.contains("lang=auto2cht") == true)

        let japanese = try #require(ClipboardAssistantTranslate.url(
            text: "hello",
            targetLanguageCode: "ja",
            provider: .baidu
        ))
        #expect(japanese.query?.contains("lang=auto2jp") == true)
    }

    @Test
    func appLanguageMapsToTranslateTargets() {
        #expect(AppLanguage.simplifiedChinese.translateTargetCode == "zh-CN")
        #expect(AppLanguage.traditionalChinese.translateTargetCode == "zh-TW")
        #expect(AppLanguage.brazilianPortuguese.translateTargetCode == "pt-BR")
    }
}
