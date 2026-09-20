import SwiftUI
import WebKit

struct MailHTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> MailBodyWebView {
        MailBodyWebView()
    }

    func updateNSView(_ webView: MailBodyWebView, context: Context) {
        webView.setHTML(html)
    }
}

final class MailBodyWebView: WKWebView, WKNavigationDelegate {
    private var lastHTML: String?
    var openLink: (URL) -> Void = { NSWorkspace.shared.open($0) }

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setHTML(_ html: String) {
        guard lastHTML != html else { return }
        lastHTML = html
        loadHTMLString("""
            <!doctype html><html><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: https: http:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
            <style>
            body { margin: 12px; font: 14px -apple-system, sans-serif; color: #24292f; background: white; overflow-wrap: anywhere; }
            img { max-width: 100%; height: auto; }
            table { max-width: 100%; width: auto; }
            </style></head><body>\(html)</body></html>
            """, baseURL: nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(navigationPolicy(
            for: navigationAction.request.url,
            isMainFrame: navigationAction.targetFrame?.isMainFrame == true,
            isLink: navigationAction.navigationType == .linkActivated
        ))
    }

    func navigationPolicy(for url: URL?, isMainFrame: Bool, isLink: Bool) -> WKNavigationActionPolicy {
        guard let url else { return .cancel }
        if isMainFrame,
           url.absoluteString == "about:blank" || url.absoluteString.hasPrefix("about:blank#") {
            return .allow
        } else {
            if isLink,
               ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                openLink(url)
            }
            return .cancel
        }
    }
}
