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
    func parsesUnclosedCodeBlockToEOF() {
        let blocks = MarkdownParser.parse("```\n未闭合代码")
        #expect(blocks == [.codeBlock(language: nil, content: "未闭合代码")])
    }

    @Test
    func parsesHorizontalRule() {
        for rule in ["---", "***", "___", "- - -"] {
            #expect(MarkdownParser.parse(rule) == [.horizontalRule], "应识别分隔线: \(rule)")
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
        // 图片标记前后有其它文本时，不应识别为独立图片块
        let blocks = MarkdownParser.parse("看这张 ![图](/x.png) 怎么样")
        #expect(blocks.count == 1)
        if case .paragraph = blocks[0] {
            // 正确：识别为段落
        } else {
            #expect(Bool(false), "应解析为段落，而非独立图片块")
        }
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
}

@MainActor
struct NotesAppBridgeTests {
    @Test
    func storesMarkdownAsPlainDivLinesNotPre() {
        let markdown = "# 随记\n\n正文 & 代码 <tag>"
        let body = NotesAppBridge.bodyHTML(for: markdown)

        #expect(!body.contains("<pre>"))
        #expect(body.contains("<div># 随记</div>"))
        #expect(body.contains("<div><br></div>"))
        #expect(body.contains("<div>正文 &amp; 代码 &lt;tag&gt;</div>"))
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
    func keepsPlainDivMarkdownEditable() {
        let markdown = "# 随记\n正文"
        let content = NotesAppBridge.NoteContent(
            plainText: markdown,
            bodyHTML: NotesAppBridge.bodyHTML(for: markdown)
        )

        #expect(!content.usesNativeHTML)
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
    func keepsPlainNativeNoteEditable() {
        let content = NotesAppBridge.NoteContent(
            plainText: "普通备忘录",
            bodyHTML: "<div>普通备忘录</div>"
        )

        #expect(!content.usesNativeHTML)
    }

    // MARK: - 最近删除过滤回归

    @Test
    func filtersKnownRecentlyDeletedFolderNames() {
        // 所有已知语言的「最近删除」文件夹名都应被排除
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
        // 普通文件夹和历史/兼容文件夹均不应被误过滤
        let safe: [String] = [
            "Notes",       // 默认笔记文件夹（英文）
            "备忘录",        // 默认笔记文件夹（中文）
            "随记",
            "工作",
            "Reading",
            "Todo",
            "Journal",
            "Zisla",       // 历史兼容
            "随记笔记",
            "Zisla",
            "",            // 空字符串（无容器时）
            "Recently",    // 近似但不完全匹配
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
        // 系统文件夹名大小写固定；前后空格、大小写变化均不应命中
        #expect(!NotesAppBridge.isInRecentlyDeletedFolder("recently deleted"))
        #expect(!NotesAppBridge.isInRecentlyDeletedFolder("RECENTLY DELETED"))
        #expect(!NotesAppBridge.isInRecentlyDeletedFolder("最近删除 "))   // 末尾空格
        #expect(!NotesAppBridge.isInRecentlyDeletedFolder(" 最近删除"))   // 前置空格
    }
}

@Suite struct MarkdownImageInlinerTests {
    /// 生成一个最小的有效 JPEG（1x1 红像素），用于模拟笔记里的本地图片文件。
    private func makeTestJPEG() -> Data {
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
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
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

    /// 写到临时目录并在测试结束清理，返回文件路径。
    private func writeTempImage(extension ext: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-md-img-\(UUID().uuidString).\(ext)")
        try makeTestJPEG().write(to: url)
        // 清理在测试体内用 defer 处理
        return url.path
    }

    @Test
    func inlinesLocalAbsolutePathImageIntoDataURL() throws {
        MarkdownImageInliner.clearCache()
        let path = try writeTempImage(extension: "jpg")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let html = #"<p><img src="\#(path)" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)

        #expect(!result.contains(path), "原路径应被替换掉")
        #expect(result.contains("data:image/jpeg;base64,"), "应内联为 JPEG data URL")
        #expect(result.contains(#"alt="x""#), "其它属性应保留")
    }

    @Test
    func inlinesFileURLStyleImage() throws {
        MarkdownImageInliner.clearCache()
        let path = try writeTempImage(extension: "jpg")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let fileURL = "file://\(path)"

        let html = #"<p><img src="\#(fileURL)" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)

        #expect(!result.contains(fileURL), "file:// 形式也应被替换")
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
        #expect(result == html, "网络 URL 不应被改写")
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
        #expect(result == html, "已经内联的 data URL 不应再处理")
    }

    @Test
    func preservesMissingLocalFileSrc() {
        MarkdownImageInliner.clearCache()
        let missing = "/tmp/zisla-definitely-not-exist-\(UUID().uuidString).jpg"
        let html = #"<p><img src="\#(missing)" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)
        #expect(result == html, "读取失败时保留原 src（与现状一致，无回归）")
    }

    @Test
    func preservesRelativePathWithoutScheme() {
        MarkdownImageInliner.clearCache()
        // 没有 scheme、不是绝对路径的相对路径会被忽略，保留原样。
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
        #expect(result.contains("https://example.com/x.png"), "网络 URL 应保留")
        // 至少出现两次 data URL（前两张本地图）
        #expect(result.components(separatedBy: "data:image/jpeg;base64,").count - 1 == 2)
    }

    @Test
    func inlinesImageWithAmpersandInPath() throws {
        MarkdownImageInliner.clearCache()
        // 模拟 MarkdownHTMLRenderer 管线：escapeHTML 把 & 转为 &amp;，
        // attributeEscape 保持 &amp;，inliner 需还原才能正确读文件。
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-a&b-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.jpg").path
        try makeTestJPEG().write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: dir.path) }

        let html = #"<p><img src="\#(path)" alt="x"></p>"#
        let result = MarkdownImageInliner.inlineLocalImages(in: html)

        #expect(!result.contains(path), "含 & 的路径也应被替换")
        #expect(result.contains("data:image/jpeg;base64,"))
    }

    @Test
    func fullPipelineInlinesStandaloneImage() throws {
        MarkdownImageInliner.clearCache()
        let path = try writeTempImage(extension: "jpg")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let markdown = "![测试图片](\(path))"
        let html = MarkdownHTMLRenderer.html(from: markdown)

        #expect(html.contains("data:image/jpeg;base64,"), "完整管线应把独立图片行内联为 data URL")
        #expect(!html.contains(path), "原始路径不应残留在 HTML 中")
    }
}
