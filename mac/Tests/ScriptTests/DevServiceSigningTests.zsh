#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
source "$ROOT/Scripts/dev-service.sh"

tests_run=0

function expect_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  (( tests_run += 1 ))
  if [[ "$actual" != "$expected" ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "expected: $expected"
    print -u2 -r -- "actual:   $actual"
    exit 1
  fi
}

function expect_failure_containing() {
  local expected_message="$1"
  local description="$2"
  local output

  (( tests_run += 1 ))
  if output="$(resolve_dev_code_sign_identity 2>&1)"; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "expected command to fail, got: $output"
    exit 1
  fi
  if [[ "$output" != *"$expected_message"* ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "missing message: $expected_message"
    print -u2 -r -- "actual:          $output"
    exit 1
  fi
}

function expect_contains() {
  local actual="$1"
  local expected="$2"
  local description="$3"

  (( tests_run += 1 ))
  if [[ "$actual" != *"$expected"* ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "missing: $expected"
    print -u2 -r -- "actual:  $actual"
    exit 1
  fi
}

function expect_not_contains() {
  local actual="$1"
  local unexpected="$2"
  local description="$3"

  (( tests_run += 1 ))
  if [[ "$actual" == *"$unexpected"* ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "unexpected: $unexpected"
    print -u2 -r -- "actual:     $actual"
    exit 1
  fi
}

function security() {
  print -r -- '  1) AUTO_IDENTITY "Apple Development: Developer One (TEAMONE)"'
  print -r -- '  2) OTHER_IDENTITY "Developer ID Application: Developer One (TEAMONE)"'
  print -r -- '     2 valid identities found'
}

CODE_SIGN_IDENTITY="EXPLICIT_IDENTITY"
expect_equal \
  "EXPLICIT_IDENTITY" \
  "$(resolve_dev_code_sign_identity)" \
  "explicit stable identity is preserved"

unset CODE_SIGN_IDENTITY
expect_equal \
  "AUTO_IDENTITY" \
  "$(resolve_dev_code_sign_identity)" \
  "first Apple Development identity is selected"

CODE_SIGN_IDENTITY="-"
expect_failure_containing \
  "调试服务不能使用 ad-hoc 签名" \
  "ad-hoc identity is rejected"

unset CODE_SIGN_IDENTITY
function security() {
  print -r -- '     0 valid identities found'
}
expect_failure_containing \
  "未找到 Apple Development 证书" \
  "missing stable identity stops the development launch"

run_command="$(make -n -C "${ROOT:h}" run)"
expect_contains \
  "$run_command" \
  "SIGNING_MODE=dev mac/Scripts/dev-service.sh run" \
  "make run forces development signing"

update_command="$(make -n -C "${ROOT:h}" update)"
expect_contains \
  "$update_command" \
  "SIGNING_MODE=dev mac/Scripts/dev-service.sh run" \
  "make update forces development signing"
expect_equal \
  "$run_command" \
  "$update_command" \
  "make run and make update use the same launch command"

launch_agent_arguments="$(grep -n 'ProgramArguments' "$ROOT/Scripts/dev-service.sh")"
expect_contains \
  "$launch_agent_arguments" \
  'ProgramArguments.0 -string "$APP_BINARY"' \
  "debug service launchd target is the main app binary"
expect_not_contains \
  "$launch_agent_arguments" \
  "/usr/bin/open" \
  "debug service launches the app directly instead of keeping open alive"

events_file="${TMPDIR%/}/zisla-dev-service-events-$$"
trap '[[ -f "$events_file" ]] && find "$events_file" -delete' EXIT

function service_is_loaded() { return 1 }
function matching_app_pids() { print -r -- "4242" }
function collect_matching_pids() { print -r -- "4242" }
function wait_for_processes_to_exit() { return 0 }
function osascript() { print -r -- "quit" >> "$events_file" }
function kill() { print -r -- "kill $*" >> "$events_file" }
function rm() { return 0 }
function rmdir() { return 0 }

stop_service >/dev/null
stop_events="$(<"$events_file")"
expect_contains \
  "$stop_events" \
  "quit" \
  "stopping the debug service requests graceful app termination"
expect_not_contains \
  "$stop_events" \
  "kill -TERM" \
  "graceful app termination avoids SIGTERM fallback"

print -r -- "PASS: $tests_run dev-service signing tests"
