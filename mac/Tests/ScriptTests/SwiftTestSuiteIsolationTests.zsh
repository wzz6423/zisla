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
