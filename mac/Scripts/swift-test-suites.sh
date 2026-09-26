#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TARGET="$1"
shift
SWIFT_TEST_SUITES="$(mktemp -d "${TMPDIR:-/tmp}/zisla-swift-test-suites.XXXXXX")"
trap 'find "$SWIFT_TEST_SUITES" -depth -delete' EXIT

swift test "$@" list > "$SWIFT_TEST_SUITES/tests.txt"
python3 - "$TARGET" "$SWIFT_TEST_SUITES/tests.txt" > "$SWIFT_TEST_SUITES/filters.txt" <<'PYTHON'
import re
import sys

with open(sys.argv[2]) as test_list:
    suites = sorted({line.strip().split("/")[0] for line in test_list if line.startswith(sys.argv[1] + ".")})
if not suites:
    sys.exit(f"No Swift test suites found for {sys.argv[1]}")
for suite in suites:
    print("^" + re.escape(suite) + "/")
PYTHON

# AppKit changes process-wide run-loop state; each suite needs a fresh test host.
while IFS= read -r suite_filter; do
  zsh "$ROOT/Scripts/swift-test.sh" "$@" --skip-build --filter "$suite_filter"
done < "$SWIFT_TEST_SUITES/filters.txt"
