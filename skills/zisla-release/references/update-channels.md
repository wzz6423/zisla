# zisla 更新通道策略

| 用户选择 | 主 feed | 单次回退 feed | 发布物 |
| --- | --- | --- | --- |
| Release | Gitee `update-release/download/appcast-<架构>.xml` | GitHub `latest/download/appcast-<架构>.xml` | 各自 EdDSA 签名的同架构 ZIP；Sparkle 自动下载、验签、替换与重启 |
| Preview | Gitee `releases/download/preview/appcast-<架构>.xml` | GitHub `releases/download/preview/appcast-<架构>.xml` | 各自 EdDSA 签名的同架构 ZIP；Sparkle 自动下载、验签、替换与重启 |

`<架构>` 是运行中的 slice：`arm64` 或 `x86_64`，Rosetta 下运行的 x86_64 slice 按 `arm64` 请求，否则这台 Mac 会被永久留在 Intel 包上。Info.plist 里四个 feed 键仍写 `appcast.xml` 基准地址，只有单架构安装改写文件名；Universal 安装按可执行文件里的 slice 数判定，仍请求 `appcast.xml`。`appcast.xml` 本身继续引用 Universal ZIP，服务对象就是 Universal 安装；0.1.6 及更早的版本没有内置 Sparkle，不会请求任何 appcast。

运行时设置的 `UpdateChannel` 同时决定自动检查与手动检查的目标，不受安装包初始 `ZislaDefaultUpdateChannel` 限制。每次检查都先读取 Gitee；Gitee appcast 检查或更新包下载失败时重试 GitHub 一次，GitHub 失败后不会再次回到 Gitee。切换通道时，Sparkle 将重置下一次自动检查周期；手动检查立即读取新 feed。Sparkle 只按 `sparkle:version` 升级，从不降级：Preview 用户切回 Release 后，会停在当前 preview 构建直到正式版的构建号超过它，所以 Preview 与 Release 共用的构建号必须始终全局递增。更新 ZIP 验签后会在退出或重启时安装。

`package-release.sh` 为每次构建生成 `appcast-gitee.xml` 和 `appcast-github.xml`，只引用本次那一套架构的 ZIP；`build-package.sh` 把三次构建的产物汇总成三对，Universal 那对保留原名并作为远端 `appcast.xml`，另两对上传为 `appcast-arm64.xml` 与 `appcast-x86_64.xml`。Release appcast 使用实际 `v${VERSION}` tag 的站点内下载 URL；版本 tag 禁止带 `release/` 等路径前缀，保持与 `SPARKLE_*_DOWNLOAD_URL_PREFIX` 的默认值一致。每个 Preview 仍发布至实际 prerelease tag，并将各自已签名的 appcast 覆盖上传到对应永久 `preview` tag；正式 Gitee appcast 则覆盖上传到永久 `update-release`。绝不可让某站 appcast 引用另一站的 ZIP，也不可让某架构 appcast 引用另一架构的 ZIP。
