# AI Brand Icons

The SVG brand assets in this directory come from `lobehub/lobe-icons` at commit
`fbd2d56e3f734e889f1373e71c8368cc4e60e0d7` and are distributed under the MIT License.

Source: https://github.com/lobehub/lobe-icons

Product names and logos remain trademarks of their respective owners. The Grok and OpenAI
monochrome SVG fills were set to white for legibility on the black compact island surface.
Intrinsic SVG dimensions were normalized to 24 points. Gemini's layered color fills were
combined into one four-color gradient because AppKit CoreSVG does not render the upstream
layer stack reliably; its source path is unchanged.

`doubao.png` is the 192px official app favicon published at https://www.doubao.com/.
`qoder.icns`, `trae.icns`, and `workbuddy.icns` are official application icons retained as
offline fallbacks when their corresponding local clients are unavailable. Product names and
logos remain trademarks of their respective owners.

`copilot.svg` is the GitHub Copilot Codicon distributed with VS Code under the MIT License.
`github-mark.svg` is GitHub's official mark from `primer/octicons`, distributed under the MIT License.
`kimi.png` is the official Kimi Code extension icon published by Moonshot AI on Open VSX.

# Video Platform Icons

`youtube.svg`, `bilibili.svg`, `xiaohongshu.svg`, `weibo.svg`, `tiktok.svg`, and `instagram.svg` are
fetched by `Scripts/fetch-platform-icons.sh` from `simple-icons/simple-icons` at commit
`25d6e5b39bc55bc446e147700294628af1734f7e`, and are distributed under CC0-1.0 (public domain).
Asset-to-slug mapping and brand colors are taken verbatim from that commit's
`data/simple-icons.json` (note `weibo.svg` comes from the `sinaweibo` slug).

The script injects each brand's official color into the upstream monochrome glyph and normalizes
intrinsic SVG dimensions to 24 points, because AppKit CoreSVG requires explicit dimensions. No
glyph paths are redrawn or otherwise altered. simple-icons ships single-color glyphs, so
Instagram's gradient and TikTok's two-color offset are flattened to one color.

Douyin has no bundled asset: simple-icons does not carry a Douyin glyph at that commit, and drawing
a substitute ourselves is not acceptable. Douyin therefore uses the runtime favicon path below,
which serves its official icon straight from `douyin.com`.

Platforms without a bundled asset fall back to the site's own favicon, fetched at runtime from that
site and cached under `Application Support/favicons/`. Product names and logos remain trademarks of
their respective owners; they are used here only to identify a download's source.
