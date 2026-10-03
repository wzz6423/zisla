#!/bin/zsh
set -euo pipefail

SWIFT_TEST_RESULTS="$(mktemp -d "${TMPDIR:-/tmp}/zisla-swift-test.XXXXXX")"
trap 'find "$SWIFT_TEST_RESULTS" -depth -delete' EXIT

# SwiftPM can exit successfully before Swift Testing finishes its AppKit run loop.
swift test "$@" --event-stream-output-path "$SWIFT_TEST_RESULTS/events.jsonl" --event-stream-version 0
python3 - "$SWIFT_TEST_RESULTS/events.jsonl" <<'PYTHON'
import json
import sys

try:
    with open(sys.argv[1]) as stream:
        events = [json.loads(line) for line in stream]
except (OSError, json.JSONDecodeError) as error:
    sys.exit(f"Swift Testing did not produce a complete event stream: {error}")

kinds = [event["payload"]["kind"] for event in events if event["kind"] == "event"]
functions = {event["payload"]["id"] for event in events
             if event["kind"] == "test" and event["payload"]["kind"] == "function"}
skipped_function = any(event["kind"] == "event"
                       and event["payload"]["kind"] == "testSkipped"
                       and event["payload"].get("testID") in functions for event in events)
if "runEnded" not in kinds or ("testEnded" not in kinds and not skipped_function):
    sys.exit("Swift Testing exited before completing a nonempty test run")
PYTHON
