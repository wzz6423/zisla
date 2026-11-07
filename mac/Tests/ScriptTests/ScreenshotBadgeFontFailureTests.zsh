#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
CAPTURE_SOURCE="${1:-$ROOT/Sources/Zisla/ScreenshotCapture.swift}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-badge-font-failure.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

# Fault injection changes NSString globally, so keep it outside the shared Swift test host.
python3 - "$CAPTURE_SOURCE" "$TEST_ROOT/Badge.swift" <<'PYTHON'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
geometry = 'enum ScreenshotSelectionHandle:' + source.split('enum ScreenshotSelectionHandle:', 1)[1].split(
    'enum ScreenshotSnapTargetGeometry', 1
)[0]
badge = 'struct ScreenshotSelectionSizeBadge: View {' + source.split(
    'struct ScreenshotSelectionSizeBadge: View {', 1
)[1]
Path(sys.argv[2]).write_text(r'''
import AppKit
import ObjectiveC
import SwiftUI
''' + geometry + badge + r'''

extension NSString {
    @objc func zisla_failBadgeMeasurement(withAttributes attributes: [NSAttributedString.Key: Any]?) -> NSSize {
        if let font = attributes?[.font] as? NSFont, font.pointSize == 12,
           font.fontDescriptor.symbolicTraits.contains(.monoSpace) {
            NSException(name: .invalidArgumentException,
                reason: "attempt to insert nil object from objects[0]", userInfo: nil).raise()
        }
        return zisla_failBadgeMeasurement(withAttributes: attributes)
    }
}

@main
struct BadgeFontFailureTest {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSSetUncaughtExceptionHandler { exception in
            FileHandle.standardError.write(Data("\(exception.name.rawValue): \(exception.reason ?? "")\n".utf8))
            exit(86)
        }
        guard let original = class_getInstanceMethod(NSString.self, #selector(NSString.size(withAttributes:))),
              let injected = class_getInstanceMethod(NSString.self, #selector(NSString.zisla_failBadgeMeasurement(withAttributes:)))
        else { fatalError("Cannot inject the logged font measurement failure") }
        method_exchangeImplementations(original, injected)
        defer { method_exchangeImplementations(original, injected) }

        if CommandLine.arguments.contains("--control") {
            _ = ("300 × 200" as NSString).size(withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            ])
            fatalError("The font failure control must raise")
        }

        let bounds = CGSize(width: 800, height: 600)
        for radius: CGFloat? in [nil, 0, 205] {
            let selection = CGRect(x: 200, y: 100, width: 452, height: 300)
            let badge = ScreenshotSelectionSizeBadge(selection: selection, bounds: bounds, cornerRadius: radius)
            let size = badge.badgeSize
            precondition(size.width.isFinite && size.width > 20 && size.height >= 27,
                         "The readout must keep its text and padding after a font measurement failure")
            let renderer = ImageRenderer(content: badge.frame(width: bounds.width, height: bounds.height))
            precondition(renderer.cgImage != nil, "The selection readout must remain renderable")
        }
        print("PASS: selection and radius readouts survive the logged font measurement exception")
    }
}
''')
PYTHON

xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$TEST_ROOT/ModuleCache" \
  "$TEST_ROOT/Badge.swift" -o "$TEST_ROOT/Badge"

python3 - "$TEST_ROOT/Badge" <<'PYTHON'
import subprocess
import sys

control = subprocess.run([sys.argv[1], '--control'], capture_output=True, text=True)
if control.returncode != 86 or 'NSInvalidArgumentException: attempt to insert nil object' not in control.stderr:
    sys.exit('The control did not reproduce the logged font measurement failure')
result = subprocess.run([sys.argv[1]], capture_output=True, text=True)
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
if result.returncode:
    sys.exit(f'Selection badge exited during the font measurement failure (status {result.returncode})')
PYTHON
