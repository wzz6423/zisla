#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEMPORARY_ROOT="$(mktemp -d "${TMPDIR%/}/zisla-vendored-dependency-tests.XXXXXX")"
function cleanup() {
  [[ "$TEMPORARY_ROOT" == "${TMPDIR%/}/zisla-vendored-dependency-tests."* ]] || return
  [[ -d "$TEMPORARY_ROOT" ]] && find "$TEMPORARY_ROOT" -depth -delete
}
trap cleanup EXIT

tests_run=0

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

if ! dependency_graph="$({
  env \
    http_proxy=http://127.0.0.1:9 \
    https_proxy=http://127.0.0.1:9 \
    all_proxy=http://127.0.0.1:9 \
    swift package \
      --package-path "$ROOT" \
      --cache-path "$TEMPORARY_ROOT/cache" \
      --scratch-path "$TEMPORARY_ROOT/scratch" \
      --disable-sandbox \
      --disable-dependency-cache \
      show-dependencies --format text
} 2>&1)"; then
  print -u2 -r -- "FAIL: local dependencies could not resolve without network access"
  print -u2 -r -- "$dependency_graph"
  exit 1
fi

expect_contains \
  "$dependency_graph" \
  "zstd.swift<$ROOT/Vendor/zstd.swift@unspecified>" \
  "the dependency graph uses the vendored zstd.swift package"
expect_not_contains \
  "$dependency_graph" \
  "https://github.com/awxkee/zstd.swift" \
  "the dependency graph does not retain the remote zstd.swift URL"

print -r -- "PASS: $tests_run vendored dependency tests"
