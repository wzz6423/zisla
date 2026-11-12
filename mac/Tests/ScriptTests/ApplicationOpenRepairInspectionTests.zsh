#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-repair-inspection.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

python3 - "$ROOT" "$TEST_ROOT" <<'PYTHON'
from pathlib import Path
import subprocess
import sys

root, temporary = map(Path, sys.argv[1:])
source = (root / "Sources/Zisla/ApplicationOpenRepairPresenter.swift").read_text()
source = source.replace("import ZislaCore\n", "").replace("import ZislaKit\n", "")
fixture = temporary / "Inspection.swift"
fixture.write_text(source + r'''

struct ClipboardFileReference: Sendable {
    let url: URL
    let displayName: String
    let bookmark: Data
}
enum ClipboardHistoryContent: Sendable { case file(ClipboardFileReference) }
enum ClipboardAssistantKind: Sendable { case appCannotOpen }
struct ClipboardAssistantDetection: Sendable { let url: URL }
struct FeatureSettings: Sendable {
    let applicationOpenFailureMonitoringActive = true
    let applicationOpenRepairEnabled = true
    let clipboardAssistantDisplayDuration = 0
    let collapsedProgressGlowEnabled = false
    let islandNotchBackground = 0
    let islandVisualStyle = 0
}
@MainActor final class ClipboardAssistantController {
    var displayDuration = 0
    var presentation = Presentation()
    var detections: [ClipboardAssistantDetection] = []
    struct Presentation { var progressGlowEnabled = false; var notchBackground = 0 }
    func present(_ detection: ClipboardAssistantDetection, visualStyle: Int) -> UUID? {
        detections.append(detection)
        return UUID()
    }
}
final class InspectionProbe: @unchecked Sendable {
    static let shared = InspectionProbe()
    private let lock = NSLock()
    private var visited: [URL] = []
    func inspect(_ url: URL) -> ClipboardAssistantDetection? {
        lock.withLock {
            let repeated = visited.contains(url)
            visited.append(url)
            // A file may disappear, lose quarantine, or be cancelled after the first inspection.
            guard !repeated, url.lastPathComponent == "Match.app" else { return nil }
            return ClipboardAssistantDetection(url: url)
        }
    }
    var paths: [URL] { lock.withLock { visited } }
}
enum ClipboardAssistantDetector {
    static func detect(content: ClipboardHistoryContent, enabledKinds: Set<ClipboardAssistantKind>) -> ClipboardAssistantDetection? {
        switch content {
        case .file(let reference): return InspectionProbe.shared.inspect(reference.url)
        }
    }
}
@main struct InspectionFixture {
    @MainActor static func main() async {
        signal(SIGTRAP) { _ in _exit(86) }
        alarm(10)
        let match = URL(fileURLWithPath: "/fixture/Match.app")
        let skipped = URL(fileURLWithPath: "/fixture/Unavailable.app")
        let later = URL(fileURLWithPath: "/fixture/Later.app")
        let controller = ClipboardAssistantController()
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { FeatureSettings() }, canPresent: { true })
        let scenario = CommandLine.arguments[1]
        let inputs = scenario == "first" ? [match, later] : scenario == "second" ? [skipped, match, later] : [skipped]
        presenter.receive(inputs)
        await presenter.task?.value
        let expected = scenario == "none" ? [] : [match]
        guard controller.detections.map(\.url) == expected else { fatalError("Incorrect detected application") }
        let inspected = scenario == "first" ? [match] : scenario == "second" ? [skipped, match] : [skipped]
        guard InspectionProbe.shared.paths == inspected else { fatalError("Inspection must stop after its first matching application") }
        presenter.cancel()
        guard presenter.task == nil else { fatalError("Inspection task was not cleared") }
    }
}
''')
executable = temporary / "inspection"
subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", str(fixture), "-o", str(executable)], check=True)
for scenario in ("first", "second", "none"):
    result = subprocess.run([str(executable), scenario], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"{scenario}: inspection repeated an unstable file read; exit={result.returncode}\n{result.stdout}{result.stderr}"
print("PASS: 3 repair-inspection cases cover unstable detections, skipped files, and no matching application")
PYTHON
