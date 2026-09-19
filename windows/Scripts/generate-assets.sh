#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/../mac/Resources/AppIconSource.png"
WORK_DIRECTORY="$(mktemp -d /tmp/zisla-windows-icons.XXXXXX)"
trap 'rm -rf "$WORK_DIRECTORY"' EXIT

swift "$ROOT/../mac/Scripts/generate-icon.swift" "$SOURCE" day 1024 "$WORK_DIRECTORY/day.png"
swift "$ROOT/../mac/Scripts/generate-icon.swift" "$SOURCE" night 1024 "$WORK_DIRECTORY/night.png"
swift "$ROOT/Scripts/generate-assets.swift" \
  "$WORK_DIRECTORY/day.png" \
  "$WORK_DIRECTORY/night.png" \
  "$ROOT/App/Assets"
