#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:?VERSION is required}"
BUILD_NUMBER="${BUILD_NUMBER:-${VERSION//./}}"
ARCHIVE_DIRECTORY="${ARCHIVE_DIRECTORY:-$ROOT/dist}"

APP="$ARCHIVE_DIRECTORY/zisla.app"
ARCHIVE="$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.zip"
DMG="$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.dmg"

if [[ "${SKIP_BUILD:-false}" == "true" ]]; then
  [[ -d "$APP" ]] || { echo "error: missing app bundle: $APP" >&2; exit 1; }
else
  VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" OUTPUT_DIRECTORY="$ARCHIVE_DIRECTORY" BUILD_ARCHITECTURES="arm64 x86_64" "$ROOT/Scripts/build-app.sh"
fi

ditto -c -k --keepParent "$APP" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"

if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" ]]; then
  APPCAST_ARGUMENTS=()
  [[ -n "${SPARKLE_APPCAST_ACCOUNT:-}" ]] && APPCAST_ARGUMENTS+=(--account "$SPARKLE_APPCAST_ACCOUNT")
  [[ -n "${SPARKLE_APPCAST_DOWNLOAD_URL_PREFIX:-}" ]] && APPCAST_ARGUMENTS+=(--download-url-prefix "$SPARKLE_APPCAST_DOWNLOAD_URL_PREFIX")
  "$SPARKLE_GENERATE_APPCAST" "${APPCAST_ARGUMENTS[@]}" "$ARCHIVE_DIRECTORY"
fi

TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR%/}/zisla-dmg.XXXXXX")"
cleanup() {
  [[ "$TEMPORARY_DIRECTORY" == "${TMPDIR%/}/zisla-dmg."* ]] || return
  rm -rf "$TEMPORARY_DIRECTORY"
}
trap cleanup EXIT

ditto "$APP" "$TEMPORARY_DIRECTORY/zisla.app"
ln -s /Applications "$TEMPORARY_DIRECTORY/Applications"
hdiutil create -quiet -volname zisla -srcfolder "$TEMPORARY_DIRECTORY" -format UDZO -ov "$DMG"

echo "$ARCHIVE"
echo "$DMG"
