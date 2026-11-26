# Riferimento per l'integrazione di `zislactl`

**Italiano** | [English](../../../../../mac/Docs/cli-reference.md) | [简体中文](../../../../../mac/Docs/cli-reference.zh-CN.md) | [Altre lingue](../../../README.md)

`zislactl` è il protocollo locale condiviso con cui strumenti AI, script e attività CI si integrano con zisla. Scrive stato delle attività, utilizzo e notifiche come dati strutturati, persistendoli in transazioni SQLite per evitare scritture parziali. Questo documento definisce provider, comandi e vincoli stabili dei campi.

## Principi di progettazione

- Lo stato viene scritto localmente; prompt, risposte e credenziali non vengono caricati.
- Gli aggiornamenti dello stesso ID attività sono idempotenti; i lettori vedono lo stato completo e confermato del database.
- I provider accettano alias di compatibilità, ma vengono salvati con il valore canonico.

## Persistenza locale e limiti JSON

Attività, utilizzo e notifiche risiedono in `~/Library/Application Support/zisla/ai-state.sqlite`. Le scritture usano transazioni SQLite; il protocollo attuale non scrive `ai-state.json`. Svuotare le attività conserva la cronologia di utilizzo.

`zislactl` accetta gli argomenti documentati; `list` produce testo riga per riga. Integrazioni e configurazioni usano ancora JSON strutturato, per esempio sessioni JSON/JSONL degli strumenti esterni e codifica/decodifica JSON delle impostazioni, secondo i rispettivi parser. La CLI usa argomenti, output testuale e persistente SQLite.

## Provider

| Valore | Alias |
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

WorkBuddy e WorkBuddy AI sono prodotti separati per mercati nazionali/internazionali, non versioni vecchie e nuove dello stesso client. Provider canonici, archivi, icone e deep link devono restare distinti. I record storici WorkBuddy con `harness` restano leggibili; il provider non viene rinominato o migrato globalmente. Gli ID delle notifiche WorkBuddy separano esplicitamente provider e attività (`ai-active-workbuddy:<id>` e `ai-active-workbuddy-ai:<id>`), così un'attività manuale WorkBuddy il cui ID inizia con `ai-` non viene confusa con WorkBuddy AI.

### Rilevamento automatico di Delta, Orca, WorkBuddy e WorkBuddy AI

- Delta legge i metadati indicizzati dei thread in streaming da `Library/Application Support/Delta/user_*/data.sqlite` e dal database precedente alla radice. Esclude thread archiviati, inattivi e obsoleti. L'utilizzo numerico proviene da `app_model_usage_daily`, con letture e scritture della cache. Le versioni senza questo registro non riportano utilizzo automatico; non stimano token dai contenuti delle conversazioni.
- Orca legge snapshot locali `agent-hooks/last-status.json` e stato dei turni delle chat strutturate da `agent-session-journal.db`, incluse directory dei profili e record v1/v2/v3. Rispetta revisioni massime e ordine originale. Esclude sessioni completate, scadute, remote o con sola identità. Percorsi autorevoli delle trascrizioni e home di account Claude/Codex fissate contribuiscono ai token. Mantengono provider CLI e identità degli eventi, evitando un secondo conteggio dal rilevatore CLI. Le cache di utilizzo globali Orca non vengono importate come utilizzo aggiuntivo.
- WorkBuddy legge solo `~/.workbuddy/workbuddy.db`, con provider `workbuddy`, relativa icona e link `workbuddy://chat/<id>`. Non esamina l'archivio WorkBuddy AI.
- WorkBuddy AI legge stato, titoli, modello e tempi da `~/.workbuddy-ai/workbuddy.db`, indipendente dall'archivio WorkBuddy. Esclude sessioni finite, eliminate o obsolete. Il più recente tra `updated_at` e `last_activity_at` mantiene visibili le sessioni lunghe. Usa provider `workbuddy-ai`, relativa icona e link `workbuddy-ai://chat/<id>`. Rileva soltanto sessioni: `session_usage.used` è occupazione del contesto e i crediti non sono USD/token, quindi nessuno viene importato come token fatturati. L'utilizzo numerico manuale si invia con `zislactl usage`.
- Tutte le integrazioni sono di sola lettura e fanno il possibile; archivi assenti o incompatibili restituiscono dati assenti. Non interrogano il testo replicato dei thread Delta né i messaggi del journal Orca. Usa `zislactl usage` dove non esistono numeri registrati.

## Sintassi delle opzioni

- Scrivi `--key value` o `--key=value`. Ogni opzione compare al massimo una volta; ripeterla è errore d'uso, codice 64.
- Un valore può iniziare con `--`, come `--detail --verbose`. Fa eccezione un flag dello stesso comando: `--failed` di `finish` o `--queued` di `update` non viene consumato come valore. Quindi una variabile vuota non quotata in `--detail $DETAIL --failed` segnala comunque l'errore dell'attività. Per quel valore letterale usa `--detail=--failed`.
- `--failed` e `--queued` sono flag: soli significano vero; `--failed=false` o `--failed false` (analogamente `--queued`) li disattivano. Ogni altro valore è errore d'uso.

## `update`

Crea o sostituisce l'attività con lo stesso `id`.

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- Senza `--progress`, l'interfaccia mostra avanzamento indeterminato.
- `--pid` è facoltativo e va indicato solo se il chiamante identifica il processo dell'attività.
- `--status` indica esecuzione, coda, attesa dell'utente o errore durante l'esecuzione.
- `--queued` equivale a `--status queued`; senza stato esplicito l'attività è in esecuzione. `--status` esplicito prevale su `--queued`.

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

Le attività riuscite passano al 100%; quelle fallite mantengono l'ultimo avanzamento.

## `remove`

```text
zislactl remove --id <id>
```

Se l'attività non esiste, termina con codice 65.

## `clear`

```text
zislactl clear
```

Svuota le attività conservando cronologia di utilizzo e notifiche.

## `list`

```text
zislactl list
```

Stampa una riga per attività con stato, provider, titolo e percentuale.

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

L'utilizzo alimenta il grafico di 12 ore e la mappa 7x24.

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

La notifica compare dal lato scelto e sospende la chiusura automatica mentre il puntatore è sopra.

## `message`

Invia una notifica su entrambi i lati: a sinistra logo e mittente, a destra il testo scorrevole.

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

Esempio:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app`, `--sender`, `--content` sono obbligatori; `--app-bundle-id` facoltativo aiuta a trovare l'icona installata.
- Righe e spazi in eccesso vengono compattati; il testo viene troncato a circa 48 caratteri con puntini di sospensione.
- Una transazione SQLite salva entrambi gli `IslandNotice`, senza cambiare il comportamento di `notify`.

## Codici di uscita

| Codice | Significato |
| --- | --- |
| `0` | Successo |
| `64` | Argomento o sottocomando non valido |
| `65` | Errore nei dati, attività assente o database corrotto |
| `70` | Errore filesystem o altro errore di esecuzione |
