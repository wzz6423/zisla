---
name: zisla-release
description: 此技能用于发布 zisla 的 macOS Preview 或 Release 版本到 GitHub 和 Gitee，分别打包 x86_64、arm64 和 Universal，并验证 Sparkle 签名自动更新、双通道 appcast 与发布资产。
---

# zisla macOS 发版

发布 zisla 的 macOS 安装包时执行本技能。覆盖 Preview 与 Release 两条通道，以及 GitHub、Gitee 两端的 Release。两个通道均使用 Sparkle 签名 ZIP 自动检查、下载、验签、替换和重启；设置中的通道切换同时影响自动检查和手动检查。

## 发布原则

- Release 主 feed 固定为 `https://gitee.com/wzz6423/zisla/releases/download/update-release/appcast.xml`，失败时仅回退一次 `https://github.com/wzz6423/zisla/releases/latest/download/appcast.xml`；Preview 主 feed 固定为 `https://gitee.com/wzz6423/zisla/releases/download/preview/appcast.xml`，失败时仅回退一次 `https://github.com/wzz6423/zisla/releases/download/preview/appcast.xml`。这四个地址是 Info.plist 里的基准值，客户端把文件名改写为运行架构的 `appcast-arm64.xml` 或 `appcast-x86_64.xml`（Rosetta 下运行的 x86_64 slice 按 `arm64` 请求，否则这台 Mac 会被永久留在 Intel 包上），只有 0.1.6 及更早的版本才请求 `appcast.xml`。Gitee appcast 检查或其更新包下载失败时回退；每次新的自动或手动检查都会重新从 Gitee 开始。appcast 与 ZIP 必须同时通过 EdDSA 签名；客户端在解压前验证，再替换并重启应用。
- Gitee 的正式永久 feed tag 是 `update-release`，Preview 永久 feed tag 是 `preview`；GitHub 的正式 feed 使用 `latest`，Preview 使用永久 prerelease tag `preview`。两个 `preview` feed 都只保存当前 Preview 的三份 appcast，且各自指向实际版本 tag（例如 `v0.2.0-preview.1`）中本站对应架构的 ZIP。GitHub 的 `preview` 必须保持 prerelease，避免污染正式 `latest`。
- 每个版本仍构建 `x86_64`、`arm64` 和 `universal` 三套包，三套 ZIP 都参与自动更新：每套各有一份只引用自己那套 ZIP 的 appcast，装哪套就一直更新哪套，单架构安装不会被 Universal 包换掉，装机体积优势也不会在一次应用内更新后消失。DMG 和校验文件只用于首次安装与 Release 页面下载，不参与应用内更新流程。
- 每次运行 `package-release.sh` 都会在同目录生成 `appcast-gitee.xml` 和 `appcast-github.xml`，两者只引用本次构建的那一套 ZIP，分别指向 Gitee 与 GitHub。`make build-package` 因此产出三对；上传时 Universal 那对命名为 `appcast.xml`（0.1.6 及更早版本请求的就是它），单架构那两对命名为 `appcast-arm64.xml` 与 `appcast-x86_64.xml`。不得手改已签名 appcast；需修改时重新运行生成工具。
- 将“实际版本的三套 ZIP 与两端三份签名 appcast（`appcast.xml`、`appcast-arm64.xml`、`appcast-x86_64.xml`）已上传，并且永久 feed 已指向该版本”视为自动更新发布的原子门禁；缺少某份架构 appcast 会让该架构的已安装版本在主 feed 和回退 feed 上同时得到 404；任一环节缺失即视为发版失败，不得宣称线上检查、发现更新或自动安装可用。不得以 Release API 的版本号、debug 专用逻辑或“已是最新”提示替代 Sparkle appcast 检查。若未获明确授权修复指定历史版本，不得回填或改动已发布版本及其永久 feed；默认在下一次更高版本发版时完整满足该门禁。
- GitHub 和 Gitee 都承载 Sparkle feed 与更新 ZIP。每个同版本 Release 必须在两端都上传 `x86_64`（X86）、`arm64` 和 `universal` 三套 DMG、ZIP 和 SHA-256，以及三份对应架构的已签名 appcast。
- **三种包都必须保留**：`x86_64` 和 `arm64` 包分别只包含单一架构，`universal` 包必须同时包含两个架构；三类资产都要分别压缩、分别上传，文件名必须带对应后缀。
- 无论安装包构建时的 `UPDATE_CHANNEL` 是什么，运行时选择 Release 或 Preview 都必须切换到对应的 Sparkle feed；自动检查和“检查更新”均遵循当前选择。切换后 Sparkle 重置下一次检查周期，手动检查立即使用新通道。
- 使用 `CFBundleShortVersionString` 作为用户可见版本。版本 tag 一律为 `v${VERSION}`（Preview 形如 `v0.2.0-preview.1`），与签名 appcast 的默认 ZIP URL 一致；禁止使用 `release/v1.2.3` 等路径前缀 tag，那会迫使每次发布额外覆盖 `SPARKLE_GITEE_DOWNLOAD_URL_PREFIX` 和 `SPARKLE_GITHUB_DOWNLOAD_URL_PREFIX`。
- Release 正文引用的截图必须先作为同一 `v${VERSION}` Release 的附件上传，并使用该 tag 的稳定下载地址。禁止带路径前缀的 `.../releases/download/release/v${VERSION}/`、会随下一版移动的 `.../releases/latest/download/` 和临时图床；正文同步到另一镜像时，可以引用已验证可达的原站图片地址。发布后要在实际页面确认每张图返回 HTTP 200 且内容确实是 PNG。
- 每次发布前验证 DMG 中只有 `zisla.app` 和 `Applications` 软链接。首次安装 Sparkle 版仍需要用户手动安装；之后的已安装 Sparkle 版本才可自动更新。
- 正式版发布完成后必须同步 Homebrew cask：`Casks/zisla.rb` 的 `version` 与两个 `sha256` 必须分别对应本次 `arm64` 与 `x86_64` ZIP，并与官网 `latestRelease` 同版本，否则 CI 的 `Verify the Homebrew cask` 失败。cask 用 `arch` 映射按机器解析下载地址，Apple Silicon 与 Intel 各自只取对应架构的包；Sparkle 之后读同一架构的 appcast，安装不会在一次应用内更新后变成 Universal。Preview 不进 tap，避免 `brew upgrade` 把用户带到预发布版本。cask 保留 `auto_updates true`，更新链路仍归 Sparkle，Homebrew 只负责首次安装与显式升级。
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
7. 正式版还要确认 `wzz6423/homebrew-tap` 已存在且当前凭据可向它推送；Preview 不涉及 tap。

```zsh
gh auth status
security find-generic-password -a 'wzz6423' -s 'gitee.com.zisla.release-token' >/dev/null
```

## 构建

在仓库根目录执行 `make build-package` 完成打包。它按 `arm64`、`x86_64`、`arm64 x86_64` 顺序调用 `mac/Scripts/package-release.sh`，对每次调用强制 `DEBUG_BUILD=false`，把三套 DMG、ZIP 及其 SHA-256 平铺到仓库根 `outputs/`，并保留三对 appcast：Universal 的 `appcast-gitee.xml` 与 `appcast-github.xml`，以及 `appcast-gitee-arm64.xml`、`appcast-github-arm64.xml`、`appcast-gitee-x86_64.xml`、`appcast-github-x86_64.xml`。`outputs/` 每次重建，其内容即本次需要上传的全部资产；GitHub Release 自动生成的源码压缩包不属于它，不得手工构造或补传。三套 `zisla.app` 保留在 `outputs/.staging/<架构>/`，只用于下面的发布前验证，不上传。

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

为实际版本建立 GitHub Release。上传 `arm64`、`x86_64` 和 `universal` 三套 DMG、ZIP、各自 SHA-256，以及三份引用 GitHub 上对应架构 ZIP 的 appcast，远端分别命名为 `appcast.xml`（Universal）、`appcast-arm64.xml` 和 `appcast-x86_64.xml`。Release 版本由 GitHub `latest/download/` 提供这三个文件；Preview 版本还必须将同三份 appcast 覆盖上传到永久 `preview` prerelease。

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
  "$RELEASE_OUTPUT_DIRECTORY/appcast-github-arm64.xml#appcast-arm64.xml" \
  "$RELEASE_OUTPUT_DIRECTORY/appcast-github-x86_64.xml#appcast-x86_64.xml" \
  --repo wzz6423/zisla --title "zisla v${VERSION}" \
  "${RELEASE_CREATE_OPTIONS[@]}"
```

首次启用 Preview 自动更新时，先创建永久 feed Release；之后每次 Preview 发版只覆盖其 GitHub `appcast.xml`：

```zsh
if [[ "$UPDATE_CHANNEL" == preview ]]; then
  gh release view preview --repo wzz6423/zisla >/dev/null 2>&1 || \
    gh release create preview --repo wzz6423/zisla \
      --title "zisla Preview update feed" --notes "Preview Sparkle feed" --prerelease
  gh release upload preview \
    "$RELEASE_OUTPUT_DIRECTORY/appcast-github.xml#appcast.xml" \
    "$RELEASE_OUTPUT_DIRECTORY/appcast-github-arm64.xml#appcast-arm64.xml" \
    "$RELEASE_OUTPUT_DIRECTORY/appcast-github-x86_64.xml#appcast-x86_64.xml" \
    --repo wzz6423/zisla --clobber
fi
```

对已存在实际版本 Release 使用 `gh release edit` 和 `gh release upload --clobber`，不要创建同 tag 的重复 Release。替换某份 appcast 时必须与它引用的那套 ZIP 同次上传。GitHub Release 不会自动同步到 Gitee；使用 Gitee API 创建或更新同 tag Release，并上传三套架构资产、校验文件和三份 Gitee appcast（远端命名为 `appcast.xml`、`appcast-arm64.xml`、`appcast-x86_64.xml`）。正式版本还要把这三份 Gitee appcast 复制到永久 `update-release`；Preview 要把同三份复制到两端永久 `preview`。所有永久 appcast 仍必须引用实际版本 tag 中本站、对应架构的 ZIP。

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
    # lipo reports fat-header order, which is x86_64 first, so compare as a sorted set.
    test "$(print -rl -- ${(s: :)ARCHES} | sort | paste -sd' ' -)" = "arm64 x86_64"
  else
    test "$ARCHES" = "$ARCHITECTURE"
  fi
  # The checksum files carry bare file names, so verify them from inside the output directory.
  (cd "$RELEASE_OUTPUT_DIRECTORY" && shasum -a 256 -c \
    "zisla-v${VERSION}-macOS-${ARCHITECTURE}.dmg.sha256" \
    "zisla-v${VERSION}-macOS-${ARCHITECTURE}.zip.sha256")
  diskutil image attach --mountOptions nobrowse "$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-${ARCHITECTURE}.dmg"
  test -L /Volumes/zisla/Applications
  diskutil eject /Volumes/zisla
done
for ARCHITECTURE in universal arm64 x86_64; do
  # The universal pair keeps the bare name because it is the appcast.xml that 0.1.6 and
  # earlier still request.
  SUFFIX=""
  [[ "$ARCHITECTURE" == universal ]] || SUFFIX="-$ARCHITECTURE"
  for HOST in gitee github; do
    APPCAST="$RELEASE_OUTPUT_DIRECTORY/appcast-${HOST}${SUFFIX}.xml"
    xmllint --noout "$APPCAST"
    rg -q 'sparkle:edSignature=' "$APPCAST"
    rg -q "<sparkle:version>${BUILD_NUMBER}</sparkle:version>" "$APPCAST"
    # One item per appcast, so an install can only be offered its own architecture.
    test "$(rg -c '<item>' "$APPCAST")" = 1
    rg -q "zisla-v${VERSION}-macOS-${ARCHITECTURE}.zip" "$APPCAST"
    rg -q "https://${HOST}.com/wzz6423/zisla/releases/download/v${VERSION}/" "$APPCAST"
  done
done
test -d "$STAGING_DIRECTORY/universal/zisla.app/Contents/Frameworks/Sparkle.framework"
codesign --verify --deep --strict "$STAGING_DIRECTORY/universal/zisla.app"
```

上传后分别获取 Gitee 主 feed 与 GitHub fallback feed 上的三份 appcast，确认每份都返回 HTTP 200、为有效 XML、含签名，并指向对应站点、对应架构的本次 ZIP：Release 验证 Gitee `update-release/download/` 与 GitHub `latest/download/` 下的 `appcast.xml`、`appcast-arm64.xml`、`appcast-x86_64.xml`；Preview 验证两端 `releases/download/preview/` 下的同三份。任一 feed 非 200、无法解析、未签名或未指向本次对应架构 ZIP 时，停止发布并修复本次发布资产，不能以客户端版本比较作为替代。使用一台已安装旧 Sparkle 版应用的测试机，分别验证 Release→Release、Preview→Preview、Release→Preview 与 Preview→Release：切换通道后手动检查应先访问 Gitee；断开 Gitee 或让 Gitee 更新包下载失败时只能自动重试 GitHub 一次；开启自动下载时应在退出或重启时完成替换。单架构测试机更新后还要用 `lipo -archs` 确认应用仍只含本机架构，Rosetta 下运行的 x86_64 安装则应更新到 `arm64` 包。再验证两端 Release 正文里的截图：每个地址都必须使用本次 `v${VERSION}` tag 的稳定下载地址，返回 HTTP 200，且下载到的字节确实是 PNG。任一截图不满足时补传附件并改正正文，不能以“本地图片没问题”替代。

```zsh
for HOST in github gitee; do
  case "$HOST" in
    github) RELEASE_BODY="$(gh release view "v${VERSION}" --repo wzz6423/zisla --json body --jq .body)" ;;
    gitee) RELEASE_BODY="$(curl -sS "https://gitee.com/api/v5/repos/wzz6423/zisla/releases/tags/v${VERSION}" | jq -r .body)" ;;
  esac
  IMAGE_URLS=(${(f)"$(print -r -- "$RELEASE_BODY" | rg -o '!\[[^]]*\]\((https://[^)]+)\)' -r '$1')"})
  test "${#IMAGE_URLS}" -ge 1
  for IMAGE_URL in "${IMAGE_URLS[@]}"; do
    [[ "$IMAGE_URL" == "https://github.com/wzz6423/zisla/releases/download/v${VERSION}/"*.png || \
      "$IMAGE_URL" == "https://gitee.com/wzz6423/zisla/releases/download/v${VERSION}/"*.png ]]
    IMAGE_FILE="$(mktemp "${TMPDIR:-/tmp}/zisla-release-image.XXXXXX")"
    test "$(curl -sSL -o "$IMAGE_FILE" -w '%{http_code}' "$IMAGE_URL")" = 200
    file -b "$IMAGE_FILE" | rg -q '^PNG image data'
    rm -f "$IMAGE_FILE"
  done
done
```

正式版还要先完成下节的 Homebrew cask 同步（它要读 `outputs/` 里 `arm64` 与 `x86_64` ZIP 的校验文件），再在仓库根目录执行 `make clean` 删除 `outputs/`（含 `.staging/`）与本地调试产物，并清理 `.release-*`、临时挂载和本次测试下载物，不清理私钥备份。

## 同步 Homebrew cask

仅正式版执行，Preview 跳过本节。两端 Release 资产上传并通过上节验证后，在仓库根目录执行：

```zsh
PUBLISH_TAP=true make sync-cask
```

脚本沿用已导出的 `VERSION` 与 `RELEASE_OUTPUT_DIRECTORY`，改写 `Casks/zisla.rb` 的 `version` 与两个 `sha256`：优先读 `$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-arm64.zip.sha256` 与同目录的 `x86_64` 校验文件，缺失时从已发布的 GitHub 资产拉取。校验不通过的 cask 不会写回；通过后镜像到 `wzz6423/homebrew-tap`。不带 `PUBLISH_TAP` 即为试运行，只更新仓库内的 cask。

改写后的 cask 必须与官网 `latestRelease` 的版本改动一起提交，随后确认 tap 真的可安装：

```zsh
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

`brew list --cask --versions` 必须报出本次版本，`brew livecheck` 必须解析到同一版本。cask 的下载地址必须同时保留 `#{version}` 与 `#{arch}` 插值：写死版本号会让 `brew upgrade` 在下一版拉到旧包，写死架构会把另一半用户带到错误的包。

## 交付记录

在 Release 正文中写清楚版本类型、签名方式、公证状态、已测试的 macOS 范围、WeatherKit 限制、GitHub Issues/PR 入口，以及 Gitee 不受理 Issues/PR 的事实。说明首次安装需手动完成，Sparkle 版后续更新会自动验签并在退出或重启时安装。不要包含证书序列号、访问令牌、私钥、Keychain 密码或个人 Apple ID 信息。截图不由 `make build-package` 产出，也不属于 `outputs/`：先将截图作为 `v${VERSION}` Release 的附件上传，再在正文引用该 tag 的稳定地址；若两端都承载截图，则分别引用各自站点的地址。
