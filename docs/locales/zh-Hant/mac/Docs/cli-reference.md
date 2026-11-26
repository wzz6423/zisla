# `zislactl` 接入設計與協議

[English](../../../../../mac/Docs/cli-reference.md) | [简体中文](../../../../../mac/Docs/cli-reference.zh-CN.md) | **繁體中文** | [其他語言](../../../README.md)

`zislactl` 是本地 AI 工具、腳本和 CI 任務接入 zisla 的統一狀態協議。設計目標是讓任務狀態、用量和通知都通過結構化資料寫入，並以 SQLite 事務避免半寫入狀態；本檔案定義穩定的 Provider、命令和字段約束。

## 設計原則

- 狀態寫入只發生在本機，不上傳提示詞、回答正文或憑據。
- 同一任務 ID 的更新保持冪等，讀取方看到完整提交的資料庫狀態。
- Provider 名稱允許兼容別名，但持久化時使用規範值。

## 本地持久化與 JSON 邊界

任務、用量與通知儲存在 `~/Library/Application Support/zisla/ai-state.sqlite`。寫入使用 SQLite 事務，當前協議不寫入 `ai-state.json`。清空任務不刪除用量歷史。

`zislactl` 接受上述命令行參數，`list` 輸出逐行文本。集成和配置仍使用真實的結構化 JSON，例如外部工具的 JSON/JSONL 會話輸入與設定的 JSON 編解碼；這些資料按各自的解析規則處理。CLI 本身使用命令行參數輸入和文本輸出，持久化使用 SQLite。

## Provider

| 值 | 別名 |
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
| `workbuddy` | `workbuddy-desktop` |
| `workbuddy-ai` | `workbuddyai`、`workbuddy ai` |

WorkBuddy 與 WorkBuddy AI 是面向國內/國外市場的兩個獨立產品，不是舊版與新版關係。
兩者的規範 provider、存儲目錄、圖標和深連結必須獨立。歷史 WorkBuddy 記錄中使用的
`harness` 仍可讀取，不整體重命名或遷移該 provider。兩者活動通知使用明確的 provider/任務邊界
（`ai-active-workbuddy:<id>` 與 `ai-active-workbuddy-ai:<id>`），避免 ID 以 `ai-` 開頭的
手動 WorkBuddy 任務被誤判為 WorkBuddy AI。

### Delta、Orca、WorkBuddy 與 WorkBuddy AI 自動檢測

- Delta：只讀 `Library/Application Support/Delta/user_*/data.sqlite` 及舊版根資料庫中的
  streaming 會話索引；忽略歸檔、空閒及過期會話。用量讀取 `app_model_usage_daily` 數字賬本，
  包含緩存讀寫 token。沒有該賬本的版本不會自動生成用量，也不會從會話正文猜測計數。
- Orca：讀取本地 `agent-hooks/last-status.json` 和 `agent-session-journal.db` 的當前結構化
  會話狀態，支援 profile 目錄及 v1/v2/v3 turn 記錄，按最高 revision 和 turn 的創建順序還原。
  忽略結束、租約過期、遠程及純身份記錄。由工具確認的 transcript
  路徑以及綁定的 Claude/Codex 賬號目錄提供用量，保留底層 CLI provider 和事件 ID，避免與
  普通 CLI 檢測器重復計數。不把 Orca 的全機器用量緩存再次作為額外用量匯入。
- WorkBuddy：只讀自己的 `~/.workbuddy/workbuddy.db`，使用 `workbuddy` provider、
  WorkBuddy 圖標和 `workbuddy://chat/<id>` 跳轉，不讀取 WorkBuddy AI 的資料目錄。
- WorkBuddy AI：讀取 `~/.workbuddy-ai/workbuddy.db` 中的會話狀態、標題、模型與時間戳，
  與 WorkBuddy 的 `~/.workbuddy/workbuddy.db` 獨立。忽略結束、刪除和過期會話，取 `updated_at` 與
  `last_activity_at` 中較新時間以保留長任務。使用 `workbuddy-ai` provider、WorkBuddy AI 圖標
  和 `workbuddy-ai://chat/<id>` 跳轉。本集成僅檢測會話；`session_usage.used` 是上下文佔用，
  credits 也不是美元或 token，因此不作為計費用量匯入。數字用量可用 `zislactl usage` 上報。
- 這些集成都只讀、盡力兼容，缺失或不兼容的資料源不產生記錄。不查詢 Delta 複製樹正文或
  Orca journal 的消息正文。沒有數字用量接口的工具版本可通過 `zislactl usage` 上報。

## 參數寫法

- 參數可寫成 `--key value` 或 `--key=value`。同一命令里每個參數只能出現一次，重復會按用法錯誤處理（退出碼 64）。
- 值可以以 `--` 開頭，例如 `--detail --verbose`。例外是同一命令的開關（`finish` 的 `--failed`、`update` 的 `--queued`）：它們不會被當作值，所以 `--detail $DETAIL --failed` 里的變量為空且沒加引號時，任務仍記為失敗。確實要傳這類字面值時寫成 `--detail=--failed`。
- `--failed` 和 `--queued` 是開關。單獨出現表示開啓；`--failed=false` 或 `--failed false`（`--queued` 同理）表示關閉；其他值按用法錯誤處理。

## `update`

新增或覆蓋同一 `id` 的任務。

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- `--progress` 缺省時顯示不確定進度。
- `--pid` 可選；僅在呼叫方能確認任務所屬程序時傳入。
- `--status` 可顯式上報運行、排隊、等待用戶操作或運行中錯誤。
- `--queued` 是 `--status queued` 的兼容寫法；未指定狀態時為運行中。同時傳了 `--status` 時以 `--status` 為準。

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

成功任務自動設為 100%；失敗任務保留最後進度。

## `remove`

```text
zislactl remove --id <id>
```

任務不存在時退出碼為 65。

## `clear`

```text
zislactl clear
```

僅清空任務，保留用量歷史和通知。

## `list`

```text
zislactl list
```

按行輸出當前任務狀態、provider、標題和百分比。

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

用量用於 12 小時曲線和 7x24 熱度圖。

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

新通知會從指定一側彈出，懸停時暫停自動關閉。

## `message`

向靈動島兩側同時推送一條消息通知：左側顯示應用 Logo 與發件人，右側滾動展示正文。

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

示例：

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`、`--sender`、`--content` 必填；`--app-bundle-id` 可選，用於解析已安裝 App 圖標。
- 正文會折疊換行與多餘空白，並截斷到約 48 個字符後加省略號。
- 一次 SQLite 事務會同時提交左右兩條 `IslandNotice`，不影響既有 `notify` 行為。

## 退出碼

| 退出碼 | 含義 |
| --- | --- |
| `0` | 成功 |
| `64` | 參數或子命令錯誤 |
| `65` | 資料錯誤、任務不存在或資料庫損壞 |
| `70` | 檔案系統等運行時錯誤 |
