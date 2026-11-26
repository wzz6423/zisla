# `zislactl`-integratiereferentie

**Nederlands** | [English](../../../../../mac/Docs/cli-reference.md) | [简体中文](../../../../../mac/Docs/cli-reference.zh-CN.md) | [Andere talen](../../../README.md)

`zislactl` is het gedeelde lokale statusprotocol waarmee AI-tools, scripts en CI-taken met zisla verbinden. Taakstatus, gebruik en meldingen worden als gestructureerde gegevens in SQLite-transacties geschreven, zodat lezers geen gedeeltelijke staat zien. Dit document legt stabiele providers, opdrachten en veldgrenzen vast.

## Ontwerpprincipes

- Status blijft lokaal; prompts, antwoordteksten en inloggegevens worden nooit geüpload.
- Updates met dezelfde taak-ID zijn idempotent; lezers zien volledig vastgelegde databasestatus.
- Providernamen accepteren compatibiliteitsaliassen, maar worden canoniek opgeslagen.

## Lokale opslag en JSON-grenzen

Taken, gebruik en meldingen staan in `~/Library/Application Support/zisla/ai-state.sqlite`. Schrijven gebeurt met SQLite-transacties; het huidige protocol schrijft geen `ai-state.json`. Taken wissen behoudt gebruiksgeschiedenis.

De CLI accepteert de beschreven opties en `list` schrijft tekst per regel. Integraties en configuratie gebruiken nog gestructureerde JSON, zoals externe JSON/JSONL-sessies en JSON-codering/decodering van instellingen, volgens hun eigen parserregels. De CLI zelf gebruikt argumenten, tekstuitvoer en SQLite-opslag.

## Providers

| Waarde | Aliassen |
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

WorkBuddy en WorkBuddy AI zijn aparte producten voor binnenlandse/internationale markten, geen oudere/nieuwere versies. Canonieke providers, opslag, iconen en deeplinks blijven gescheiden. Historische WorkBuddy-records met `harness` blijven leesbaar; die provider wordt niet wereldwijd hernoemd of gemigreerd. Activiteitsmeldingen scheiden provider en taak expliciet: `ai-active-workbuddy:<id>` en `ai-active-workbuddy-ai:<id>`. Een handmatige WorkBuddy-taak met `ai-` aan het begin wordt daardoor niet verward met WorkBuddy AI.

### Automatische detectie van Delta, Orca, WorkBuddy en WorkBuddy AI

- Delta leest geïndexeerde streamingthreadmetadata uit `Library/Application Support/Delta/user_*/data.sqlite` en de oude hoofddatabase. Gearchiveerde, inactieve en verouderde threads vallen weg. Numeriek gebruik komt uit `app_model_usage_daily`, inclusief cachelezingen en -schrijvingen. Versies zonder die registratie tonen geen automatisch gebruik; gesprekstekst wordt niet gebruikt om aantallen te raden.
- Orca leest lokale `agent-hooks/last-status.json`-snapshots en gestructureerde chatturnstatus uit `agent-session-journal.db`, inclusief profielen en v1/v2/v3-records. Hoogste revisies en oorspronkelijke volgorde gelden. Voltooide, verlopen, externe en alleen-identiteitsessies worden uitgesloten. Betrouwbare transcriptiepaden en vastgezette Claude/Codex-accounthuizen dragen ook tokengebruik bij. Deze metingen houden hun CLI-provider en gebeurtenisidentiteit, zodat reguliere CLI-detectie niet dubbel telt. Orca's machinebrede gebruikscaches worden bewust niet als extra gebruik geïmporteerd.
- WorkBuddy leest zijn eigen `~/.workbuddy/workbuddy.db`, gebruikt provider `workbuddy`, eigen pictogram en `workbuddy://chat/<id>`. Het bekijkt WorkBuddy AI-opslag niet.
- WorkBuddy AI leest sessiestatus, titels, model en tijden uit `~/.workbuddy-ai/workbuddy.db`, los van WorkBuddy. Afgeronde, verwijderde en oude sessies vallen weg. Het nieuwste van `updated_at` en `last_activity_at` houdt lange sessies zichtbaar. Taken gebruiken `workbuddy-ai`, eigen pictogram en `workbuddy-ai://chat/<id>`. Deze integratie detecteert alleen sessies: `session_usage.used` is contextbezetting en credits zijn geen USD/tokengebruik; beide worden niet als gefactureerde tokens geïmporteerd. Numeriek handmatig gebruik kan via `zislactl usage`.
- Alle integraties zijn alleen-lezen en werken naar beste vermogen. Ontbrekende/incompatibele opslag geeft geen gegevens. Delta-threadteksten en Orca-journalberichtteksten worden niet gelezen. Gebruik `zislactl usage` waar geregistreerd numeriek gebruik ontbreekt.

## Optiesyntaxis

- Gebruik `--key value` of `--key=value`. Elke optie maximaal eenmaal per opdracht; herhaling is gebruiksfout met afsluitcode 64.
- Een waarde mag met `--` beginnen, bijvoorbeeld `--detail --verbose`. Een vlag van dezelfde opdracht is uitgezonderd: `--failed` voor `finish` en `--queued` voor `update` worden geen waarde. Een lege, niet-gequote variabele in `--detail $DETAIL --failed` markeert de taak dus nog als mislukt. Gebruik `--detail=--failed` voor die letterlijke waarde.
- `--failed` en `--queued` zijn vlaggen. Zonder waarde betekenen ze waar; `--failed=false` of `--failed false` en hetzelfde voor `--queued` zetten ze uit. Andere waarden zijn gebruiksfouten.

## `update`

Maakt of vervangt de taak met dezelfde `id`.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- Zonder `--progress` is de voortgang onbepaald.
- `--pid` is optioneel, alleen als de aanroeper het taakproces kan identificeren.
- `--status` meldt uitvoeren, wachtrij, gebruikersactie nodig of fout tijdens uitvoeren.
- `--queued` is alias voor `--status queued`. Zonder expliciete status is de taak actief; expliciete `--status` gaat vóór `--queued`.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

Succesvolle taken worden 100%; mislukte houden hun laatste voortgang.

## `remove`

```text
zislactl remove --id <id>
```

Afsluitcode 65 wanneer de taak niet bestaat.

## `clear`

```text
zislactl clear
```

Wist taken, bewaart gebruiksgeschiedenis en meldingen.

## `list`

```text
zislactl list
```

Schrijft per regel huidige taakstatus, provider, titel en percentage.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

Gebruik voedt de 12-uursgrafiek en 7x24-kaart.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

De melding verschijnt aan de gekozen kant en pauzeert automatisch sluiten tijdens aanwijzen.

## `message`

Stuurt één berichtmelding naar beide kanten: links applogo en afzender, rechts scrollende berichttekst.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

Voorbeeld:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender`, `--content` zijn verplicht. Optioneel `--app-bundle-id` helpt het geïnstalleerde appicoon te vinden.
- Regeleinden en overtollige witruimte worden samengevoegd; de tekst wordt met ellips op circa 48 tekens afgekapt.
- Eén SQLite-transactie bewaart beide `IslandNotice`-items zonder bestaand `notify`-gedrag te wijzigen.

## Afsluitcodes

| Code | Betekenis |
| --- | --- |
| `0` | Succes |
| `64` | Ongeldig argument of subopdracht |
| `65` | Gegevensfout, ontbrekende taak of beschadigde database |
| `70` | Bestandssysteem- of andere runtimefout |
