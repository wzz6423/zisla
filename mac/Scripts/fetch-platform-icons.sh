#!/usr/bin/env bash
# Fetch platform logos used by the native downloader compact state.
#
# Source: simple-icons (CC0-1.0, public domain). Official brand glyphs only; no redrawing.
# Logos remain trademarks of their owners; used here only to identify download sources.
#
# Usage: mac/Scripts/fetch-platform-icons.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Resources/BrandIcons"
# Pin the commit so upstream redesigns do not drift outputs; update LICENSE.md when bumping.
COMMIT="25d6e5b39bc55bc446e147700294628af1734f7e"
BASE="https://raw.githubusercontent.com/simple-icons/simple-icons/$COMMIT/icons"

# asset name:simple-icons slug:official brand color (both taken verbatim from that commit's data/simple-icons.json)
# Douyin is deliberately absent: simple-icons has no Douyin glyph (3450 icons, zero matches), and drawing one
# ourselves is not allowed. It falls back at runtime to douyin.com's own favicon, which is the official logo.
ENTRIES=(
  "youtube.svg:youtube:#FF0000"
  "bilibili.svg:bilibili:#00A1D6"
  "xiaohongshu.svg:xiaohongshu:#FF2442"
  "weibo.svg:sinaweibo:#E6162D"
  "tiktok.svg:tiktok:#000000"
  "instagram.svg:instagram:#FF0069"
)

mkdir -p "$DEST"
failed=0

for entry in "${ENTRIES[@]}"; do
  IFS=':' read -r asset slug color <<<"$entry"
  url="$BASE/$slug.svg"
  tmp="$(mktemp)"

  if ! curl -fsSL --max-time 20 "$url" -o "$tmp"; then
    echo "✗ $asset  拉取失败：$url" >&2
    rm -f "$tmp"
    failed=$((failed + 1))
    continue
  fi

  # simple-icons paths are monochrome and unfilled; inject the official brand color and hard-code 24pt intrinsic size,
  # matching existing BrandIcons assets (AppKit CoreSVG requires explicit dimensions).
  python3 - "$tmp" "$color" <<'PY'
import re
import sys

path, color = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    svg = handle.read()

opening, _, rest = svg.partition(">")
# Child-element fills override root inheritance; clear them before injecting or the brand color silently fails.
rest = re.sub(r'\s+fill="[^"]*"', "", rest)

if "width=" not in opening:
    opening = opening.replace("<svg", '<svg width="24" height="24"', 1)
if "fill=" in opening:
    opening = re.sub(r'fill="[^"]*"', f'fill="{color}"', opening, count=1)
else:
    opening = opening.replace("<svg", f'<svg fill="{color}"', 1)

svg = opening + ">" + rest

with open(path, "w", encoding="utf-8") as handle:
    handle.write(svg)
PY

  mv "$tmp" "$DEST/$asset"
  echo "✓ $asset  ($slug, $color)"
done

echo
echo "注意：simple-icons 为单色字形，Instagram / TikTok 的官方渐变与双色错位会被压平为单色。"
echo "抖音无随包 logo（上游未收录），运行时改用 douyin.com 自身的 favicon。"

if [[ $failed -gt 0 ]]; then
  echo "$failed 个资源拉取失败，产物不完整。" >&2
  exit 1
fi
echo "完成。产物在 $DEST"
