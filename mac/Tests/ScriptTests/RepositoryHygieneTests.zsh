#!/bin/zsh
set -euo pipefail

MAC_ROOT="${0:A:h:h:h}"
REPOSITORY_ROOT="${MAC_ROOT:h}"
TEMPORARY_ROOT="$(mktemp -d "${TMPDIR%/}/zisla-repository-hygiene-tests.XXXXXX")"
function cleanup() {
  [[ "$TEMPORARY_ROOT" == "${TMPDIR%/}/zisla-repository-hygiene-tests."* ]] || return
  [[ -d "$TEMPORARY_ROOT" ]] && find "$TEMPORARY_ROOT" -depth -delete
}
trap cleanup EXIT

TEST_ROOT="$TEMPORARY_ROOT/repository"
SCRIPT="$TEST_ROOT/.github/scripts/check-repository-hygiene.sh"
mkdir -p "$TEST_ROOT/.github/scripts" \
  "$TEST_ROOT/mac/Vendor/MediaRemoteAdapter.framework" \
  "$TEST_ROOT/mac/Vendor/Sparkle.xcframework/macos/Sparkle.framework"
cp "$REPOSITORY_ROOT/.github/scripts/check-repository-hygiene.sh" "$SCRIPT"
chmod +x "$SCRIPT"

print -r -- adapter > "$TEST_ROOT/mac/Vendor/MediaRemoteAdapter.framework/MediaRemoteAdapter"
print -r -- sparkle > "$TEST_ROOT/mac/Vendor/Sparkle.xcframework/macos/Sparkle.framework/Sparkle"

git -C "$TEST_ROOT" init -q
git -C "$TEST_ROOT" config user.email tests@zisla.local
git -C "$TEST_ROOT" config user.name "Zisla Tests"
git -C "$TEST_ROOT" add .

tests_run=0

(( tests_run += 1 ))
if ! output="$(cd "$TEST_ROOT" && "$SCRIPT" 2>&1)"; then
  print -u2 -r -- "FAIL: known vendored frameworks were rejected"
  print -u2 -r -- "$output"
  exit 1
fi

mkdir -p "$TEST_ROOT/mac/Vendor/Unexpected.framework"
print -r -- unexpected > "$TEST_ROOT/mac/Vendor/Unexpected.framework/Unexpected"
git -C "$TEST_ROOT" add .

(( tests_run += 1 ))
if output="$(cd "$TEST_ROOT" && "$SCRIPT" 2>&1)"; then
  print -u2 -r -- "FAIL: an unknown vendored framework bypassed repository hygiene"
  exit 1
fi
if [[ "$output" != *"Forbidden generated build artifact: mac/Vendor/Unexpected.framework/Unexpected"* ]]; then
  print -u2 -r -- "FAIL: the unknown vendored framework reported the wrong violation"
  print -u2 -r -- "$output"
  exit 1
fi

git -C "$TEST_ROOT" rm -qrf mac/Vendor/Unexpected.framework
mkdir -p "$TEST_ROOT/mac/Resources/MediaRemoteAdapter.framework"
print -r -- stale > "$TEST_ROOT/mac/Resources/MediaRemoteAdapter.framework/MediaRemoteAdapter"
git -C "$TEST_ROOT" add .

(( tests_run += 1 ))
if output="$(cd "$TEST_ROOT" && "$SCRIPT" 2>&1)"; then
  print -u2 -r -- "FAIL: the stale Resources framework bypassed repository hygiene"
  exit 1
fi
if [[ "$output" != *"Forbidden generated build artifact: mac/Resources/MediaRemoteAdapter.framework/MediaRemoteAdapter"* ]]; then
  print -u2 -r -- "FAIL: the stale Resources framework reported the wrong violation"
  print -u2 -r -- "$output"
  exit 1
fi

print -r -- "PASS: $tests_run repository hygiene tests"
