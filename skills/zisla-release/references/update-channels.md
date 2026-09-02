# zisla 更新通道策略

| 用户选择 | 主 feed | 单次回退 feed | 发布物 |
| --- | --- | --- | --- |
| Release | Gitee `update-release/download/appcast.xml` | GitHub `latest/download/appcast.xml` | 各自 EdDSA 签名的 Universal ZIP；Sparkle 自动下载、验签、替换与重启 |
| Preview | Gitee `releases/download/preview/appcast.xml` | GitHub `releases/download/preview/appcast.xml` | 各自 EdDSA 签名的 Universal ZIP；Sparkle 自动下载、验签、替换与重启 |

运行时设置的 `UpdateChannel` 同时决定自动检查与手动检查的目标，不受安装包初始 `ZislaDefaultUpdateChannel` 限制。每次检查都先读取 Gitee；Gitee appcast 检查或更新包下载失败时重试 GitHub 一次，GitHub 失败后不会再次回到 Gitee。切换通道时，Sparkle 将重置下一次自动检查周期；手动检查立即读取新 feed。更新 ZIP 验签后会在退出或重启时安装。

`package-release.sh` 为每次构建生成 `appcast-gitee.xml` 和 `appcast-github.xml`。Release appcast 默认使用实际 `v${VERSION}` tag 的站点内下载 URL；若使用 `release/v1.2.3` 等路径前缀 tag，必须同时设置 `SPARKLE_GITEE_DOWNLOAD_URL_PREFIX` 和 `SPARKLE_GITHUB_DOWNLOAD_URL_PREFIX`。每个 Preview 仍发布至实际 prerelease tag，并将各自已签名的 appcast 覆盖上传到对应永久 `preview` tag；正式 Gitee appcast 则覆盖上传到永久 `update-release`。绝不可让某站 appcast 引用另一站的 ZIP。
