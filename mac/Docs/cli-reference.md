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
| `delta` | `delta-app`, `delta-desktop`, `zed-delta` |
| `orca` | `orca-desktop`, `orca-ide` |
| `workbuddy` | `workbuddy-desktop` |
| `workbuddy-ai` | `workbuddyai`, `workbuddy ai` |

WorkBuddy and WorkBuddy AI are separate products for domestic/international markets, not
older/newer versions of one client. Their canonical providers, stores, icons and deep links
must remain separate. Historical WorkBuddy records using `harness` remain readable; that
provider is not globally renamed or migrated. WorkBuddy activity-notice IDs use an explicit
provider/task boundary (`ai-active-workbuddy:<id>` or `ai-active-workbuddy-ai:<id>`), so a manual
WorkBuddy task whose ID starts with `ai-` cannot be mistaken for WorkBuddy AI.

### Delta, Orca, WorkBuddy and WorkBuddy AI automatic detection

- Delta: reads indexed streaming-thread metadata from `Library/Application Support/Delta/user_*/data.sqlite`
  (and the legacy root database). Archived, idle and stale threads are excluded. Numeric usage comes
  from Delta's `app_model_usage_daily` ledger, including cache reads and writes. A release without
  this ledger reports no automatic usage; it does not guess counts from conversation content.
- Orca: reads local `agent-hooks/last-status.json` snapshots and current structured-chat turn state
  from `agent-session-journal.db`, including profile directories and v1/v2/v3 turn records.
  Highest revisions and original turn ordering are respected. Completed, expired, remote and
  identity-only sessions are excluded. Authoritative transcript paths and pinned Claude/Codex
  account homes also contribute token usage. Those samples retain the underlying CLI provider and
  event identity, so the regular CLI detector cannot count them again. Orca's machine-wide usage
  caches are deliberately not imported as additional usage.
- WorkBuddy: reads its own `~/.workbuddy/workbuddy.db` with provider `workbuddy`, the
  WorkBuddy icon and `workbuddy://chat/<id>` links. It does not inspect WorkBuddy AI's store.
- WorkBuddy AI: reads session status, titles, model and timestamps from
  `~/.workbuddy-ai/workbuddy.db`, independently of WorkBuddy's `~/.workbuddy/workbuddy.db`.
  Finished, deleted and stale sessions are excluded; the fresher of `updated_at` and
  `last_activity_at` keeps long-running sessions visible. Tasks use the `workbuddy-ai` provider,
  the WorkBuddy AI icon and `workbuddy-ai://chat/<id>` links. This integration detects sessions
  only: `session_usage.used` is context occupancy and credits are not USD/token usage, so neither
  is imported as billed tokens. Manual numeric usage can be reported with `zislactl usage`.
- All integrations are read-only and best effort; missing or incompatible stores return no data.
  Neither queries replicated Delta thread bodies or Orca journal message bodies. Use `zislactl usage`
  for tools or versions that do not expose recorded numeric usage.

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
