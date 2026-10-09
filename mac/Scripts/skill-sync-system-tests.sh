#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SKILL_SYNC_SYSTEM="$(mktemp -d "${TMPDIR:-/tmp}/zisla-skill-system-run.XXXXXX")"
trap 'find "$SKILL_SYNC_SYSTEM" -depth -delete' EXIT
SKILL_SYNC_BUILD="${ZISLA_SKILL_SYNC_BUILD_ROOT:-$SKILL_SYNC_SYSTEM/build}"
cd "$ROOT"
if [[ "${ZISLA_SKILL_SYNC_SKIP_BUILD:-0}" != 1 ]]; then
  if ! swift test --scratch-path "$SKILL_SYNC_BUILD" list > "$SKILL_SYNC_SYSTEM/build.log" 2>&1; then
    tail -n 80 "$SKILL_SYNC_SYSTEM/build.log"
    exit 1
  fi
fi

python3 - "$SKILL_SYNC_SYSTEM" "$SKILL_SYNC_BUILD" <<'PYTHON'
import itertools
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

scratch, build = (Path(value).resolve() for value in sys.argv[1:])
real_home = Path(pwd.getpwuid(os.getuid()).pw_dir).resolve()
swift = Path(subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip())
helper = swift.parent.parent / "libexec/swift/pm/swiftpm-testing-helper"
platform = Path(subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], text=True).strip())
test_name = "ZislaKitTests.AIAgentSkillSynchronizationSystemTests/isolatedHomeLifecycle()"
counts = os.environ.get("ZISLA_SKILL_SYNC_COUNTS", "0 1 50 100 150 1000").split()
layouts = os.environ.get("ZISLA_SKILL_SYNC_LAYOUTS", "plain relative absolute chain root-link mixed broken cycle readonly-backup").split()
modes = os.environ.get("ZISLA_SKILL_SYNC_MODES", "symbolicLink fileCopy").split()
cases = [(layout, count, mode) for layout, count, mode in itertools.product(layouts, counts, modes)
         if not (layout in ("broken", "cycle") and count == "0")]
assert cases, "No system cases selected"
# Foundation ignores TMPDIR for atomic writes; permit only this run's replacement directories.
process_prefix = "zisla-skill-" + uuid.uuid4().hex
replacement_parent = (Path(subprocess.check_output(["getconf", "DARWIN_USER_TEMP_DIR"], text=True).strip()) / "TemporaryItems").resolve()
replacement_pattern = "^" + re.escape(str(replacement_parent)) + "/NSIRD_" + process_prefix + "-[0-9]+_[^/]+(/|$)"
quote = lambda path: json.dumps(str(path), ensure_ascii=False)
profile = scratch / "isolation.sb"
profile.write_text(f'''(version 1)
(allow default)
(deny network*)
(deny file-write* (require-all
    (require-not (subpath {quote(scratch)}))
    (require-not (regex #{quote(replacement_pattern)}))
    (require-not (literal "/dev/null"))))
(deny file-read* (subpath {quote(real_home)}))
''')
# SIP strips inherited DYLD variables from sandbox-exec; set them inside it.
launch = ["/usr/bin/sandbox-exec", "-f", str(profile), "/usr/bin/env",
          f"DYLD_FRAMEWORK_PATH={platform / 'Developer/Library/Frameworks'}",
          f"DYLD_LIBRARY_PATH={platform / 'Developer/usr/lib'}", str(helper)]
failures = []
for index, (layout, count, mode) in enumerate(cases, 1):
    case_root = scratch / f"case-{index}"
    case_home = case_root / "home"
    case_tmp = case_root / "tmp"
    case_home.mkdir(parents=True)
    case_tmp.mkdir()
    process_name = f"{process_prefix}-{index}"
    (case_home / ".skill-sync-test-home").write_text("isolated skill sync fixture")
    environment = {
        "PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "en_US.UTF-8",
        "HOME": str(case_home),
        "CFFIXED_USER_HOME": str(case_home),
        "TMPDIR": str(case_tmp) + "/",
        "XDG_CACHE_HOME": str(case_home / ".cache"),
        "PYTHONNOUSERSITE": "1",
        "ZISLA_SKILL_SYNC_TEST_HOME": str(case_home),
        "ZISLA_SKILL_SYNC_TEST_COUNT": count,
        "ZISLA_SKILL_SYNC_TEST_LAYOUT": layout,
        "ZISLA_SKILL_SYNC_TEST_MODE": mode,
        "ZISLA_SKILL_SYNC_TEST_PROCESS": process_name,
    }
    if index == 1:
        # Probe a disposable file outside the allowed tree, never a user's skill.
        with tempfile.NamedTemporaryFile(prefix="zisla-skill-isolation-probe-") as sentinel:
            sentinel.write(b"unchanged")
            sentinel.flush()
            probe = '''import os, sys
try:
    os.listdir(sys.argv[1])
except PermissionError:
    pass
else:
    raise AssertionError("Real HOME remains readable")
try:
    with open(sys.argv[2], "wb") as stream:
        stream.write(b"changed")
except PermissionError:
    pass
else:
    raise AssertionError("Writes outside the test tree remain possible")
'''
            subprocess.run(["/usr/bin/sandbox-exec", "-f", str(profile), sys.executable,
                            "-c", probe, str(real_home), sentinel.name], env=environment, check=True)
            sentinel.seek(0)
            assert sentinel.read() == b"unchanged"
        print("Isolation verified: real HOME reads and writes outside temporary paths are denied.", flush=True)
        binaries = []
        for bundle in build.rglob("*.xctest"):
            binary = bundle / "Contents/MacOS" / bundle.stem
            listing = subprocess.run(launch + ["--test-bundle-path", str(binary), "--testing-library", "swift-testing",
                                              "--list-tests"], cwd=case_home, env=environment, capture_output=True, text=True)
            if listing.returncode:
                sys.exit(listing.stderr)
            if test_name in listing.stdout.splitlines():
                binaries.append(binary)
        assert len(binaries) == 1, f"Expected one system test bundle, found {binaries}"
        test_binary = binaries[0]
    log = case_root / "test.log"
    events = case_root / "events.jsonl"
    command = launch + ["--test-bundle-path", str(test_binary), "--testing-library", "swift-testing",
                        "--filter", "^ZislaKitTests.AIAgentSkillSynchronizationSystemTests/",
                        "--event-stream-output-path", str(events), "--event-stream-version", "0"]
    try:
        with log.open("w") as output:
            result = subprocess.run(command, cwd=case_home, env=environment, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=300)
        lines = log.read_text().splitlines()
        summaries = [line for line in lines if line.startswith("SKILL_SYNC_RESULT ")]
        event_kinds = [item["payload"]["kind"] for item in map(json.loads, events.read_text().splitlines())
                       if item["kind"] == "event"] if events.exists() else []
        if result.returncode or len(summaries) != 1 or not {"testEnded", "runEnded"}.issubset(event_kinds):
            failures.append((layout, count, mode))
            print(f"[{index}/{len(cases)}] FAILED {layout} {count} {mode}", flush=True)
            print("\n".join(lines[-30:]), flush=True)
        else:
            print(f"[{index}/{len(cases)}] PASSED {summaries[0]}", flush=True)
    except subprocess.TimeoutExpired:
        failures.append((layout, count, mode))
        print(f"[{index}/{len(cases)}] TIMEOUT {layout} {count} {mode}", flush=True)
    finally:
        shutil.rmtree(case_root)
        for replacement in replacement_parent.glob(f"NSIRD_{process_name}_*"):
            shutil.rmtree(replacement)
print(f"System matrix: {len(cases) - len(failures)}/{len(cases)} passed; failures={failures}", flush=True)
sys.exit(bool(failures))
PYTHON
