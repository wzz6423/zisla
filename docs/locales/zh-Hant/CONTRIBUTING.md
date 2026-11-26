# 貢獻指南

[English](../../../CONTRIBUTING.md) | [简体中文](../../../CONTRIBUTING.zh-CN.md) | **繁體中文** | [其他語言](../README.md)

感謝你為 zisla 做出貢獻。

## 問題反饋

感謝你提交 Issue。開始前請搜索已有的 Issue 和 Discussions，避免重復提交。

- 缺陷報告標題使用 `[Bug] Short problem description`，例如 `[Bug] Voice input is not written to the current text field`。正文至少包含 zisla 版本、macOS 與設備、安裝方式、復現步驟、預期行為和實際行為。
- 功能建議標題使用 `[Feature] Short request description`，例如 `[Feature] Support custom voice-organization prompts`。正文說明當前問題、建議方案和已考慮的替代方案。
- 表單中的**所屬範圍**為必填，它決定 `area:*` 標籤：`Feature Development`、`Bug Fix`、`CI & Build`、`Documentation`、`Community & Discussion`。簡體中文表單提供同一組對應選項，並映射到同一批標籤。
- 日誌、截圖和螢幕錄影需先移除令牌、賬號、本地路徑等敏感信息。
- 安全漏洞請通過 [安全通告](https://github.com/wzz6423/zisla/security/advisories/new) 私下報告，不要公開提交 Issue。
- 自動化會打上 `bug` 或 `enhancement` 以及對應的 `area:*` 標籤，並保留其他所有標籤。標題前綴或必填字段不符合表單時會追加 `needs-more-info`，並用同一條評論列出缺失項；編輯 Issue 後該評論會自動更新。

## 開發

當前 macOS 實現在 `mac/` 目錄中，依賴 macOS 14+ 與 Swift 6 / Xcode 16+。

```bash
cd mac
swift test
```

提交前請刪除測試、構建和打包產生的二進制產物。

每次提交或 amend 前，在倉庫根目錄使用與 CI 一致的 SwiftFormat 0.64.7 執行 `make format`。檢查差異，只保留當前任務需要的格式化。

## 分支和提交

- 從最新的 `main` 創建分支，前綴與該 PR 聲明的類型一致：`feat/`（或 `feature/`）、`fix/`、`docs/`、`style/`、`refactor/`、`perf/`、`test/`、`chore/`、`build/`、`ci/`、`revert/`，例如 `fix/download-timeout` 或 `ci/skip-directive-timing`。
- 提交信息使用英文 [Conventional Commits](https://www.conventionalcommits.org/) 格式：`type(scope): description`，例如 `fix(ui): resolve layout issue in notch area`。
- 一個分支和一個 PR 應只處理一個明確目標；請避免混入格式化或無關重構。
- 發佈分支 `publish-v*` 僅用於發佈維護。除發佈修復外，貢獻請提交到 `main`。

## 拉取請求

感謝你提交 Pull Request。請在等待評審時確認以下要求。

- **PR 標題**必須使用英文 Conventional Commit 格式，例如：
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  允許的類型：`feat`、`fix`、`docs`、`style`、`refactor`、`perf`、`test`、`chore`、`build`、`ci`、`revert`。

- **PR 正文**必須使用英文，並包含 `.github/PULL_REQUEST_TEMPLATE.md` 提供的 `Summary`、`GitHub Project`、`PR Type`、`Validation`、`Risk and Rollback`、`Related Issue`、`AI Attribution` 七節。
  - `GitHub Project` 保留模板給出的 `- Project: zisla Development`。`Project Automation` 據此把 PR 放進共享看板。
  - `GitHub Project` 中必須填寫 `Start date` 和 `Target date`，各出現一次，使用 `YYYY-MM-DD` 格式的真實日期；`Target date` 不能早於 `Start date`。缺失、留空、僅寫在注釋中、重復或無效的日期都會導致 `PR Quality` 失敗。`Submitted date` 自動取 UTC+08:00 的創建日期；`End date` 在 PR 合併時自動填寫，兩者都不需要手動輸入。
  - `PR Type` 只寫一條 `- Type:`，且必須能解析為標題中的類型。標題使用規範類型；正文同時接受類型標籤名和已配置別名，因此 `fix`、`bug`、`bug fix`、`bugfix`、`hotfix` 都會解析為 `fix`。`PR Automation` 會根據解析後的類型打標籤，例如 `fix` 對應 `bug`。
  - `Project Automation` 按配置的標籤映射（包含 PR 類型標籤）選擇 `Status`，關閉或合併後設為 `Done`，不需要手動填寫。
  - `Summary` 必須說明改動；`Risk and Rollback` 必須各填寫一條非空的 `Risk` 和 `Rollback`。
  - 每項 `Validation` 都從自己的 `- Status:` 開始，精確聲明 `passed`、`failed` 或 `not run`。每項 `passed` 或 `failed` 都需要自己的非空 `Command` 和 `Result`；每項 `not run` 都需要自己的非空 `Reason`，不能借用其他項的字段。測試失敗時如實填寫 `failed`。
  - `Related Issue` 要麼用 `Closes #123` 之類的關鍵字關聯 Issue（同時自動打上 `development`），要麼寫成 `None`。
  - `AI Attribution` 必須聲明且僅聲明一條非空的 `- Agent:`。聲明瞭具體 agent 時，必須補一條 `- Co-authored-by: Name <email>`，並且該 trailer 必須真實出現在至少一個 commit 上，同時會自動打上 `ai-assisted`。

  標題示例：`fix(ci): validate every PR metadata entry`

  正文示例（請填寫實際驗證結果）：

  ```markdown
  ## Summary
  - Validate every PR metadata field and each Validation entry independently.
  - Keep contributor welcome replies aligned with the current PR template.

  ## GitHub Project
  - Project: zisla Development
  - Start date: 2026-10-05
  - Target date: 2026-10-12
  <!--
  Automatic Project fields (illustration only; not PR body inputs):
  - Submitted date: 2026-10-05 (PR creation date in UTC+08:00)
  - End date: 2026-10-12 (assumed merge date in UTC+08:00; blank before merge)
  Automation updates Project date fields and the PR Timeline; it does not fill these comment lines.
  -->

  ## PR Type
  - Type: fix

  ## Validation
  - Status: passed
  - Command: ruby .github/scripts/pr-metadata-test.rb
  - Result: All PR metadata contract tests passed.

  - Status: passed
  - Command: ruby .github/scripts/contributor-welcome-test.rb
  - Result: Both documented examples pass PR validation and the welcome reply preserves the complete example.

  - Status: passed
  - Command: actionlint .github/workflows/*.yml
  - Result: All workflow files passed actionlint.

  - Status: not run
  - Reason: Local macOS tests were not run because this change only affects PR metadata and contributor guidance. Platform checks still run in CI.

  ## Risk and Rollback
  - Risk: Stricter metadata checks may reject incomplete PR descriptions; no application behavior changes.
  - Rollback: Revert this pull request to restore the previous metadata checks and guidance.

  ## Related Issue
  None

  ## AI Attribution
  - Agent: Codex
  - Co-authored-by: Codex <noreply@openai.com>
  ```

  日期示例：假設 PR 於 2026-10-05 創建、2026-10-12 合併（UTC+08:00）。代碼注釋中的自動字段只展示 Project 的示例值，不是輸入項；自動化更新 GitHub Project 和 PR Timeline，不會填寫這些示例注釋行。

  | 日期 | 創建時（2026-10-05） | 合併後（2026-10-12） | 來源 |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | 必須手填 |
  | `Target date` | 2026-10-12 | 2026-10-12 | 必須手填 |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | 自動取創建日期 |
  | `End date` | 空 | 2026-10-12 | 自動取合併日期 |

- `PR Quality` 檢查會自動驗證上述格式；狀態檢查未通過時不能合併。隨後 `PR Automation` 負責打標籤與指派。
- macOS 代碼變更必須運行 `cd mac && swift test`；涉及界面時請用文字說明實際驗證結果。
- PR 正文和發版說明均可只使用文字，不需要圖片、截圖或封面。
- 修改功能、行為、預設值、構建方式或發佈流程時，同一補丁同步正式文檔與官網幫助。官網用戶文案覆蓋 17 種語言，復用現有幫助結構和集中本地化文檔目錄。
- 不要提交 `.build`、`dist`、下載檔案、日誌、令牌、簽名材料或其他個人資料。
- `main` 和 `publish-v*` 受保護，只能通過檢查並完成評審的 PR 合併。

## 跳過 CI

當改動確實不可能影響某些檢查時（例如純文檔修改），維護者與被請求的 reviewer 可以跳過它們。在 PR 評論中單獨一行寫下指令：

| 指令 | 效果 |
| --- | --- |
| `skip-all` | 跳過 `.github/ci-skip.json` 中列出的所有工作流。 |
| `skip-<workflow>` | 按名稱、檔案名或別名跳過單個工作流，例如 `skip-swift`、`skip-web-ci`、`skip-Web CI`。 |
| `unskip-all` | 取消所有跳過指令。 |
| `unskip-<workflow>` | 恢復單個工作流。 |

- 指令後面可以接自由文本，例如 `skip-all: documentation only change`。
- 工作流可以直接寫 GitHub 上顯示的名字（含空格），因此 `skip-CI Lint` 與 `skip-lint` 等價；匹配時取最長的已知名稱，剩下的詞作為備注。
- 只有倉庫 owner、組織成員、協作者或被請求的 reviewer 的指令才生效，機器人評論一律忽略。
- `CI Skip` 會取消正在運行的任務，把被跳過的檢查標記為成功以滿足必需檢查，打上 `skip-ci` 標籤，並復用同一條評論匯總當前決策。
- 每次評論都會重放整個評論區，因此最新的指令始終生效。
- 一旦推送了新 commit，此前的指令隨即失效：指令只能針對作者當時看到的代碼，否則被標記為成功的檢查會讓未經構建的新 commit 直接合併。每次推送都會重新運行 `CI Skip`，摘掉 `skip-ci` 標籤並恢復檢查，摘要評論里會列出失效的指令。若新 commit 同樣需要跳過，請再評論一次。
- 維護者也可以不用新增評論，在 **Actions -> CI Skip -> Run workflow** 里填入 PR 編號重新應用當前決策。
- `.github/ci-skip.json` 記錄了每個工作流發佈的檢查名；清單與工作流不一致時 `CI Checks` 會失敗。

## 按路徑裁剪檢查

平台相關的工作流只在 PR 改動了它構建的檔案時才運行，所以文檔改動按所屬路徑決定是否運行平台檢查：

| 工作流 | 觸發它的改動路徑 |
| --- | --- |
| `Swift Tests` | `mac/**`、`Makefile`、`.swiftformat`、`.github/**` |
| `Web CI` | `web/**`、`promo/**`、`docs/**`、`.github/**` |

- 範圍由 `.github/ci-skip.json` 的 `paths` 字段決定；沒有聲明 `paths` 的工作流始終運行，因此 `CI Lint`、`PR Quality Gates`、`CodeQL`、`Dependency Review` 每個 PR 都會跑。倉庫衛生與技能驗證屬於 `CI Checks`；舊 `hygiene` 和 `skills` 別名不再使用。
- 只要改動了 `.github/` 下的檔案就全部運行，因為改 CI 必須在所有平台上驗證。
- 裁剪用的是 job 級條件而不是工作流的 `paths:` 過濾器，這樣必需檢查會報告成功，而不是一直掛在 pending。
- 檔案重命名會同時按舊路徑和新路徑匹配，且比較時忽略大小寫。
