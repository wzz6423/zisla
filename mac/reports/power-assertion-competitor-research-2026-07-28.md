# macOS 保持亮屏、空闲防休眠与合盖防休眠调研

调研日期：2026-07-28  
范围：仅调查实现路径和可验证限制；未修改产品代码、配置或测试。

## 结论摘要

这三个能力不是同一件事，不能共用一个“防休眠”承诺：

| 能力 | 可用的稳定公开机制 | 能否覆盖合盖 | 关键限制 |
| --- | --- | --- | --- |
| 保持亮屏 | `kIOPMAssertPreventUserIdleDisplaySleep` 或 `caffeinate -d` | 否 | 仅阻止**用户闲置**造成的显示器关闭；不会重新点亮已关闭的显示器。 |
| 防止空闲系统休眠 | `kIOPMAssertPreventUserIdleSystemSleep` 或 `caffeinate -i` | 否 | 显示器仍可关闭；合盖、低电量、用户选“睡眠”等仍可使系统睡眠。 |
| 合盖后保持运行 | 没有等价的稳定公开 assertion；竞品使用 RootDomain 私有 selector 或 `pmset -a disablesleep 1` | 是，取决于系统和硬件 | 系统级、高热/耗电风险；需要专门的安全、恢复和兼容性设计。 |

因此，普通 IOKit assertion 修复的是“保持亮屏”和“防止**空闲**休眠”；它不能兑现“合盖不休眠”。若产品继续提供后者，必须把它实现为独立的高级能力，而不是把普通 assertion 重新命名。

## State 2.1.8 的实际实现

本机已安装的 `/Applications/State.app`（bundle id `com.better365.menubar`、版本 `2.1.8`、arm64 可执行文件 SHA-256 `271e01b007eca111c4345e3717baf95ab4faa77d1a641b0bcdeb418f669961ba`）没有公开源码。以下结论来自该已签名二进制的静态检查，而非对源代码的臆测。

### “保持亮屏”

- State 导入 `IOPMAssertionCreateWithName` 和 `IOPMAssertionRelease`，二进制内含字符串 `PreventUserIdleDisplaySleep`。
- arm64 的 `keepScreenOn` 在 `0x10005cb98` 调用 `IOPMAssertionCreateWithName`，以 `0xff`（`kIOPMAssertionLevelOn`）创建 assertion，保存返回的 assertion id；`closeScreenOn` 在 `0x10005cbf8` 对该 id 调用 `IOPMAssertionRelease`。
- 这与 Apple 在 [`IOPMLib.h`](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h#L295-L314) 对 `kIOPMAssertPreventUserIdleDisplaySleep` 的定义一致：阻止因用户闲置而使显示器关闭；合盖或机器睡眠仍可使显示器关闭。

结论：State 的“保持亮屏”走的是正确的、公开的 display-idle assertion 路径。

### “合盖不休眠”

- State 的本地化字符串把该功能标为“合盖不休眠”/“Don't sleep when closed”。
- 它没有使用 `caffeinate`、`pmset` 或 `disablesleep` 字符串。反汇编显示 `setClamshellCausingSleep:` 在 `0x10005ca88` 先调用 `IOPMFindPowerManagement(MACH_PORT_NULL)`，再调用 `IOConnectCallScalarMethod(connection, 12, &(!flag), 1, NULL, NULL)`，最后关闭连接。
- Apple 开源 XNU 将 selector `12` 定义为 [`kPMSetClamshellSleepState`](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/IOKit/pwr_mgt/IOPMLibDefs.h#L42)。RootDomain user-client 对这个 selector 接收一个 scalar，并调用 [`setClamShellSleepDisable(value != 0, kClamshellSleepDisablePowerd)`](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/RootDomainUserClient.cpp#L388-L396)；处理分支见[同文件](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/RootDomainUserClient.cpp#L525-L529)。

结论：State 确实使用了能改变合盖睡眠状态的 RootDomain user-client 路径，并非错误地把 display/idle assertion 当作合盖支持。这个 selector 未出现在面向第三方的 `IOPMLib.h` 公共 assertion API 文档中；它虽然可从 Apple 开源内核源码核验，但不是可承诺跨 macOS 版本稳定的公开应用 API。当前静态检查也未证明 State 在崩溃、强制退出、低电量或高温时一定会复位该状态，因此不能把它的行为模型直接照搬到 Zisla。

## Apple 一手资料：公开 assertion 与 `caffeinate`

Apple 的 [`IOPMLib.h`](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h) 明确区分两类 public assertion：

- [`kIOPMAssertPreventUserIdleSystemSleep`](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h#L274-L292)：防止用户闲置导致的系统睡眠；显示器仍可关闭，而且文档明确列出合盖、Apple 菜单、低电量及其他原因仍可睡眠。
- [`kIOPMAssertPreventUserIdleDisplaySleep`](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h#L295-L314)：防止用户闲置导致的显示器关闭；合盖和系统睡眠仍有效；显示器已经关闭时并不会被该 assertion 点亮。
- [`IOPMAssertionCreateWithName`](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h#L757-L781) 不需要特殊权限，但必须检查返回值，仅在成功时保存 assertion id，并在结束时 release。

Apple 开源的 [`caffeinate(8)` 手册](https://github.com/apple-oss-distributions/PowerManagement/blob/main/caffeinate/caffeinate.8) 说明：

- `-d`：创建防显示器睡眠 assertion；
- `-i`：创建防系统**空闲**睡眠 assertion；
- `-s`：创建防系统睡眠 assertion，但只在交流电下有效；
- `-t`：超时自动释放；`-w pid`：目标进程退出时释放。

对应的 [Apple 源码](https://github.com/apple-oss-distributions/PowerManagement/blob/main/caffeinate/caffeinate.c#L52-L57) 将 `-i/-d/-s` 分别映射为 `PreventUserIdleSystemSleep`、`PreventUserIdleDisplaySleep`、`PreventSystemSleep`。注意 `PreventSystemSleep` 在当前 [`IOPMLib.h`](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h#L1014-L1023) 中标为已弃用且“不受任何 OS X release 支持”，不能作为新实现的依据。

## 竞品实现对比

| 产品 | 公开可核验实现 | 显示器/空闲休眠 | 合盖 | 限制与保护 |
| --- | --- | --- | --- | --- |
| KeepingYouAwake | 官方源码以 `NSTask` 包装 `/usr/bin/caffeinate` | 允许显示器休眠时 `-i`；否则 `-di` | 不支持 | README 明确限定为台式机和开盖笔记本。 |
| Amphetamine | 闭盖模式与普通 session 分开；官方 App Store 说明 Apple Silicon 需额外的 Power Protect 脚本/配置 | 官方声明可独立允许/阻止显示器睡眠 | 官方声明支持 | 实现源码未公开；不能据此断言具体使用哪个 API。官方帮助页面目前重定向到登录页。 |
| Owly | 普通模式使用 `IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep)`；强力模式执行 `sudo pmset -a disablesleep 1/0` | 普通模式防空闲系统休眠 | 仅强力模式 | 一次管理员授权、严格 sudoers 限制、启动和退出时复位。 |
| LiDDY | 普通模式同时持有 display/system idle assertion；闭盖由特权 LaunchDaemon 执行 `pmset -a disablesleep 1/0` | 两种 assertion 分层 | 特权 helper 模式 | 一次管理员授权、守护进程心跳超时复位、启动时清理陈旧状态。 |

### KeepingYouAwake

官方 README [明确](https://github.com/newmarcel/KeepingYouAwake/blob/06d02f56da76731ecd54b7279664eaa09d7bc26d/README.md#L15) 它只是 `caffeinate` 的包装器，并明确回答“合盖不支持”。其 [`KYASleepWakeTimer.m`](https://github.com/newmarcel/KeepingYouAwake/blob/06d02f56da76731ecd54b7279664eaa09d7bc26d/Packages/KYASleepWakeTimer/Sources/KYASleepWakeTimer/KYASleepWakeTimer.m#L95) 创建 `/usr/bin/caffeinate` task，使用 `-i` 或 `-di`，可附加 `-t`、`-w <自身 PID>`；停止时结束子进程。

这是一条低风险、公开、可观测的实现路线，但它明确不解决合盖。

### Amphetamine

Amphetamine 的[官方 App Store 页面](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12) 宣称 session 可分别控制 display sleep 与 built-in display closed 时的系统睡眠，也宣称低电量时自动结束 session。其当前版本说明称：Apple Silicon 的 Closed-Display Mode 使用单独下载的脚本和配置（Power Protect），早期脚本需要 Touch ID 或管理员密码。

其官方帮助文章 `Amphetamine & Closed-Display Mode` 在本次调研时返回登录重定向，无法获取正文；Amphetamine 未公开相关源码。因此本报告只记录其官方产品行为，不把其实现归因为 IOKit selector、`pmset` 或其他具体机制。

### Owly

[Owly 源码](https://github.com/Aarontaken/owly/blob/e0b704bd5c9a08585c3b277729c580cafaf1ffc9/src/main.swift#L434) 的普通“熄屏不睡”模式创建 `PreventUserIdleSystemSleep` assertion 并在结束时 release。它把合盖单列为强力模式，通过 [`sudo -n /usr/bin/pmset -a disablesleep 0|1`](https://github.com/Aarontaken/owly/blob/e0b704bd5c9a08585c3b277729c580cafaf1ffc9/src/main.swift#L635) 修改系统行为，并用仅允许这两条命令的 [sudoers 模板](https://github.com/Aarontaken/owly/blob/e0b704bd5c9a08585c3b277729c580cafaf1ffc9/resources/sudoers.template#L1) 限定权限。[README](https://github.com/Aarontaken/owly/blob/e0b704bd5c9a08585c3b277729c580cafaf1ffc9/README.md#L73) 明确说明普通 IOKit 模式不能防合盖；启动时清理遗留状态、退出时复位。

### LiDDY

[LiDDY 的 `PowerAssertions.swift`](https://github.com/docholypancake/LiDDY/blob/ff333a3ce560d6e137545eecf4c22f8a56962854/LiDDY/PowerAssertions.swift#L5) 同时管理 display 与 idle-system assertions。合盖另由特权 helper 的 [`PMSetController.swift`](https://github.com/docholypancake/LiDDY/blob/ff333a3ce560d6e137545eecf4c22f8a56962854/LiDDYHelper/PMSetController.swift#L3) 调用 `pmset -a disablesleep 1/0`。其 [README](https://github.com/docholypancake/LiDDY/blob/ff333a3ce560d6e137545eecf4c22f8a56962854/README.md#L32) 要求一次管理员密码和 macOS 14+；[helper](https://github.com/docholypancake/LiDDY/blob/ff333a3ce560d6e137545eecf4c22f8a56962854/LiDDYHelper/HelperService.swift#L93) 用心跳超时和启动清理避免系统停留在闭盖不睡状态。

## 对 Zisla 的实现建议

1. 保留两个层级清晰的公开能力：`保持亮屏` 使用 display-idle assertion，`防止空闲休眠` 使用 system-idle assertion；按钮文案和帮助文本必须说明它们不覆盖合盖、低电量和用户主动睡眠。
2. 若要恢复“合盖不休眠”这个承诺，不应复用现有 `PowerAssertionController`。它需要独立的高级功能、显式风险确认、会话时限、交流电/温度/电量保护、进程崩溃和应用退出后的复位策略，以及针对目标 macOS/硬件版本的实机验证。
3. 不建议直接采用 State 的 selector `12`：它是 Apple 内核源码中可见、但并非第三方稳定公开 API 的 RootDomain user-client 调用。选择它意味着接受系统升级、沙盒/App Store 审核和状态残留风险。
4. 同样不应把 `pmset disablesleep` 称为普通 app 的无风险实现：Apple 当前开源 [`pmset(1)` 手册](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.1) 未把 `disablesleep` 列为文档化设置，且该路径通常需要管理员权限。若采用，必须像 Owly/LiDDY 一样把权限收敛到固定命令，并可靠恢复原状态。

## 调研边界与残余不确定性

- State 没有公开源码，静态分析已能证明其 assertion 与 RootDomain selector 调用，但不能证明所有生命周期分支（崩溃、强制退出、低电量、高温）的复位行为。
- Apple 开源 XNU 说明 selector `12` 的名称和调用语义，但并不等于 Apple 向第三方承诺该私有接口的兼容性或审核可用性。
- Amphetamine 的官方 Closed-Display Mode 帮助正文不可访问，且没有可验证源码；报告未对其内部 API 作推断。
- 本任务没有编译、运行测试或创建二进制/临时产物；所有结论为只读源码、手册、App Store 元数据与本机 State 二进制静态检查所得。
