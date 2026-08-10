---
name: zisla-release
description: 此技能用于发布 zisla 的 macOS Preview 或 Release 版本到 GitHub 和 Gitee，管理免费 ad-hoc 或 Developer ID 分发，并验证双通道检查和下载更新。
---

# zisla macOS 发版

发布 zisla 的 macOS 安装包时执行本技能。覆盖 Preview 与 Release 两条通道，以及 GitHub、Gitee 两端的 Release。

## 发布原则

- 应用内更新只检查 Release 并下载 DMG；绝不自动替换、重启或挂载应用。
- GitHub 与 Gitee 都是检查和下载源。每个同版本 Release 必须在两端都上传同名 universal DMG。
- Release 包自动检查正式 Release；Preview 包自动检查 prerelease。设置中的跨通道选择只影响手动检查。
- 使用 `CFBundleShortVersionString` 作为用户可见版本，tag 应使用可解析的语义版本，例如 `v1.2.3` 或 `release/v1.2.3`。
- 每次发布前验证 DMG 中只有 `zisla.app` 和 `Applications` 软链接。用户需要退出 zisla 后再拖入 `Applications` 安装。

详细凭据和通道约束见 [references/credentials.md](references/credentials.md) 与 [references/update-channels.md](references/update-channels.md)。

## 发行前检查

1. 确认工作树中只有预期的源代码与文档变更，并确定实际发布 tag。
2. 确认 `UPDATE_CHANNEL`：Preview 使用 `preview`，正式版使用 `release`。
3. 确认 GitHub CLI 已登录，Gitee Release API 令牌已安全保存。

```zsh
gh auth status
security find-generic-password -a 'wzz6423' -s 'gitee.com.zisla.release-token' >/dev/null
```

## 构建

从 `mac/` 目录执行脚本。`CODE_SIGN_IDENTITY=-` 是免费 ad-hoc Preview 分发；它不需要 Apple Developer Program，但未公证，首次启动可能需要用户在系统设置中选择“仍要打开”。

```zsh
export VERSION='0.1.1-preview.1'
export BUILD_NUMBER='2'
export UPDATE_CHANNEL='preview'
export CODE_SIGN_IDENTITY=-
export ARCHIVE_DIRECTORY="$PWD/.release-v${VERSION}"
Scripts/package-release.sh
```

正式 Release 将 `UPDATE_CHANNEL` 改为 `release`。拥有 Developer ID 证书和公证凭据后，将 `CODE_SIGN_IDENTITY` 替换为 `Developer ID Application: ...`，并在上传前完成 notarization 与 stapling。

## GitHub 与 Gitee 发布

为实际版本建立 Release。Preview 必须加 `--prerelease`，Release 不加该参数。上传 DMG；ZIP 和 ZIP SHA-256 可作为供用户校验与公证的附加资产一并上传。

```zsh
gh release create "v${VERSION}" \
  "$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.dmg" \
  "$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.zip" \
  "$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.zip.sha256" \
  --repo wzz6423/zisla --title "zisla v${VERSION}" --prerelease
```

对已存在 Release 使用 `gh release edit` 和 `gh release upload --clobber`，不要创建同 tag 的重复 Release。GitHub Release 不会自动同步到 Gitee；使用 Gitee API 创建或更新同 tag Release，并上传同一批 DMG、ZIP 和 SHA-256。

Gitee API 的 PATCH 必须携带 `tag_name`，否则返回 `400: tag_name is missing`。上传新附件后再删除同名旧附件，避免 Release 出现空档。

## 验证与清理

在上传前执行：

```zsh
zsh -n Scripts/build-app.sh Scripts/package-release.sh
codesign --verify --deep --strict --all-architectures --verbose=4 "$ARCHIVE_DIRECTORY/zisla.app"
lipo -archs "$ARCHIVE_DIRECTORY/zisla.app/Contents/MacOS/zisla"
shasum -a 256 "$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.dmg"
hdiutil attach -nobrowse "$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.dmg"
test -L /Volumes/zisla/Applications
hdiutil detach /Volumes/zisla
```

上传后在旧版本中检查对应通道，确认可以下载 DMG 到默认目录和临时指定目录，并确认同名包不会被覆盖。最后清理 `.release-*`、临时挂载和本次测试下载物。

## 交付记录

在 Release 正文中写清楚版本类型、签名方式、公证状态、已测试的 macOS 范围、WeatherKit 限制、GitHub Issues/PR 入口，以及 Gitee 不受理 Issues/PR 的事实。说明更新包需要用户先退出 zisla 后手动安装。不要包含证书序列号、访问令牌或 Keychain 密码。
