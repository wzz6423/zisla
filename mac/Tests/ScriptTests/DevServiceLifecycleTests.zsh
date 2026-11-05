#!/bin/zsh
set -euo pipefail

MAC_ROOT="${0:A:h:h:h}"
python3 - "$MAC_ROOT/Scripts/dev-service.sh" <<'PYTHON'
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile

child_script = r'''
set -euo pipefail
source "$SOURCE_DEV_SERVICE"
print -r -- "lock=$SERVICE_LOCK"
SERVICE_LOCK="$TEST_SERVICE_LOCK"
function start_service() {
  print -r -- entered
  read -r response
  return "$TEST_ACTION_RESULT"
}
function stop_service() { start_service }
function zsystem() {
  if [[ "$TEST_EXPECT_CONTENTION" == 1 && "$1" == flock ]]; then
    local probe_status=0
    builtin zsystem flock -t 0.1 "$SERVICE_LOCK" || probe_status=$?
    if [[ "$probe_status" != 2 ]]; then
      print -u2 -r -- "Expected the other worktree to hold the lock, got $probe_status"
      return 1
    fi
    print -r -- queued
  fi
  builtin zsystem "$@"
}
print -r -- ready
run_service_command "$TEST_ACTION"
'''

def expect_line(process, expected=None):
    readable, _, _ = select.select([process.stdout], [], [], 5)
    assert readable, f"Service did not report {expected!r} within five seconds"
    actual = process.stdout.readline()
    if expected is not None:
        assert actual == expected, f"Expected {expected!r}, got {actual!r}"
    return actual

with tempfile.TemporaryDirectory(prefix="zisla-dev-service-lifecycle.") as temporary:
    environment = dict(os.environ, SOURCE_DEV_SERVICE=sys.argv[1], TEST_EXPECT_CONTENTION="0")
    source = Path(sys.argv[1]).read_text()
    cases = [("run", "run", 0), ("run", "stop", 0), ("stop", "run", 0),
        ("run", "run", 1), ("run", "run", -15)]
    for index, (first_action, second_action, result) in enumerate(cases):
        case_root = Path(temporary) / str(index)
        first_script = case_root / "first/mac/Scripts/dev-service.sh"
        second_script = case_root / "second/mac/Scripts/dev-service.sh"
        for script in [first_script, second_script]:
            script.parent.mkdir(parents=True)
            script.write_text(source)
        lock = case_root / "runtime/locks/service.lock"
        case_environment = dict(environment, TEST_SERVICE_LOCK=str(lock))
        processes = []
        try:
            first = subprocess.Popen(["zsh", "-c", child_script],
                env=dict(case_environment, SOURCE_DEV_SERVICE=str(first_script),
                    TEST_ACTION=first_action, TEST_ACTION_RESULT=str(max(0, result))),
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
            processes.append(first)
            shared_lock = expect_line(first)
            assert shared_lock.startswith(b"lock=")
            expect_line(first, b"ready\n")
            expect_line(first, b"entered\n")
            probe = subprocess.run(["zsh", "-c",
                'zmodload zsh/system; zsystem flock -t 0.1 "$TEST_SERVICE_LOCK"'],
                env=case_environment, capture_output=True, timeout=5)
            assert probe.returncode == 2, (
                f"{first_action} must hold the shared service lock throughout its lifecycle, "
                f"got lock probe exit {probe.returncode}: {probe.stderr.decode()}")

            second = subprocess.Popen(["zsh", "-c", child_script],
                env=dict(case_environment, SOURCE_DEV_SERVICE=str(second_script),
                    TEST_ACTION=second_action, TEST_ACTION_RESULT="0", TEST_EXPECT_CONTENTION="1"),
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
            processes.append(second)
            assert expect_line(second) == shared_lock, "Different worktrees must use the same user-level lock"
            expect_line(second, b"ready\n")
            expect_line(second, b"queued\n")
            if result < 0:
                first.terminate()
            else:
                first.stdin.write(b"release\n")
                first.stdin.flush()
            assert first.wait(timeout=5) == result
            expect_line(second, b"entered\n")
            second.stdin.write(b"release\n")
            second.stdin.flush()
            assert second.wait(timeout=5) == 0, "The queued action must acquire the released lock"
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
                process.stdin.close()
                process.stdout.close()

    invalid_lock = Path(temporary) / "invalid" / "service.lock"
    invalid = subprocess.run(["zsh", "-c", child_script],
        env=dict(environment, TEST_SERVICE_LOCK=str(invalid_lock), TEST_ACTION="invalid", TEST_ACTION_RESULT="0"),
        capture_output=True, timeout=5)
    assert invalid.returncode == 64
    assert not invalid_lock.exists(), "Invalid commands must not create runtime resources"

    blocked_cache = Path(temporary) / "blocked" / "locks"
    blocked_cache.parent.mkdir(parents=True)
    blocked_cache.write_text("not a directory")
    blocked = subprocess.run(["zsh", "-c", child_script],
        env=dict(environment, TEST_SERVICE_LOCK=str(blocked_cache / "service.lock"), TEST_ACTION="run", TEST_ACTION_RESULT="0"),
        input=b"release\n", capture_output=True, timeout=5)
    assert blocked.returncode != 0
    assert b"entered\n" not in blocked.stdout, "Lock setup failure must leave the running service untouched"

print(f"PASS: {len(cases) + 2} dev-service lifecycle tests")
PYTHON
