# zisla

**Italiano** | [English](../../../README.md) | [简体中文](../../../README.zh-CN.md) | [Altre lingue](../README.md)

**zisla è uno spazio di lavoro nativo per macOS che compare quando serve e si ritira quando hai finito.** Sposta il puntatore al centro del bordo superiore dello schermo per aprire un unico accesso leggero alle attività AI, ai media, al trasferimento di file, ai download e alle utilità del desktop. Gli schermi senza notch usano la stessa area di stato simulata.

L'implementazione attuale richiede **macOS 14+**. Apple Silicon è la configurazione supportata; i pacchetti di rilascio Intel possono funzionare, ma la compatibilità non è garantita.

[Guarda la presentazione completa — 2:40 · 1080p / 60 fps](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

[![Guarda il video di lancio di zisla](../../../web/public/media/zisla-launch-poster.webp)](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

Musica: “Funkorama” di Kevin MacLeod · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Fonte](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474).

## Perché tenerlo nella parte superiore dello schermo

- **Disponibile quando serve, senza sottrarre il focus.** Espandilo dal bordo superiore, fissalo se necessario e continua a lavorare nell'app corrente.
- **Un unico posto per le attività in corso.** Consulta riproduzione, attività AI, download, timer, posta, stato del sistema e batteria senza aprire una dashboard completa.
- **Attività AI senza accesso alle conversazioni.** zisla legge solo gli eventi strutturati e i metadati locali necessari a determinare lo stato delle attività. Non legge mai prompt o contenuti delle risposte.
- **Controlli locali.** Moduli, cronologia degli appunti e rilevamento dei link hanno interruttori indipendenti; le autorizzazioni vengono richieste solo al primo utilizzo della funzione.

## Cosa può fare

### Continuare il lavoro sul desktop

| Funzione | Comportamento |
| --- | --- |
| In riproduzione | Mostra copertina, titolo, avanzamento, testi e controlli di riproduzione; Core Audio può identificare l'app che emette realmente audio quando i metadati non sono disponibili. |
| Trasferimento e condivisione | Trascina file, media o link nell'area superiore per conservarli nella vaschetta di trasferimento, mostrarli nel Finder o aprire il menu di condivisione di macOS. Comprimi file e cartelle selezionati in ZIP, ridimensiona o converti le immagini selezionate con gli strumenti immagini e rimanda i risultati riusciti alla vaschetta, oppure importa immagini, video e audio nella libreria dello studio di registrazione conservando progetto e timeline correnti. |
| Appunti e notifiche | Registra facoltativamente la cronologia locale degli appunti, riconosce i nuovi link sul dispositivo e mostra media, attività AI, download del browser, timer, posta e aggiornamenti nello stato compatto. Le azioni rapide facoltative mostrano una piccola notifica nell'isola dopo ogni copia, con anteprima e azioni pertinenti: apri, mostra nel Finder, cerca, traduci, calcola o salva. Dopo un download del browser o l'arrivo di un file AirDrop, la stessa scorciatoia può aprirne la cartella. Le nuove immagini della cronologia entrano nella coda di riconoscimento del testo sul dispositivo; cerca il loro testo per ritrovare l'immagine originale oppure fai clic destro per riconoscere o copiare il testo. |
| Spazio quotidiano | Include meteo, calendario, promemoria, Mail.app, note Markdown archiviate in Note di Apple, informazioni nella schermata di blocco e animali desktop facoltativi. |

### Rendere visibile il lavoro AI

zisla monitora l'attività locale di Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, Delta, Orca, TRAE, OpenCode, Harnext, WorkBuddy, WorkBuddy AI e altre fonti supportate. Mostra attività, stato, tendenze dei token, mappe dei contributi e notifiche laterali.

Per gli strumenti senza una fonte locale stabile, `zislactl` consente a script, CI e hook di inviare avanzamento, utilizzo e notifiche mantenendo lo stato del protocollo su questo Mac. Le impostazioni possono anche rilevare, installare, aggiornare e rimuovere le CLI AI comuni e gestire Skills locali. Consulta il [riferimento per l'integrazione CLI](mac/Docs/cli-reference.md) per provider e comandi.

### Svolgere le piccole attività utili

| Area | Strumenti inclusi |
| --- | --- |
| Download e documenti | Download di video e audio tramite `yt-dlp`; unione, divisione, rotazione, ritaglio, conversione e rendering dei PDF locali, esportazione del testo, filigrane, numeri di pagina, cifratura, sblocco e modifica dei metadati. |
| Concentrazione e presentazioni | Timer Pomodoro con un singolo avviso sonoro e una notifica locale a fine sessione, modalità che mantiene il Mac attivo, prevenzione dello stop per inattività, pulizia di schermo e tastiera, suggeritore e specchio della fotocamera. |
| Sistema e batteria | Informazioni su CPU, GPU, memoria, disco, rete, ventole e batteria, oltre alla pulizia di cache e registri eliminabili in sicurezza. |
| Input vocale | Scorciatoie globali per registrazione e trascrizione, organizzazione facoltativa delle trascrizioni tramite modelli locali o remoti e cronologia vocale locale. |

### Accessi e flussi di lavoro attuali

L'isola contiene 12 moduli: Home, Trasferimento, Appunti, Monitoraggio AI, Suoni della tastiera, Download, Agenda, Posta, Note, Mixer del volume delle applicazioni, Utilità e Sistema. I dettagli della batteria sono in Sistema; la visualizzazione nella schermata di blocco è separata. Apri gli strumenti PDF, immagini e audio dalle impostazioni e lo studio di registrazione dalle impostazioni o dalla barra dei menu.

- **Registrazione e creazione:** registra uno schermo, una finestra o un'area con audio di sistema, microfono e fotocamera facoltativi. Modifica sottotitoli, zoom ed effetti per ritratto e voce su più tracce, visualizza l'anteprima ed esporta video, GIF, Live Photo o audio. Gli strumenti immagini offrono 9 operazioni locali; quelli audio ne offrono 27.
- **Mixer e riproduzione:** macOS 14.4+ supporta volume e silenziamento per app. Scegli l'uscita audio nell'area media e le preferenze del lettore nelle impostazioni.
- **Desktop e riunioni:** anteprime delle finestre nel Dock e con Command+Tab, note contestuali per pagine web, finestre e desktop, conto alla rovescia di 10 minuti per le riunioni, accesso e note collegate. Agita il puntatore mentre trascini file per mostrare la destinazione dello scaffale.
- **Riepilogo giornaliero:** 8 modelli, anteprima, esportazione PNG manuale o programmata, statistiche selezionate e cartella di salvataggio indipendente.
- **Account AI:** consulta quote disponibili, orari di ripristino, avvisi di quota bassa e tempi di campionamento supportati; esporta la cronologia locale dei token in `.xlsx`. Le quote Gemini e Claude/GPT di Antigravity hanno monitoraggio, visualizzazione e avvisi indipendenti. Le quote di chat di Gemini App usano un Cookie web dello stesso account Google; Gemini CLI resta separato.
- **Azioni rapide:** nel popup, `Command+1` fino a `Command+0` seguono l'ordine delle azioni. Per le nuove configurazioni, il comando aggiuntivo predefinito `Command+N` esegue la prima azione. Gli aggiornamenti conservano scorciatoie salvate e comandi rimossi.

La [guida utente](https://wzz6423.github.io/zisla/help.html?lang=it#help) offre nove guide passo dopo passo: appunti, cattura, scaffale, riunioni, AI, strumenti media, riepiloghi giornalieri, note del desktop/anteprime delle finestre e riproduzione/mixer. La [guida macOS](mac/README.md#posizioni-di-salvataggio) elenca cartelle di output e dipendenze.

## Iniziare

### Installare l'app

Scarica l'ultimo DMG da [GitHub Releases](https://github.com/wzz6423/zisla/releases) o [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), montalo e trascina `zisla.app` in `Applications`.

Puoi anche usare Homebrew:

```bash
brew install --cask wzz6423/tap/zisla
```

Homebrew scarica la build corrispondente al tuo chip: un Mac Apple Silicon o Intel riceve solo la propria architettura. Il cask proviene dal tap di terze parti `wzz6423/tap`, non dal repository ufficiale dei cask Homebrew; installarlo significa quindi fidarsi di questo tap.

Dopo l'avvio, sposta il puntatore al centro del bordo superiore dello schermo corrente oppure scegli **Mostra isola** dall'icona nella barra dei menu. I pacchetti non sono autenticati da Apple; al primo avvio, qualunque sia il metodo di installazione, seleziona **Apri comunque** in **Impostazioni di Sistema > Privacy e sicurezza** oppure rimuovi manualmente l'attributo di quarantena:

```bash
xattr -d com.apple.quarantine /Applications/zisla.app
```

### Aggiornare l'app

zisla si aggiorna con Sparkle indipendentemente dal metodo di installazione. Con Homebrew, `brew upgrade` sostituisce l'app solo se la copia installata è davvero precedente alla versione nel tap: da Homebrew 5.1.6 viene letta la versione nel bundle, quindi un aggiornamento Sparkle non viene sovrascritto e l'installazione non resta obsoleta. Specificando il cask, invece, valgono i registri di installazione di Homebrew, che possono riportare un'app aggiornata da Sparkle alla versione del tap:

```bash
brew upgrade --cask zisla
```

Il tap distribuisce solo rilasci stabili; le anteprime restano su Releases, quindi `brew upgrade` non passa a una versione preliminare. Se specifichi il cask mentre usi un'anteprima, la sostituisci con la build stabile corrente. Sparkle non effettua downgrade: tornando al canale Release resti sull'anteprima finché un rilascio stabile non la supera. `brew uninstall --cask zisla` rimuove l'app; `brew uninstall --zap --cask zisla` elimina anche i dati locali.

### Eseguire dai sorgenti

Sono necessari Swift 6 / Xcode 16+; il progetto può essere compilato anche con i soli Command Line Tools.

```bash
cd mac
swift run zisla
```

Il downloader richiede `yt-dlp`; `ffmpeg` è facoltativo. Per convertire Office in PDF serve LibreOffice o OpenOffice. Le istruzioni di compilazione, test e creazione dei pacchetti sono nella [guida di sviluppo macOS](mac/README.md).

## Progettato per non intralciare

- Supporta più schermi, Spaces e normali app a tutto schermo senza attivare l'app né sottrarre il focus a quella corrente.
- Lo stato nascosto non usa una finestra trasparente permanente né un ciclo di rendering; l'espansione dipende da eventi globali e controlli geometrici.
- Usa un solo materiale di sistema e passa a uno sfondo opaco quando è attiva Riduci trasparenza.
- Rileva il notch fisico tramite l'area sicura di sistema; sugli schermi esterni senza notch usa una sovrapposizione con lo stesso contorno.

Consulta [architettura e prestazioni](mac/Docs/architecture.md) per le scelte implementative.

## Privacy e autorizzazioni

zisla richiede un'autorizzazione solo quando una funzione abilitata ne ha bisogno per la prima volta. Puoi disattivare i moduli nelle impostazioni e revocare le autorizzazioni nelle impostazioni di macOS in qualunque momento.

| Ambito | Limite |
| --- | --- |
| Attività AI | Legge soltanto eventi strutturati e metadati locali. Non legge mai prompt o testo delle risposte. |
| Appunti e file | Cronologia, rilevamento dei link e azioni rapide sono interruttori locali separati. Le azioni rapide gestiscono download completati e file AirDrop ricevuti indipendentemente dall'avanzamento dei download del browser. Il riconoscimento avviene interamente sul dispositivo; i link e le azioni si aprono solo dopo un clic o un comando esplicito. Il trasferimento usa segnalibri con ambito di sicurezza e non copia il file originale. |
| Note, posta e voce | Note e Mail usano AppleScript/JXA con l'autorizzazione Automazione. La voce viene registrata solo mentre la funzione è attiva; l'organizzazione della trascrizione invia testo solo al modello locale, provider remoto o profilo CLI selezionato. |
| Download del browser e media | Usa informazioni pubbliche di avanzamento file di macOS, metadati MediaRemote e stato di uscita Core Audio. Non legge i database della cronologia del browser. Forme d'onda di sistema e mixer elaborano audio localmente; le registrazioni salvano audio solo quando la sorgente corrispondente è abilitata. |
| Rete | Meteo, ricerca dell'IP pubblico, selezione del mirror di aggiornamento, download, verifiche delle quote AI abilitate e installazione di dipendenze/CLI contattano i rispettivi servizi. Traduzione, pulizia vocale e modifiche AI delle registrazioni usano il provider o la CLI selezionati. Il riconoscimento vocale Apple può usare la rete secondo il supporto di sistema e lingua. |

### Autorizzazioni per funzione

zisla richiede l'autorizzazione necessaria al primo utilizzo. Se l'hai negata in precedenza, apri la relativa voce in **Impostazioni di Sistema > Privacy e sicurezza** e consenti l'accesso a `zisla`; i nomi possono variare tra versioni di macOS.

| Autorizzazione o impostazione | Quando serve | Ambito autorizzato |
| --- | --- | --- |
| Controllo dispositivo e accesso ai dati (Accessibilità in alcune versioni) | Inserire automaticamente le trascrizioni nel campo di testo dell'app corrente | Individua i campi di input non destinati a password e inserisce il testo tramite API di accessibilità o `Cmd+V`. Senza autorizzazione, la trascrizione viene comunque copiata negli appunti. |
| Microfono | Input vocale o attivazione del microfono nello studio | Acquisisce il microfono selezionato per registrazione o monitoraggio abilitato. |
| Riconoscimento vocale | Trasformare l'audio registrato in testo | Elabora soltanto la voce registrata attivamente. L'input vocale richiede sia Microfono sia Riconoscimento vocale. |
| Accesso completo al disco | Visualizzare la posta mentre Mail.app non è in esecuzione | Legge l'indice locale in `~/Library/Mail` per account, mittenti, oggetti, riepiloghi, orari e stato di lettura. Questo accesso all'indice richiede autorizzazione. |
| Automazione | Leggere, scrivere, rispondere, contrassegnare o eliminare messaggi Mail.app; leggere e scrivere Note di Apple | Consente a zisla di controllare le rispettive app di sistema. Le autorizzazioni di Mail e Note sono revocabili separatamente. |
| Calendari; Promemoria | Usare il modulo agenda | Legge e gestisce eventi e promemoria con autorizzazioni separate. |
| Localizzazione | Meteo della posizione corrente | Richiede la posizione una volta, senza tracciamento continuo. Le località aggiunte manualmente non richiedono accesso alla posizione. |
| Fotocamera | Aprire lo specchio o attivare anteprima/registrazione della fotocamera nello studio | Usa la fotocamera selezionata mentre la funzione corrispondente è attiva. |
| Monitoraggio input | Suoni della tastiera, statistiche di digitazione, pulizia tastiera e scorciatoie con soli modificatori o pulsanti laterali del mouse | Osserva gli eventi della funzione abilitata; le statistiche restano locali. Le normali scorciatoie globali non richiedono questa autorizzazione. |
| Bluetooth | Consultare la batteria degli accessori in Sistema → Batteria | Legge solo le informazioni di batteria pubbliche di dispositivi connessi o abbinati. |
| Registrazione schermo e audio di sistema (Registrazione schermo nelle versioni precedenti) | Screenshot, anteprime finestre, registrazione, forme d'onda audio e mixer delle app | Legge immagini dello schermo e sorgenti audio selezionate. Salva localmente le sorgenti abilitate; il mixer richiede macOS 14.4+. |
| Notifiche | Avvisi Pomodoro | Riproduce un singolo avviso sonoro e mostra una notifica locale a fine timer. |
| Cartelle selezionate dall'utente (nessuna autorizzazione manuale) | Trasferimento, importazione, esportazione e cartella dei download | Il selettore di file concede accesso alla cartella scelta. Non è necessario Accesso completo al disco. |

La revoca di un'autorizzazione disabilita solo la funzione corrispondente. Se una funzione resta indisponibile dopo una modifica, chiudi e riapri zisla, poi riprova.

La [guida macOS](mac/README.md#autorizzazioni-e-privacy) descrive tutte le autorizzazioni e il comportamento di rete.

## Documentazione

| Documento | Scopo |
| --- | --- |
| [Guida di sviluppo macOS](mac/README.md) | Moduli, integrazione AI, dipendenze, compilazione, test, autorizzazioni e limiti di sistema. |
| [Guida del sito](../../../web/README.md) | Sviluppo locale, build di produzione e download correnti. |
| [Guida del video di lancio](../../../promo/README.md) | Anteprima e rendering Remotion, composizioni, musica e licenze degli asset. |
| [Architettura e prestazioni](mac/Docs/architecture.md) | Bordo superiore, finestre, concorrenza, media e sicurezza dei download. |
| [Riferimento CLI](mac/Docs/cli-reference.md) | Provider, comandi, campi e codici di uscita di `zislactl`. |
| [Firma e rilascio](mac/Docs/releasing.md) | Firma, autenticazione Apple, DMG, canali di aggiornamento e verifica del rilascio. |
| [Guida ai contributi](CONTRIBUTING.md) | Ambiente di sviluppo, branch, commit e requisiti delle pull request. |

## Contribuire

Issue e pull request sono benvenute. Leggi prima la [guida ai contributi](CONTRIBUTING.md). Segnala i problemi di sicurezza privatamente tramite [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), senza aprire una issue pubblica.

## Licenza

[PolyForm Noncommercial License 1.0.0](../../../LICENSE.md). È consentito l'uso non commerciale; non sono consentiti la vendita del software o altri usi commerciali.
