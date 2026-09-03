# 贡献指南

[English](CONTRIBUTING.md) | **简体中文**

感谢你为 zisla 做出贡献。

## 问题反馈

感谢你提交 Issue。开始前请搜索已有的 Issue 和 Discussions，避免重复提交。

- 缺陷报告标题使用 `[Bug] 简短问题描述`，例如 `[Bug] 语音输入结束后未写入当前文本框`。正文至少包含 zisla 版本、macOS 与设备、安装方式、复现步骤、预期行为和实际行为。
- 功能建议标题使用 `[Feature] 简短需求描述`，例如 `[Feature] 支持自定义语音整理提示词`。正文说明当前问题、建议方案和已考虑的替代方案。
- 日志、截图和录屏需先移除令牌、账号、本地路径等敏感信息。
- 安全漏洞请通过 [安全通告](https://github.com/wzz6423/zisla/security/advisories/new) 私下报告，不要公开提交 Issue。

## 开发

当前 macOS 实现在 `mac/` 目录中，依赖 macOS 14+ 与 Swift 6 / Xcode 16+。

```bash
cd mac
swift test
```

提交前请删除测试、构建和打包产生的二进制产物。

## 分支和提交

- 从最新的 `main` 创建分支，使用 `feature/`、`fix/`、`docs/` 或 `chore/` 前缀，例如 `fix/download-timeout`。
- 提交信息使用英文 [Conventional Commits](https://www.conventionalcommits.org/) 格式：`type(scope): description`，例如 `fix(ui): resolve layout issue in notch area`。
- 一个分支和一个 PR 应只处理一个明确目标；请避免混入格式化或无关重构。
- 发布分支 `publish-v*` 仅用于发布维护。除发布修复外，贡献请提交到 `main`。

## 拉取请求

感谢你提交 Pull Request。请在等待评审时确认以下要求。

- **PR 标题**必须使用英文 Conventional Commit 格式，例如：
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  允许的类型：`feat`、`fix`、`docs`、`style`、`refactor`、`perf`、`test`、`chore`、`build`、`ci`、`revert`。

- **PR 正文**必须使用英文，并包含 `.github/PULL_REQUEST_TEMPLATE.md` 提供的 `Summary`、`PR Type`、`Validation`、`Risk and Rollback`、`Related Issue`、`AI Attribution` 六节。
  - `PR Type` 只写一条 `- Type:`，且必须与标题中的类型一致。`PR Automation` 会据此打标签，例如 `fix` 对应 `bug`。
  - `Validation` 中每项都必须声明 `passed`、`failed` 或 `not run`：前两者需要 `Command` 与 `Result`，后者需要 `Reason`。
  - `Related Issue` 要么用 `Closes #123` 之类的关键字关联 Issue（同时自动打上 `development`），要么写成 `None`。
  - `AI Attribution` 必须声明 `- Agent:`。声明了具体 agent 时，必须补一条 `- Co-authored-by: Name <email>`，并且该 trailer 必须真实出现在至少一个 commit 上，同时会自动打上 `ai-assisted`。

  正文示例：

  ```markdown
  ## Summary
  - Add a repository hygiene check.

  ## PR Type
  - Type: ci

  ## Validation
  - Status: passed
  - Command: shellcheck .github/scripts/check-repository-hygiene.sh
  - Result: All checks passed.

  ## Risk and Rollback
  - Risk: Only repository automation is affected.
  - Rollback: Revert this pull request.

  ## Related Issue
  Closes #123

  ## AI Attribution
  - Agent: Claude Code
  - Co-authored-by: Claude <noreply@anthropic.com>
  ```

- `PR Quality` 检查会自动验证上述格式；状态检查未通过时不能合并。随后 `PR Automation` 负责打标签与指派。
- macOS 代码变更必须运行 `cd mac && swift test`；涉及界面时请补充实际验证说明或截图。
- 更新用户可见行为、构建方式或发布流程时，同步更新相应文档。
- 不要提交 `.build`、`dist`、下载文件、日志、令牌、签名材料或其他个人数据。
- `main` 和 `publish-v*` 受保护，只能通过检查并完成评审的 PR 合并。

## 跳过 CI

当改动确实不可能影响某些检查时（例如纯文档修改），维护者与被请求的 reviewer 可以跳过它们。在 PR 评论中单独一行写下指令：

| 指令 | 效果 |
| --- | --- |
| `skip-all` | 跳过 `.github/ci-skip.json` 中列出的所有工作流。 |
| `skip-<workflow>` | 按名称或别名跳过单个工作流，例如 `skip-swift`、`skip-web`。 |
| `unskip-all` | 取消所有跳过指令。 |
| `unskip-<workflow>` | 恢复单个工作流。 |

- 指令后面可以接自由文本，例如 `skip-all: documentation only change`。
- 只有仓库 owner、组织成员、协作者或被请求的 reviewer 的指令才生效，机器人评论一律忽略。
- `CI Skip` 会取消正在运行的任务，把被跳过的检查标记为成功以满足必需检查，打上 `skip-ci` 标签，并复用同一条评论汇总当前决策。
- 每次评论都会重放整个评论区，因此最新的指令始终生效。
- `.github/ci-skip.json` 记录了每个工作流发布的检查名；清单与工作流不一致时 `Test CI Scripts` 会失败。
