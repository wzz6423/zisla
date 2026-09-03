---
name: zisla-release
description: 此技能用于发布 zisla 的 macOS Preview 或 Release 版本到 GitHub 和 Gitee，分别打包 x86_64、arm64 和 Universal，并验证 Sparkle 签名自动更新、双通道 appcast 与发布资产。
---

# zisla macOS 发版

发布 zisla 的 macOS 安装包时执行本技能。覆盖 Preview 与 Release 两条通道，以及 GitHub、Gitee 两端的 Release。两个通道均使用 Sparkle 签名 ZIP 自动检查、下载、验签、替换和重启；设置中的通道切换同时影响自动检查和手动检查。

## 发布原则

- Release 主 feed 固定为 `https://gitee.com/wzz6423/zisla/releases/download/update-release/appcast.xml`，失败时仅回退一次 `https://github.com/wzz6423/zisla/releases/latest/download/appcast.xml`；Preview 主 feed 固定为 `https://gitee.com/wzz6423/zisla/releases/download/preview/appcast.xml`，失败时仅回退一次 `https://github.com/wzz6423/zisla/releases/download/preview/appcast.xml`。Gitee appcast 检查或其更新包下载失败时回退；每次新的自动或手动检查都会重新从 Gitee 开始。appcast 与 ZIP 必须同时通过 EdDSA 签名；客户端在解压前验证，再替换并重启应用。
- Gitee 的正式永久 feed tag 是 `update-release`，Preview 永久 feed tag 是 `preview`；GitHub 的正式 feed 使用 `latest`，Preview 使用永久 prerelease tag `preview`。两个 `preview` feed 都只保存当前 Preview 的 `appcast.xml`，且各自指向实际版本 tag（例如 `v0.2.0-preview.1`）中本站的 Universal ZIP。GitHub 的 `preview` 必须保持 prerelease，避免污染正式 `latest`。
- 每个版本仍构建 `x86_64`、`arm64` 和 `universal` 三套包。自动更新只引用 Universal ZIP，它同时覆盖 Intel 和 Apple Silicon；其余架构 ZIP、DMG 和校验文件用于首次安装与 Release 页面下载，不参与应用内更新流程。
- 每次运行 `package-release.sh` 都会在同目录生成 `appcast-gitee.xml` 和 `appcast-github.xml`。前者只能引用 Gitee 上的 Universal ZIP，后者只能引用 GitHub 上的 Universal ZIP；上传到各自 Release 时均命名为 `appcast.xml`。不得手改已签名 appcast；需修改时重新运行生成工具。
- 将“实际版本 Universal ZIP 与两端签名 `appcast.xml` 已上传，并且永久 feed 已指向该版本”视为自动更新发布的原子门禁；任一环节缺失即视为发版失败，不得宣称线上检查、发现更新或自动安装可用。不得以 Release API 的版本号、debug 专用逻辑或“已是最新”提示替代 Sparkle appcast 检查。若未获明确授权修复指定历史版本，不得回填或改动已发布版本及其永久 feed；默认在下一次更高版本发版时完整满足该门禁。
- GitHub 和 Gitee 都承载 Sparkle feed 与更新 ZIP。每个同版本 Release 必须在两端都上传 `x86_64`（X86）、`arm64` 和 `universal` 三套 DMG、ZIP 和 SHA-256，以及对应的已签名 appcast。
- **三种包都必须保留**：`x86_64` 和 `arm64` 包分别只包含单一架构，`universal` 包必须同时包含两个架构；三类资产都要分别压缩、分别上传，文件名必须带对应后缀。
- 无论安装包构建时的 `UPDATE_CHANNEL` 是什么，运行时选择 Release 或 Preview 都必须切换到对应的 Sparkle feed；自动检查和“检查更新”均遵循当前选择。切换后 Sparkle 重置下一次检查周期，手动检查立即使用新通道。
- 使用 `CFBundleShortVersionString` 作为用户可见版本。默认签名 appcast 的 ZIP URL 假定 tag 为 `v${VERSION}`；使用 `release/v1.2.3` 等路径前缀 tag 时，必须同时显式设置正确的 `SPARKLE_GITEE_DOWNLOAD_URL_PREFIX` 和 `SPARKLE_GITHUB_DOWNLOAD_URL_PREFIX`。
- 每次发布前验证 DMG 中只有 `zisla.app` 和 `Applications` 软链接。首次安装 Sparkle 版仍需要用户手动安装；之后的已安装 Sparkle 版本才可自动更新。
- 发版构建严禁使用调试变体：必须显式使用 `DEBUG_BUILD=false`，产物必须是 `zisla.app`、Bundle ID `dev.wzz.zisla`；`zisla-debug.app` 或 `dev.wzz.zisla.debug` 只能用于本地调试，不能上传。
- 发版资源必须来自正式资源目录：`AppIcon.icns` 必须作为主图标，`AppIconNight.icns` 只能作为深色模式备用图标；调试构建使用的黑底白字图标复制方式，以及 `zisla-debug.app` 中的任何资源，都不能用于正式包或通过改名后上传。
- 发版不得把 `make run` 生成的 `dist/zisla-debug.app` 直接压缩、改名或复制资源；必须由 `Scripts/package-release.sh` 重新构建正式包并通过身份与图标校验。

详细凭据和通道约束见 [references/credentials.md](references/credentials.md) 与 [references/update-channels.md](references/update-channels.md)。

## 发行前检查

1. 确认工作树中只有预期的源代码与文档变更，并确定实际发布 tag。
2. 确认 `UPDATE_CHANNEL` 与本次版本类型匹配，并确认两端实际版本 tag 使用 `v${VERSION}`；Release 同步 Gitee `update-release` 和 GitHub `latest`，Preview 同步两端永久 `preview` feed。
3. 确认 GitHub CLI 已登录，Gitee Release API 令牌已安全保存。
4. 清除调试构建状态：即使当前 shell 继承了 `DEBUG_BUILD=true`，也必须在每次发版构建前显式设置 `DEBUG_BUILD=false`，并在产物中核对正式 Bundle ID。
5. 核对资源身份：正式包的主图标必须与 `Resources/AppIcon.icns` 完全一致，不能是 `Resources/AppIconNight.icns` 的副本。
6. 确认 Sparkle 2.9.4 的 `generate_appcast` 可执行，私钥位于钥匙串或已移动到受限的离线/加密位置；不得打印、提交或上传私钥。

```zsh
gh auth status
security find-generic-password -a 'wzz6423' -s 'gitee.com.zisla.release-token' >/dev/null
```

## 构建

在仓库根目录执行 `make build-package` 完成打包。它按 `arm64`、`x86_64`、`arm64 x86_64` 顺序调用 `mac/Scripts/package-release.sh`，对每次调用强制 `DEBUG_BUILD=false`，把三套 DMG、ZIP 及其 SHA-256 平铺到仓库根 `outputs/`，并只保留 Universal 的 `appcast-gitee.xml` 与 `appcast-github.xml`。`outputs/` 每次重建，其内容即本次需要上传的全部资产；GitHub Release 自动生成的源码压缩包不属于它，不得手工构造或补传。三套 `zisla.app` 保留在 `outputs/.staging/<架构>/`，只用于下面的发布前验证，不上传。

`CODE_SIGN_IDENTITY=-` 是免费 ad-hoc 分发；它不需要 Apple Developer Program，但未公证，首次启动可能需要用户在系统设置中选择“仍要打开”。后续更新仍由 Sparkle 的 EdDSA 签名保护。

**必须构建三套包**：`arm64`、`x86_64`（X86）单架构包，以及同时包含两个架构的 `universal` 包；`make build-package` 一次生成三套，缺任一套即视为打包失败：

```zsh
export VERSION='0.1.1'
export BUILD_NUMBER='2'
export UPDATE_CHANNEL='release'
export CODE_SIGN_IDENTITY=-
export DEBUG_BUILD=false
export SPARKLE_GENERATE_APPCAST='/安全位置/Sparkle/bin/generate_appcast'
export SPARKLE_ED_KEY_FILE='/安全位置/zisla-sparkle-ed25519-private-key.txt'
export RELEASE_OUTPUT_DIRECTORY="$(git rev-parse --show-toplevel)/outputs"
test -x "$SPARKLE_GENERATE_APPCAST"
test -f "$SPARKLE_ED_KEY_FILE"

make build-package
```

只有需要单独重建某一套包时，才从 `mac/` 目录直接调用脚本并显式指定架构与归档目录，例如只重建 arm64：

```zsh
DEBUG_BUILD=false ARCHIVE_DIRECTORY="$PWD/.release-v${VERSION}/arm64" \
  BUILD_ARCHITECTURES=arm64 Scripts/package-release.sh
```

单架构构建不得生成 Universal 内容；Universal 构建不得只包含一个架构。若脚本的输出文件名与上述后缀不一致，先调整脚本，再继续发版；禁止仅修改文件名后上传未经架构验证的包。

`SPARKLE_ED_KEY_FILE` 优先于钥匙串；无交互发布必须显式设置它。仅在本机交互发布时，才可不设置该变量并由 `zisla-update-ed25519` 登录钥匙串账户读取。拥有 Developer ID 证书和公证凭据后，将 `CODE_SIGN_IDENTITY` 替换为 `Developer ID Application: ...`，并在上传前完成 notarization 与 stapling。

## GitHub 与 Gitee 发布

为实际版本建立 GitHub Release。上传 `arm64`、`x86_64` 和 `universal` 三套 DMG、ZIP、各自 SHA-256，以及引用 GitHub Universal ZIP 的 `appcast-github.xml`，并将远端附件命名为 `appcast.xml`。Release 版本由 GitHub `latest/download/appcast.xml` 提供该文件；Preview 版本还必须将同一 appcast 覆盖上传到永久 `preview` prerelease。

```zsh
RELEASE_CREATE_OPTIONS=()
if [[ "$UPDATE_CHANNEL" == preview ]]; then
  RELEASE_CREATE_OPTIONS+=(--prerelease)
fi

gh release create "v${VERSION}" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-arm64.dmg" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-arm64.dmg.sha256" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-arm64.zip" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-arm64.zip.sha256" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-x86_64.dmg" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-x86_64.dmg.sha256" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-x86_64.zip" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-x86_64.zip.sha256" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-universal.dmg" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-universal.dmg.sha256" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-universal.zip" \
  "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-universal.zip.sha256" \
  "$RELEASE_OUTPUT_DIRECTORY/appcast-github.xml#appcast.xml" \
  --repo wzz6423/zisla --title "zisla v${VERSION}" \
  "${RELEASE_CREATE_OPTIONS[@]}"
```

首次启用 Preview 自动更新时，先创建永久 feed Release；之后每次 Preview 发版只覆盖其 GitHub `appcast.xml`：

```zsh
if [[ "$UPDATE_CHANNEL" == preview ]]; then
  gh release view preview --repo wzz6423/zisla >/dev/null 2>&1 || \
    gh release create preview --repo wzz6423/zisla \
      --title "zisla Preview update feed" --notes "Preview Sparkle feed" --prerelease
  gh release upload preview "$RELEASE_OUTPUT_DIRECTORY/appcast-github.xml#appcast.xml" \
    --repo wzz6423/zisla --clobber
fi
```

对已存在实际版本 Release 使用 `gh release edit` 和 `gh release upload --clobber`，不要创建同 tag 的重复 Release。替换 appcast 时必须与引用的 Universal ZIP 同次上传。GitHub Release 不会自动同步到 Gitee；使用 Gitee API 创建或更新同 tag Release，并上传三套架构资产、校验文件和 `appcast-gitee.xml`（远端命名为 `appcast.xml`）。正式版本还要把该 Gitee appcast 复制到永久 `update-release`；Preview 要把同一 appcast 复制到两端永久 `preview`。所有永久 appcast 仍必须引用实际版本 tag 中本站的 Universal ZIP。

Gitee API 的 PATCH 必须携带 `tag_name`，否则返回 `400: tag_name is missing`。上传新附件后再删除同名旧附件，避免 Release 出现空档。

## 验证与清理

在 `mac/` 目录对三套资产分别执行上传前验证，`RELEASE_OUTPUT_DIRECTORY` 沿用构建时的取值：

```zsh
zsh -n Scripts/build-app.sh Scripts/package-release.sh Scripts/build-package.sh
STAGING_DIRECTORY="$RELEASE_OUTPUT_DIRECTORY/.staging"
test "$(plutil -extract CFBundleIdentifier raw -o - "$STAGING_DIRECTORY/arm64/zisla.app/Contents/Info.plist")" = "dev.wzz.zisla"
test "$(plutil -extract CFBundleDisplayName raw -o - "$STAGING_DIRECTORY/arm64/zisla.app/Contents/Info.plist")" = "zisla"
test "$(plutil -extract CFBundleIconFile raw -o - "$STAGING_DIRECTORY/arm64/zisla.app/Contents/Info.plist")" = "AppIcon"
test ! -e "$STAGING_DIRECTORY/arm64/zisla-debug.app"
for ARCHITECTURE in arm64 x86_64 universal; do
  cmp -s "$STAGING_DIRECTORY/$ARCHITECTURE/zisla.app/Contents/Resources/AppIcon.icns" Resources/AppIcon.icns
  cmp -s "$STAGING_DIRECTORY/$ARCHITECTURE/zisla.app/Contents/Resources/AppIconNight.icns" Resources/AppIconNight.icns
  codesign --verify --deep --strict --verbose=4 "$STAGING_DIRECTORY/$ARCHITECTURE/zisla.app"
  ARCHES="$(lipo -archs "$STAGING_DIRECTORY/$ARCHITECTURE/zisla.app/Contents/MacOS/zisla")"
  if [[ "$ARCHITECTURE" == universal ]]; then
    test "$ARCHES" = "arm64 x86_64"
  else
    test "$ARCHES" = "$ARCHITECTURE"
  fi
  shasum -a 256 "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-${ARCHITECTURE}.dmg"
  hdiutil attach -nobrowse "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-${ARCHITECTURE}.dmg"
  test -L /Volumes/zisla/Applications
  hdiutil detach /Volumes/zisla
done
for APPCAST in "$RELEASE_OUTPUT_DIRECTORY/appcast-gitee.xml" "$RELEASE_OUTPUT_DIRECTORY/appcast-github.xml"; do
  xmllint --noout "$APPCAST"
  rg -q 'sparkle:edSignature=' "$APPCAST"
  rg -q "<sparkle:version>${BUILD_NUMBER}</sparkle:version>" "$APPCAST"
  rg -q "zisla-v${VERSION}-macOS-universal.zip" "$APPCAST"
done
rg -q "https://gitee.com/wzz6423/zisla/releases/download/v${VERSION}/" "$RELEASE_OUTPUT_DIRECTORY/appcast-gitee.xml"
rg -q "https://github.com/wzz6423/zisla/releases/download/v${VERSION}/" "$RELEASE_OUTPUT_DIRECTORY/appcast-github.xml"
test -d "$STAGING_DIRECTORY/universal/zisla.app/Contents/Frameworks/Sparkle.framework"
codesign --verify --deep --strict "$STAGING_DIRECTORY/universal/zisla.app"
```

上传后分别获取 Gitee 主 feed 与 GitHub fallback feed，确认两者均返回 HTTP 200、为有效 XML、含签名并指向对应站点的本次 Universal ZIP：Release 验证 Gitee `update-release/download/appcast.xml` 和 GitHub `latest/download/appcast.xml`；Preview 验证两端 `releases/download/preview/appcast.xml`。任一 feed 非 200、无法解析、未签名或未指向本次 ZIP 时，停止发布并修复本次发布资产，不能以客户端版本比较作为替代。使用一台已安装旧 Sparkle 版应用的测试机，分别验证 Release→Release、Preview→Preview、Release→Preview 与 Preview→Release：切换通道后手动检查应先访问 Gitee；断开 Gitee 或让 Gitee 更新包下载失败时只能自动重试 GitHub 一次；开启自动下载时应在退出或重启时完成替换。最后在仓库根目录执行 `make clean` 删除 `outputs/`（含 `.staging/`）与本地调试产物，并清理 `.release-*`、临时挂载和本次测试下载物，不清理私钥备份。

## 交付记录

在 Release 正文中写清楚版本类型、签名方式、公证状态、已测试的 macOS 范围、WeatherKit 限制、GitHub Issues/PR 入口，以及 Gitee 不受理 Issues/PR 的事实。说明首次安装需手动完成，Sparkle 版后续更新会自动验签并在退出或重启时安装。不要包含证书序列号、访问令牌、私钥、Keychain 密码或个人 Apple ID 信息。
