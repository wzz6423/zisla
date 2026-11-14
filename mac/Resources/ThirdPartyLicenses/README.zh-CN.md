# 第三方声明

[English](README.md) | **简体中文**

Zed token 用量解码使用 zstd.swift v1.0.2 和 Zstandard：

https://github.com/awxkee/zstd.swift
https://github.com/facebook/zstd

zstd.swift 封装采用 CC0 许可证；Zstandard 采用 BSD 3-Clause 许可证。详见本目录的 `Zstandard-LICENSE.txt`。

Apple 移动设备电量读取器改编自 MacTools，使用以下 commit：

`cfac26ade8e88ee967cf8ed300211d0498079336`

https://github.com/ggbond268/MacTools

Copyright 2026 MacTools contributors. 采用 Apache License 2.0，详见本目录的 `MacTools-LICENSE.txt`。

组合菜单栏图标的几何定义、绘制路径、状态映射、外观选项及蓝牙音频绘制改编自：

https://github.com/lingyired/status-trio

固定 revision：`2b0571a51c70fab0f1176db1eb0c32a8d7f2b4ad`。
原始文件位于 `Sources/StatusTrioCore`，包括
`UI/Icon/StatusIconGeometry.swift`、`UI/Icon/StatusIconRenderer.swift`、
`UI/StatusBarController.swift`、`Models/StatusMappings.swift`、
`Models/RingStrokeStyle.swift`、`Models/BatteryIconOptions.swift`、
`Models/VolumeIconOptions.swift`、`Models/ConnectionIconOptions.swift`、
`Models/StatusSnapshot.swift`、`Models/MenuBarStatus.swift` 和
`Models/BluetoothAudioIconOptions.swift`。

几何定义直接保留上游路径和坐标；新增的绘制计算用于设置电池顶部开口的尺寸。渲染器复用上游电池和音量描边及 SF Symbol 绘制代码。

本地快照重命名了类型，接入 zisla 的电池和系统遥测快照，优先显示低电量模式颜色，将缺失读数视为不可用，并保留电池、Wi-Fi、蓝牙音频替换和底部菜单栏绘制路径。蓝牙设备身份和电量数据来自 zisla 现有的音频输出服务。电池环显示电脑电量；连接时短暂显示白色耳机图标。菜单栏沿用上游的正方形画布、统一绘制变换及 AppKit 可变宽度状态项。顶部区域保留 zisla 的闪电与百分比组合布局，增加环形间距，并将放大的百分比和闪电图形一起居中。
配件电量仍只显示在现有连接通知中。不包含 Dock 渲染、充电动画、网络管理、任意蓝牙设备固定及上游应用界面。构建和绘制这些图标不需要远端依赖。

Copyright 2026 lingyired. 采用 Apache License 2.0，详见本目录的 `MenuBarIcon-LICENSE.txt` 和 `MenuBarIcon-NOTICE.txt`。

屏幕开合角度读取器和合盖纵深效果改编自 Mac Duo，使用以下 commit：

`88cb939b6f286487887b32e7c8f529604d340c6c`

https://github.com/sumimakito/Mac-Duo

Copyright 2026 Makito. 采用 Apache License 2.0，详见本目录的 `MacDuo-LICENSE.txt`。

内置 Emoji 别名目录由 Unicode CLDR 48.2 和 Unicode Emoji 17.0 数据生成：

https://github.com/unicode-org/cldr
https://github.com/unicode-org/cldr-json

Copyright 1991-2026 Unicode, Inc. 采用 Unicode License V3，详见本目录的 `Unicode-CLDR-LICENSE.txt`。

原生录屏工作室参考了 DogSC 中的采集时钟、暂停处理、非破坏性编辑和渲染技术：

https://github.com/laogou717/dogsc

固定 revision：`567fd6ed3bf113227dcf3e815f87ce60f0b69497`。
Copyright (c) 2026 神烦老狗. 采用 MIT 许可证，详见本目录的 `DogSC-LICENSE.txt`。

缩放插值、字幕分组、源时间编辑计划和 AI 编辑工作流也参考了 OpenScreen：

https://github.com/getopenscreen/openscreen

固定 revision：`d8bf2d8138cc2ce2c6542549853260f716cb8fb6`。
相关源文件包括 `src/lib/captioning/annotationsFromCaptions.ts`、
`src/lib/ai-edition/captions/cues.ts` 和 `electron/ai-edition/agent-tools.ts`。
Copyright (c) 2025 Siddharth Vaddem and (c) 2025-2026 OpenScreen contributors.
采用 MIT 许可证，详见本目录的 `OpenScreen-LICENSE.txt`。

zisla 使用自身的项目模型和现有 AI 设置，在 Swift 中实现这些工作流。未内置上游应用、Electron 运行时或远端构建依赖。

Cursor 账户用量、Muse Code 用量和凭据，以及 Chromium Safe Storage 解码改编自 CodexBar：

https://github.com/steipete/CodexBar

固定 revision：`d253dd1137242889804326a89972dfa21cda4722`。
相关源文件为 `CursorAppAuth.swift`、`CursorUsageEventsFetcher.swift`、
`CursorStatusProbe+UsageSummary.swift`、`MuseLocalUsageReader.swift`、
`MuseCredentials.swift`、`muse.ts` provider 插件、`ChromiumSafeStorage.swift` 和
`KeychainAccessPreflight.swift`。
Copyright (c) 2026 Peter Steinberger. 采用 MIT 许可证，详见本目录的 `CodexBar-LICENSE.txt`。

Cursor SQLite 元数据选择遵循 chat-stasher 的 Cursor 数据源实现：

https://github.com/dimpurr/chat-stasher

固定 revision：`9586c5518398d43b34cc73af70b237324d953d39`。
相关源文件为 `docs/sources/cursor.md` 和 `crates/chat-stasher/src/activity.rs`。
采用 Apache License 2.0，详见本目录的 `ChatStasher-LICENSE.txt`。

这些改编保留了原生 macOS 元数据和账户额度读取，并使用 zisla 现有的只读 SQLite、增量 JSONL 读取器、用量仓库和监控器。未内置上游界面、浏览器 cookie 扫描、账单变更、对话导出和运行时。读取 Keychain 前必须通过非交互式访问检查。未引入远端构建依赖。

原生 AI 账户余额凭据和额度解析还使用了 CodexBar 的 revision
`7447bc77c2497323d9c41e40164ce705533493c8`，包括 Claude、Codex、Copilot、Gemini、Kimi、Cursor、Zed 和 Muse 的额度数据源。同样适用 `CodexBar-LICENSE.txt` 中的 MIT 许可证。

额外的账户额度数据结构和端点映射改编自：

https://github.com/Javis603/token-monitor

固定 revision：`235a77c3fd3f63926a8fc50e879ada5a80029275`。
相关源文件为 `src/shared/providers/{codex,copilot,grok,kimi,cursor,qoder,trae,zcode,zed,workbuddy,opencode,muse}`。
采用 MIT 许可证，详见本目录的 `TokenMonitor-LICENSE.txt`。
zisla 原生实现这些映射，不包含浏览器凭据扫描、上游界面、自动登录或远端构建依赖。
