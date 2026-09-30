import Foundation
import Testing
@testable import ZislaKit

struct MailHTMLBodyTests {
    @Test
    func preservesTheOriginalDocumentStylesTablesAndLinks() {
        let html = """
        <!doctype html><html><head><style>.button { background: #218739; }</style></head>
        <body><h1>Workflow run</h1><table><tr><td>Failed</td></tr></table>
        <a class="button" href="https://example.com/run">View workflow run</a></body></html>
        """
        #expect(MailHTMLBody.html(from: "Content-Type: text/html; charset=utf-8\n\n" + html) == html)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func selectsHTMLFromNestedMultipartAndUnfoldsHeaders(newline: String) {
        let source = """
        Content-Type: multipart/mixed; boundary="outer"

        Preamble
        --outer
        Content-Type: text/html
        Content-Disposition: attachment; filename="attachment.html"

        <p>Attachment must not replace the body</p>
        --outer
        Content-Type: multipart/alternative;
        \tboundary="inner;quoted"

        --inner;quoted
        Content-Type: text/plain

        Plain preview
        --inner;quoted
        content-type: TEXT/HTML; CHARSET="UTF-8"
        Content-Transfer-Encoding: quoted-printable

        <p style=3D"color: red">=E4=BD=A0=E5=A5=BD=\n world</p>
        --inner;quoted--
        --outer--
        Epilogue
        """.replacingOccurrences(of: "\n", with: newline)

        #expect(MailHTMLBody.html(from: source) == "<p style=\"color: red\">你好 world</p>")
    }

    @Test
    func decodesBase64UsingTheDeclaredCharacterSet() {
        let source = """
        Content-Type: text/html; charset=iso-8859-1
        Content-Transfer-Encoding: base64

        PHA+Y2Fm6Twv
        cD4=
        """
        #expect(MailHTMLBody.html(from: source) == "<p>café</p>")
    }

    @Test(arguments: ["", "7bit", "8bit", "binary"])
    func decodesUnencodedUTF8BytesFromMailSource(transfer: String) throws {
        let html = "<h1>Hi</h1><p>您好，系统发现您的账号有异常登录。café 🪷</p>"
        let body = try #require(String(data: Data(html.utf8), encoding: .isoLatin1))
        let transferHeader = transfer.isEmpty ? "" : "Content-Transfer-Encoding: \(transfer)\n"
        let source = "Content-Type: text/html; charset=utf-8\n" + transferHeader + "\n" + body

        #expect(MailHTMLBody.html(from: source) == html)
    }

    @Test(arguments: [
        ("gb18030", Data([0xD6, 0xD0, 0xCE, 0xC4]), "中文"),
        ("windows-1252", Data([0x80]), "€"),
        ("iso-8859-1", Data([0x63, 0x61, 0x66, 0xE9]), "café"),
    ])
    func decodesUnencodedBytesUsingTheDeclaredCharacterSet(charset: String, data: Data, text: String) throws {
        let body = try #require(String(data: data, encoding: .isoLatin1))
        let source = "Content-Type: text/html; charset=\(charset)\nContent-Transfer-Encoding: 8bit\n\n<p>\(body)</p>"

        #expect(MailHTMLBody.html(from: source) == "<p>\(text)</p>")
    }

    @Test(arguments: ["", "7bit", "8bit", "binary"], [
        "<p>您好，café 🪷</p>",
        "<p>café naïve</p>",
        "<p>Plain ASCII</p>",
    ])
    func preservesAlreadyDecodedUnencodedHTML(transfer: String, html: String) {
        let transferHeader = transfer.isEmpty ? "" : "Content-Transfer-Encoding: \(transfer)\n"
        let source = "Content-Type: text/html; charset=utf-8\n" + transferHeader + "\n" + html

        #expect(MailHTMLBody.html(from: source) == html)
    }

    @Test
    func preservesUnencodedHTMLWithAnUnknownCharacterSet() {
        let html = "<p>café</p>"
        let source = "Content-Type: text/html; charset=unknown-charset\nContent-Transfer-Encoding: 8bit\n\n" + html

        #expect(MailHTMLBody.html(from: source) == html)
    }

    @Test
    func roundTripsUnencodedUnicodeWithABoundedDeterministicCorpus() throws {
        let characters = Array("Aé€您好한국語العربية🪷 \t")
        var seed: UInt64 = 0xC0DE
        for length in 0..<64 {
            var text = ""
            for _ in 0..<length {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                text.append(characters[Int(seed % UInt64(characters.count))])
            }
            let html = "<p>\(text)</p>"
            let body = try #require(String(data: Data(html.utf8), encoding: .isoLatin1))
            let source = "Content-Type: text/html\nContent-Transfer-Encoding: 8bit\n\n" + body

            #expect(MailHTMLBody.html(from: source) == html)
        }
    }

    @Test
    func resolvesRelatedImagesInAttributesAndCSSWithoutReadingFiles() {
        let source = """
        Content-Type: multipart/related; boundary=related

        --related
        Content-Type: text/html

        <img src="cid:logo@example"><div style="background-image:url('cid:logo%40example')"></div>
        --related
        Content-Type: image/png
        Content-ID: <logo@example>
        Content-Disposition: inline; filename="../../secret.png"
        Content-Transfer-Encoding: base64

        aW1hZ2U=
        --related--
        """
        #expect(MailHTMLBody.html(from: source) == "<img src=\"data:image/png;base64,aW1hZ2U=\"><div style=\"background-image:url('data:image/png;base64,aW1hZ2U=')\"></div>")
    }

    @Test
    func onlyRecognizesDelimitersOnCompleteLines() {
        let source = """
        Content-Type: multipart/alternative; boundary=part

        --part
        Content-Type: text/html

        <p>Keep --part in text</p>
        --part-extra
         --part
        --part-- \t
        """
        #expect(MailHTMLBody.html(from: source) == "<p>Keep --part in text</p>\n--part-extra\n --part")
    }

    @Test(arguments: ["alternative", "mixed"])
    func selectsThePreferredBodyWithoutAppendingUnrelatedHTML(kind: String) {
        let source = """
        Content-Type: multipart/\(kind); boundary=part

        --part
        Content-Type: text/html

        <p>First</p>
        --part
        Content-Type: text/html

        <p>Last</p>
        --part--
        """
        #expect(MailHTMLBody.html(from: source) == (kind == "alternative" ? "<p>Last</p>" : "<p>First</p>"))
    }

    @Test
    func supportsEscapedQuotedBoundaryParameters() {
        let source = "Content-Type: multipart/mixed; boundary=\"a\\\"b\"\n\n--a\"b\nContent-Type: text/html\n\n<p>Body</p>\n--a\"b--"
        #expect(MailHTMLBody.html(from: source) == "<p>Body</p>")
    }

    @Test(arguments: ["image/svg+xml", "text/html", "application/octet-stream"])
    func doesNotInlineActiveOrUnrecognizedAttachments(type: String) {
        let source = """
        Content-Type: multipart/related; boundary=part

        --part
        Content-Type: text/html

        <p>Body</p><img src="cid:attachment">
        --part
        Content-Type: \(type)
        Content-ID: <attachment>
        Content-Disposition: attachment
        Content-Transfer-Encoding: base64

        c2FmZQ==
        --part--
        """
        #expect(MailHTMLBody.html(from: source) == "<p>Body</p><img src=\"cid:attachment\">")
    }

    @Test(arguments: [
        "", "No MIME headers", "Content-Type: text/plain\n\n<p>Literal text</p>",
        "Content-Type: text/html\n\n \t\n",
        "Content-Type: text/html\nContent-Transfer-Encoding: base64\n\n###",
        "Content-Type: text/html\nContent-Transfer-Encoding: quoted-printable\n\n<p>=ZZ</p>",
        "Content-Type: text/html; charset=unknown-charset\nContent-Transfer-Encoding: base64\n\nPHA+PC9wPg==",
        "Content-Type: multipart/mixed\n\n<p>No boundary</p>",
        "Content-Type: multipart/mixed; boundary=part\n\n--part\nContent-Type: text/html\n\n<p>Incomplete</p>",
        "Content-Type: text/html\nContent-Transfer-Encoding: unknown\n\n<p>Body</p>",
        "Content-Type: text/html\nContent-Disposition: attachment\n\n<p>Attachment</p>",
        "Content-Type: message/rfc822\n\nContent-Type: text/html\n\n<p>Forwarded attachment</p>",
    ])
    func unsupportedOrMalformedSourceFallsBackToMailPlainText(source: String) {
        #expect(MailHTMLBody.html(from: source) == nil)
    }

    @Test
    func limitsSourceSizeAndMIMENesting() {
        let oversized = "Content-Type: text/html\n\n" + String(repeating: "a", count: 20 * 1_024 * 1_024)
        #expect(MailHTMLBody.html(from: oversized) == nil)
        var nested = "Content-Type: text/html\n\n<p>Deep</p>"
        for index in 0..<40 {
            nested = "Content-Type: multipart/mixed; boundary=b\(index)\n\n--b\(index)\n\(nested)\n--b\(index)--"
        }
        #expect(MailHTMLBody.html(from: nested) == nil)
    }

    @Test
    func boundsRepeatedInlineImageExpansion() {
        let image = Data(repeating: 0, count: 1_024 * 1_024).base64EncodedString()
        let source = "Content-Type: multipart/related; boundary=p\n\n--p\nContent-Type: text/html\n\n"
            + String(repeating: "<img src=\"cid:large\">", count: 20)
            + "\n--p\nContent-Type: image/png\nContent-ID: <large>\nContent-Transfer-Encoding: base64\n\n"
            + image + "\n--p--"
        #expect(MailHTMLBody.html(from: source) == nil)
    }

    @Test
    func truncatedTransferEncodingsFailWithABoundedDeterministicCorpus() {
        for length in 0..<32 {
            let body = String(repeating: "a", count: length)
            for suffix in ["=", "=Q", "=ZZ", "=+1", "=-0"] {
                let source = "Content-Type: text/html\nContent-Transfer-Encoding: quoted-printable\n\n" + body + suffix
                #expect(MailHTMLBody.html(from: source) == nil)
            }
        }
    }
}
