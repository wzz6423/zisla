#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
ICONSET="$ROOT/Resources/AppIcon.iconset"
OUTPUT="$ROOT/Resources/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  swift "$ROOT/Scripts/generate-icon.swift" "$size" "$ICONSET/icon_${size}x${size}.png"
  double=$((size * 2))
  swift "$ROOT/Scripts/generate-icon.swift" "$double" "$ICONSET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"
echo "$OUTPUT"
