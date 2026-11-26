# Bijdragen aan zisla

**Nederlands** | [English](../../../CONTRIBUTING.md) | [简体中文](../../../CONTRIBUTING.zh-CN.md) | [Andere talen](../README.md)

Bedankt voor je bijdrage.

## Issue

Zoek vóór openen bestaande Issues en Discussions om dubbele meldingen te voorkomen.

- Bugtitel `[Bug] Short problem description`, bijvoorbeeld `[Bug] Voice input is not written to the current text field`. Vermeld zisla/macOS-versie, apparaat, installatie, stappen, verwacht en werkelijk gedrag.
- Functietitel `[Feature] Short request description`, bijvoorbeeld `[Feature] Support custom voice-organization prompts`. Beschrijf probleem, oplossing en overwogen alternatieven.
- Kies één verplichte **Area**: bepaalt `area:*`, met `Feature Development`, `Bug Fix`, `CI & Build`, `Documentation`, `Community & Discussion`. Chinese formulieren geven dezelfde opties en labels.
- Verwijder tokens, accounts, lokale paden en gevoelige informatie uit log, afbeeldingen en opnames.
- Meld kwetsbaarheden privé via [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), niet openbaar.
- Automatisering zet `bug`/`enhancement` met de passende `area:*` en laat andere labels staan. Ongeldig voorvoegsel of vereist veld zet `needs-more-info` en één commentaar met ontbrekende informatie, bijgewerkt zodra de issue verandert.

## Ontwikkeling

macOS-code staat in `mac/`, vereist macOS 14+ en Swift 6 / Xcode 16+.

```bash
cd mac
swift test
```

Verwijder test-, bouw- en pakketbinaries vóór commit.

Voer vóór iedere commit of amend `make format` uit vanaf de root met SwiftFormat 0.64.7, gelijk aan CI. Bekijk de diff en behoud alleen benodigde opmaak.

## Branches en commits

- Maak vanaf nieuwste `main` met PR-typevoorvoegsel: `feat/` of `feature/`, `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `chore/`, `build/`, `ci/`, `revert/`. Bijvoorbeeld `fix/download-timeout` of `ci/skip-directive-timing`.
- Gebruik Engelse [Conventional Commits](https://www.conventionalcommits.org/), bijvoorbeeld `type(scope): description` of `fix(ui): resolve layout issue in notch area`.
- Houd één branch/PR gericht op één doel; vermijd alleen-opmaak en ongerelateerde refactors.
- `publish-v*` is voor releases; overige bijdragen gaan naar `main`.

## Pull Request

Controleer deze eisen tijdens wachten op review.

- **Titel:** Engelse Conventional Commit, bijvoorbeeld `feat(ci): add PR quality gates`, `fix(mac): resolve memory leak in overlay`, `docs: update contributing guidelines`. Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci`, `revert`.
- **Beschrijving:** Engels en alle templateonderdelen `Summary`, `GitHub Project`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue`, `AI Attribution` uit `.github/PULL_REQUEST_TEMPLATE.md`.
  - Houd `- Project: zisla Development`; `Project Automation` gebruikt dit voor het gedeelde bord.
  - `Start date`/`Target date` zijn elk eenmaal verplicht als echte `YYYY-MM-DD`, target niet vóór start. Afwezig, leeg, uit-gecommentarieerd, dubbel of ongeldig faalt `PR Quality`. `Submitted date` is automatisch aanmaakdatum UTC+08:00; `End date` merge-datum. Niet handmatig invullen.
  - Eén `- Type:` dat naar titeltype oplost. Titel canoniek; body accepteert labelnamen/aliassen. `fix`, `bug`, `bug fix`, `bugfix`, `hotfix` worden `fix`, door `PR Automation` naar label `bug`.
  - Automatisering kiest `Status` uit labelmapping inclusief PR-type, en zet gesloten/merged op `Done`; niet handmatig invoeren.
  - `Summary` beschrijft wijziging; `Risk and Rollback` bevat precies één niet-leeg `Risk` en `Rollback`.
  - Elke validatie begint met eigen `- Status:` van exact `passed`, `failed`, `not run`. Passed/failed vereisen eigen niet-lege `Command`/`Result`; not run eigen `Reason`. Velden uit andere entries tellen niet; fouten eerlijk `failed`.
  - `Related Issue` sluit met bijvoorbeeld `Closes #123`, wat ook `development` toepast, of is exact `None`.
  - Eén niet-leeg `- Agent:`. Anders dan `None` vraagt passende `- Co-authored-by: Name <email>`, ook als trailer in minimaal één commit, en label `ai-assisted`.

  Voorbeeldtitel: `fix(ci): validate every PR metadata entry`

  Voorbeeldbody: registreer echte validatieresultaten.

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

  Voorbeeld: gemaakt 2026-10-05, samengevoegd 2026-10-12, UTC+08:00. Automatische velden in commentaar zijn Project-illustratie, geen invoer. Automatisering past Project en Timeline aan, niet samplecommentaar.

  | Datum | Aanmaak (2026-10-05) | Na merge (2026-10-12) | Bron |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | Vereiste invoer |
  | `Target date` | 2026-10-12 | 2026-10-12 | Vereiste invoer |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | Automatische aanmaak |
  | `End date` | Leeg | 2026-10-12 | Automatische merge |

- `PR Quality` controleert het formaat en blokkeert merge bij fout; `PR Automation` labelt en wijst toe.
- Voor macOS-code `cd mac && swift test`; schrijf handmatige UI-resultaten in tekst.
- Beschrijvingen en release-notities mogen alleen tekst zijn; afbeeldingen/covers niet vereist.
- Wijzig gerelateerde formele documentatie en websitehulp in dezelfde patch bij functie, gedrag, standaard, bouw of releaseproces. Sitecopy omvat 17 talen; hergebruik hulpstructuur en lokalisatiemap.
- Commit geen `.build`, `dist`, downloads, logs, tokens, ondertekenmateriaal of persoonsgegevens.
- `main` en `publish-v*` zijn beschermd; alleen gereviewde PR met geslaagde checks.

## CI overslaan

Beheerders en aangevraagde reviewers mogen niet-relevante checks overslaan, bijvoorbeeld documentatie. Zet de richtlijn op eigen regel in PR-commentaar:

| Richtlijn | Effect |
| --- | --- |
| `skip-all` | Alle workflows in `.github/ci-skip.json` overslaan. |
| `skip-<workflow>` | Eén workflow per naam/bestand/alias, zoals `skip-swift`, `skip-web-ci`, `skip-Web CI`. |
| `unskip-all` | Alle overslaaninstructies wissen. |
| `unskip-<workflow>` | Eén workflow herstellen. |

- Vrije tekst mag volgen, zoals `skip-all: documentation only change`.
- GitHub-naam met spaties toegestaan; `skip-CI Lint` en `skip-lint` gelijk. Langste passende naam wint, overige woorden zijn de notitie.
- Alleen eigenaar, organisatielid, collaborator of gevraagde reviewer. Bots worden genegeerd.
- `CI Skip` annuleert lopende runs, rapporteert succes voor vereiste overgeslagen checks, zet `skip-ci` en werkt één samenvatting bij.
- Hele thread wordt na ieder commentaar afgespeeld; nieuwste richtlijn wint.
- Een richtlijn vervalt bij een nieuw gepusht commit: ze betreft alleen bekeken code. Anders zou nieuwe code ongebouwd mogen mergen. Na push herstelt `CI Skip` checks, verwijdert label en noemt verlopen regels; plaats opnieuw voor nieuw commit.
- Beheerder kan opnieuw toepassen via **Actions -> CI Skip -> Run workflow**, met PR-nummer.
- Manifest koppelt workflows aan gepubliceerde checknamen; `CI Checks` faalt bij afwijking.

## Padgebonden controles

Platformchecks draaien alleen voor bestanden die ze bouwen; documentatie volgt eigenaarspad.

| Workflow | Paden in PR |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.swiftformat`, `.github/**` |
| `Web CI` | `web/**`, `promo/**`, `docs/**`, `.github/**` |

- `paths` van `.github/ci-skip.json` is leidend; zonder scope draait altijd. `CI Lint`, `PR Quality Gates`, `CodeQL`, `Dependency Review` dus elke PR. Repositoryhygiëne en skillvalidatie horen bij `CI Checks`; oude `hygiene`/`skills`-aliassen niet meer gebruikt.
- Iedere `.github/`-wijziging draait alles, om CI op alle platformen te bewijzen.
- Jobvoorwaarden in plaats van workflow-`paths:` zorgen dat vereiste checks succes melden in plaats van eeuwig pending.
- Hernoemde bestanden worden op oud én nieuw pad getoetst, hoofdletterongevoelig.
