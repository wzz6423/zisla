# Contributing to zisla

**English** | [简体中文](CONTRIBUTING.zh-CN.md)

Thank you for contributing to zisla.

## Issue

Thank you for opening an issue. Search existing Issues and Discussions first so that reports are not duplicated.

- Use `[Bug] Short problem description` for bug reports, for example `[Bug] Voice input is not written to the current text field`. Include the zisla version, macOS version and device, installation method, reproduction steps, expected behavior, and actual behavior.
- Use `[Feature] Short request description` for feature requests, for example `[Feature] Support custom voice-organization prompts`. Describe the problem, the proposed solution, and alternatives you considered.
- Remove tokens, account details, local paths, and other sensitive information from logs, screenshots, and recordings.
- Report security vulnerabilities privately through [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new) instead of opening a public issue.

## Development

The current macOS implementation is in `mac/` and requires macOS 14+ with Swift 6 / Xcode 16+.

```bash
cd mac
swift test
```

Remove test, build, and packaging binaries before committing.

## Branches and commits

- Create branches from the latest `main` and use a `feature/`, `fix/`, `docs/`, or `chore/` prefix, such as `fix/download-timeout`.
- Use the English [Conventional Commits](https://www.conventionalcommits.org/) format, such as `type(scope): description` or `fix(ui): resolve layout issue in notch area`.
- Keep one branch and one pull request focused on one clear goal; avoid formatting-only changes and unrelated refactors.
- `publish-v*` branches are reserved for release maintenance. Submit all other contributions to `main`.

## Pull Request

Thank you for opening a pull request. Check these requirements while it is awaiting review.

- The **PR title** must use an English Conventional Commit subject, for example:
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  Allowed types are `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci`, and `revert`.

- The **PR body** must be in English and contain `Summary`, `Validation`, and `Risk and Rollback` sections. Every `Validation` item must declare `passed`, `failed`, or `not run`:
  - `passed` and `failed` entries must include the command and observed result.
  - `not run` entries must explain why the check was not run.

  Example:

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

- The `PR Quality` check validates this format; a pull request cannot be merged while the check is failing.
- Use the PR template to describe the change, validation, and related issue.
- Run `cd mac && swift test` for macOS code changes; include manual verification or screenshots for UI changes.
- Update the relevant documentation when changing user-visible behavior, build instructions, or the release process.
- Do not commit `.build`, `dist`, downloaded files, logs, tokens, signing materials, or personal data.
- `main` and `publish-v*` are protected and can only be updated through a reviewed pull request that passes its checks.
