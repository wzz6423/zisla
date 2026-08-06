#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/Resources/AppIconSource.png"

generate_icon() {
  local theme="$1"
  local iconset="$2"
  local output="$3"

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

generate_icon day "$ROOT/Resources/AppIcon.iconset" "$ROOT/Resources/AppIcon.icns"
generate_icon night "$ROOT/Resources/AppIconNight.iconset" "$ROOT/Resources/AppIconNight.icns"
echo "$ROOT/Resources/AppIcon.icns"
echo "$ROOT/Resources/AppIconNight.icns"
