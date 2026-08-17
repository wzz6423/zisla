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

print -r -- "PASS: $tests_run dev-service signing tests"
