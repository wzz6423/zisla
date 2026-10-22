import Foundation
import SwiftUI
import WebKit

/// Renders Markdown-generated HTML in a `WKWebView`, enabling true support for **images, tables**
/// and other rich content (which `Text`/`AttributedString` cannot handle). Transparent background
/// blends with the Dynamic Island dark glass; link clicks open in an external browser; reloads
/// only when HTML content changes to avoid losing scroll position during edits.
struct MarkdownWebView: NSViewRepresentable {
    let html: String
    var baseURL: URL?
    var allowedLinkSchemes: Set<String>?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        // Transparent background — lets the outer container (dark glass) show through.
        // WebKit exposes this transparency switch through KVC without advertising its selector.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.allowedLinkSchemes = allowedLinkSchemes
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(allowedLinkSchemes: allowedLinkSchemes)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var allowedLinkSchemes: Set<String>?

        init(allowedLinkSchemes: Set<String>? = nil) {
            self.allowedLinkSchemes = allowedLinkSchemes
        }

        func allowsExternalLink(_ url: URL) -> Bool {
            allowedLinkSchemes.map { $0.contains(url.scheme?.lowercased() ?? "") } ?? true
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // Only allow loading our injected HTML; user link clicks open externally.
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url, allowsExternalLink(url) {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
