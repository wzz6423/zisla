#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SERVICE_LABEL="dev.wzz.zisla.debug"
USER_ID="$(id -u)"
SERVICE_DOMAIN="gui/$USER_ID"
SERVICE_TARGET="$SERVICE_DOMAIN/$SERVICE_LABEL"
APP_DIRECTORY="$ROOT/dist"
APP="$APP_DIRECTORY/zisla.app"
APP_BINARY="$APP/Contents/MacOS/zisla"
ADAPTER_SCRIPT="$APP/Contents/Resources/MediaRemoteAdapter/mediaremote-adapter.pl"
SOURCE_ADAPTER_SCRIPT="$ROOT/Resources/MediaRemoteAdapter/mediaremote-adapter.pl"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$SERVICE_LABEL.plist"
OUT_LOG="$HOME/Library/Logs/zisla-debug.log"
ERROR_LOG="$HOME/Library/Logs/zisla-debug-error.log"

function fail() {
  print -u2 -r -- "错误：$1"
  exit 1
}

function matching_pids() {
  local pid
  local process_command

  for pid in ${(f)"$(pgrep -x zisla 2>/dev/null || true)"}; do
    process_command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    [[ "$process_command" == "$APP_BINARY"* ]] && print -r -- "$pid"
  done

  for pid in ${(f)"$(pgrep -x perl 2>/dev/null || true)"}; do
    process_command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$process_command" == *"$ADAPTER_SCRIPT"* || "$process_command" == *"$SOURCE_ADAPTER_SCRIPT"* ]]; then
      print -r -- "$pid"
    fi
  done
}

function collect_matching_pids() {
  local -a pids

  pids=("${(@f)$(matching_pids)}")
  [[ ${#pids[@]} -eq 1 && -z "${pids[1]}" ]] && pids=()
  print -rl -- "${pids[@]}"
}

function service_is_loaded() {
  launchctl print "$SERVICE_TARGET" >/dev/null 2>&1
}

function wait_for_service_to_unload() {
  local attempt

  for ((attempt = 0; attempt < 50; attempt++)); do
    service_is_loaded || return 0
    sleep 0.1
  done

  return 1
}

function wait_for_processes_to_exit() {
  local attempt
  local -a pids

  for ((attempt = 0; attempt < 50; attempt++)); do
    pids=("${(@f)$(collect_matching_pids)}")
    [[ ${#pids[@]} -eq 1 && -z "${pids[1]}" ]] && pids=()
    (( ${#pids[@]} == 0 )) && return 0
    sleep 0.1
  done

  return 1
}

function wait_for_service_to_run() {
  local attempt
  local -a pids

  for ((attempt = 0; attempt < 50; attempt++)); do
    pids=("${(@f)$(collect_matching_pids)}")
    [[ ${#pids[@]} -eq 1 && -z "${pids[1]}" ]] && pids=()
    if service_is_loaded && (( ${#pids[@]} > 0 )); then
      print -r -- "${pids[1]}"
      return 0
    fi
    sleep 0.1
  done

  return 1
}

function stop_service() {
  local -a pids

  if service_is_loaded; then
    launchctl bootout "$SERVICE_TARGET" || fail "无法卸载调试服务 $SERVICE_LABEL"
    wait_for_service_to_unload || fail "调试服务 $SERVICE_LABEL 仍在运行"
  fi

  pids=("${(@f)$(collect_matching_pids)}")
  [[ ${#pids[@]} -eq 1 && -z "${pids[1]}" ]] && pids=()
  (( ${#pids[@]} > 0 )) && kill -TERM "${pids[@]}"

  if ! wait_for_processes_to_exit; then
    pids=("${(@f)$(collect_matching_pids)}")
    [[ ${#pids[@]} -eq 1 && -z "${pids[1]}" ]] && pids=()
    (( ${#pids[@]} > 0 )) && kill -KILL "${pids[@]}"
    wait_for_processes_to_exit || fail "zisla 调试进程未能退出"
  fi

  rm -f "$LAUNCH_AGENT" "$OUT_LOG" "$ERROR_LOG"
  rm -rf "$APP"
  rmdir "$APP_DIRECTORY" 2>/dev/null || true
  print -r -- "zisla 调试服务已停止，运行时资源已清理。"
}

function start_service() {
  local pid

  stop_service
  "$ROOT/Scripts/build-app.sh"
  [[ -x "$APP_BINARY" ]] || fail "构建未生成 zisla.app 可执行文件"

  mkdir -p "${LAUNCH_AGENT:h}" "${OUT_LOG:h}"
  rm -f "$LAUNCH_AGENT"
  plutil -create xml1 "$LAUNCH_AGENT"
  plutil -insert Label -string "$SERVICE_LABEL" "$LAUNCH_AGENT"
  plutil -insert Program -string "$APP_BINARY" "$LAUNCH_AGENT"
  plutil -insert ProcessType -string Interactive "$LAUNCH_AGENT"
  plutil -insert RunAtLoad -bool true "$LAUNCH_AGENT"
  plutil -insert KeepAlive -bool true "$LAUNCH_AGENT"
  plutil -insert ThrottleInterval -integer 10 "$LAUNCH_AGENT"
  plutil -insert StandardOutPath -string "$OUT_LOG" "$LAUNCH_AGENT"
  plutil -insert StandardErrorPath -string "$ERROR_LOG" "$LAUNCH_AGENT"
  plutil -lint "$LAUNCH_AGENT" >/dev/null

  launchctl bootstrap "$SERVICE_DOMAIN" "$LAUNCH_AGENT"
  pid="$(wait_for_service_to_run)" || fail "调试服务未能启动，请检查 $ERROR_LOG"
  print -r -- "zisla 调试服务已启动（PID $pid）。停止请执行：make stop"
}

case "${1:-}" in
  run)
    start_service
    ;;
  stop)
    stop_service
    ;;
  *)
    print -u2 -r -- "用法：$0 {run|stop}"
    exit 64
    ;;
esac
