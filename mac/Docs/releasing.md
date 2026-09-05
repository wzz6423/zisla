# Signing and release design

**English** | [简体中文](releasing.zh-CN.md)

The complete release process, dual update channels, and GitHub/Gitee asset synchronization are maintained by [`skills/zisla-release`](../../skills/zisla-release/SKILL.md). This page documents only the design constraints for signing, notarization, and update packages; follow the skill when publishing a release.

Both selected update channels use Sparkle to verify a signed ZIP and appcast before replacing and relaunching the app. Each check reads Gitee first and retries GitHub exactly once when the Gitee appcast cannot load or its update package fails to download. `package-release.sh` requires `SPARKLE_GENERATE_APPCAST` to point to Sparkle 2.9.4's `generate_appcast` and writes `appcast-gitee.xml` and `appcast-github.xml` alongside the ZIP and DMG. Each appcast must be signed independently and point to the Universal ZIP hosted by its own site. Upload each as `appcast.xml` to its respective release: Gitee keeps permanent `update-release` (Release) and `preview` (Preview) feeds; GitHub uses `latest` for Release and permanent prerelease `preview` for Preview. Set `SPARKLE_ED_KEY_FILE` to the privately stored EdDSA key file when publishing non-interactively, or leave it unset to use the `zisla-update-ed25519` login-keychain account. The private key must never enter the repository. Developer ID packages should still be notarized. Free ad-hoc previews cannot be notarized and may require **Open Anyway** in System Settings on first launch.

## Prerequisites

- A Developer ID Application certificate
- Apple notarization credentials
- The official `yt-dlp` helper fetched and verified through `Scripts/fetch-yt-dlp.sh`

## 1. Build a signed app

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Output:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Free preview distribution

Without the Apple Developer Program, build an ad-hoc signed preview:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

This package is not notarized and does not include the WeatherKit entitlement. After publishing its signed appcast to the permanent Preview feed, the app checks, downloads, verifies, installs, and relaunches Preview updates through Sparkle. The first launch may still require **System Settings > Privacy & Security > Open Anyway**. Developer ID signing and notarization remain the recommended path for distribution without security prompts.

## 2. Notarize

```bash
xcrun notarytool submit \
  dist/zisla-v1.0.0-macOS-universal.zip \
  --keychain-profile AC_NOTARY \
  --wait

xcrun stapler staple 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'

# Repackage the stapled app so both the ZIP and DMG contain the final artifact.
export SKIP_BUILD=true
Scripts/package-release.sh
```

## 3. Publish and verify

Upload the ZIP, DMG, checksums, and `appcast-github.xml` as `appcast.xml` to the same versioned GitHub tag; upload the matching assets and `appcast-gitee.xml` as `appcast.xml` to the same Gitee tag. A stable release must not be marked as a prerelease. Copy the Gitee appcast to permanent `update-release`; copy Preview appcasts to permanent `preview` on both sites. The selected channel then checks Gitee first and retries GitHub once when Gitee's appcast cannot load or its update package fails to download.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

Use an older app version to check the new release. Confirm that automatic and manual checks use the selected Gitee feed first, retry its GitHub counterpart once when Gitee cannot load or its package download fails, and that Sparkle verifies, installs, and relaunches the Universal ZIP. Test Release→Preview and Preview→Release switching as well as same-channel updates.

## 4. Sync the Homebrew cask

A stable release ends at Homebrew. Preview releases stop before this step: the tap serves stable versions only, so `brew upgrade` never moves a user onto a prerelease.

From the repository root, after the release assets are published:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

The script rewrites `version` and both `sha256` values in `Casks/zisla.rb`, reading each digest from `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` and its `x86_64` counterpart when those files exist and from the published GitHub assets otherwise. The cask resolves `#{arch}` per machine, so Apple Silicon and Intel download only their own slice; verification rejects a cask that reuses one digest for both. It refuses to write a cask that fails `homebrew-cask.rb verify`, then mirrors the file to `wzz6423/homebrew-tap`. Omit `PUBLISH_TAP` for a dry run that only updates the in-repo cask.

The cask carries `auto_updates true` because Sparkle owns the update path: a plain `brew upgrade` leaves the app alone, and only `brew upgrade --cask zisla` or `--greedy` makes Homebrew replace it. Commit the rewritten cask together with the site's `latestRelease` bump — CI fails when the two pin different versions. Then confirm the tap:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew livecheck --cask wzz6423/tap/zisla
```
