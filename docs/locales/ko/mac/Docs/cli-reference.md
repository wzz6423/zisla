# `zislactl` 연동 참조

**한국어** | [English](../../../../../mac/Docs/cli-reference.md) | [简体中文](../../../../../mac/Docs/cli-reference.zh-CN.md) | [다른 언어](../../../README.md)

`zislactl`은 AI 도구, 스크립트와 CI 작업이 zisla와 연결하는 공통 로컬 상태 프로토콜입니다. 작업 상태, 사용량과 알림을 구조화 데이터로 쓰고 SQLite 트랜잭션에 저장해 부분적으로 기록된 상태를 방지합니다. 이 문서는 안정된 제공자, 명령과 필드 제약을 정의합니다.

## 설계 원칙

- 상태는 로컬에 기록하며 프롬프트, 답변 본문과 인증 정보를 업로드하지 않습니다.
- 같은 작업 ID의 업데이트는 멱등합니다. 읽는 쪽에는 완전히 커밋된 데이터베이스 상태가 보입니다.
- 제공자 이름은 호환 별칭을 허용하지만 정식 값으로 저장합니다.

## 저장과 JSON 경계

작업, 사용량과 알림은 `~/Library/Application Support/zisla/ai-state.sqlite`에 저장합니다. 쓰기는 SQLite 트랜잭션을 사용하며 현재 프로토콜은 `ai-state.json`을 쓰지 않습니다. 작업을 지워도 사용량 기록은 남습니다.

`zislactl`은 문서화된 명령행 옵션을 받으며 `list`는 한 줄씩 텍스트를 출력합니다. 외부 도구의 JSON/JSONL 세션과 설정의 JSON 인코딩·디코딩 등 연동과 구성에는 실제 구조화 JSON을 계속 사용하며 각 파싱 규칙을 따릅니다. CLI 자체는 명령행 인수, 텍스트 출력과 SQLite 저장을 사용합니다.

## 제공자

| 값 | 별칭 |
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

WorkBuddy와 WorkBuddy AI는 국내·해외 시장을 위한 별도 제품이며 같은 앱의 구버전·신버전이 아닙니다. 정식 제공자, 저장소, 아이콘과 딥 링크를 분리해야 합니다. `harness`를 사용한 이전 WorkBuddy 기록은 계속 읽을 수 있지만 해당 제공자를 전체적으로 이름 변경하거나 이전하지 않습니다. 활동 알림 ID는 `ai-active-workbuddy:<id>` 또는 `ai-active-workbuddy-ai:<id>`처럼 제공자와 작업을 명시적으로 나눕니다. 따라서 ID가 `ai-`로 시작하는 수동 WorkBuddy 작업을 WorkBuddy AI로 오인하지 않습니다.

### Delta, Orca, WorkBuddy와 WorkBuddy AI 자동 감지

- Delta는 `Library/Application Support/Delta/user_*/data.sqlite`와 이전 루트 DB에서 스트리밍 스레드의 색인 메타데이터를 읽습니다. 보관, 유휴 또는 오래된 스레드는 제외합니다. 숫자 사용량은 캐시 읽기·쓰기를 포함한 `app_model_usage_daily` 장부에서 가져옵니다. 이 장부가 없는 릴리스는 자동 사용량을 표시하지 않으며 대화 내용에서 수치를 추정하지 않습니다.
- Orca는 로컬 `agent-hooks/last-status.json` 스냅샷과 `agent-session-journal.db`의 현재 구조화 대화 턴 상태를 읽습니다. 프로필 디렉터리와 v1/v2/v3 기록을 지원하며 가장 높은 리비전과 원래 턴 순서를 지킵니다. 완료, 만료, 원격 또는 식별 정보만 있는 세션은 제외합니다. 신뢰할 수 있는 전사 경로와 고정된 Claude/Codex 계정 홈도 토큰 사용량에 기여합니다. 이 표본은 원래 CLI 제공자와 이벤트 ID를 유지하므로 일반 CLI 감지가 중복 계산하지 않습니다. Orca의 기기 전체 사용량 캐시는 추가 사용량으로 가져오지 않습니다.
- WorkBuddy는 `~/.workbuddy/workbuddy.db`만 읽고 `workbuddy` 제공자, WorkBuddy 아이콘과 `workbuddy://chat/<id>` 링크를 사용합니다. WorkBuddy AI 저장소를 검사하지 않습니다.
- WorkBuddy AI는 `~/.workbuddy-ai/workbuddy.db`에서 세션 상태, 제목, 모델과 시각을 읽으며 WorkBuddy 저장소와 독립적입니다. 완료, 삭제 또는 오래된 세션은 제외합니다. `updated_at`과 `last_activity_at` 중 최근 값으로 장기 실행 세션을 유지합니다. 작업은 `workbuddy-ai`, WorkBuddy AI 아이콘과 `workbuddy-ai://chat/<id>`를 사용합니다. 이 연동은 세션만 감지합니다. `session_usage.used`는 컨텍스트 점유율이며 크레딧은 USD·토큰 사용량이 아니므로 청구 토큰으로 가져오지 않습니다. 수동 숫자 사용량은 `zislactl usage`로 보고합니다.
- 모든 연동은 읽기 전용이며 가능한 범위에서 감지합니다. 없거나 호환되지 않는 저장소는 데이터 없음으로 처리합니다. 복제된 Delta 스레드 본문과 Orca 저널의 메시지 본문은 조회하지 않습니다. 기록된 숫자 사용량이 없는 도구·버전은 `zislactl usage`를 사용하세요.

## 인수 표기

- 옵션은 `--key value` 또는 `--key=value`로 씁니다. 명령마다 각 옵션은 한 번만 허용하며 중복은 사용 오류, 종료 코드 64입니다.
- 값은 `--detail --verbose`처럼 `--`로 시작할 수 있습니다. 같은 명령의 플래그인 `finish`의 `--failed`와 `update`의 `--queued`는 예외로 값으로 소비하지 않습니다. 따라서 따옴표 없는 빈 변수 `--detail $DETAIL --failed`도 작업을 실패로 표시합니다. 그 문자열 자체가 값이면 `--detail=--failed`로 전달하세요.
- `--failed`와 `--queued`는 플래그입니다. 단독 사용은 참이며 `--failed=false` 또는 `--failed false`는 끕니다. `--queued`도 같습니다. 다른 값은 사용 오류입니다.

## `update`

같은 `id`의 작업을 생성하거나 교체합니다.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- `--progress`가 없으면 진행은 불확정으로 표시합니다.
- `--pid`는 선택 사항이며 호출자가 작업 프로세스를 식별할 때만 지정합니다.
- `--status`는 실행 중, 대기열, 사용자 작업 대기 또는 실행 중 오류를 명시합니다.
- `--queued`는 `--status queued`의 별칭입니다. 명시적 상태가 없으면 실행 중이며 명시한 `--status`가 `--queued`보다 우선합니다.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

성공한 작업은 100%로 설정하고 실패한 작업은 마지막 진행 값을 유지합니다.

## `remove`

```text
zislactl remove --id <id>
```

작업이 없으면 종료 코드 65를 반환합니다.

## `clear`

```text
zislactl clear
```

작업을 지우고 사용량 기록과 알림은 유지합니다.

## `list`

```text
zislactl list
```

현재 작업 상태, 제공자, 제목과 퍼센트를 한 줄씩 출력합니다.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

사용량은 12시간 차트와 7x24 히트맵에 반영됩니다.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

알림은 선택한 쪽에서 나타나며 포인터를 올리면 자동 닫기를 일시 중지합니다.

## `message`

하나의 메시지 알림을 양쪽에 보냅니다. 왼쪽은 앱 로고와 발신자, 오른쪽은 스크롤되는 본문을 표시합니다.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

예제:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender`와 `--content`는 필수입니다. 선택적 `--app-bundle-id`는 설치된 앱의 아이콘을 찾는 데 도움이 됩니다.
- 줄바꿈과 불필요한 공백을 합치고 본문을 약 48자로 줄여 말줄임표를 붙입니다.
- 하나의 SQLite 트랜잭션으로 두 `IslandNotice`를 저장하며 기존 `notify` 동작은 유지합니다.

## 종료 코드

| 코드 | 의미 |
| --- | --- |
| `0` | 성공 |
| `64` | 잘못된 인수 또는 하위 명령 |
| `65` | 데이터 오류, 없는 작업 또는 손상된 DB |
| `70` | 파일 시스템 또는 다른 런타임 오류 |
