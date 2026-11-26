# `zislactl` 接続リファレンス

[English](../../../../../mac/Docs/cli-reference.md) | [简体中文](../../../../../mac/Docs/cli-reference.zh-CN.md) | **日本語** | [他の言語](../../../README.md)

`zislactl` は AI ツール、スクリプト、CI が zisla に接続する共通ローカル状態プロトコルです。タスク、使用量、通知を構造化して SQLite トランザクションで保存し、途中状態を防ぎます。ここでは安定した Provider、コマンドと制約を定義します。

## 設計原則

- 状態はローカルに保存し、プロンプト、回答本文、認証情報を送信しません。
- 同一 ID の更新は冪等で、読み手はコミット済みの完全な状態を取得します。
- Provider は互換別名を受け付けますが、正規値で保存します。

## ローカル保存と JSON の境界

タスク、使用量と通知は `~/Library/Application Support/zisla/ai-state.sqlite` にあります。SQLite トランザクションで書き、現在のプロトコルは `ai-state.json` に書きません。タスクを消去しても使用履歴を保持します。

`zislactl` は記載されたコマンド引数を受け、`list` は行単位のテキストを出力します。外部ツールの JSON/JSONL セッション入力や設定の JSON のエンコード・デコードは各解析規則で処理します。CLI 自体はコマンド引数、テキスト出力と SQLite 保存を使います。

## Provider

| 値 | 別名 |
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

WorkBuddy と WorkBuddy AI は国内・国外向けの独立製品で、旧版・新版ではありません。Provider、保存先、アイコン、deep link を分離します。過去の WorkBuddy の `harness` レコードは読めますが、Provider 全体を改名・移行しません。活動通知 ID は `ai-active-workbuddy:<id>` と `ai-active-workbuddy-ai:<id>` の境界を使い、`ai-` で始まる手動タスクを別製品と混同しません。

### Delta、Orca、WorkBuddy と WorkBuddy AI の自動検出

- **Delta：** `Library/Application Support/Delta/user_*/data.sqlite` と旧ルート DB の streaming-thread 索引を読みます。アーカイブ、アイドル、古い会話を除外し、`app_model_usage_daily` の数値（cache 読み書きも含む）を使用します。台帳がない版では使用量を自動取得せず、会話から推定しません。
- **Orca：** `agent-hooks/last-status.json` と `agent-session-journal.db` の現在の構造化 turn 状態を、profile と v1/v2/v3 対応で読みます。最高 revision と元の順序を守り、完了、期限切れ、リモート、識別情報のみを除外します。確認された transcript と固定 Claude/Codex アカウントの数値も使用し、元 CLI Provider とイベント ID を保持して重複を防ぎます。全機械の使用量 cache は追加取得しません。
- **WorkBuddy：** `~/.workbuddy/workbuddy.db` だけを読み、`workbuddy`、専用アイコン、`workbuddy://chat/<id>` を使います。WorkBuddy AI の DB を読みません。
- **WorkBuddy AI：** `~/.workbuddy-ai/workbuddy.db` の状態、タイトル、モデル、日時を独立して読みます。完了、削除、古い会話は除外し、`updated_at` と `last_activity_at` の新しい方で長いタスクを維持します。Provider `workbuddy-ai` と `workbuddy-ai://chat/<id>` を使います。セッション検出のみで、`session_usage.used` は文脈占有、credits は USD/token ではないため課金 token にしません。数値は `zislactl usage` で報告できます。
- すべて読み取り専用で、欠損や非互換の保存先はデータなしになります。Delta の複製された本文や Orca journal の本文を読みません。数値を提供しない版は `zislactl usage` を使ってください。

## 引数の書式

- `--key value` または `--key=value`。一つの引数はコマンドごとに一度のみで、重複は終了コード 64 です。
- 値は `--` で始められます（`--detail --verbose`）。同コマンドの flag（`finish` の `--failed`、`update` の `--queued`）は値にしないため、引用されていない空変数 `--detail $DETAIL --failed` でも失敗扱いになります。その文字列を値にするなら `--detail=--failed` を使います。
- `--failed` と `--queued` は単独なら true です。`--failed=false` または `--failed false` は無効にし、`--queued` も同じ書式を使います。他の値は用法エラーです。

## `update`

同じ `id` のタスクを作成または置き換えます。

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- `--progress` 省略は進行不定の表示です。
- `--pid` はタスクのプロセスを特定できる場合だけ指定します。
- `--status` は実行中、待機、ユーザー操作待ち、実行中エラーを明示します。
- `--queued` は `--status queued` の別名で、未指定は実行中。明示した `--status` が優先します。

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

成功は 100% にし、失敗は直前の進行を保持します。

## `remove`

```text
zislactl remove --id <id>
```

タスクがなければ 65 で終了します。

## `clear`

```text
zislactl clear
```

使用履歴と通知を残してタスクだけを消去します。

## `list`

```text
zislactl list
```

タスク状態、Provider、タイトルと割合を一行ずつ表示します。

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

12 時間グラフと 7x24 ヒートマップに使います。

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

選んだ側に表示し、ホバー中は自動終了を止めます。

## `message`

左右に同時通知します。左はアプリのロゴと送信者、右は本文をスクロール表示します。

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

例：

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`、`--sender`、`--content` は必須。任意の `--app-bundle-id` は導入済みアプリのアイコン取得を助けます。
- 改行・余分な空白をまとめ、本文を約 48 文字に省略します。
- 一つの SQLite トランザクションで左右の `IslandNotice` を保存し、`notify` は変更しません。

## 終了コード

| コード | 意味 |
| --- | --- |
| `0` | 成功 |
| `64` | 引数・コマンドの用法エラー |
| `65` | データエラー、タスクなし、DB 破損 |
| `70` | ファイルシステムなどの実行時エラー |
