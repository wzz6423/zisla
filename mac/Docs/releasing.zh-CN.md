# 签名与发布设计

[English](releasing.md) | **简体中文**

项目的完整发布流程、双更新通道和 GitHub/Gitee 的资产同步由仓库根目录的 [`skills/zisla-release`](../../skills/zisla-release/SKILL.md) 统一维护。本页只说明签名、公证和更新包的设计约束；发布时以该技能为准。

当前选择的两个更新通道都使用 Sparkle：先验签 ZIP 和 appcast，再替换并重启应用。每次检查先读取 Gitee；当 Gitee appcast 无法加载或更新包下载失败时，自动重试一次 GitHub。`package-release.sh` 要求通过 `SPARKLE_GENERATE_APPCAST` 指向 Sparkle 2.9.4 的 `generate_appcast`，并会在 ZIP、DMG 同目录写出 `appcast-gitee.xml` 和 `appcast-github.xml`。两份 appcast 都必须独立签名，且只能指向各自站点的 Universal ZIP。上传时分别以 `appcast.xml` 放到对应站点的 Release：Gitee 的 Release/Preview 永久 feed 分别为 `update-release` 和 `preview`；GitHub 的 Release 使用 `latest`，Preview 使用永久 prerelease `preview`。非交互发布时设置 `SPARKLE_ED_KEY_FILE` 指向私下保管的 EdDSA 私钥文件；不设置则读取登录钥匙串的 `zisla-update-ed25519` 账户。私钥绝不能进入仓库。Developer ID 发布包仍建议公证；免费 ad-hoc Preview 不能公证，首次打开可能需要在系统设置中选择“仍要打开”。

## 前提

- Developer ID Application 证书
- Apple 公证凭据
- 官方 `yt-dlp` Helper 已通过 `Scripts/fetch-yt-dlp.sh` 获取并校验

## 1. 构建签名应用

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

输出：

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### 免费预览分发

不使用 Apple Developer Program 时，可以用 ad-hoc 签名构建预览包：

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

该包不经过公证，且不包含 WeatherKit 权限。将已签名 appcast 发布到永久 Preview feed 后，应用会通过 Sparkle 检查、下载、验签、安装并重启 Preview 更新。首次打开仍需在 **系统设置 > 隐私与安全性** 中选择 **仍要打开**。
Developer ID 和公证仍是面向普通用户无拦截分发的推荐方式。

## 2. 公证

```bash
xcrun notarytool submit \
  dist/zisla-v1.0.0-macOS-universal.zip \
  --keychain-profile AC_NOTARY \
  --wait

xcrun stapler staple 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'

# 重新打包已 stapled 的应用，确保 ZIP 和 DMG 都携带最终产物。
export SKIP_BUILD=true
Scripts/package-release.sh
```

## 3. 发布与验证

将 ZIP、DMG、校验文件和 `appcast-github.xml` 以 `appcast.xml` 上传到 GitHub 的同一版本 tag Release；将匹配资产和 `appcast-gitee.xml` 以 `appcast.xml` 上传到 Gitee 的同一 tag。正式版不能标记为 prerelease。Gitee 的正式 appcast 还必须复制到永久 `update-release`；Preview 的 appcast 必须复制到两端永久 `preview`。客户端按选择的通道先检查 Gitee，当 Gitee appcast 无法加载或更新包下载失败时回退一次 GitHub。

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

使用旧版本检查新 Release，确认自动检查和手动检查都先读取所选 Gitee feed，当其无法加载或更新包下载失败时回退一次对应 GitHub feed，且 Sparkle 能验签、安装并重启 Universal ZIP。还要验证 Release→Preview、Preview→Release 和同通道更新。

## 4. 同步 Homebrew cask

正式版的最后一站是 Homebrew。Preview 版本到上一步为止：tap 只提供正式版，`brew upgrade` 因此不会把用户带到预发布版本。

发布资产上传完成后，在仓库根目录执行：

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

脚本会改写 `Casks/zisla.rb` 中的 `version` 与 `sha256`：`$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-universal.zip.sha256` 存在时读本地摘要，否则从已发布的 GitHub 资产拉取。未通过 `homebrew-cask.rb verify` 的 cask 不会被写回，通过后再镜像到 `wzz6423/homebrew-tap`。不带 `PUBLISH_TAP` 即为试运行，只更新仓库内的 cask。

cask 声明 `auto_updates true`，因为更新链路归 Sparkle 所有：直接执行 `brew upgrade` 不会动已安装的应用，只有 `brew upgrade --cask zisla` 或 `--greedy` 才让 Homebrew 替换。改写后的 cask 必须与官网 `latestRelease` 的版本一起提交——两者版本不一致时 CI 会失败。随后验证 tap：

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew livecheck --cask wzz6423/tap/zisla
```
