---
name: zisla-release
description: 此技能用于发布 zisla 的 macOS Preview 或 Release 版本到 GitHub 和 Gitee，分别打包 x86_64、arm64 和 Universal，并验证双通道检查和下载更新。
---

# zisla macOS 发版

发布 zisla 的 macOS 安装包时执行本技能。覆盖 Preview 与 Release 两条通道，以及 GitHub、Gitee 两端的 Release。

## 发布原则

- 应用内更新只检查 Release 并下载 DMG；绝不自动替换、重启或挂载应用。
- GitHub 与 Gitee 都是检查和下载源。每个同版本 Release 必须在两端都上传 `x86_64`（X86）、`arm64` 和 `universal` 三套 DMG、ZIP 和 SHA-256。
- **三种包都必须保留**：`x86_64` 和 `arm64` 包分别只包含单一架构，`universal` 包必须同时包含两个架构；三类资产都要分别压缩、分别上传，文件名必须带对应后缀。
- Release 包自动检查正式 Release；Preview 包自动检查 prerelease。设置中的跨通道选择只影响手动检查。
- 使用 `CFBundleShortVersionString` 作为用户可见版本，tag 应使用可解析的语义版本，例如 `v1.2.3` 或 `release/v1.2.3`。
- 每次发布前验证 DMG 中只有 `zisla.app` 和 `Applications` 软链接。用户需要退出 zisla 后再拖入 `Applications` 安装。
- 发版构建严禁使用调试变体：必须显式使用 `DEBUG_BUILD=false`，产物必须是 `zisla.app`、Bundle ID `dev.wzz.zisla`；`zisla-debug.app` 或 `dev.wzz.zisla.debug` 只能用于本地调试，不能上传。
- 发版资源必须来自正式资源目录：`AppIcon.icns` 必须作为主图标，`AppIconNight.icns` 只能作为深色模式备用图标；调试构建使用的黑底白字图标复制方式，以及 `zisla-debug.app` 中的任何资源，都不能用于正式包或通过改名后上传。
- 发版不得把 `make run` 生成的 `dist/zisla-debug.app` 直接压缩、改名或复制资源；必须由 `Scripts/package-release.sh` 重新构建正式包并通过身份与图标校验。

详细凭据和通道约束见 [references/credentials.md](references/credentials.md) 与 [references/update-channels.md](references/update-channels.md)。

## 发行前检查

1. 确认工作树中只有预期的源代码与文档变更，并确定实际发布 tag。
2. 确认 `UPDATE_CHANNEL`：Preview 使用 `preview`，正式版使用 `release`。
3. 确认 GitHub CLI 已登录，Gitee Release API 令牌已安全保存。
4. 清除调试构建状态：即使当前 shell 继承了 `DEBUG_BUILD=true`，也必须在每次发版构建前显式设置 `DEBUG_BUILD=false`，并在产物中核对正式 Bundle ID。
5. 核对资源身份：正式包的主图标必须与 `Resources/AppIcon.icns` 完全一致，不能是 `Resources/AppIconNight.icns` 的副本。

```zsh
gh auth status
security find-generic-password -a 'wzz6423' -s 'gitee.com.zisla.release-token' >/dev/null
```

## 构建

从 `mac/` 目录执行脚本。`CODE_SIGN_IDENTITY=-` 是免费 ad-hoc Preview 分发；它不需要 Apple Developer Program，但未公证，首次启动可能需要用户在系统设置中选择“仍要打开”。

**必须构建三套包**：`arm64`、`x86_64`（X86）单架构包，以及同时包含两个架构的 `universal` 包：

```zsh
export VERSION='0.1.1-preview.1'
export BUILD_NUMBER='2'
export UPDATE_CHANNEL='preview'
export CODE_SIGN_IDENTITY=-
export DEBUG_BUILD=false
export ARCHIVE_DIRECTORY="$PWD/.release-v${VERSION}"

# arm64：只包含 arm64，最终资产必须带 -macOS-arm64 后缀
DEBUG_BUILD=false ARCHIVE_DIRECTORY="$ARCHIVE_DIRECTORY/arm64" \
  BUILD_ARCHITECTURES=arm64 Scripts/package-release.sh

# x86_64（X86）：只包含 x86_64，最终资产必须带 -macOS-x86_64 后缀
DEBUG_BUILD=false ARCHIVE_DIRECTORY="$ARCHIVE_DIRECTORY/x86_64" \
  BUILD_ARCHITECTURES=x86_64 Scripts/package-release.sh

# universal：同时包含 arm64 和 x86_64，最终资产必须带 -macOS-universal 后缀
DEBUG_BUILD=false ARCHIVE_DIRECTORY="$ARCHIVE_DIRECTORY/universal" \
  BUILD_ARCHITECTURES="arm64 x86_64" Scripts/package-release.sh
```

单架构构建不得生成 Universal 内容；Universal 构建不得只包含一个架构。若脚本的输出文件名与上述后缀不一致，先调整脚本，再继续发版；禁止仅修改文件名后上传未经架构验证的包。

正式 Release 将 `UPDATE_CHANNEL` 改为 `release`。拥有 Developer ID 证书和公证凭据后，将 `CODE_SIGN_IDENTITY` 替换为 `Developer ID Application: ...`，并在上传前完成 notarization 与 stapling。

## GitHub 与 Gitee 发布

为实际版本建立 Release。Preview 必须加 `--prerelease`，Release 不加该参数。上传 `arm64`、`x86_64` 和 `universal` 三套 DMG；对应 ZIP 和 ZIP SHA-256 也一并上传。两端的架构后缀、文件内容和校验值必须一致。

```zsh
gh release create "v${VERSION}" \
  "$ARCHIVE_DIRECTORY/arm64/zisla-v${VERSION}-macOS-arm64.dmg" \
  "$ARCHIVE_DIRECTORY/arm64/zisla-v${VERSION}-macOS-arm64.zip" \
  "$ARCHIVE_DIRECTORY/arm64/zisla-v${VERSION}-macOS-arm64.zip.sha256" \
  "$ARCHIVE_DIRECTORY/x86_64/zisla-v${VERSION}-macOS-x86_64.dmg" \
  "$ARCHIVE_DIRECTORY/x86_64/zisla-v${VERSION}-macOS-x86_64.zip" \
  "$ARCHIVE_DIRECTORY/x86_64/zisla-v${VERSION}-macOS-x86_64.zip.sha256" \
  "$ARCHIVE_DIRECTORY/universal/zisla-v${VERSION}-macOS-universal.dmg" \
  "$ARCHIVE_DIRECTORY/universal/zisla-v${VERSION}-macOS-universal.zip" \
  "$ARCHIVE_DIRECTORY/universal/zisla-v${VERSION}-macOS-universal.zip.sha256" \
  --repo wzz6423/zisla --title "zisla v${VERSION}" --prerelease
```

对已存在 Release 使用 `gh release edit` 和 `gh release upload --clobber`，不要创建同 tag 的重复 Release。GitHub Release 不会自动同步到 Gitee；使用 Gitee API 创建或更新同 tag Release，并上传三套架构资产及其 SHA-256。

Gitee API 的 PATCH 必须携带 `tag_name`，否则返回 `400: tag_name is missing`。上传新附件后再删除同名旧附件，避免 Release 出现空档。

## 验证与清理

在上传前对三套资产分别执行：

```zsh
zsh -n Scripts/build-app.sh Scripts/package-release.sh
test "$(plutil -extract CFBundleIdentifier raw -o - "$ARCHIVE_DIRECTORY/arm64/zisla.app/Contents/Info.plist")" = "dev.wzz.zisla"
test "$(plutil -extract CFBundleDisplayName raw -o - "$ARCHIVE_DIRECTORY/arm64/zisla.app/Contents/Info.plist")" = "zisla"
test "$(plutil -extract CFBundleIconFile raw -o - "$ARCHIVE_DIRECTORY/arm64/zisla.app/Contents/Info.plist")" = "AppIcon"
test ! -e "$ARCHIVE_DIRECTORY/arm64/zisla-debug.app"
for ARCHITECTURE in arm64 x86_64 universal; do
  cmp -s "$ARCHIVE_DIRECTORY/$ARCHITECTURE/zisla.app/Contents/Resources/AppIcon.icns" Resources/AppIcon.icns
  cmp -s "$ARCHIVE_DIRECTORY/$ARCHITECTURE/zisla.app/Contents/Resources/AppIconNight.icns" Resources/AppIconNight.icns
  codesign --verify --deep --strict --verbose=4 "$ARCHIVE_DIRECTORY/$ARCHITECTURE/zisla.app"
  ARCHES="$(lipo -archs "$ARCHIVE_DIRECTORY/$ARCHITECTURE/zisla.app/Contents/MacOS/zisla")"
  if [[ "$ARCHITECTURE" == universal ]]; then
    test "$ARCHES" = "arm64 x86_64"
  else
    test "$ARCHES" = "$ARCHITECTURE"
  fi
  shasum -a 256 "$ARCHIVE_DIRECTORY/$ARCHITECTURE/zisla-v${VERSION}-macOS-${ARCHITECTURE}.dmg"
  hdiutil attach -nobrowse "$ARCHIVE_DIRECTORY/$ARCHITECTURE/zisla-v${VERSION}-macOS-${ARCHITECTURE}.dmg"
  test -L /Volumes/zisla/Applications
  hdiutil detach /Volumes/zisla
done
```

上传后在旧版本中检查对应通道，确认三类 DMG 都可以下载到默认目录和临时指定目录，并确认同名包不会被覆盖。最后清理 `.release-*`、临时挂载和本次测试下载物。

## 交付记录

在 Release 正文中写清楚版本类型、签名方式、公证状态、已测试的 macOS 范围、WeatherKit 限制、GitHub Issues/PR 入口，以及 Gitee 不受理 Issues/PR 的事实。说明更新包需要用户先退出 zisla 后手动安装。不要包含证书序列号、访问令牌或 Keychain 密码。
