#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:?VERSION is required}"
BUILD_NUMBER="${BUILD_NUMBER:?BUILD_NUMBER is required (for example 12)}"
UPDATE_CHANNEL="${UPDATE_CHANNEL:-release}"
TMP_ROOT="${TMPDIR:-/tmp}"
ARCHIVE_DIRECTORY="${ARCHIVE_DIRECTORY:-$ROOT/dist}"
BUILD_SCRATCH_DIRECTORY="${BUILD_SCRATCH_DIRECTORY:-$ROOT/.build}"
BUILD_ARCHITECTURES="${BUILD_ARCHITECTURES:-arm64 x86_64}"
ARCHITECTURES=(${=BUILD_ARCHITECTURES})
SKIP_BUILD="${SKIP_BUILD:-false}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-zisla-update-ed25519}"
SPARKLE_ED_KEY_FILE="${SPARKLE_ED_KEY_FILE:-}"
SPARKLE_GITEE_DOWNLOAD_URL_PREFIX="${SPARKLE_GITEE_DOWNLOAD_URL_PREFIX:-https://gitee.com/wzz6423/zisla/releases/download/v${VERSION}/}"
SPARKLE_GITHUB_DOWNLOAD_URL_PREFIX="${SPARKLE_GITHUB_DOWNLOAD_URL_PREFIX:-https://github.com/wzz6423/zisla/releases/download/v${VERSION}/}"

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){2}(-[A-Za-z0-9]+([.-][A-Za-z0-9]+)*)?$ ]] || {
  echo "error: VERSION must be a semantic version (for example 1.2.3 or 1.2.3-preview.1)" >&2
  exit 1
}
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || {
  echo "error: BUILD_NUMBER must contain only digits" >&2
  exit 1
}
case "$UPDATE_CHANNEL" in
  release|preview) ;;
  *)
    echo "error: UPDATE_CHANNEL must be release or preview" >&2
    exit 1
    ;;
esac
case "$SKIP_BUILD" in
  true|false) ;;
  *)
    echo "error: SKIP_BUILD must be true or false" >&2
    exit 1
    ;;
esac

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
GITEE_APPCAST="$ARCHIVE_DIRECTORY/appcast-gitee.xml"
GITHUB_APPCAST="$ARCHIVE_DIRECTORY/appcast-github.xml"

if [[ "$SKIP_BUILD" == "true" ]]; then
  [[ -d "$APP" ]] || { echo "error: missing app bundle: $APP" >&2; exit 1; }
else
  if [[ "${CODE_SIGN_IDENTITY:--}" == "-" ]]; then
    RELEASE_SIGNING_MODE=adhoc
  else
    RELEASE_SIGNING_MODE=release
  fi
  DEBUG_BUILD=false VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" UPDATE_CHANNEL="$UPDATE_CHANNEL" \
    SIGNING_MODE="$RELEASE_SIGNING_MODE" \
    OUTPUT_DIRECTORY="$ARCHIVE_DIRECTORY" BUILD_SCRATCH_DIRECTORY="$BUILD_SCRATCH_DIRECTORY" \
    BUILD_ARCHITECTURES="$BUILD_ARCHITECTURES" \
    "$ROOT/Scripts/build-app.sh"
fi

INFO_PLIST="$APP/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]] || { echo "error: missing release Info.plist: $INFO_PLIST" >&2; exit 1; }
RELEASE_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST" 2>/dev/null || true)"
RELEASE_DISPLAY_NAME="$(plutil -extract CFBundleDisplayName raw -o - "$INFO_PLIST" 2>/dev/null || true)"
RELEASE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST" 2>/dev/null || true)"
RELEASE_BUILD_NUMBER="$(plutil -extract CFBundleVersion raw -o - "$INFO_PLIST" 2>/dev/null || true)"
RELEASE_UPDATE_CHANNEL="$(plutil -extract ZislaDefaultUpdateChannel raw -o - "$INFO_PLIST" 2>/dev/null || true)"
RELEASE_GITEE_FEED_URL="$(plutil -extract SUFeedURL raw -o - "$INFO_PLIST" 2>/dev/null || true)"
RELEASE_GITHUB_FALLBACK_FEED_URL="$(plutil -extract ZislaReleaseFallbackAppcastURL raw -o - "$INFO_PLIST" 2>/dev/null || true)"
PREVIEW_GITEE_FEED_URL="$(plutil -extract ZislaPreviewAppcastURL raw -o - "$INFO_PLIST" 2>/dev/null || true)"
PREVIEW_GITHUB_FALLBACK_FEED_URL="$(plutil -extract ZislaPreviewFallbackAppcastURL raw -o - "$INFO_PLIST" 2>/dev/null || true)"
[[ "$RELEASE_BUNDLE_ID" == "dev.wzz.zisla" && "$RELEASE_DISPLAY_NAME" == "zisla" ]] || {
  echo "error: release package contains a debug or unknown app identity" >&2
  exit 1
}
[[ "$RELEASE_VERSION" == "$VERSION" && "$RELEASE_BUILD_NUMBER" == "$BUILD_NUMBER" && \
  "$RELEASE_UPDATE_CHANNEL" == "$UPDATE_CHANNEL" ]] || {
  echo "error: release package metadata does not match VERSION, BUILD_NUMBER, or UPDATE_CHANNEL" >&2
  exit 1
}
[[ "$RELEASE_GITEE_FEED_URL" == "https://gitee.com/wzz6423/zisla/releases/download/update-release/appcast.xml" && \
  "$RELEASE_GITHUB_FALLBACK_FEED_URL" == "https://github.com/wzz6423/zisla/releases/latest/download/appcast.xml" && \
  "$PREVIEW_GITEE_FEED_URL" == "https://gitee.com/wzz6423/zisla/releases/download/preview/appcast.xml" && \
  "$PREVIEW_GITHUB_FALLBACK_FEED_URL" == "https://github.com/wzz6423/zisla/releases/download/preview/appcast.xml" ]] || {
  echo "error: release package is missing a configured Sparkle update feed" >&2
  exit 1
}
codesign --verify --deep --strict --all-architectures --verbose=2 "$APP" || {
  echo "error: release package code signature verification failed" >&2
  exit 1
}

mkdir -p "$ARCHIVE_DIRECTORY"
PACKAGE_STAGING_DIRECTORY="$(mktemp -d "${ARCHIVE_DIRECTORY%/}/.zisla-package.XXXXXX")"
STAGED_ARCHIVE="$PACKAGE_STAGING_DIRECTORY/${ARCHIVE:t}"
STAGED_DMG="$PACKAGE_STAGING_DIRECTORY/${DMG:t}"
STAGED_GITEE_APPCAST="$PACKAGE_STAGING_DIRECTORY/${GITEE_APPCAST:t}"
STAGED_GITHUB_APPCAST="$PACKAGE_STAGING_DIRECTORY/${GITHUB_APPCAST:t}"
TEMPORARY_DIRECTORY=""
WRITABLE_IMAGE=""
MOUNTED_DEVICE=""
MOUNT_POINT=""
cleanup() {
  if [[ -n "$MOUNTED_DEVICE" ]]; then
    diskutil eject "$MOUNTED_DEVICE" >/dev/null 2>&1 || true
  fi
  if [[ -n "$WRITABLE_IMAGE" && "$WRITABLE_IMAGE" == "${TMP_ROOT%/}/zisla-dmg."*.asif ]]; then
    rm -f "$WRITABLE_IMAGE"
  fi
  if [[ -n "$TEMPORARY_DIRECTORY" && "$TEMPORARY_DIRECTORY" == "${TMP_ROOT%/}/zisla-dmg."* ]]; then
    rm -rf "$TEMPORARY_DIRECTORY"
  fi
  if [[ "$PACKAGE_STAGING_DIRECTORY" == "${ARCHIVE_DIRECTORY%/}/.zisla-package."* ]]; then
    rm -rf "$PACKAGE_STAGING_DIRECTORY"
  fi
}
trap cleanup EXIT

TEMPORARY_DIRECTORY="$(mktemp -d "${TMP_ROOT%/}/zisla-dmg.XXXXXX")"
WRITABLE_IMAGE="${TEMPORARY_DIRECTORY}.asif"

ditto -c -k --keepParent "$APP" "$STAGED_ARCHIVE"
(
  cd "$PACKAGE_STAGING_DIRECTORY"
  shasum -a 256 "${STAGED_ARCHIVE:t}" > "${STAGED_ARCHIVE:t}.sha256"
)
[[ -n "$SPARKLE_GENERATE_APPCAST" && -x "$SPARKLE_GENERATE_APPCAST" ]] || {
  echo "error: SPARKLE_GENERATE_APPCAST must point to Sparkle's generate_appcast tool" >&2
  exit 1
}
[[ "$SPARKLE_GITEE_DOWNLOAD_URL_PREFIX" == https://* && \
  "$SPARKLE_GITHUB_DOWNLOAD_URL_PREFIX" == https://* ]] || {
  echo "error: Sparkle download URL prefixes must use HTTPS" >&2
  exit 1
}
if [[ -n "$SPARKLE_ED_KEY_FILE" ]]; then
  [[ -f "$SPARKLE_ED_KEY_FILE" ]] || {
    echo "error: SPARKLE_ED_KEY_FILE must point to a readable private EdDSA key file" >&2
    exit 1
  }
  SPARKLE_KEY_ARGUMENTS=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
else
  SPARKLE_KEY_ARGUMENTS=(--account "$SPARKLE_KEY_ACCOUNT")
fi
"$SPARKLE_GENERATE_APPCAST" \
  "${SPARKLE_KEY_ARGUMENTS[@]}" \
  --download-url-prefix "$SPARKLE_GITEE_DOWNLOAD_URL_PREFIX" \
  -o "$STAGED_GITEE_APPCAST" \
  "$PACKAGE_STAGING_DIRECTORY"
"$SPARKLE_GENERATE_APPCAST" \
  "${SPARKLE_KEY_ARGUMENTS[@]}" \
  --download-url-prefix "$SPARKLE_GITHUB_DOWNLOAD_URL_PREFIX" \
  -o "$STAGED_GITHUB_APPCAST" \
  "$PACKAGE_STAGING_DIRECTORY"
[[ -s "$STAGED_GITEE_APPCAST" && -s "$STAGED_GITHUB_APPCAST" ]] || {
  echo "error: Sparkle appcasts were not generated" >&2
  exit 1
}

ditto "$APP" "$TEMPORARY_DIRECTORY/zisla.app"
# `diskutil image create` cannot produce UDRW, so staging uses ASIF, its
# single-file writable format. The shipped DMG is still UDZO.
diskutil image create from "$TEMPORARY_DIRECTORY" --format ASIF --volumeName zisla "$WRITABLE_IMAGE" >/dev/null

ATTACH_OUTPUT="$(diskutil image attach --mountOptions nobrowse "$WRITABLE_IMAGE")"
while read -r device _ mount_point; do
  device="${device%%[[:space:]]*}"
  if [[ "$device" == /dev/disk* && -n "$mount_point" ]]; then
    MOUNTED_DEVICE="$device"
    MOUNT_POINT="$mount_point"
  fi
done <<< "$ATTACH_OUTPUT"
[[ -n "$MOUNTED_DEVICE" && -n "$MOUNT_POINT" ]] || { echo "error: failed to mount DMG" >&2; exit 1; }

ln -s /Applications "$MOUNT_POINT/Applications"

# Store the icon positions in Finder's .DS_Store so installation reads left to right.
if ! osascript - "$MOUNT_POINT" <<'APPLESCRIPT'
on run argv
set mountedVolumeAlias to POSIX file (item 1 of argv) as alias
tell application "Finder"
  set mountedVolume to item mountedVolumeAlias
  tell mountedVolume
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
end run
APPLESCRIPT
then
  echo "warning: unable to set Finder icon positions; creating DMG without a custom layout" >&2
fi

sync
diskutil eject "$MOUNTED_DEVICE" >/dev/null
MOUNTED_DEVICE=""
diskutil image create from "$WRITABLE_IMAGE" --format UDZO "$STAGED_DMG" >/dev/null
hdiutil verify "$STAGED_DMG"
(
  cd "$PACKAGE_STAGING_DIRECTORY"
  shasum -a 256 "${STAGED_DMG:t}" > "${STAGED_DMG:t}.sha256"
)

mv -f "$STAGED_ARCHIVE" "$ARCHIVE"
mv -f "${STAGED_ARCHIVE}.sha256" "${ARCHIVE}.sha256"
mv -f "$STAGED_DMG" "$DMG"
mv -f "${STAGED_DMG}.sha256" "${DMG}.sha256"
mv -f "$STAGED_GITEE_APPCAST" "$GITEE_APPCAST"
mv -f "$STAGED_GITHUB_APPCAST" "$GITHUB_APPCAST"

echo "$ARCHIVE"
echo "$DMG"
echo "$GITEE_APPCAST"
echo "$GITHUB_APPCAST"
