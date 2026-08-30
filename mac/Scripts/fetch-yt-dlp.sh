#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${YTDLP_VERSION:-2026.06.09}"
DESTINATION="${1:-$ROOT/Tools/yt-dlp}"
WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/zisla-ytdlp.XXXXXX")"
TEMPORARY_DESTINATION=""

cleanup() {
  [[ -n "$TEMPORARY_DESTINATION" && -f "$TEMPORARY_DESTINATION" ]] && rm -f "$TEMPORARY_DESTINATION"
  [[ -d "$WORK_DIRECTORY" ]] && find "$WORK_DIRECTORY" -depth -delete
}
trap cleanup EXIT

[[ "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo "error: YTDLP_VERSION contains unsupported characters" >&2
  exit 1
}

mkdir -p "${DESTINATION:h}"
gh release download "$VERSION" \
  --repo yt-dlp/yt-dlp \
  --pattern yt-dlp_macos \
  --pattern SHA2-256SUMS \
  --dir "$WORK_DIRECTORY"

expected="$(awk '$2 == "yt-dlp_macos" { print $1 }' "$WORK_DIRECTORY/SHA2-256SUMS")"
actual="$(shasum -a 256 "$WORK_DIRECTORY/yt-dlp_macos" | awk '{ print $1 }')"
[[ -n "$expected" && "$actual" == "$expected" ]]
TEMPORARY_DESTINATION="$(mktemp "${DESTINATION:h}/.${DESTINATION:t}.install.XXXXXX")"
install -m 0755 "$WORK_DIRECTORY/yt-dlp_macos" "$TEMPORARY_DESTINATION"
mv -f "$TEMPORARY_DESTINATION" "$DESTINATION"
TEMPORARY_DESTINATION=""
echo "$DESTINATION"
