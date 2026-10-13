#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
EDITOR_SOURCE="${1:-$ROOT/Sources/Zisla/ScreenshotEditorView.swift}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-screenshot-dialog-tests.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

# Native modal loops alter process-wide AppKit state, so use a dedicated window-server host.
python3 - "$EDITOR_SOURCE" "$ROOT/Sources/ZislaKit/WindowPlacement.swift" "$TEST_ROOT/Dialogs.swift" <<'PYTHON'
from pathlib import Path
import sys

editor = Path(sys.argv[1]).read_text()
presentation = '@MainActor\nenum ScreenshotDialogPresentation' + editor.split(
    '@MainActor\nenum ScreenshotDialogPresentation', 1
)[1].split('/// Presents the PNG save panel', 1)[0]
placement = Path(sys.argv[2]).read_text()
window = editor.split('final class ScreenshotEditorWindow: NSWindow', 1)[1]
window_overrides = 'override var canBecomeKey' + window.split('override var canBecomeKey', 1)[1].split(
    'override func performKeyEquivalent', 1
)[0]

Path(sys.argv[3]).write_text(r'''
import AppKit
import CoreGraphics

final class IslandPanel: NSPanel {}
enum AppLocalization {
    static func text(_ value: String) -> String { value }
}
''' + 'final class ScreenshotEditorWindow: NSWindow {\n' + window_overrides + '}\n'
    + placement + presentation + r'''

@MainActor final class ModalProgress {
    var observedModal = false
    var mainQueueRan = false
    var response: NSApplication.ModalResponse?
}

func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

@MainActor func windowServerLayer(_ window: NSWindow) -> Int? {
    let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber))
        as? [[String: Any]]
    print("[DEBUG-ci-dialog] requested=\(window.windowNumber) count=\(windows?.count ?? 0) firstID=\(String(describing: windows?.first?[kCGWindowNumber as String])) firstLayer=\(String(describing: windows?.first?[kCGWindowLayer as String]))")
    return (windows?.first?[kCGWindowLayer as String] as? NSNumber)?.intValue
}

@MainActor func checkResult(dismissal: String) {
    let screenshot = ScreenshotEditorWindow(
        contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
        styleMask: .borderless, backing: .buffered, defer: false
    )
    screenshot.isReleasedWhenClosed = false
    screenshot.alphaValue = 0
    screenshot.level = .screenSaver
    screenshot.makeKeyAndOrderFront(nil)
    let alert = NSAlert()
    alert.messageText = "Synthetic OCR result"
    let resultText = NSTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
    resultText.string = "Synthetic recognized text"
    resultText.isEditable = false
    alert.accessoryView = resultText
    alert.window.isReleasedWhenClosed = false
    alert.window.alphaValue = 0
    let progress = ModalProgress()
    let probe = Timer(timeInterval: 0.01, repeats: true) { timer in
        let observed = MainActor.assumeIsolated {
            guard NSApp.modalWindow === alert.window,
                  alert.window.isVisible, alert.window.isKeyWindow else { return false }
            progress.observedModal = true
            require(alert.window.level.rawValue > screenshot.level.rawValue,
                    "Visible OCR level \(alert.window.level.rawValue) must exceed screenshot level \(screenshot.level.rawValue)")
            let alertLayer = windowServerLayer(alert.window)
            let screenshotLayer = windowServerLayer(screenshot)
            require(alertLayer != nil && screenshotLayer != nil, "Both windows must exist in WindowServer")
            require(alertLayer! > screenshotLayer!,
                    "WindowServer must display OCR above the screenshot: OCR=\(alertLayer!), screenshot=\(screenshotLayer!)")

            let movedFrame = alert.window.frame.offsetBy(dx: 20, dy: 20)
            alert.window.setFrame(movedFrame, display: false)
            alert.window.resignKey()
            alert.window.level = .modalPanel
            alert.window.becomeKey()
            require(alert.window.level.rawValue > screenshot.level.rawValue, "Refocusing must restore the result level")
            require(alert.window.frame == movedFrame, "Refocusing must not recenter the result")
            alert.window.makeFirstResponder(resultText)
            DispatchQueue.main.async {
                progress.mainQueueRan = true
                if dismissal == "escape" {
                    let escape = NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: alert.window.windowNumber, context: nil,
                        characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                        isARepeat: false, keyCode: 53
                    )!
                    NSApp.postEvent(escape, atStart: true)
                } else {
                    alert.buttons[dismissal == "copy" ? 0 : 1].performClick(nil)
                }
            }
            return true
        }
        if observed { timer.invalidate() }
    }
    let watchdog = Timer(timeInterval: 2, repeats: false) { _ in
        MainActor.assumeIsolated {
            NSApp.stopModal(withCode: .abort)
            let wake = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0
            )!
            NSApp.postEvent(wake, atStart: true)
        }
    }
    defer {
        probe.invalidate()
        watchdog.invalidate()
        alert.window.close()
        screenshot.close()
    }
    DispatchQueue.main.async {
        RunLoop.main.add(probe, forMode: .modalPanel)
        RunLoop.main.add(watchdog, forMode: .modalPanel)
        ScreenshotDialogPresentation.present(alert) { progress.response = $0 }
    }
    let deadline = Date(timeIntervalSinceNow: 3)
    while progress.response == nil, Date() < deadline {
        RunLoop.main.run(mode: .default, before: deadline)
    }
    require(progress.observedModal && progress.mainQueueRan, "The visible modal must allow main-queue work")
    require(progress.response == (dismissal == "copy" ? .alertFirstButtonReturn : .alertSecondButtonReturn),
            "\(dismissal) must finish the modal without the watchdog")
    require(NSApp.modalWindow == nil && !alert.window.isVisible, "The OCR modal must be dismissed")
    require(screenshot.isVisible, "Dismissing OCR must keep the screenshot open")
    screenshot.makeKeyAndOrderFront(nil)
    require(screenshot.isKeyWindow, "The screenshot must regain focus after OCR closes")
    alert.window.level = .normal
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: alert.window)
    require(alert.window.level == WindowPlacement.modalWindowLevel, "A completed result must release its level observer")
    screenshot.performClose(nil)
    require(!screenshot.isVisible, "The screenshot must close after OCR is dismissed")
}

alarm(12)
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
WindowPlacement.installTransientWindowPromotion()
let dismissal = CommandLine.arguments[1]
for _ in 0..<2 { checkResult(dismissal: dismissal) }
print("PASS: native OCR \(dismissal), visible window levels, focus restoration, and a second screenshot")
''')
PYTHON

xcrun swiftc -swift-version 6 -module-cache-path "$TEST_ROOT/ModuleCache" \
  "$TEST_ROOT/Dialogs.swift" -o "$TEST_ROOT/Dialogs"

for dismissal in copy close escape; do
  "$TEST_ROOT/Dialogs" "$dismissal"
done
