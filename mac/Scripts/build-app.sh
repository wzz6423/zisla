#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUTPUT_DIRECTORY="${OUTPUT_DIRECTORY:-$ROOT/dist}"
APP="$OUTPUT_DIRECTORY/zisla.app"
CONTENTS="$APP/Contents"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
BUILD_ARCHITECTURES="${BUILD_ARCHITECTURES:-$(uname -m)}"
ARCHITECTURES=(${=BUILD_ARCHITECTURES})
BINARIES=()

for ARCHITECTURE in "${ARCHITECTURES[@]}"; do
  TARGET_TRIPLE="${ARCHITECTURE}-apple-macosx"
  swift build --package-path "$ROOT" -c "$CONFIGURATION" --disable-sandbox --triple "$TARGET_TRIPLE" --product zisla
  BIN_DIRECTORY="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --disable-sandbox --triple "$TARGET_TRIPLE" --show-bin-path)"
  BINARIES+=("$BIN_DIRECTORY/zisla")
done

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks" "$CONTENTS/Helpers"
if (( ${#BINARIES[@]} == 1 )); then
  install -m 0755 "$BINARIES[1]" "$CONTENTS/MacOS/zisla"
else
  lipo -create "${BINARIES[@]}" -output "$CONTENTS/MacOS/zisla"
  chmod 0755 "$CONTENTS/MacOS/zisla"
fi

sed \
  -e "s/@VERSION@/$VERSION/g" \
  -e "s/@BUILD_NUMBER@/$BUILD_NUMBER/g" \
  "$ROOT/Resources/Info.plist" > "$CONTENTS/Info.plist"

if [[ -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$CONTENTS/Info.plist"
fi

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  install -m 0644 "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

if [[ -d "$ROOT/Resources/BrandIcons" ]]; then
  ditto "$ROOT/Resources/BrandIcons" "$CONTENTS/Resources/BrandIcons"
fi

if [[ -d "$ROOT/Vendor/MediaRemoteAdapter.framework" ]]; then
  ditto "$ROOT/Vendor/MediaRemoteAdapter.framework" "$CONTENTS/Frameworks/MediaRemoteAdapter.framework"
fi

if [[ -f "$ROOT/Resources/MediaRemoteAdapter/mediaremote-adapter.pl" ]]; then
  mkdir -p "$CONTENTS/Resources/MediaRemoteAdapter"
  install -m 0755 \
    "$ROOT/Resources/MediaRemoteAdapter/mediaremote-adapter.pl" \
    "$CONTENTS/Resources/MediaRemoteAdapter/mediaremote-adapter.pl"
  install -m 0644 \
    "$ROOT/Resources/MediaRemoteAdapter/LICENSE" \
    "$CONTENTS/Resources/MediaRemoteAdapter/LICENSE"
fi

sparkle_framework="$(find "$ROOT/.build" -type d -name Sparkle.framework -print -quit)"
if [[ -n "$sparkle_framework" ]]; then
  ditto "$sparkle_framework" "$CONTENTS/Frameworks/Sparkle.framework"
  if ! otool -l "$CONTENTS/MacOS/zisla" | grep -Fq "path @executable_path/../Frameworks"; then
    install_name_tool -add_rpath @executable_path/../Frameworks "$CONTENTS/MacOS/zisla"
  fi
fi

helper="${YTDLP_BINARY:-$ROOT/Tools/yt-dlp}"
if [[ -x "$helper" ]]; then
  install -m 0755 "$helper" "$CONTENTS/Helpers/yt-dlp"
fi

ENTITLEMENTS="$ROOT/Resources/Zisla.entitlements"
if [[ "$IDENTITY" == "-" ]]; then
  # Ad-hoc signs cannot carry WeatherKit (or other restricted) entitlements.
  echo "warning: ad-hoc code signature (TeamIdentifier empty); WeatherKit unavailable, mainland China uses China Weather alerts" >&2
  codesign --force --deep --sign - "$APP"
else
  if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "error: missing entitlements file: $ENTITLEMENTS" >&2
    exit 1
  fi
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict --all-architectures --verbose=2 "$APP"
echo "$APP"
