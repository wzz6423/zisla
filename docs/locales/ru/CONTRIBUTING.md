# Участие в zisla

[English](../../../CONTRIBUTING.md) | [简体中文](../../../CONTRIBUTING.zh-CN.md) | **Русский** | [Другие языки](../README.md)

Спасибо за участие в zisla.

## Сообщения о проблемах

Спасибо за создание issue. Сначала найдите существующие Issues и Discussions, чтобы не дублировать сообщения.

- Заголовок ошибки использует `[Bug] Short problem description`, например `[Bug] Voice input is not written to the current text field`. Укажите версию zisla, macOS и устройство, способ установки, шаги воспроизведения, ожидаемое и фактическое поведение.
- Заголовок запроса использует `[Feature] Short request description`, например `[Feature] Support custom voice-organization prompts`. Опишите проблему, решение и рассмотренные альтернативы.
- Выберите один обязательный **Area** формы, определяющий метку `area:*`: `Feature Development`, `Bug Fix`, `CI & Build`, `Documentation` или `Community & Discussion`. Формы на упрощённом китайском предлагают те же варианты и метки.
- Удалите токены, данные учётных записей, локальные пути и другую конфиденциальную информацию из журналов, снимков и записей.
- Сообщайте об уязвимостях приватно через [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), не публичный issue.
- Автоматизация добавляет `bug`/`enhancement` и соответствующую `area:*`, сохраняя остальные метки. Неверный префикс или обязательное поле добавляет `needs-more-info` и одну обновляемую при редактировании issue запись о недостающих данных.

## Разработка

Реализация macOS находится в `mac/` и требует macOS 14+ со Swift 6 / Xcode 16+.

```bash
cd mac
swift test
```

Удаляйте двоичные результаты тестов, сборки и упаковки перед коммитом.

Перед каждым коммитом или amend запускайте `make format` из корня со SwiftFormat 0.64.7, как в CI. Проверьте diff и сохраните только форматирование текущей задачи.

## Ветки и коммиты

- Создавайте ветки из последней `main` с префиксом типа PR: `feat/` (или `feature/`), `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `chore/`, `build/`, `ci/`, `revert/`; примеры: `fix/download-timeout` и `ci/skip-directive-timing`.
- Используйте английский формат [Conventional Commits](https://www.conventionalcommits.org/), например `type(scope): description` или `fix(ui): resolve layout issue in notch area`.
- Одна ветка и один PR должны иметь одну ясную цель; исключайте только форматирование и несвязанные рефакторинги.
- Ветки `publish-v*` предназначены для сопровождения выпуска. Остальные изменения направляются в `main`.

## Запрос на слияние

Спасибо за pull request. Во время ожидания проверки соблюдайте требования.

- **Заголовок PR** — английский Conventional Commit, например:
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  Допустимы `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci` и `revert`.

- **Текст PR** должен быть английским и содержать разделы `Summary`, `GitHub Project`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue`, `AI Attribution` из `.github/PULL_REQUEST_TEMPLATE.md`.
  - `GitHub Project` сохраняет `- Project: zisla Development` шаблона. `Project Automation` использует его для общей доски.
  - В `GitHub Project` обязательны `Start date` и `Target date`, каждая ровно один раз как действительная дата `YYYY-MM-DD`; целевая дата не раньше начальной. Отсутствие, пустота, комментарий вместо поля, повтор или неверная дата нарушают `PR Quality`. `Submitted date` автоматически берётся из создания в UTC+08:00, `End date` заполняется при слиянии; вручную их не вводят.
  - `PR Type` содержит ровно одно `- Type:`, соответствующее типу заголовка. Заголовок использует канонический тип; тело принимает метки и настроенные псевдонимы: `fix`, `bug`, `bug fix`, `bugfix`, `hotfix` все означают `fix`. `PR Automation` преобразует тип в метку, например `fix` в `bug`.
  - `Project Automation` выбирает `Status` по отображению меток, включая тип PR, и задаёт `Done` после закрытия/слияния. Вручную `Status` не вводят.
  - `Summary` описывает изменение; `Risk and Rollback` содержит ровно по одному непустому `Risk` и `Rollback`.
  - Каждая запись `Validation` начинается собственным `- Status:` со значением строго `passed`, `failed` или `not run`. Для `passed`/`failed` обязательны собственные непустые `Command` и `Result`; `not run` требует собственный `Reason`. Поля другой записи не засчитываются. Ошибки честно отмечаются `failed`.
  - `Related Issue` либо закрывает issue ключевым словом, например `Closes #123`, добавляя `development`, либо содержит точно `None`.
  - `AI Attribution` содержит ровно одно непустое `- Agent:`. Для agent, отличного от `None`, обязательна соответствующая строка `- Co-authored-by: Name <email>` и такой trailer хотя бы в одном коммите; применяется `ai-assisted`.

  Пример заголовка: `fix(ci): validate every PR metadata entry`

  Пример текста (укажите фактические результаты):

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

  Пример дат: PR создан 2026-10-05 и слит 2026-10-12 (UTC+08:00). Автоматические поля комментария показывают значения Project, а не входные данные. Автоматизация обновляет GitHub Project и PR Timeline, не строки примера.

  | Дата | При создании (2026-10-05) | После слияния (2026-10-12) | Источник |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | Обязательный ввод |
  | `Target date` | 2026-10-12 | 2026-10-12 | Обязательный ввод |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | Автоматическая дата создания |
  | `End date` | Пусто | 2026-10-12 | Автоматическая дата слияния |

- `PR Quality` проверяет формат; при ошибке PR нельзя слить. Затем `PR Automation` назначает метки и исполнителя.
- Для кода macOS выполняйте `cd mac && swift test`; изменения UI описывайте фактическими результатами ручной проверки.
- Текст PR и заметки выпуска могут содержать только текст; изображения, скриншоты и обложки не обязательны.
- Изменения функций, поведения, стандартных настроек, сборки и выпуска сопровождайте официальной документацией и помощью сайта в том же патче. Текст сайта охватывает все 17 языков; используйте имеющуюся помощь и каталог локализованных документов.
- Не коммитьте `.build`, `dist`, загрузки, журналы, токены, материалы подписи и личные данные.
- `main` и `publish-v*` защищены и обновляются только через проверенный PR с успешными проверками.

## Пропуск CI

Сопровождающие и запрошенные рецензенты могут пропускать проверки, на которые изменение не влияет, например чисто документальное. Запишите директиву отдельной строкой комментария PR:

| Директива | Действие |
| --- | --- |
| `skip-all` | Пропускает все процессы `.github/ci-skip.json`. |
| `skip-<workflow>` | Пропускает один процесс по имени, файлу или псевдониму: `skip-swift`, `skip-web-ci`, `skip-Web CI`. |
| `unskip-all` | Удаляет все директивы пропуска. |
| `unskip-<workflow>` | Восстанавливает один процесс. |

- После директивы допустим свободный текст, например `skip-all: documentation only change`.
- Имя процесса может совпадать с отображением GitHub, включая пробелы; `skip-CI Lint` и `skip-lint` равнозначны. Выбирается самое длинное совпадение; оставшиеся слова служат заметкой.
- Директивы принимаются лишь от владельца, члена организации, соавтора или запрошенного рецензента. Комментарии ботов игнорируются.
- `CI Skip` отменяет текущие запуски, сообщает пропущенные проверки успешными для обязательных условий, ставит `skip-ci` и редактирует один итоговый комментарий.
- При каждом комментарии переигрывается вся ветка; последнее указание побеждает.
- Новый коммит немедленно завершает действие старой директивы: она касается только уже просмотренного кода, иначе успешный статус разрешил бы слияние несобранного изменения. При каждом push `CI Skip` удаляет `skip-ci` и восстанавливает проверки; итог перечисляет истёкшие указания. Для нового коммита прокомментируйте снова.
- Сопровождающий может повторно применить решение через **Actions -> CI Skip -> Run workflow**, указав номер PR без нового комментария.
- `.github/ci-skip.json` сопоставляет процессы с публикуемыми именами проверок. Расхождение с файлами процессов нарушает `CI Checks`.

## Проверки по путям

Платформенный процесс выполняет проверки лишь при изменении файлов, которые собирает; документация проверяется по её расположению:

| Процесс | Изменения PR для запуска |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.swiftformat`, `.github/**` |
| `Web CI` | `web/**`, `promo/**`, `docs/**`, `.github/**` |

- Области задаёт `paths` в `.github/ci-skip.json`; процесс без областей выполняется всегда. `CI Lint`, `PR Quality Gates`, `CodeQL` и `Dependency Review` работают для каждого PR. Гигиена репозитория и проверка skills входят в `CI Checks`; старые псевдонимы `hygiene`/`skills` не используются.
- Любое изменение `.github/` запускает всё, поскольку CI проверяется на каждой платформе.
- Задания пропускаются условием job, не фильтром `paths:` процесса, чтобы обязательная проверка возвращала успех вместо бесконечного ожидания.
- Переименованный файл проверяется по старому и новому пути без учёта регистра.
