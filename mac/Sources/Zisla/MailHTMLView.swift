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

final class MailBodyWebView: WKWebView, WKNavigationDelegate, WKUIDelegate {
    private var lastHTML: String?
    var openLink: (URL) -> Void = { NSWorkspace.shared.open($0) }

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.glassAppearanceScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
        uiDelegate = self
        // Match the Notes web view so the shared native glass surface remains visible.
        setValue(false, forKey: "drawsBackground")
        underPageBackgroundColor = .clear
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
            body { margin: 12px; font: 14px -apple-system, sans-serif; overflow-wrap: anywhere; }
            a { color: #4aa3ff; }
            img { max-width: 100%; height: auto; }
            table { max-width: 100%; width: auto; }
            </style></head><body>\(html)</body></html>
            """, baseURL: nil)
    }

    // Sender templates often put their paper color on nested tables, not just the body.
    // Adapt neutral surfaces in an isolated world without enabling scripts from the email.
    private static let glassAppearanceScript = #"""
        (() => {
          const color = value => {
            const match = value.match(/^rgba?\(([\d.,\s]+)\)$/);
            if (!match) return null;
            const channels = match[1].split(',').map(Number);
            return { neutral: Math.max(...channels.slice(0, 3)) - Math.min(...channels.slice(0, 3)) <= 32,
                     dark: Math.max(...channels.slice(0, 3)) < 192,
                     alpha: channels[3] ?? 1 };
          };
          const accented = new WeakSet();
          for (const element of document.querySelectorAll('*')) {
            if (!(element instanceof HTMLElement)) continue;
            const style = getComputedStyle(element);
            const background = color(style.backgroundColor);
            const foreground = color(style.color);
            const root = element === document.documentElement || element === document.body;
            if (!root && (accented.has(element.parentElement) || (background && !background.neutral && background.alpha > 0))) {
              accented.add(element);
              continue;
            }
            if (root || (background?.neutral && background.alpha > 0)) {
              element.style.setProperty('background', 'transparent', 'important');
            }
            if (foreground?.neutral && foreground.dark && foreground.alpha > 0) {
              element.style.setProperty('color', 'rgba(255,255,255,0.92)', 'important');
            }
          }
        })();
        """#

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(navigationPolicy(
            for: navigationAction.request.url,
            isMainFrame: navigationAction.targetFrame?.isMainFrame == true,
            isLink: navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil
        ))
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        _ = navigationPolicy(
            for: navigationAction.request.url,
            isMainFrame: navigationAction.targetFrame?.isMainFrame == true,
            isLink: true
        )
        return nil
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
