import AppKit
import Network
import Testing
import WebKit
import XCTest
@testable import Zisla

@MainActor
@Suite(.serialized)
struct MailHTMLViewTests {
    @Test
    func rendersOriginalStylesTablesAndInlineImagesOnTransparentBackground() async throws {
        let webView = makeWebView()
        defer { webView.stopLoading() }
        try await load("""
            <!doctype html><html><head><style>.button { background-color: rgb(33, 135, 57); padding: 16px; }</style></head>
            <body><h1>Workflow run</h1><table><tr><td>Failed</td></tr></table>
            <a class="button" href="https://example.com/run">View run</a>
            <img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==">
            </body></html>
            """, in: webView)
        let result = try #require(await webView.evaluateJavaScript("""
            (() => ({
              heading: document.querySelector('h1').innerText,
              cell: document.querySelector('td').innerText,
              buttonColor: getComputedStyle(document.querySelector('.button')).backgroundColor,
              background: getComputedStyle(document.body).backgroundColor,
              imageWidth: document.querySelector('img').naturalWidth
            }))()
            """) as? [String: Any])
        #expect(result["heading"] as? String == "Workflow run")
        #expect(result["cell"] as? String == "Failed")
        #expect(result["buttonColor"] as? String == "rgb(33, 135, 57)")
        #expect(result["background"] as? String == "rgba(0, 0, 0, 0)")
        #expect(result["imageWidth"] as? Int == 1)
    }

    @Test
    func exposesTheNativeGlassAndAdaptsNeutralMailColorsWithoutChangingAccents() async throws {
        let webView = makeWebView()
        defer { webView.stopLoading() }
        try await load("""
            <style>td { background:#f6f8fa !important; }</style>
            <html style="background: rgb(0,40,80) !important"><body style="background: #fff !important; color: #24292f">
            <table bgcolor="#ffffff"><tr><td style="background-color:rgb(246,248,250)">
            <span id="modern" style="color:color(display-p3 1 0 0)">Brand</span>
            <div id="text" style="color: #24292f !important">Readable message</div>
            <a id="link" href="https://example.com">View issue</a>
            <a id="button" style="background:#218739;color:white;padding:12px" href="https://example.com"><span>View run</span></a>
            <p id="warning" style="color: rgb(180,20,20)">Failed</p>
            <div id="accent" style="background:rgb(255,220,0)"><span style="color:black">Status</span></div>
            <span id="hidden" style="color:rgba(0,0,0,0)">Hidden preview</span>
            <svg width="10" height="10" style="color:black"><rect id="graphic" width="10" height="10" fill="currentColor"/></svg>
            </td></tr></table></body></html>
            """, in: webView)
        let result = try #require(await webView.evaluateJavaScript("""
            (() => ({
              backgrounds: ['html', 'body', 'table', 'td'].map(selector => getComputedStyle(document.querySelector(selector)).backgroundColor),
              text: getComputedStyle(document.getElementById('text')).color,
              link: getComputedStyle(document.getElementById('link')).color,
              button: getComputedStyle(document.getElementById('button')).backgroundColor,
              warning: getComputedStyle(document.getElementById('warning')).color,
              accent: getComputedStyle(document.getElementById('accent')).backgroundColor,
              accentText: getComputedStyle(document.querySelector('#accent span')).color,
              hidden: getComputedStyle(document.getElementById('hidden')).color,
              modern: getComputedStyle(document.getElementById('modern')).color,
              graphic: getComputedStyle(document.getElementById('graphic')).fill
            }))()
            """) as? [String: Any])
        #expect(result["backgrounds"] as? [String] == Array(repeating: "rgba(0, 0, 0, 0)", count: 4))
        #expect(result["text"] as? String == "rgba(255, 255, 255, 0.92)")
        #expect(result["link"] as? String == "rgb(74, 163, 255)")
        #expect(result["button"] as? String == "rgb(33, 135, 57)")
        #expect(result["warning"] as? String == "rgb(180, 20, 20)")
        #expect(result["accent"] as? String == "rgb(255, 220, 0)")
        #expect(result["accentText"] as? String == "rgb(0, 0, 0)")
        #expect(result["hidden"] as? String == "rgba(0, 0, 0, 0)")
        #expect(result["modern"] as? String == "color(display-p3 1 0 0)")
        #expect(result["graphic"] as? String == "rgb(0, 0, 0)")
        #expect(!webView.isOpaque)
        #expect(webView.underPageBackgroundColor.alphaComponent == 0)
        #expect(!webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    }

    @Test
    func fitsWideImagesTablesAndUnbrokenTextInsideTheReadingPane() async throws {
        let webView = makeWebView()
        defer { webView.stopLoading() }
        try await load("""
            <img width="800" height="800" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==">
            <table width="800"><tr><td>Workflow</td></tr></table>
            <p>\(String(repeating: "longword", count: 100))</p>
            """, in: webView)
        let result = try #require(await webView.evaluateJavaScript("""
            (() => ({
              image: document.querySelector('img').getBoundingClientRect().width,
              imageHeight: document.querySelector('img').getBoundingClientRect().height,
              table: document.querySelector('table').getBoundingClientRect().width,
              width: document.documentElement.clientWidth,
              scrollWidth: document.documentElement.scrollWidth
            }))()
            """) as? [String: Double])
        let width = try #require(result["width"])
        #expect(try #require(result["image"]) <= width)
        #expect(result["image"] == result["imageHeight"])
        #expect(try #require(result["table"]) <= width)
        #expect(result["scrollWidth"] == width)
    }

    @Test
    func blocksScriptsFramesFormsFileResourcesAndAutomaticNavigation() async throws {
        let webView = makeWebView()
        defer { webView.stopLoading() }
        var opened: [URL] = []
        webView.openLink = { opened.append($0) }
        try await load("""
            <meta http-equiv="refresh" content="0;url=data:text/html,redirected">
            <base href="https://example.com/">
            <script>window.compromised = true</script>
            <iframe src="data:text/html,<p>frame-content</p>"></iframe>
            <img src="file:///does/not/exist" onerror="window.compromised = true">
            <form action="data:text/html,submitted"><input name="secret" value="fixture"></form>
            <p>Safe body</p>
            """, in: webView)
        let result = try #require(await webView.evaluateJavaScript("""
            (() => ({
              compromised: Boolean(window.compromised),
              frame: document.querySelector('iframe').contentDocument?.body?.innerText ?? '',
              base: document.baseURI,
              fileWidth: document.querySelector('img').naturalWidth,
              text: document.body.innerText
            }))()
            """) as? [String: Any])
        #expect(result["compromised"] as? Bool == false)
        #expect(result["frame"] as? String == "")
        #expect(result["base"] as? String == "about:blank")
        #expect(result["fileWidth"] as? Int == 0)
        #expect((result["text"] as? String)?.contains("Safe body") == true)
        _ = try await webView.evaluateJavaScript("document.querySelector('form').submit()")
        #expect(webView.url?.absoluteString == "about:blank")
        #expect(opened.isEmpty)
        #expect(!webView.configuration.websiteDataStore.isPersistent)
        #expect(!webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    }

    @Test(arguments: ["https://127.0.0.1:1/run", "http://127.0.0.1:1/run", "mailto:fixture@example.com"])
    func opensClickedLinksExternallyWithoutReplacingTheMessage(address: String) async throws {
        let webView = makeWebView()
        defer { webView.stopLoading() }
        let opened = XCTestExpectation(description: "A clicked mail link opens externally")
        var openedURL: URL?
        webView.openLink = { url in
            openedURL = url
            opened.fulfill()
        }
        try await load("<a href=\"\(address)\" target=\"_blank\">Open</a><p>Message</p>", in: webView)
        _ = try await webView.evaluateJavaScript("document.querySelector('a').click()")
        try #require(await XCTWaiter.fulfillment(of: [opened], timeout: 5) == .completed)
        #expect(openedURL?.absoluteString == address)
        #expect(webView.url?.absoluteString == "about:blank")
    }

    @Test(arguments: ["file:///does/not/exist", "javascript:window.compromised=true", "zisla://action", "data:text/html,replaced"])
    func rejectsUnsafeLinkSchemes(address: String) {
        let webView = makeWebView()
        defer { webView.stopLoading() }
        var opened: [URL] = []
        webView.openLink = { opened.append($0) }
        let policy = webView.navigationPolicy(for: URL(string: address), isMainFrame: true, isLink: true)
        #expect(opened.isEmpty)
        #expect(policy == .cancel)
    }

    @Test
    func onlyAllowsLocalDocumentNavigationAndNeverOpensAutomaticRequests() {
        let webView = makeWebView()
        var opened: [URL] = []
        webView.openLink = { opened.append($0) }
        let cases: [(String?, Bool, Bool, WKNavigationActionPolicy)] = [
            ("about:blank", false, true, .allow),
            ("about:blank#section", true, true, .allow),
            ("about:blank", false, false, .cancel),
            ("https://example.com/redirect", false, true, .cancel),
            (nil, false, true, .cancel),
        ]
        for (address, isLink, mainFrame, expected) in cases {
            let policy = webView.navigationPolicy(for: address.flatMap(URL.init(string:)), isMainFrame: mainFrame, isLink: isLink)
            #expect(policy == expected)
            #expect(opened.isEmpty)
        }
    }

    @Test
    func preservesScrollOnRefreshAndReplacesTheDocumentWhenContentChanges() async throws {
        let webView = makeWebView()
        defer { webView.stopLoading() }
        let html = "<div style=\"height:3000px\">Long message</div>"
        try await load(html, in: webView)
        _ = try await webView.evaluateJavaScript("window.scrollTo(0, 150); window.fixtureMarker = true")
        webView.setHTML(html)
        #expect(try await webView.evaluateJavaScript("Boolean(window.fixtureMarker)") as? Bool == true)
        #expect(try await webView.evaluateJavaScript("window.scrollY") as? Double == 150)
        try await load("<p>Next message</p>", in: webView)
        #expect(try await webView.evaluateJavaScript("document.body.innerText") as? String == "Next message")
        #expect(try await webView.evaluateJavaScript("Boolean(window.fixtureMarker)") as? Bool == false)
    }

    @Test
    func rendersRemoteImagesUsingAnIsolatedLoopbackServer() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = XCTestExpectation(description: "The fixture image server starts")
        let received = XCTestExpectation(description: "The mail image requests its resource")
        let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!
        let capture = MailImageServerCapture()
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                capture.connections.append(connection)
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    Task { @MainActor in
                        capture.requestText = String(decoding: data ?? Data(), as: UTF8.self)
                        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(pixel.count)\r\nConnection: close\r\n\r\n".utf8)
                        response.append(pixel)
                        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                        received.fulfill()
                    }
                }
            }
        }
        listener.start(queue: .main)
        defer {
            listener.cancel()
            capture.connections.forEach { $0.cancel() }
        }
        try #require(await XCTWaiter.fulfillment(of: [ready], timeout: 5) == .completed)
        let port = try #require(listener.port?.rawValue)
        let webView = makeWebView()
        defer { webView.stopLoading() }
        try await load("<img src=\"http://127.0.0.1:\(port)/pixel.png\">", in: webView)
        try #require(await XCTWaiter.fulfillment(of: [received], timeout: 5) == .completed)
        #expect(capture.requestText.hasPrefix("GET /pixel.png HTTP/1.1"))
        #expect(!capture.requestText.lowercased().contains("\r\ncookie:"))
        #expect(try await webView.evaluateJavaScript("document.querySelector('img').naturalWidth") as? Int == 1)
    }

    private func makeWebView() -> MailBodyWebView {
        let webView = MailBodyWebView()
        webView.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        return webView
    }

    private func load(_ html: String, in webView: MailBodyWebView) async throws {
        let finished = XCTestExpectation(description: "The mail HTML finishes loading")
        let observation = webView.observe(\.isLoading, options: .new) { _, change in
            if change.newValue == false { finished.fulfill() }
        }
        defer { observation.invalidate() }
        webView.setHTML(html)
        try #require(await XCTWaiter.fulfillment(of: [finished], timeout: 10) == .completed)
    }
}

@MainActor
private final class MailImageServerCapture {
    var requestText = ""
    var connections: [NWConnection] = []
}
