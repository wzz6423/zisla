#!/bin/zsh
set -euo pipefail

MAC_ROOT="${0:A:h:h}"
OUTPUT_DIRECTORY="${MAC_ROOT:h}/outputs"
STAGING_DIRECTORY="$OUTPUT_DIRECTORY/.staging"
ARCHITECTURE_NAMES=(arm64 x86_64 universal)
ARCHITECTURE_SETS=(arm64 x86_64 'arm64 x86_64')

rm -rf "$OUTPUT_DIRECTORY"

for index in {1..${#ARCHITECTURE_NAMES}}; do
  DEBUG_BUILD=false \
    ARCHIVE_DIRECTORY="$STAGING_DIRECTORY/${ARCHITECTURE_NAMES[index]}" \
    BUILD_ARCHITECTURES="${ARCHITECTURE_SETS[index]}" \
    "$MAC_ROOT/Scripts/package-release.sh"
done

# Assets stay flat so a release can upload the whole directory. Only the
# universal appcast ships because Sparkle updates reference the universal ZIP.
mv "$STAGING_DIRECTORY"/*/zisla-v*-macOS-*(.) "$OUTPUT_DIRECTORY"
mv "$STAGING_DIRECTORY/universal/appcast-gitee.xml" \
  "$STAGING_DIRECTORY/universal/appcast-github.xml" \
  "$OUTPUT_DIRECTORY"

# The staging directory keeps every app bundle so release verification can still
# check bundle identity, icons, architectures, and signatures before uploading.
print -rl -- "$OUTPUT_DIRECTORY"/*(.)
