# 内置第三方依赖

[English](README.md) | **简体中文**

`Sparkle.xcframework` 从官方 Sparkle 2.10.0 二进制发布包中原样提取：

- 来源：`https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0`
- 发布文件：`Sparkle-for-Swift-Package-Manager.zip`
- SHA-256：`17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959`
- 许可证：MIT

将 XCFramework 纳入仓库，是因为部分 macOS 代理配置下，SwiftPM 的 Git 拉取和构建依赖下载不够稳定。更新前必须核对 Sparkle 对应 tag 的 `Package.swift` 中公布的源压缩包校验值。

`MediaRemoteAdapter.framework` 使用 MediaRemote Adapter 0.7.6 源码构建，未作修改：

- 来源：`https://github.com/ungive/mediaremote-adapter/releases/tag/v0.7.6`
- Commit：`3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`
- 许可证：BSD-3-Clause，副本位于 `Resources/MediaRemoteAdapter/LICENSE`

将此辅助组件纳入仓库，使打包后的应用能在 macOS 15.4 及更新版本上读取系统“正在播放”会话，无需在使用时下载依赖。

`SkyLightWindow` 来自上游 1.0.0 源码快照，源代码未作修改：

- 来源：`https://github.com/Lakr233/SkyLightWindow`
- 版本：`1.0.0`
- Commit：`b7bd99f62a0673a99bed4bfd31098ca1dcdd10eb`
- 许可证：MIT，副本位于 `SkyLightWindow/LICENSE`
- 本地文档调整：中英文 README 切换入口，以及指向固定上游快照的预览图链接。

该包通过本地路径引用，正常构建时 SwiftPM 不会从网络拉取。更新时，手动将 `SkyLightWindow` 替换为经过验证的上游快照，保留许可证，并更新上述版本与 commit 记录。

`zstd.swift` 来自固定的上游 1.0.2 源码快照：

- 来源：`https://github.com/awxkee/zstd.swift`
- 版本：`1.0.2`
- Commit：`475fe3175c1aacccf9f420add35bf55e69936936`
- 许可证：CC0，副本位于 `zstd.swift/LICENSE.md`
- 内置二进制：上游 `libzstd.xcframework`，包含 iOS、Mac Catalyst、模拟器及 macOS Universal 架构。
- 本地补丁：参照 Zstandard 流式解压示例的流结束检查，`ZStd.decompress(src:dst:)` 在输入于帧内截断时抛出错误，不再返回不完整的输出。更新快照后需重新应用此补丁。
- 本地文档调整：中英文 README 切换入口，以及与内置 API 一致的使用示例。

该包通过本地路径引用，正常构建时 SwiftPM 不会从网络拉取。更新时，将 `zstd.swift` 替换为经过验证的上游快照，保留许可证与二进制架构，并更新上述版本与 commit 记录。内置 Zstandard 库继续使用 `Resources/ThirdPartyLicenses/Zstandard-LICENSE.txt` 中的许可证。
