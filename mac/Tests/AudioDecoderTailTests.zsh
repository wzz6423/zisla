#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-audio-decoder-tail.XXXXXX")"
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

# The injected stall affects only this host, after it receives the requested audio duration.
source = temporary / "DecoderTail.m"
source.write_text(r'''#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#include <math.h>

static const void *readerKey = &readerKey;
static const void *positionKey = &positionKey;
static BOOL (*originalStart)(id, SEL);
static CMSampleBufferRef (*originalRead)(id, SEL);

static BOOL startReading(id reader, SEL command) {
    for (AVAssetReaderOutput *output in [reader outputs]) {
        if ([output isKindOfClass:[AVAssetReaderAudioMixOutput class]]) {
            objc_setAssociatedObject(output, readerKey, reader, OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(output, positionKey, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    return originalStart(reader, command);
}

static CMSampleBufferRef nextSample(id output, SEL command) {
    AVAssetReader *reader = objc_getAssociatedObject(output, readerKey);
    NSNumber *position = objc_getAssociatedObject(output, positionKey);
    if (reader && [position longLongValue] >= llround(CMTimeGetSeconds(reader.timeRange.duration) * 48000)) {
        fputs("Zisla regression: stalled decoder EOF\n", stderr);
        fflush(stderr);
        dispatch_semaphore_wait(dispatch_semaphore_create(0), DISPATCH_TIME_FOREVER);
    }
    CMSampleBufferRef sample = originalRead(output, command);
    if (reader && sample) {
        int64_t end = llround(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) * 48000)
            + CMSampleBufferGetNumSamples(sample);
        objc_setAssociatedObject(output, positionKey, @(end), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (end >= llround(CMTimeGetSeconds(reader.timeRange.duration) * 48000)) {
            fputs("Zisla regression: decoder EOF stall armed\n", stderr);
        }
    }
    return sample;
}

__attribute__((constructor)) static void installTailDelay(void) {
    @autoreleasepool {
        Method start = class_getInstanceMethod([AVAssetReader class], @selector(startReading));
        originalStart = (void *)method_setImplementation(start, (IMP)startReading);
        Method read = class_getInstanceMethod([AVAssetReaderAudioMixOutput class], @selector(copyNextSampleBuffer));
        originalRead = (void *)method_getImplementation(read);
        if (!class_addMethod([AVAssetReaderAudioMixOutput class], @selector(copyNextSampleBuffer),
                            (IMP)nextSample, method_getTypeEncoding(read))) {
            method_setImplementation(read, (IMP)nextSample);
        }
    }
}
''')
library = temporary / "DecoderTail.dylib"
subprocess.run([str(swift.parent / "clang"), "-dynamiclib", "-fobjc-arc", "-fblocks", "-isysroot", sdk,
    "-framework", "Foundation", "-framework", "AVFoundation", "-framework", "CoreMedia",
    str(source), "-o", str(library)], check=True)
environment = dict(os.environ,
    DYLD_FRAMEWORK_PATH=os.pathsep.join(str(platform / "Developer/Library" / directory)
        for directory in ("Frameworks", "PrivateFrameworks")),
    DYLD_LIBRARY_PATH=str(platform / "Developer/usr/lib"),
    HOME=str(temporary), CFFIXED_USER_HOME=str(temporary), TMPDIR=str(temporary) + "/")
for candidate in sorted(binary_directory.glob("*.xctest")):
    bundle = candidate / "Contents/MacOS" / candidate.stem
    tests = subprocess.check_output([str(host), "--test-bundle-path", str(bundle), "--list-tests"],
        env=environment, text=True)
    if any(test.startswith("ZislaTests.ScreenRecordingAudioOnlyExportTests/") for test in tests.splitlines()):
        break
else:
    sys.exit("No audio-only export test bundle found")
environment["DYLD_INSERT_LIBRARIES"] = str(library)
log = temporary / "output.log"
with log.open("w") as output:
    process = subprocess.Popen(["zsh", str(root / "Scripts/swift-test.sh"), "--runner", "/usr/bin/env",
        *(f"{key}={value}" for key, value in environment.items() if key.startswith("DYLD_")),
        str(host), "--test-bundle-path", str(bundle), "--filter",
        r"^ZislaTests.ScreenRecordingAudioOnlyExportTests/(?:nativeAudioFormatsPreserveTheEditedMixedTimelineWithoutVideo|resamplingKeepsFractionalCutsAndTimelineDuration)"],
        env={key: value for key, value in environment.items() if not key.startswith("DYLD_")},
        stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        result = process.wait(timeout=60)
    except subprocess.TimeoutExpired:
        result = 124
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
text = log.read_text()
print(text, end="", flush=True)
if result:
    sys.exit(f"Audio decoder-tail regression failed ({result})")
if "Zisla regression: decoder EOF stall armed" not in text:
    sys.exit("The decoder EOF stall was not armed")
print("PASS: native audio formats and resampling finish without waiting for decoder EOF")
PYTHON
