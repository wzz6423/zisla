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
| `trae` | `trae-work`、`traework`、`trae-solo`、`trae-cn` |
| `opencode` | `open-code`、`open_code` |
| `harness` | `harnext`、`harnext-cli`、`harness-cli` |
| `doubao` | `豆包` |

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
