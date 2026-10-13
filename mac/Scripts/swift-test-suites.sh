#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TARGET="${1:?a Swift test target is required}"
shift
exec python3 - "$ROOT" "$TARGET" "$@" <<'PYTHON'
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

root, target, *arguments = sys.argv[1:]
try:
    workers = int(os.environ.get("SWIFT_TEST_WORKERS", "1"))
    if workers < 1:
        raise ValueError()
except ValueError:
    sys.exit("SWIFT_TEST_WORKERS must be a positive integer")

def interrupted(signum, _frame):
    sys.exit(128 + signum)

signal.signal(signal.SIGINT, interrupted)
signal.signal(signal.SIGTERM, interrupted)

def selected_tests(output):
    return {re.sub(r"/[^/]+\.swift:\d+:\d+$", "", line.strip())
            for line in output.splitlines() if line.startswith(target + ".")}

def stop_workers(workers):
    for process, _suite, _output in workers:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            # Darwin can report EPERM when an owned group contains only zombies.
            pass
    deadline = time.monotonic() + 5
    for process, _suite, output in workers:
        while True:
            process.poll()
            try:
                os.killpg(process.pid, 0)
                if time.monotonic() >= deadline:
                    os.killpg(process.pid, signal.SIGKILL)
                    break
            except (ProcessLookupError, PermissionError):
                break
            time.sleep(0.05)
        process.wait()
        output.close()

def capture(command, environment=None):
    with tempfile.TemporaryFile(mode="w+") as output:
        process = subprocess.Popen(command, env=environment, stdout=output, start_new_session=True)
        try:
            result = process.wait()
            if result:
                sys.exit(result if result > 0 else 128 - result)
            output.seek(0)
            return output.read()
        finally:
            stop_workers([(process, None, output)])

with tempfile.TemporaryDirectory(prefix="zisla-swift-test-suites.") as temporary:
    scratch = Path(temporary)
    expected = selected_tests(capture(["swift", "test", *arguments, "list"]))
    if not expected:
        sys.exit(f"No Swift test suites found for {target}")

    build_arguments = [argument for argument in arguments if argument != "--skip-build"]
    binary_directory = Path(capture(["swift", "build", *build_arguments, "--show-bin-path"]).strip())
    swift = Path(capture(["xcrun", "--find", "swift"]).strip())
    helper = swift.parent.parent / "libexec/swift/pm/swiftpm-testing-helper"
    platform = Path(capture(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"]).strip())
    environment = dict(os.environ,
        DYLD_FRAMEWORK_PATH=os.pathsep.join(str(platform / "Developer/Library" / directory)
            for directory in ("Frameworks", "PrivateFrameworks")),
        DYLD_LIBRARY_PATH=str(platform / "Developer/usr/lib"))
    suites = {}
    discovered = set()
    for bundle in sorted(binary_directory.glob("*.xctest")):
        binary = bundle / "Contents/MacOS" / bundle.stem
        command = [str(helper), "--test-bundle-path", str(binary), "--testing-library", "swift-testing"]
        tests = selected_tests(capture(command + ["--list-tests"], environment))
        for suite in {test.split("/")[0] for test in tests}:
            if suite in suites:
                sys.exit(f"Swift suite appears in multiple test bundles: {suite}")
            suites[suite] = command
        discovered.update(tests)
    if discovered != expected:
        sys.exit(f"Swift test discovery mismatch; missing={sorted(expected - discovered)}, unexpected={sorted(discovered - expected)}")

    pending = iter(enumerate(sorted(suites)))
    running = {}
    exhausted = False
    try:
        while running or not exhausted:
            while not exhausted and len(running) < workers:
                item = next(pending, None)
                if item is None:
                    exhausted = True
                    break
                index, suite = item
                work = scratch / str(index)
                (work / "home").mkdir(parents=True)
                (work / "tmp").mkdir()
                suite_environment = dict(environment, HOME=str(work / "home"),
                    CFFIXED_USER_HOME=str(work / "home"), TMPDIR=str(work / "tmp") + "/")
                output = (work / "output.log").open("w")
                # SwiftPM locks its scratch path even with --skip-build; the helper only loads the built bundle.
                # SIP strips DYLD variables when zsh starts, so restore them after the system shell handoff.
                process = subprocess.Popen(
                    ["zsh", str(Path(root) / "Scripts/swift-test.sh"), "--runner", "/usr/bin/env",
                     "DYLD_FRAMEWORK_PATH=" + environment["DYLD_FRAMEWORK_PATH"],
                     "DYLD_LIBRARY_PATH=" + environment["DYLD_LIBRARY_PATH"], *suites[suite],
                     "--filter", "^" + re.escape(suite) + "/"],
                    env=suite_environment, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
                running[process.pid] = (process, suite, output)
            if running:
                pid, status = os.wait()
                process, suite, output = running[pid]
                process.returncode = os.waitstatus_to_exitcode(status)
                output.close()
                print(f"Swift suite: {suite}", flush=True)
                with open(output.name) as log:
                    shutil.copyfileobj(log, sys.stdout)
                sys.stdout.flush()
                if process.returncode:
                    sys.exit(process.returncode if process.returncode > 0 else 128 - process.returncode)
                stop_workers([running[pid]])
                del running[pid]
    finally:
        stop_workers(running.values())
PYTHON
