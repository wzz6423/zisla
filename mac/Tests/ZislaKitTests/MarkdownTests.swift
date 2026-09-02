import Foundation
import ImageIO
import CoreGraphics
import Testing
@testable import ZislaKit

struct MarkdownParserTests {
    @Test
    func parsesEmptyInputAsEmpty() {
        #expect(MarkdownParser.parse("").isEmpty)
        #expect(MarkdownParser.parse("   \n\n  ").isEmpty)
    }

    @Test
    func parsesHeadings() {
        let blocks = MarkdownParser.parse("# 大标题\n## 中标题\n### 小标题")
        #expect(blocks.count == 3)
        #expect(blocks[0] == .heading(level: 1, text: "大标题"))
        #expect(blocks[1] == .heading(level: 2, text: "中标题"))
        #expect(blocks[2] == .heading(level: 3, text: "小标题"))
    }

    @Test
    func parsesBulletList() {
        let blocks = MarkdownParser.parse("- 苹果\n- 香蕉\n- 橙子")
        #expect(blocks == [.bulletList(items: ["苹果", "香蕉", "橙子"])])
    }

    @Test
    func parsesOrderedList() {
        let blocks = MarkdownParser.parse("1. 第一\n2. 第二\n3. 第三")
        #expect(blocks == [.orderedList(items: ["第一", "第二", "第三"])])
    }

    @Test
    func parsesTaskListCheckboxes() {
        let blocks = MarkdownParser.parse("- [ ] 未完成\n- [x] 已完成")
        #expect(blocks == [.bulletList(items: ["☐ 未完成", "☑ 已完成"])])
    }

    @Test
    func parsesBlockquote() {
        let blocks = MarkdownParser.parse("> 引用内容\n> 第二段引用")
        #expect(blocks == [.blockquote(text: "引用内容 第二段引用")])
    }

    @Test
    func parsesFencedCodeBlock() {
        let blocks = MarkdownParser.parse("```\nlet x = 1\nprint(x)\n```")
        #expect(blocks == [.codeBlock(language: nil, content: "let x = 1\nprint(x)")])
    }

    @Test
    func parsesFencedCodeBlockWithLanguage() {
        let blocks = MarkdownParser.parse("```swift\nlet x = 1\n```")
        #expect(blocks == [.codeBlock(language: "swift", content: "let x = 1")])
    }

    @Test
    func preservesLongFenceUntilItsMatchingCloser() {
        let source = "````text\n```\nkeep\n````"
        #expect(MarkdownParser.parse(source) == [.codeBlock(language: "text", content: "```\nkeep")])
    }

    @Test
    func parsesUnclosedCodeBlockToEOF() {
        let blocks = MarkdownParser.parse("```\n未闭合代码")
        #expect(blocks == [.codeBlock(language: nil, content: "未闭合代码")])
    }

    @Test
    func parsesHorizontalRule() {
        for rule in ["---", "***", "___", "- - -"] {
            #expect(MarkdownParser.parse(rule) == [.horizontalRule], "Should recognize horizontal rule: \(rule)")
        }
    }

    @Test
    func parsesParagraph() {
        let blocks = MarkdownParser.parse("这是一段普通文本。")
        #expect(blocks == [.paragraph(text: "这是一段普通文本。")])
    }

    @Test
    func mergesMultiLineParagraph() {
        let blocks = MarkdownParser.parse("第一行\n第二行\n第三行")
        #expect(blocks == [.paragraph(text: "第一行 第二行 第三行")])
    }

    @Test
    func separatesMixedBlocks() {
        let blocks = MarkdownParser.parse("# 标题\n正文一\n正文二\n\n- 列表项")
        #expect(blocks.count == 3)
        #expect(blocks[0] == .heading(level: 1, text: "标题"))
        #expect(blocks[1] == .paragraph(text: "正文一 正文二"))
        #expect(blocks[2] == .bulletList(items: ["列表项"]))
    }

    @Test
    func parsesStandaloneImage() {
        let blocks = MarkdownParser.parse("![照片](/path/to/image.png)")
        #expect(blocks.count == 1)
        #expect(blocks[0] == .image(url: "/path/to/image.png", alt: "照片"))
    }

    @Test
    func parsesStandaloneImageWithEmptyAlt() {
        let blocks = MarkdownParser.parse("![](/path/to/image.png)")
        #expect(blocks.count == 1)
        #expect(blocks[0] == .image(url: "/path/to/image.png", alt: ""))
    }

    @Test
    func parsesStandaloneImageWithTildePath() {
        let blocks = MarkdownParser.parse("![截图](~/Desktop/screenshot.png)")
        #expect(blocks.count == 1)
        #expect(blocks[0] == .image(url: "~/Desktop/screenshot.png", alt: "截图"))
    }

    @Test
    func doesNotParseInlineImageAsStandaloneBlock() {
        // Image markup with surrounding text must not be parsed as a standalone image block
        let blocks = MarkdownParser.parse("看这张 ![图](/x.png) 怎么样")
        #expect(blocks.count == 1)
        if case .paragraph = blocks[0] {
            // Correct: parsed as a paragraph
        } else {
            #expect(Bool(false), "Should be parsed as paragraph, not standalone image block")
        }
    }

    @Test
    func imageMarkerWithoutURLAtLineEndDoesNotCrash() {
        // When `]` ends the line, index(after:) is endIndex; regression coverage requires paragraph handling without an out-of-bounds crash.
        #expect(MarkdownParser.parse("![截图]") == [.paragraph(text: "![截图]")])
        #expect(MarkdownParser.parse("![alt]") == [.paragraph(text: "![alt]")])
        #expect(MarkdownParser.parse("正文\n![image]") == [.paragraph(text: "正文 ![image]")])
    }

    @Test
    func parsesTableImmediatelyAfterParagraph() {
        // When a table immediately follows a paragraph without a blank line, its header must not be consumed and its body must not degrade into bare text.
        let blocks = MarkdownParser.parse("对比如下：\n| A | B |\n| --- | --- |\n| 1 | 2 |")
        #expect(blocks == [
            .paragraph(text: "对比如下："),
            .table(header: ["A", "B"], rows: [["1", "2"]]),
        ])
    }

    @Test
    func requiresThreeHyphensInEveryTableDelimiterCell() {
        let source = "| A | B |\n| - | - |\n| 1 | 2 |"
        #expect(MarkdownParser.parse(source) == [.paragraph(text: "| A | B | | - | - | | 1 | 2 |")])
    }

    @Test
    func keepsMultipleImageMarkersInParagraphs() {
        let source = "![one](/one.png) ![one](/one.png)"
        #expect(MarkdownParser.parse(source) == [.paragraph(text: source)])
    }

    // MARK: - Leading whitespace preservation

    @Test
    func preservesLeadingSpacesInParagraph() {
        let blocks = MarkdownParser.parse("    缩进四空格")
        #expect(blocks == [.paragraph(text: "%%ZISLA_INDENT:4%%缩进四空格")])
    }

    @Test
    func preservesLeadingTabsInParagraph() {
        let blocks = MarkdownParser.parse("\t\t制表符缩进")
        #expect(blocks == [.paragraph(text: "%%ZISLA_INDENT:2%%制表符缩进")])
    }

    @Test
    func preservesMixedLeadingWhitespace() {
        let blocks = MarkdownParser.parse(" \t 混合缩进")
        #expect(blocks == [.paragraph(text: "%%ZISLA_INDENT:3%%混合缩进")])
    }

    @Test
    func preservesIndentationInMultiLineParagraph() {
        let blocks = MarkdownParser.parse("第一行\n  第二行缩进")
        #expect(blocks == [.paragraph(text: "第一行 %%ZISLA_INDENT:2%%第二行缩进")])
    }

    @Test
    func doesNotMarkUnindentedParagraph() {
        let blocks = MarkdownParser.parse("无缩进文本")
        #expect(blocks == [.paragraph(text: "无缩进文本")])
    }
}

struct MarkdownRendererTests {
    @Test
    func emptyInputProducesEmptyAttributedString() {
        let attr = MarkdownRenderer.attributedString(from: "")
        #expect(attr.characters.isEmpty)
    }

    @Test
    func nonEmptyInputProducesNonEmptyOutput() {
        let attr = MarkdownRenderer.attributedString(from: "# 标题\n正文 **粗体**")
        #expect(!attr.characters.isEmpty)
        #expect(String(attr.characters).contains("标题"))
        #expect(String(attr.characters).contains("粗体"))
    }

    @Test
    func renderingDoesNotCrashOnComplexInput() {
        let source = """
        # 标题
        ## 副标题
        段落 **粗体** *斜体* `代码` ~~删除~~ [链接](https://x.com)

        - 项目一
        - 项目二

        1. 第一
        2. 第二

        > 引用块

        ```swift
        let x = 1
        ```

        ---
        """
        let attr = MarkdownRenderer.attributedString(from: source)
        #expect(!attr.characters.isEmpty)
    }

    @Test
    func escapesInlineCodeExactlyOnce() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "`<tag>&`")
        #expect(html.contains("<code>&lt;tag&gt;&amp;</code>"))
        #expect(!html.contains("&amp;lt;"))
    }

    @Test
    func preservesLiteralTextThatMatchesHistoricalCodePlaceholder() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "%%CODE0%% and `value`")
        #expect(html.contains("%%CODE0%% and <code>value</code>"))
    }

    // MARK: - Leading whitespace rendering

    @Test
    func rendersLeadingSpacesAsNonBreakingSpaces() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "    缩进内容")
        #expect(html.contains("&nbsp;&nbsp;&nbsp;&nbsp;缩进内容"))
        #expect(!html.contains("%%ZISLA_INDENT"))
    }

    @Test
    func rendersLeadingTabsAsNonBreakingSpaces() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "\t\t制表符内容")
        #expect(html.contains("&nbsp;&nbsp;制表符内容"))
        #expect(!html.contains("%%ZISLA_INDENT"))
    }

    @Test
    func rendersIndentedMultiLineParagraph() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "标题行\n  缩进行")
        #expect(html.contains("标题行 &nbsp;&nbsp;缩进行"))
    }

    @Test
    func doesNotAddSpacesToUnindentedContent() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "普通段落")
        #expect(html.contains("<p>普通段落</p>"))
        #expect(!html.contains("&nbsp;"))
    }

    @Test
    func preservesIndentationWithInlineFormatting() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "  **粗体**缩进")
        #expect(html.contains("&nbsp;&nbsp;<strong>粗体</strong>缩进"))
    }
}

@MainActor
struct NotesAppBridgeTests {
    @Test
    func parsesPasswordProtectionFromSummary() throws {
        let json = #"[{"id":"locked","title":"私密","modified":0,"passwordProtected":true}]"#
        let summary = try #require(NotesAppBridge.parseSummaries(json)?.first)

        #expect(summary.isPasswordProtected)
    }

    @Test
    func extractsVisibleTagsWithoutDuplicates() {
        #expect(
            NotesAppBridge.tags(in: "#项目 进展\n#Release-1\n再次 #项目\n普通#文本")
                == ["项目", "Release-1"]
        )
    }

    @Test
    func migratesLegacyMarkdownToEditableHTML() {
        let body = MarkdownHTMLRenderer.bodyHTML(from: "# 随记\n\n- 第一项\n- 第二项")

        #expect(body.contains("<h1>随记</h1>"))
        #expect(body.contains("<ul>"))
        #expect(body.contains("<li>第一项</li>"))
    }

    @Test
    func storesMarkdownAsPlainDivLinesNotPre() {
        let markdown = "# 随记\n\n正文 & 代码 <tag>"
        let body = NotesAppBridge.bodyHTML(for: markdown)

        #expect(!body.contains("<pre>"))
        #expect(body.contains("<div># 随记</div>"))
        #expect(body.contains("<div><br></div>"))
        #expect(body.contains("<div>正文 &amp; 代码 &lt;tag&gt;</div>"))
    }

    // MARK: - Leading whitespace round-trip

    @Test
    func storesLeadingSpacesAsNonBreakingSpaces() {
        let body = NotesAppBridge.bodyHTML(for: "    缩进四空格")

        #expect(body.contains("<div>&nbsp;&nbsp;&nbsp;&nbsp;缩进四空格</div>"))
    }

    @Test
    func storesLeadingTabsAsNonBreakingSpaces() {
        let body = NotesAppBridge.bodyHTML(for: "\t\t制表符缩进")

        #expect(body.contains("<div>&nbsp;&nbsp;制表符缩进</div>"))
    }

    @Test
    func storesIndentedLinesWithEscapedContent() {
        let body = NotesAppBridge.bodyHTML(for: "  正文 & <tag>")

        #expect(body.contains("<div>&nbsp;&nbsp;正文 &amp; &lt;tag&gt;</div>"))
    }

    @Test
    func keepsUnindentedLinesWithoutExtraSpaces() {
        let body = NotesAppBridge.bodyHTML(for: "无缩进")

        #expect(body.contains("<div>无缩进</div>"))
        #expect(!body.contains("&nbsp;无缩进"))
    }

    @Test
    func keepsLegacyPreMarkdownEditable() {
        let markdown = "# 随记\n正文"
        let content = NotesAppBridge.NoteContent(
            plainText: markdown,
            bodyHTML: "<pre># 随记\n正文</pre>"
        )

        #expect(!content.usesNativeHTML)
        #expect(content.plainText == markdown)
    }

    @Test
    func preservesPlainDivParagraphsAsNativeHTML() {
        let markdown = "# 随记\n正文"
        let content = NotesAppBridge.NoteContent(
            plainText: markdown,
            bodyHTML: NotesAppBridge.bodyHTML(for: markdown)
        )

        #expect(content.usesNativeHTML)
        #expect(content.plainText == markdown)
    }

    @Test
    func preservesNativeTableAndImageHTML() {
        let body = #"<div><table><tr><th>项目</th></tr><tr><td>随记</td></tr></table><img src='file:///tmp/note.png'></div>"#
        let content = NotesAppBridge.NoteContent(plainText: "项目\n随记", bodyHTML: body)
        let html = MarkdownHTMLRenderer.html(fromNotesHTML: content.bodyHTML)

        #expect(content.usesNativeHTML)
        #expect(html.contains("<table>"))
        #expect(html.contains("<img src='file:///tmp/note.png'>"))
    }

    @Test
    func preservesPlainNativeNoteHTML() {
        let content = NotesAppBridge.NoteContent(
            plainText: "普通备忘录",
            bodyHTML: "<div>普通备忘录</div>"
        )

        #expect(content.usesNativeHTML)
    }

    // MARK: - Recently Deleted filtering regression

    @Test
    func filtersKnownRecentlyDeletedFolderNames() {
        // Every known-language "Recently Deleted" folder name must be excluded
        for name in NotesAppBridge.recentlyDeletedFolderNames {
            #expect(
                NotesAppBridge.isInRecentlyDeletedFolder(name),
                "Expected '\(name)' to be identified as Recently Deleted folder"
            )
        }
    }

    @Test
    func excludesRecentlyDeletedNotesFromListedSummaries() {
        let json = #"""
        [
          {"id":"active","title":"保留","modified":1000,"container":"备忘录"},
          {"id":"deleted","title":"已删除","modified":2000,"container":"最近删除"},
          {"id":"unknown-container","title":"保守保留","modified":3000}
        ]
        """#

        let summaries = NotesAppBridge.parseSummaries(json)

        #expect(summaries?.map(\.id) == ["active", "unknown-container"])
    }

    @Test
    func doesNotFilterRegularOrHistoricalFolderNames() {
        // Regular and historical/compat folder names must not be filtered by mistake
        let safe: [String] = [
            "Notes",       // default Notes folder (English)
            "备忘录",        // default Notes folder (Chinese)
            "随记",
            "工作",
            "Reading",
            "Todo",
            "Journal",
            "Zisla",       // historical compatibility
            "随记笔记",
            "Zisla",
            "",            // empty string (no container)
            "Recently",    // approximate but incomplete match
            "Deleted",
            "最近",
            "删除",
        ]
        for name in safe {
            #expect(
                !NotesAppBridge.isInRecentlyDeletedFolder(name),
                "Expected '\(name)' NOT to be identified as Recently Deleted folder"
            )
        }
    }

    @Test
    func filterIsCaseSensitiveAndExact() {
        // System folder names have fixed casing; leading/trailing spaces or case changes must not match
        #expect(!NotesAppBridge.isInRecentlyDeletedFolder("recently deleted"))
        #expect(!NotesAppBridge.isInRecentlyDeletedFolder("RECENTLY DELETED"))
        #expect(!NotesAppBridge.isInRecentlyDeletedFolder("最近删除 "))   // trailing space
        #expect(!NotesAppBridge.isInRecentlyDeletedFolder(" 最近删除"))   // leading space
    }
}

@Suite struct MarkdownImageInlinerTests {
    /// Build a minimal valid JPEG (1x1 red pixel) to simulate a local image file in Notes.
    private func makeTestJPEG(red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 0) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let cgImage = ctx.makeImage()!
        let mutable = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            mutable,
            "public.jpeg" as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return mutable as Data
    }

    /// Write to a temporary directory (cleaned up at test end) and return the file path.
    private func writeTempImage(extension ext: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-md-img-\(UUID().uuidString).\(ext)")
        try makeTestJPEG().write(to: url)
        // Cleanup is handled with defer inside the test body
        return url.path
    }

    @Test
    func inlinesLocalAbsolutePathImageIntoDataURL() throws {
        MarkdownImageInliner.clearCache()
        let path = try writeTempImage(extension: "jpg")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let html = #"<p><img src="\#(path)" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)

        #expect(!result.contains(path), "Original path should be replaced")
        #expect(result.contains("data:image/jpeg;base64,"), "Should inline as JPEG data URL")
        #expect(result.contains(#"alt="x""#), "Other attributes should be preserved")
    }

    @Test
    func inlinesFileURLStyleImage() throws {
        MarkdownImageInliner.clearCache()
        let path = try writeTempImage(extension: "jpg")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let fileURL = "file://\(path)"

        let html = #"<p><img src="\#(fileURL)" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)

        #expect(!result.contains(fileURL), "file:// format should also be replaced")
        #expect(result.contains("data:image/jpeg;base64,"))
    }

    @Test
    func inlinesSingleQuotedLocalImage() throws {
        MarkdownImageInliner.clearCache()
        let path = try writeTempImage(extension: "jpg")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let html = #"<img src='\#(path)' alt='x'>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)

        #expect(!result.contains(path))
        #expect(result.contains("data:image/jpeg;base64,"))
    }

    @Test
    func preservesHTTPSImageSrc() {
        MarkdownImageInliner.clearCache()
        let html = #"<p><img src="https://example.com/foo.png" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)
        #expect(result == html, "Network URLs should not be rewritten")
    }

    @Test
    func preservesHTTPImageSrc() {
        MarkdownImageInliner.clearCache()
        let html = #"<p><img src="http://example.com/foo.png" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)
        #expect(result == html)
    }

    @Test
    func preservesAlreadyInlinedDataURL() {
        MarkdownImageInliner.clearCache()
        let html = #"<p><img src="data:image/png;base64,AAAA" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)
        #expect(result == html, "Already inlined data URLs should not be processed again")
    }

    @Test
    func preservesMissingLocalFileSrc() {
        MarkdownImageInliner.clearCache()
        let missing = "/tmp/zisla-definitely-not-exist-\(UUID().uuidString).jpg"
        let html = #"<p><img src="\#(missing)" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)
        #expect(result == html, "Preserve original src on read failure (no regression from current behavior)")
    }

    @Test
    func preservesRelativePathWithoutScheme() {
        MarkdownImageInliner.clearCache()
        // Relative paths without a scheme or absolute path are ignored and left as-is.
        let html = #"<p><img src="foo/bar.png" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)
        #expect(result == html)
    }

    @Test
    func leavesHTMLWithoutImgUntouched() {
        let html = "<p>纯文本段落</p><ul><li>列表</li></ul>"
        let result = MarkdownImageInliner.inlineLocalImages(in: html)
        #expect(result == html)
    }

    @Test
    func processesMultipleImagesIndependently() throws {
        MarkdownImageInliner.clearCache()
        let p1 = try writeTempImage(extension: "jpg")
        let p2 = try writeTempImage(extension: "jpg")
        defer {
            try? FileManager.default.removeItem(atPath: p1)
            try? FileManager.default.removeItem(atPath: p2)
        }

        let html = #"""
        <p><img src="\#(p1)" alt="a"></p>
        <p><img src="https://example.com/x.png" alt="b"></p>
        <p><img src="\#(p2)" alt="c"></p>
        """#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)

        #expect(!result.contains(p1))
        #expect(!result.contains(p2))
        #expect(result.contains("https://example.com/x.png"), "Network URLs should be preserved")
        // At least two data URLs should appear (the first two local images)
        #expect(result.components(separatedBy: "data:image/jpeg;base64,").count - 1 == 2)
    }

    @Test
    func inlinesImageWithAmpersandInPath() throws {
        MarkdownImageInliner.clearCache()
        // Simulate the MarkdownHTMLRenderer pipeline: escapeHTML turns & into &amp;,
        // attributeEscape keeps &amp;, and the inliner must unescape to read the file correctly.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-a&b-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.jpg").path
        try makeTestJPEG().write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: dir.path) }

        let html = #"<p><img src="\#(path)" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)

        #expect(!result.contains(path), "Paths with & should also be replaced")
        #expect(result.contains("data:image/jpeg;base64,"))
    }

    @Test
    func fullPipelineInlinesStandaloneImage() throws {
        MarkdownImageInliner.clearCache()
        let path = try writeTempImage(extension: "jpg")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let markdown = "![测试图片](\(path))"
        let html = MarkdownHTMLRenderer.html(from: markdown)

        #expect(html.contains("data:image/jpeg;base64,"), "Full pipeline should inline standalone image as data URL")
        #expect(!html.contains(path), "Original path should not remain in HTML")
    }

    @Test
    func refreshesCachedImageWhenTheLocalFileChanges() throws {
        MarkdownImageInliner.clearCache()
        let path = try writeTempImage(extension: "jpg")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let html = #"<img src="\#(path)" alt="x">"#
        let first = MarkdownImageInliner.inlineLocalImages(in: html)
        try makeTestJPEG(red: 0, blue: 1).write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 1)],
            ofItemAtPath: path
        )
        let second = MarkdownImageInliner.inlineLocalImages(in: html)

        #expect(first != second)
    }
}
