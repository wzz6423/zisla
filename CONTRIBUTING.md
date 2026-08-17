# 贡献指南

感谢你为 zisla 做出贡献。

## Issue

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

## Pull Request

感谢你提交 Pull Request。请在等待评审时确认以下要求。

- **PR 标题**必须使用英文 Conventional Commit 格式，例如：
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  允许的类型：`feat`、`fix`、`docs`、`style`、`refactor`、`perf`、`test`、`chore`、`build`、`ci`、`revert`。

- **PR 正文**必须使用英文并包含 `Summary`、`Validation`、`Risk and Rollback` 三节。`Validation` 中每项都必须声明 `passed`、`failed` 或 `not run`：
  - `passed` 或 `failed` 必须写明执行命令与实际结果。
  - `not run` 必须说明未执行的原因。

  正文示例：

  ```markdown
  ## Summary
  - Add a repository hygiene check.

  ## Validation
  - Status: passed
  - Command: shellcheck .github/scripts/check-repository-hygiene.sh
  - Result: All checks passed.

  ## Risk and Rollback
  - Risk: Only repository automation is affected.
  - Rollback: Revert this pull request.
  ```

- `PR Quality` 检查会自动验证上述格式；状态检查未通过时不能合并。

- 使用 PR 模板，说明变更、验证方式和关联 Issue。
- macOS 代码变更必须运行 `cd mac && swift test`；涉及界面时请补充实际验证说明或截图。
- 修改 `windows/` 时，CI 会在 Windows 上执行 CMake Core 测试，并编译 WinUI 应用。完整的 Windows 应用构建不会在 CI 中启动界面或访问用户数据。
- 更新用户可见行为、构建方式或发布流程时，同步更新相应文档。
- 不要提交 `.build`、`dist`、下载文件、日志、令牌、签名材料或其他个人数据。
- `main` 和 `publish-v*` 受保护，只能通过通过检查并完成评审的 PR 合并。
