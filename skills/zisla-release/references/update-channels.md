# zisla 双通道更新策略

## 通道地址

| 用户选择 | Sparkle feed | 发布物 |
| --- | --- | --- |
| Release | `releases/latest/download/appcast.xml` | 最新非 prerelease 的 GitHub Release |
| Preview | `releases/download/preview/appcast.xml` | `preview` relay prerelease 中的最新 appcast |

客户端将安装包的 `ZislaDefaultUpdateChannel` 作为自动更新来源：Release 包自动跟踪 Release，Preview 包自动跟踪 Preview。设置中保存的 `UpdateChannel` 仅是手动检查目标；用户主动点击检查时可选择另一通道，检查完成后自动更新仍回到安装包所属通道。两个 feed 都由同一个 Sparkle EdDSA 私钥签名。

## 版本序列

给每次构建分配全局严格递增的 `BUILD_NUMBER`。例如：

```text
v0.1.1-preview.1  -> 2
v0.1.1-preview.2  -> 3
v0.1.1             -> 4
v0.1.2-preview.1  -> 5
```

这样，Release 到 Preview、Preview 到 Preview、Release 到 Release，以及 Preview 到后续正式 Release，都能走同一条 Sparkle 安装逻辑。设置页只选择 feed，不绕过 Sparkle 的版本保护。

## 真实降级的限制

不要把“切换到 Release 通道”理解为 Sparkle 可以安装任意较旧版本。Sparkle 和 macOS 安装器会拒绝较低 `CFBundleVersion`，即使 appcast 与包签名正确。

需要从较新的 Preview 回退到历史 Release 时，下载该 Release 的 DMG，退出 zisla，手动替换 `/Applications/zisla.app`，并重新完成 Gatekeeper 的首次打开步骤。不要用自定义版本比较器绕过该保护。

要让 Preview 用户自动进入最新 Release，先发布一个具有更高全局 `BUILD_NUMBER` 的正式 Release；其 appcast 就会被 Release 通道选中。要让 Release 用户进入 Preview，发布一个具有更高 `BUILD_NUMBER` 的 Preview 并更新 `preview` relay feed。
