#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-portrait-kernels.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

python3 - "$ROOT" "$TEST_ROOT" <<'PYTHON'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root, temporary = (Path(value).resolve() for value in sys.argv[1:])
package = temporary / "package with spaces"
(package / "Sources/Fixture").mkdir(parents=True)
(package / "Plugins/RecordingPortraitKernels").mkdir(parents=True)
(package / "Resources").mkdir()
shutil.copy(root / "Plugins/RecordingPortraitKernels/plugin.swift", package / "Plugins/RecordingPortraitKernels/plugin.swift")
shutil.copy(root / "Resources/RecordingPortraitKernels.metal", package / "Resources/RecordingPortraitKernels.metal")
(package / "Sources/Fixture/main.swift").write_text('print("fixture")\n')
(package / "Package.swift").write_text('''// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "Fixture", targets: [
    .executableTarget(name: "Fixture", plugins: [.plugin(name: "RecordingPortraitKernels")]),
    .plugin(name: "RecordingPortraitKernels", capability: .buildTool()),
])
''')
compiler = temporary / "downloaded toolchain/metal"
compiler.parent.mkdir()
compiler.write_text('''#!/usr/bin/python3
import json
from pathlib import Path
import sys
arguments = sys.argv[1:]
output = Path(arguments[arguments.index("-o") + 1])
output.write_text(json.dumps(arguments))
''')
compiler.chmod(0o755)
command = ["swift", "build", "--package-path", str(package), "--scratch-path", str(temporary / "build")]
environment = dict(os.environ, ZISLA_METAL_COMPILER=str(compiler))
result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=90)
assert result.returncode == 0, result.stdout + result.stderr
libraries = list((temporary / "build/plugins/outputs").rglob("RecordingPortraitKernels.metallib"))
assert len(libraries) == 1, "The plugin must produce exactly one Metal library"
arguments = json.loads(libraries[0].read_text())
assert arguments == ["-fcikernel", "-mmacosx-version-min=14.0", str(package / "Resources/RecordingPortraitKernels.metal"),
                     "-o", str(libraries[0])], arguments

libraries[0].unlink()
compiler.write_text('#!/bin/sh\necho "injected Metal compiler failure" >&2\nexit 42\n')
result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=90)
assert result.returncode != 0 and "injected Metal compiler failure" in result.stdout + result.stderr, result.stdout + result.stderr
assert not libraries[0].exists(), "A failed compiler must not publish a Metal library"

compiler.unlink()
result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=90)
assert result.returncode != 0, "A missing explicitly selected compiler must not fall back to xcrun"
assert not libraries[0].exists(), "A missing compiler must not publish a Metal library"

environment.pop("ZISLA_METAL_COMPILER")
default_build = temporary / "default-build"
result = subprocess.run([*command[:-1], str(default_build)], env=environment, capture_output=True, text=True, timeout=90)
assert result.returncode == 0, result.stdout + result.stderr
libraries = list((default_build / "plugins/outputs").rglob("RecordingPortraitKernels.metallib"))
assert len(libraries) == 1 and libraries[0].read_bytes().startswith(b"MTLB"), "Default builds must compile a real Metal library via xcrun"
print("PASS: 4 portrait-kernel plugin cases cover compiler paths with spaces, failed compilation, a missing compiler, and default Metal builds")
PYTHON
