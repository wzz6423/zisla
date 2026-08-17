# zisla 双通道检查策略

| 用户选择 | 查询方式 | 发布物 |
| --- | --- | --- |
| Release | GitHub/Gitee 最新正式 Release API | 最新非 prerelease 的 DMG |
| Preview | GitHub/Gitee Release 列表 API | 版本号最高的 prerelease DMG |

自动检查始终使用安装包的 `ZislaDefaultUpdateChannel`；设置中的 `UpdateChannel` 只决定手动检查的目标。自动下载开启时，发现新版本后将 DMG 保存到用户的默认下载目录；不会打开、安装、替换或重启应用。

版本以 tag 的语义版本比较，支持 `release/v1.2.3` 形式。用户可以检查不同通道，但所有更新都需要退出 zisla 后手动安装 DMG，因此不存在自动降级或自动跨通道替换。
