#!/bin/zsh
set -euo pipefail

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
OUT_LOG="$TEST_TEMPORARY_ROOT/logs/stdout.log"
ERROR_LOG="$TEST_TEMPORARY_ROOT/logs/stderr.log"

function security() { print -u2 -- "Unexpected security call"; return 1 }
function service_is_loaded() { return 1 }
function matching_app_pids() { return 0 }
function wait_for_processes_to_exit() { return 0 }
function wait_for_service_to_run() { print -r -- "4242" }
function launchctl() {
  [[ "$#" == 3 && "$1" == bootstrap && "$2" == "$SERVICE_DOMAIN" && "$3" == "$LAUNCH_AGENT" ]] || return 1
  python3 - "$LAUNCH_AGENT" "$APP_BINARY" >> "$CAPTURE_FILE" <<'PYTHON'
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    agent = plistlib.load(source)
value = agent["EnvironmentVariables"]["ZISLA_FIRST"]
assert type(value) is str, "ZISLA_FIRST must be a plist string"
assert agent["ProgramArguments"] == [sys.argv[2]], "launchd must launch the app binary directly"
assert agent["Label"] == "dev.wzz.zisla.debug", "debug service label must stay stable"
print(f"plist first={value}")
PYTHON
}

[[ "$#" == 1 && "$1" == run ]] || exit 1
print -r -- "script first=${ZISLA_FIRST-unset} signing=${SIGNING_MODE-unset}" >> "$CAPTURE_FILE"
start_service
SCRIPT

cat > "$TEST_ROOT/mac/Scripts/build-app.sh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
print -r -- "build debug=$DEBUG_BUILD signing=$SIGNING_MODE identity=$CODE_SIGN_IDENTITY" >> "$CAPTURE_FILE"
mkdir -p "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS"
print -r -- '#!/bin/zsh' > "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS/zisla"
chmod +x "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS/zisla"
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
  local expected="script first=$input_value signing=dev
build debug=true signing=dev identity=TEST_STABLE_IDENTITY
plist first=$plist_value"

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

print -r -- "PASS: $tests_run first-launch service tests"
