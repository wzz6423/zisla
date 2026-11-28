# Architettura e progettazione delle prestazioni

**Italiano** | [English](../../../../../mac/Docs/architecture.md) | [简体中文](../../../../../mac/Docs/architecture.zh-CN.md) | [Altre lingue](../../../README.md)

## Attivazione dal bordo superiore

Lo stato nascosto non usa una finestra trasparente. `PointerEdgeMonitor` installa monitor `NSEvent` globali e locali per movimenti e trascinamenti del mouse; `ScreenLayoutEngine` usa soltanto la geometria per verificare l'ingresso nei 6 px centrali del bordo superiore di ogni schermo.

Ogni schermo ha un'identità stabile che associa `NSScreenNumber` al relativo `CGDirectDisplayID`. Il layout è ancorato a `screen.frame.maxY`, quindi supporta coordinate negative, schermi sovrapposti verticalmente e schermi esterni senza notch.

Con più schermi collegati, Impostazioni → Generali → Modalità degli schermi permette di scegliere per ciascuno la modalità Dynamic Island (posizione della fotocamera o personalizzata), la modalità notch o di nasconderla. Con un solo schermo questa impostazione è nascosta e si usa l’aspetto globale; ricollegando gli schermi si ripristinano le configurazioni salvate. Tutti gli schermi visibili mantengono l’isola chiusa contemporaneamente. L’espansione, le azioni rapide, la registrazione e i messaggi temporanei sostituiscono solo l’isola del proprio schermo; la selezione degli schermi per le notifiche filtra il contenuto senza nascondere l’isola inattiva.

## Finestra

L'isola principale mantiene un solo pannello `.borderless + .nonactivatingPanel`:

- Usa il livello `.statusBar` e non copre il blocco schermo o i menu di sistema.
- `.canJoinAllSpaces + .fullScreenAuxiliary` supporta Spaces e normali app a tutto schermo.
- L'espansione al passaggio del puntatore non chiama mai `NSApp.activate`, quindi non sottrae il focus all'app corrente.
- Lo stato nascosto usa `orderOut`, evitando che una finestra trasparente occupi l'area della barra dei menu.

I pannelli di notifica sinistro e destro vengono creati quando servono e nascosti appena le code sono vuote.

## Stato e concorrenza

- AppKit, stato SwiftUI e gestione delle finestre restano su `MainActor`.
- Quando la gestione della barra dei menu è attiva, zisla crea due controlli `NSStatusItem`. Mentre l’elenco delle icone è aperto, legge `AXExtrasMenuBar` e verifica la posizione dell’icona selezionata dopo lo spostamento.
- Download, meteo e richieste GitHub usano actor.
- Lo stato AI scritto dagli hook viene osservato tramite eventi del filesystem sulla directory. Ogni fonte di sessioni AI confronta data di modifica e dimensione dell'ultimo file locale di sessione o attività e riutilizza la cache di parsing se nulla cambia.
- Il rilevamento automatico legge solo eventi strutturati, marcatori fissi e metadati necessari a determinare lo stato delle attività. Non legge prompt o risposte; un errore del parser di un provider non blocca gli altri.
- Le quote degli account AI sono rilevate separatamente dai fornitori. Le quote Gemini e Claude/GPT di Antigravity mantengono periodi di ripristino e avvisi propri. La quota di chat ordinaria di Gemini App usa il Cookie web salvato dello stesso account Google; Gemini CLI mantiene la fonte OAuth locale. Le quote mancanti non vengono stimate.
- Il ritardo di chiusura usa `Task` annullabili e un token di generazione, così una vecchia operazione non può nascondere un'isola già riaperta.
- Lo stato nascosto non usa `TimelineView`, timer a 60 Hz o invii continui di animazioni.

## Rilevamento dei media

MediaRemote fornisce titolo, copertina, avanzamento e controlli. Le proprietà degli oggetti processo di Core Audio 14.4+ confermano un flusso di uscita attivo e identificano l'app sorgente quando mancano i metadati. Elenco dei processi e stato di uscita usano listener delle proprietà con verifiche periodiche limitate; non acquisiscono contenuti audio e non richiedono Registrazione schermo o Accessibilità. Sorgenti in pausa, ferme o silenziate non restano nell'area media.

## Registrazione e mixer delle applicazioni

Registrazione schermo e mixer del volume sono percorsi separati dal rilevamento dei metadati. La registrazione richiede Registrazione schermo e le autorizzazioni dei microfoni/fotocamere abilitati, salva localmente i media selezionati e gestisce i progetti nella cartella di registrazione scelta. Il mixer usa tap Core Audio su macOS 14.4+ e richiede Registrazione audio di sistema.

## Materiali

macOS 26 usa un singolo livello SwiftUI `glassEffect`; macOS 14/15 usano un singolo livello `NSVisualEffectView`. Riduci trasparenza attiva uno sfondo opaco. L'isola non sovrappone più livelli di sfocatura o materiale.

## Limiti di sicurezza dei download

Swift avvia `yt-dlp` con `Process.executableURL` e un array di argomenti; l'URL è sempre un valore argv separato dopo `--`. Configurazione a runtime, plugin ed exec sono disabilitati, le pipe di output vengono svuotate contemporaneamente e l'avanzamento viene analizzato tramite un marcatore JSON.

Un'attività riesce solo se il codice di uscita è 0, il percorso di output esiste e il percorso risolto resta dentro la directory autorizzata. Ogni attività pulisce solo la propria directory temporanea identificata da UUID.

## Verifica e download degli aggiornamenti

Il canale selezionato determina il codice del paese dell'IP pubblico una volta per avvio. Sparkle recupera l'appcast firmato per la build installata, scarica lo ZIP via HTTPS, verifica le firme EdDSA dell'archivio e del feed prima dell'estrazione, sostituisce l'app e la riavvia. `CN` usa prima Gitee (`update-release` per Release, `preview` per Preview), poi ritenta una volta il feed GitHub corrispondente; gli altri paesi usano l'ordine inverso. Se la ricerca del paese non riesce, resta la priorità Gitee. Ogni feed punta a uno ZIP firmato sul proprio host.

Il rilascio pubblica un appcast per architettura accanto al comune `appcast.xml`. Un'installazione a singola architettura richiede il feed della propria slice (una slice x86_64 eseguita tramite traduzione richiede `arm64`), quindi non viene sostituita dalla build Universal. Un'installazione Universal conta le slice del proprio eseguibile e continua a usare `appcast.xml`, che serve anche le versioni precedenti agli aggiornamenti separati per architettura. Cambiare canale modifica le verifiche automatiche e manuali e reimposta il prossimo ciclo Sparkle. La chiave pubblica integrata non contiene informazioni di account; quella privata resta nel Portachiavi macOS del responsabile del rilascio o in un file protetto separato.
