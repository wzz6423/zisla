# `zislactl` 接入设计与协议

[English](cli-reference.md) | **简体中文**

`zislactl` 是本地 AI 工具、脚本和 CI 任务接入 zisla 的统一状态协议。设计目标是让任务状态、用量和通知都通过结构化数据写入，并以原子替换避免半写入状态；本文件定义稳定的 Provider、命令和字段约束。

## 设计原则

- 状态写入只发生在本机，不上传提示词、回答正文或凭据。
- 同一任务 ID 的更新保持幂等，读取方始终看到完整 JSON 状态。
- Provider 名称允许兼容别名，但持久化时使用规范值。

## Provider

| 值 | 别名 |
| --- | --- |
| `claude` | `claude-code`、`claude-cli`、`claude-desktop` |
| `codex` | `openai-codex`、`codex-cli`、`codex-desktop` |
| `gemini` | `google-gemini`、`gemini-cli`、`gemini-code-assist` |
| `grok` | `grok-cli`、`xai` |
| `gpt` | `openai`、`chatgpt`、`openai-gpt` |
| `copilot` | `github-copilot`、`copilot-cli`、`copilot-chat` |
| `kimi` | `kimi-code`、`kimi-code-cli`、`kimi-vscode` |
| `qwen` | `tongyi`、`qwen-code`、`qwen-code-cli`、`qwen-vscode` |
| `coder` | `qoder`、`qoder-cli`、`qoderwork`、`qoderwork-cn`、`qoderwake`、`qwen-coder` |
| `zcode` | `z-code`、`zcode-cli`、`zcode-desktop`、`glm`、`glm-coding`、`z-ai`、`z.ai` |
| `trae` | `trae-work`、`traework`、`trae-solo`、`trae-cn` |
| `opencode` | `open-code`、`open_code` |
| `pi` | `pi-coding`、`pi-coding-agent`、`pi-cli`、`pi-agent` |
| `harness` | `harnext`、`harnext-cli`、`harness-cli` |
| `doubao` | `豆包` |
| `delta` | `delta-app`、`delta-desktop`、`zed-delta` |
| `orca` | `orca-desktop`、`orca-ide` |
| `workbuddy` | `workbuddy-ai`、`workbuddyai`、`workbuddy ai` |

### Delta、Orca 与 WorkBuddy AI 自动检测

- Delta：只读 `Library/Application Support/Delta/user_*/data.sqlite` 及旧版根数据库中的
  streaming 会话索引；忽略归档、空闲及过期会话。用量读取 `app_model_usage_daily` 数字账本，
  包含缓存读写 token。没有该账本的版本不会自动生成用量，也不会从会话正文猜测计数。
- Orca：读取本地 `agent-hooks/last-status.json` 和 `agent-session-journal.db` 的当前结构化
  会话状态，支持 profile 目录及 v1/v2/v3 turn 记录，按最高 revision 和 turn 的创建顺序还原。
  忽略结束、租约过期、远程及纯身份记录。由工具确认的 transcript
  路径以及绑定的 Claude/Codex 账号目录提供用量，保留底层 CLI provider 和事件 ID，避免与
  普通 CLI 检测器重复计数。不把 Orca 的全机器用量缓存再次作为额外用量导入。
- WorkBuddy AI：读取 `~/.workbuddy-ai/workbuddy.db` 中的会话状态、标题、模型与时间戳，
  与旧版 `~/.workbuddy/workbuddy.db` 独立。忽略结束、删除和过期会话，取 `updated_at` 与
  `last_activity_at` 中较新时间以保留长任务。使用 `workbuddy` provider、WorkBuddy AI 图标
  和 `workbuddy-ai://chat/<id>` 跳转。本集成仅检测会话；`session_usage.used` 是上下文占用，
  credits 也不是美元或 token，因此不作为计费用量导入。数字用量可用 `zislactl usage` 上报。
- 三种集成都只读、尽力兼容，缺失或不兼容的数据源不产生记录。不查询 Delta 复制树正文或
  Orca journal 的消息正文。没有数字用量接口的工具版本可通过 `zislactl usage` 上报。

## `update`

新增或覆盖同一 `id` 的任务。

```text
zislactl update --id <id> --provider <provider> --title <标题>
  [--progress <0-100>] [--detail <文本>] [--pid <进程 PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- `--progress` 缺省时显示不确定进度。
- `--pid` 可选；仅在调用方能确认任务所属进程时传入。
- `--status` 可显式上报运行、排队、等待用户操作或运行中错误。
- `--queued` 是 `--status queued` 的兼容写法；未指定状态时为运行中。

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <文本>]
```

成功任务自动设为 100%；失败任务保留最后进度。

## `remove`

```text
zislactl remove --id <id>
```

任务不存在时退出码为 65。

## `clear`

```text
zislactl clear
```

仅清空任务，保留用量历史和通知。

## `list`

```text
zislactl list
```

按行输出当前任务状态、provider、标题和百分比。

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <美元>] [--model <模型>] [--timestamp <Unix 秒>]
```

用量用于 12 小时曲线和 7x24 热力图。

## `notify`

```text
zislactl notify --title <标题>
  [--detail <文本>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

新通知会从指定一侧弹出，悬停时暂停自动关闭。

## `message`

向灵动岛两侧同时推送一条消息通知：左侧显示应用 Logo 与发件人，右侧滚动展示正文。

```text
zislactl message --app <应用名> --sender <发件人> --content <正文>
  [--app-bundle-id <bundle id>]
```

示例：

```text
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "今晚 7 点会议室见" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`、`--sender`、`--content` 必填；`--app-bundle-id` 可选，用于解析已安装 App 图标。
- 正文会折叠换行与多余空白，并截断到约 48 个字符后加省略号。
- 一次写入会原子落盘左右两条 `IslandNotice`，不影响既有 `notify` 行为。

## 退出码

| 退出码 | 含义 |
| --- | --- |
| `0` | 成功 |
| `64` | 参数或子命令错误 |
| `65` | 数据错误、任务不存在或状态文件损坏 |
| `70` | 文件系统等运行时错误 |
