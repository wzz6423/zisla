#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-cooperative-runner.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

python3 - "$ROOT" "$TEST_ROOT" <<'PYTHON'
from pathlib import Path
import os
import shutil
import subprocess
import sys

root, temporary = map(Path, sys.argv[1:])
swift = Path(subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip())
platform = Path(subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], text=True).strip())
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
tools = temporary / "bin"
tools.mkdir()
build = temporary / "build"
build.mkdir()
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
compiler = [str(swift.parent / "swiftc"), "-swift-version", "6", "-parse-as-library",
    "-emit-library", "-F", str(platform / "Developer/Library/Frameworks"),
    "-sdk", sdk, str(fixture), "-load-plugin-library",
    str(swift.parent.parent / "lib/swift/host/plugins/testing/libTestingMacros.dylib")]
for module in ("ZislaKitTests", "UnrelatedTests"):
    subprocess.run(compiler + ["-module-name", module, "-o", str(temporary / (module + ".dylib"))], check=True)
(tools / "swift").write_text("#!" + sys.executable + "\nprint(" + repr(str(build)) + ")\n")
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
unrelated = build / "ATests.xctest/Contents/MacOS/ATests"
unrelated.parent.mkdir(parents=True)
shutil.copyfile(temporary / "UnrelatedTests.dylib", unrelated)
for name in ("ZislaKitTests", "zislaPackageTests"):
    binary = build / (name + ".xctest") / "Contents/MacOS" / name
    binary.parent.mkdir(parents=True)
    shutil.copyfile(temporary / "ZislaKitTests.dylib", binary)
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
    shutil.rmtree(binary.parents[2])
for empty in (False, True):
    if empty:
        shutil.rmtree(unrelated.parents[2])
    result = subprocess.run(["/bin/zsh", str(root / "Tests/CooperativePoolTests.zsh")],
        env=environment, capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    assert result.returncode != 0 and "No ZislaKitTests test bundle found" in output, output
    assert not list(temporary.glob("zisla-cooperative-pool.*")), "The runner left temporary artifacts"
print("PASS: 6 cooperative-pool runner cases cover split/combined bundles, missing targets, dylib isolation, failures, and cleanup")
PYTHON
