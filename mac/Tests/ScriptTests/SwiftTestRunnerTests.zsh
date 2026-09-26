#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-swift-test-runner.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/results"

cat > "$TEST_ROOT/bin/swift" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
[[ "$1" == test && "$2" == --filter && "$3" == '^FixtureTests\.' ]]
[[ "$4" == --event-stream-output-path && "$6" == --event-stream-version && "$7" == 0 ]]
print -r -- "$5" > "$SWIFT_TEST_CAPTURE"
completed='{"version":0,"kind":"event","payload":{"kind":"testEnded"}}
{"version":0,"kind":"event","payload":{"kind":"runEnded"}}'
case "$SWIFT_TEST_FIXTURE" in
  success) print -r -- "$completed" > "$5" ;;
  missing) exit 0 ;;
  truncated) print -r -- '{"version":0,"kind":' > "$5" ;;
  empty) print -r -- '{"version":0,"kind":"event","payload":{"kind":"runEnded"}}' > "$5" ;;
  unfinished) print -r -- '{"version":0,"kind":"event","payload":{"kind":"testEnded"}}' > "$5" ;;
  nonzero)
    print -r -- "$completed" > "$5"
    exit 7
    ;;
esac
SCRIPT
chmod +x "$TEST_ROOT/bin/swift"

for fixture in success missing truncated empty unfinished nonzero; do
  result=0
  PATH="$TEST_ROOT/bin:$PATH" TMPDIR="$TEST_ROOT/results" \
    SWIFT_TEST_FIXTURE="$fixture" SWIFT_TEST_CAPTURE="$TEST_ROOT/result-path" \
    zsh "$ROOT/Scripts/swift-test.sh" --filter '^FixtureTests\.' \
    > "$TEST_ROOT/$fixture.log" 2>&1 || result=$?
  if [[ "$fixture" == success ]]; then
    [[ "$result" == 0 ]] || { cat "$TEST_ROOT/$fixture.log"; exit 1; }
  elif [[ "$fixture" == nonzero ]]; then
    [[ "$result" == 7 ]] || { print -u2 -- "Lost Swift's failure status: $result"; exit 1; }
  else
    [[ "$result" != 0 ]] || { print -u2 -- "Accepted incomplete or failing result: $fixture"; exit 1; }
  fi
  [[ ! -e "$(<"$TEST_ROOT/result-path")" ]] || { print -u2 -- "Leaked test results: $fixture"; exit 1; }
done

print -- 'PASS: Swift test results reject missing, truncated, empty, unfinished, and nonzero runs; temporary results are removed'
