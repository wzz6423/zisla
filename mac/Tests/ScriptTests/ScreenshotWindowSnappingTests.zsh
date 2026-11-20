#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
CAPTURE_SOURCE="${1:-$ROOT/Sources/Zisla/ScreenshotCapture.swift}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-window-snapping.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

# Exercise the selection controller's default query without displaying windows or reading screen contents.
python3 - "$CAPTURE_SOURCE" "$TEST_ROOT/Snapping.swift" <<'PYTHON'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text()
start = source.index('enum ScreenshotSnapTargetGeometry {')
end = source.index('@MainActor\nfinal class ScreenshotSelectionPanel:', start)
provider = source[start:end]
default_query = re.search(
    r'snapTargets: @escaping SnapTargets = (\{.*?\n        \})\n    \)', source, re.S
).group(1)

Path(sys.argv[2]).write_text(r'''
import AppKit

enum ScreenshotCaptureService {
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

nonisolated(unsafe) var windowInfo: [[String: Any]]?
func CGWindowListCopyWindowInfo(_ options: CGWindowListOption, _ relativeWindow: CGWindowID) -> CFArray? {
    windowInfo.map { $0 as CFArray }
}

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func window(_ rect: CGRect, layer: Int = 0, alpha: Double = 1, owner: pid_t) -> [String: Any] {
    [kCGWindowBounds as String: rect.dictionaryRepresentation,
     kCGWindowLayer as String: layer,
     kCGWindowAlpha as String: alpha,
     kCGWindowOwnerPID as String: owner]
}
''' + provider + r'''
@main struct WindowSnappingTests {
    @MainActor static func main() {
        guard let screen = NSScreen.screens.first,
              let display = ScreenshotCaptureService.displayID(for: screen) else {
            fatalError("A display is required for the coordinate fixture")
        }
        let bounds = CGDisplayBounds(display)
        let settings = CGRect(x: bounds.minX + 100, y: bounds.minY + 100, width: 320, height: 200)
        let external = CGRect(x: bounds.minX + 60, y: bounds.minY + 60, width: 480, height: 320)
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let query: (NSScreen) -> [CGRect] = ''' + default_query + r'''
        let localSettings = ScreenshotSnapTargetGeometry.localRect(settings, in: bounds)!
        let localExternal = ScreenshotSnapTargetGeometry.localRect(external, in: bounds)!

        windowInfo = [window(settings, owner: ownProcess), window(external, owner: ownProcess + 1)]
        let rects = query(screen)
        require(ScreenshotSnapTargetGeometry.target(
            at: CGPoint(x: localSettings.midX, y: localSettings.midY), in: rects
        ) == localSettings, "Default selection must snap to its own settings window instead of the window behind it")
        require(rects == [localSettings, localExternal], "Both local and external regular windows must be selectable")
        print("PASS: default selection includes the settings window and external windows")

        windowInfo = [
            window(bounds, layer: NSWindow.Level.screenSaver.rawValue, owner: ownProcess),
            window(settings, layer: NSWindow.Level.floating.rawValue, owner: ownProcess),
            window(bounds, owner: ownProcess),
            window(settings, alpha: 0.01, owner: ownProcess),
            window(CGRect(x: bounds.minX + 10, y: bounds.minY + 10, width: 39, height: 30), owner: ownProcess),
            window(CGRect(x: bounds.minX + 10, y: bounds.minY + 10, width: 40, height: 29), owner: ownProcess),
            window(settings, owner: ownProcess),
        ]
        require(query(screen) == [localSettings], "Selection/island overlays, invisible, full-display and tiny windows must stay excluded")
        require(ScreenshotSnapTargetGeometry.target(at: .zero, in: query(screen)) == nil,
            "A point outside the settings window must not snap to an overlay")
        print("PASS: overlay and visibility filters remain effective")

        windowInfo = [window(settings, owner: ownProcess), window(external, owner: ownProcess + 1)]
        require(ScreenshotSnapTargetProvider.windowRects(on: screen, excludingProcessIdentifier: ownProcess)
            == [localExternal], "Explicit process exclusion must remain available")
        print("PASS: explicit process exclusion is preserved")

        windowInfo = [[:], [kCGWindowBounds as String: "invalid"]]
        require(query(screen).isEmpty, "Malformed window records must not become snap targets")
        windowInfo = []
        require(query(screen).isEmpty, "An empty window list must produce no targets")
        windowInfo = nil
        require(query(screen).isEmpty, "An unavailable window list must produce no targets")
        print("PASS: malformed, empty and unavailable window lists fail safely")
    }
}
''')
PYTHON

xcrun swiftc -swift-version 6 -parse-as-library "$TEST_ROOT/Snapping.swift" -o "$TEST_ROOT/snapping-tests"
"$TEST_ROOT/snapping-tests"
