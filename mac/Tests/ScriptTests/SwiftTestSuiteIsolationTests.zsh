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
if args == ["test", "list"]:
    if mode == "list-failure":
        sys.exit(5)
    listed = tests[:3] if mode == "empty" else tests
    print("\n".join(test.split("/FixtureTests.swift")[0] for test in listed))
    sys.exit(0)

assert "--skip-build" in args
selector = args[args.index("--filter") + 1]
selected = [test for test in tests if re.search(selector, test)]
assert selected
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

python3 - "$ROOT/../.github/workflows/swift-tests.yml" <<'PYTHON'
from pathlib import Path
import re
import shlex
import sys

commands = [
    shlex.split(line.strip())
    for line in Path(sys.argv[1]).read_text().splitlines()
    if line.strip().startswith("zsh Scripts/swift-test.sh ")
]
for suite, test in [
    ("AIMascotImageCacheTests", "recoversFromTransientLoadFailureAfterRetry()"),
    ("AIResultSweepPresentationTests", "renderedViewUpdatesWithPlaybackWithoutAnotherQueueEvent()"),
]:
    test_id = f"ZislaTests.{suite}/{test}"
    selected = [
        command for command in commands
        if "--filter" in command
        and re.search(command[command.index("--filter") + 1], test_id)
        and ("--skip" not in command
             or not re.search(command[command.index("--skip") + 1], test_id))
    ]
    if len(selected) != 1 or "--skip" in selected[0]:
        sys.exit(f"CI must run {suite} exactly once in its own test process")
    selector = selected[0][selected[0].index("--filter") + 1]
    for other_suite in ["AIMascotIdentityTests", "RichNoteEditorTests", suite + "Extra"]:
        if re.search(selector, f"ZislaTests.{other_suite}/test()"):
            sys.exit(f"CI {suite} isolation also selected {other_suite}")
    print(f"PASS: CI runs {suite} exactly once without unrelated AppKit tests")
PYTHON
