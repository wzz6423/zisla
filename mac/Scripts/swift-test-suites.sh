#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TARGET="${1:?comma-separated Swift test targets are required}"
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
targets = target.split(",")
try:
    workers = int(os.environ.get("SWIFT_TEST_WORKERS", "1"))
    if workers < 1:
        raise ValueError()
except ValueError:
    sys.exit("SWIFT_TEST_WORKERS must be a positive integer")
try:
    shard_count = int(os.environ.get("SWIFT_TEST_SHARD_COUNT", "1"))
    shard_index = int(os.environ.get("SWIFT_TEST_SHARD_INDEX", "0"))
    if shard_count < 1 or not 0 <= shard_index < shard_count:
        raise ValueError()
except ValueError:
    sys.exit("SWIFT_TEST_SHARD_COUNT must be positive and SWIFT_TEST_SHARD_INDEX must be between zero and count - 1")

def interrupted(signum, _frame):
    sys.exit(128 + signum)

signal.signal(signal.SIGINT, interrupted)
signal.signal(signal.SIGTERM, interrupted)

def selected_tests(output):
    return {re.sub(r"/[^/]+\.swift:\d+:\d+$", "", line.strip())
            for line in output.splitlines() if line.startswith(tuple(name + "." for name in targets))}

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
    for name in targets:
        if not any(test.startswith(name + ".") for test in expected):
            sys.exit(f"No Swift test suites found for {name}")

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

    # Measured on the macos-26 runner; run the longest work first to avoid a serial tail.
    durations = {
        "ZislaKitTests.EmojiNameCatalogTests": 221,
        "ZislaKitTests.ClipboardAssistantSmartActionsTests": 114,
        "ZislaKitTests.ClipboardAssistantShellCommandTests": 98,
        "ZislaKitTests.ClipboardAssistantDetectorTests": 85,
        "ZislaKitTests.ClipboardAssistantNumericActionsTests": 63,
        "ZislaKitTests.ClipboardAssistantCurrencyDetectionTests": 55,
        "ZislaTests.LongCaptureRealWorldTests/realWorldMultiFrameSessionReproducesThePage()": 63,
        "ZislaTests.LongCaptureRealWorldTests/realWorldSmallScrollStepsStillStitchExactly()": 53,
        "ZislaTests.LongCaptureRealWorldTests/realWorldRepeatingListRowsDoNotShiftTheSeam()": 21,
        "ZislaTests.LongCaptureRealWorldTests/realWorldRepeatingListWithChangingScrollStepsKeepsExactAlignment()": 19,
        "ZislaTests.LongCaptureRealWorldTests/realWorldTableIgnoresScrollJitter()": 38,
        "ZislaTests.LongCaptureRealWorldTests/realWorldTinyScrollDoesNotStartADuplicateCapture(frameHeight:)": 92,
        "ZislaTests.LongCaptureRealWorldTests/realWorldPeriodicRowsDoNotTurnJitterIntoThePreviousScrollStep(delta:)": 29,
        "ZislaTests.LongCaptureRealWorldTests/realWorldStationaryRepeatingListIsNeverAppended()": 8,
        "ZislaTests.LongCaptureRealWorldTests/realWorldStationaryPageIsNeverAppended()": 8,
        "ZislaTests.LongCaptureRealWorldTests/realWorldStationaryPageWithTickingContentIsNeverAppended()": 44,
        "ZislaTests.LongCaptureRealWorldTests/realWorldSparseChatPageStitchesExactly()": 26,
        "ZislaTests.LongCaptureRealWorldTests/realWorldChatSmallScrollIsNotDiscardedAsUnchanged()": 4,
        "ZislaTests.LongCaptureRealWorldTests/realWorldStationarySparseChatFrameIsNotAppended()": 4,
        "ZislaTests.LongCaptureRealWorldTests/realWorldRetinaSparseChatPageStitchesExactly()": 33,
    }
    tasks = {}
    for suite, command in suites.items():
        if suite == "ZislaTests.LongCaptureRealWorldTests":
            # Each scenario owns its model and images; separate hosts keep MainActor work parallel.
            for test in discovered:
                if test.startswith(suite + "/"):
                    tasks[test] = (command, durations.get(test, 32))
        else:
            tasks[suite] = (command, durations.get(suite, 1))
    if shard_count > len(tasks):
        sys.exit("SWIFT_TEST_SHARD_COUNT exceeds the number of test tasks")
    shards = [[] for _ in range(shard_count)]
    loads = [0] * shard_count
    for name in sorted(tasks, key=lambda name: (-tasks[name][1], name)):
        index = min(range(shard_count), key=lambda index: (loads[index], index))
        shards[index].append(name)
        loads[index] += tasks[name][1]
    pending = iter(enumerate(shards[shard_index]))
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
                     "DYLD_LIBRARY_PATH=" + environment["DYLD_LIBRARY_PATH"], *tasks[suite][0],
                     "--filter", "^" + re.escape(suite) + r"(?:/|$)"],
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
