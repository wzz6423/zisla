#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEMPORARY_ROOT="$(mktemp -d "${TMPDIR%/}/zisla-build-app-toolchain-tests.XXXXXX")"
function cleanup() {
  [[ "$TEMPORARY_ROOT" == "${TMPDIR%/}/zisla-build-app-toolchain-tests."* ]] || return
  [[ -d "$TEMPORARY_ROOT" ]] && find "$TEMPORARY_ROOT" -depth -delete
}
trap cleanup EXIT

TEST_ROOT="$TEMPORARY_ROOT/project"
FAKE_BIN="$TEMPORARY_ROOT/bin"
CLT_DEVELOPER="$TEMPORARY_ROOT/CommandLineTools"
XCODE_APP="$TEMPORARY_ROOT/Xcode.app"
XCODE_DEVELOPER="$XCODE_APP/Contents/Developer"
CAPTURE_FILE="$TEMPORARY_ROOT/developer-directory.txt"

mkdir -p "$TEST_ROOT/Scripts" "$TEST_ROOT/Resources" "$FAKE_BIN" \
  "$XCODE_DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin" \
  "$XCODE_DEVELOPER/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
cp "$ROOT/Scripts/build-app.sh" "$TEST_ROOT/Scripts/build-app.sh"
touch "$XCODE_DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
touch "$XCODE_DEVELOPER/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"
chmod +x "$XCODE_DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
cp "$ROOT/Resources/Info.plist" "$TEST_ROOT/Resources/Info.plist"
print -r -- day > "$TEST_ROOT/Resources/AppIcon.icns"
print -r -- night > "$TEST_ROOT/Resources/AppIconNight.icns"

cat > "$FAKE_BIN/xcode-select" <<'SCRIPT'
#!/bin/zsh
print -r -- "$FAKE_CLT_DEVELOPER"
SCRIPT

cat > "$FAKE_BIN/mdfind" <<'SCRIPT'
#!/bin/zsh
print -r -- "$FAKE_XCODE_APP"
SCRIPT

cat > "$FAKE_BIN/swift" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
arguments=("$@")
scratch_path=""
[[ "$*" == *"-Xswiftc -DSWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE"* ]] || {
  print -u2 -r -- "missing hand-built app resource-bundle compile condition"
  exit 1
}
for (( index = 1; index <= ${#arguments[@]}; index += 1 )); do
  if [[ "${arguments[index]}" == "--scratch-path" ]]; then
    scratch_path="${arguments[index + 1]}"
    break
  fi
done
[[ -n "$scratch_path" ]] || {
  print -u2 -r -- "missing --scratch-path"
  exit 1
}
bin_directory="$scratch_path/out/Products/Release"
if [[ "$*" == *"--show-bin-path"* ]]; then
  print -r -- "$bin_directory"
else
  print -r -- "$DEVELOPER_DIR" > "$FAKE_CAPTURE_FILE"
  mkdir -p "$bin_directory"
  touch "$bin_directory/zisla"
  mkdir -p "$bin_directory/zisla_KeyboardKit.bundle"
fi
SCRIPT

cat > "$FAKE_BIN/lipo" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
arguments=("$@")
for (( index = 1; index <= ${#arguments[@]}; index += 1 )); do
  if [[ "${arguments[index]}" == "-output" ]]; then
    touch "${arguments[index + 1]}"
    exit 0
  fi
done
print -u2 -r -- "missing lipo output"
exit 1
SCRIPT

cat > "$FAKE_BIN/codesign" <<'SCRIPT'
#!/bin/zsh
if [[ "$*" == *"-dv"* ]]; then
  print -u2 -r -- "Signature=adhoc"
  print -u2 -r -- "TeamIdentifier=not set"
fi
exit 0
SCRIPT

chmod +x "$FAKE_BIN"/*

function expect_architecture_failure() {
  local architectures="$1"
  local expected_message="$2"
  local output

  if output="$(
    PATH="$FAKE_BIN:$PATH" \
      FAKE_CAPTURE_FILE="$CAPTURE_FILE" \
      FAKE_CLT_DEVELOPER="$CLT_DEVELOPER" \
      FAKE_XCODE_APP="$XCODE_APP" \
      BUILD_ARCHITECTURES="$architectures" \
      CODE_SIGN_IDENTITY=- \
      OUTPUT_DIRECTORY="$TEMPORARY_ROOT/invalid-output" \
      SIGNING_MODE=adhoc \
      "$TEST_ROOT/Scripts/build-app.sh" 2>&1
  )"; then
    print -u2 -r -- "FAIL: invalid architecture list '$architectures' was accepted"
    exit 1
  fi
  if [[ "$output" != *"$expected_message"* ]]; then
    print -u2 -r -- "FAIL: invalid architecture list '$architectures' reported the wrong error"
    print -u2 -r -- "expected message: $expected_message"
    print -u2 -r -- "actual:           $output"
    exit 1
  fi
}

expect_architecture_failure \
  "   " \
  "BUILD_ARCHITECTURES must contain at least one architecture"
expect_architecture_failure \
  "arm64e" \
  "unsupported architecture: arm64e"
expect_architecture_failure \
  "arm64 arm64" \
  "duplicate architecture: arm64"

(
  unset DEVELOPER_DIR
  PATH="$FAKE_BIN:$PATH" \
    FAKE_CAPTURE_FILE="$CAPTURE_FILE" \
    FAKE_CLT_DEVELOPER="$CLT_DEVELOPER" \
    FAKE_XCODE_APP="$XCODE_APP" \
    BUILD_ARCHITECTURES='arm64 x86_64' \
    CODE_SIGN_IDENTITY=- \
    OUTPUT_DIRECTORY="$TEMPORARY_ROOT/output" \
    SIGNING_MODE=adhoc \
    "$TEST_ROOT/Scripts/build-app.sh" >/dev/null
)

[[ "$(<"$CAPTURE_FILE")" == "$XCODE_DEVELOPER" ]] || {
  print -u2 -r -- "FAIL: build-app did not switch from Command Line Tools to full Xcode"
  exit 1
}
[[ -x "$TEMPORARY_ROOT/output/zisla.app/Contents/MacOS/zisla" ]] || {
  print -u2 -r -- "FAIL: build-app did not produce the app binary"
  exit 1
}
RELEASE_PLIST="$TEMPORARY_ROOT/output/zisla.app/Contents/Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$RELEASE_PLIST")" == "dev.wzz.zisla" ]] || {
  print -u2 -r -- "FAIL: release Bundle ID was not rendered"
  exit 1
}
[[ "$(plutil -extract CFBundleDisplayName raw -o - "$RELEASE_PLIST")" == "zisla" ]] || {
  print -u2 -r -- "FAIL: release display name was not rendered"
  exit 1
}
[[ "$(plutil -extract ZislaApplicationSupportDirectory raw -o - "$RELEASE_PLIST")" == "zisla" ]] || {
  print -u2 -r -- "FAIL: release application support directory was not rendered"
  exit 1
}
for architecture in arm64 x86_64; do
  [[ -f "$TEST_ROOT/.build/$architecture/out/Products/Release/zisla" ]] || {
    print -u2 -r -- "FAIL: build-app did not isolate $architecture build output"
    exit 1
  }
done

(
  PATH="$FAKE_BIN:$PATH" \
    FAKE_CAPTURE_FILE="$CAPTURE_FILE" \
    FAKE_CLT_DEVELOPER="$CLT_DEVELOPER" \
    FAKE_XCODE_APP="$XCODE_APP" \
    DEBUG_BUILD=true \
    BUILD_ARCHITECTURES=arm64 \
    CODE_SIGN_IDENTITY=- \
    OUTPUT_DIRECTORY="$TEMPORARY_ROOT/output" \
    "$TEST_ROOT/Scripts/build-app.sh" >/dev/null
)

DEBUG_APP="$TEMPORARY_ROOT/output/zisla-debug.app"
DEBUG_PLIST="$DEBUG_APP/Contents/Info.plist"
[[ -x "$DEBUG_APP/Contents/MacOS/zisla" ]] || {
  print -u2 -r -- "FAIL: debug build did not produce the app binary"
  exit 1
}
[[ -d "$TEMPORARY_ROOT/output/zisla.app" ]] || {
  print -u2 -r -- "FAIL: debug build removed the release app"
  exit 1
}
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$DEBUG_PLIST")" == "dev.wzz.zisla.debug" ]] || {
  print -u2 -r -- "FAIL: debug Bundle ID was not rendered"
  exit 1
}
[[ "$(plutil -extract CFBundleDisplayName raw -o - "$DEBUG_PLIST")" == "zisla-debug" ]] || {
  print -u2 -r -- "FAIL: debug display name was not rendered"
  exit 1
}
[[ "$(plutil -extract ZislaApplicationSupportDirectory raw -o - "$DEBUG_PLIST")" == "zisla-debug" ]] || {
  print -u2 -r -- "FAIL: debug application support directory was not rendered"
  exit 1
}
cmp -s "$TEST_ROOT/Resources/AppIconNight.icns" "$DEBUG_APP/Contents/Resources/AppIcon.icns" || {
  print -u2 -r -- "FAIL: debug build did not use the night icon"
  exit 1
}
cmp -s "$DEBUG_APP/Contents/Resources/AppIcon.icns" "$DEBUG_APP/Contents/Resources/AppIconNight.icns" || {
  print -u2 -r -- "FAIL: debug icon resources are inconsistent"
  exit 1
}

print -r -- "PASS: build-app identity, data, icon, and architecture isolation"
