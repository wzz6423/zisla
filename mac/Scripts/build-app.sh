#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.1.3}"
BUILD_NUMBER="${BUILD_NUMBER:-6}"
UPDATE_CHANNEL="${UPDATE_CHANNEL:-release}"
OUTPUT_DIRECTORY="${OUTPUT_DIRECTORY:-$ROOT/dist}"
APP="$OUTPUT_DIRECTORY/zisla.app"
CONTENTS="$APP/Contents"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
BUILD_ARCHITECTURES="${BUILD_ARCHITECTURES:-$(uname -m)}"
ARCHITECTURES=(${=BUILD_ARCHITECTURES})
BINARIES=()

case "$UPDATE_CHANNEL" in
  release|preview) ;;
  *)
    echo "error: UPDATE_CHANNEL must be release or preview" >&2
    exit 1
    ;;
esac

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
  -e "s/@UPDATE_CHANNEL@/$UPDATE_CHANNEL/g" \
  "$ROOT/Resources/Info.plist" > "$CONTENTS/Info.plist"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  install -m 0644 "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi
if [[ -f "$ROOT/Resources/AppIconNight.icns" ]]; then
  install -m 0644 "$ROOT/Resources/AppIconNight.icns" "$CONTENTS/Resources/AppIconNight.icns"
fi

if [[ -d "$ROOT/Resources/BrandIcons" ]]; then
  ditto "$ROOT/Resources/BrandIcons" "$CONTENTS/Resources/BrandIcons"
fi

if [[ -d "$ROOT/Resources/Pets" ]]; then
  ditto "$ROOT/Resources/Pets" "$CONTENTS/Resources/Pets"
fi

if [[ -d "$ROOT/Resources/QuickNotes" ]]; then
  ditto "$ROOT/Resources/QuickNotes" "$CONTENTS/Resources/QuickNotes"
fi

if [[ -d "$ROOT/Resources/ThirdPartyLicenses" ]]; then
  ditto "$ROOT/Resources/ThirdPartyLicenses" "$CONTENTS/Resources/ThirdPartyLicenses"
fi

if [[ -d "$ROOT/Resources/Localization" ]]; then
  ditto "$ROOT/Resources/Localization" "$CONTENTS/Resources"
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

helper="${YTDLP_BINARY:-$ROOT/Tools/yt-dlp}"
if [[ -x "$helper" ]]; then
  install -m 0755 "$helper" "$CONTENTS/Helpers/yt-dlp"
fi

ENTITLEMENTS="$ROOT/Resources/Zisla.entitlements"
if [[ "$IDENTITY" == "-" ]]; then
  # Ad-hoc signs cannot carry WeatherKit (or other restricted) entitlements.
  # Note: an ad hoc designated requirement is the build-specific cdhash,
  # so every rebuild silently invalidates TCC permissions (such as Accessibility).
  echo "warning: ad-hoc code signature (TeamIdentifier empty); WeatherKit unavailable, mainland China uses China Weather alerts" >&2
  codesign --force --deep --sign - "$APP"
elif [[ "${SIGNING_MODE:-release}" == "dev" ]]; then
  # Development signing: a stable certificate identity keeps TCC permissions valid across builds.
  # Do not include entitlements because restricted entitlements such as WeatherKit are rejected by AMFI without a provisioning profile,
  # and do not enable the hardened runtime because local debugging does not require it.
  codesign --force --deep --sign "$IDENTITY" "$APP"
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
