#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-cooperative-pool.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

python3 - "$ROOT" "$TEST_ROOT" "$@" <<'PYTHON'
from pathlib import Path
import os
import signal
import subprocess
import sys

root, temporary = map(Path, sys.argv[1:3])
swift = Path(subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip())
platform = Path(subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], text=True).strip())
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
binary_directory = Path(subprocess.check_output([
    "swift", "build", *sys.argv[3:], "--show-bin-path"], text=True).strip())
host = temporary / "swift-testing-host"
subprocess.run([str(swift.parent / "swiftc"), "-swift-version", "6", "-parse-as-library",
    str(root / "Scripts/SwiftTestingHost.swift"), "-F", str(platform / "Developer/Library/Frameworks"),
    "-sdk", sdk, "-o", str(host)], check=True)

# Limit only this test process, without changing kernel settings or relying on the machine's CPU count.
source = temporary / "LimitedPool.c"
marker = "Zisla regression: two cooperative workers"
source.write_text('''#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static dispatch_queue_t limited_global_queue(intptr_t priority, uintptr_t flags) {
    if (flags != 4) return dispatch_get_global_queue(priority, flags);
    static dispatch_queue_t limited;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        limited = dispatch_queue_create("zisla-test-cooperative-pool", DISPATCH_QUEUE_CONCURRENT);
        void (*set_width)(dispatch_queue_t, long) = dlsym(RTLD_DEFAULT, "dispatch_queue_set_width");
        if (!set_width) { fputs("dispatch_queue_set_width unavailable\\n", stderr); exit(1); }
        set_width(limited, 2);
        dispatch_set_target_queue(limited, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        fputs("Zisla regression: two cooperative workers\\n", stderr);
    });
    return limited;
}
__attribute__((used)) static struct { const void *replacement; const void *original; } interpose
    __attribute__((section("__DATA,__interpose"))) = {limited_global_queue, dispatch_get_global_queue};
''')
library = temporary / "LimitedPool.dylib"
architecture = subprocess.check_output(["xcrun", "lipo", "-archs", str(host)], text=True).strip()
subprocess.run([str(swift.parent / "clang"), "-dynamiclib", "-arch", architecture, "-fblocks", "-isysroot", sdk,
    str(source), "-o", str(library)], check=True)
environment = dict(os.environ,
    DYLD_FRAMEWORK_PATH=os.pathsep.join(str(platform / "Developer/Library" / directory)
        for directory in ("Frameworks", "PrivateFrameworks")),
    DYLD_LIBRARY_PATH=str(platform / "Developer/usr/lib"), DYLD_INSERT_LIBRARIES=str(library),
    HOME=str(temporary), CFFIXED_USER_HOME=str(temporary), TMPDIR=str(temporary) + "/")
bundle = binary_directory / "ZislaKitTests.xctest/Contents/MacOS/ZislaKitTests"
filters = (
    r"^ZislaKitTests.SystemMonitorServiceTests/(?:inFlightSamplesCannotWriteAcrossHistoryLifecycleChanges|concurrentSampleRequestsShareOneInFlightTask)",
    r"^ZislaKitTests.DownloadServiceTests/serviceRunsSeparateDownloadTasksConcurrently",
)
for index, pattern in enumerate(filters):
    log = temporary / f"{index}.log"
    with log.open("w") as output:
        process = subprocess.Popen(["zsh", str(root / "Scripts/swift-test.sh"), "--runner", "/usr/bin/env",
            *(f"{key}={value}" for key, value in environment.items() if key.startswith("DYLD_")),
            str(host), "--test-bundle-path", str(bundle), "--filter", pattern],
            env=environment, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            result = process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            result = 124
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    text = log.read_text()
    print(text, end="", flush=True)
    if result:
        sys.exit(f"Cooperative-pool regression failed ({result}): {pattern}")
    if marker not in text:
        sys.exit("The cooperative-pool limit was not applied")
print("PASS: hardware lifecycle, shared sampling, and simultaneous downloads finish with two cooperative workers")
PYTHON
