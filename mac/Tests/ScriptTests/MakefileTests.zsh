#!/bin/zsh
set -euo pipefail

MAC_ROOT="${0:A:h:h:h}"
REPOSITORY_ROOT="${MAC_ROOT:h}"
TEMPORARY_ROOT="$(mktemp -d "${TMPDIR%/}/zisla-makefile-tests.XXXXXX")"
function cleanup() {
  [[ "$TEMPORARY_ROOT" == "${TMPDIR%/}/zisla-makefile-tests."* ]] || return
  [[ -d "$TEMPORARY_ROOT" ]] && find "$TEMPORARY_ROOT" -depth -delete
}
trap cleanup EXIT

TEST_ROOT="$TEMPORARY_ROOT/repository"
CAPTURE_FILE="$TEMPORARY_ROOT/target-invocations.txt"
mkdir -p "$TEST_ROOT/mac/Scripts"
cp "$REPOSITORY_ROOT/Makefile" "$TEST_ROOT/Makefile"

# The mock records whether release output still exists when the service stops so
# the test can prove `clean` stops the debug service before deleting artifacts.
cat > "$TEST_ROOT/mac/Scripts/dev-service.sh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
if [[ -e outputs ]]; then
  print -r -- "dev-service $1 outputs-present" >> "$CAPTURE_FILE"
else
  print -r -- "dev-service $1 outputs-removed" >> "$CAPTURE_FILE"
fi
SCRIPT

cat > "$TEST_ROOT/mac/Scripts/build-package.sh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
print -r -- "build-package" >> "$CAPTURE_FILE"
SCRIPT

chmod +x "$TEST_ROOT/mac/Scripts/dev-service.sh" "$TEST_ROOT/mac/Scripts/build-package.sh"

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

function expect_absent() {
  local target_path="$1"
  local description="$2"

  (( tests_run += 1 ))
  if [[ -e "$TEST_ROOT/$target_path" ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "still present: $target_path"
    exit 1
  fi
}

function expect_present() {
  local target_path="$1"
  local description="$2"

  (( tests_run += 1 ))
  if [[ ! -e "$TEST_ROOT/$target_path" ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "missing: $target_path"
    exit 1
  fi
}

ARTIFACT_FILES=(
  outputs/zisla-v0.1.3-macOS-universal.zip
  outputs/.staging/universal/zisla.app/Contents/Info.plist
  .impeccable/cache
  .playwright-cli/cache
  mac/dist/zisla-debug.app/Contents/Info.plist
  mac/.build/debug/zisla
  mac/.swiftpm/configuration/state
  mac/DerivedData/Build/product
  mac/.release-v0.1.3/universal/zisla.app/Contents/Info.plist
  Web/dist/index.html
  Web/.playwright/state
  Web/screenshots/home.png
)
ARTIFACT_ROOTS=(
  outputs .impeccable .playwright-cli
  mac/dist mac/.build mac/.swiftpm mac/DerivedData mac/.release-v0.1.3
  Web/dist Web/.playwright Web/screenshots
)
PRESERVED_FILES=(
  docs/notes/history-peak-axis.md
  mac/Docs/releasing.md
  mac/Sources/Zisla/main.swift
  Web/src/main.ts
)

# `path` is tied to PATH in zsh, so fixtures use a distinct loop variable.
for fixture_path in $ARTIFACT_FILES $PRESERVED_FILES; do
  mkdir -p "$TEST_ROOT/${fixture_path:h}"
  print -r -- fixture > "$TEST_ROOT/$fixture_path"
done

CAPTURE_FILE="$CAPTURE_FILE" make -C "$TEST_ROOT" clean >/dev/null

expect_equal \
  "dev-service stop outputs-present" \
  "$(<"$CAPTURE_FILE")" \
  "clean stops the debug service before removing build output"

for artifact_path in $ARTIFACT_ROOTS; do
  expect_absent "$artifact_path" "clean removes the $artifact_path artifacts"
done

for preserved_path in $PRESERVED_FILES; do
  expect_present "$preserved_path" "clean keeps the tracked file $preserved_path"
done

CAPTURE_FILE="$CAPTURE_FILE" make -C "$TEST_ROOT" build-package >/dev/null

expect_equal \
  "dev-service stop outputs-present
build-package" \
  "$(<"$CAPTURE_FILE")" \
  "build-package packages a release without touching the debug service"

print -r -- "PASS: $tests_run Makefile target tests"
