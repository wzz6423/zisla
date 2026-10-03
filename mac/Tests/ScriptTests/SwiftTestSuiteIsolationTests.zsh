#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-swift-test-suites-tests.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/results"

cat > "$TEST_ROOT/bin/swift" <<'SCRIPT'
#!/usr/bin/env python3
import json
import os
import re
import sys

args = sys.argv[1:]
assert args[0] == "test"
mode = os.environ["SWIFT_TEST_MODE"]
tests = [
    "OtherTests.First/test()",
    "FixtureTestsExtra.First/test()",
    "FixtureTestsXFirst/test()",
    "FixtureTests.Third/test()",
    "FixtureTests.First/testOne()",
    "FixtureTests.First/Nested/testTwo()",
    "FixtureTests.FirstExtra/test()",
    "FixtureTests.Second/test()",
    "FixtureTests.First/testThree()",
    "FixtureTests.topLevel()/FixtureTests.swift:1:1",
]
if mode == "workflow":
    tests = [
        "ZislaCoreTests.ModelTests/test()",
        "ZislaKitTests.ServiceTests/test()",
        "ZislaTests.WiFiNetworkPanelViewTests/observedPowerKeepsItsColorAndToggleSemanticsInAnInactiveWindow()",
        "ZislaTests.FutureAppKitTests/test()",
        "ZislaTests.FutureAppKitTests/Nested/test()",
        "ZislaTests.FutureAppKitTestsExtra/test()",
        "ZislaTests.topLevel()/Tests.swift:1:1",
    ]
if args == ["test", "list"]:
    if mode == "list-failure":
        sys.exit(5)
    listed = tests[:3] if mode == "empty" else tests
    print("\n".join(test.split("/FixtureTests.swift")[0] for test in listed))
    sys.exit(0)

if mode != "workflow":
    assert "--skip-build" in args
selector = args[args.index("--filter") + 1]
selected = [test for test in tests if re.search(selector, test)]
assert selected
if mode == "workflow":
    assert "--skip" not in args
    appkit = [test for test in selected if test.startswith(("ZislaTests.", "ZislaKitTests."))]
    if appkit:
        assert "--skip-build" in args
        assert len({test.split("/")[0] for test in selected}) == 1, "AppKit suites share a test process"
with open(os.environ["SWIFT_TEST_CAPTURE"], "a") as capture:
    capture.write("\n".join(selected) + "\n")
if mode == "test-failure" and "Second" in selector:
    sys.exit(6)
output = args[args.index("--event-stream-output-path") + 1]
with open(output, "w") as events:
    for kind in ["testEnded", "runEnded"]:
        events.write(json.dumps({"kind": "event", "payload": {"kind": kind}, "version": 0}) + "\n")
SCRIPT
chmod +x "$TEST_ROOT/bin/swift"

for mode in success empty list-failure test-failure; do
  : > "$TEST_ROOT/calls"
  result=0
  PATH="$TEST_ROOT/bin:$PATH" TMPDIR="$TEST_ROOT/results" \
    SWIFT_TEST_MODE="$mode" SWIFT_TEST_CAPTURE="$TEST_ROOT/calls" \
    zsh "$ROOT/Scripts/swift-test-suites.sh" FixtureTests \
    > "$TEST_ROOT/$mode.log" 2>&1 || result=$?
  case "$mode" in
    success)
      [[ "$result" == 0 ]] || { cat "$TEST_ROOT/$mode.log"; exit 1; }
      expected=$'FixtureTests.First/Nested/testTwo()\nFixtureTests.First/testOne()\nFixtureTests.First/testThree()\nFixtureTests.FirstExtra/test()\nFixtureTests.Second/test()\nFixtureTests.Third/test()\nFixtureTests.topLevel()/FixtureTests.swift:1:1'
      ;;
    empty)
      [[ "$result" != 0 ]] || { print -u2 -- 'Accepted an empty test target'; exit 1; }
      expected=""
      ;;
    list-failure)
      [[ "$result" == 5 ]] || { print -u2 -- 'Lost test discovery failure'; exit 1; }
      expected=""
      ;;
    test-failure)
      [[ "$result" == 6 ]] || { print -u2 -- 'Lost isolated suite failure'; exit 1; }
      expected=$'FixtureTests.First/Nested/testTwo()\nFixtureTests.First/testOne()\nFixtureTests.First/testThree()\nFixtureTests.FirstExtra/test()\nFixtureTests.Second/test()'
      ;;
  esac
  [[ "$(LC_ALL=C sort "$TEST_ROOT/calls")" == "$expected" ]] || { print -u2 -- "Wrong test selection: $mode"; cat "$TEST_ROOT/calls"; exit 1; }
  [[ -z "$(find "$TEST_ROOT/results" -mindepth 1 -print)" ]] || { print -u2 -- 'Leaked suite results'; exit 1; }
done

print -- 'PASS: Swift suite isolation preserves nested and top-level tests, filters exact targets, and propagates discovery and test failures'

PATH="$TEST_ROOT/bin:$PATH" TMPDIR="$TEST_ROOT/results" \
  SWIFT_TEST_MODE=workflow SWIFT_TEST_CAPTURE="$TEST_ROOT/workflow-calls" \
  python3 - "$ROOT" <<'PYTHON'
from pathlib import Path
import os
import shlex
import subprocess
import sys

root = Path(sys.argv[1])
commands = [
    shlex.split(line.strip())
    for line in (root.parent / ".github/workflows/swift-tests.yml").read_text().splitlines()
    if line.strip().startswith(("zsh Scripts/swift-test.sh ", "zsh Scripts/swift-test-suites.sh "))
]
for command in commands:
    subprocess.run(command, cwd=root, check=True)
actual = Path(os.environ["SWIFT_TEST_CAPTURE"]).read_text().splitlines()
expected = [
    "ZislaCoreTests.ModelTests/test()",
    "ZislaKitTests.ServiceTests/test()",
    "ZislaTests.WiFiNetworkPanelViewTests/observedPowerKeepsItsColorAndToggleSemanticsInAnInactiveWindow()",
    "ZislaTests.FutureAppKitTests/test()",
    "ZislaTests.FutureAppKitTests/Nested/test()",
    "ZislaTests.FutureAppKitTestsExtra/test()",
    "ZislaTests.topLevel()/Tests.swift:1:1",
]
assert sorted(actual) == sorted(expected), f"Workflow missed or duplicated tests: {actual}"
assert not list(Path(os.environ["TMPDIR"]).iterdir()), "Workflow leaked test results"
print("PASS: workflow discovers every target and runs every AppKit suite exactly once in its own process")
PYTHON
