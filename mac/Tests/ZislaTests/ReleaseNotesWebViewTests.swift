import Foundation
import Testing
import WebKit
import ZislaCore
import ZislaKit

@Suite(.serialized)
@MainActor
struct ReleaseNotesWebViewTests {
    @Test(arguments: [AppLanguage.english, .arabic])
    func webKitRendersTheDocumentAndBlocksEmbeddedExecutableContent(language: AppLanguage) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let resources = ReleaseNotesResourceProbe()
        configuration.setURLSchemeHandler(resources, forURLScheme: "release-notes-test")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 720, height: 400), configuration: configuration)
        let navigation = ReleaseNotesNavigation()
        webView.navigationDelegate = navigation
        defer { webView.stopLoading(); webView.navigationDelegate = nil }
        let html = ReleaseNotesHTML.document(
            markdown: "# Notes\n\n- **Fixed** update notifications\n\n| Version | State |\n| --- | --- |\n| 1.2.3 | Installed |\n\n<script>window.releaseNotesInjected = true</script>\n\n![blocked](release-notes-test:resource)",
            language: language
        )
        try await navigation.load(html, in: webView)
        let document = try #require(await webView.evaluateJavaScript("""
        JSON.stringify({
            title: document.querySelector('h1').textContent,
            items: document.querySelectorAll('li').length,
            cells: document.querySelectorAll('td').length,
            injected: window.releaseNotesInjected === true,
            scripts: document.querySelectorAll('script').length,
            direction: getComputedStyle(document.body).direction,
            bodySize: parseFloat(getComputedStyle(document.body).fontSize),
            headingSize: parseFloat(getComputedStyle(document.querySelector('h1')).fontSize),
            imageLoaded: document.querySelector('img').naturalWidth > 0
        })
        """) as? String)
        let state = try #require(try JSONSerialization.jsonObject(with: Data(document.utf8)) as? [String: Any])
        #expect(state["title"] as? String == "Notes")
        #expect(state["items"] as? Int == 1)
        #expect(state["cells"] as? Int == 2)
        #expect(state["injected"] as? Bool == false)
        #expect(state["scripts"] as? Int == 0)
        #expect(state["imageLoaded"] as? Bool == false)
        #expect(resources.requestCount == 0)
        #expect(state["direction"] as? String == (language.isRightToLeft ? "rtl" : "ltr"))
        #expect(state["headingSize"] as? Double == (state["bodySize"] as? Double).map { $0 * 2 })
    }
}

@MainActor
private final class ReleaseNotesNavigation: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@MainActor
private final class ReleaseNotesResourceProbe: NSObject, WKURLSchemeHandler {
    private(set) var requestCount = 0

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        requestCount += 1
        urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
