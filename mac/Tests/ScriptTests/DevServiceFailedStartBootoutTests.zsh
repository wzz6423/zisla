#!/bin/zsh
set -euo pipefail
unset ZISLA_FRESH_START ZISLA_DEBUG_BUNDLE_ID CFFIXED_USER_HOME ZISLA_DEBUG_AI_MODEL_USAGE ZISLA_DEBUG_SHOW_CHARGE_TO_FULL

MAC_ROOT="${0:A:h:h:h}"
TEMPORARY_ROOT="$(mktemp -d "${TMPDIR%/}/zisla-failed-start-bootout.XXXXXX")"
function cleanup() {
  [[ "$TEMPORARY_ROOT" == "${TMPDIR%/}/zisla-failed-start-bootout."* ]] || return
  [[ -d "$TEMPORARY_ROOT" ]] && find "$TEMPORARY_ROOT" -depth -delete
}
trap cleanup EXIT

TEST_ROOT="$TEMPORARY_ROOT/repository"
CAPTURE_FILE="$TEMPORARY_ROOT/launchctl.txt"
LOADED_FILE="$TEMPORARY_ROOT/service-loaded"
STDOUT_FILE="$TEMPORARY_ROOT/stdout.txt"
STDERR_FILE="$TEMPORARY_ROOT/stderr.txt"
mkdir -p "$TEST_ROOT/mac/Scripts"
cp "${MAC_ROOT:h}/Makefile" "$TEST_ROOT/Makefile"
print -r -- 0 > "$LOADED_FILE"
: > "$CAPTURE_FILE"

REAL_AGENT="$HOME/Library/LaunchAgents/dev.wzz.zisla.debug.plist"
REAL_ERROR_LOG="$HOME/Library/Logs/zisla-debug-error.log"
function snapshot() {
  local path="$1"
  if [[ -e "$path" ]]; then
    stat -f '%i %m %z' "$path"
  else
    print -r -- missing
  fi
}
real_agent_before="$(snapshot "$REAL_AGENT")"
real_error_log_before="$(snapshot "$REAL_ERROR_LOG")"

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
function service_is_loaded() { [[ "$(<"$LOADED_FILE")" == 1 ]] }
function matching_app_pids() { return 0 }
function wait_for_processes_to_exit() { return 0 }
function wait_for_service_to_unload() { if service_is_loaded; then return 1; fi }
function wait_for_service_to_run() { return 1 }
function launchctl() {
  if [[ "$#" == 3 && "$1" == bootstrap && "$2" == "$SERVICE_DOMAIN" && "$3" == "$LAUNCH_AGENT" ]]; then
    print -r -- 1 > "$LOADED_FILE"
    print -r -- "bootstrap $2 $3" >> "$CAPTURE_FILE"
    mkdir -p "${ERROR_LOG:h}"
    print -r -- "simulated crash" > "$ERROR_LOG"
    return 0
  fi
  if [[ "$#" == 2 && "$1" == bootout && "$2" == "$SERVICE_TARGET" ]]; then
    print -r -- 0 > "$LOADED_FILE"
    print -r -- "bootout $2" >> "$CAPTURE_FILE"
    return 0
  fi
  print -u2 -r -- "unexpected launchctl: $*"
  return 1
}

[[ "$#" == 1 && "$1" == run ]] || exit 1
run_service_command "$@"
SCRIPT

cat > "$TEST_ROOT/mac/Scripts/build-app.sh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
mkdir -p "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS"
print -r -- '#!/bin/zsh' > "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS/zisla"
chmod +x "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/MacOS/zisla"
plutil -create xml1 "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "${ZISLA_DEBUG_BUNDLE_ID:-dev.wzz.zisla.debug}" "$OUTPUT_DIRECTORY/zisla-debug.app/Contents/Info.plist"
SCRIPT
chmod +x "$TEST_ROOT/mac/Scripts/dev-service.sh" "$TEST_ROOT/mac/Scripts/build-app.sh"

export CAPTURE_FILE
export LOADED_FILE
export SOURCE_DEV_SERVICE="$MAC_ROOT/Scripts/dev-service.sh"
export TEST_TEMPORARY_ROOT="$TEMPORARY_ROOT"
export CODE_SIGN_IDENTITY=TEST_STABLE_IDENTITY

launch_status=0
env -u MAKEFLAGS -u MFLAGS make -C "$TEST_ROOT" run >"$STDOUT_FILE" 2>"$STDERR_FILE" || launch_status=$?

AGENT_PLIST="$TEMPORARY_ROOT/LaunchAgents/dev.wzz.zisla.debug.plist"
ERROR_LOG="$TEMPORARY_ROOT/logs/stderr.log"
APP_BINARY="$TEMPORARY_ROOT/app/zisla-debug.app/Contents/MacOS/zisla"
SERVICE_DOMAIN="gui/$(id -u)"
SERVICE_TARGET="$SERVICE_DOMAIN/dev.wzz.zisla.debug"
expected_capture="bootstrap $SERVICE_DOMAIN $AGENT_PLIST
bootout $SERVICE_TARGET"
expected_stderr="错误：调试服务未能启动，请检查 $ERROR_LOG"
expected_stdout="zisla 调试服务已停止，运行时资源已清理。"

function fail_test() {
  print -u2 -r -- "FAIL: $1"
  print -u2 -r -- "status: $launch_status"
  print -u2 -r -- "stdout: $(<"$STDOUT_FILE")"
  print -u2 -r -- "stderr: $(<"$STDERR_FILE")"
  print -u2 -r -- "launchctl: $(<"$CAPTURE_FILE")"
  print -u2 -r -- "loaded: $(<"$LOADED_FILE")"
  exit 1
}

[[ "$launch_status" != 0 ]] || fail_test "a failed wait after bootstrap must exit non-zero"
[[ "$(<"$STDERR_FILE")" == *"$expected_stderr"* ]] || fail_test "the failure must tell the developer to read the error log"
[[ "$(<"$STDERR_FILE")" != *unexpected\ launchctl* ]] || fail_test "launchctl stub rejected an unexpected command"
[[ "$(<"$CAPTURE_FILE")" == "$expected_capture" ]] || fail_test "bootstrap must be followed by bootout of SERVICE_TARGET"
[[ "$(<"$LOADED_FILE")" == 0 ]] || fail_test "the debug service must not stay loaded"
[[ -f "$ERROR_LOG" && "$(<"$ERROR_LOG")" == "simulated crash" ]] || fail_test "the crash log must remain after the failed start"
[[ -x "$APP_BINARY" ]] || fail_test "the built debug app must remain after the failed start"
[[ -f "$AGENT_PLIST" ]] || fail_test "the launch agent plist must remain for the developer to inspect"
[[ "$(plutil -extract KeepAlive raw -o - "$AGENT_PLIST")" == true ]] || fail_test "a failed start must not disable KeepAlive"
[[ "$(plutil -extract ThrottleInterval raw -o - "$AGENT_PLIST")" == 10 ]] || fail_test "a failed start must not change the launchd throttle"
[[ "$(plutil -extract StandardErrorPath raw -o - "$AGENT_PLIST")" == "$ERROR_LOG" ]] || fail_test "the retained log must be the plist error path"
[[ "$(<"$STDOUT_FILE")" == "$expected_stdout" ]] || fail_test "the failed start must not stop the service again or report success"
[[ "$(snapshot "$REAL_AGENT")" == "$real_agent_before" ]] || fail_test "the developer LaunchAgents file must stay untouched"
[[ "$(snapshot "$REAL_ERROR_LOG")" == "$real_error_log_before" ]] || fail_test "the developer error log must stay untouched"
[[ "$AGENT_PLIST" != "$REAL_AGENT" && "$ERROR_LOG" != "$REAL_ERROR_LOG" ]] || fail_test "the test must use an isolated temporary launch agent"

print -r -- "PASS: 1 failed-start bootout test"
