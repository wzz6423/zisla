# Contribuire a zisla

**Italiano** | [English](../../../CONTRIBUTING.md) | [简体中文](../../../CONTRIBUTING.zh-CN.md) | [Altre lingue](../README.md)

Grazie per contribuire a zisla.

## Issue

Prima di aprire una issue, cerca tra Issue e Discussions esistenti per evitare duplicati.

- Bug: titolo `[Bug] Short problem description`, per esempio `[Bug] Voice input is not written to the current text field`. Includi versione zisla, versione macOS e dispositivo, installazione, passi di riproduzione, risultato atteso e reale.
- Funzioni: `[Feature] Short request description`, per esempio `[Feature] Support custom voice-organization prompts`. Descrivi problema, soluzione proposta e alternative considerate.
- Scegli un'**Area** obbligatoria: determina `area:*` ed è `Feature Development`, `Bug Fix`, `CI & Build`, `Documentation` o `Community & Discussion`. I moduli cinesi offrono equivalenti mappati alle stesse etichette.
- Rimuovi token, account, percorsi locali e dati sensibili da registri, screenshot e video.
- Segnala vulnerabilità privatamente tramite [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), non con issue pubbliche.
- L'automazione applica `bug` o `enhancement` e l'`area:*` corrispondente, lasciando altre etichette intatte. Prefisso o campi non validi aggiungono `needs-more-info` e un singolo commento sulle informazioni mancanti; modificando la issue il commento si aggiorna.

## Sviluppo

Il codice macOS attuale è in `mac/` e richiede macOS 14+, Swift 6 / Xcode 16+.

```bash
cd mac
swift test
```

Prima del commit rimuovi binari di test, build e pacchetti.

Prima di ogni commit o amend, esegui `make format` dalla radice con SwiftFormat 0.64.7, come CI. Esamina il diff e conserva solo la formattazione necessaria al compito.

## Branch e commit

- Crea branch dall'ultimo `main`, con il tipo della PR: `feat/` o `feature/`, `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `chore/`, `build/`, `ci/`, `revert/`. Esempi: `fix/download-timeout`, `ci/skip-directive-timing`.
- Usa [Conventional Commits](https://www.conventionalcommits.org/) in inglese, come `type(scope): description` o `fix(ui): resolve layout issue in notch area`.
- Una branch e una PR per un obiettivo chiaro. Evita sola formattazione e refactoring estranei.
- `publish-v*` è riservato alla manutenzione dei rilasci; altri contributi vanno a `main`.

## Pull Request

Verifica questi requisiti mentre la PR attende revisione.

- **Titolo:** Conventional Commit inglese, per esempio `feat(ci): add PR quality gates`, `fix(mac): resolve memory leak in overlay`, `docs: update contributing guidelines`. Tipi consentiti: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci`, `revert`.
- **Corpo:** inglese, con `Summary`, `GitHub Project`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue`, `AI Attribution` dal template `.github/PULL_REQUEST_TEMPLATE.md`.
  - `GitHub Project` mantiene `- Project: zisla Development`, usato da `Project Automation` per la board comune.
  - `Start date` e `Target date` obbligatorie una sola volta, date reali `YYYY-MM-DD`; target non precedente allo start. Assenti, vuote, commentate, duplicate o invalide falliscono `PR Quality`. `Submitted date` usa automaticamente la creazione UTC+08:00; `End date` viene inserita alla fusione. Non servono manualmente.
  - `PR Type` contiene un solo `- Type:` coerente col titolo. Titolo canonico; corpo ammette etichette/alias configurati. `fix`, `bug`, `bug fix`, `bugfix`, `hotfix` risolvono `fix`. `PR Automation` applica l'etichetta, ad esempio `bug`.
  - `Project Automation` determina `Status` dalla mappatura, incluso tipo PR; chiusa o fusa diventa `Done`. Non inserirlo manualmente.
  - `Summary` descrive la modifica; rischi contengono esattamente un `Risk` e un `Rollback` non vuoti.
  - Ogni verifica ha un proprio `- Status:`: soltanto `passed`, `failed`, `not run`. Passed/failed richiedono `Command` e `Result` non vuoti; not run richiede `Reason`. Campi di un'altra voce non valgono. Dichiarare gli errori come `failed`.
  - `Related Issue` chiude un'issue con una parola come `Closes #123`, che applica anche `development`, oppure è esattamente `None`.
  - `AI Attribution` ha un solo `- Agent:` non vuoto. Se diverso da `None`, serve `- Co-authored-by: Name <email>` corrispondente anche nel trailer di almeno un commit, applicando `ai-assisted`.

  Titolo di esempio: `fix(ci): validate every PR metadata entry`

  Corpo di esempio, con risultati di verifica reali:

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

  L'esempio assume creazione il 2026-10-05 e fusione il 2026-10-12, UTC+08:00. I campi automatici nel commento illustrano valori Project, non sono input; l'automazione aggiorna Project e Timeline, non quei commenti.

  | Campo | Alla creazione (2026-10-05) | Dopo fusione (2026-10-12) | Fonte |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | Input richiesto |
  | `Target date` | 2026-10-12 | 2026-10-12 | Input richiesto |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | Creazione automatica |
  | `End date` | Vuoto | 2026-10-12 | Fusione automatica |

- `PR Quality` verifica il formato e impedisce la fusione se fallisce; `PR Automation` assegna etichette e PR.
- Per codice macOS esegui `cd mac && swift test`; per interfacce descrivi le verifiche manuali.
- Corpo PR e note di rilascio possono essere solo testo; immagini e copertine non sono obbligatorie.
- Se cambiano funzioni, comportamenti, valori predefiniti, build o rilasci, aggiorna documenti formali e aiuto del sito nella stessa patch. Il testo del sito copre 17 lingue; riusa struttura dell'aiuto e directory localizzata.
- Non committare `.build`, `dist`, download, log, token, firme o dati personali.
- `main` e `publish-v*` sono protetti: solo PR revisionate e con verifiche riuscite.

## Saltare CI

Manutentori e revisori richiesti possono saltare controlli non influenzati, per esempio per soli documenti. Scrivi la direttiva su una riga autonoma del commento PR:

| Direttiva | Effetto |
| --- | --- |
| `skip-all` | Salta ogni workflow di `.github/ci-skip.json`. |
| `skip-<workflow>` | Salta per nome/file/alias, come `skip-swift`, `skip-web-ci`, `skip-Web CI`. |
| `unskip-all` | Rimuove tutte le direttive. |
| `unskip-<workflow>` | Ripristina un workflow. |

- Può seguire una nota, per esempio `skip-all: documentation only change`.
- Sono ammessi nomi visibili GitHub con spazi: `skip-CI Lint` e `skip-lint` equivalgono. Vince il nome più lungo; il resto è nota.
- Solo proprietario, membro dell'organizzazione, collaboratore o revisore richiesto sono autorizzati. I bot vengono ignorati.
- `CI Skip` annulla esecuzioni attive, riporta successo per i controlli saltati, applica `skip-ci` e aggiorna un unico riepilogo.
- A ogni commento rilegge la conversazione: prevale la direttiva più recente.
- Una direttiva scade quando arriva un commit nuovo: riguarda solo codice già visto e altrimenti consentirebbe fusione senza build. A ogni push `CI Skip` rimuove `skip-ci`, ripristina i check e elenca direttive scadute; ripeti il commento per il nuovo commit.
- Si può riapplicare dalla schermata **Actions -> CI Skip -> Run workflow** con il numero PR.
- `.github/ci-skip.json` mappa workflow e check; `CI Checks` fallisce se il manifest diverge dai file.

## Controlli per percorso

I workflow di piattaforma eseguono i controlli soltanto per percorsi che compilano; i documenti seguono il proprietario del percorso.

| Workflow | Percorsi della PR |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.swiftformat`, `.github/**` |
| `Web CI` | `web/**`, `promo/**`, `docs/**`, `.github/**` |

- `paths` in `.github/ci-skip.json` è la fonte. Senza scope il workflow gira sempre: `CI Lint`, `PR Quality Gates`, `CodeQL`, `Dependency Review`. Igiene e validazione skill sono in `CI Checks`; vecchi alias `hygiene`/`skills` non si usano più.
- Ogni modifica `.github/` esegue tutto per verificare CI su ogni piattaforma.
- Condizioni sui job, non filtro workflow `paths:`, fanno riportare successo ai requisiti anziché lasciarli pendenti.
- Le rinomine verificano percorso vecchio e nuovo senza distinzione maiuscole/minuscole.
