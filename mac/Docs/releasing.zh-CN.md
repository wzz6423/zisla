# 签名与发布设计

[English](releasing.md) | **简体中文**

项目的完整发布流程、双更新通道和 GitHub/Gitee 的资产同步由仓库根目录的 [`skills/zisla-release`](../../skills/zisla-release/SKILL.md) 统一维护。本页只说明签名、公证和更新包的设计约束；发布时以该技能为准。

应用内只检查 Release 和下载 DMG，绝不自动替换或重启应用。Developer ID 发布包仍建议公证；免费 ad-hoc Preview 不能公证，首次打开可能需要在系统设置中选择“仍要打开”。

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
```

### 免费预览分发

不使用 Apple Developer Program 时，可以用 ad-hoc 签名构建预览包：

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

该包不经过公证，且不包含 WeatherKit 权限。应用会定期检查 GitHub/Gitee Release；发现新版本后，用户确认即可下载对应 DMG，再把 DMG 中的应用拖入
`Applications`。首次打开仍需在 **System Settings > Privacy & Security** 中选择 **Open Anyway**。
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

将 DMG 上传到 GitHub 和 Gitee 的同一 tag Release。正式版不能标记为 prerelease；Preview 必须标记为 prerelease。客户端根据通道调用 Release API，选择带有 `macOS` 名称的 DMG。

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

hdiutil attach -nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
hdiutil detach /Volumes/zisla
```

使用旧版本检查新 Release，确认可下载 DMG、DMG 落在所选目录且未覆盖同名文件。安装验收时先退出 zisla，再挂载 DMG 并拖入 `Applications`。
