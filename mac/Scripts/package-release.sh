#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:?VERSION is required}"
BUILD_NUMBER="${BUILD_NUMBER:-${VERSION//./}}"
UPDATE_CHANNEL="${UPDATE_CHANNEL:-release}"
ARCHIVE_DIRECTORY="${ARCHIVE_DIRECTORY:-$ROOT/dist}"
BUILD_ARCHITECTURES="${BUILD_ARCHITECTURES:-arm64 x86_64}"
ARCHITECTURES=(${=BUILD_ARCHITECTURES})

for arch in "${ARCHITECTURES[@]}"; do
  case "$arch" in
    arm64|x86_64) ;;
    *)
      echo "error: unsupported architecture: $arch" >&2
      exit 1
      ;;
  esac
done

if (( ${#ARCHITECTURES[@]} == 1 )); then
  ARCHITECTURE_SUFFIX="${ARCHITECTURES[1]}"
elif (( ${#ARCHITECTURES[@]} == 2 )) && [[ "${ARCHITECTURES[*]}" == "arm64 x86_64" || "${ARCHITECTURES[*]}" == "x86_64 arm64" ]]; then
  ARCHITECTURE_SUFFIX="universal"
else
  echo "error: unsupported architecture combination: $BUILD_ARCHITECTURES" >&2
  exit 1
fi

APP="$ARCHIVE_DIRECTORY/zisla.app"
ARCHIVE="$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-${ARCHITECTURE_SUFFIX}.zip"
DMG="$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-${ARCHITECTURE_SUFFIX}.dmg"

if [[ "${SKIP_BUILD:-false}" == "true" ]]; then
  [[ -d "$APP" ]] || { echo "error: missing app bundle: $APP" >&2; exit 1; }
else
  VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" UPDATE_CHANNEL="$UPDATE_CHANNEL" OUTPUT_DIRECTORY="$ARCHIVE_DIRECTORY" BUILD_ARCHITECTURES="$BUILD_ARCHITECTURES" "$ROOT/Scripts/build-app.sh"
fi

ditto -c -k --keepParent "$APP" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"

TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR%/}/zisla-dmg.XXXXXX")"
WRITABLE_DMG="${TEMPORARY_DIRECTORY}.dmg"
MOUNTED_DEVICE=""
cleanup() {
  if [[ -n "$MOUNTED_DEVICE" ]]; then
    hdiutil detach -quiet "$MOUNTED_DEVICE" || true
  fi
  [[ "$WRITABLE_DMG" == "${TMPDIR%/}/zisla-dmg."*.dmg ]] || return
  rm -f "$WRITABLE_DMG"
  [[ "$TEMPORARY_DIRECTORY" == "${TMPDIR%/}/zisla-dmg."* ]] || return
  rm -rf "$TEMPORARY_DIRECTORY"
}
trap cleanup EXIT

ditto "$APP" "$TEMPORARY_DIRECTORY/zisla.app"
ln -s /Applications "$TEMPORARY_DIRECTORY/Applications"
hdiutil create -quiet -volname zisla -srcfolder "$TEMPORARY_DIRECTORY" -format UDRW -ov "$WRITABLE_DMG"

MOUNTED_DEVICE="$(
  hdiutil attach -readwrite -noverify -noautoopen "$WRITABLE_DMG" \
    | awk '/^\/dev\/disk/ { print $1; exit }'
)"
[[ -n "$MOUNTED_DEVICE" ]] || { echo "error: failed to mount DMG" >&2; exit 1; }

# Store the icon positions in Finder's .DS_Store so installation reads left to right.
if ! osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "zisla"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 740, 440}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 12
    set position of item "zisla.app" of container window to {175, 160}
    set position of item "Applications" of container window to {475, 160}
    close
  end tell
end tell
APPLESCRIPT
then
  echo "warning: unable to set Finder icon positions; creating DMG without a custom layout" >&2
fi

sync
hdiutil detach -quiet "$MOUNTED_DEVICE"
MOUNTED_DEVICE=""
hdiutil convert -quiet "$WRITABLE_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG"

echo "$ARCHIVE"
echo "$DMG"
