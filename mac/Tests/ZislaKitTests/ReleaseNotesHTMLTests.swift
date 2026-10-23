import Foundation
import Testing
import ZislaCore
import ZislaKit

struct ReleaseNotesHTMLTests {
    @Test
    func rendersReleaseNotesWithTheExistingMarkdownParser() {
        let html = ReleaseNotesHTML.document(
            markdown: "# Release\n\n## Changes\n\n- **Fixed** updates\n\n| Before | After |\n| --- | --- |\n| 1 | 2 |\n\n\u{0060}\u{0060}\u{0060}swift\nlet value = 1\n\u{0060}\u{0060}\u{0060}",
            language: .english
        )
        #expect(html.contains("<h1>Release</h1>"))
        #expect(html.contains("<h2>Changes</h2>"))
        #expect(html.contains("<li><strong>Fixed</strong> updates</li>"))
        #expect(html.contains("<table>"))
        #expect(html.contains("<pre><code>let value = 1</code></pre>"))
        #expect(html.contains("color-scheme: light dark"))
    }

    @Test
    func escapesUntrustedHTMLAndBlocksLocalResourcesAndScripts() {
        let html = ReleaseNotesHTML.document(
            markdown: "<script>alert('unsafe')</script>\n\n![local](/private/release-notes-image.png)\n\n[link](javascript:alert)",
            language: .english
        )
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("img-src https: data:"))
        #expect(!html.contains("img-src file:"))
        #expect(!html.contains("base-uri https:"))
    }

    @Test(arguments: AppLanguage.allCases)
    func respectsTheInterfaceLanguageAndTextDirection(language: AppLanguage) {
        let html = ReleaseNotesHTML.document(markdown: "Notes", language: language)
        #expect(html.contains("lang=\"\(language.rawValue)\""))
        #expect(html.contains("dir=\"\(language.isRightToLeft ? "rtl" : "ltr")\""))
        #expect(html.contains("padding-inline-start"))
        #expect(html.contains("text-align: start"))
    }

    @Test
    func emptyInputStillProducesASafeReadableDocument() {
        let html = ReleaseNotesHTML.document(markdown: "", language: .english)
        #expect(html.contains("<body><article><div><br></div></article></body>"))
        #expect(html.contains("Content-Security-Policy"))
    }
}
