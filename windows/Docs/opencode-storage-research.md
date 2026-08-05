# OpenCode 本地存储调研（Windows 扫描器）

调研日期：2026-08-04。范围仅限 OpenCode 官方仓库 `anomalyco/opencode` 的公开源码与发布标签；当前分支快照为 [`dev` 的 `6c3299103ce1494b4b37f5727199ac9539130534`](https://github.com/anomalyco/opencode/commit/6c3299103ce1494b4b37f5727199ac9539130534)。未把社区文章、逆向结论或 macOS 现有实现当作事实依据。

## 结论

当前上游的主会话存储是 SQLite，不是逐会话 JSON 文件。`opencode.db` 因此不是应当只做“遗留兼容”的格式：当前 `dev` 与官方发布标签 `v1.18.12` 的数据库路径实现都仍会选择它。`storage/` 下的 JSON 文件服务依然存在，但源码将其用作迁移旧项目目录布局的兼容层。

Windows 扫描器应按下面的优先级实现：

1. 在 OpenCode 的数据根目录下只读发现 `opencode.db` 和 `opencode-*.db`；不递归扫描整个用户目录。
2. 对发现的 SQLite 数据库使用只读打开、短暂 busy timeout，并把 `-wal`/`-shm` 作为同一数据库的变化来源；绝不复制、移动、checkpoint 或写入数据库。
3. 仅在同一个数据根目录内兼容读取 `storage/` 的 JSON 布局；JSON 解析失败、正在写入或超出大小上限时跳过该项。
4. `OPENCODE_DB` 可把数据库改到任意绝对路径，扫描器不能安全地猜测这种位置；应保留显式配置路径入口，而不是扩大默认扫描范围。

## 一手来源与事实

| 事实 | 官方来源 | 对扫描器的影响 |
| --- | --- | --- |
| OpenCode 将数据根目录定义为 `path.join(xdgData, "opencode")`，锁定 `xdg-basedir@5.1.0`；该依赖的官方实现以 `os.homedir()/.local/share` 作为 `xdgData` 回退值。 | [Global.Path](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/core/src/global.ts#L10-L29)、[依赖版本](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/core/package.json#L126)、[`xdg-basedir@5.1.0` 官方源码](https://github.com/sindresorhus/xdg-basedir/blob/v5.1.0/index.js#L4-L16) | 默认 Windows 根为 `%USERPROFILE%\\.local\\share\\opencode`；若 OpenCode 进程拥有 `XDG_DATA_HOME`，则为 `<XDG_DATA_HOME>\\opencode`。不要把 `%APPDATA%` 或 `%LOCALAPPDATA%` 当作默认根。 |
| 数据库路径优先服从 `OPENCODE_DB`；相对值相对数据根解析，`:memory:` 没有可扫描文件。默认在 `latest`、`beta`、`prod` 或关闭 channel 数据库时为 `opencode.db`，否则为 `opencode-<channel>.db`。 | [Database.path()](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/core/src/database/database.ts#L43-L55)、[v1.18.12 同一实现](https://github.com/anomalyco/opencode/blob/v1.18.12/packages/core/src/database/database.ts) | 默认只枚举数据根目录第一层的这两类文件名。`OPENCODE_DB` 的任意绝对路径只能由用户设置或未来的官方发现接口提供。 |
| 上游以 WAL 模式运行 SQLite，并配置 busy timeout、被动 checkpoint、迁移。 | [Database 初始化](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/core/src/database/database.ts#L27-L33) | 读者必须只读打开主库，让 SQLite 自己合并可见 WAL；不得把 `-wal` 当成独立数据库、不得执行 checkpoint。锁定、损坏或 schema 不兼容时返回空增量/保留上一快照。 |
| `session` 表保存标题、更新时间、归档时间、模型和统计；`message` 表以 `session_id`、时间戳与 JSON `data` 保存历史投影；当前事件流另有 `session_message` 表。 | [Session/Message SQLite schema](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/core/src/session/sql.ts#L22-L138) | 最小查询取 `session.id`、`title`、`time_updated`、`time_archived`，再按存在的表读取最新 `session_message` 或 `message` 的必要元数据。不得导出 `part`、提示词文本、工具输出、目录路径或整个 `metadata`。 |
| 当前会话业务层依赖 `Database.node`；JSON `Storage` 代码的根则是 `Global.Path.data/storage`。 | [Session service](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/opencode/src/session/session.ts)、[Storage service](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/opencode/src/storage/storage.ts) | SQLite 是默认路径；`storage/` 只作为兼容读取路径，不能倒置为主数据源。 |
| JSON 存储键统一映射为 `<storage root>/<key...>.json`，迁移代码明确给出旧项目布局和迁移后的 session/message/part 文件布局。 | [Storage 迁移与文件命名](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/opencode/src/storage/storage.ts#L63-L325) | JSON 扫描只接受下文列出的固定相对路径，禁止通配读取任意 JSON。 |
| `busy`/`retry`/`idle` 状态保存于进程内 `Map`；任务结束时设为 `idle` 并删除该项。 | [Session 状态事件](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/schema/src/session-status-event.ts#L9-L49)、[SessionStatus](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/opencode/src/session/status.ts#L26-L48) | 不存在可靠的持久化“正在运行”字段。任何基于未完成消息与最近更新时间的结果都必须命名为“活跃推断”，不能声称读取到了官方运行状态。 |

## 扫描根与文件名

令 `dataRoot = <OpenCode 运行时的 xdgData>/opencode`。以当前锁定的 `xdg-basedir@5.1.0` 而言，Windows 未设置 `XDG_DATA_HOME` 时的默认根为 `%USERPROFILE%\\.local\\share\\opencode`；设置该变量时为 `<XDG_DATA_HOME>\\opencode`。代码仍应让 `dataRoot` 可注入：启动 OpenCode 的环境可以覆盖变量，Windows 真机阶段只需验证这一覆盖和路径可访问性。

### 1. 当前 SQLite 主路径

| 相对 `dataRoot` 的目标 | 读取规则 | 说明 |
| --- | --- | --- |
| `opencode.db` | 存在才以 SQLite 只读模式打开 | 主路径，适用于 `latest`、`beta`、`prod` 等情况。 |
| `opencode-*.db` | 只匹配数据根第一层，文件名白名单为 ASCII `A-Za-z0-9._-` channel 派生名 | 非默认 channel 的路径；同一用户可以并存多个 channel 数据库。 |
| `<OPENCODE_DB>` | 仅当用户显式提供且是本地普通文件时读取 | 上游允许绝对路径、相对 `dataRoot` 的文件名和 `:memory:`；后者不可扫描。 |

`OPENCODE_CONFIG_DIR` 只改变配置目录，不会在 [Global.Path 的实现](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/global.ts) 中替换 `dataRoot`，不应被误当成数据库根。

### 2. JSON 兼容路径

当前迁移逻辑展示了两套会在旧安装中存在的布局。它没有提供“这些文件仍是当前唯一写入格式”的证据，故两者均为低优先级、只读兼容项。

| 布局 | 固定可读取文件 | 用途 |
| --- | --- | --- |
| 迁移后 JSON 根 | `storage/session/<projectID>/<sessionID>.json` | 会话信息。 |
| 迁移后 JSON 根 | `storage/message/<sessionID>/<messageID>.json` | 消息元数据。 |
| 迁移后 JSON 根 | `storage/part/<messageID>/<partID>.json` | 不读内容；本功能不需要。 |
| 迁移后 JSON 根 | `storage/project/<projectID>.json`、`storage/session_diff/<sessionID>.json`、`storage/migration` | 不读内容；不写 migration marker。 |
| 更早的项目内布局 | `project/<legacyProjectID>/storage/session/info/<sessionID>.json` | 仅在需要覆盖尚未迁移的旧安装时兼容。 |
| 更早的项目内布局 | `project/<legacyProjectID>/storage/session/message/<sessionID>/<messageID>.json` | 仅取元数据。 |
| 更早的项目内布局 | `project/<legacyProjectID>/storage/session/part/<sessionID>/<messageID>/<partID>.json` | 不读内容。 |

这些路径均直接来自 [Storage migration.1](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/storage/storage.ts) 和 [Storage migration.2](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/storage/storage.ts)。扫描器不应主动触发上游迁移，也不应根据其 marker 改写文件。

## 最小元数据与状态推断

### SQLite

官方 schema 确定可稳定作为降级读取输入的列为：

| 对象 | 只读取字段 | 用途 |
| --- | --- | --- |
| `session` | `id`、`title`、`time_updated`、`time_archived` | 唯一标识、展示标题、排序/过期、排除归档会话。 |
| `session_message`（存在时优先） | `id`、`session_id`、`type`、`seq`、`time_created`、`time_updated`、`data` | 当前事件流的最新活动时间；只解析能识别的状态元数据。 |
| `message`（兼容投影） | `id`、`session_id`、`time_created`、`time_updated`、`data` | 选择每会话最新消息；`data` 只解析角色、时间完成标记、模型标识和错误标记。 |

`session.model`、`session.metadata`、`message.data` 和 `session_message.data` 都是 JSON 列。由于 schema 与迁移会演进，扫描器必须先确认 `session` 与可用的事件/消息表及所需列存在，再使用参数化只读查询；可选 JSON key 缺失不是错误。不要依赖 `SELECT *`，也不要把某一版的 `finish` 值当作跨版本协议。

旧式消息 schema 的角色为 `user` / `assistant`；assistant 可包含 `time.completed`、`error`、`finish`，工具 part 还可出现 `pending`、`running`、`completed`、`error`。这些均只能作为辅助信号，见 [v1 消息 schema](https://github.com/anomalyco/opencode/blob/6c3299103ce1494b4b37f5727199ac9539130534/packages/schema/src/v1/session.ts#L259-L491)。JSON 文件、`message.data` 或 `session_message.data` 若不符合可识别形状，应被当作未知版本而不是解析失败后访问正文。

推荐的 Zisla 本地推断（不是 OpenCode 状态协议）：

1. 排除 `time_archived` 非空的会话。
2. 选择该会话 `time_updated` 最大的消息；相同时间以稳定的 `id` 排序打破平局。
3. 会话最近更新且最新消息没有可识别的完成时间时，标为“可能活跃”。有可识别错误时可标为失败/未知，但不能据此重写数据。
4. 用户消息、assistant 消息、缺失字段或不认识的 JSON 版本都不要强行归类为“运行中”；展示层应允许“等待/未知”。

### JSON

会话文件可按 [Session.Info](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/session/session.ts) 只解析：

- `id`、`title`；
- `time.created`、`time.updated`、可选 `time.archived`；
- 可选 `model.id`、`model.providerID`。

消息文件只解析上述最小消息字段。特别是 `parts`、工具参数/结果、工作目录、提示词、附件 URL、完整 `metadata` 均超出活动展示所需范围，不能保存在 Zisla 数据库、日志或遥测中。

## 安全与实现边界

- 只接受普通文件；遇到重解析点、符号链接、权限拒绝、目录逃逸、不可读文件或超过实现上限的 JSON 时跳过。
- SQLite 以 `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX` 打开，设置短 busy timeout；任何打开、prepare、step 或 JSON 解析失败都不创建文件、不重试写入，也不阻塞 UI。
- 文件变化 token 同时覆盖主 `.db`、`-wal` 和 `-shm` 的大小/时间。只有 token 改变时才刷新，失败时保留最近一次成功快照。
- 默认限制会话数、每会话消息数和 JSON 文件字节数；所有路径与根目录边界比较后再打开。
- UI 只显示会话标题、模型（若可识别）、更新时间与“推断状态”。不暴露文件路径、工作区路径、消息正文、工具输出、令牌、账户资料或数据库原始 JSON。

## 不确定项与 Windows 实机待验证

1. 已知默认根来自当前锁定的 `xdg-basedir@5.1.0`；但 `XDG_DATA_HOME` 可在启动 OpenCode 的环境中覆盖它。首次 Windows 调试必须核对实际 `dataRoot` 和覆盖变量，不应额外扩大为 `%APPDATA%`/`%LOCALAPPDATA%` 的全盘候选扫描。
2. `OPENCODE_DB` 可以指向任意绝对路径，且启动时环境变量不一定能从另一个进程恢复。默认扫描不应尝试全盘或全用户目录猜测；需要用户显式设置扫描路径。
3. 当前源码同时保留 SQLite 和 JSON 迁移服务，未承诺外部扫描器的 schema 稳定性。实现必须用固定 fixture 覆盖 SQLite 主路径、channel 数据库、带 WAL、锁库/损坏库、迁移后 JSON、旧项目 JSON 和未知 schema。
4. SQLite 只能提供时间和可解析的消息完成标记；官方 `busy/idle` 是内存态。因此真机验证时要对照 OpenCode UI/CLI，校准“可能活跃”的时间窗与展示文案。

## 本次未运行测试

本任务只新增调研文档，没有修改生产代码、测试代码或构建配置；没有可运行的相关 UT。Windows 文件路径、SQLite WAL 互操作和 OpenCode 实例行为均留待 Windows 真机阶段验证。
