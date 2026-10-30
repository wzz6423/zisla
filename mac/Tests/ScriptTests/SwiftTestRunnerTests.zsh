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
function='{"version":0,"kind":"test","payload":{"id":"FixtureTests.Suite/test()","kind":"function"}}'
run_started='{"version":0,"kind":"event","payload":{"kind":"runStarted"}}'
run_ended='{"version":0,"kind":"event","payload":{"kind":"runEnded"}}'
test_started='{"version":0,"kind":"event","payload":{"kind":"testStarted","testID":"FixtureTests.Suite/test()"}}'
test_ended='{"version":0,"kind":"event","payload":{"kind":"testEnded","testID":"FixtureTests.Suite/test()"}}'
test_skipped='{"version":0,"kind":"event","payload":{"kind":"testSkipped","testID":"FixtureTests.Suite/test()"}}'
completed="$function
$run_started
$test_started
$test_ended
$run_ended"
skipped="$function
$run_started
$test_skipped"
case "$SWIFT_TEST_FIXTURE" in
  skipped)
    print -r -- "$skipped" > "$5"
    print -r -- "$run_ended" >> "$5"
    ;;
  skipped-after-start)
    print -r -- "$function
$run_started
$test_started
$test_skipped
$run_ended" > "$5"
    ;;
  skipped-unfinished) print -r -- "$skipped" > "$5" ;;
  suite-skipped)
    print -r -- '{"version":0,"kind":"test","payload":{"id":"FixtureTests.Suite","kind":"suite"}}
{"version":0,"kind":"event","payload":{"kind":"runStarted"}}
{"version":0,"kind":"event","payload":{"kind":"testSkipped","testID":"FixtureTests.Suite"}}
{"version":0,"kind":"event","payload":{"kind":"runEnded"}}' > "$5"
    ;;
  unknown-skipped)
    print -r -- '{"version":0,"kind":"event","payload":{"kind":"runStarted"}}
{"version":0,"kind":"event","payload":{"kind":"testSkipped","testID":"FixtureTests.Unknown/test()"}}
{"version":0,"kind":"event","payload":{"kind":"runEnded"}}' > "$5"
    ;;
  success) print -r -- "$completed" > "$5" ;;
  success-with-empty-targets)
    print -r -- "$run_started
$run_ended
$completed
$run_started
$run_ended" > "$5"
    ;;
  unfinished-with-empty-targets)
    print -r -- "$function
$run_started
$test_started
$test_ended
$run_started
$run_ended
$run_started
$run_ended" > "$5"
    ;;
  completed-before-unfinished)
    print -r -- "$completed
$function
$run_started
$test_started
$test_ended" > "$5"
    ;;
  partial-functions)
    print -r -- "$function
{\"version\":0,\"kind\":\"test\",\"payload\":{\"id\":\"FixtureTests.Suite/second()\",\"kind\":\"function\"}}
$run_started
$test_started
{\"version\":0,\"kind\":\"event\",\"payload\":{\"kind\":\"testStarted\",\"testID\":\"FixtureTests.Suite/second()\"}}
$test_ended
$run_ended" > "$5"
    ;;
  partial-suite)
    print -r -- "$function
$run_started
{\"version\":0,\"kind\":\"event\",\"payload\":{\"kind\":\"testStarted\",\"testID\":\"FixtureTests.Suite\"}}
$test_started
$test_ended
$run_ended" > "$5"
    ;;
  missing-start) print -r -- "$function
$test_ended
$run_ended" > "$5" ;;
  unexpected-end) print -r -- "$completed
$run_ended" > "$5" ;;
  missing) exit 0 ;;
  truncated) print -r -- '{"version":0,"kind":' > "$5" ;;
  empty) print -r -- "$run_started
$run_ended" > "$5" ;;
  unfinished) print -r -- "$function
$run_started
$test_started
$test_ended" > "$5" ;;
  nonzero)
    print -r -- "$completed" > "$5"
    exit 7
    ;;
esac
SCRIPT
chmod +x "$TEST_ROOT/bin/swift"

for launch in swiftpm runner; do
  arguments=(--filter '^FixtureTests\.')
  if [[ "$launch" == runner ]]; then
    arguments=(--runner "$TEST_ROOT/bin/swift" test "${arguments[@]}")
  fi
for fixture in success skipped skipped-after-start success-with-empty-targets unfinished-with-empty-targets completed-before-unfinished partial-functions partial-suite missing-start unexpected-end skipped-unfinished suite-skipped unknown-skipped missing truncated empty unfinished nonzero; do
  result=0
  PATH="$TEST_ROOT/bin:$PATH" TMPDIR="$TEST_ROOT/results" \
    SWIFT_TEST_FIXTURE="$fixture" SWIFT_TEST_CAPTURE="$TEST_ROOT/result-path" \
    zsh "$ROOT/Scripts/swift-test.sh" "${arguments[@]}" \
    > "$TEST_ROOT/$fixture.log" 2>&1 || result=$?
  if [[ "$fixture" == success || "$fixture" == skipped || "$fixture" == skipped-after-start || "$fixture" == success-with-empty-targets ]]; then
    [[ "$result" == 0 ]] || { cat "$TEST_ROOT/$fixture.log"; exit 1; }
  elif [[ "$fixture" == nonzero ]]; then
    [[ "$result" == 7 ]] || { print -u2 -- "Lost Swift's failure status: $result"; exit 1; }
  else
    [[ "$result" != 0 ]] || { print -u2 -- "Accepted incomplete or failing result: $fixture"; exit 1; }
  fi
  [[ ! -e "$(<"$TEST_ROOT/result-path")" ]] || { print -u2 -- "Leaked test results: $fixture"; exit 1; }
done
done

if TMPDIR="$TEST_ROOT/results" zsh "$ROOT/Scripts/swift-test.sh" --runner > "$TEST_ROOT/missing-runner.log" 2>&1; then
  print -u2 -- 'Accepted a missing test runner executable'
  exit 1
fi
[[ -z "$(find "$TEST_ROOT/results" -mindepth 1 -print)" ]] || { print -u2 -- 'Leaked results after invalid runner input'; exit 1; }

print -- 'PASS: 37 SwiftPM/direct-runner cases preserve complete target runs, test completion, failure status, and temporary result cleanup'
