#!/bin/zsh
set -euo pipefail

MAC_ROOT="${0:A:h:h:h}"
TEMPORARY_ROOT="$(mktemp -d "${TMPDIR%/}/zisla-build-package-tests.XXXXXX")"
function cleanup() {
  [[ "$TEMPORARY_ROOT" == "${TMPDIR%/}/zisla-build-package-tests."* ]] || return
  [[ -d "$TEMPORARY_ROOT" ]] && find "$TEMPORARY_ROOT" -depth -delete
}
trap cleanup EXIT

TEST_ROOT="$TEMPORARY_ROOT/repository with spaces"
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
if [[ "${FAIL_ARCHITECTURE:-}" == "$suffix" ]]; then
  print -u2 -r -- "injected $suffix package failure"
  exit 42
fi
for extension in zip zip.sha256 dmg dmg.sha256; do
  print -r -- "$suffix" > "$ARCHIVE_DIRECTORY/zisla-v0.1.3-macOS-${suffix}.${extension}"
done
print -r -- "gitee $suffix" > "$ARCHIVE_DIRECTORY/appcast-gitee.xml"
print -r -- "github $suffix" > "$ARCHIVE_DIRECTORY/appcast-github.xml"
if [[ "${OMIT_APPCAST_ARCHITECTURE:-}" == "$suffix" ]]; then
  rm "$ARCHIVE_DIRECTORY/appcast-github.xml"
fi
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

function expect_directory_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  (( tests_run += 1 ))
  if ! diff -qr "$expected" "$actual" >/dev/null; then
    print -u2 -r -- "FAIL: $description"
    exit 1
  fi
}

command_status=0
CAPTURE_FILE="$CAPTURE_FILE" FAIL_ARCHITECTURE=arm64 "$SCRIPT" \
  > "$TEMPORARY_ROOT/failure-output.txt" 2>&1 || command_status=$?
expect_equal 42 "$command_status" "a first package failure is reported"
expect_absent "$OUTPUT_DIRECTORY" "a first package failure does not publish partial outputs"
temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
expect_equal 0 "${#temporary_directories}" "a first package failure cleans up temporary packages"
: > "$CAPTURE_FILE"

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
  "assets from an earlier version are removed after successful packaging"
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
expect_equal \
  "$(print -rl -- "$RESOLVED_OUTPUT_DIRECTORY/.staging" "${expected_listing[@]}" | LC_ALL=C sort)" \
  "$(print -rl -- "$RESOLVED_OUTPUT_DIRECTORY"/*(D) | LC_ALL=C sort)" \
  "outputs contain only the release assets and retained app bundles"

temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
expect_equal 0 "${#temporary_directories}" "a successful package cleans up its temporary directory"

PREVIOUS_OUTPUT_DIRECTORY="$TEMPORARY_ROOT/previous-output"
cp -R "$OUTPUT_DIRECTORY" "$PREVIOUS_OUTPUT_DIRECTORY"
for failed_architecture in arm64 x86_64 universal; do
  command_status=0
  CAPTURE_FILE="$CAPTURE_FILE" FAIL_ARCHITECTURE="$failed_architecture" "$SCRIPT" \
    > "$TEMPORARY_ROOT/failure-output.txt" 2>&1 || command_status=$?
  expect_equal 42 "$command_status" "a $failed_architecture package failure is reported"

  expect_directory_equal "$PREVIOUS_OUTPUT_DIRECTORY" "$OUTPUT_DIRECTORY" \
    "a $failed_architecture package failure preserves the previous release output"

  temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
  expect_equal 0 "${#temporary_directories}" "a $failed_architecture failure cleans up temporary packages"
done

command_status=0
CAPTURE_FILE="$CAPTURE_FILE" OMIT_APPCAST_ARCHITECTURE=universal "$SCRIPT" \
  > "$TEMPORARY_ROOT/failure-output.txt" 2>&1 || command_status=$?
expect_equal 1 "$command_status" "a missing appcast prevents publication"
expect_directory_equal "$PREVIOUS_OUTPUT_DIRECTORY" "$OUTPUT_DIRECTORY" \
  "an asset collection failure preserves the previous release output"
temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
expect_equal 0 "${#temporary_directories}" "an asset collection failure cleans up temporary packages"

FAKE_BIN="$TEMPORARY_ROOT/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/mv" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
move_arguments=("$@")
[[ "$1" != -n ]] || move_arguments=("${@:2}")
if (( ${#move_arguments} == 2 )); then
  move_source="$move_arguments[1]"
  move_target="$move_arguments[2]"
  if [[ "$move_target" == "${PACKAGE_TEST_OUTPUT:h}" ]]; then
    move_target="$move_target/${move_source:t}"
  fi
  if [[ "$FAIL_MOVE_STAGE" == collision* && "$move_target" == "$PACKAGE_TEST_OUTPUT" && ! -e "$MOVE_FAILURE_MARKER" ]]; then
    : > "$MOVE_FAILURE_MARKER"
    cp -RP "$COLLISION_FIXTURE" "$PACKAGE_TEST_OUTPUT"
    [[ "$FAIL_MOVE_STAGE" != collision-restore ]] || exit 43
  fi
  if [[ "$FAIL_MOVE_STAGE" == backup && "$move_source" == "$PACKAGE_TEST_OUTPUT" ]]; then
    print -u2 -r -- "injected package backup failure"
    exit 43
  elif [[ "$FAIL_MOVE_STAGE" != backup && "$move_target" == "$PACKAGE_TEST_OUTPUT" ]]; then
    if [[ "$FAIL_MOVE_STAGE" == rollback || ! -e "$MOVE_FAILURE_MARKER" ]]; then
      : > "$MOVE_FAILURE_MARKER"
      print -u2 -r -- "injected package $FAIL_MOVE_STAGE failure"
      exit 43
    fi
  fi
fi
exec /bin/mv "$@"
SCRIPT
chmod +x "$FAKE_BIN/mv"

for failed_move in publish backup; do
  command_status=0
  CAPTURE_FILE="$CAPTURE_FILE" PATH="$FAKE_BIN:$PATH" PACKAGE_TEST_OUTPUT="$RESOLVED_OUTPUT_DIRECTORY" \
    FAIL_MOVE_STAGE="$failed_move" MOVE_FAILURE_MARKER="$TEMPORARY_ROOT/$failed_move-failed" "$SCRIPT" \
    > "$TEMPORARY_ROOT/failure-output.txt" 2>&1 || command_status=$?
  expect_equal 43 "$command_status" "a $failed_move failure is reported"
  expect_directory_equal "$PREVIOUS_OUTPUT_DIRECTORY" "$OUTPUT_DIRECTORY" \
    "a $failed_move failure preserves the previous release output"
  temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
  expect_equal 0 "${#temporary_directories}" "a $failed_move failure cleans up temporary packages"
done

COLLISION_ROOT="$TEMPORARY_ROOT/collisions"
mkdir -p "$COLLISION_ROOT/empty-directory" "$COLLISION_ROOT/nonempty-directory" "$COLLISION_ROOT/link-target"
print -r -- concurrent > "$COLLISION_ROOT/nonempty-directory/marker.txt"
print -r -- concurrent > "$COLLISION_ROOT/regular-file"
print -r -- linked > "$COLLISION_ROOT/link-target/marker.txt"
ln -s "$COLLISION_ROOT/link-target" "$COLLISION_ROOT/directory-link"
ln -s "$COLLISION_ROOT/missing-target" "$COLLISION_ROOT/dangling-link"
cp -R "$COLLISION_ROOT/link-target" "$COLLISION_ROOT/original-link-target"

for collision in empty-directory nonempty-directory regular-file directory-link dangling-link restore-directory; do
  collision_fixture="$COLLISION_ROOT/$collision"
  failure_stage=collision
  expected_status=1
  if [[ "$collision" == restore-directory ]]; then
    collision_fixture="$COLLISION_ROOT/nonempty-directory"
    failure_stage=collision-restore
    expected_status=43
  fi
  command_status=0
  CAPTURE_FILE="$CAPTURE_FILE" PATH="$FAKE_BIN:$PATH" PACKAGE_TEST_OUTPUT="$RESOLVED_OUTPUT_DIRECTORY" \
    FAIL_MOVE_STAGE="$failure_stage" COLLISION_FIXTURE="$collision_fixture" \
    MOVE_FAILURE_MARKER="$TEMPORARY_ROOT/$collision-collision" "$SCRIPT" \
    > "$TEMPORARY_ROOT/failure-output.txt" 2>&1 || command_status=$?
  if [[ -L "$collision_fixture" ]]; then
    expect_equal "$(readlink "$collision_fixture")" "$(readlink "$OUTPUT_DIRECTORY")" \
      "a $collision collision preserves the new output symlink"
  else
    expect_directory_equal "$collision_fixture" "$OUTPUT_DIRECTORY" \
      "a $collision collision does not nest or overwrite files in the new destination"
  fi
  expect_directory_equal "$COLLISION_ROOT/original-link-target" "$COLLISION_ROOT/link-target" \
    "a $collision collision does not write through an output symlink"
  temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
  expect_equal 1 "${#temporary_directories}" "a $collision collision keeps its recovery directory"
  RECOVERY_DIRECTORY="${temporary_directories[1]:A}/previous-outputs/outputs"
  expect_directory_equal "$PREVIOUS_OUTPUT_DIRECTORY" "$RECOVERY_DIRECTORY" \
    "a $collision collision preserves the complete previous release"
  expect_equal "$expected_status" "$command_status" "a $collision collision reports failure"
  (( tests_run += 1 ))
  if [[ "$(<"$TEMPORARY_ROOT/failure-output.txt")" != *"previous release remains at $RECOVERY_DIRECTORY"* ]]; then
    print -u2 -r -- "FAIL: a $collision collision does not report its recovery directory"
    exit 1
  fi
  /bin/mv "$OUTPUT_DIRECTORY" "$TEMPORARY_ROOT/observed-$collision"
  /bin/mv "$RECOVERY_DIRECTORY" "$OUTPUT_DIRECTORY"
  rm -rf "$temporary_directories[1]"
done

mv "$OUTPUT_DIRECTORY" "$TEMPORARY_ROOT/before-first-collision"
command_status=0
CAPTURE_FILE="$CAPTURE_FILE" PATH="$FAKE_BIN:$PATH" PACKAGE_TEST_OUTPUT="$RESOLVED_OUTPUT_DIRECTORY" \
  FAIL_MOVE_STAGE=collision COLLISION_FIXTURE="$COLLISION_ROOT/nonempty-directory" \
  MOVE_FAILURE_MARKER="$TEMPORARY_ROOT/first-collision" "$SCRIPT" \
  > "$TEMPORARY_ROOT/failure-output.txt" 2>&1 || command_status=$?
expect_directory_equal "$COLLISION_ROOT/nonempty-directory" "$OUTPUT_DIRECTORY" \
  "a first publication collision preserves the new destination"
expect_equal 1 "$command_status" "a first publication collision reports failure"
(( tests_run += 1 ))
if [[ "$(<"$TEMPORARY_ROOT/failure-output.txt")" != *"output destination already exists: $RESOLVED_OUTPUT_DIRECTORY"* ]]; then
  print -u2 -r -- "FAIL: a first publication collision does not identify the occupied destination"
  exit 1
fi
temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
expect_equal 0 "${#temporary_directories}" "a first publication collision cleans up unneeded packages"
mv "$OUTPUT_DIRECTORY" "$TEMPORARY_ROOT/observed-first-collision"
mv "$TEMPORARY_ROOT/before-first-collision" "$OUTPUT_DIRECTORY"

mv "$OUTPUT_DIRECTORY" "$TEMPORARY_ROOT/saved-output"
ln -s "$TEMPORARY_ROOT/missing-output" "$OUTPUT_DIRECTORY"
command_status=0
CAPTURE_FILE="$CAPTURE_FILE" PATH="$FAKE_BIN:$PATH" PACKAGE_TEST_OUTPUT="$RESOLVED_OUTPUT_DIRECTORY" \
  FAIL_MOVE_STAGE=publish MOVE_FAILURE_MARKER="$TEMPORARY_ROOT/symlink-publish-failed" "$SCRIPT" \
  > "$TEMPORARY_ROOT/failure-output.txt" 2>&1 || command_status=$?
expect_equal 43 "$command_status" "a publication failure with an existing dangling symlink is reported"
expect_equal "$TEMPORARY_ROOT/missing-output" "$(readlink "$OUTPUT_DIRECTORY")" \
  "a publication failure restores an existing dangling output symlink"
temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
expect_equal 0 "${#temporary_directories}" "restoring an output symlink cleans up temporary packages"

command_status=0
CAPTURE_FILE="$CAPTURE_FILE" PATH="$FAKE_BIN:$PATH" PACKAGE_TEST_OUTPUT="$RESOLVED_OUTPUT_DIRECTORY" \
  FAIL_MOVE_STAGE=collision COLLISION_FIXTURE="$COLLISION_ROOT/empty-directory" \
  MOVE_FAILURE_MARKER="$TEMPORARY_ROOT/symlink-collision" "$SCRIPT" \
  > "$TEMPORARY_ROOT/failure-output.txt" 2>&1 || command_status=$?
expect_directory_equal "$COLLISION_ROOT/empty-directory" "$OUTPUT_DIRECTORY" \
  "a collision while restoring a dangling symlink preserves the new destination"
temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
expect_equal 1 "${#temporary_directories}" "a skipped symlink restore keeps its recovery directory"
RECOVERY_DIRECTORY="${temporary_directories[1]:A}/previous-outputs/outputs"
expect_equal "$TEMPORARY_ROOT/missing-output" "$(readlink "$RECOVERY_DIRECTORY")" \
  "a skipped symlink restore preserves the previous dangling output symlink"
expect_equal 1 "$command_status" "a skipped symlink restore reports failure"
/bin/mv "$OUTPUT_DIRECTORY" "$TEMPORARY_ROOT/observed-symlink-collision"
/bin/mv "$RECOVERY_DIRECTORY" "$OUTPUT_DIRECTORY"
rm -rf "$temporary_directories[1]"

CAPTURE_FILE="$CAPTURE_FILE" "$SCRIPT" >/dev/null
expect_directory_equal "$PREVIOUS_OUTPUT_DIRECTORY" "$OUTPUT_DIRECTORY" \
  "successful publication replaces a dangling output symlink with the new release"
expect_absent "$TEMPORARY_ROOT/missing-output" "publication does not write through the old output symlink"
temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
expect_equal 0 "${#temporary_directories}" "replacing an output symlink cleans up temporary packages"

mv "$OUTPUT_DIRECTORY" "$TEMPORARY_ROOT/saved-symlink-output"
CAPTURE_FILE="$CAPTURE_FILE" "$SCRIPT" >/dev/null
expect_directory_equal "$PREVIOUS_OUTPUT_DIRECTORY" "$OUTPUT_DIRECTORY" \
  "a first successful package publishes the complete release"
temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
expect_equal 0 "${#temporary_directories}" "a first successful package cleans up temporary packages"

command_status=0
CAPTURE_FILE="$CAPTURE_FILE" PATH="$FAKE_BIN:$PATH" PACKAGE_TEST_OUTPUT="$RESOLVED_OUTPUT_DIRECTORY" \
  FAIL_MOVE_STAGE=rollback MOVE_FAILURE_MARKER="$TEMPORARY_ROOT/rollback-failed" "$SCRIPT" \
  > "$TEMPORARY_ROOT/failure-output.txt" 2>&1 || command_status=$?
temporary_directories=("$TEST_ROOT"/.zisla-build-package.*(N))
expect_equal 1 "${#temporary_directories}" "a failed rollback keeps its recovery directory"
RECOVERY_DIRECTORY="${temporary_directories[1]:A}/previous-outputs/outputs"
expect_directory_equal "$PREVIOUS_OUTPUT_DIRECTORY" "$RECOVERY_DIRECTORY" \
  "a failed rollback leaves the previous release available for recovery"
expect_equal 43 "$command_status" "a failed rollback preserves the publication failure status"
(( tests_run += 1 ))
if [[ "$(<"$TEMPORARY_ROOT/failure-output.txt")" != *"previous release remains at $RECOVERY_DIRECTORY"* ]]; then
  print -u2 -r -- "FAIL: a failed rollback does not report the recovery directory"
  exit 1
fi

print -r -- "PASS: $tests_run build-package tests"
