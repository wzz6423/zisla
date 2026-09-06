---
name: zisla-release
description: 此技能用于发布 zisla 的 macOS Preview 或 Release 版本到 GitHub 和 Gitee，分别打包 x86_64、arm64 和 Universal，并验证 Sparkle 签名自动更新、双通道 appcast 与发布资产。
---

# zisla macOS 发版

发布 zisla 的 macOS 安装包时执行本技能。覆盖 Preview 与 Release 两条通道，以及 GitHub、Gitee 两端的 Release。两个通道均使用 Sparkle 签名 ZIP 自动检查、下载、验签、替换和重启；设置中的通道切换同时影响自动检查和手动检查。

## 发布原则

- Release 主 feed 固定为 `https://gitee.com/wzz6423/zisla/releases/download/update-release/appcast.xml`，失败时仅回退一次 `https://github.com/wzz6423/zisla/releases/latest/download/appcast.xml`；Preview 主 feed 固定为 `https://gitee.com/wzz6423/zisla/releases/download/preview/appcast.xml`，失败时仅回退一次 `https://github.com/wzz6423/zisla/releases/download/preview/appcast.xml`。这四个地址是 Info.plist 里的基准值，单架构安装把文件名改写为运行架构的 `appcast-arm64.xml` 或 `appcast-x86_64.xml`（Rosetta 下运行的 x86_64 slice 按 `arm64` 请求，否则这台 Mac 会被永久留在 Intel 包上）；Universal 安装按可执行文件里的 slice 数判定，保留 `appcast.xml`，更新后仍是 Universal。0.1.6 及更早的版本不含 Sparkle，只能手动下载新版，因此没有任何已发布版本依赖这份基准名。Gitee appcast 检查或其更新包下载失败时回退；每次新的自动或手动检查都会重新从 Gitee 开始。appcast 与 ZIP 必须同时通过 EdDSA 签名；客户端在解压前验证，再替换并重启应用。
- Gitee 的正式永久 feed tag 是 `update-release`，Preview 永久 feed tag 是 `preview`；GitHub 的正式 feed 使用 `latest`，Preview 使用永久 prerelease tag `preview`。两个 `preview` feed 都只保存当前 Preview 的三份 appcast，且各自指向实际版本 tag（例如 `v0.2.0-preview.1`）中本站对应架构的 ZIP。GitHub 的 `preview` 必须保持 prerelease，避免污染正式 `latest`。
- 每个版本仍构建 `x86_64`、`arm64` 和 `universal` 三套包，三套 ZIP 都参与自动更新：每套各有一份只引用自己那套 ZIP 的 appcast，装哪套就一直更新哪套——单架构安装不会被 Universal 包换掉，装机体积优势不会在一次应用内更新后消失；Universal 安装也不会被换成单架构包，跨架构可用不会因为一次更新而失去。DMG 和校验文件只用于首次安装与 Release 页面下载，不参与应用内更新流程。
- 每次运行 `package-release.sh` 都会在同目录生成 `appcast-gitee.xml` 和 `appcast-github.xml`，两者只引用本次构建的那一套 ZIP，分别指向 Gitee 与 GitHub。`make build-package` 因此产出三对；上传时 Universal 那对命名为 `appcast.xml`（Universal 安装请求的就是它），单架构那两对命名为 `appcast-arm64.xml` 与 `appcast-x86_64.xml`。不得手改已签名 appcast；需修改时重新运行生成工具。
- 将“实际版本的三套 ZIP 与两端三份签名 appcast（`appcast.xml`、`appcast-arm64.xml`、`appcast-x86_64.xml`）已上传，并且永久 feed 已指向该版本”视为自动更新发布的原子门禁；缺少某份架构 appcast 会让该架构的已安装版本在主 feed 和回退 feed 上同时得到 404；任一环节缺失即视为发版失败，不得宣称线上检查、发现更新或自动安装可用。不得以 Release API 的版本号、debug 专用逻辑或“已是最新”提示替代 Sparkle appcast 检查。若未获明确授权修复指定历史版本，不得回填或改动已发布版本及其永久 feed；默认在下一次更高版本发版时完整满足该门禁。
- GitHub 和 Gitee 都承载 Sparkle feed 与更新 ZIP。每个同版本 Release 必须在两端都上传 `x86_64`（X86）、`arm64` 和 `universal` 三套 DMG、ZIP 和 SHA-256，以及三份对应架构的已签名 appcast。
- **三种包都必须保留**：`x86_64` 和 `arm64` 包分别只包含单一架构，`universal` 包必须同时包含两个架构；三类资产都要分别压缩、分别上传，文件名必须带对应后缀。
- 无论安装包构建时的 `UPDATE_CHANNEL` 是什么，运行时选择 Release 或 Preview 都必须切换到对应的 Sparkle feed；自动检查和“检查更新”均遵循当前选择。切换后 Sparkle 重置下一次检查周期，手动检查立即使用新通道。
- 使用 `CFBundleShortVersionString` 作为用户可见版本。版本 tag 一律为 `v${VERSION}`（Preview 形如 `v0.2.0-preview.1`），与签名 appcast 的默认 ZIP URL 一致；禁止使用 `release/v1.2.3` 等路径前缀 tag，那会迫使每次发布额外覆盖 `SPARKLE_GITEE_DOWNLOAD_URL_PREFIX` 和 `SPARKLE_GITHUB_DOWNLOAD_URL_PREFIX`。
- Release 正文引用的截图必须先作为同一 `v${VERSION}` Release 的附件上传，并使用该 tag 的稳定下载地址。禁止带路径前缀的 `.../releases/download/release/v${VERSION}/`、会随下一版移动的 `.../releases/latest/download/` 和临时图床；正文同步到另一镜像时，可以引用已验证可达的原站图片地址。发布后要在实际页面确认每张图返回 HTTP 200 且内容确实是 PNG。
- 每次发布前验证 DMG 中只有 `zisla.app` 和 `Applications` 软链接。首次安装 Sparkle 版仍需要用户手动安装；之后的已安装 Sparkle 版本才可自动更新。
- 正式版发布完成后必须同步 Homebrew cask：`Casks/zisla.rb` 的 `version` 与两个 `sha256` 必须分别对应本次 `arm64` 与 `x86_64` ZIP，并与官网 `latestRelease` 同版本，否则 CI 的 `Verify the Homebrew cask` 失败。cask 用 `arch` 映射按机器解析下载地址，Apple Silicon 与 Intel 各自只取对应架构的包；Sparkle 之后读同一架构的 appcast，安装不会在一次应用内更新后变成 Universal。Preview 不进 tap，避免 `brew upgrade` 把用户带到预发布版本。cask 保留 `auto_updates true`，更新链路仍归 Sparkle，Homebrew 只负责首次安装、显式升级，以及已装应用落后于 tap 时的兜底升级。tap 里的版本只能是三份 appcast 都已上传并验证通过的版本：brew 装到的用户之后靠 Sparkle 拿更新，而 `auto_updates true` 让 Homebrew 只在已装应用确实旧于 tap 时才接手（Homebrew 5.1.6 起读应用包内的版本号，更早的版本直接跳过 `auto_updates` 的 cask）。所以不含 Sparkle 或 appcast 缺失的版本必须先从 tap 移除（`Casks/zisla.rb` 曾因指向不含 Sparkle 的 0.1.6 而被撤下）。
- 发版构建严禁使用调试变体：必须显式使用 `DEBUG_BUILD=false`，产物必须是 `zisla.app`、Bundle ID `dev.wzz.zisla`；`zisla-debug.app` 或 `dev.wzz.zisla.debug` 只能用于本地调试，不能上传。
- 发版资源必须来自正式资源目录：`AppIcon.icns` 必须作为主图标，`AppIconNight.icns` 只能作为深色模式备用图标；调试构建使用的黑底白字图标复制方式，以及 `zisla-debug.app` 中的任何资源，都不能用于正式包或通过改名后上传。
- 发版不得把 `make run` 生成的 `dist/zisla-debug.app` 直接压缩、改名或复制资源；必须由 `Scripts/package-release.sh` 重新构建正式包并通过身份与图标校验。

详细凭据和通道约束见 [references/credentials.md](references/credentials.md) 与 [references/update-channels.md](references/update-channels.md)。

## 发行前检查

1. 从两端一致的最新 `main` 和干净工作树开始；待发代码必须在冻结前合入，不带任何未提交修改发版。确定本次 `VERSION`，完成以下检查后再创建 begin commit。
2. 确认 `UPDATE_CHANNEL` 与本次版本类型匹配，并确认两端实际版本 tag 使用 `v${VERSION}`；Release 同步 Gitee `update-release` 和 GitHub `latest`，Preview 同步两端永久 `preview` feed。
3. 确认 GitHub CLI 已登录，Gitee Release API 令牌已安全保存。
4. 清除调试构建状态：即使当前 shell 继承了 `DEBUG_BUILD=true`，也必须在每次发版构建前显式设置 `DEBUG_BUILD=false`，并在产物中核对正式 Bundle ID。
5. 核对资源身份：正式包的主图标必须与 `Resources/AppIcon.icns` 完全一致，不能是 `Resources/AppIconNight.icns` 的副本。
6. 确认 Sparkle 2.9.4 的 `generate_appcast` 可执行，私钥位于钥匙串或已移动到受限的离线/加密位置；不得打印、提交或上传私钥。
7. 核对签名密钥配对：私钥推导出的公钥必须与 `mac/Resources/Info.plist` 的 `SUPublicEDKey` 完全一致。签错密钥的表现是客户端发现更新、下载完成后静默不安装，而整套 appcast 必须重新生成，所以必须在构建前查。
8. 正式版还要确认 `wzz6423/homebrew-tap` 已存在且当前凭据可向它推送；Preview 不涉及 tap。

```zsh
gh auth status
security find-internet-password -s gitee.com -a wzz6423 >/dev/null
# -p 只打印公钥，不输出私钥；--account 必须给，默认账户名 ed25519 下没有这把钥匙。
test "$("${SPARKLE_GENERATE_APPCAST:h}/generate_keys" --account zisla-update-ed25519 -p)" = \
  "$(plutil -extract SUPublicEDKey raw -o - mac/Resources/Info.plist)"
```

## 开始发版：冻结与 begin commit

从 begin 到 end 推送并验证完成期间，**不得合入任何 PR**，包括自动合并、merge queue、机器人与人工操作。开始前暂停这些入口并通知协作者冻结 `main`；确认冻结有效后才提交 begin。没有权限落实冻结时停止并说明阻塞。失败、超时或会话中断都不能自动解除冻结，也不能提交 end；恢复时沿用已记录的 `VERSION`、通道、构建号和同一个 begin SHA，不新建 begin、不移动版本 tag。若源代码必须修复或远端 `main` 已前进，停止本轮并报告，由用户明确决定如何结束失败发布和启动新一轮，不得悄悄重置分支或继续上传。

版本号只通过环境变量 `VERSION` 传入打包脚本；应用构建脚本的 `VERSION` 默认值为 `unknow`（准确拼写），不在发版时改成实际版本。`mac/Resources/Info.plist` 保留 `@VERSION@` 模板并由构建替换；`unknow` 不能出现在发布包或 appcast 中。已发布的 cask、官网 `latestRelease` 和历史发布记录仍记录真实版本，不属于源码默认值。

begin **只能修改 `mac/Scripts/build-app.sh` 中 `BUILD_NUMBER` 的默认值这一行**；它是唯一持久化构建号。先核对 GitHub/Gitee 两端 Release 与 Preview 已发布的最大构建号，新值必须超过所有已发布值；不能机械地把本地默认值加一。不要新增第二份构建号文件，也不要用独立环境值覆盖已提交的构建号。所有示例在同一个 `zsh` 会话执行，任何门禁失败即停止：

```zsh
set -euo pipefail
export VERSION="${VERSION:?先设置本次实际版本}"
export UPDATE_CHANNEL="${UPDATE_CHANNEL:?先设置 release 或 preview}"
GITEE_REMOTE='git@gitee.com:wzz6423/zisla.git'
remote_commit() {
  git ls-remote --exit-code "$1" "$2" "${2}^{}" | awk '
    /\^\{\}$/ { peeled = $1 }
    !/\^\{\}$/ { direct = $1 }
    END { print (peeled != "" ? peeled : direct) }
  '
}
test -z "$(git status --porcelain)"
test "$(git branch --show-current)" = main
git pull --ff-only origin main
test "$(git rev-parse HEAD)" = "$(remote_commit origin refs/heads/main)"
test "$(git rev-parse HEAD)" = "$(remote_commit "$GITEE_REMOTE" refs/heads/main)"
# Edit only the BUILD_NUMBER default in build-app.sh before continuing.
```

编辑完成后，核对差异并提交；不要 `git add .`：

```zsh
export BUILD_NUMBER="$(sed -n 's/^BUILD_NUMBER="${BUILD_NUMBER:-\([0-9][0-9]*\)}"$/\1/p' mac/Scripts/build-app.sh)"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]
git diff -- mac/Scripts/build-app.sh
git add mac/Scripts/build-app.sh
test "$(git status --porcelain)" = 'M  mac/Scripts/build-app.sh'
git diff --cached --check
git diff --cached --unified=0 -- mac/Scripts/build-app.sh | ruby -e '
  changes = STDIN.each_line.reject { |line| line.start_with?("+++", "---") }
    .select { |line| line.start_with?("+", "-") }.map(&:strip)
  abort "begin must change only the BUILD_NUMBER default" unless changes.length == 2 &&
    changes[0].match?(/\A-BUILD_NUMBER="\$\{BUILD_NUMBER:-[0-9]+\}"\z/) &&
    changes[1].match?(/\A\+BUILD_NUMBER="\$\{BUILD_NUMBER:-[0-9]+\}"\z/)
'
git commit -m "chore(release): prepare release[begin] - update build id to ${BUILD_NUMBER}"
export RELEASE_BEGIN_SHA="$(git rev-parse HEAD)"
test -z "$(git status --porcelain)"
git push origin HEAD:refs/heads/main
git push "$GITEE_REMOTE" HEAD:refs/heads/main
```

立即在发布记录中保存 begin SHA、版本、通道和构建号。两端实际版本 tag 都必须显式指向这个 SHA，Release 必须使用已有的这个 tag，禁止让 GitHub/Gitee 根据默认分支自动创建版本 tag。首次发布时：

```zsh
test "$(remote_commit origin refs/heads/main)" = "$RELEASE_BEGIN_SHA"
test "$(remote_commit "$GITEE_REMOTE" refs/heads/main)" = "$RELEASE_BEGIN_SHA"
git tag "v${VERSION}" "$RELEASE_BEGIN_SHA"
git push origin "refs/tags/v${VERSION}"
git push "$GITEE_REMOTE" "refs/tags/v${VERSION}"
release_gate() {
  test "$(git rev-parse HEAD)" = "${1:-$RELEASE_BEGIN_SHA}" || return 1
  test "$(git rev-parse "v${VERSION}^{commit}")" = "$RELEASE_BEGIN_SHA" || return 1
  local release_remote
  for release_remote in origin "$GITEE_REMOTE"; do
    test "$(remote_commit "$release_remote" refs/heads/main)" = "$RELEASE_BEGIN_SHA" || return 1
    test "$(remote_commit "$release_remote" "refs/tags/v${VERSION}")" = "$RELEASE_BEGIN_SHA" || return 1
  done
}
release_gate
```

中断恢复时，先从记录恢复变量和上述函数，核对已有 tag 的 commit，不重复执行 `git tag`，不 force push。**每次构建、上传/覆盖资产、更新永久 feed，以及提交 end 前都执行 `release_gate`**；构建和上传前还要求 `git status --porcelain` 为空。产物必须在 begin SHA 的干净源码上生成，任何门禁失败均保留冻结状态并停止。永久 `preview` / `update-release` 是 feed 标签，不替代实际版本 tag。

## 构建

在仓库根目录执行 `make build-package` 完成打包。它按 `arm64`、`x86_64`、`arm64 x86_64` 顺序调用 `mac/Scripts/package-release.sh`，对每次调用强制 `DEBUG_BUILD=false`，把三套 DMG、ZIP 及其 SHA-256 平铺到仓库根 `outputs/`，并保留三对 appcast：Universal 的 `appcast-gitee.xml` 与 `appcast-github.xml`，以及 `appcast-gitee-arm64.xml`、`appcast-github-arm64.xml`、`appcast-gitee-x86_64.xml`、`appcast-github-x86_64.xml`。`outputs/` 每次重建，其内容即本次需要上传的全部资产；GitHub Release 自动生成的源码压缩包不属于它，不得手工构造或补传。三套 `zisla.app` 保留在 `outputs/.staging/<架构>/`，只用于下面的发布前验证，不上传。

`CODE_SIGN_IDENTITY=-` 是免费 ad-hoc 分发；它不需要 Apple Developer Program，但未公证，首次启动可能需要用户在系统设置中选择“仍要打开”。后续更新仍由 Sparkle 的 EdDSA 签名保护。

**必须构建三套包**：`arm64`、`x86_64`（X86）单架构包，以及同时包含两个架构的 `universal` 包；`make build-package` 一次生成三套，缺任一套即视为打包失败：

```zsh
release_gate
test -z "$(git status --porcelain)"
export VERSION="${VERSION:?沿用 begin 记录的实际版本}"
export BUILD_NUMBER="$(sed -n 's/^BUILD_NUMBER="${BUILD_NUMBER:-\([0-9][0-9]*\)}"$/\1/p' mac/Scripts/build-app.sh)"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]
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
release_gate
test -z "$(git status --porcelain)"
DEBUG_BUILD=false ARCHIVE_DIRECTORY="$PWD/.release-v${VERSION}/arm64" \
  BUILD_ARCHITECTURES=arm64 Scripts/package-release.sh
```

单架构构建不得生成 Universal 内容；Universal 构建不得只包含一个架构。若脚本的输出文件名与上述后缀不一致，停止本轮并按失败流程处理，不得在 begin 后修改源码继续发版；禁止仅修改文件名后上传未经架构验证的包。

`SPARKLE_ED_KEY_FILE` 优先于钥匙串；无交互发布必须显式设置它。仅在本机交互发布时，才可不设置该变量并由 `zisla-update-ed25519` 登录钥匙串账户读取。拥有 Developer ID 证书和公证凭据后，将 `CODE_SIGN_IDENTITY` 替换为 `Developer ID Application: ...`，并在上传前完成 notarization 与 stapling。

## GitHub 与 Gitee 发布

为实际版本建立 GitHub Release。上传 `arm64`、`x86_64` 和 `universal` 三套 DMG、ZIP、各自 SHA-256，以及三份引用 GitHub 上对应架构 ZIP 的 appcast，远端分别命名为 `appcast.xml`（Universal）、`appcast-arm64.xml` 和 `appcast-x86_64.xml`。Release 版本由 GitHub `latest/download/` 提供这三个文件；Preview 版本还必须将同三份 appcast 覆盖上传到永久 `preview` prerelease。

```zsh
release_gate
test -z "$(git status --porcelain)"
RELEASE_CREATE_OPTIONS=()
if [[ "$UPDATE_CHANNEL" == preview ]]; then
  RELEASE_CREATE_OPTIONS+=(--prerelease)
fi

# gh 的 `文件#文字` 只设显示 label，资产名仍是 basename，而下载地址用的正是资产名，
# 所以三份 appcast 必须先复制成远端要的名字，否则 latest/download/appcast.xml 会 404。
GITHUB_FEED_DIRECTORY="$(mktemp -d)"
cp "$RELEASE_OUTPUT_DIRECTORY/appcast-github.xml" "$GITHUB_FEED_DIRECTORY/appcast.xml"
cp "$RELEASE_OUTPUT_DIRECTORY/appcast-github-arm64.xml" "$GITHUB_FEED_DIRECTORY/appcast-arm64.xml"
cp "$RELEASE_OUTPUT_DIRECTORY/appcast-github-x86_64.xml" "$GITHUB_FEED_DIRECTORY/appcast-x86_64.xml"

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
  "$GITHUB_FEED_DIRECTORY/appcast.xml" \
  "$GITHUB_FEED_DIRECTORY/appcast-arm64.xml" \
  "$GITHUB_FEED_DIRECTORY/appcast-x86_64.xml" \
  --repo wzz6423/zisla --title "zisla v${VERSION}" --verify-tag --target "$RELEASE_BEGIN_SHA" \
  "${RELEASE_CREATE_OPTIONS[@]}"
```

首次启用 Preview 自动更新时，先创建永久 feed Release；之后每次 Preview 发版只覆盖其 GitHub `appcast.xml`：

```zsh
release_gate
if [[ "$UPDATE_CHANNEL" == preview ]]; then
  gh release view preview --repo wzz6423/zisla >/dev/null 2>&1 || \
    gh release create preview --repo wzz6423/zisla \
      --title "zisla Preview update feed" --notes "Preview Sparkle feed" --prerelease \
      --target "$RELEASE_BEGIN_SHA"
  gh release upload preview \
    "$GITHUB_FEED_DIRECTORY/appcast.xml" \
    "$GITHUB_FEED_DIRECTORY/appcast-arm64.xml" \
    "$GITHUB_FEED_DIRECTORY/appcast-x86_64.xml" \
    --repo wzz6423/zisla --clobber
fi
```

对已存在实际版本 Release 使用 `gh release edit` 和 `gh release upload --clobber`，不要创建同 tag 的重复 Release。替换某份 appcast 时必须与它引用的那套 ZIP 同次上传。GitHub Release 不会自动同步到 Gitee；使用 Gitee API 创建或更新同 tag Release，并上传三套架构资产、校验文件和三份 Gitee appcast（远端命名为 `appcast.xml`、`appcast-arm64.xml`、`appcast-x86_64.xml`）。正式版本还要把这三份 Gitee appcast 复制到永久 `update-release`；Preview 要把同三份复制到两端永久 `preview`。所有永久 appcast 仍必须引用实际版本 tag 中本站、对应架构的 ZIP。

Gitee 创建实际版本 Release 前先通过 `release_gate`，请求必须显式携带 `tag_name="v${VERSION}"` 与 `target_commitish="$RELEASE_BEGIN_SHA"`，且已存在的版本 tag 必须解析为 begin SHA；创建后再次核对两端实际版本 tag。已有 Release 的恢复上传同样受门禁约束，不得修改 tag 指向。

Gitee API 的 PATCH 必须携带 `tag_name`，否则返回 `400: tag_name is missing`。上传新附件后再删除同名旧附件，避免 Release 出现空档。

Gitee 的「最新版」徽章按 Release 创建顺序（id）判定，既不看 `prerelease` 标记也不看更新时间，因此永久 `update-release` 必须在实际版本 Release **之前**创建或刷新。顺序颠倒时徽章会落在只放 appcast 的永久 feed 上，`PATCH` 重新保存实际版本 Release 也纠正不了，只能删掉它再按同 tag 重建（`DELETE /releases/{id}` 不会删除 git tag，重建会得到更大的 id）。

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
  test "$(plutil -extract CFBundleShortVersionString raw -o - "$STAGING_DIRECTORY/$ARCHITECTURE/zisla.app/Contents/Info.plist")" = "$VERSION"
  test "$(plutil -extract CFBundleVersion raw -o - "$STAGING_DIRECTORY/$ARCHITECTURE/zisla.app/Contents/Info.plist")" = "$BUILD_NUMBER"
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
  # The universal pair keeps the bare name because that is the appcast.xml a universal
  # install requests.
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

上传后分别获取 Gitee 主 feed 与 GitHub fallback feed 上的三份 appcast，确认每份都返回 HTTP 200、为有效 XML、含签名，并指向对应站点、对应架构的本次 ZIP：Release 验证 Gitee `update-release/download/` 与 GitHub `latest/download/` 下的 `appcast.xml`、`appcast-arm64.xml`、`appcast-x86_64.xml`；Preview 验证两端 `releases/download/preview/` 下的同三份。任一 feed 非 200、无法解析、未签名或未指向本次对应架构 ZIP 时，停止发布并修复本次发布资产，不能以客户端版本比较作为替代。使用一台已安装旧 Sparkle 版应用的测试机，分别验证 Release→Release、Preview→Preview、Release→Preview 与 Preview→Release：切换通道后手动检查应先访问 Gitee；断开 Gitee 或让 Gitee 更新包下载失败时只能自动重试 GitHub 一次；开启自动下载时应在退出或重启时完成替换。线上还没有任何含 Sparkle 的已发布版本时（0.1.6 及更早都不含），用本次包自建旧版代替，不得因为“没有旧版可装”而跳过这一步。单架构测试机更新后还要用 `lipo -archs` 确认应用仍只含本机架构，Universal 安装更新后同样用 `lipo -archs` 确认仍含两个架构，Rosetta 下运行的 x86_64 安装则应更新到 `arm64` 包。再验证两端 Release 正文里的截图：每个地址都必须使用本次 `v${VERSION}` tag 的稳定下载地址，返回 HTTP 200，且下载到的字节确实是 PNG。任一截图不满足时补传附件并改正正文，不能以“本地图片没问题”替代。

两端资产清单与六份 feed 用与 CI 同一份脚本核对，避免逐个 URL 手点漏掉某个架构：

```zsh
# 六份 feed 各自 200、恰好一个 item、带 edSignature，且指向本站本架构的本次 ZIP。
ruby .github/scripts/appcast-feeds.rb verify --tag "v${VERSION}" --channel "$UPDATE_CHANNEL"
# 15 份必需资产：三套 DMG/ZIP 及其 SHA-256，加三份 appcast。截图和源码包属于额外资产。
gh release view "v${VERSION}" --repo wzz6423/zisla --json assets --jq '.assets[].name' \
  | ruby .github/scripts/appcast-feeds.rb verify-assets --tag "v${VERSION}"
curl -sS "https://gitee.com/api/v5/repos/wzz6423/zisla/releases/tags/v${VERSION}" \
  | jq -r '.assets[].name' \
  | ruby .github/scripts/appcast-feeds.rb verify-assets --tag "v${VERSION}"
if [[ "$UPDATE_CHANNEL" == preview ]]; then
  gh release view preview --repo wzz6423/zisla --json assets --jq '.assets[].name' \
    | ruby .github/scripts/appcast-feeds.rb verify-assets --tag preview --layout feed
fi
```

发布后 GitHub Actions 的 `Release Feeds` 会自动跑上面这套校验：`release: published` 触发，prerelease 自动走 preview 通道，永久 feed tag（`preview`、`update-release`）跳过。永久 feed 是手工发版的后续步骤，所以它最多轮询 10 次、每次间隔 60 秒，任一环节始终缺失才失败；补齐资产后用 `gh workflow run 'Release Feeds' -f tag="v${VERSION}" -f channel="$UPDATE_CHANNEL"` 重跑即可。runner 访问 Gitee 常被限流或拒绝，此时该工作流只验 GitHub 回退 feed 并给出 warning，Gitee 主 feed 仍必须按上面的命令人工验证过才算发版完成。

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

自建旧版只改版本号与 Bundle ID，因此它验的是真实私钥签出的线上 feed、应用内置的真实 `SUPublicEDKey`，以及终止旧实例后重新拉起新版这一段——这三项本地测试都覆盖不到。改 Bundle ID 是为了不污染正式实例的 Sparkle 偏好；改过 Info.plist 必须重签，否则 Sparkle 校验宿主签名时失败。

```zsh
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-update-test.XXXXXX")"
ditto "$RELEASE_OUTPUT_DIRECTORY/.staging/arm64/zisla.app" "$TEST_ROOT/zisla.app"
TEST_INFO="$TEST_ROOT/zisla.app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string 0.0.1 "$TEST_INFO"
plutil -replace CFBundleVersion -string 1 "$TEST_INFO"
plutil -replace CFBundleIdentifier -string dev.wzz.zisla.updatetest "$TEST_INFO"
codesign --force --deep --sign - "$TEST_ROOT/zisla.app"
open "$TEST_ROOT/zisla.app"
# 在这个实例里切换通道并手动检查更新，走完下载、验签、替换与重启。
# 验完删除测试实例与它的偏好文件：
# rm -rf "$TEST_ROOT" ~/Library/Preferences/dev.wzz.zisla.updatetest.plist
```

正式版还要先完成下节的 Homebrew cask 同步（它要读 `outputs/` 里 `arm64` 与 `x86_64` ZIP 的校验文件），再在仓库根目录执行 `make clean` 删除 `outputs/`（含 `.staging/`）与本地调试产物，并清理 `.release-*`、临时挂载和本次测试下载物，不清理私钥备份。

## 同步 Homebrew cask

仅正式版执行，Preview 跳过本节。两端 Release 资产上传并通过上节验证后，在仓库根目录执行：

```zsh
release_gate
PUBLISH_TAP=true make sync-cask
```

脚本沿用已导出的 `VERSION` 与 `RELEASE_OUTPUT_DIRECTORY`，改写 `Casks/zisla.rb` 的 `version` 与两个 `sha256`：优先读 `$RELEASE_OUTPUT_DIRECTORY/zisla-v${VERSION}-macOS-arm64.zip.sha256` 与同目录的 `x86_64` 校验文件，缺失时从已发布的 GitHub 资产拉取。校验不通过的 cask 不会写回；通过后镜像到 `wzz6423/homebrew-tap`。不带 `PUBLISH_TAP` 即为试运行，只更新仓库内的 cask。

改写官网 `web/src/content.ts` 的 `latestRelease` 和 `web/README.md` 的下载链接，与 cask 使用同一实际版本；这三项留到 end 一起提交。先确认 tap 真的可安装：

```zsh
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

`brew list --cask --versions` 必须报出本次版本，`brew livecheck` 必须解析到同一版本。cask 的下载地址必须同时保留 `#{version}` 与 `#{arch}` 插值：写死版本号会让 `brew upgrade` 在下一版拉到旧包，写死架构会把另一半用户带到错误的包。

## 结束发版：end commit

只有两端全部资产、六份永久 feed、截图与自动更新验证通过，且正式版的 tap/cask/官网同步及校验完成，才允许结束；任何跳过、失败或未完成的验证都不得用 end 标记成功。正式版仅暂存 `Casks/zisla.rb`、`web/src/content.ts` 和 `web/README.md` 的发布元数据；tap 仓库由 `sync-cask` 单独提交和推送，其远端版本、校验和也须确认。Preview 不更新正式 cask、tap 或官网，但仍提交相同格式的空 end commit。

```zsh
release_gate
if [[ "$UPDATE_CHANNEL" == release ]]; then
  ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
  git add Casks/zisla.rb web/src/content.ts web/README.md
fi
git diff --cached --check
# The release executor must check that only release metadata is staged; Preview must be clean.
git status --short
git diff --cached
git commit --allow-empty -m 'chore(release): finish release[end] - update tap, casks and web'
RELEASE_END_SHA="$(git rev-parse HEAD)"
test "$(git rev-parse HEAD^)" = "$RELEASE_BEGIN_SHA"
release_gate "$RELEASE_END_SHA"
git push origin HEAD:refs/heads/main
git push "$GITEE_REMOTE" HEAD:refs/heads/main
for RELEASE_REMOTE in origin "$GITEE_REMOTE"; do
  test "$(remote_commit "$RELEASE_REMOTE" refs/heads/main)" = "$RELEASE_END_SHA"
  test "$(remote_commit "$RELEASE_REMOTE" "refs/tags/v${VERSION}")" = "$RELEASE_BEGIN_SHA"
done
```

版本 tag 和两端 Release **始终标记 begin**，不得移动到 end；end 只记录发布收尾。end 若只有一端推送成功，继续冻结，核对成功端为 end、另一端仍为 begin、两端版本 tag 均为 begin 后，仅补推同一个 end 到缺失端，不新建 commit。全部远端校验通过后，记录 end SHA、恢复此前暂停的合并入口，才允许后续 PR 合入。完成清理并确认工作树干净。

## 交付记录

在 Release 正文中写清楚版本类型、签名方式、公证状态、已测试的 macOS 范围、WeatherKit 限制、GitHub Issues/PR 入口，以及 Gitee 不受理 Issues/PR 的事实。说明首次安装需手动完成，Sparkle 版后续更新会自动验签并在退出或重启时安装。不要包含证书序列号、访问令牌、私钥、Keychain 密码或个人 Apple ID 信息。截图不由 `make build-package` 产出，也不属于 `outputs/`：先将截图作为 `v${VERSION}` Release 的附件上传，再在正文引用该 tag 的稳定地址；若两端都承载截图，则分别引用各自站点的地址。
