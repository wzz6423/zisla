#!/bin/zsh
set -euo pipefail

MAC_ROOT="${0:A:h:h}"
OUTPUT_DIRECTORY="${MAC_ROOT:h}/outputs"
TEMPORARY_DIRECTORY="$(mktemp -d "${MAC_ROOT:h}/.zisla-build-package.XXXXXX")"
PACKAGE_DIRECTORY="$TEMPORARY_DIRECTORY/outputs"
PREVIOUS_OUTPUT_DIRECTORY="$TEMPORARY_DIRECTORY/previous-outputs/outputs"
STAGING_DIRECTORY="$PACKAGE_DIRECTORY/.staging"
ARCHITECTURE_NAMES=(arm64 x86_64 universal)
ARCHITECTURE_SETS=(arm64 x86_64 'arm64 x86_64')

move_outputs() {
  # Target the parent so a destination created by another process cannot cause nesting.
  mv -n "$1" "${OUTPUT_DIRECTORY:h}" || return
  if [[ -e "$1" || -L "$1" ]]; then
    print -u2 -r -- "error: output destination already exists: $OUTPUT_DIRECTORY"
    return 1
  fi
}

cleanup() {
  # A package still in staging has not replaced the previous release.
  if [[ -d "$PACKAGE_DIRECTORY" && ( -e "$PREVIOUS_OUTPUT_DIRECTORY" || -L "$PREVIOUS_OUTPUT_DIRECTORY" ) ]]; then
    move_outputs "$PREVIOUS_OUTPUT_DIRECTORY" || {
      print -u2 -r -- "error: could not restore outputs; previous release remains at $PREVIOUS_OUTPUT_DIRECTORY"
      return 1
    }
  fi
  rm -rf "$TEMPORARY_DIRECTORY"
}
trap cleanup EXIT

for index in {1..${#ARCHITECTURE_NAMES}}; do
  DEBUG_BUILD=false \
    ARCHIVE_DIRECTORY="$STAGING_DIRECTORY/${ARCHITECTURE_NAMES[index]}" \
    BUILD_ARCHITECTURES="${ARCHITECTURE_SETS[index]}" \
    "$MAC_ROOT/Scripts/package-release.sh"
done

# Assets stay flat so a release can upload the whole directory.
mv "$STAGING_DIRECTORY"/*/zisla-v*-macOS-*(.) "$PACKAGE_DIRECTORY"

# Every architecture ships its own appcast so an update keeps an install on its own slice.
# The universal pair keeps the bare name because it becomes the appcast.xml that apps
# released before per-architecture updates still request.
mv "$STAGING_DIRECTORY/universal/appcast-gitee.xml" \
  "$STAGING_DIRECTORY/universal/appcast-github.xml" \
  "$PACKAGE_DIRECTORY"
for ARCHITECTURE in arm64 x86_64; do
  mv "$STAGING_DIRECTORY/$ARCHITECTURE/appcast-gitee.xml" \
    "$PACKAGE_DIRECTORY/appcast-gitee-$ARCHITECTURE.xml"
  mv "$STAGING_DIRECTORY/$ARCHITECTURE/appcast-github.xml" \
    "$PACKAGE_DIRECTORY/appcast-github-$ARCHITECTURE.xml"
done

if [[ -e "$OUTPUT_DIRECTORY" || -L "$OUTPUT_DIRECTORY" ]]; then
  mkdir "${PREVIOUS_OUTPUT_DIRECTORY:h}"
  mv "$OUTPUT_DIRECTORY" "$PREVIOUS_OUTPUT_DIRECTORY"
fi
# Explicit exit keeps zsh's outer EXIT trap active when the helper fails.
move_outputs "$PACKAGE_DIRECTORY" || exit $?

# The staging directory keeps every app bundle so release verification can still
# check bundle identity, icons, architectures, and signatures before uploading.
print -rl -- "$OUTPUT_DIRECTORY"/*(.)
