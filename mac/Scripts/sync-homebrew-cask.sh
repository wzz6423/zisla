#!/bin/zsh
set -euo pipefail

# Rewrites Casks/zisla.rb for VERSION and, with PUBLISH_TAP=true, mirrors it to the
# Homebrew tap that serves `brew install --cask wzz6423/tap/zisla`.

ROOT="${0:A:h:h:h}"
VERSION="${VERSION:?VERSION is required}"
CASK_FILE="${CASK_FILE:-$ROOT/Casks/zisla.rb}"
RELEASE_OUTPUT_DIRECTORY="${RELEASE_OUTPUT_DIRECTORY:-}"
HOMEBREW_TAP_REPOSITORY="${HOMEBREW_TAP_REPOSITORY:-wzz6423/homebrew-tap}"
PUBLISH_TAP="${PUBLISH_TAP:-false}"
ARCHIVE_NAME="zisla-v${VERSION}-macOS-universal.zip"

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){2}$ ]] || {
  echo "error: VERSION must be a release version such as 1.2.3" >&2
  echo "note: previews stay off Homebrew so 'brew upgrade' never moves a user to a prerelease" >&2
  exit 1
}
case "$PUBLISH_TAP" in
  true|false) ;;
  *)
    echo "error: PUBLISH_TAP must be true or false" >&2
    exit 1
    ;;
esac
[[ -f "$CASK_FILE" ]] || { echo "error: missing cask: $CASK_FILE" >&2; exit 1; }

LOCAL_CHECKSUM_FILE="${RELEASE_OUTPUT_DIRECTORY:+$RELEASE_OUTPUT_DIRECTORY/$ARCHIVE_NAME.sha256}"
if [[ -n "$LOCAL_CHECKSUM_FILE" && -f "$LOCAL_CHECKSUM_FILE" ]]; then
  CHECKSUM="$(awk 'NR == 1 { print $1 }' "$LOCAL_CHECKSUM_FILE")"
  CHECKSUM_SOURCE="$LOCAL_CHECKSUM_FILE"
else
  CHECKSUM_SOURCE="https://github.com/wzz6423/zisla/releases/download/v${VERSION}/${ARCHIVE_NAME}.sha256"
  CHECKSUM="$(curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
    "$CHECKSUM_SOURCE" | awk 'NR == 1 { print $1 }')"
fi
[[ "$CHECKSUM" =~ '^[0-9a-f]{64}$' ]] || {
  echo "error: $CHECKSUM_SOURCE did not yield a SHA-256 digest" >&2
  exit 1
}

STAGED_CASK="$(mktemp "${TMPDIR:-/tmp}/zisla-cask.XXXXXX")"
TAP_CLONE=""
cleanup() {
  rm -f "$STAGED_CASK"
  if [[ -n "$TAP_CLONE" && "$TAP_CLONE" == "${TMPDIR:-/tmp}"* ]]; then
    rm -rf "$TAP_CLONE"
  fi
}
trap cleanup EXIT

sed -e "s|^  version \".*\"\$|  version \"${VERSION}\"|" \
  -e "s|^  sha256 \".*\"\$|  sha256 \"${CHECKSUM}\"|" \
  "$CASK_FILE" > "$STAGED_CASK"
ruby -c "$STAGED_CASK" >/dev/null
ruby "$ROOT/.github/scripts/homebrew-cask.rb" verify --cask "$STAGED_CASK" --version "$VERSION"
cat "$STAGED_CASK" > "$CASK_FILE"

echo "cask: ${CASK_FILE} now pins v${VERSION}"
echo "sha256: ${CHECKSUM} (from ${CHECKSUM_SOURCE})"

[[ "$PUBLISH_TAP" == true ]] || {
  echo "note: set PUBLISH_TAP=true to mirror this cask to ${HOMEBREW_TAP_REPOSITORY}"
  exit 0
}

TAP_CLONE="$(mktemp -d "${TMPDIR:-/tmp}/zisla-tap.XXXXXX")"
git clone --depth 1 "https://github.com/${HOMEBREW_TAP_REPOSITORY}.git" "$TAP_CLONE/tap"
mkdir -p "$TAP_CLONE/tap/Casks"
cat "$CASK_FILE" > "$TAP_CLONE/tap/Casks/zisla.rb"
git -C "$TAP_CLONE/tap" add Casks/zisla.rb
if git -C "$TAP_CLONE/tap" diff --cached --quiet; then
  echo "tap: ${HOMEBREW_TAP_REPOSITORY} already serves v${VERSION}"
  exit 0
fi
git -C "$TAP_CLONE/tap" commit --message "zisla ${VERSION}"
git -C "$TAP_CLONE/tap" push origin HEAD
echo "tap: ${HOMEBREW_TAP_REPOSITORY} now serves v${VERSION}"
