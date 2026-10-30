#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-swift-test-suites-tests.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

python3 - "$ROOT" "$TEST_ROOT" <<'PYTHON'
from pathlib import Path
import json
import os
import select
import shlex
import signal
import socket
import subprocess
import sys

root, test_root = map(Path, sys.argv[1:])
results = test_root / "results"
results.mkdir()
tools = test_root / "bin"
tools.mkdir()
helper = test_root / "toolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
helper.parent.mkdir(parents=True)
for name in ("Combined", "Duplicate"):
    binary = test_root / "build" / (name + ".xctest") / "Contents/MacOS" / name
    binary.parent.mkdir(parents=True)
    binary.touch()
(test_root / "empty-build").mkdir()

fake = r"""#!/usr/bin/env python3
from pathlib import Path
import json
import os
import re
import signal
import socket
import subprocess
import sys

root = Path(os.environ["SWIFT_TEST_FIXTURE_ROOT"])
mode = os.environ["SWIFT_TEST_MODE"]
args = sys.argv[1:]

def coordinate(record, orphan=False):
    with socket.socket(socket.AF_INET) as connection:
        connection.connect(("127.0.0.1", int(os.environ["SWIFT_TEST_COORDINATOR"])))
        if orphan:
            ready, child_ready = os.pipe()
            child = subprocess.Popen([sys.executable, "-c",
                "import os, signal, sys; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                "os.write(int(sys.argv[1]), b'R'); signal.pause()", str(child_ready)],
                pass_fds=(child_ready, connection.fileno()))
            os.close(child_ready)
            assert os.read(ready, 1) == b"R"
            os.close(ready)
            record["child_pid"] = child.pid
        connection.sendall((json.dumps(record) + "\n").encode())
        if connection.recv(1) == b"!":
            sys.exit(6)

tests = [
    "OtherTests.First/test()",
    "FixtureTestsExtra.First/test()",
    "FixtureTestsXFirst/test()",
    "FixtureTests.Third/test()",
    "FixtureTests.First/testOne()",
    "FixtureTests.First/Nested/testTwo()",
    "FixtureTests.FirstExtra/test()",
    "FixtureTests.Second/test()",
    "FixtureTests.First/testThree()",
    "FixtureTests.topLevel()/FixtureTests.swift:1:1",
]
if mode == "workflow":
    tests = [
        "ZislaCoreTests.ModelTests/test()",
        "ZislaKitTests.ServiceTests/test()",
        "ZislaTests.WiFiNetworkPanelViewTests/observedPowerKeepsItsColorAndToggleSemanticsInAnInactiveWindow()",
        "ZislaTests.FutureAppKitTests/test()",
        "ZislaTests.FutureAppKitTests/Nested/test()",
        "ZislaTests.FutureAppKitTestsExtra/test()",
        "ZislaTests.topLevel()/Tests.swift:1:1",
    ]
if mode == "long-budget":
    tests = ["FixtureTests.Long/test()"]
if mode in ("throughput", "throughput-failure"):
    tests = [
        "ZislaTests.AShortTests/test()",
        "ZislaTests.LongCaptureRealWorldTests/testOne()",
        "ZislaTests.LongCaptureRealWorldTests/testOneExtra()",
        "ZislaTests.LongCaptureRealWorldTests/testTwo(frameHeight:)",
        "ZislaTests.LongCaptureRealWorldTests/Nested/test()",
        "ZislaTests.LongCaptureRealWorldTests/realWorldTinyScrollDoesNotStartADuplicateCapture(frameHeight:)",
        "ZislaTests.LongCaptureRealWorldTests/realWorldRetinaSparseChatPageStitchesExactly()",
        "ZislaTests.LongCaptureRealWorldTestsExtra/testOne()",
        "ZislaTests.LongCaptureRealWorldTestsExtra/testTwo()",
        "ZislaKitTests.EmojiNameCatalogTests/testOne()",
        "ZislaKitTests.EmojiNameCatalogTests/testTwo()",
        "ZislaKitTests.ClipboardAssistantSmartActionsTests/test()",
        "ZislaKitTests.ClipboardAssistantShellCommandTests/test()",
        "ZislaKitTests.ClipboardAssistantDetectorTests/test()",
        "ZislaKitTests.ClipboardAssistantNumericActionsTests/test()",
        "ZislaKitTests.ClipboardAssistantCurrencyDetectionTests/test()",
    ]
if mode in ("smart-throughput", "smart-throughput-failure"):
    tests = [
        "ZislaKitTests.ClipboardAssistantSmartActionsTests/testOne()",
        "ZislaKitTests.ClipboardAssistantSmartActionsTests/testOneExtra()",
        "ZislaKitTests.ClipboardAssistantSmartActionsTests/testTwo(sample:)",
        "ZislaKitTests.ClipboardAssistantSmartActionsTests/Nested/test()",
        "ZislaKitTests.ClipboardAssistantSmartActionsTestsExtra/testOne()",
        "ZislaKitTests.ClipboardAssistantSmartActionsTestsExtra/testTwo()",
        "ZislaTests.OtherTests/test()",
    ]
is_swift = Path(sys.argv[0]).name == "swift"
if not is_swift:
    frameworks = os.environ["DYLD_FRAMEWORK_PATH"].split(os.pathsep)
    assert str(root / "platform/Developer/Library/Frameworks") in frameworks, "Test helper cannot resolve public XCTest frameworks"
    assert str(root / "platform/Developer/Library/PrivateFrameworks") in frameworks, "Test helper cannot resolve XCTestCore"
    assert os.environ["DYLD_LIBRARY_PATH"] == str(root / "platform/Developer/usr/lib")
if is_swift and args[0] == "build":
    assert "--skip-build" not in args
    if "--build-tests" in args:
        (root / "built").touch()
        with (root / "builds").open("a") as builds:
            builds.write("build\n")
    else:
        assert "--show-bin-path" in args
        print(root / ("empty-build" if mode == "no-bundles" else "build"))
    sys.exit(0)
if is_swift and args[0] == "test" and args[-1] == "list":
    if mode == "discovery-interrupted":
        coordinate(dict(pid=os.getpid()), orphan=True)
    if mode == "list-failure":
        sys.exit(5)
    if "--skip-build" in args:
        assert (root / "built").exists(), "Test discovery did not reuse a completed build"
    else:
        with (root / "builds").open("a") as builds:
            builds.write("build\n")
    if "--scratch-path" in args:
        assert args[args.index("--scratch-path") + 1] == str(root / "build with spaces")
    listed = tests[:3] if mode == "empty" else tests
    print("\n".join(re.sub(r"/[^/]+\.swift:\d+:\d+$", "", test) for test in listed))
    sys.exit(0)
if not is_swift and "--list-tests" in args:
    if mode == "helper-list-failure":
        sys.exit(9)
    binary = Path(args[args.index("--test-bundle-path") + 1])
    listed = tests[:3] if mode == "empty" else tests
    if binary.name == "Duplicate":
        listed = tests if mode == "duplicate-discovery" else []
    if mode == "missing-discovery":
        listed = [test for test in listed if "testOne" not in test]
    print("\n".join(listed))
    sys.exit(0)

selector = args[args.index("--filter") + 1]
selected = [test for test in tests if re.search(selector, test)]
assert selected, "An empty suite was launched"
assert len({test.split("/")[0] for test in selected}) == 1, "Suites share a test host"
assert "--skip" not in args
if is_swift:
    assert mode == "workflow" and "--skip-build" in args and (root / "built").exists()
else:
    assert os.environ["HOME"] == os.environ["CFFIXED_USER_HOME"]
    assert Path(os.environ["HOME"]).parent == Path(os.environ["TMPDIR"]).parent
    assert str(root / "results") in os.environ["HOME"]
record = dict(selected=selected, pid=os.getpid(), group=os.getpgrp(), home=os.environ["HOME"], tmp=os.environ["TMPDIR"])
with open(os.environ["SWIFT_TEST_CAPTURE"], "a") as capture:
    capture.write(json.dumps(record) + "\n")
if mode in ("timeout", "timeout-orphan"):
    print("LAST TEST: waiting for an injected media dependency", flush=True)
    coordinate(record, orphan=mode == "timeout-orphan")
if mode in ("parallel", "parallel-failure", "interrupted", "orphaned-worker", "orphaned-failure", "long-budget"):
    coordinate(record, orphan=mode in ("orphaned-worker", "orphaned-failure"))
if mode == "test-failure" and "Second" in selector:
    sys.exit(6)
if mode == "throughput-failure" and any("LongCaptureRealWorldTests/" in test for test in selected):
    sys.exit(6)
if mode == "smart-throughput-failure" and any("ClipboardAssistantSmartActionsTests/" in test for test in selected):
    sys.exit(6)
output = args[args.index("--event-stream-output-path") + 1]
with open(output, "w") as events:
    events.write(json.dumps({"kind": "event", "payload": {"kind": "runStarted"}, "version": 0}) + "\n")
    for test in selected:
        events.write(json.dumps({"kind": "test", "payload": {"kind": "function", "id": test}, "version": 0}) + "\n")
        for kind in ("testStarted", "testEnded"):
            events.write(json.dumps({"kind": "event", "payload": {"kind": kind, "testID": test}, "version": 0}) + "\n")
    events.write(json.dumps({"kind": "event", "payload": {"kind": "runEnded"}, "version": 0}) + "\n")
"""
for executable in (tools / "swift", helper):
    executable.write_text(fake.replace("#!/usr/bin/env python3", "#!" + sys.executable, 1))
    executable.chmod(0o755)
(tools / "xcrun").write_text("""#!/usr/bin/env python3
import os
from pathlib import Path
import sys
root = Path(os.environ["SWIFT_TEST_FIXTURE_ROOT"])
args = sys.argv[1:]
if args == ["--find", "swift"]:
    print(root / "toolchain/usr/bin/swift")
else:
    assert args == ["--sdk", "macosx", "--show-sdk-platform-path"]
    print(root / "platform")
""")
(tools / "xcrun").chmod(0o755)

expected = [
    "FixtureTests.First/Nested/testTwo()",
    "FixtureTests.First/testOne()",
    "FixtureTests.First/testThree()",
    "FixtureTests.FirstExtra/test()",
    "FixtureTests.Second/test()",
    "FixtureTests.Third/test()",
    "FixtureTests.topLevel()/FixtureTests.swift:1:1",
]
environment = dict(os.environ, PATH=str(tools) + ":" + os.environ["PATH"],
    TMPDIR=str(results), SWIFT_TEST_FIXTURE_ROOT=str(test_root))
environment.pop("SWIFT_TEST_SHARD_COUNT", None)
environment.pop("SWIFT_TEST_SHARD_INDEX", None)
environment.pop("SWIFT_TEST_SUITE_TIMEOUT", None)
command = ["zsh", str(root / "Scripts/swift-test-suites.sh"), "FixtureTests"]
checks = 0

def read_records(path):
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

def check_cleanup(records):
    assert not list(results.iterdir()), "Leaked suite results or isolated homes"
    for record in records:
        try:
            os.kill(record["pid"], 0)
        except ProcessLookupError:
            continue
        raise AssertionError(f"Test worker still running: {record['pid']}")

def run_case(mode, status, selected, workers=None, arguments=(), target="FixtureTests",
             shard_count=None, shard_index=None, suite_timeout=None):
    global checks
    capture = test_root / (mode + "-" + str(checks) + ".jsonl")
    case_environment = dict(environment, SWIFT_TEST_MODE=mode, SWIFT_TEST_CAPTURE=str(capture))
    if workers is None:
        case_environment.pop("SWIFT_TEST_WORKERS", None)
    else:
        case_environment["SWIFT_TEST_WORKERS"] = workers
    if shard_count is not None:
        case_environment["SWIFT_TEST_SHARD_COUNT"] = shard_count
    if shard_index is not None:
        case_environment["SWIFT_TEST_SHARD_INDEX"] = shard_index
    if suite_timeout is not None:
        case_environment["SWIFT_TEST_SUITE_TIMEOUT"] = suite_timeout
    result = subprocess.run(command[:-1] + [target] + list(arguments),
        env=case_environment,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15)
    assert result.returncode == status, f"{mode}: expected exit {status}, got {result.returncode}\n{result.stdout}"
    records = read_records(capture)
    actual = sorted(test for record in records for test in record["selected"])
    assert actual == sorted(selected), f"{mode}: missed or duplicated tests: {actual}"
    assert len({record["home"] for record in records}) == len(records), "Suites shared a preferences home"
    assert len({record["tmp"] for record in records}) == len(records), "Suites shared a temporary directory"
    check_cleanup(records)
    checks += 1
    return records

run_case("success", 0, expected)
run_case("success", 0, expected + ["OtherTests.First/test()"], target="FixtureTests,OtherTests")
run_case("success", 1, [], target="FixtureTests,MissingTests")
run_case("success", 1, [], target="FixtureTests,")
run_case("empty", 1, [])
run_case("list-failure", 5, [])
run_case("test-failure", 6, expected[:5])
run_case("no-bundles", 1, [])
run_case("helper-list-failure", 9, [])
run_case("missing-discovery", 1, [])
run_case("duplicate-discovery", 1, [])
(test_root / "built").touch()
run_case("success", 0, expected, arguments=("--skip-build", "--scratch-path", str(test_root / "build with spaces")))
for workers in ("0", "-1", "not-a-number", "1.5", "", "1; touch unexpected"):
    run_case("invalid-workers", 1, [], workers=workers)
run_case("success", 0, expected, suite_timeout="1")
for timeout in ("0", "-1", "not-a-number", "1.5", "", " 1", "1 ", "+1", "01", "1; touch unexpected"):
    run_case("invalid-timeout", 1, [], suite_timeout=timeout)

smart_tests = [
    "ZislaKitTests.ClipboardAssistantSmartActionsTests/testOne()",
    "ZislaKitTests.ClipboardAssistantSmartActionsTests/testOneExtra()",
    "ZislaKitTests.ClipboardAssistantSmartActionsTests/testTwo(sample:)",
    "ZislaKitTests.ClipboardAssistantSmartActionsTests/Nested/test()",
    "ZislaKitTests.ClipboardAssistantSmartActionsTestsExtra/testOne()",
    "ZislaKitTests.ClipboardAssistantSmartActionsTestsExtra/testTwo()",
    "ZislaTests.OtherTests/test()",
]
smart_records = run_case("smart-throughput", 0, smart_tests, target="ZislaKitTests,ZislaTests")
assert all(len(record["selected"]) == 1 for record in smart_records
           if record["selected"][0].startswith("ZislaKitTests.ClipboardAssistantSmartActionsTests/")), "Smart Action methods shared a worker"
assert len(smart_records[-2]["selected"]) == 2, "A similarly named Smart Action suite lost its shared host"
for index, positions in enumerate(([3, 2], [0, 4, 5], [1, 6])):
    for target in ("ZislaKitTests,ZislaTests", "ZislaTests,ZislaKitTests"):
        run_case("smart-throughput", 0, [smart_tests[position] for position in positions],
                 target=target, shard_count="3", shard_index=str(index))
run_case("smart-throughput-failure", 6, [smart_tests[3]], target="ZislaKitTests,ZislaTests")

throughput_tests = [
    "ZislaTests.AShortTests/test()",
    "ZislaTests.LongCaptureRealWorldTests/testOne()",
    "ZislaTests.LongCaptureRealWorldTests/testOneExtra()",
    "ZislaTests.LongCaptureRealWorldTests/testTwo(frameHeight:)",
    "ZislaTests.LongCaptureRealWorldTests/Nested/test()",
    "ZislaTests.LongCaptureRealWorldTests/realWorldTinyScrollDoesNotStartADuplicateCapture(frameHeight:)",
    "ZislaTests.LongCaptureRealWorldTests/realWorldRetinaSparseChatPageStitchesExactly()",
    "ZislaTests.LongCaptureRealWorldTestsExtra/testOne()",
    "ZislaTests.LongCaptureRealWorldTestsExtra/testTwo()",
    "ZislaKitTests.EmojiNameCatalogTests/testOne()",
    "ZislaKitTests.EmojiNameCatalogTests/testTwo()",
    "ZislaKitTests.ClipboardAssistantSmartActionsTests/test()",
    "ZislaKitTests.ClipboardAssistantShellCommandTests/test()",
    "ZislaKitTests.ClipboardAssistantDetectorTests/test()",
    "ZislaKitTests.ClipboardAssistantNumericActionsTests/test()",
    "ZislaKitTests.ClipboardAssistantCurrencyDetectionTests/test()",
]
records = run_case("throughput", 0, throughput_tests, target="ZislaKitTests,ZislaTests")
assert [record["selected"][0] for record in records[:8]] == [
    "ZislaKitTests.EmojiNameCatalogTests/testOne()",
    "ZislaKitTests.ClipboardAssistantShellCommandTests/test()",
    "ZislaTests.LongCaptureRealWorldTests/realWorldTinyScrollDoesNotStartADuplicateCapture(frameHeight:)",
    "ZislaKitTests.ClipboardAssistantDetectorTests/test()",
    "ZislaKitTests.ClipboardAssistantNumericActionsTests/test()",
    "ZislaKitTests.ClipboardAssistantCurrencyDetectionTests/test()",
    "ZislaTests.LongCaptureRealWorldTests/realWorldRetinaSparseChatPageStitchesExactly()",
    "ZislaKitTests.ClipboardAssistantSmartActionsTests/test()",
], "Long suites waited behind short suites"
assert all(len(record["selected"]) == 1 for record in records
           if record["selected"][0].startswith("ZislaTests.LongCaptureRealWorldTests/")), "Long capture methods shared a worker"
assert all(record["selected"][0].startswith("ZislaTests.LongCaptureRealWorldTests/") for record in records[8:12]), "Long capture methods waited behind short suites"
assert len(records[-1]["selected"]) == 2, "A similarly named ordinary suite lost its shared host"
run_case("throughput-failure", 6,
    [test for record in records[:3] for test in record["selected"]], target="ZislaKitTests,ZislaTests")

shard_tasks = [
    [0, 9, 12, 13],
    [1, 4, 5, 8, 11],
    [2, 3, 6, 7, 10],
]
for index, tasks in enumerate(shard_tasks):
    selected = [test for task in tasks for test in records[task]["selected"]]
    for target in ("ZislaKitTests,ZislaTests", "ZislaTests,ZislaKitTests"):
        run_case("throughput", 0, selected, target=target, shard_count="3", shard_index=str(index))
run_case("throughput-failure", 6,
    [test for record in records[2:3] for test in record["selected"]],
    target="ZislaKitTests,ZislaTests", shard_count="3", shard_index="2")
for count, index in (("0", "0"), ("-1", "0"), ("invalid", "0"), ("1.5", "0"),
                     ("", "0"), ("3", "-1"), ("3", "3"), ("3", "invalid"),
                     ("3", "1.5"), ("3", ""), ("3; touch unexpected", "0"), ("99", "0")):
    run_case("invalid-shard", 1, [], shard_count=count, shard_index=index)

for mode in ("parallel", "parallel-failure", "interrupted", "orphaned-worker", "orphaned-failure"):
    capture = test_root / (mode + ".jsonl")
    connections = []
    with socket.socket(socket.AF_INET) as coordinator:
        coordinator.bind(("127.0.0.1", 0))
        address = str(coordinator.getsockname()[1])
        coordinator.listen()
        coordinator.settimeout(5)
        with (test_root / (mode + ".log")).open("w") as output:
            process = subprocess.Popen(command,
                env=dict(environment, SWIFT_TEST_MODE=mode, SWIFT_TEST_CAPTURE=str(capture),
                    SWIFT_TEST_WORKERS="3", SWIFT_TEST_COORDINATOR=str(address)),
                stdout=output, stderr=subprocess.STDOUT)
            try:
                for _ in range(3):
                    connection, _ = coordinator.accept()
                    record = json.loads(connection.makefile().readline())
                    connections.append((connection, record))
                assert not select.select([coordinator], [], [], 0.2)[0], "Exceeded the configured worker limit"
                if mode == "parallel":
                    for connection, _ in connections:
                        connection.sendall(b"+")
                    for _ in range(2):
                        connection, _ = coordinator.accept()
                        json.loads(connection.makefile().readline())
                        connection.sendall(b"+")
                        connections.append((connection, None))
                    expected_status = 0
                elif mode in ("parallel-failure", "orphaned-failure"):
                    connections[0][0].sendall(b"!")
                    expected_status = 6
                else:
                    process.send_signal(signal.SIGTERM)
                    expected_status = 143
                actual_status = process.wait(timeout=10)
                assert actual_status == expected_status, f"{mode}: wrong exit status {actual_status}\n{(test_root / (mode + '.log')).read_text()}"
                if mode in ("orphaned-worker", "orphaned-failure"):
                    for connection, record in connections:
                        connection.settimeout(1)
                        assert connection.recv(1) == b"", f"Orphaned worker survived cancellation: {record['child_pid']}"
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
                for connection, record in connections:
                    connection.close()
                    if record and "child_pid" in record:
                        try:
                            os.kill(record["child_pid"], signal.SIGKILL)
                        except ProcessLookupError:
                            pass
    records = read_records(capture)
    if mode == "parallel":
        assert sorted(test for record in records for test in record["selected"]) == sorted(expected)
    check_cleanup(records)
    checks += 1

with socket.socket(socket.AF_INET) as coordinator:
    coordinator.bind(("127.0.0.1", 0))
    address = str(coordinator.getsockname()[1])
    coordinator.listen()
    coordinator.settimeout(5)
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        env=dict(environment, SWIFT_TEST_MODE="discovery-interrupted", SWIFT_TEST_WORKERS="1",
            SWIFT_TEST_COORDINATOR=str(address)))
    connection, _ = coordinator.accept()
    record = json.loads(connection.makefile().readline())
    try:
        process.send_signal(signal.SIGTERM)
        assert process.wait(timeout=10) == 143, "Discovery lost cancellation status"
        connection.settimeout(1)
        assert connection.recv(1) == b"", "Discovery left a worker alive"
        check_cleanup([record])
    finally:
        connection.close()
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        try:
            os.kill(record["child_pid"], signal.SIGKILL)
        except ProcessLookupError:
            pass
checks += 1

for mode in ("timeout", "timeout-orphan"):
    capture = test_root / (mode + ".jsonl")
    connections = []
    with socket.socket(socket.AF_INET) as coordinator:
        coordinator.bind(("127.0.0.1", 0))
        coordinator.listen()
        coordinator.settimeout(5)
        address = str(coordinator.getsockname()[1])
        with (test_root / (mode + ".log")).open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                env=dict(environment, SWIFT_TEST_MODE=mode, SWIFT_TEST_CAPTURE=str(capture),
                    SWIFT_TEST_WORKERS="3", SWIFT_TEST_SUITE_TIMEOUT="1", SWIFT_TEST_COORDINATOR=address))
            try:
                for _ in range(3):
                    connection, _ = coordinator.accept()
                    record = json.loads(connection.makefile().readline())
                    connections.append((connection, record))
                initial_log = (test_root / (mode + ".log")).read_text()
                for _, record in connections:
                    name = record["selected"][0].split("/")[0]
                    assert f"Swift suite started: {name} (pid={record['group']})" in initial_log, "A blocked suite and process group must be named before it completes"
                suite = initial_log.split("Swift suite started: ", 1)[1].split(" (pid=", 1)[0]
                actual_status = process.wait(timeout=10)
                log = (test_root / (mode + ".log")).read_text()
                assert actual_status == 124, f"{mode}: expected timeout exit 124, got {actual_status}\n{log}"
                assert f"Swift suite timed out after 1 seconds: {suite}" in log, "Timeout must name the stuck suite"
                assert "LAST TEST: waiting for an injected media dependency" in log, "Timeout discarded the last test output"
                for connection, _ in connections:
                    connection.settimeout(1)
                    assert connection.recv(1) == b"", "Timed-out suite or parallel child survived cancellation"
                check_cleanup(read_records(capture))
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
                for connection, record in connections:
                    connection.close()
                    try:
                        os.killpg(record["group"], signal.SIGKILL)
                    except (ProcessLookupError, PermissionError):
                        pass
                    if "child_pid" in record:
                        try:
                            os.kill(record["child_pid"], signal.SIGKILL)
                        except ProcessLookupError:
                            pass
    checks += 1

clock_tools = test_root / "clock-bin"
clock_tools.mkdir()
clock_python = clock_tools / "python3"
clock_python.write_text("#!" + sys.executable + r"""
import os
import select
import socket
import sys
import time

if sys.argv[1:3] != ["-", os.environ["SWIFT_TEST_RUNNER_ROOT"]]:
    os.execv(sys.executable, [sys.executable, *sys.argv[1:]])
source = sys.stdin.read()
clock = socket.create_connection(("127.0.0.1", int(os.environ["SWIFT_TEST_CLOCK_COORDINATOR"])))
clock.sendall(b'{"clock":0}\n')
clock.setblocking(False)
elapsed = 0
def monotonic():
    global elapsed
    if select.select([clock], [], [], 0)[0]:
        elapsed = int(clock.recv(32))
        clock.sendall(('{"clock":' + str(elapsed) + '}\n').encode())
    return elapsed
time.monotonic = monotonic
sys.argv = sys.argv[1:]
exec(compile(source, "swift-test-suites.sh", "exec"))
""")
clock_python.chmod(0o755)
for elapsed, expected_status in ((221, 0), (600, 124)):
    capture = test_root / ("long-budget-" + str(elapsed) + ".jsonl")
    with socket.socket(socket.AF_INET) as coordinator:
        coordinator.bind(("127.0.0.1", 0))
        coordinator.listen()
        coordinator.settimeout(5)
        address = str(coordinator.getsockname()[1])
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            env=dict(environment, PATH=str(clock_tools) + ":" + environment["PATH"],
                SWIFT_TEST_MODE="long-budget", SWIFT_TEST_CAPTURE=str(capture), SWIFT_TEST_WORKERS="1",
                SWIFT_TEST_COORDINATOR=address, SWIFT_TEST_CLOCK_COORDINATOR=address,
                SWIFT_TEST_RUNNER_ROOT=str(root)))
        clock, _ = coordinator.accept()
        clock.settimeout(5)
        ticks = clock.makefile()
        assert json.loads(ticks.readline()) == {"clock": 0}
        connection, _ = coordinator.accept()
        json.loads(connection.makefile().readline())
        try:
            clock.sendall(str(elapsed).encode())
            assert json.loads(ticks.readline()) == {"clock": elapsed}
            if expected_status == 0:
                connection.sendall(b"+")
            output, _ = process.communicate(timeout=10)
            assert process.returncode == expected_status, f"Default budget at {elapsed}s: expected {expected_status}, got {process.returncode}\n{output}"
            if expected_status == 124:
                assert "Swift suite timed out after 600 seconds: FixtureTests.Long" in output
            connection.settimeout(1)
            assert connection.recv(1) == b"", "Default budget left a test host running"
            check_cleanup(read_records(capture))
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            connection.close()
            ticks.close()
            clock.close()
    checks += 1

capture = test_root / "workflow.jsonl"
(test_root / "built").unlink()
(test_root / "builds").unlink()
workflow = (root.parent / ".github/workflows/swift-tests.yml").read_text()
commands = [
    shlex.split(line.strip())
    for line in workflow.splitlines()
    if line.strip().startswith(("swift build --build-tests", "zsh Scripts/swift-test.sh ", "zsh Scripts/swift-test-suites.sh "))
]
for entry in commands:
    subprocess.run(entry, cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        env=dict(environment, SWIFT_TEST_MODE="workflow", SWIFT_TEST_CAPTURE=str(capture), SWIFT_TEST_WORKERS="3"))
assert (test_root / "builds").read_text().splitlines() == ["build"], "Workflow rebuilt tests during discovery or execution"
actual = sorted(test for record in read_records(capture) for test in record["selected"])
assert actual == sorted([
    "ZislaCoreTests.ModelTests/test()",
    "ZislaKitTests.ServiceTests/test()",
    "ZislaTests.WiFiNetworkPanelViewTests/observedPowerKeepsItsColorAndToggleSemanticsInAnInactiveWindow()",
    "ZislaTests.FutureAppKitTests/test()",
    "ZislaTests.FutureAppKitTests/Nested/test()",
    "ZislaTests.FutureAppKitTestsExtra/test()",
    "ZislaTests.topLevel()/Tests.swift:1:1",
]), f"Workflow missed or duplicated tests: {actual}"
check_cleanup(read_records(capture))
checks += 1
print(f"PASS: {checks} suite-runner cases cover exact discovery, isolated hosts, bounded concurrency, failure/cancellation cleanup, and complete workflow coverage")
PYTHON
