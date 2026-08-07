# 签名与发布设计

项目的完整发布流程、双更新通道、GitHub/Gitee 的资产同步，以及 Sparkle 与 Gitee 凭据来源由仓库根目录的 [`skills/zisla-release`](../../skills/zisla-release/SKILL.md) 统一维护。本页只说明签名、公证和更新包的设计约束；发布时以该技能为准。

Developer ID 发布包需要公证；免费 ad-hoc Preview 可以使用 Sparkle EdDSA 自动更新，但不能公证，首次打开可能需要在系统设置中选择“仍要打开”。

## 前提

- Developer ID Application 证书
- Apple 公证凭据
- Sparkle EdDSA 私钥已保存在发布机器的 Keychain 或 CI Secret
- 官方 `yt-dlp` Helper 已通过 `Scripts/fetch-yt-dlp.sh` 获取并校验

## 1. 准备 Sparkle 公钥

使用 Sparkle 发行包中的 `generate_keys` 生成密钥。私钥不得写入仓库。

将输出的公钥提供给构建：

```bash
export SPARKLE_PUBLIC_KEY='<base64-public-key>'
```

构建脚本仅在该值解码后长度为 32 字节时启用自动更新控制器。

## 2. 构建签名应用

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
```

### 免费预览分发

不使用 Apple Developer Program 时，可以用 ad-hoc 签名构建预览包：

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

该包不经过公证，且不包含 WeatherKit 权限。用户需要把 DMG 中的应用拖入
`Applications`，再在 **System Settings > Privacy & Security** 中选择 **Open Anyway**。
Developer ID 和公证仍是面向普通用户无拦截分发的推荐方式。

## 3. 公证

```bash
xcrun notarytool submit \
  dist/zisla-v1.0.0-macOS-universal.zip \
  --keychain-profile AC_NOTARY \
  --wait

xcrun stapler staple 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'

# 重新打包已 stapled 的应用，确保 ZIP、DMG 和 appcast 都携带最终产物。
export SKIP_BUILD=true
Scripts/package-release.sh
```

## 4. 生成 appcast

设置 Sparkle `generate_appcast` 的绝对路径：

```bash
export SPARKLE_GENERATE_APPCAST=/path/to/generate_appcast
export SPARKLE_APPCAST_ACCOUNT=dev.wzz.zisla
export SPARKLE_APPCAST_DOWNLOAD_URL_PREFIX='https://github.com/wzz6423/zisla/releases/download/v1.0.0/'
Scripts/package-release.sh
```

将生成的 `appcast.xml` 与 ZIP、SHA256 一起上传到 GitHub Release。App 内固定读取：

```text
https://github.com/wzz6423/zisla/releases/latest/download/appcast.xml
```

## 5. 验证

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.zip

hdiutil attach -nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
hdiutil detach /Volumes/zisla
```

使用旧签名版本检查新 Release，确认 Sparkle 验证 EdDSA 签名、替换应用、重启并显示新版本。
