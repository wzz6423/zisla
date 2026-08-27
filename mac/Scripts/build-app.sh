#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.1.7}"
BUILD_NUMBER="${BUILD_NUMBER:-13}"
UPDATE_CHANNEL="${UPDATE_CHANNEL:-release}"
DEBUG_BUILD="${DEBUG_BUILD:-false}"
OUTPUT_DIRECTORY="${OUTPUT_DIRECTORY:-$ROOT/dist}"

if [[ "$DEBUG_BUILD" == "true" ]]; then
  APP_NAME="zisla-debug"
  BUNDLE_ID="dev.wzz.zisla.debug"
  APP_SUPPORT_DIRECTORY="zisla-debug"
  ICON_FILE="AppIconNight"
else
  APP_NAME="zisla"
  BUNDLE_ID="dev.wzz.zisla"
  APP_SUPPORT_DIRECTORY="zisla"
  ICON_FILE="AppIcon"
fi

APP="$OUTPUT_DIRECTORY/$APP_NAME.app"
CONTENTS="$APP/Contents"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGNING_MODE="${SIGNING_MODE:-}"
BUILD_ARCHITECTURES="${BUILD_ARCHITECTURES:-$(uname -m)}"
ARCHITECTURES=(${=BUILD_ARCHITECTURES})
BINARIES=()
HAND_BUILT_APP_SWIFT_FLAGS=(-Xswiftc -DSWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE)

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){2}([.-][A-Za-z0-9.-]+)?$ ]] || {
  echo "error: VERSION must be a semantic version (for example 1.2.3 or 1.2.3-preview.1)" >&2
  exit 1
}
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || {
  echo "error: BUILD_NUMBER must contain only digits" >&2
  exit 1
}

function supports_swiftui_macros() {
  local developer_directory="$1"

  [[ -x "$developer_directory/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" && \
    -f "$developer_directory/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]]
}

function resolve_developer_directory() {
  local selected_directory
  local xcode_app
  local candidate
  local -a candidates

  candidates=()
  [[ -n "${DEVELOPER_DIR:-}" ]] && candidates+=("$DEVELOPER_DIR")

  selected_directory="$(xcode-select -p 2>/dev/null || true)"
  [[ -n "$selected_directory" ]] && candidates+=("$selected_directory")

  for xcode_app in ${(f)"$(mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"' 2>/dev/null || true)"}; do
    candidates+=("$xcode_app/Contents/Developer")
  done
  for xcode_app in /Applications/Xcode*.app(N); do
    candidates+=("$xcode_app/Contents/Developer")
  done

  for candidate in "${candidates[@]}"; do
    if supports_swiftui_macros "$candidate"; then
      print -r -- "$candidate"
      return
    fi
  done

  echo "error: a full Xcode installation with SwiftUI macro support is required; install Xcode or set DEVELOPER_DIR" >&2
  exit 1
}

export DEVELOPER_DIR="$(resolve_developer_directory)"

if [[ -z "$SIGNING_MODE" ]]; then
  if [[ "$IDENTITY" == "-" ]]; then
    SIGNING_MODE="adhoc"
  else
    SIGNING_MODE="release"
  fi
fi

case "$SIGNING_MODE" in
  adhoc)
    [[ "$IDENTITY" == "-" ]] || {
      echo "error: SIGNING_MODE=adhoc requires CODE_SIGN_IDENTITY=-" >&2
      exit 1
    }
    ;;
  dev|release)
    [[ "$IDENTITY" != "-" ]] || {
      echo "error: SIGNING_MODE=$SIGNING_MODE requires a certificate identity" >&2
      exit 1
    }
    ;;
  *)
    echo "error: SIGNING_MODE must be adhoc, dev, or release" >&2
    exit 1
    ;;
esac

case "$UPDATE_CHANNEL" in
  release|preview) ;;
  *)
    echo "error: UPDATE_CHANNEL must be release or preview" >&2
    exit 1
    ;;
esac

for ARCHITECTURE in "${ARCHITECTURES[@]}"; do
  TARGET_TRIPLE="${ARCHITECTURE}-apple-macosx"
  SCRATCH_DIRECTORY="$ROOT/.build/$ARCHITECTURE"
  swift build --package-path "$ROOT" -c "$CONFIGURATION" --disable-sandbox --scratch-path "$SCRATCH_DIRECTORY" --triple "$TARGET_TRIPLE" "${HAND_BUILT_APP_SWIFT_FLAGS[@]}" --product zisla
  BIN_DIRECTORY="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --disable-sandbox --scratch-path "$SCRATCH_DIRECTORY" --triple "$TARGET_TRIPLE" "${HAND_BUILT_APP_SWIFT_FLAGS[@]}" --show-bin-path)"
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
  -e "s/@APP_NAME@/$APP_NAME/g" \
  -e "s/@BUNDLE_ID@/$BUNDLE_ID/g" \
  -e "s/@APP_SUPPORT_DIRECTORY@/$APP_SUPPORT_DIRECTORY/g" \
  "$ROOT/Resources/Info.plist" > "$CONTENTS/Info.plist"

if [[ "$DEBUG_BUILD" == "true" ]]; then
  [[ -f "$ROOT/Resources/$ICON_FILE.icns" ]] || {
    echo "error: missing debug icon: $ROOT/Resources/$ICON_FILE.icns" >&2
    exit 1
  }
  install -m 0644 "$ROOT/Resources/$ICON_FILE.icns" "$CONTENTS/Resources/AppIcon.icns"
  install -m 0644 "$ROOT/Resources/$ICON_FILE.icns" "$CONTENTS/Resources/AppIconNight.icns"
else
  if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    install -m 0644 "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
  fi
  if [[ -f "$ROOT/Resources/AppIconNight.icns" ]]; then
    install -m 0644 "$ROOT/Resources/AppIconNight.icns" "$CONTENTS/Resources/AppIconNight.icns"
  fi
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
if [[ "$SIGNING_MODE" == "adhoc" ]]; then
  # Ad-hoc signs cannot carry WeatherKit (or other restricted) entitlements.
  # Note: an ad hoc designated requirement is the build-specific cdhash,
  # so every rebuild silently invalidates TCC permissions (such as Accessibility).
  echo "warning: ad-hoc code signature (TeamIdentifier empty); WeatherKit unavailable, mainland China uses China Weather alerts" >&2
  codesign --force --deep --sign - "$APP"
elif [[ "$SIGNING_MODE" == "dev" ]]; then
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
if [[ "$SIGNING_MODE" == "adhoc" ]]; then
  SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
  [[ "$SIGNATURE_DETAILS" == *"Signature=adhoc"* ]] || {
    echo "error: expected an ad-hoc signature" >&2
    exit 1
  }
  [[ "$SIGNATURE_DETAILS" != *"Authority="* && "$SIGNATURE_DETAILS" == *"TeamIdentifier=not set"* ]] || {
    echo "error: ad-hoc build unexpectedly contains a certificate identity" >&2
    exit 1
  }
fi
echo "$APP"
