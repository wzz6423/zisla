#!/bin/zsh
set -euo pipefail

MAC_ROOT="${0:A:h:h:h}"
TEMPORARY_ROOT="$(mktemp -d "${TMPDIR%/}/zisla-build-package-tests.XXXXXX")"
function cleanup() {
  [[ "$TEMPORARY_ROOT" == "${TMPDIR%/}/zisla-build-package-tests."* ]] || return
  [[ -d "$TEMPORARY_ROOT" ]] && find "$TEMPORARY_ROOT" -depth -delete
}
trap cleanup EXIT

TEST_ROOT="$TEMPORARY_ROOT/repository"
SCRIPT="$TEST_ROOT/mac/Scripts/build-package.sh"
OUTPUT_DIRECTORY="$TEST_ROOT/outputs"
CAPTURE_FILE="$TEMPORARY_ROOT/package-release-invocations.txt"
mkdir -p "$TEST_ROOT/mac/Scripts"
cp "$MAC_ROOT/Scripts/build-package.sh" "$SCRIPT"

cat > "$TEST_ROOT/mac/Scripts/package-release.sh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
print -r -- "$BUILD_ARCHITECTURES|$DEBUG_BUILD|${ARCHIVE_DIRECTORY:t}" >> "$CAPTURE_FILE"
case "$BUILD_ARCHITECTURES" in
  "arm64 x86_64") suffix=universal ;;
  *) suffix="$BUILD_ARCHITECTURES" ;;
esac
mkdir -p "$ARCHIVE_DIRECTORY/zisla.app/Contents"
for extension in zip zip.sha256 dmg dmg.sha256; do
  print -r -- "$suffix" > "$ARCHIVE_DIRECTORY/zisla-v0.1.3-macOS-${suffix}.${extension}"
done
print -r -- "gitee $suffix" > "$ARCHIVE_DIRECTORY/appcast-gitee.xml"
print -r -- "github $suffix" > "$ARCHIVE_DIRECTORY/appcast-github.xml"
SCRIPT
chmod +x "$SCRIPT" "$TEST_ROOT/mac/Scripts/package-release.sh"

tests_run=0

function expect_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  (( tests_run += 1 ))
  if [[ "$actual" != "$expected" ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "expected: $expected"
    print -u2 -r -- "actual:   $actual"
    exit 1
  fi
}

function expect_file() {
  local target_path="$1"
  local description="$2"

  (( tests_run += 1 ))
  if [[ ! -f "$target_path" ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "missing: $target_path"
    exit 1
  fi
}

function expect_absent() {
  local target_path="$1"
  local description="$2"

  (( tests_run += 1 ))
  if [[ -e "$target_path" ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "unexpected: $target_path"
    exit 1
  fi
}

mkdir -p "$OUTPUT_DIRECTORY"
print -r -- stale > "$OUTPUT_DIRECTORY/zisla-v0.0.9-macOS-arm64.zip"

SCRIPT_OUTPUT="$(CAPTURE_FILE="$CAPTURE_FILE" DEBUG_BUILD=true "$SCRIPT")"

expect_equal \
  "arm64|false|arm64
x86_64|false|x86_64
arm64 x86_64|false|universal" \
  "$(<"$CAPTURE_FILE")" \
  "every architecture is packaged in order without a debug build"

for architecture in arm64 x86_64 universal; do
  for extension in zip zip.sha256 dmg dmg.sha256; do
    expect_file \
      "$OUTPUT_DIRECTORY/zisla-v0.1.3-macOS-${architecture}.${extension}" \
      "$architecture $extension is collected into outputs"
  done
done

# The universal pair keeps the bare name because it becomes the appcast.xml that apps
# released before per-architecture updates still request.
for host in gitee github; do
  expect_equal \
    "$host universal" \
    "$(<"$OUTPUT_DIRECTORY/appcast-${host}.xml")" \
    "the published $host appcast comes from the universal package"
  for architecture in arm64 x86_64; do
    expect_equal \
      "$host $architecture" \
      "$(<"$OUTPUT_DIRECTORY/appcast-${host}-${architecture}.xml")" \
      "the $architecture $host appcast comes from the $architecture package"
  done
done

expect_absent \
  "$OUTPUT_DIRECTORY/zisla-v0.0.9-macOS-arm64.zip" \
  "assets from an earlier version are removed before packaging"
expect_absent "$OUTPUT_DIRECTORY/zisla.app" "the app bundle is not published as a release asset"

for architecture in arm64 x86_64 universal; do
  (( tests_run += 1 ))
  if [[ ! -d "$OUTPUT_DIRECTORY/.staging/$architecture/zisla.app" ]]; then
    print -u2 -r -- "FAIL: the $architecture app bundle is not kept for release verification"
    exit 1
  fi
done

RESOLVED_OUTPUT_DIRECTORY="${OUTPUT_DIRECTORY:A}"
expected_listing=()
for host in gitee github; do
  for suffix in -arm64 -x86_64 ''; do
    expected_listing+=("$RESOLVED_OUTPUT_DIRECTORY/appcast-${host}${suffix}.xml")
  done
done
for architecture in arm64 universal x86_64; do
  for extension in dmg dmg.sha256 zip zip.sha256; do
    expected_listing+=("$RESOLVED_OUTPUT_DIRECTORY/zisla-v0.1.3-macOS-${architecture}.${extension}")
  done
done
expect_equal \
  "${(F)expected_listing}" \
  "$(print -rl -- ${(f)SCRIPT_OUTPUT} | LC_ALL=C sort)" \
  "the printed listing names every uploadable asset and nothing else"

print -r -- "PASS: $tests_run build-package tests"
