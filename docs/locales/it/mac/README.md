# zisla per macOS

**Italiano** | [English](../../../../mac/README.md) | [简体中文](../../../../mac/README.zh-CN.md) | [Altre lingue](../../README.md)

Questa directory contiene l'implementazione macOS di zisla. Sposta il puntatore al centro della parte superiore dello schermo per espandere l'isola; allontanalo per nasconderla. L'app usa AppKit `NSPanel`, SwiftUI e servizi basati su eventi, senza una finestra trasparente permanente né un ciclo di rendering mentre è nascosta.

Target Swift, ID del bundle, directory dei dati locali e `zislactl` usano tutti l'identificatore zisla. Gli aggiornamenti migrano automaticamente dati e preferenze delle versioni precedenti.

Sono supportati macOS 14 e successivi. macOS 26 usa Liquid Glass; macOS 14/15 usano il materiale di sistema nativo.

## Funzioni

### 12 moduli dell'isola

| Modulo | Funzioni implementate |
| --- | --- |
| Home | Riassume quando serve il timer Pomodoro corrente, la prima attività AI attiva, i download nativi e l'avanzamento di più download del browser. |
| Suoni e statistiche della tastiera | 20 timbri integrati; statistiche di digitazione locali attivabili separatamente, tendenze, timeline delle applicazioni e mappa per singolo tasto. |
| Trasferimento | Trascina file, media o link nell'area superiore per conservarli nella vaschetta, mostrarli nel Finder o aprire il menu di condivisione di sistema. Gli screenshot conservati hanno schede blu larghe il doppio e una categoria propria, con copia immagine, esportazione PNG ed eliminazione. Comprimi file e cartelle selezionati in ZIP, ridimensiona o converti immagini con gli strumenti immagini e rimanda i risultati riusciti alla vaschetta; importa immagini, video e audio nella libreria dello studio conservando progetto e timeline correnti. |
| Appunti | Cronologia locale ricercabile, filtri per immagini, URL e file e preferiti; cronologia e rilevamento link hanno interruttori indipendenti. Le nuove immagini entrano nella coda locale di riconoscimento: cerca il testo per ritrovare l'originale oppure fai clic destro per riconoscerlo o copiarlo. La riconoscizione in corso può essere annullata; quella in background non copia automaticamente il testo. |
| Monitoraggio AI | Riunisce attività, stato, tendenze token, mappe dei contributi e notifiche laterali da CLI, app desktop e IDE supportati. |
| Download | Usa `yt-dlp` per video e audio; senza `ffmpeg`, AVFoundation combina le tracce compatibili ed è disponibile un percorso Bilibili di sola lettura. |
| Agenda | Meteo della posizione corrente e di fino a sei località salvate; consulta, crea ed elimina eventi e promemoria e segna questi ultimi come completati. L’ora di aggiornamento del meteo appare nell’intestazione, a sinistra del pulsante di aggiornamento. Se i dati meteo sono incompleti, altre fonti completano il risultato più dettagliato; i dati disponibili restano visibili se non è possibile ottenere il resto. |
| Posta | Legge account Mail.app selezionati: posta in arrivo, stato di lettura, risposte, composizione e spostamento nel cestino. |
| Note | Usa Note di Apple come unica fonte per consultare, modificare, creare ed eliminare note Markdown, con anteprima e scrittura automatica delle modifiche. |
| Mixer volume applicazioni | Su macOS 14.4+, modifica volume e silenziamento di ogni app in riproduzione e ne ricorda il volume; richiede Registrazione audio di sistema. |
| Utilità | Timer Pomodoro con un singolo suono e notifica locale alla fine, modalità attiva, prevenzione dello stop per inattività, pulizia schermo/tastiera, suggeritore, specchio fotocamera e svuotamento del cestino con conferma. Il nome del timer vale solo per la sessione corrente e torna a quello predefinito quando termina o viene annullata. |
| Sistema | CPU, GPU, memoria, disco, rete, temperatura e ventole; libera memoria e analizza cache, registri e dati temporanei eliminabili in sicurezza, oltre alla salute della batteria e ai livelli degli accessori. |

### Funzioni tra moduli

- **In riproduzione:** MediaRemote mostra copertina, titolo, avanzamento, testi scorrevoli e controlli; Core Audio identifica l'app sorgente come ripiego. Le sorgenti in pausa, ferme o silenziate sono nascoste.
- **Download del browser:** mostra fonte e avanzamento di Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera e Arc nella Home, nello stato compatto e nelle notifiche laterali.
- **Input vocale:** scorciatoie a commutazione o premi-per-parlare, scorciatoie globali personalizzate, riconoscimento di sistema, organizzazione locale o remota delle trascrizioni e cronologia locale delle registrazioni.
- **Azioni rapide:** dopo ogni copia, una piccola notifica dell'isola mostra anteprima e azioni: aprire link, mostrare file nel Finder, cercare con motore selezionabile, tradurre, calcolare, creare eventi dalle date riconosciute e salvare testi lunghi o immagini. A download completato o file AirDrop ricevuto, la stessa scorciatoia apre la cartella; ciò dipende dalle azioni rapide e non dall'avanzamento download. Riconosce URL, percorsi, email, telefoni, colori CSS con campioni, calcoli, date/orari, testo in lingua diversa dal sistema, codice, testo con conteggi, immagini con miniature e riferimenti a file. Si attiva con pulsanti, `Command+N` aggiuntivo predefinito o modificatore/pulsante laterale configurato. Offre anche copia tramite pulsante sinistro tenuto più clic destro, inizialmente disattivata, blacklist di app, interruttori per tipo e modalità promemoria leggera.
- **CLI e Skills:** rileva, installa, aggiorna e rimuove CLI AI comuni e gestisce Skills locali dalle impostazioni.
- **Animali desktop:** scegli un animale integrato o importato e posizionalo su un lato dell'isola.
- **Aggiornamenti:** Release/Preview determina il paese dell'IP pubblico una volta per avvio. `CN` verifica prima l'appcast firmato Gitee e ritenta GitHub una volta; gli altri paesi fanno il contrario. Se la ricerca fallisce, Gitee resta primo. Sparkle scarica, verifica, installa e riavvia. Il canale vale per verifiche automatiche e manuali.
- **Aspetto e interazione:** tema di sistema, chiaro o scuro, superfici trasparenti o satinate, espansione fissata, più schermi, Spaces e schermi esterni senza notch.
- **Predefiniti:** le nuove installazioni abilitano i moduli. Funzioni, indicatori compatti, notifiche laterali, statistiche della barra dei menu e aggiornamenti sono regolabili separatamente; le installazioni esistenti conservano la configurazione.

### Strumenti indipendenti e flussi

- **Studio di registrazione:** aprilo dalla barra dei menu o dalle impostazioni. Registra schermo, finestra o area con audio di sistema, microfono e camera facoltativi. Modifica video, audio, immagini e testo su più tracce, con sottotitoli, zoom, animazioni ed effetti ritratto/voce; anteprima ed esportazione video, GIF, Live Photo o audio. Alcuni formati richiedono FFmpeg; HDR dipende dal dispositivo. Importa media dallo scaffale nella libreria conservando progetto e timeline correnti.
- **Immagini, audio e PDF:** accesso dalle impostazioni. Immagini: 9 operazioni locali ed export batch/ZIP. Audio: 27 operazioni, tra cui mixer, normalizzazione LUFS ed elaborazione rumore, con FFmpeg e ffprobe. PDF: 14 operazioni; Office richiede LibreOffice o OpenOffice.
- **Riepilogo giornaliero:** scegli 8 modelli e statistiche, visualizza l'anteprima ed esporta PNG manualmente o a un orario giornaliero. I dati indisponibili non diventano zero misurato.
- **Anteprime finestre:** passa sul Dock o usa Command+Tab e fai clic sull'anteprima per attivare la finestra. Gestisci funzione e autorizzazioni nelle impostazioni.
- **Note contestuali e riunioni:** tieni il tasto configurato e agita il puntatore per annotare pagina, finestra o desktop. Gli eventi con link riunione mostrano 10 minuti di conto alla rovescia: partecipa, crea o collega una nota. Gestisci le note sullo scaffale.
- **Agita per rilasciare:** durante il trascinamento mostra una destinazione; l'interruttore nelle impostazioni è indipendente.
- **Uscita e lettore:** scegli dispositivo nell'area media. Impostazioni: sorgente automatica o lettore preferito, layout compatto e condizioni di arresto dei suoni ambientali.
- **Quote AI e ripristini:** mostra quote supportate, tempi di campionamento e ripristino e avvisi bassi, con finestre 5h/7d e budget Cursor USD disponibili. Sono separati dalla cronologia locale dei token. Le quote Gemini e Claude/GPT di Antigravity hanno monitoraggio, visualizzazione e avvisi indipendenti. Le quote di chat di Gemini App usano un Cookie web dello stesso account Google; Gemini CLI resta separato.

### Ordine dei tasti delle azioni rapide

Il popup assegna `Command+1`…`Command+9`, poi `Command+0`, nell'ordine delle azioni. La scorciatoia aggiuntiva per nuove configurazioni è `Command+N` per la prima azione; `Command+Delete` chiude. Configura tasto, pulsante laterale e ordine nelle impostazioni. L'aggiornamento conserva ogni combinazione esplicitamente salvata, compresi vecchio `Command+1`, personalizzazioni e comandi rimossi; soltanto nuove configurazioni o campo assente adottano `Command+N`.

### Posizioni di salvataggio

Impostazioni → Posizione di salvataggio separa download, screenshot, immagini, registrazioni, PDF, azioni rapide e riepiloghi. Le nuove configurazioni usano sottocartelle di `~/Downloads`: `picture` per immagini/screenshot, `video` per registrazioni, `pdf`, `quick`, `daily`. L'audio usa la finestra di export per scegliere file o cartella. Lo scaffale conserva riferimenti agli originali; screenshot e stato delle note contestuali sono locali in `~/Library/Application Support/zisla`, i progetti nella cartella registrazioni e le Note rapide in Note di Apple.

La [guida utente](https://wzz6423.github.io/zisla/help.html?lang=it#help) copre nove temi con passi e brevi video: appunti, cattura, scaffale, riunioni, AI, strumenti media, riepiloghi, note desktop/anteprime e riproduzione/mixer.

### Screenshot: scorciatoie e conservazione

**Conserva** è tra **Fissa** e **Copia** e salva nello scaffale l'immagine modificata finale, con annotazioni e catture scorrevoli completate, senza copiarla negli appunti. PNG e metadati, tra cui app originale e ora, sono in SQLite locale e sopravvivono al riavvio. La categoria **Screenshot conservati** mostra solo queste schede.

**Evidenziatore** segue **Pennello**: evidenziazioni traslucide, linee terminali e segni circolari predefiniti disattivabili nel menu. **Estrai** segue **Sfoca**: estrazione soggetto/sfondo di macOS o selezione libera, anche con più aree unite. Seleziona tutto e Cancella gestiscono le aree; i pixel esterni diventano trasparenti e si può annullare. Raggio angoli iniziale 0, modificabile con maniglia o cursore; il badge mostra `r`. PNG conserva trasparenza e 0 ripristina i pixel originali.

| Contesto | Azione | Scorciatoia |
| --- | --- | --- |
| Globale | Screenshot | `Control+1` |
| Globale | Screenshot scorrevole | `Control+2` |
| Editor | Fissa | `Control+1` |
| Editor | Conserva | `Control+2` |
| Editor | Rettangolo | `Control+3` |
| Editor | Ellisse | `Control+4` |
| Editor | Pennello | `Control+5` |
| Editor | Evidenziatore | `Control+6` |
| Editor | Freccia | `Control+7` |
| Editor | Numero | `Control+8` |
| Editor | Testo | `Control+9` |
| Editor | Sfoca | `Control+0` |
| Editor | Estrai | `Control+A` |
| Editor | Cattura scorrevole | `Control+B` |
| Editor | Copia | `Enter` |
| Editor | Salva | `Command+S` |
| Editor | Annulla | `Command+Z` |
| Editor | Ripeti | `Command+Shift+Z` |

Le impostazioni mostrano e registrano tasti globali e dell'editor. Copia, Salva, Annulla e Ripeti sono visibili ma non registrabili. Gli aggiornamenti conservano i tasti dell'utente. Fissa è un'azione dell'editor, non un tasto globale separato; resta l'accesso nel menu.

I predefiniti seguono la barra: `Control+1`…`Control+9`, `Control+0`, `Control+A`, `Control+B` e lettere successive. Saltano `Q`, `M`, `N`, `W`, perché premere Command per errore potrebbe uscire, minimizzare, aprire o chiudere una finestra. Le combinazioni registrate dall'utente sono comunque consentite.

Gli schemi precedenti non modificati, compreso il vecchio Fissa/Conserva, passano una volta ai nuovi valori. Se qualsiasi tasto screenshot è personalizzato, l'intero schema resta; le nuove azioni con conflitto prendono una combinazione Control libera nello stesso ordine sicuro. Anche queste combinazioni possono essere registrate di nuovo.

## Avvio rapido

### Ambiente

- macOS 14+
- Swift 6 / Xcode 16+; bastano anche i Command Line Tools
- Facoltativi: `yt-dlp`, `ffmpeg`; Office-PDF richiede LibreOffice/OpenOffice

Con Homebrew:

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### Esecuzione dai sorgenti

```bash
swift run zisla
```

L'app parte come accessorio della barra dei menu. Entra con il puntatore nei 6 px superiori centrali dello schermo corrente oppure scegli “Mostra isola” dal menu.

### Compilare una `.app`

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

Per includere l'helper ufficiale `yt-dlp`:

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh` scarica una versione standalone macOS ufficiale fissata e la verifica con `SHA2-256SUMS` ufficiale prima di installarla in `Tools/yt-dlp`.

## Integrazione degli strumenti AI

### Rilevamento automatico

zisla legge stato di sessione pubblico o locale stabile ed estrae solo eventi strutturati e metadati necessari. Non legge prompt o risposte.

| Ambiente | Rilevamento |
| --- | --- |
| OpenAI / Anthropic | Codex CLI e Desktop, Claude Code e ambienti ospitanti |
| GitHub / Google / xAI | Copilot CLI e VS Code, Gemini CLI e Desktop, Grok CLI |
| Strumenti indipendenti e regionali | Pi, Kimi Code, Qwen Code, Qoder, ZCode Desktop/CLI, TRAE, OpenCode, Harnext/Harness, WorkBuddy |

Attesa di approvazione/risposta: giallo; errori di comandi/strumenti: rosso; esecuzione normale: verde. Fonti simultanee sono raggruppate rosso, giallo, verde. Il sidecar Qwen è attivo solo finché il PID esiste, evitando stati obsoleti dopo l'uscita.

Se un'app desktop conversazionale non salva eventi strutturati, non si può distinguere un'app aperta inattiva da una generazione in corso. Strumenti come ChatGPT devono usare l'hook `zislactl`; il processo residente non simula attività.

### Protocollo locale `zislactl`

`zislactl` scrive stato e utilizzo in SQLite:

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

La cronologia sopravvive a riavvii, sostituzioni dell'app e pulizia delle attività; si perde solo eliminando manualmente i dati dell'app.

Esempio:

```bash
swift run zislactl update \
  --id build-42 \
  --provider claude \
  --title "Refactor index" \
  --progress 68 \
  --detail "17/25"

swift run zislactl usage \
  --provider claude \
  --input-tokens 12400 \
  --output-tokens 2100 \
  --model claude-opus-4-8

swift run zislactl finish --id build-42 --detail "Complete"
```

Provider canonici: `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `zcode`, `trae`, `opencode`, `pi`, `harness`, `doubao`. Gli alias comuni vengono normalizzati. Invocalo da hook, wrapper shell o script.

Elenco AI e stato compatto usano i loghi ufficiali per identificare la fonte. Vedi il [riferimento CLI](Docs/cli-reference.md).

## Avanzamento download del browser

zisla ascolta l'avanzamento pubblico dei file nella directory Download e combina estensioni temporanee, attributi di origine e browser in esecuzione. Non legge cronologia né fa richieste per rilevare avanzamento. Il completamento resta circa tre secondi. Le azioni rapide usano gli stessi eventi e offrono Apri cartella quando il trasferimento riuscito raggiunge il percorso finale; la durata segue le impostazioni e l'ultima copia o trasferimento sostituisce il messaggio precedente.

## Downloader

Ordine degli eseguibili:

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

L'URL è un argv separato di `Process`, senza shell. Configurazione runtime e plugin sono ignorati, `--exec` è disabilitato, si applica il limite a un elemento e si verifica che il file finale resti nella directory autorizzata.

Senza `ffmpeg`:

- Video: preferisce AVC/MP4 e audio M4A, combinati in MP4 con AVFoundation; il formato singolo rimane invariato.
- Audio: preferisce M4A o mantiene il formato originale.
- Con HTTP 412, formato assente o yt-dlp locale mancante, Bilibili recupera tracce DASH tramite API di sola lettura e usa lo stesso confezionamento nativo, senza altri strumenti.

## Note

Markdown usa Note di Apple come unica fonte: creazione, lettura, modifica ed eliminazione, non solo aggiunta.

- **Elenco:** all'apertura JXA (`osascript -l JavaScript`) legge titolo e data delle note non eliminate e ordina per modifica recente. Tornando da Note aggiorna l'elenco, esclude Eliminate di recente e consente selezione, aggiornamento, nuova nota o eliminazione contestuale.
- **Vista e modifica:** AppleScript legge `plaintext`, il sorgente Markdown. `TextEditor` salva dopo circa 0,8 s di inattività, evitando una chiamata per tasto. Le nuove note sono create in Note di Apple e selezionate.
- **Anteprima:** il parser a blocchi rende titoli, liste non ordinate/ordinate/attività, citazioni, codice recintato, linee, grassetto, corsivo, codice inline, barrato e link con `AttributedString`.
- **Archiviazione:** salva il sorgente nel `body` come testo ordinario con escape HTML e righe vuote conservate. `plaintext` lo ripristina; Note di Apple mostra testo normale, non Markdown renderizzato.
- **Autorizzazioni:** la prima lettura/scrittura richiede Automazione per Note; una negazione produce un avviso dall'elenco o editor.

Nessuna seconda copia locale: Note di Apple è il backend.

## Autorizzazioni e privacy

- **Calendario:** Calendari e Promemoria hanno richieste separate al primo accesso; dopo creazione, eliminazione o completamento si aggiornano.
- **Posizione:** richiesta meteo una sola volta, senza tracciamento continuo; cerca, salva e rimuovi altre località nelle impostazioni.
- **File e download:** directory selezionate con segnalibri ad ambito di sicurezza; trasferire non copia l'originale.
- **Appunti:** nuove installazioni con cronologia e link attivi separatamente. Ogni `changeCount` riconosce al massimo un link localmente; non registra query né chiama API di svuotamento, dichiarazione tipo o scrittura, così non sostituisce gli appunti universali.
- **Azioni rapide:** opera localmente a ogni `changeCount` se abilitata, anche per download finiti e AirDrop ricevuti. Modificatori/mouse possono usare Monitoraggio input; il gesto copia invia ⌘C sintetico e richiede Accessibilità. Il riconoscimento non usa rete; apri, cerca, traduci, salva solo su comando. Blacklist e interruttori per tipo controllano prompt di copia; l'interruttore generale controlla anche quelli di trasferimento.
- **Stato AI:** solo eventi strutturati e metadati locali necessari a determinare lo stato.
- **Voce:** microfono e riconoscimento solo dopo azione esplicita. Registrazioni, testo grezzo e organizzato locali; il testo va solo al modello/provider/profilo CLI scelto e le credenziali remote sono in un database privato.
- **Bluetooth e dispositivi:** livelli degli accessori e dispositivi mobili Apple fidati solo con vista Batteria di Sistema aperta.
- **Fotocamera e input:** specchio e studio richiedono Camera per anteprima/registrazione. Suoni, statistiche, pulizia e modificatori/mouse usano Monitoraggio input; statistiche locali e interruttori indipendenti.
- **Schermo e audio:** screenshot, registrazioni e anteprime con Registrazione schermo. Registra sorgenti selezionate localmente; microfono/camera solo se abilitati. Mixer su macOS 14.4+ con Registrazione audio di sistema e tap Core Audio locali.
- **Browser:** solo avanzamento pubblico e file temporanei; non cronologia o contenuto delle pagine.
- **Media:** MediaRemote fornisce metadati e Core Audio verifica uscita. MediaRemote è privato, quindi la build non è idonea all'invio diretto al Mac App Store. Se mancano metadati, mostra l'app audio attiva.
- **Rete:** Le previsioni interrogano China Weather, Open-Meteo e MET Norway secondo la regione e consultano altre fonti se i dati sono incompleti. Le allerte ufficiali vengono recuperate separatamente da China Weather o WeatherKit. `ipinfo.io/country` determina una volta per avvio il paese: `CN` Gitee poi GitHub, altri inverso, errore Gitee primo. Bilibili usa informazioni/playback/CDN di sola lettura; link appunti riconosciuti offline. Quote account attive contattano provider; traduzione, AI registrazioni e pulizia trascrizioni usano modello/CLI scelti. Apple può usare rete per voce secondo sistema/lingua. Installazioni e aggiornamenti dipendenze/CLI, IP pubblico e azioni di rete scelte contattano servizi.
- **Automazione:** AppleScript/JXA elenca, legge, modifica, crea ed elimina Note di Apple, con autorizzazione, senza rete e con dati in Note.

## Test

Con Xcode completo:

```bash
swift test
```

Con soli Command Line Tools:

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Documentazione

- [Architettura e prestazioni](Docs/architecture.md)
- [Riferimento CLI](Docs/cli-reference.md)
- [Firma e rilascio](Docs/releasing.md)
- [Dipendenze incluse](../../../../mac/Vendor/README.md)
- [Avvisi di terze parti](../../../../mac/Resources/ThirdPartyLicenses/README.md)

## Limiti di sistema

- macOS non ha API pubblica Dynamic Island. Il notch viene dedotto da `safeAreaInsets` e area ausiliaria superiore; sugli altri schermi si usa la stessa sovrapposizione.
- Video DRM, finestre login, blocco schermo e alcune app a tutto schermo esclusivo possono non offrire dati media né sovrapposizioni.
- App senza integrazione media possono mostrare la sorgente audio ma non garantiscono titolo, copertina o avanzamento; video in pausa, fermi e silenziati sono nascosti volutamente.
- Il browser deve pubblicare avanzamento macOS o usare temporanei riconoscibili in Download per mostrare percentuali.
- Batteria, temperatura, potenza e accessori dipendono da hardware, connessione e dati macOS; campi assenti sono indisponibili.
- Office-PDF richiede LibreOffice/OpenOffice; il resto del PDF è locale.
- Pacchetti non autenticati possono richiedere **Apri comunque**. I rilasci stabili mantengono un certificato autofirmato, preservando le autorizzazioni negli aggiornamenti; Sparkle verifica separatamente ciascun aggiornamento con la chiave EdDSA integrata prima di estrarre, sostituire e riavviare.

## Licenza

[PolyForm Noncommercial License 1.0.0](../../../../LICENSE.md). Uso non commerciale consentito; vendita o altro uso commerciale vietati.
