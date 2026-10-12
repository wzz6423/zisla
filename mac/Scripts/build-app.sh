#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-unknow}"
BUILD_NUMBER="${BUILD_NUMBER:-24}"
UPDATE_CHANNEL="${UPDATE_CHANNEL:-release}"
DEBUG_BUILD="${DEBUG_BUILD:-false}"
OUTPUT_DIRECTORY="${OUTPUT_DIRECTORY:-$ROOT/dist}"
BUILD_SCRATCH_DIRECTORY="${BUILD_SCRATCH_DIRECTORY:-$ROOT/.build}"

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "error: CONFIGURATION must be debug or release" >&2
    exit 1
    ;;
esac
case "$DEBUG_BUILD" in
  true|false) ;;
  *)
    echo "error: DEBUG_BUILD must be true or false" >&2
    exit 1
    ;;
esac

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
SIGNING_KEYCHAIN="${CODE_SIGN_KEYCHAIN:-}"
SIGNING_MODE="${SIGNING_MODE:-}"
BUILD_ARCHITECTURES="${BUILD_ARCHITECTURES:-$(uname -m)}"
ARCHITECTURES=(${=BUILD_ARCHITECTURES})
BINARIES=()
KEYBOARD_RESOURCE_BUNDLE=""
ZISLAKIT_RESOURCE_BUNDLE=""
HAND_BUILT_APP_SWIFT_FLAGS=(-Xswiftc -DSWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE)

[[ "$VERSION" == "unknow" || "$VERSION" =~ ^[0-9]+(\.[0-9]+){2}(-[A-Za-z0-9]+([.-][A-Za-z0-9]+)*)?$ ]] || {
  echo "error: VERSION must be unknow or a semantic version (for example 1.2.3 or 1.2.3-preview.1)" >&2
  exit 1
}
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || {
  echo "error: BUILD_NUMBER must contain only digits" >&2
  exit 1
}
(( ${#ARCHITECTURES[@]} > 0 )) || {
  echo "error: BUILD_ARCHITECTURES must contain at least one architecture" >&2
  exit 1
}

typeset -A SEEN_ARCHITECTURES=()
for ARCHITECTURE in "${ARCHITECTURES[@]}"; do
  case "$ARCHITECTURE" in
    arm64|x86_64) ;;
    *)
      echo "error: unsupported architecture: $ARCHITECTURE" >&2
      exit 1
      ;;
  esac
  [[ -z "${SEEN_ARCHITECTURES[$ARCHITECTURE]:-}" ]] || {
    echo "error: duplicate architecture: $ARCHITECTURE" >&2
    exit 1
  }
  SEEN_ARCHITECTURES[$ARCHITECTURE]=1
done

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

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"

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

if [[ -n "$SIGNING_KEYCHAIN" && ! -f "$SIGNING_KEYCHAIN" ]]; then
  echo "error: CODE_SIGN_KEYCHAIN does not exist: $SIGNING_KEYCHAIN" >&2
  exit 1
fi

case "$UPDATE_CHANNEL" in
  release|preview) ;;
  *)
    echo "error: UPDATE_CHANNEL must be release or preview" >&2
    exit 1
    ;;
esac

for ARCHITECTURE in "${ARCHITECTURES[@]}"; do
  TARGET_TRIPLE="${ARCHITECTURE}-apple-macosx"
  SCRATCH_DIRECTORY="$BUILD_SCRATCH_DIRECTORY/$ARCHITECTURE"
  swift build --package-path "$ROOT" -c "$CONFIGURATION" --disable-sandbox --scratch-path "$SCRATCH_DIRECTORY" --triple "$TARGET_TRIPLE" "${HAND_BUILT_APP_SWIFT_FLAGS[@]}" --product zisla
  BIN_DIRECTORY="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --disable-sandbox --scratch-path "$SCRATCH_DIRECTORY" --triple "$TARGET_TRIPLE" "${HAND_BUILT_APP_SWIFT_FLAGS[@]}" --show-bin-path)"
  BINARIES+=("$BIN_DIRECTORY/zisla")
  if [[ -z "$KEYBOARD_RESOURCE_BUNDLE" ]]; then
    KEYBOARD_RESOURCE_BUNDLE="$BIN_DIRECTORY/zisla_KeyboardKit.bundle"
  fi
  if [[ -z "$ZISLAKIT_RESOURCE_BUNDLE" ]]; then
    ZISLAKIT_RESOURCE_BUNDLE="$BIN_DIRECTORY/zisla_ZislaKit.bundle"
  fi
done

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks" "$CONTENTS/Helpers"
[[ -d "$KEYBOARD_RESOURCE_BUNDLE" ]] || {
  echo "error: missing KeyboardKit resource bundle: $KEYBOARD_RESOURCE_BUNDLE" >&2
  exit 1
}
[[ -d "$ZISLAKIT_RESOURCE_BUNDLE" ]] || {
  echo "error: missing ZislaKit resource bundle: $ZISLAKIT_RESOURCE_BUNDLE" >&2
  exit 1
}
ditto "$KEYBOARD_RESOURCE_BUNDLE" "$CONTENTS/Resources/zisla_KeyboardKit.bundle"
ditto "$ZISLAKIT_RESOURCE_BUNDLE" "$CONTENTS/Resources/zisla_ZislaKit.bundle"
if (( ${#BINARIES[@]} == 1 )); then
  install -m 0755 "$BINARIES[1]" "$CONTENTS/MacOS/zisla"
else
  lipo -create "${BINARIES[@]}" -output "$CONTENTS/MacOS/zisla"
  chmod 0755 "$CONTENTS/MacOS/zisla"
fi

# Xcode 27's SwiftPM links executables with the deployment target recorded as the SDK version;
# macOS 26+ then renders the app with legacy window chrome in compatibility mode instead of
# native Liquid Glass controls. Package.swift pins the real platform versions, so fail loudly
# if a toolchain drops them again.
LINKED_SDK_VERSION="$(vtool -show-build "$CONTENTS/MacOS/zisla" | awk '$1 == "sdk" { print $2; exit }')"
[[ "$LINKED_SDK_VERSION" == "$SDK_VERSION" ]] || {
  echo "error: linked SDK version is $LINKED_SDK_VERSION, expected $SDK_VERSION; the app would run with legacy window chrome" >&2
  exit 1
}

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

if [[ -d "$ROOT/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]]; then
  ditto \
    "$ROOT/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
    "$CONTENTS/Frameworks/Sparkle.framework"
  # Sparkle launches its installer through Updater.app. The final signature below runs with
  # --deep and regenerates the framework's CodeResources, so a missing Updater.app survives
  # every later codesign check and only surfaces as an update that refuses to install.
  if [[ ! -x "$CONTENTS/Frameworks/Sparkle.framework/Updater.app/Contents/MacOS/Updater" ]]; then
    echo "error: Sparkle.framework is missing Updater.app; updates would fail to install" >&2
    exit 1
  fi
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$CONTENTS/MacOS/zisla"
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
CERTIFICATE_SIGNING_ARGUMENTS=(--sign "$IDENTITY")
[[ -z "$SIGNING_KEYCHAIN" ]] || CERTIFICATE_SIGNING_ARGUMENTS+=(--keychain "$SIGNING_KEYCHAIN")
function sign_app() {
  if [[ "$SIGNING_MODE" == "adhoc" ]]; then
    # Ad-hoc signs cannot carry WeatherKit (or other restricted) entitlements.
    # Note: an ad hoc designated requirement is the build-specific cdhash,
    # so every rebuild silently invalidates TCC permissions (such as Accessibility).
    echo "warning: ad-hoc code signature (TeamIdentifier empty); WeatherKit unavailable, mainland China uses China Weather alerts" >&2
    codesign --force "$@" --sign - "$APP"
  elif [[ "$SIGNING_MODE" == "dev" ]]; then
    # A stable certificate identity keeps TCC permissions valid across builds. This mode also
    # signs self-signed releases, which cannot carry restricted Developer ID entitlements.
    # Do not include entitlements because restricted entitlements such as WeatherKit are rejected by AMFI without a provisioning profile,
    # and do not enable the hardened runtime because this path is not notarized.
    codesign --force "$@" "${CERTIFICATE_SIGNING_ARGUMENTS[@]}" "$APP"
  else
    if [[ ! -f "$ENTITLEMENTS" ]]; then
      echo "error: missing entitlements file: $ENTITLEMENTS" >&2
      exit 1
    fi
    codesign --force "$@" --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" \
      "${CERTIFICATE_SIGNING_ARGUMENTS[@]}" "$APP"
  fi
}
sign_app --deep
codesign --verify --deep --strict --all-architectures --verbose=2 "$APP"
SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if [[ "$SIGNING_MODE" == "adhoc" ]]; then
  [[ "$SIGNATURE_DETAILS" == *"Signature=adhoc"* ]] || {
    echo "error: expected an ad-hoc signature" >&2
    exit 1
  }
  [[ "$SIGNATURE_DETAILS" != *"Authority="* && "$SIGNATURE_DETAILS" == *"TeamIdentifier=not set"* ]] || {
    echo "error: ad-hoc build unexpectedly contains a certificate identity" >&2
    exit 1
  }
else
  [[ "$SIGNATURE_DETAILS" != *"Signature=adhoc"* && "$SIGNATURE_DETAILS" == *"Authority="* ]] || {
    echo "error: expected a certificate-backed code signature" >&2
    exit 1
  }
  DESIGNATED_REQUIREMENT="$(codesign -d -r- "$APP" 2>&1)"
  [[ "$DESIGNATED_REQUIREMENT" == *"certificate"* && "$DESIGNATED_REQUIREMENT" != *"designated => cdhash"* ]] || {
    echo "error: certificate signing did not produce a stable designated requirement" >&2
    exit 1
  }
fi

if [[ "$SIGNING_MODE" != "adhoc" ]]; then
  # SMJobBless needs stable mutual identities. Ad-hoc cdhashes change when the helper is embedded.
  APP_REQUIREMENT="${DESIGNATED_REQUIREMENT#*designated => }"
  POWER_HELPER_LABEL="$BUNDLE_ID.power-helper"
  POWER_HELPER_METADATA="$BUILD_SCRATCH_DIRECTORY/power-helper-metadata"
  mkdir -p "$POWER_HELPER_METADATA" "$CONTENTS/Library/LaunchServices"
  python3 - "$POWER_HELPER_METADATA" "$POWER_HELPER_LABEL" "$APP_REQUIREMENT" <<'PYTHON'
import pathlib
import plistlib
import sys

directory, label, client = sys.argv[1:]
metadata = {
    "Info.plist": {
        "CFBundleIdentifier": label,
        "CFBundleName": "zisla Power Helper",
        "CFBundleVersion": "1",
        "SMAuthorizedClients": [client],
    },
    "Launchd.plist": {
        "Label": label,
        "ProgramArguments": ["/Library/PrivilegedHelperTools/" + label],
        "MachServices": {label: True},
        "AbandonProcessGroup": True,
    },
}
for name, content in metadata.items():
    with (pathlib.Path(directory) / name).open("wb") as stream:
        plistlib.dump(content, stream)
PYTHON
  POWER_HELPER_BINARIES=()
  for ARCHITECTURE in "${ARCHITECTURES[@]}"; do
    TARGET_TRIPLE="${ARCHITECTURE}-apple-macosx"
    SCRATCH_DIRECTORY="$BUILD_SCRATCH_DIRECTORY/$ARCHITECTURE"
    swift build --package-path "$ROOT" -c "$CONFIGURATION" --disable-sandbox \
      --scratch-path "$SCRATCH_DIRECTORY" --triple "$TARGET_TRIPLE" \
      "${HAND_BUILT_APP_SWIFT_FLAGS[@]}" --product zisla-power-helper \
      -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$POWER_HELPER_METADATA/Info.plist" \
      -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __launchd_plist -Xlinker "$POWER_HELPER_METADATA/Launchd.plist"
    BIN_DIRECTORY="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --disable-sandbox \
      --scratch-path "$SCRATCH_DIRECTORY" --triple "$TARGET_TRIPLE" \
      "${HAND_BUILT_APP_SWIFT_FLAGS[@]}" --show-bin-path)"
    POWER_HELPER_BINARIES+=("$BIN_DIRECTORY/zisla-power-helper")
  done
  POWER_HELPER="$CONTENTS/Library/LaunchServices/$POWER_HELPER_LABEL"
  if (( ${#POWER_HELPER_BINARIES[@]} == 1 )); then
    install -m 0755 "$POWER_HELPER_BINARIES[1]" "$POWER_HELPER"
  else
    lipo -create "${POWER_HELPER_BINARIES[@]}" -output "$POWER_HELPER"
    chmod 0755 "$POWER_HELPER"
  fi
  POWER_HELPER_SIGNING_ARGUMENTS=()
  [[ "$SIGNING_MODE" != "release" ]] || POWER_HELPER_SIGNING_ARGUMENTS+=(--options runtime --timestamp)
  codesign --force --identifier "$POWER_HELPER_LABEL" "${CERTIFICATE_SIGNING_ARGUMENTS[@]}" \
    "${POWER_HELPER_SIGNING_ARGUMENTS[@]}" "$POWER_HELPER"
  POWER_HELPER_REQUIREMENT="$(codesign -d -r- "$POWER_HELPER" 2>&1)"
  POWER_HELPER_REQUIREMENT="${POWER_HELPER_REQUIREMENT#*designated => }"
  python3 - "$CONTENTS/Info.plist" "$POWER_HELPER_LABEL" "$POWER_HELPER_REQUIREMENT" <<'PYTHON'
import plistlib
import sys

path, label, requirement = sys.argv[1:]
with open(path, "rb") as stream:
    info = plistlib.load(stream)
info["SMPrivilegedExecutables"] = {label: requirement}
with open(path, "wb") as stream:
    plistlib.dump(info, stream)
PYTHON
  sign_app
  codesign --verify --deep --strict --all-architectures --verbose=2 "$APP"
  codesign --verify --strict --all-architectures -R "=$APP_REQUIREMENT" "$APP"
  codesign --verify --strict --all-architectures -R "=$POWER_HELPER_REQUIREMENT" "$POWER_HELPER"
fi
echo "$APP"
