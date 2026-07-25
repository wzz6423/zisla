# 系统监控与清理竞品调研

> 调研日期：2026-07-23。目标是为 zisla 的 CPU、GPU、磁盘清理、网络、风扇和内存功能划定可发布的实现边界。Stats 源码固定在 [5d6f3d2](https://github.com/exelban/stats/tree/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d)，另参考 [AppCleaner](https://freemacsoft.net/appcleaner/) 官方说明和 Apple 官方文档。这里的“可用”指不依赖私有 API、管理员权限或绕过用户授权。

## 结论先行

1. **CPU、内存、磁盘、网络速率、主接口私有 IP 和 CPU/网络波形图**均可用公开接口安全落地；波形只是本进程维护的有限环形样本，没有额外系统权限。
2. **公网 IP 不是 macOS 可本地推导的信息**。Stats 也通过外部 HTTPS 服务获取；zisla 应将其设为默认关闭的显式开关，说明供应商与刷新时间，并在关闭时绝不发出请求。
3. **Stats 的 GPU 利用率不是公开 API 实现**：它读取未文档化的 `IOAccelerator` 注册表 `PerformanceStatistics` 键，并自行声明 `IOReport*` 符号。可以研究 UI 与采样节奏，不能将该取数路径作为 zisla 的稳定能力或 Mac App Store 路径。
4. **风扇 RPM/控制同理不可照抄**。Stats 直接访问未文档化的 `AppleSMC` 键；其风扇控制另安装需管理员权限的特权 helper，且项目已标注为 legacy/not maintained。zisla 应继续显示“此机型不支持公开读取”，不要做伪造数值或隐藏权限升级。
5. **Stats 是监控产品而非内存清理器**。其 RAM 模块读取 VM 统计和压力，不包含“释放其他应用内存”的实现。zisla 的“内存清理”应限于自身缓存，产品文案应改为“释放 zisla 缓存”，不能承诺系统或其他 App 的可用内存增加。
6. **AppCleaner 的公开承诺是“拖入应用，找出相关文件，允许用户删除”**，其匹配规则不是开源可审计实现。zisla 可借鉴“先列证据、由用户选择、可恢复删除”的交互，不应声称照抄其不可见规则，更不能把名称模糊匹配的结果自动选中。

## Stats 的真实实现与可借鉴部分

### CPU 与内存

Stats 的 CPU reader 用 `host_processor_info`/`host_statistics` 两次采样后的 tick 差值计算总占用、用户占用和系统占用，并保留逐核心数据；这是标准 Mach 统计思路。[源码：CPU readers](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/Modules/CPU/readers.swift) Apple 公开的 [host_processor_info](https://developer.apple.com/documentation/kernel/host_processor_info) 和 [host_statistics](https://developer.apple.com/documentation/kernel/host_statistics) 是 zisla 可采用的基础。

Stats 的 RAM reader 使用 `host_statistics64(HOST_VM_INFO64)`、`host_info(HOST_BASIC_INFO)`、`sysctlbyname("kern.memorystatus_vm_pressure_level")` 与 `sysctlbyname("vm.swapusage")` 构造活跃、非活跃、压缩、可清除、swap 和压力视图。[源码：RAM readers](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/Modules/RAM/readers.swift) 这说明“监测内存压力”是可信且可实现的；源码中没有全局内存回收或结束别的进程的动作。

**zisla 应采用：**

- 以 CPU user/system/idle tick 差值和 VM 压力为数据源；第一帧标为“正在建立基线”，不要展示由零基线推得的假峰值。
- “清理内存”仅执行本进程已知可释放项，例如 `URLCache.shared.removeAllCachedResponses()` 与可归还的本进程 allocator 页；结果显示“已请求 zisla 归还 X”，不要称作“释放系统内存 X”。
- 不调用 `purge`、不通过私有 `memorystatus` 接口干预别的进程、不以杀进程伪装内存清理。这些做法会破坏用户工作状态，也不等价于 macOS 的内存管理。

### CPU、GPU 与网络波形

Stats 的 CPU popup 创建长度可配的 `LineChartView`，每次 CPU 采样只追加一个总占用样本；GPU popup 的做法相同。[CPU popup](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/Modules/CPU/popup.swift) [GPU popup](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/Modules/GPU/popup.swift) 其通用折线组件固定点数、以时间顺序连线，并支持固定/动态比例尺和断点。[LineChart](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/Kit/Widgets/LineChart.swift)

网络图则维护上行和下行两条序列，历史长度、动态/固定比例尺和颜色均可配置。[Network popup](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/Modules/Net/popup.swift)

**可安全复用的是交互模型，不是源码复制：**

- `MetricHistory` 维护 CPU、网络下行和网络上行的三个定长 ring buffer；推荐 1 秒采样、120 点历史，切换模块或窗口不可见时降频/暂停。
- CPU 与 GPU 各用独立曲线。GPU 没有受支持数据时保留曲线槽位但显示“不支持此 Mac”，不要把 CPU 曲线或帧率冒充 GPU 利用率。
- 网络双曲线应有固定高度和固定点数，纵轴采用“最近窗口最大值向上取整”的动态尺度，或者让用户切到固定尺度；速率为零时仍追加零，断网/读取失败才追加 gap。

### 网络、私有 IP 与公网 IP

Stats 先从 `State:/Network/Global/IPv4` 的 `PrimaryInterface` 选择主接口，再用 `getifaddrs` 读接口状态和 `if_data` 字节计数；本地 IPv4/IPv6 则从 `AF_INET`/`AF_INET6` 地址用 `getnameinfo(..., NI_NUMERICHOST)` 格式化。[Stats 网络 reader](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/Modules/Net/readers.swift) 这是“主接口优先、明确排除 loopback/无关接口”的关键，优于遍历到第一个私网地址就返回。

Stats 还把本地 IP 和公网 IPv4/IPv6 分开展示，并允许用户关闭公网 IP。[Stats 网络 popup](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/Modules/Net/popup.swift) 其公网地址是用 `curl -4/-6` 请求项目服务器取得；README 也明确说明外部请求是公网 IP 所必需的。[Stats README](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/README.md)

**zisla 推荐实现：**

- 用 [NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor) 监听路径切换、可用状态和接口类型；再用 SystemConfiguration 的动态存储选取当前主接口，用 `getifaddrs` 读取该接口的 IPv4/IPv6 和字节计数。Network 框架负责“路径变化”，不替代地址枚举。
- UI 同时显示“私有 IPv4/IPv6”和“公网 IPv4/IPv6”；若 VPN 是主路径，明确显示接口名或 VPN 标签，避免把 Wi-Fi 地址误标为当前出口地址。
- 公网地址请求使用 `URLSession`，设 5 秒超时、失败退避、手动刷新和最长 15 分钟缓存；只在用户开启后调用。服务端会看到用户的源 IP，因此在设置里写明端点/隐私影响。若以 App Sandbox 分发，还需要 [outgoing network connections entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)。
- 不为公网 IP 启动 `curl`/shell。Stats 的实现是竞品事实，不是 zisla 的实现建议。

### GPU：Stats 为什么能显示，但不应照抄

Stats 在 `IOAccelerator`/`IOGPU`/`AGXAccelerator` 里读取 `PerformanceStatistics` 字典中的 `Device Utilization %`、`GPU Activity(%)`、`Renderer Utilization %` 等字符串键。[GPU reader](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/Modules/GPU/reader.swift) 这些注册表属性和键名没有 Apple 的公开稳定契约；随硬件、驱动和 macOS 版本改变，缺失时源码也直接放弃读取。

更明显的是，Stats 为 `IOReportCopyChannelsInGroup`、`IOReportCreateSubscription` 等符号手写 bridge 声明，而不是引入公开 SDK header。[GPU bridge](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/Modules/GPU/bridge.h) 这类 `IOReport` 使用不应进入 zisla 的发布代码。

Apple 公开的 [MTLDevice](https://developer.apple.com/documentation/metal/mtldevice) 可枚举 GPU、检查能力、创建 zisla 自己的 Metal 资源和对 zisla 提交的命令采样；它没有承诺提供“全系统 GPU 利用率”。[CGDisplayStream](https://developer.apple.com/documentation/coregraphics/cgdisplaystream) 传输的是显示内容，也不是 GPU 占用计数器，不能用屏幕帧变化替代 GPU load。

**发布决策：**

| 需求 | 结论 | 原因 |
| --- | --- | --- |
| GPU 名称、能力、zisla 自身 Metal 资源 | 可用 | `MTLDevice` 是公开 Metal 接口。 |
| 全系统 GPU 利用率/渲染器/温度/频率 | 不作为公开稳定功能 | Stats 依赖未文档化 IORegistry/IOReport 数据。 |
| GPU 波形 | 仅在有受支持采样源时显示 | 曲线本身安全，数据源不应伪造。 |

### 风扇：读取与控制都不应作为 zisla 基线功能

Stats 的 SMC 程序用 `IOServiceMatching("AppleSMC")` 打开服务并按 `FNum`、`F0Ac`、`F0Tg`、`F0Md`/`F0md` 等键读写风扇状态。[SMC implementation](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/SMC/smc.swift) 这些服务和键并非 Apple 文档化的硬件监控 API，并且不同 Intel/Apple Silicon 机型的键与语义不同。

Stats 的 README 明确写着 fan control 是 legacy/not maintained，卸载 SMC helper 需要管理员权限；其 helper 位于 `/Library/LaunchDaemons` 与 `/Library/PrivilegedHelperTools`。[Stats README](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/README.md) [helper implementation](https://github.com/exelban/stats/blob/5d6f3d27025d04436dcd2413d98e4f5f33d5ec8d/SMC/Helper/main.swift) helper 还会对调用者签名做校验，这说明这不是普通 App 内一个按钮可以安全替代的能力。

**zisla 决策：**

- 不读取或控制 AppleSMC；不安装特权 helper；不请求管理员权限。
- 展示“风扇：此 Mac 未提供公开传感器接口”，并保留不可用状态而非 `0 RPM`。
- 若将来业务明确接受“非 App Store、机型差异、管理员 helper、SMC 风险”，应单独立项并进行签名校验、权限、故障恢复和硬件回归；它不能混入本次监控功能。

## AppCleaner 借鉴：残留扫描应是证据驱动的卸载辅助

AppCleaner 的官方说明只承诺：应用安装时会把文件分布在系统中；用户把应用拖入窗口后，它找出 related files，用户点击删除。[AppCleaner 官方页](https://freemacsoft.net/appcleaner/) AppCleaner 的匹配源码和评分规则没有作为公开一方源码提供，因此以下是可审计的 zisla 设计，不冒充为其内部算法。

### 两阶段扫描与置信度

输入应是用户明确选择的 `.app` URL。先解析 `Contents/Info.plist` 的 `CFBundleIdentifier`、显示名和可执行文件路径，解析符号链接后再建立候选项。扫描只读、逐项计算分配大小，并在结果中给出“为何匹配”。

| 置信度 | 允许的候选位置/条件 | 默认选择 |
| --- | --- | --- |
| 高 | `~/Library/Preferences/<bundle-id>.plist`、`~/Library/Preferences/ByHost/<bundle-id>.*`、`~/Library/Saved Application State/<bundle-id>.savedState`、`~/Library/Caches/<bundle-id>`、`~/Library/Logs/<bundle-id>`、`~/Library/WebKit/<bundle-id>` | 可预选，但仍可取消 |
| 高 | `~/Library/Application Support/<bundle-id>`、`~/Library/Containers/<bundle-id>`，且路径精确等于 bundle ID | 可预选；Sandbox 访问失败则仅报告“无权限” |
| 高 | `~/Library/LaunchAgents/*.plist` 的 `Label` 精确等于 bundle ID，或 `Program`/`ProgramArguments` 精确包含已解析的 app 可执行文件 | 不直接删除；先展示 plist 内容摘要与影响 |
| 中 | 以上受控目录内与显示名完整相等的目录/文件 | 默认不选，要求用户确认 |
| 低/禁止 | 只做子串名称匹配、`/Library`、`/System`、`/private/var`、其他 App Container、共享组容器、浏览器 profile、钥匙串、用户文档 | 不扫描或只作为手动定位，不加入自动清理 |

`group.*` 容器不能仅凭主 App bundle ID 推导：共享组可能被多 App 共同使用，删除会损坏仍在使用的组件。匹配 LaunchAgent 时必须用 `PropertyListSerialization` 解析 plist，不用文本 grep；程序路径必须归一化并与已选 App 的实际可执行文件精确比较。

### 删除和权限边界

- 扫描到删除之间要重新 canonicalize 路径、禁止符号链接逃逸、再次验证它仍位于允许根目录并且 bundle ID/可执行文件证据不变。
- 展示名称、完整路径、类别、分配大小和匹配理由；所有候选都可取消，失败项目逐项保留错误原因。
- 删除一律调用 [FileManager.trashItem](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)) 或 [NSWorkspace.recycle](https://developer.apple.com/documentation/appkit/nsworkspace/recycle(_:completionhandler:)) 移入废纸篓，不直接 `removeItem`，不报告“已释放”直到移动成功。大小应优先使用 [totalFileAllocatedSizeKey](https://developer.apple.com/documentation/foundation/urlresourcekey/totalfileallocatedsizekey) 而不是逻辑文件大小。
- 若 zisla 未来启用 App Sandbox，Apple 要求经 entitlement 限定资源访问；App Store 分发必须启用 Sandbox，文件范围需要用户选择或对应 entitlement。[App Sandbox](https://developer.apple.com/documentation/security/app_sandbox) 因此不能承诺无条件遍历 `~/Library/Containers` 或所有用户目录。

## “全局脏数据”应该扩大扫描，不扩大删除权

现有“缓存/日志”之外，用户确实会期待看到废纸篓、崩溃报告和开发工具缓存；但“可扫描”不等于“可默认删除”。建议按风险分层：

| 类别 | 建议 | 风险控制 |
| --- | --- | --- |
| `~/Library/Caches`、`~/Library/Logs`、用户废纸篓 | 一期扫描直接子项，按大小排序 | 移入废纸篓；不递归跟随 symlink；用户逐项选择 |
| `~/Library/Application Support/CrashReporter` | 可列为崩溃报告 | 显示日期；默认不选最近 7 天，避免丢失排障证据 |
| Xcode `DerivedData`、CoreSimulator 缓存 | 单独“开发缓存”类别 | 明确会触发下次重建/下载；只处理精确目录，不碰 Archives、源代码、模拟器数据 |
| 已卸载应用残留 | 按上一节 bundle ID 证据扫描 | 高置信度才预选；中低置信度不预选 |
| Downloads 中的 `.dmg`/`.zip`、iOS DeviceSupport、浏览器缓存 | 只做“可审阅的大文件”或后续专项 | 这些可能是用户文件、离线内容或正在使用的数据，不能按“垃圾”自动清理 |
| `/System`、`/Library`、`/private/var/folders`、Time Machine 本地快照、系统更新缓存 | 排除 | 可能需要管理员权限，或由 macOS 管理；不以清理器名义绕过系统策略 |

## 对当前 zisla 实现的直接影响

以下是调研得出的代码审计结论，供后续实现任务使用；本调研**不修改代码**。

1. 当前 `SystemMonitorService.sampleGPU()` 也读取 `IOAccelerator` 的 `PerformanceStatistics`。它与 Stats 的未文档化路径相同，不能再在 UI 或文档中称为“公开 API GPU 监控”。应从默认功能移除，或明确标为实验性、无保证且不作为发布能力。
2. 当前公网 IP provider 会自动请求 `api64.ipify.org`。应新增用户可见的默认关闭开关、服务说明、刷新按钮、超时/退避及 IPv4/IPv6 分别呈现；Stats 的公网 IP 开关是可借鉴的隐私基线。
3. 当前私有 IPv4 通过遍历接口取到第一个地址。应先按 SystemConfiguration/NWPathMonitor 确定主接口，再读取该接口地址；同时补 IPv6 和 VPN/接口标识。
4. 当前历史对象已具备 CPU/GPU 样本，但缺少上下行网络序列。应以同一时间基准维护固定长度 CPU、网络下载和网络上传环形缓冲区，并让 GPU 只有在受支持数据存在时才追加。
5. 当前缓存、日志、废纸篓、开发缓存和崩溃报告可保留为基础清理类别；下一步增加的是“按 bundle ID 证据扫描的应用残留”，不是对整个 `~/Library/Application Support` 做名称模糊清理。
6. 当前“释放内存”仅清 zisla 自身 URL cache/allocator 页，这是正确的权限边界；应调整按钮和结果文字，使其不被理解为 Mac Cleaners 常见但不可信的全局 RAM 回收。

## 建议验收标准

- CPU 和网络波形连续运行 10 分钟，样本数始终不超过上限，切换网络后 2 秒内更新主接口，断网时曲线显式 gap 或零值而非沿用旧速率。
- 私有 IPv4/IPv6、接口名和公网 IP 三者可分别复制；关闭公网 IP 后以网络抓包/日志确认零外部请求。
- GPU/风扇在没有受支持数据的设备上显示不可用，不出现 `0%` 或 `0 RPM`；代码不链接/声明 `IOReport*`，不读取 `PerformanceStatistics`/`AppleSMC`。
- 选择未安装 App 的残留扫描时，每条候选都有 bundle ID、精确路径或 plist 证据；名称相似的文件未预选；所有删除进入废纸篓并可在 Finder 恢复。
- 任何无权限目录、解析失败 plist、符号链接或扫描期间变化的路径都被跳过并显示原因，绝不升级权限或退化为递归删除。
