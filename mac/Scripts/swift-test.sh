#!/bin/zsh
set -euo pipefail

SWIFT_TEST_RESULTS="$(mktemp -d "${TMPDIR:-/tmp}/zisla-swift-test.XXXXXX")"
trap 'find "$SWIFT_TEST_RESULTS" -depth -delete' EXIT

# SwiftPM can exit successfully before Swift Testing finishes its AppKit run loop.
runner=(swift test)
if [[ "${1:-}" == --runner ]]; then
  shift
  runner=("${1:?--runner requires an executable}")
  shift
fi
"${runner[@]}" "$@" --event-stream-output-path "$SWIFT_TEST_RESULTS/events.jsonl" --event-stream-version 0
python3 - "$SWIFT_TEST_RESULTS/events.jsonl" <<'PYTHON'
import json
import sys

try:
    with open(sys.argv[1]) as stream:
        events = [json.loads(line) for line in stream]
except (OSError, json.JSONDecodeError) as error:
    sys.exit(f"Swift Testing did not produce a complete event stream: {error}")

functions = {event["payload"]["id"] for event in events
             if event["kind"] == "test" and event["payload"]["kind"] == "function"}
active = False
pending = set()
nonempty = False
for event in events:
    if event["kind"] != "event":
        continue
    payload = event["payload"]
    kind = payload["kind"]
    if kind == "runStarted":
        if active:
            sys.exit("Swift Testing started another target before completing the previous run")
        active = True
    elif kind == "testStarted":
        pending.add(payload["testID"])
    elif kind in ("testEnded", "testSkipped"):
        test = payload["testID"]
        pending.discard(test)
        nonempty |= test in functions
    elif kind == "runEnded":
        if not active or pending:
            sys.exit("Swift Testing ended a target with unfinished tests")
        active = False
if active or not nonempty:
    sys.exit("Swift Testing exited before completing a nonempty test run")
PYTHON
