#!/bin/zsh
set -euo pipefail

if [[ "${ZISLA_NATIVE_SCROLL_TESTS:-0}" != 1 ]]; then
  print -r -- 'SKIP: set ZISLA_NATIVE_SCROLL_TESTS=1 to test isolated AppKit/WebKit input delivery.'
  exit 0
fi

ROOT="${0:A:h:h:h}"
SCROLL_SOURCE="${1:-$ROOT/Sources/Zisla/ScreenshotLongCaptureAutoScroll.swift}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-long-capture-native.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

python3 - "$SCROLL_SOURCE" "$ROOT/Sources/Zisla/ScreenshotEditorView.swift" \
  "$ROOT/Sources/Zisla/ScreenshotCapture.swift" "$TEST_ROOT/Native.swift" <<'PYTHON'
from pathlib import Path
import sys

scroll, editor, capture = (Path(path).read_text() for path in sys.argv[1:4])
directions = editor[editor.index('enum ScreenshotLongCaptureDirection:'):editor.index('struct ScreenshotLongCaptureMatch:')]
start = capture.index('    static func globalPoint(')
end = capture.index('\n    static func target(', start)
geometry = 'enum ScreenshotSnapTargetGeometry {\n' + capture[start:end] + '\n}\n'
Path(sys.argv[4]).write_text('import AppKit\nimport WebKit\nimport Darwin\n' + directions + geometry + scroll + r'''

func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}

final class FixtureDocument: NSView {
    override var isFlipped: Bool { true }
}

@MainActor final class Receiver: NSObject, WKNavigationDelegate {
    let mode: String
    let direction: ScreenshotLongCaptureDirection
    let placement: ScreenshotLongCapturePlacement
    let window = NSWindow(contentRect: CGRect(x: 300, y: 200, width: 480, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let target = NSScrollView(frame: CGRect(x: 260, y: 40, width: 200, height: 220))
    let decoy = NSScrollView(frame: CGRect(x: 20, y: 40, width: 200, height: 220))
    var webView: WKWebView?
    var eventCount = 0
    var eventWindow = 0
    var monitor: Any?

    init(mode: String, direction: ScreenshotLongCaptureDirection, placement: ScreenshotLongCapturePlacement) {
        self.mode = mode
        self.direction = direction
        self.placement = placement
    }

    func start() {
        window.isReleasedWhenClosed = false
        window.title = "Zisla isolated scrolling fixture"
        window.alphaValue = 0.02
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 480, height: 300))
        window.contentView = root
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            MainActor.assumeIsolated {
                eventCount += 1
                eventWindow = event.windowNumber
                DispatchQueue.main.asyncAfter(deadline: .now() + ScreenshotLongCaptureAutoScroll.settleDelay + 0.1) { [self] in
                    sample()
                }
            }
            return event
        }
        if mode == "appkit" {
            for scrollView in [target, decoy] {
                scrollView.documentView = FixtureDocument(frame: CGRect(x: 0, y: 0, width: 2_000, height: 2_000))
                scrollView.hasHorizontalScroller = true
                scrollView.hasVerticalScroller = true
                scrollView.usesPredominantAxisScrolling = false
                root.addSubview(scrollView)
            }
            target.contentView.scroll(to: CGPoint(x: 200, y: 200))
            target.reflectScrolledClipView(target.contentView)
            window.makeKeyAndOrderFront(nil)
            ready(at: target.convert(CGPoint(x: 100, y: 110), to: nil))
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: root.bounds, configuration: configuration)
            self.webView = webView
            webView.navigationDelegate = self
            root.addSubview(webView)
            window.makeKeyAndOrderFront(nil)
            webView.loadHTMLString("""
                <html><head><style>
                body { margin: 0; width: 2000px; height: 2000px; }
                .box { position: absolute; top: 40px; width: 200px; height: 220px; overflow: scroll; }
                #decoy { left: 20px; } #target { left: 260px; }
                .content { width: 2000px; height: 2000px; background: linear-gradient(135deg, #bde, #ebd); }
                </style></head><body>
                <div id="decoy" class="box"><div class="content"></div></div>
                <div id="target" class="box"><div class="content"></div></div>
                </body></html>
                """, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.getElementById('target').scrollTo(200, 200)") { [self] _, error in
            MainActor.assumeIsolated {
                if let error { fail("WebKit setup failed: \(error)") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                    ready(at: CGPoint(x: 360, y: 300 - 150))
                }
            }
        }
    }

    func ready(at localPoint: CGPoint) {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let screenPoint = window.convertPoint(toScreen: localPoint)
        let mainFrame = NSScreen.screens[0].frame
        let quartzPoint = CGPoint(x: screenPoint.x, y: mainFrame.maxY - screenPoint.y)
        guard ScreenshotLongCaptureAutoScroll.targetWindow(at: quartzPoint,
            processIdentifier: ProcessInfo.processInfo.processIdentifier, windows: windows)?.number == Int64(window.windowNumber) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [self] in ready(at: localPoint) }
            return
        }
        emit(["kind": "ready", "pid": ProcessInfo.processInfo.processIdentifier,
              "window": window.windowNumber, "x": quartzPoint.x, "y": quartzPoint.y])
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [self] in
            fail("\(mode) received no verified wheel event before the bounded deadline")
        }
    }

    func sample() {
        if let webView {
            webView.evaluateJavaScript("""
                (() => { const t = document.getElementById('target'); const d = document.getElementById('decoy');
                return [t.scrollLeft, t.scrollTop, d.scrollLeft, d.scrollTop, window.scrollX, window.scrollY]; })()
                """) { [self] value, error in
                    MainActor.assumeIsolated {
                        if let error { fail("WebKit sampling failed: \(error)") }
                        guard let offsets = value as? [Double], offsets.count == 6 else {
                            fail("WebKit did not return the fixture offsets")
                        }
                        finish(offsets: offsets)
                    }
                }
        } else {
            let origin = target.contentView.bounds.origin
            let other = decoy.contentView.bounds.origin
            finish(offsets: [origin.x, origin.y, other.x, other.y, 0, 0])
        }
    }

    func finish(offsets: [Double]) {
        let distance: Double = placement == .append ? 40 : -40
        let expected = direction == .vertical ? [200, 200 + distance] : [200 + distance, 200]
        guard offsets[0..<2].elementsEqual(expected), offsets[2...].allSatisfy({ $0 == 0 }),
              eventCount == 1, eventWindow == window.windowNumber else {
            fail("\(mode) \(direction) \(placement): offsets=\(offsets), expected=\(expected), events=\(eventCount), window=\(eventWindow)/\(window.windowNumber)")
        }
        emit(["kind": "passed", "mode": mode, "offsets": offsets])
        if let monitor { NSEvent.removeMonitor(monitor) }
        window.close()
        exit(0)
    }

    func fail(_ message: String) -> Never {
        emit(["kind": "failed", "message": message])
        window.close()
        exit(1)
    }
}

alarm(30)
if CommandLine.arguments[1] == "receiver" {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let receiver = Receiver(mode: CommandLine.arguments[2],
        direction: CommandLine.arguments[3] == "vertical" ? .vertical : .horizontal,
        placement: CommandLine.arguments[4] == "append" ? .append : .prepend)
    DispatchQueue.main.async { receiver.start() }
    NSApp.run()
} else {
    guard CGPreflightPostEventAccess() else {
        FileHandle.standardError.write(Data("FAIL: this opt-in test requires existing event-posting permission\n".utf8))
        exit(1)
    }
    for mode in ["appkit", "webkit"] {
        for direction in ["vertical", "horizontal"] {
            for placement in ["append", "prepend"] {
                let receiver = Process()
                receiver.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                receiver.arguments = ["receiver", mode, direction, placement]
                let output = Pipe()
                receiver.standardOutput = output
                receiver.standardError = FileHandle.standardError
                try receiver.run()
                var line = Data()
                var passed = false
                var posted = false
                while true {
                    let byte = output.fileHandleForReading.readData(ofLength: 1)
                    if byte.isEmpty { break }
                    if byte[0] != 10 { line.append(byte); continue }
                    let value = try JSONSerialization.jsonObject(with: line) as! [String: Any]
                    line.removeAll()
                    if value["kind"] as? String == "ready" {
                        let point = CGPoint(x: value["x"] as! Double, y: value["y"] as! Double)
                        let pid = (value["pid"] as! NSNumber).int32Value
                        let hover = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                            mouseCursorPosition: CGPoint(x: point.x - 240, y: point.y), mouseButton: .left)!
                        guard ScreenshotLongCaptureAutoScroll.post(hover, to: pid) else {
                            FileHandle.standardError.write(Data("FAIL: fixture closed before its hover primer\n".utf8))
                            exit(1)
                        }
                        Thread.sleep(forTimeInterval: 0.05)
                        let event = ScreenshotLongCaptureAutoScroll.event(
                            selection: CGRect(x: point.x - 100, y: point.y - 100, width: 200, height: 200),
                            displayBounds: CGDisplayBounds(CGMainDisplayID()),
                            direction: direction == "vertical" ? .vertical : .horizontal,
                            placement: placement == "append" ? .append : .prepend)!
                        posted = ScreenshotLongCaptureAutoScroll.post(event, to: pid)
                    } else if value["kind"] as? String == "passed" {
                        passed = true
                    } else if let message = value["message"] as? String {
                        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                    }
                }
                receiver.waitUntilExit()
                guard posted, passed, receiver.terminationStatus == 0 else {
                    FileHandle.standardError.write(Data("FAIL: \(mode) \(direction) \(placement): posted=\(posted), passed=\(passed)\n".utf8))
                    exit(1)
                }
                print("PASS: \(mode) \(direction) \(placement); targeted content moved 40pt and neighboring content stayed still")
            }
        }
    }
    print("PASS: 8 isolated AppKit/WebKit delivery cases")
}
''')
PYTHON

xcrun swiftc -swift-version 6 -module-cache-path "$TEST_ROOT/ModuleCache" \
  "$TEST_ROOT/Native.swift" -o "$TEST_ROOT/Native"
"$TEST_ROOT/Native" sender
