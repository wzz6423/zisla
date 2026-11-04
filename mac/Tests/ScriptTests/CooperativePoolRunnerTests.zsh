#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-cooperative-runner.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

python3 - "$ROOT" "$TEST_ROOT" <<'PYTHON'
from pathlib import Path
import os
import subprocess
import sys

root, temporary = map(Path, sys.argv[1:])
swift = Path(subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip())
platform = Path(subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], text=True).strip())
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
tools = temporary / "bin"
tools.mkdir()
binary = temporary / "build/ZislaKitTests.xctest/Contents/MacOS/ZislaKitTests"
binary.parent.mkdir(parents=True)
fixture = temporary / "Fixture.swift"
fixture.write_text('''import Foundation
import Testing

struct SystemMonitorServiceTests {
    @Test func inFlightSamplesCannotWriteAcrossHistoryLifecycleChanges() async {
        #expect(ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"]?.hasSuffix("/LimitedPool.dylib") == true)
        #expect(ProcessInfo.processInfo.environment["COOPERATIVE_FIXTURE_FAIL"] != "1")
    }
    @Test func concurrentSampleRequestsShareOneInFlightTask() async {
        #expect(ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"]?.hasSuffix("/LimitedPool.dylib") == true)
    }
}
struct DownloadServiceTests {
    @Test func serviceRunsSeparateDownloadTasksConcurrently() async {
        #expect(ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"]?.hasSuffix("/LimitedPool.dylib") == true)
    }
}
''')
subprocess.run([str(swift.parent / "swiftc"), "-swift-version", "6", "-parse-as-library",
    "-emit-library", "-module-name", "ZislaKitTests", "-F", str(platform / "Developer/Library/Frameworks"),
    "-sdk", sdk, str(fixture), "-load-plugin-library",
    str(swift.parent.parent / "lib/swift/host/plugins/testing/libTestingMacros.dylib"),
    "-o", str(binary)], check=True)
(tools / "swift").write_text("#!" + sys.executable + "\nprint(" + repr(str(binary.parents[3])) + ")\n")
(tools / "swift").chmod(0o755)

# A launcher must not inherit host-only dylibs, regardless of its Mach-O architecture.
launcher = temporary / "Launcher.c"
launcher.write_text('''#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (getenv("DYLD_INSERT_LIBRARIES")) {
        fputs("Host dylib leaked into launcher\\n", stderr);
        return 64;
    }
    argv[0] = "/bin/zsh";
    execv(argv[0], argv);
    return 1;
}
''')
subprocess.run([str(swift.parent / "clang"), "-isysroot", sdk,
    str(launcher), "-o", str(tools / "zsh")], check=True)
environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"], TMPDIR=str(temporary) + "/")
for fail in (False, True):
    result = subprocess.run(["/bin/zsh", str(root / "Tests/CooperativePoolTests.zsh")],
        env=dict(environment, COOPERATIVE_FIXTURE_FAIL=str(int(fail))),
        capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    assert (result.returncode != 0) == fail, output
    assert "Host dylib leaked into launcher" not in output, output
    assert "Zisla regression: two cooperative workers" in output, output
    if fail:
        assert "Expectation failed" in output, output
    else:
        assert "PASS: hardware lifecycle, shared sampling, and simultaneous downloads" in output, output
    assert not list(temporary.glob("zisla-cooperative-pool.*")), "The runner left temporary artifacts"
print("PASS: 2 cooperative-pool runner cases isolate dylib injection and preserve test failures")
PYTHON
