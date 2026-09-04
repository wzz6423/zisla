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

- The **PR body** must be in English and contain the `Summary`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue`, and `AI Attribution` sections that `.github/PULL_REQUEST_TEMPLATE.md` provides.
  - `PR Type` declares exactly one `- Type:` value, and it must match the type in the title. `PR Automation` turns it into a label, for example `fix` into `bug`.
  - Every `Validation` block must declare `passed`, `failed`, or `not run`. `passed` and `failed` need `Command` and `Result`; `not run` needs `Reason`.
  - `Related Issue` must either close an issue with a keyword such as `Closes #123`, which also applies the `development` label, or be exactly `None`.
  - `AI Attribution` must declare `- Agent:`. Any agent other than `None` requires a matching `- Co-authored-by: Name <email>` line, which must also appear as a trailer on at least one commit, and applies the `ai-assisted` label.

  Example:

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

- The `PR Quality` check validates this format; a pull request cannot be merged while the check is failing. `PR Automation` then applies the labels and assigns the pull request.
- Run `cd mac && swift test` for macOS code changes; include manual verification or screenshots for UI changes.
- Update the relevant documentation when changing user-visible behavior, build instructions, or the release process.
- Do not commit `.build`, `dist`, downloaded files, logs, tokens, signing materials, or personal data.
- `main` and `publish-v*` are protected and can only be updated through a reviewed pull request that passes its checks.

## Skipping CI

Maintainers and requested reviewers can skip checks that a change cannot affect, for example a documentation-only fix. Write the directive on its own line in a pull request comment:

| Directive | Effect |
| --- | --- |
| `skip-all` | Skips every workflow listed in `.github/ci-skip.json`. |
| `skip-<workflow>` | Skips one workflow by name, file name or alias, such as `skip-swift`, `skip-web-ci` or `skip-Web CI`. |
| `unskip-all` | Clears every skip directive. |
| `unskip-<workflow>` | Restores one workflow. |

- Free text may follow the directive, for example `skip-all: documentation only change`.
- A workflow may be named the way GitHub displays it, spaces included, so `skip-Repository Hygiene` and `skip-hygiene` are the same directive. The longest name that matches wins and the words left over become the note.
- Directives are honored only from the repository owner, an organization member, a collaborator, or a requested reviewer. Bot comments are ignored.
- `CI Skip` cancels the runs in flight, reports the skipped checks as successful so the required checks stay satisfied, applies the `skip-ci` label, and edits one summary comment with the current decision.
- The whole comment thread is replayed on every comment, so the newest directive always wins.
- A maintainer can re-apply the current decision without a new comment from **Actions -> CI Skip -> Run workflow**, passing the pull request number.
- `.github/ci-skip.json` maps each workflow to the check names it publishes. `Test CI Scripts` fails when the manifest drifts from the workflow files.

## Path-scoped checks

A platform workflow only runs when the pull request touches the files it builds, so a documentation change never boots a Windows or macOS runner:

| Workflow | Runs when the pull request touches |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.github/**` |
| `Core Tests` | `windows/**`, `.github/**` |
| `Web CI` | `web/**`, `.github/**` |
| `Skill CI` | `skills/**`, `.github/**` |

- The `paths` field of `.github/ci-skip.json` owns the scopes, and a workflow that declares none always runs. `CI Lint`, `Repository Hygiene`, `PR Quality Gates`, `CodeQL` and `Dependency Review` therefore run on every pull request.
- Any change under `.github/` runs everything, because a change to CI must be proven against every platform.
- The jobs are skipped by a job condition instead of a workflow `paths:` filter, so a required check reports success rather than staying pending forever.
- A renamed file is matched under both its old and its new path, and the comparison ignores case.
