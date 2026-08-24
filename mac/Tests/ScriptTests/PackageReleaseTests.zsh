#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEMPORARY_ROOT="$(mktemp -d "${TMPDIR%/}/zisla-package-release-tests.XXXXXX")"
function cleanup() {
  [[ "$TEMPORARY_ROOT" == "${TMPDIR%/}/zisla-package-release-tests."* ]] || return
  [[ -d "$TEMPORARY_ROOT" ]] && find "$TEMPORARY_ROOT" -depth -delete
}
trap cleanup EXIT

TEST_ROOT="$TEMPORARY_ROOT/project"
FAKE_BIN="$TEMPORARY_ROOT/bin"
mkdir -p "$TEST_ROOT/Scripts" "$FAKE_BIN"
cp "$ROOT/Scripts/package-release.sh" "$TEST_ROOT/Scripts/package-release.sh"

cat > "$TEST_ROOT/Scripts/build-app.sh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
print -r -- "$BUILD_ARCHITECTURES" > "$CAPTURE_FILE"
mkdir -p "$OUTPUT_DIRECTORY/zisla.app/Contents/MacOS"
touch "$OUTPUT_DIRECTORY/zisla.app/Contents/MacOS/zisla"
plutil -create xml1 "$OUTPUT_DIRECTORY/zisla.app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string dev.wzz.zisla "$OUTPUT_DIRECTORY/zisla.app/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string zisla "$OUTPUT_DIRECTORY/zisla.app/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$VERSION" "$OUTPUT_DIRECTORY/zisla.app/Contents/Info.plist"
plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$OUTPUT_DIRECTORY/zisla.app/Contents/Info.plist"
plutil -insert ZislaDefaultUpdateChannel -string "$UPDATE_CHANNEL" "$OUTPUT_DIRECTORY/zisla.app/Contents/Info.plist"
SCRIPT
chmod +x "$TEST_ROOT/Scripts/build-app.sh"

cat > "$FAKE_BIN/ditto" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
destination="${@: -1}"
if [[ "$destination" == *.zip ]]; then
  mkdir -p "${destination:h}"
  touch "$destination"
else
  mkdir -p "$destination"
fi
SCRIPT

cat > "$FAKE_BIN/shasum" <<'SCRIPT'
#!/bin/zsh
print -r -- "checksum  ${@: -1}"
SCRIPT

cat > "$FAKE_BIN/hdiutil" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
case "$1" in
  create)
    touch "${@: -1}"
    ;;
  attach)
    print -r -- "/dev/disk999 Apple_HFS zisla"
    ;;
  detach)
    ;;
  convert)
    output_index=${argv[(i)-o]}
    touch "$argv[$(( output_index + 1 ))]"
    ;;
  verify)
    touch "$HDIUTIL_VERIFY_CAPTURE"
    ;;
esac
SCRIPT

cat > "$FAKE_BIN/osascript" <<'SCRIPT'
#!/bin/zsh
cat >/dev/null
SCRIPT

cat > "$FAKE_BIN/sync" <<'SCRIPT'
#!/bin/zsh
exit 0
SCRIPT

cat > "$FAKE_BIN/codesign" <<'SCRIPT'
#!/bin/zsh
exit 0
SCRIPT

chmod +x "$FAKE_BIN"/*

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

function expect_file() {
  local path="$1"
  local description="$2"

  (( tests_run += 1 ))
  if [[ ! -f "$path" ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "missing: $path"
    exit 1
  fi
}

function expect_architecture_failure() {
  local architectures="$1"
  local expected_message="$2"
  local output

  (( tests_run += 1 ))
  if output="$(
    PATH="$FAKE_BIN:$PATH" \
      VERSION=0.1.3 \
      BUILD_NUMBER=5 \
      UPDATE_CHANNEL=release \
      CODE_SIGN_IDENTITY=- \
      BUILD_ARCHITECTURES="$architectures" \
      ARCHIVE_DIRECTORY="$TEMPORARY_ROOT/invalid" \
      CAPTURE_FILE="$TEMPORARY_ROOT/invalid/architectures.txt" \
      "$TEST_ROOT/Scripts/package-release.sh" 2>&1
  )"; then
    print -u2 -r -- "FAIL: unsupported architecture '$architectures' was accepted"
    exit 1
  fi
  if [[ "$output" != *"$expected_message"* ]]; then
    print -u2 -r -- "FAIL: unsupported architecture '$architectures' reported the wrong error"
    print -u2 -r -- "expected message: $expected_message"
    print -u2 -r -- "actual:           $output"
    exit 1
  fi
}

for architecture in arm64 x86_64 universal; do
  case_directory="$TEMPORARY_ROOT/$architecture"
  capture_file="$case_directory/architectures.txt"
  verify_capture="$case_directory/dmg-verified"
  mkdir -p "$case_directory"

  if [[ "$architecture" == universal ]]; then
    build_architectures="arm64 x86_64"
  else
    build_architectures="$architecture"
  fi

  PATH="$FAKE_BIN:$PATH" \
    VERSION=0.1.3 \
    BUILD_NUMBER=5 \
    UPDATE_CHANNEL=release \
    CODE_SIGN_IDENTITY=- \
    BUILD_ARCHITECTURES="$build_architectures" \
    ARCHIVE_DIRECTORY="$case_directory" \
    CAPTURE_FILE="$capture_file" \
    HDIUTIL_VERIFY_CAPTURE="$verify_capture" \
    "$TEST_ROOT/Scripts/package-release.sh" >/dev/null

  expect_equal \
    "$build_architectures" \
    "$(<"$capture_file")" \
    "$architecture build preserves BUILD_ARCHITECTURES"
  expect_file \
    "$case_directory/zisla-v0.1.3-macOS-${architecture}.zip" \
    "$architecture ZIP uses the architecture suffix"
  expect_file \
    "$case_directory/zisla-v0.1.3-macOS-${architecture}.zip.sha256" \
    "$architecture checksum uses the architecture suffix"
  expect_file \
    "$case_directory/zisla-v0.1.3-macOS-${architecture}.dmg" \
    "$architecture DMG uses the architecture suffix"
  expect_file \
    "$case_directory/zisla-v0.1.3-macOS-${architecture}.dmg.sha256" \
    "$architecture DMG checksum uses the architecture suffix"
  expect_file \
    "$verify_capture" \
    "$architecture DMG is verified before release"
done

function expect_debug_bundle_failure() {
  local case_directory="$TEMPORARY_ROOT/debug-bundle"
  local output

  (( tests_run += 1 ))
  mkdir -p "$case_directory/zisla.app/Contents"
  plutil -create xml1 "$case_directory/zisla.app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string dev.wzz.zisla.debug "$case_directory/zisla.app/Contents/Info.plist"
  plutil -insert CFBundleDisplayName -string zisla-debug "$case_directory/zisla.app/Contents/Info.plist"
  if output="$(
    PATH="$FAKE_BIN:$PATH" \
      VERSION=0.1.3 \
      BUILD_NUMBER=5 \
      UPDATE_CHANNEL=release \
      SKIP_BUILD=true \
      ARCHIVE_DIRECTORY="$case_directory" \
      "$TEST_ROOT/Scripts/package-release.sh" 2>&1
  )"; then
    print -u2 -r -- "FAIL: debug bundle was accepted for release packaging"
    exit 1
  fi
  if [[ "$output" != *"release package contains a debug or unknown app identity"* ]]; then
    print -u2 -r -- "FAIL: debug bundle reported the wrong release identity error"
    print -u2 -r -- "$output"
    exit 1
  fi
}

expect_debug_bundle_failure

function expect_metadata_mismatch_failure() {
  local case_directory="$TEMPORARY_ROOT/metadata-mismatch"
  local output

  (( tests_run += 1 ))
  mkdir -p "$case_directory/zisla.app/Contents"
  plutil -create xml1 "$case_directory/zisla.app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string dev.wzz.zisla "$case_directory/zisla.app/Contents/Info.plist"
  plutil -insert CFBundleDisplayName -string zisla "$case_directory/zisla.app/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string 0.1.5 "$case_directory/zisla.app/Contents/Info.plist"
  plutil -insert CFBundleVersion -string 11 "$case_directory/zisla.app/Contents/Info.plist"
  plutil -insert ZislaDefaultUpdateChannel -string release "$case_directory/zisla.app/Contents/Info.plist"
  if output="$(
    PATH="$FAKE_BIN:$PATH" \
      VERSION=0.1.6 \
      BUILD_NUMBER=12 \
      UPDATE_CHANNEL=release \
      SKIP_BUILD=true \
      ARCHIVE_DIRECTORY="$case_directory" \
      "$TEST_ROOT/Scripts/package-release.sh" 2>&1
  )"; then
    print -u2 -r -- "FAIL: mismatched release metadata was accepted"
    exit 1
  fi
  if [[ "$output" != *"release package metadata does not match"* ]]; then
    print -u2 -r -- "FAIL: metadata mismatch reported the wrong error"
    print -u2 -r -- "$output"
    exit 1
  fi
}

expect_metadata_mismatch_failure

expect_architecture_failure \
  "arm64 arm64" \
  "unsupported architecture combination: arm64 arm64"
expect_architecture_failure \
  "arm64e" \
  "unsupported architecture: arm64e"

function expect_version_failure() {
  local version="$1"
  local expected_message="$2"
  local output

  (( tests_run += 1 ))
  if output="$(
    PATH="$FAKE_BIN:$PATH" \
      VERSION="$version" \
      BUILD_NUMBER=5 \
      UPDATE_CHANNEL=release \
      CODE_SIGN_IDENTITY=- \
      BUILD_ARCHITECTURES=arm64 \
      ARCHIVE_DIRECTORY="$TEMPORARY_ROOT/invalid-version" \
      CAPTURE_FILE="$TEMPORARY_ROOT/invalid-version/architectures.txt" \
      "$TEST_ROOT/Scripts/package-release.sh" 2>&1
  )"; then
    print -u2 -r -- "FAIL: invalid VERSION '$version' was accepted"
    exit 1
  fi
  if [[ "$output" != *"$expected_message"* ]]; then
    print -u2 -r -- "FAIL: invalid VERSION '$version' reported the wrong error"
    print -u2 -r -- "expected message: $expected_message"
    print -u2 -r -- "actual:           $output"
    exit 1
  fi
}

expect_version_failure \
  "1.2.3/../../escape" \
  "VERSION must be a semantic version"

print -r -- "PASS: $tests_run package-release tests"
