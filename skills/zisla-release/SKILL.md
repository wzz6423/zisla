---
name: zisla-release
description: 此技能用于发布 zisla 的 macOS Preview 或 Release 版本到 GitHub 和 Gitee，生成 Sparkle 更新元数据，管理免费 ad-hoc 或 Developer ID 分发，并验证双通道自动更新。
---

# zisla macOS 发版

发布 zisla 的 macOS 安装包时执行本技能。覆盖 Preview 与 Release 两条通道，以及 GitHub、Gitee 两端的 Release。

## 发布原则

- 将 GitHub 作为 Sparkle 自动更新的唯一源；Gitee 仅镜像源码和 Release 附件。
- 使用同一套 Sparkle EdDSA 密钥签署 Preview 与 Release。不要为两个通道生成不同密钥，否则已安装应用无法验证跨通道更新。
- Release 包自动检查并安装 Release feed；Preview 包自动检查并安装 Preview feed。设置页的跨通道选择只在用户主动检查时生效，不能改变后续自动更新通道。
- 为每次可安装构建分配全局严格递增的 `BUILD_NUMBER`，不要按通道分别从 1 计数。
- 将 `CFBundleShortVersionString` 用作用户可见版本，将 `CFBundleVersion`（即 `BUILD_NUMBER`）用作 Sparkle 与 macOS 的安装顺序。
- 不要声称 Sparkle 支持真正的降级。Sparkle 会拒绝较低的 `CFBundleVersion`；历史版本回退只能手动下载 DMG 安装。
- 保留 Preview 为 prerelease；只有正式 Release 才应成为 GitHub 的 Latest。

详细的凭据与通道约束见 [references/credentials.md](references/credentials.md)、[references/update-channels.md](references/update-channels.md) 和 [references/v0.1.0-preview-lessons.md](references/v0.1.0-preview-lessons.md)。

## 发行前检查

1. 确认工作树中只有预期的源代码与文档变更，并确定实际发布 tag。
2. 为本次构建分配大于所有历史 Preview/Release 的 `BUILD_NUMBER`。
3. 确认 `UPDATE_CHANNEL`：Preview 使用 `preview`，正式版使用 `release`。
4. 确认 Sparkle 公钥来自登录钥匙串，私钥从不写入仓库、Release 正文、shell 历史或日志。
5. 确认 GitHub CLI 已登录，Gitee Release API 令牌和 Sparkle 私钥都在 macOS Keychain 中。

```zsh
gh auth status
security find-generic-password -a 'wzz6423' -s 'gitee.com.zisla.release-token' >/dev/null
security find-generic-password -s 'https://sparkle-project.org' -a 'dev.wzz.zisla' >/dev/null
```

## 构建

从 `mac/` 目录执行脚本。`CODE_SIGN_IDENTITY=-` 是免费 ad-hoc Preview 分发；它不需要 Apple Developer Program，但未公证，首次启动需要用户在系统设置中选择“仍要打开”。

```zsh
export VERSION='0.1.1-preview.1'
export BUILD_NUMBER='2'
export UPDATE_CHANNEL='preview'
export CODE_SIGN_IDENTITY=-
export SPARKLE_PUBLIC_KEY='<从钥匙串对应的公钥读取，不要提交私钥>'
export SPARKLE_GENERATE_APPCAST='/absolute/path/to/generate_appcast'
export SPARKLE_APPCAST_ACCOUNT='dev.wzz.zisla'
export SPARKLE_APPCAST_DOWNLOAD_URL_PREFIX="https://github.com/wzz6423/zisla/releases/download/v${VERSION}/"
export ARCHIVE_DIRECTORY="$PWD/.release-v${VERSION}"
Scripts/package-release.sh
```

正式 Release 仅把 `UPDATE_CHANNEL` 改为 `release`。拥有 Developer ID 证书和公证凭据后，再将 `CODE_SIGN_IDENTITY` 替换为 `Developer ID Application: ...`，并在上传前完成 notarization 与 stapling。

## GitHub 发布

为实际版本建立 Release。Preview 必须加 `--prerelease`，Release 不加该参数。上传四个文件：`appcast.xml`、DMG、ZIP、ZIP SHA-256。

```zsh
gh release create "v${VERSION}" \
  "$ARCHIVE_DIRECTORY/appcast.xml" \
  "$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.dmg" \
  "$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.zip" \
  "$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.zip.sha256" \
  --repo wzz6423/zisla --title "zisla v${VERSION}" --prerelease
```

对已存在 Release 使用 `gh release edit` 和 `gh release upload --clobber`，不要创建同 tag 的重复 Release。

### Preview feed

Preview 不会被 GitHub 的 `/releases/latest/` 选中。维护一个固定 tag 为 `preview` 的 prerelease，只保存当前 Preview 的 `appcast.xml`，供客户端读取：

```text
https://github.com/wzz6423/zisla/releases/download/preview/appcast.xml
```

先创建该 relay Release，再在每次 Preview 后覆盖 appcast：

```zsh
gh release create preview --repo wzz6423/zisla --prerelease --title 'zisla Preview update feed' --notes ''
gh release upload preview "$ARCHIVE_DIRECTORY/appcast.xml" --repo wzz6423/zisla --clobber
```

正式通道继续读取：

```text
https://github.com/wzz6423/zisla/releases/latest/download/appcast.xml
```

`appcast.xml` 的 enclosure 长度和 EdDSA 签名必须来自这一次最终上传的 ZIP。重新打包、重新签名或覆盖 ZIP 后，必须重新执行 `generate_appcast`，再把 ZIP、SHA-256 和 appcast 一起覆盖上传；不能只替换 ZIP。

## Gitee 发布

不要假定 GitHub Release 会自动镜像到 Gitee。同步代码、tag 和 GitHub Release 后，单独更新 Gitee 的同 tag Release，并上传同样四个文件。

- 上传实际 Preview/Release 的四个资产；源码 ZIP/TAR 由平台自动生成。
- 通过 `GET /repos/wzz6423/zisla/releases/<id>/attach_files` 先获得旧附件 ID。
- 更新 Release 时，Gitee API 的 PATCH 必须携带 `tag_name`，否则返回 `400: tag_name is missing`。
- 上传新文件后再删除同名旧附件，避免 Release 出现空档。
- 自动更新仍从 GitHub 获取 appcast 和 ZIP；Gitee 是下载镜像与国内访问入口。

## 验证与清理

在上传前执行：

```zsh
zsh -n Scripts/build-app.sh Scripts/package-release.sh
codesign --verify --deep --strict --all-architectures --verbose=4 "$ARCHIVE_DIRECTORY/zisla.app"
lipo -archs "$ARCHIVE_DIRECTORY/zisla.app/Contents/MacOS/zisla"
xmllint --noout "$ARCHIVE_DIRECTORY/appcast.xml"
shasum -a 256 -c "$ARCHIVE_DIRECTORY/zisla-v${VERSION}-macOS-universal.zip.sha256"
```

确认主程序、Sparkle.framework、Updater、Downloader 和 Installer 都包含 `arm64 x86_64`。挂载 DMG 后确认根目录只有 `zisla.app` 与指向 `/Applications` 的 `Applications` 软链接；Finder 图标必须是左侧 `zisla.app`、右侧 `Applications`，使用户从左向右拖动安装。不要在自动化中启动应用替代用户验收。

上传后读取 GitHub 与 Gitee Release 附件清单，分别下载四个资产的字节流计算 SHA-256，并与本地产物对比。最后清理 `.release-*`、临时 Sparkle 工具和本次测试下载物。

## 交付记录

在 Release 正文中写清楚版本类型、签名方式、公证状态、已测试的 macOS 范围、WeatherKit 限制、自动更新频道、GitHub Issues/PR 入口，以及 Gitee 不受理 Issues/PR 的事实。不要包含证书序列号、访问令牌、Sparkle 私钥或 Keychain 密码。
