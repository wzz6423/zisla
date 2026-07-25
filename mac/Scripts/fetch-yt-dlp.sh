#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${YTDLP_VERSION:-2026.06.09}"
DESTINATION="${1:-$ROOT/Tools/yt-dlp}"
WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/zisla-ytdlp.XXXXXX")"
trap 'rm -rf "$WORK_DIRECTORY"' EXIT

mkdir -p "${DESTINATION:h}"
gh release download "$VERSION" \
  --repo yt-dlp/yt-dlp \
  --pattern yt-dlp_macos \
  --pattern SHA2-256SUMS \
  --dir "$WORK_DIRECTORY"

expected="$(awk '$2 == "yt-dlp_macos" { print $1 }' "$WORK_DIRECTORY/SHA2-256SUMS")"
actual="$(shasum -a 256 "$WORK_DIRECTORY/yt-dlp_macos" | awk '{ print $1 }')"
[[ -n "$expected" && "$actual" == "$expected" ]]
install -m 0755 "$WORK_DIRECTORY/yt-dlp_macos" "$DESTINATION"
echo "$DESTINATION"
