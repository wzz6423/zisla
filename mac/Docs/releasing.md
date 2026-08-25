# Signing and release design

**English** | [简体中文](releasing.zh-CN.md)

The complete release process, dual update channels, and GitHub/Gitee asset synchronization are maintained by [`skills/zisla-release`](../../skills/zisla-release/SKILL.md). This page documents only the design constraints for signing, notarization, and update packages; follow the skill when publishing a release.

The app only checks releases and downloads DMGs. It never replaces or restarts itself. Developer ID packages should still be notarized. Free ad-hoc previews cannot be notarized and may require **Open Anyway** in System Settings on first launch.

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
```

### Free preview distribution

Without the Apple Developer Program, build an ad-hoc signed preview:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

This package is not notarized and does not include the WeatherKit entitlement. The app periodically checks GitHub/Gitee Releases; after a user confirms an available version, it downloads the matching DMG, which the user then opens and drags into `Applications`. The first launch may still require **System Settings > Privacy & Security > Open Anyway**. Developer ID signing and notarization remain the recommended path for distribution without security prompts.

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

Upload the DMG to releases with the same tag on GitHub and Gitee. A stable release must not be marked as a prerelease; a preview must be marked as a prerelease. The client uses its selected channel's Release API and chooses the DMG whose name contains `macOS`.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

hdiutil attach -nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
hdiutil detach /Volumes/zisla
```

Use an older app version to check the new release. Confirm that the DMG downloads to the selected directory without overwriting a file with the same name. For installation acceptance, quit zisla before mounting the DMG and dragging the app to `Applications`.
