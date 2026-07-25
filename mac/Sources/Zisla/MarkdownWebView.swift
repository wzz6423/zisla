import Foundation
import SwiftUI
import WebKit

/// 把 Markdown 渲染出的 HTML 用 `WKWebView` 显示，从而真正支持**图片、表格**等
/// 富内容（这是 `Text`/`AttributedString` 做不到的）。透明背景以融入灵动岛深色玻璃；
/// 点击链接在外部浏览器打开；仅当 HTML 内容变化时重载，避免编辑时丢失滚动位置。
struct MarkdownWebView: NSViewRepresentable {
    let html: String
    var baseURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        // 透明背景，让外层容器（深色玻璃）透出。
        if webView.responds(to: Selector(("setDrawsBackground:"))) {
            webView.setValue(false, forKey: "drawsBackground")
        }
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // 仅允许加载我们注入的 HTML；用户点击链接则在外部打开。
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
