# Zu zisla beitragen

**Deutsch** | [Dokumentationssprachen](../README.md)

Vielen Dank für Ihren Beitrag zu zisla.

## Issues

Vielen Dank für das Öffnen eines Issues. Durchsuchen Sie zuerst bestehende Issues und Discussions, damit Meldungen nicht doppelt erscheinen.

- Verwenden Sie `[Bug] Short problem description` für Fehlermeldungen, etwa `[Bug] Voice input is not written to the current text field`. Nennen Sie zisla-Version, macOS-Version und Gerät, Installationsmethode, Reproduktionsschritte, erwartetes und tatsächliches Verhalten.
- Verwenden Sie `[Feature] Short request description` für Funktionswünsche, etwa `[Feature] Support custom voice-organization prompts`. Beschreiben Sie das Problem, den Lösungsvorschlag und erwogene Alternativen.
- Wählen Sie im Formular eine **Area**. Dieses Pflichtfeld bestimmt das `area:*`-Label: `Feature Development`, `Bug Fix`, `CI & Build`, `Documentation` oder `Community & Discussion`. Die vereinfachten chinesischen Formulare bieten dieselben Optionen mit denselben Labels.
- Entfernen Sie Tokens, Kontodaten, lokale Pfade und weitere sensible Informationen aus Protokollen, Screenshots und Aufnahmen.
- Melden Sie Sicherheitslücken vertraulich über [Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), statt ein öffentliches Issue zu öffnen.
- Die Automatisierung setzt `bug` oder `enhancement` und das passende `area:*`-Label; andere Labels bleiben unverändert. Entsprechen Titelpräfix oder Pflichtfeld nicht dem Formular, wird zusätzlich `needs-more-info` gesetzt und ein einzelner Kommentar mit fehlenden Angaben gepflegt. Nach Bearbeitung des Issues aktualisiert er sich selbst.

## Entwicklung

Die aktuelle macOS-Implementierung liegt in `mac/` und benötigt macOS 14+ mit Swift 6 / Xcode 16+.

```bash
cd mac
swift test
```

Entfernen Sie Test-, Build- und Paketierungsbinärdateien vor dem Commit.

Führen Sie vor jedem Commit oder Amend `make format` aus der Repository-Wurzel mit SwiftFormat 0.64.7 wie in CI aus. Prüfen Sie den Diff und behalten Sie nur die für diese Aufgabe erforderliche Formatierung.

## Branches und Commits

- Erstellen Sie Branches vom neuesten `main` und verwenden Sie das Präfix des in der Pull Request erklärten Typs: `feat/` oder `feature/`, `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `chore/`, `build/`, `ci/` oder `revert/`, etwa `fix/download-timeout` oder `ci/skip-directive-timing`.
- Verwenden Sie englische [Conventional Commits](https://www.conventionalcommits.org/), etwa `type(scope): description` oder `fix(ui): resolve layout issue in notch area`.
- Halten Sie einen Branch und eine Pull Request auf ein klares Ziel ausgerichtet; vermeiden Sie reine Formatänderungen und sachfremde Refactorings.
- `publish-v*`-Branches sind für Release-Wartung reserviert. Alle anderen Beiträge gehen an `main`.

## Pull Requests

Vielen Dank für das Öffnen einer Pull Request. Prüfen Sie diese Anforderungen während der Überprüfung.

- Der **PR-Titel** muss ein englischer Conventional-Commit-Betreff sein, zum Beispiel:
  - `feat(ci): add PR quality gates`
  - `fix(mac): resolve memory leak in overlay`
  - `docs: update contributing guidelines`
  Erlaubte Typen sind `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci` und `revert`.

- Der **PR-Text** muss Englisch sein und die Abschnitte `Summary`, `GitHub Project`, `PR Type`, `Validation`, `Risk and Rollback`, `Related Issue` und `AI Attribution` aus `.github/PULL_REQUEST_TEMPLATE.md` enthalten.
  - `GitHub Project` behält den Vorlagenwert `- Project: zisla Development`. `Project Automation` liest ihn, um die PR ins gemeinsame Board einzuordnen.
  - In `GitHub Project` sind `Start date` und `Target date` Pflichtfelder. Geben Sie jedes genau einmal als gültiges Kalenderdatum in `YYYY-MM-DD` an; `Target date` darf nicht vor `Start date` liegen. Fehlende, leere, auskommentierte, doppelte oder ungültige Daten lassen `PR Quality` fehlschlagen. `Submitted date` übernimmt automatisch das Erstellungsdatum in UTC+08:00; `End date` wird beim Merge automatisch gesetzt. Beide benötigen keine manuelle Eingabe.
  - `PR Type` enthält genau einen `- Type:`-Wert, der dem Titeltyp entsprechen muss. Titel verwenden kanonische Typen; der Text akzeptiert auch Typ-Labelnamen und konfigurierte Aliase, daher werden `fix`, `bug`, `bug fix`, `bugfix` und `hotfix` zu `fix`. `PR Automation` wandelt den Typ in ein Label um, etwa `fix` in `bug`.
  - `Project Automation` wählt `Status` anhand der konfigurierten Labelzuordnung einschließlich PR-Typ und setzt ihn bei Schließung oder Merge auf `Done`. Tragen Sie `Status` nicht manuell ein.
  - `Summary` beschreibt die Änderung; `Risk and Rollback` enthält genau ein nicht leeres `Risk`- und ein nicht leeres `Rollback`-Feld.
  - Jeder `Validation`-Eintrag beginnt mit seinem eigenen `- Status:` und exakt `passed`, `failed` oder `not run`. Jeder `passed`-/`failed`-Eintrag benötigt eigene nicht leere `Command` und `Result`; jeder `not run`-Eintrag ein eigenes nicht leeres `Reason`. Felder anderer Einträge erfüllen die Anforderung nicht. Melden Sie Fehler ehrlich als `failed`.
  - `Related Issue` schließt ein Issue über ein Schlüsselwort wie `Closes #123`, was auch `development` setzt, oder lautet exakt `None`.
  - `AI Attribution` enthält genau ein nicht leeres `- Agent:`-Feld. Ein Agent außer `None` braucht eine passende `- Co-authored-by: Name <email>`-Zeile, die auch als Trailer in mindestens einem Commit steht; außerdem wird `ai-assisted` gesetzt.

  Beispieltitel: `fix(ci): validate every PR metadata entry`

  Beispieltext, in den Sie Ihre tatsächlichen Prüfergebnisse eintragen:

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

  Datumsbeispiel: Die PR wird am 2026-10-05 erstellt und am 2026-10-12 gemergt, UTC+08:00. Automatische Felder im Codekommentar zeigen nur beispielhafte Project-Werte und sind keine Eingaben. Automation aktualisiert GitHub Project und die PR-Timeline, nicht diese Kommentarzeilen.

  | Datum | Bei Erstellung (2026-10-05) | Nach Merge (2026-10-12) | Quelle |
  | --- | --- | --- | --- |
  | `Start date` | 2026-10-05 | 2026-10-05 | Pflichteingabe |
  | `Target date` | 2026-10-12 | 2026-10-12 | Pflichteingabe |
  | `Submitted date` | 2026-10-05 | 2026-10-05 | Automatisches Erstellungsdatum |
  | `End date` | Leer | 2026-10-12 | Automatisches Mergedatum |

- `PR Quality` prüft dieses Format; eine PR kann bei fehlgeschlagener Prüfung nicht gemergt werden. `PR Automation` setzt anschließend Labels und weist die PR zu.
- Führen Sie bei macOS-Codeänderungen `cd mac && swift test` aus; beschreiben Sie bei UI-Änderungen manuelle Prüfergebnisse als Text.
- PR-Texte und Release Notes dürfen reiner Text sein; Bilder, Screenshots und Titelbilder sind nicht erforderlich.
- Aktualisieren Sie bei Änderungen an Funktionen, Verhalten, Voreinstellungen, Buildanleitungen oder Releaseabläufen die offiziellen Dokumente und Websitehilfe im selben Patch. Website-Benutzertexte decken alle 17 Sprachen ab; verwenden Sie bestehende Hilfestruktur und den lokalisierten Dokumentationsordner.
- Committen Sie keine `.build`, `dist`, Downloads, Protokolle, Tokens, Signaturmaterialien oder persönlichen Daten.
- `main` und `publish-v*` sind geschützt und werden nur über überprüfte Pull Requests mit erfolgreichen Checks aktualisiert.

## CI überspringen

Maintainer und angeforderte Reviewer können Prüfungen überspringen, die eine Änderung nicht betreffen kann, etwa bei einer reinen Dokumentationskorrektur. Schreiben Sie die Direktive in eine eigene Zeile eines PR-Kommentars:

| Direktive | Wirkung |
| --- | --- |
| `skip-all` | Überspringt alle Workflows aus `.github/ci-skip.json`. |
| `skip-<workflow>` | Überspringt einen Workflow nach Name, Datei oder Alias, etwa `skip-swift`, `skip-web-ci` oder `skip-Web CI`. |
| `unskip-all` | Löscht alle Überspringdirektiven. |
| `unskip-<workflow>` | Stellt einen Workflow wieder her. |

- Freitext darf folgen, etwa `skip-all: documentation only change`.
- Der Workflow kann einschließlich Leerzeichen wie auf GitHub benannt werden, also sind `skip-CI Lint` und `skip-lint` gleichwertig. Der längste passende Name gewinnt, übrige Wörter werden zur Anmerkung.
- Nur Direktiven von Repository-Eigentümer, Organisationsmitglied, Mitwirkendem oder angefordertem Reviewer werden berücksichtigt. Bot-Kommentare werden ignoriert.
- `CI Skip` bricht laufende Ausführungen ab, meldet übersprungene Prüfungen als erfolgreich, damit erforderliche Checks erfüllt bleiben, setzt `skip-ci` und aktualisiert einen gemeinsamen Entscheidungskommentar.
- Bei jedem Kommentar wird der gesamte Thread erneut ausgewertet; die neueste Direktive gilt.
- Eine Direktive verfällt mit einem neuen gepushten Commit: Sie gilt nur für den vom Autor gesehenen Code, sonst könnte eine erfolgreiche Meldung neuen ungebauten Code freigeben. `CI Skip` läuft bei jedem Push erneut, entfernt `skip-ci`, stellt Checks wieder her und nennt abgelaufene Direktiven im Kommentar. Kommentieren Sie erneut, um auch den neuen Commit zu überspringen.
- Maintainer können die aktuelle Entscheidung ohne neuen Kommentar über **Actions -> CI Skip -> Run workflow** mit der PR-Nummer erneut anwenden.
- `.github/ci-skip.json` ordnet Workflows ihren Checknamen zu. `CI Checks` schlägt bei Abweichungen zwischen Manifest und Workflowdateien fehl.

## Pfadbezogene Prüfungen

Ein Plattformworkflow prüft nur, wenn die PR seine Builddateien berührt; Dokumentationsänderungen werden somit anhand ihres Pfads eingeordnet:

| Workflow | Läuft bei Änderungen an |
| --- | --- |
| `Swift Tests` | `mac/**`, `Makefile`, `.swiftformat`, `.github/**` |
| `Web CI` | `web/**`, `promo/**`, `docs/**`, `.github/**` |

- Das `paths`-Feld in `.github/ci-skip.json` legt Bereiche fest; Workflows ohne Angabe laufen immer. Daher laufen `CI Lint`, `PR Quality Gates`, `CodeQL` und `Dependency Review` bei jeder PR. Repository-Hygiene und Skillvalidierung gehören zu `CI Checks`; frühere `hygiene`-/`skills`-Aliase werden nicht mehr genutzt.
- Jede Änderung unter `.github/` startet alles, weil CI-Änderungen auf allen Plattformen nachgewiesen werden müssen.
- Jobs werden per Jobbedingung statt Workflow-`paths:`-Filter übersprungen, damit erforderliche Checks Erfolg melden und nicht dauerhaft ausstehen.
- Umbenannte Dateien werden anhand des alten und neuen Pfads ohne Beachtung der Groß-/Kleinschreibung verglichen.
