# zisla 기여하기

[English](../../../CONTRIBUTING.md) | [简体中文](../../../CONTRIBUTING.zh-CN.md) | **한국어** | [다른 언어](../README.md)

zisla에 기여해 주셔서 감사합니다.

## Issue

Issue를 열기 전에 기존 Issues와 Discussions를 검색해 중복 보고를 피하세요.

- Bug는 [Bug] Short problem description, 예 [Bug] Voice input is not written to the current text field입니다. 버전·macOS·기기·설치·재현·예상·실제 행동을 적습니다.
- Feature는 [Feature] Short request description, 예 [Feature] Support custom voice-organization prompts입니다. 문제·제안·대안을 설명합니다.
- 필수 Area를 하나 선택합니다: Feature Development, Bug Fix, CI & Build, Documentation, Community & Discussion. 간체 중국어 양식도 같은 선택지를 제공하며 동일한 `area:*` 라벨에 연결됩니다.
- 로그·그림·녹화에서 token·계정·로컬 경로와 민감정보를 뺍니다.
- 보안 문제는 공개 대신 [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new)로 보고합니다.
- 자동화는 `bug` 또는 `enhancement`와 해당 `area:*`를 적용하며 다른 라벨은 유지합니다. 제목 접두어나 필수 필드가 양식을 따르지 않으면 `needs-more-info`를 추가하고 부족한 정보를 한 댓글에 표시합니다. Issue를 수정하면 그 댓글도 갱신됩니다.

## 개발

현재 구현은 mac/, macOS 14+, Swift 6/Xcode 16+입니다.

```bash
cd mac
swift test
```

commit 전 테스트·빌드·패키지 바이너리를 지웁니다. 모든 commit/amend 전에 CI와 같은 SwiftFormat 0.64.7로 루트 make format을 실행하고 작업 관련 서식만 유지합니다.

## 브랜치와 커밋

- 최신 main에서 PR 타입별 feat/(또는 feature/), fix/, docs/, style/, refactor/, perf/, test/, chore/, build/, ci/, revert/를 씁니다. 예 fix/download-timeout 또는 ci/skip-directive-timing.
- 영어 [Conventional Commits](https://www.conventionalcommits.org/) `type(scope): description` 형식입니다. 예: `fix(ui): resolve layout issue in notch area`.
- 한 브랜치·PR은 한 목적, 서식만 변경이나 무관한 리팩터링은 피합니다.
- publish-v*는 출시 유지보수, 나머지는 main입니다.

## Pull Request

리뷰 대기 동안 다음을 확인합니다.

- 제목은 영어 Conventional Commit입니다. feat(ci): add PR quality gates, fix(mac): resolve memory leak in overlay, docs: update contributing guidelines. 허용 타입은 feat/fix/docs/style/refactor/perf/test/chore/build/ci/revert.
- 본문도 영어이며 `.github/PULL_REQUEST_TEMPLATE.md`의 Summary, GitHub Project, PR Type, Validation, Risk and Rollback, Related Issue, AI Attribution 7절입니다.
  - `GitHub Project`는 `- Project: zisla Development`를 유지하며 `Project Automation`이 공유 보드에 배치합니다.
  - Start date와 Target date는 각각 한 번, 실제 YYYY-MM-DD, Target≥Start. 누락·빈·주석·중복·잘못된 날짜는 실패입니다. Submitted는 UTC+08 생성일, End는 merge 후 자동입니다.
  - `PR Type`에는 정확히 하나의 `- Type:`을 쓰며 제목의 정식 타입과 일치해야 합니다. 제목은 정식 타입을, 본문은 타입 라벨과 설정된 별칭도 허용합니다. `fix`, `bug`, `bug fix`, `bugfix`, `hotfix`는 모두 `fix`로 해석하며 `PR Automation`이 `bug` 라벨을 적용합니다.
  - Status는 타입 포함 라벨 매핑, 종료·merge는 Done, 직접 쓰지 않습니다.
  - Summary 설명 및 Risk/Rollback 각각 한 비어있지 않은 필드가 필요합니다.
  - 각 `Validation` 항목은 자체 `- Status:`로 시작하고 정확히 `passed`, `failed`, `not run` 중 하나를 씁니다. `passed`·`failed`에는 각각 비어 있지 않은 `Command`와 `Result`, `not run`에는 `Reason`이 필요합니다. 다른 항목의 필드는 사용할 수 없으며 실패는 `failed`로 보고합니다.
  - `Related Issue`는 `Closes #123` 같은 닫기 참조로 `development` 라벨을 적용하거나 정확히 `None`으로 씁니다.
  - `AI Attribution`에는 하나의 비어 있지 않은 `- Agent:`를 씁니다. `None`이 아니면 본문에 `- Co-authored-by: Name <email>`을 쓰고 같은 내용을 최소 한 커밋의 trailer에 넣어 `ai-assisted`를 표시합니다.

제목 예: fix(ci): validate every PR metadata entry. 본문 예는 실제 결과로 채웁니다:

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

2026-10-05 생성, 2026-10-12 merge 예입니다. 주석의 자동 날짜는 입력이 아니라 설명이며 Project와 Timeline만 업데이트합니다.

| 필드 | 생성 | 병합 | 원천 |
| --- | --- | --- | --- |
| Start date | 2026-10-05 | 2026-10-05 | 필수 |
| Target date | 2026-10-12 | 2026-10-12 | 필수 |
| Submitted date | 2026-10-05 | 2026-10-05 | 자동 |
| End date | 비어있음 | 2026-10-12 | 자동 |

- PR Quality 실패 중 merge 불가, PR Automation 라벨과 할당입니다.
- macOS 변경은 cd mac && swift test, UI 실사용은 텍스트로 결과를 적습니다.
- PR·릴리스는 텍스트만 가능, 그림·표지는 불필요입니다.
- 기능·행동·기본값·빌드·출시 변경은 같은 patch에서 정식 문서와 17언어 웹 도움말을 동기화합니다. 기존 도움말과 집중 번역 폴더를 씁니다.
- .build·dist·다운로드·로그·token·서명·개인정보를 commit하지 않습니다.
- main/publish-v*는 보호되며 검사를 통과한 리뷰 PR만 변경합니다.

## CI 건너뛰기

영향이 없을 때 유지관리자와 요청 reviewer가 댓글의 독립 행으로 지정합니다.

| 명령 | 효과 |
| --- | --- |
| `skip-all` | `.github/ci-skip.json`의 모든 워크플로 생략 |
| `skip-<workflow>` | 이름·파일·별칭 하나 생략. 예: `skip-swift`, `skip-web-ci`, `skip-Web CI` |
| `unskip-all` | 전체 복원 |
| `unskip-<workflow>` | 하나 복원 |

- 뒤에 자유 문장 가능, 예 skip-all: documentation only change.
- 표시 이름의 공백 포함, skip-CI Lint와 skip-lint 동일. 가장 긴 이름 뒤를 이유로 봅니다.
- owner·조직·협업자·요청 reviewer만 유효, bot 무시.
- CI Skip은 실행을 취소하고 성공 체크, skip-ci 라벨과 하나 요약을 갱신합니다.
- 전체 댓글을 재생해 최근 명령 우선.
- 새 커밋을 푸시하면 이전 지시가 만료됩니다. 지시는 작성자가 본 코드에만 적용되므로 새 코드가 빌드 없이 병합되는 것을 막습니다. `CI Skip`은 푸시마다 `skip-ci`를 지우고 검사를 복구하며 요약 댓글에 만료된 지시를 표시합니다. 새 커밋도 건너뛰려면 지시를 다시 댓글로 남깁니다.
- Actions→CI Skip→Run workflow에서 PR 번호로 재적용합니다.
- manifest 검사명과 실제가 다르면 CI Checks 실패입니다.

## 경로별 검사

문서도 소유 경로에 따라 실행합니다.

| 워크플로 | 경로 |
| --- | --- |
| Swift Tests | mac/**, Makefile, .swiftformat, .github/** |
| Web CI | web/**, promo/**, docs/**, .github/** |

- paths가 기준, 미선언은 항상. CI Lint, PR Quality Gates, CodeQL, Dependency Review는 모든 PR입니다. 위생·skill은 CI Checks이고 옛 hygiene/skills 별칭은 없습니다.
- .github 변경은 모든 플랫폼을 검사합니다.
- 워크플로의 `paths:` 필터 대신 작업 조건으로 건너뛰므로 필수 검사가 계속 대기하지 않고 성공을 보고합니다.
- 이름 변경은 양쪽 경로와 대소문자 무시입니다.
