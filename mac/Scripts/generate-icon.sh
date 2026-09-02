#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/Resources/AppIconSource.png"
STAGING_DIRECTORY="$(mktemp -d "$ROOT/Resources/.icon-generation.XXXXXX")"

cleanup() {
  [[ -d "$STAGING_DIRECTORY" ]] && find "$STAGING_DIRECTORY" -depth -delete
}
trap cleanup EXIT

generate_icon() {
  local theme="$1"
  local iconset="$2"
  local output="$3"
  local double

  rm -rf "$iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    swift "$ROOT/Scripts/generate-icon.swift" "$SOURCE" "$theme" "$size" "$iconset/icon_${size}x${size}.png"
    double=$((size * 2))
    swift "$ROOT/Scripts/generate-icon.swift" "$SOURCE" "$theme" "$double" "$iconset/icon_${size}x${size}@2x.png"
  done
  iconutil -c icns "$iconset" -o "$output"
  rm -rf "$iconset"
}

generate_icon day "$STAGING_DIRECTORY/AppIcon.iconset" "$STAGING_DIRECTORY/AppIcon.icns"
generate_icon night "$STAGING_DIRECTORY/AppIconNight.iconset" "$STAGING_DIRECTORY/AppIconNight.icns"
mv -f "$STAGING_DIRECTORY/AppIcon.icns" "$ROOT/Resources/AppIcon.icns"
mv -f "$STAGING_DIRECTORY/AppIconNight.icns" "$ROOT/Resources/AppIconNight.icns"
echo "$ROOT/Resources/AppIcon.icns"
echo "$ROOT/Resources/AppIconNight.icns"
