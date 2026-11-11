#!/bin/zsh
set -euo pipefail
unset ZISLA_FRESH_START ZISLA_DEBUG_BUNDLE_ID CFFIXED_USER_HOME ZISLA_DEBUG_SHOW_CHARGE_TO_FULL

MAC_ROOT="${0:A:h:h:h}"
TEMPORARY_ROOT="$(mktemp -d "${TMPDIR%/}/zisla-first-launch-tests.XXXXXX")"
function cleanup() {
  [[ "$TEMPORARY_ROOT" == "${TMPDIR%/}/zisla-first-launch-tests."* ]] || return
  [[ -d "$TEMPORARY_ROOT" ]] && find "$TEMPORARY_ROOT" -depth -delete
}
trap cleanup EXIT

TEST_ROOT="$TEMPORARY_ROOT/repository"
CAPTURE_FILE="$TEMPORARY_ROOT/invocations.txt"
mkdir -p "$TEST_ROOT/mac/Scripts"
cp "${MAC_ROOT:h}/Makefile" "$TEST_ROOT/Makefile"

# Source the real service but keep every runtime resource and command isolated.
cat > "$TEST_ROOT/mac/Scripts/dev-service.sh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
source "$SOURCE_DEV_SERVICE"
ROOT="${0:A:h:h}"
APP_DIRECTORY="$TEST_TEMPORARY_ROOT/app"
APP="$APP_DIRECTORY/zisla-debug.app"
APP_BINARY="$APP/Contents/MacOS/zisla"
LAUNCH_AGENT="$TEST_TEMPORARY_ROOT/LaunchAgents/$SERVICE_LABEL.plist"
SERVICE_LOCK="$TEST_TEMPORARY_ROOT/cache/service.lock"
OUT_LOG="$TEST_TEMPORARY_ROOT/logs/stdout.log"
ERROR_LOG="$TEST_TEMPORARY_ROOT/logs/stderr.log"

function security() { print -u2 -- "Unexpected security call"; return 1 }
function mktemp() {
  [[ "${TEST_PROFILE_CREATION_FAILURE:-0}" != 1 ]] || return 1
  command mktemp "$@"
}
function service_is_loaded() { return 1 }
function matching_app_pids() { return 0 }
function wait_for_processes_to_exit() { return 0 }
function wait_for_service_to_run() { print -r -- "4242" }
function launchctl() {
  [[ "$#" == 3 && "$1" == bootstrap && "$2" == "$SERVICE_DOMAIN" && "$3" == "$LAUNCH_AGENT" ]] || return 1
  python3 - "$LAUNCH_AGENT" "$APP_BINARY" "$APP/Contents/Info.plist" "$TEST_TEMPORARY_ROOT" >> "$CAPTURE_FILE" <<'PYTHON'
import plistlib
import os
import sys
from pathlib import Path

with open(sys.argv[1], "rb") as source:
    agent = plistlib.load(source)
value = agent["EnvironmentVariables"]["ZISLA_FIRST"]
assert type(value) is str, "ZISLA_FIRST must be a plist string"
assert agent["EnvironmentVariables"]["ZISLA_DEBUG_SHOW_CHARGE_TO_FULL"] == (os.environ.get("ZISLA_DEBUG_SHOW_CHARGE_TO_FULL") or "0"), "Charge action display override must reach the launchd environment"
assert agent["ProgramArguments"] == [sys.argv[2]], "launchd must launch the app binary directly"
assert agent["Label"] == "dev.wzz.zisla.debug", "debug service label must stay stable"
with open(sys.argv[3], "rb") as source:
    bundle = plistlib.load(source)["CFBundleIdentifier"]
home = agent["EnvironmentVariables"].get("CFFIXED_USER_HOME", "none")
if home != "none":
    assert Path(home).is_dir(), "Fresh profile must exist before launch"
    assert Path(home).parent == Path(sys.argv[4]) / "cache", "Profile must use the controlled cache directory"
    assert bundle == "dev.wzz.zisla.debug.fresh." + Path(home).suffix[1:], "Preferences and home must identify the same fresh launch"
    assert not any(Path(home).iterdir()), "Fresh launch must not copy existing data"
assert agent["KeepAlive"] is True, "Automatic restarts must keep the same launch environment"
print(f"plist first={value} home={home} bundle={bundle}")
PYTHON
}

[[ "$#" == 1 && "$1" == run ]] || exit 1
print -r -- "script first=${ZISLA_FIRST-unset} fresh=${ZISLA_FRESH_START-unset} signing=${SIGNING_MODE-unset}" >> "$CAPTURE_FILE"
run_service_command "$@"
SCRIPT

cat > "$TEST_ROOT/mac/Scripts/build-app.sh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
print -r -- "build debug=$DEBUG_BUILD signing=$SIGNING_MODE identity=$CODE_SIGN_IDENTITY bundle=${ZISLA_DEBUG_BUNDLE_ID-unset}" >> "$CAPTURE_FILE"
mkdir -p "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS"
print -r -- '#!/bin/zsh' > "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS/zisla"
chmod +x "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS/zisla"
plutil -create xml1 "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "${ZISLA_DEBUG_BUNDLE_ID:-dev.wzz.zisla.debug}" "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/Info.plist"
SCRIPT
chmod +x "$TEST_ROOT/mac/Scripts/dev-service.sh" "$TEST_ROOT/mac/Scripts/build-app.sh"

export CAPTURE_FILE
export SOURCE_DEV_SERVICE="$MAC_ROOT/Scripts/dev-service.sh"
export TEST_TEMPORARY_ROOT="$TEMPORARY_ROOT"
export CODE_SIGN_IDENTITY=TEST_STABLE_IDENTITY
tests_run=0

function expect_launch() {
  local description="$1"
  local input_value="$2"
  local plist_value="$3"
  shift 3
  local actual
  local expected="script first=$input_value fresh=0 signing=dev
build debug=true signing=dev identity=TEST_STABLE_IDENTITY bundle=dev.wzz.zisla.debug
plist first=$plist_value home=none bundle=dev.wzz.zisla.debug"

  : > "$CAPTURE_FILE"
  "$@" >/dev/null
  actual="$(<"$CAPTURE_FILE")"
  (( tests_run += 1 ))
  if [[ "$actual" != "$expected" ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "expected: $expected"
    print -u2 -r -- "actual:   $actual"
    exit 1
  fi
}

for target in run update; do
  expect_launch "$target forwards environment 1" 1 1 \
    env -u MAKEFLAGS -u MFLAGS ZISLA_FIRST=1 make -C "$TEST_ROOT" "$target"
  expect_launch "$target forwards command-line 1" 1 1 \
    env -u MAKEFLAGS -u MFLAGS -u ZISLA_FIRST make -C "$TEST_ROOT" "$target" ZISLA_FIRST=1
  expect_launch "$target forwards explicit 0" 0 0 \
    env -u MAKEFLAGS -u MFLAGS -u ZISLA_FIRST make -C "$TEST_ROOT" "$target" ZISLA_FIRST=0
  expect_launch "$target defaults to 0" 0 0 \
    env -u MAKEFLAGS -u MFLAGS -u ZISLA_FIRST make -C "$TEST_ROOT" "$target"
  expect_launch "$target enables before reset" 1 1 \
    env -u MAKEFLAGS -u MFLAGS ZISLA_FIRST=1 make -C "$TEST_ROOT" "$target"
  expect_launch "$target resets previous 1 to default 0" 0 0 \
    env -u MAKEFLAGS -u MFLAGS -u ZISLA_FIRST make -C "$TEST_ROOT" "$target"
  for invalid_value in '' 01 true 2; do
    expect_launch "$target normalizes '$invalid_value' to 0" "$invalid_value" 0 \
      env -u MAKEFLAGS -u MFLAGS -u ZISLA_FIRST make -C "$TEST_ROOT" "$target" "ZISLA_FIRST=$invalid_value"
  done
done

for target in run update; do
  expect_launch "$target forwards charge display environment" 0 0 \
    env -u MAKEFLAGS -u MFLAGS ZISLA_DEBUG_SHOW_CHARGE_TO_FULL=1 make -C "$TEST_ROOT" "$target"
  expect_launch "$target forwards charge display make override" 0 0 \
    env -u MAKEFLAGS -u MFLAGS -u ZISLA_DEBUG_SHOW_CHARGE_TO_FULL \
      make -C "$TEST_ROOT" "$target" ZISLA_DEBUG_SHOW_CHARGE_TO_FULL=1
  expect_launch "$target clears previous charge display override" 0 0 \
    env -u MAKEFLAGS -u MFLAGS -u ZISLA_DEBUG_SHOW_CHARGE_TO_FULL make -C "$TEST_ROOT" "$target"
  for value in '' 0 true 01 ' 1' '1 '; do
    expect_launch "$target preserves charge display value '$value' for the app to validate" 0 0 \
      env -u MAKEFLAGS -u MFLAGS "ZISLA_DEBUG_SHOW_CHARGE_TO_FULL=$value" make -C "$TEST_ROOT" "$target"
  done
done

function expect_fresh_launch() {
  local description="$1"
  shift
  : > "$CAPTURE_FILE"
  "$@" > "$TEMPORARY_ROOT/launch-output.txt"
  python3 - "$CAPTURE_FILE" "$TEMPORARY_ROOT/launch-output.txt" "$description" <<'PYTHON'
from pathlib import Path
import re
import sys

capture = Path(sys.argv[1]).read_text().splitlines()
assert len(capture) == 3, f"{sys.argv[3]}: expected one build and launch"
assert capture[0] == "script first=0 fresh=1 signing=dev", capture
bundle = capture[1].split("bundle=")[1]
assert re.fullmatch(r"dev\.wzz\.zisla\.debug\.fresh\.[A-Za-z0-9-]+", bundle), capture
assert capture[1] == f"build debug=true signing=dev identity=TEST_STABLE_IDENTITY bundle={bundle}", capture
assert capture[2].startswith("plist first=1 home="), "Fresh launch must force onboarding even with ZISLA_FIRST=0"
home = capture[2].split("home=")[1].split(" bundle=")[0]
assert home in Path(sys.argv[2]).read_text(), "Print the isolated profile location for the developer"
PYTHON
  (( tests_run += 1 ))
}

for target in run update; do
  expect_fresh_launch "$target accepts environment override" \
    env -u MAKEFLAGS -u MFLAGS ZISLA_FRESH_START=1 make -C "$TEST_ROOT" "$target"
  first_fresh_capture="$(<"$CAPTURE_FILE")"
  expect_fresh_launch "$target accepts make override" \
    env -u MAKEFLAGS -u MFLAGS make -C "$TEST_ROOT" "$target" ZISLA_FRESH_START=1 ZISLA_FIRST=0
  [[ "$(<"$CAPTURE_FILE")" != "$first_fresh_capture" ]] || {
    print -u2 -r -- "FAIL: repeated fresh runs must use different homes and preference domains"
    exit 1
  }
  (( tests_run += 1 ))
  expect_launch "$target restores regular debug identity and home" 0 0 \
    env -u MAKEFLAGS -u MFLAGS ZISLA_DEBUG_BUNDLE_ID=dev.wzz.zisla.debug.fresh.stale \
      make -C "$TEST_ROOT" "$target"
  for invalid_value in '' 0 01 true 2 ' 1' '1 '; do
    : > "$CAPTURE_FILE"
    env -u MAKEFLAGS -u MFLAGS "ZISLA_FRESH_START=$invalid_value" make -C "$TEST_ROOT" "$target" >/dev/null
    [[ "$(tail -n 1 "$CAPTURE_FILE")" == "plist first=0 home=none bundle=dev.wzz.zisla.debug" ]] || {
      print -u2 -r -- "FAIL: invalid fresh override '$invalid_value' must preserve the regular profile"
      exit 1
    }
    (( tests_run += 1 ))
  done
done

previous_agent="$(<"$TEMPORARY_ROOT/LaunchAgents/dev.wzz.zisla.debug.plist")"
previous_app="$(<"$TEMPORARY_ROOT/app/zisla-debug.app/Contents/Info.plist")"
: > "$CAPTURE_FILE"
if env -u MAKEFLAGS -u MFLAGS TEST_PROFILE_CREATION_FAILURE=1 ZISLA_FRESH_START=1 \
    make -C "$TEST_ROOT" run >/dev/null 2>&1; then
  print -u2 -r -- "FAIL: inability to create a profile must fail the fresh run"
  exit 1
fi
[[ "$(<"$CAPTURE_FILE")" == "script first=0 fresh=1 signing=dev" && \
  "$(<"$TEMPORARY_ROOT/LaunchAgents/dev.wzz.zisla.debug.plist")" == "$previous_agent" && \
  "$(<"$TEMPORARY_ROOT/app/zisla-debug.app/Contents/Info.plist")" == "$previous_app" ]] || {
  print -u2 -r -- "FAIL: profile creation failure must leave the existing service and app untouched"
  exit 1
}
(( tests_run += 1 ))

print -r -- "PASS: $tests_run first-launch service tests"
