# Integrationsreferenz für `zislactl`

**Deutsch** | [Dokumentationssprachen](../../../README.md)

`zislactl` ist das gemeinsame lokale Statusprotokoll für in zisla integrierte KI-Werkzeuge, Skripte und CI-Aufgaben. Es schreibt Aufgabenstatus, Nutzung und Mitteilungen als strukturierte Daten und speichert sie in SQLite-Transaktionen, um Teilzustände zu verhindern. Dieses Dokument definiert stabile Anbieter, Befehle und Feldgrenzen.

## Entwurfsgrundsätze

- Der Status wird lokal geschrieben; Prompts, Antwortinhalte und Zugangsdaten werden niemals hochgeladen.
- Updates derselben Aufgaben-ID sind idempotent; Leser sehen den vollständigen bestätigten Datenbankzustand.
- Anbieternamen akzeptieren kompatible Aliase, werden aber unter ihrem kanonischen Wert gespeichert.

## Lokale Persistenz und JSON-Grenzen

Aufgaben, Nutzung und Mitteilungen liegen in `~/Library/Application Support/zisla/ai-state.sqlite`. Schreibvorgänge verwenden SQLite-Transaktionen; das aktuelle Protokoll schreibt kein `ai-state.json`. Das Leeren von Aufgaben behält den Nutzungsverlauf.

`zislactl` akzeptiert die dokumentierten Befehlsoptionen, und `list` gibt zeilenweisen Text aus. Integrationen und Konfiguration nutzen weiterhin strukturiertes JSON, darunter JSON/JSONL-Sitzungseingaben externer Werkzeuge und JSON-Kodierung/-Dekodierung der Einstellungen, mit eigenen Parsingregeln. Die CLI selbst verwendet Argumente, Textausgabe und SQLite-Persistenz.

## Anbieter

| Wert | Aliase |
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

WorkBuddy und WorkBuddy AI sind getrennte Produkte für den nationalen/internationalen Markt,
keine ältere/neuere Version desselben Clients. Kanonische Anbieter, Datenspeicher, Symbole und Deep Links
müssen getrennt bleiben. Historische WorkBuddy-Einträge mit `harness` bleiben lesbar;
dieser Anbieter wird nicht global umbenannt oder migriert. WorkBuddy-Aktivitätsmitteilungs-IDs verwenden
eine ausdrückliche Anbieter/Aufgaben-Grenze (`ai-active-workbuddy:<id>` oder `ai-active-workbuddy-ai:<id>`),
damit eine manuelle WorkBuddy-Aufgabe mit `ai-` am ID-Anfang nicht als WorkBuddy AI erkannt wird.

### Automatische Erkennung von Delta, Orca, WorkBuddy und WorkBuddy AI

- Delta liest indexierte Streaming-Thread-Metadaten aus `Library/Application Support/Delta/user_*/data.sqlite`
  und der älteren Wurzeldatenbank. Archivierte, inaktive und veraltete Threads sind ausgeschlossen. Numerische Nutzung stammt
  aus Deltas `app_model_usage_daily`-Ledger einschließlich Cache-Lese- und Schreibvorgängen. Fehlt dieser Ledger
  in einem Release, wird keine automatische Nutzung gemeldet; Zahlen werden nicht aus Gesprächsinhalten geschätzt.
- Orca liest lokale `agent-hooks/last-status.json`-Snapshots und aktuellen strukturierten Gesprächsrundenstatus
  aus `agent-session-journal.db`, einschließlich Profilordnern und v1/v2/v3-Rundeneinträgen.
  Höchste Revisionen und ursprüngliche Rundenreihenfolge werden beachtet. Abgeschlossene, abgelaufene, entfernte
  und reine Identitätssitzungen sind ausgeschlossen. Maßgebliche Transkriptpfade und festgelegte Claude/Codex-
  Konto-Home-Verzeichnisse tragen ebenfalls Token-Nutzung bei. Diese Stichproben behalten CLI-Anbieter und
  Ereignisidentität, damit der normale CLI-Detektor sie nicht erneut zählt. Orcas maschinenweite Nutzungscaches
  werden bewusst nicht als zusätzliche Nutzung importiert.
- WorkBuddy liest seine eigene `~/.workbuddy/workbuddy.db` mit Anbieter `workbuddy`,
  WorkBuddy-Symbol und `workbuddy://chat/<id>`-Links. Der WorkBuddy-AI-Speicher wird nicht geprüft.
- WorkBuddy AI liest Sitzungsstatus, Titel, Modell und Zeitstempel aus
  `~/.workbuddy-ai/workbuddy.db`, unabhängig von WorkBuddys `~/.workbuddy/workbuddy.db`.
  Abgeschlossene, gelöschte und veraltete Sitzungen sind ausgeschlossen; der aktuellere Wert aus `updated_at` und
  `last_activity_at` hält lange Sitzungen sichtbar. Aufgaben nutzen Anbieter `workbuddy-ai`,
  WorkBuddy-AI-Symbol und `workbuddy-ai://chat/<id>`-Links. Die Integration erkennt nur Sitzungen:
  `session_usage.used` ist Kontextbelegung, und Credits sind keine USD-/Token-Nutzung; beides wird
  deshalb nicht als abgerechnete Tokens importiert. Manuelle numerische Nutzung meldet `zislactl usage`.
- Alle Integrationen sind schreibgeschützt und arbeiten nach verfügbaren Daten; fehlende oder inkompatible Speicher liefern keine Daten.
  Replizierte Delta-Thread-Inhalte und Orca-Journalnachrichten werden nicht abgefragt. Verwenden Sie `zislactl usage`
  für Werkzeuge oder Versionen ohne aufgezeichnete numerische Nutzung.

## Optionssyntax

- Schreiben Sie Optionen als `--key value` oder `--key=value`. Jede Option darf pro Befehl nur einmal vorkommen; Wiederholung ist ein Nutzungsfehler mit Exit-Code 64.
- Werte dürfen mit `--` beginnen, etwa `--detail --verbose`. Ausnahme sind Flags desselben Befehls: `--failed` bei `finish`, `--queued` bei `update`. Sie werden niemals als Wert gelesen, sodass ein leeres unquotiertes `--detail $DETAIL --failed` die Aufgabe weiterhin als fehlgeschlagen markiert. Solche Literalwerte übergeben Sie als `--detail=--failed`.
- `--failed` und `--queued` sind Flags. Allein bedeuten sie wahr; `--failed=false` oder `--failed false`, entsprechend auch `--queued`, schalten sie aus. Jeder andere Wert ist ein Nutzungsfehler.

## `update`

Erstellt oder ersetzt eine Aufgabe mit derselben `id`.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- Ohne `--progress` zeigt die Oberfläche unbestimmten Fortschritt.
- `--pid` ist optional und sollte nur gesetzt werden, wenn der Aufrufer den Aufgabenprozess kennt.
- `--status` meldet ausdrücklich laufend, eingereiht, wartend auf Benutzeraktion oder Fehler während der Ausführung.
- `--queued` ist ein Alias für `--status queued`; ohne ausdrücklichen Status läuft die Aufgabe. Ein ausdrücklicher `--status` hat Vorrang vor `--queued`.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

Erfolgreiche Aufgaben werden auf 100 % gesetzt; fehlgeschlagene behalten ihren letzten Fortschritt.

## `remove`

```text
zislactl remove --id <id>
```

Beendet mit Code 65, wenn die Aufgabe nicht existiert.

## `clear`

```text
zislactl clear
```

Leert Aufgaben und behält Nutzungsverlauf sowie Mitteilungen.

## `list`

```text
zislactl list
```

Gibt aktuellen Aufgabenstatus, Anbieter, Titel und Prozentsatz zeilenweise aus.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

Die Nutzung speist das 12-Stunden-Diagramm und die 7x24-Heatmap.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

Die neue Mitteilung erscheint auf der gewählten Seite und pausiert das automatische Schließen beim Darüberfahren.

## `message`

Sendet eine Nachrichtenmitteilung an beide Inselseiten: links erscheinen App-Logo und Absender, rechts läuft der Inhalt.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

Beispiel:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender` und `--content` sind erforderlich; `--app-bundle-id` ist optional und hilft bei der Zuordnung des installierten App-Symbols.
- Zeilenumbrüche und überschüssiger Leerraum werden zusammengefasst; der Inhalt wird auf etwa 48 Zeichen mit Auslassungszeichen gekürzt.
- Eine SQLite-Transaktion speichert beide `IslandNotice`-Einträge ohne Änderung am bestehenden `notify`-Verhalten.

## Exit-Codes

| Code | Bedeutung |
| --- | --- |
| `0` | Erfolg |
| `64` | Ungültiges Argument oder Unterbefehl |
| `65` | Datenfehler, fehlende Aufgabe oder beschädigte Datenbank |
| `70` | Dateisystem- oder anderer Laufzeitfehler |
