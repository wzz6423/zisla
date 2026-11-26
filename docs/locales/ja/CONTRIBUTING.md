# zisla への貢献

[English](../../../CONTRIBUTING.md) | [简体中文](../../../CONTRIBUTING.zh-CN.md) | **日本語** | [他の言語](../README.md)

zisla への貢献を歓迎します。

## Issue

既存 Issue と Discussions を検索して重複を避けてください。

- 不具合は `[Bug] Short problem description` を使います（例：`[Bug] Voice input is not written to the current text field`）。版、macOS、機器、導入方法、再現手順、期待と実際を記載します。
- 機能は `[Feature] Short request description`（例：`[Feature] Support custom voice-organization prompts`）。問題、提案と検討した代替案を説明します。
- フォームで必須の Area を一つ選びます：`Feature Development`、`Bug Fix`、`CI & Build`、`Documentation`、`Community & Discussion`。簡体中国語版も同じ `area:*` に対応します。
- ログ、画像、録画から token、アカウント、ローカルパスなどの秘密情報を削除します。
- セキュリティは公開 Issue ではなく [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) へ非公開で報告します。
- 自動化は `bug` または `enhancement` と対応する `area:*` ラベルを付け、ほかのラベルはすべて保持します。接頭辞や必須情報がない場合は `needs-more-info` と単一コメントで不足を示し、編集後に同じコメントを更新します。

## 開発

実装はルートの `mac/`、macOS 14+、Swift 6 / Xcode 16+ です。

```bash
cd mac
swift test
```

commit 前にテスト、ビルド、パッケージの二進成果物を除去します。commit と amend の前に CI と同じ SwiftFormat 0.64.7 で、ルートから `make format` を実行し、今回必要な差分だけを残します。

## ブランチと commit

- 最新 main から、PR の型に合う `feat/` または `feature/`、`fix/`、`docs/`、`style/`、`refactor/`、`perf/`、`test/`、`chore/`、`build/`、`ci/`、`revert/` を使用します。例：`fix/download-timeout` または `ci/skip-directive-timing`。
- 英語の [Conventional Commits](https://www.conventionalcommits.org/) 形式、`type(scope): description` を使います。例：`fix(ui): resolve layout issue in notch area`。
- 一つのブランチ・PR は一つの明確な目的で、無関係な整形・リファクタリングを混ぜません。
- `publish-v*` は公開保守用、その他は main 向けです。

## Pull Request

レビューを待つ間、以下を確認してください。

- タイトルは英語 Conventional Commit です。例：`feat(ci): add PR quality gates`、`fix(mac): resolve memory leak in overlay`、`docs: update contributing guidelines`。型は feat/fix/docs/style/refactor/perf/test/chore/build/ci/revert。
- 本文も英語で、`.github/PULL_REQUEST_TEMPLATE.md` の Summary、GitHub Project、PR Type、Validation、Risk and Rollback、Related Issue、AI Attribution 七節を含めます。
  - Project は `- Project: zisla Development` を保持し、Project Automation がボードへ配置します。
  - Start date と Target date は一度ずつ実在 YYYY-MM-DD を記載し、Target は Start 以降です。欠損、空白、コメント内、重複、無効は PR Quality 失敗。Submitted date は UTC+08:00 の作成日、End date は merge 時に自動設定します。
  - `PR Type` は一つの `- Type:` を宣言し、タイトルと同じ正規型に対応させます。タイトルは正規型、本文は型ラベルと設定された別名も受け付けます。`fix`、`bug`、`bug fix`、`bugfix`、`hotfix` は `fix` に対応し、`PR Automation` が `bug` ラベルを付けます。
  - Status は型を含む設定ラベルから決定し、終了・merge は Done。手入力しません。
  - Summary は変更を説明し、Risk と Rollback は一つずつ非空で必要です。
  - Validation は各項目が `- Status: passed`、failed、not run から始まります。passed/failed は独自 Command と Result、not run は Reason が必要で、他項目から借りられません。失敗を正直に記載します。
  - Related Issue は Closes #123 のように閉じる参照（development ラベル）または正確な None。
  - `AI Attribution` は一つの非空 `- Agent:` を宣言します。`None` 以外は `- Co-authored-by: Name <email>` を本文と少なくとも一 commit trailer に一致させ、`ai-assisted` ラベルを付けます。

タイトル例：`fix(ci): validate every PR metadata entry`。本文例（実際の結果を使用）：

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

作成 2026-10-05、merge 2026-10-12 の例です。コメントの自動項目は説明用で入力ではなく、自動化は Project と Timeline を更新します。

| 項目 | 作成時 | merge 後 | 元 |
| --- | --- | --- | --- |
| Start date | 2026-10-05 | 2026-10-05 | 必須入力 |
| Target date | 2026-10-12 | 2026-10-12 | 必須入力 |
| Submitted date | 2026-10-05 | 2026-10-05 | 自動 |
| End date | 空欄 | 2026-10-12 | 自動 |

- PR Quality はこの形式を検証し、失敗中は merge できません。PR Automation がラベルと担当を設定します。
- macOS コードは `cd mac && swift test` を実行し、UI の手動確認は文字で説明します。
- PR とリリース説明は文字だけでも可。画像・カバーは不要です。
- 機能、動作、初期値、ビルド、公開変更は同じ patch で正式文書・17 言語 Web ヘルプを同期し、既存構造と集中翻訳ディレクトリーを使います。
- `.build`、dist、取得ファイル、ログ、token、署名・個人データを commit しません。
- main と publish-v* は保護され、検証済みレビュー PR だけで変更します。

## CI を省略する

影響しない検証だけを管理者・依頼されたレビュアーがコメントの独立行で指定できます。

| 指令 | 意味 |
| --- | --- |
| `skip-all` | manifest の全ワークフローを省略 |
| `skip-<workflow>` | 名前、ファイル、alias の一つを省略。例：`skip-swift`、`skip-web-ci`、`skip-Web CI` |
| `unskip-all` | すべて復元 |
| `unskip-<workflow>` | 一つを復元 |

- 後ろの自由文を許可します。例：`skip-all: documentation only change`。
- 空白を含む表示名を使え、`skip-CI Lint` と `skip-lint` は同じ。最長一致後を説明とします。
- owner、組織メンバー、共同作業者、依頼された reviewer のみ有効で、bot は無視。
- CI Skip は実行中を停止し、成功チェック、skip-ci ラベル、一つの要約コメントを更新します。
- 全コメントを再処理し、最新指令を優先します。
- 新しい commit の push で過去の指令は失効します。指令は作成者が確認したコードだけを対象にし、新コードが未ビルドで merge されるのを防ぐためです。`CI Skip` は push ごとに `skip-ci` を解除して検証を戻し、要約に失効した指令を記載します。新コードにも適用する場合は再コメントします。
- Actions → CI Skip → Run workflow に PR 番号を入れて現状を再適用できます。
- `.github/ci-skip.json` が全チェック名を所有し、差分は CI Checks 失敗です。

## パスによる検証

文書も所属パスに応じて確認します。

| ワークフロー | パス |
| --- | --- |
| Swift Tests | mac/**、Makefile、.swiftformat、.github/** |
| Web CI | web/**、promo/**、docs/**、.github/** |

- manifest paths が所有し、未指定は常に実行。CI Lint、PR Quality Gates、CodeQL、Dependency Review は全 PR で、衛生・skill は CI Checks。旧 hygiene/skills alias はありません。
- .github 変更はすべてを実行します。
- workflow の `paths:` フィルターではなく job 条件で省略し、required check が pending になりません。
- 改名は旧・新両パス、大文字小文字を無視して照合します。
