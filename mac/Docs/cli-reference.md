# `zislactl` integration reference

**English** | [简体中文](cli-reference.zh-CN.md)

`zislactl` is the shared local status protocol for AI tools, scripts, and CI tasks that integrate with zisla. It writes task state, usage, and notifications as structured data and uses atomic replacement to avoid partially written state. This document defines stable providers, commands, and field constraints.

## Design principles

- State is written locally and never uploads prompts, answer bodies, or credentials.
- Updates for the same task ID are idempotent; readers always see complete JSON state.
- Provider names accept compatibility aliases but are persisted using their canonical value.

## Providers

| Value | Aliases |
| --- | --- |
| `claude` | `claude-code`, `claude-cli`, `claude-desktop` |
| `codex` | `openai-codex`, `codex-cli`, `codex-desktop` |
| `gemini` | `google-gemini`, `gemini-cli`, `gemini-code-assist` |
| `grok` | `grok-cli`, `xai` |
| `gpt` | `openai`, `chatgpt`, `openai-gpt` |
| `copilot` | `github-copilot`, `copilot-cli`, `copilot-chat` |
| `kimi` | `kimi-code`, `kimi-code-cli`, `kimi-vscode` |
| `qwen` | `tongyi`, `qwen-code`, `qwen-code-cli`, `qwen-vscode` |
| `coder` | `qoder`, `qoder-cli`, `qoderwork`, `qoderwork-cn`, `qoderwake`, `qwen-coder` |
| `zcode` | `z-code`, `zcode-cli`, `zcode-desktop`, `glm`, `glm-coding`, `z-ai`, `z.ai` |
| `trae` | `trae-work`, `traework`, `trae-solo`, `trae-cn` |
| `opencode` | `open-code`, `open_code` |
| `pi` | `pi-coding`, `pi-coding-agent`, `pi-cli`, `pi-agent` |
| `harness` | `harnext`, `harnext-cli`, `harness-cli` |
| `doubao` | `豆包` |

## `update`

Creates or replaces a task with the same `id`.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- If `--progress` is omitted, the UI shows indeterminate progress.
- `--pid` is optional and should be supplied only when the caller can identify the task's process.
- `--status` explicitly reports running, queued, waiting for user action, or an error while running.
- `--queued` is an alias for `--status queued`; without an explicit status, the task is running.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

Successful tasks are set to 100%; failed tasks keep their last progress.

## `remove`

```text
zislactl remove --id <id>
```

Exits with code 65 when the task does not exist.

## `clear`

```text
zislactl clear
```

Clears tasks while preserving usage history and notifications.

## `list`

```text
zislactl list
```

Prints the current task state, provider, title, and percentage one line at a time.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

Usage feeds the 12-hour chart and 7x24 heatmap.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

The new notification appears from the selected side and pauses auto-dismiss while hovered.

## `message`

Sends one message notification to both sides of the island: the left side shows the app logo and sender, while the right side scrolls the body.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

Example:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender`, and `--content` are required; `--app-bundle-id` is optional and helps resolve the installed app icon.
- Line breaks and excess whitespace are collapsed, and the body is truncated to about 48 characters with an ellipsis.
- One write atomically persists both `IslandNotice` entries without changing existing `notify` behavior.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `64` | Invalid argument or subcommand |
| `65` | Data error, missing task, or corrupted state file |
| `70` | Filesystem or other runtime error |
