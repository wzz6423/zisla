#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-swift-testing-host.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

python3 - "$ROOT" "$TEST_ROOT" <<'PYTHON'
from pathlib import Path
import json
import os
import subprocess
import sys

root, temporary = map(Path, sys.argv[1:])
swift = Path(subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip())
platform = Path(subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], text=True).strip())
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
frameworks = platform / "Developer/Library/Frameworks"
environment = dict(os.environ,
    DYLD_FRAMEWORK_PATH=os.pathsep.join(str(platform / "Developer/Library" / directory)
        for directory in ("Frameworks", "PrivateFrameworks")),
    DYLD_LIBRARY_PATH=str(platform / "Developer/usr/lib"))

fixture = temporary / "Fixture.swift"
fixture.write_text("""import CoreFoundation
import Dispatch
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct RunLoopStopFixtureTests {
    @Test
    func completesAfterMainRunLoopStops() async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    CFRunLoopStop(CFRunLoopGetMain())
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }
        #expect(ProcessInfo.processInfo.environment["SWIFT_TEST_HOST_EXPECT_FAILURE"] != "1")
    }
}
""")
compiler = [str(swift.parent / "swiftc"), "-swift-version", "6", "-parse-as-library",
    "-F", str(frameworks), "-sdk", sdk]
host = temporary / "swift-testing-host"
subprocess.run(compiler + [str(root / "Scripts/SwiftTestingHost.swift"), "-o", str(host)], check=True)
library = temporary / "Fixture.dylib"
subprocess.run(compiler + ["-emit-library", "-module-name", "RunLoopStopFixture", str(fixture),
    "-load-plugin-library", str(swift.parent.parent / "lib/swift/host/plugins/testing/libTestingMacros.dylib"),
    "-o", str(library)], check=True)
command = [str(host), "--test-bundle-path", str(library)]

listed = subprocess.run(command + ["--list-tests"], env=environment,
    capture_output=True, text=True, timeout=10)
test = "RunLoopStopFixture.RunLoopStopFixtureTests/completesAfterMainRunLoopStops()"
assert listed.returncode == 0 and test in listed.stdout, listed.stdout + listed.stderr

for fail in (False, True):
    events = temporary / ("failure.jsonl" if fail else "success.jsonl")
    result = subprocess.run(command + ["--filter", "RunLoopStopFixtureTests",
        "--event-stream-output-path", str(events), "--event-stream-version", "0"],
        env=dict(environment, SWIFT_TEST_HOST_EXPECT_FAILURE=str(int(fail))),
        capture_output=True, text=True, timeout=10)
    assert result.returncode == int(fail), result.stdout + result.stderr
    records = [json.loads(line) for line in events.read_text().splitlines()]
    functions = {record["payload"]["id"] for record in records
        if record["kind"] == "test" and record["payload"]["kind"] == "function"}
    assert len(functions) == 1, "The fixture must discover exactly one test function"
    ended = [record["payload"] for record in records if record["kind"] == "event"]
    assert any(event["kind"] == "testEnded" and event["testID"] in functions for event in ended), result.stdout
    assert ended[-1]["kind"] == "runEnded", "Main-loop stops truncated the test run"
    if fail:
        assert any(event["kind"] == "issueRecorded" for event in ended), "Lost the test failure"

missing = subprocess.run([str(host), "--test-bundle-path", str(temporary / "missing.xctest")],
    env=environment, capture_output=True, text=True, timeout=10)
assert missing.returncode == 1 and "missing.xctest" in missing.stderr, missing.stdout + missing.stderr
print("PASS: 4 Swift Testing host cases cover discovery, repeated main-loop stops, failure status, and bundle-load errors")
PYTHON
