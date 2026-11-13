import { createCatalog } from './createCatalog';

export const it = createCatalog({
  meta: {
    documentTitle: 'zisla · Spazio di lavoro dinamico',
    description:
      'zisla è uno spazio macOS nativo per attività IA, resoconti giornalieri e montaggio delle registrazioni, con compagni propri, catture e permessi riuniti.',
    ogTitle: 'zisla · Porta ciò che accade dove puoi vederlo',
    ogDescription:
      'Tieni in vista attività IA e la tua giornata, registra e monta su Mac, importa il tuo compagno e gestisci i permessi in un solo posto.',
  },
  tagline: 'Spazio di lavoro dinamico nativo per macOS',
  header: {
    navAriaLabel: 'Navigazione principale',
    brandHomeAriaLabel: 'Home di zisla',
    menuOpenLabel: 'Apri il menu di navigazione',
    menuCloseLabel: 'Chiudi la navigazione',
    menuButtonTitle: 'Apri la navigazione',
    navItems: {
      showcase: 'Funzioni',
      ai: 'Flusso IA',
      download: 'Download',
      changelog: 'Registro modifiche',
      faq: 'Domande frequenti',
      developers: 'Sviluppatori',
    },
    downloadCta: 'Scarica',
    downloadCtaAriaLabel: 'Vai alla sezione download',
    languageLabel: 'Lingua dell’interfaccia',
    themeLabel: 'Aspetto',
    themeModes: { auto: 'Automatico (sistema)', light: 'Modalità chiara', dark: 'Modalità scura' },
  },
  hero: {
    eyebrow: 'SPAZIO DI LAVORO NATIVO PER MACOS',
    title: 'zisla<br><em>Ciò che accade,<br>proprio dove puoi vederlo.</em>',
    lede:
      'Riunisci attività IA, media, file e agenda nella parte superiore dello schermo. Dopo una copia, una barra delle azioni rapide separata mostra un’anteprima e suggerisce il passo successivo. Appare quando serve e si fa da parte quando hai finito.',
    downloadCta: 'Scarica',
    downloadCtaAriaLabel: 'Scarica',
    sourceCta: 'Vedi il codice',
    sourceCtaAriaLabel: 'Vedi il codice sorgente di zisla su GitHub',
    hints: [
      'Porta il puntatore in alto per espandere, senza clic',
      'Dopo una copia, premi Command+N per il passo intelligente successivo',
      'Si richiude da sola senza interrompere il lavoro',
    ],
  },
  proof: {
    ariaLabel: 'Panoramica del prodotto',
    items: {
      modules: { title: '{count} moduli superiori', desc: 'Attiva i flussi che ti servono' },
      os: { title: 'macOS 14+', desc: 'Un’esperienza desktop nativa' },
      displays: { title: 'Più schermi', desc: 'Funziona con notch e schermi esterni' },
      local: { title: 'Prima locale', desc: 'Lo stato IA non legge mai le conversazioni' },
    },
  },
  showcase: {
    eyebrow: 'UN SOLO PUNTO DI ACCESSO / FLUSSI QUOTIDIANI',
    title: 'I flussi di ogni giorno, <span>in cima allo schermo.</span>',
    lede:
      'Dalle attività IA agli appunti, all’agenda e allo stato del sistema, zisla riunisce i flussi desktop dispersi dietro un unico punto di accesso.',
    ariaLabel: 'Catalogo delle funzioni di zisla',
    summaryMono: '{modules} MODULI / {groups} FLUSSI',
    summaryLede:
      'Dai flussi in alto agli strumenti locali, qui trovi ogni attività che puoi davvero completare.',
    summaryNote:
      '{modules} moduli superiori e {features} funzioni indipendenti, dalle anteprime delle finestre e catture alla gestione IA e alle app consigliate.',
    groupNames: {
      island: 'Flussi superiori',
      ai: 'Flusso IA',
      daily: 'Informazioni quotidiane',
      tools: 'Utility',
    },
    groupCount: '{count} moduli',
    pointsAriaLabel: 'Punti salienti di {name}',
    modules: {
      dashboard: {
        name: 'Home',
        caption:
          'Le schede dinamiche compaiono solo durante una sessione di concentrazione, un’attività IA o un download; quando non succede nulla non occupano spazio. La pagina iniziale raggruppa per applicazione le attività IA in corso.',
        points: ['Appare quando serve', 'Progresso in tempo reale', 'Layout adattivo'],
      },
      shelf: {
        name: 'Scaffale',
        caption:
          'Trascina file, audio, video o link nella parte alta dello schermo, poi cerca, filtra e seleziona più elementi per copiarli, condividerli o inviarli alle Note rapide. Converti immagini in PDF, invia il testo riconosciuto alle Note rapide o apri i video nello studio di registrazione per modificarli. Puoi anche mostrare i file nel Finder.',
        points: ['Ricerca e azioni in gruppo', 'Immagini in PDF e Note rapide', 'Modifica video nello studio'],
      },
      clipboard: {
        name: 'Appunti',
        caption:
          'Sfoglia la cronologia degli appunti nell’isola e filtra per immagine, URL, percorso o tipo di file e guarda quando ogni elemento è stato copiato. Invia un elemento a Note rapide, fissalo tra i preferiti o eliminalo. Puoi eliminare automaticamente la cronologia più vecchia di 7, 15 o 30 giorni mantenendo i preferiti. L’eliminazione automatica è disattivata inizialmente.',
        points: ['Cronologia nell’isola', 'Filtro per tipo', 'Note rapide e preferiti'],
      },
      aiMonitor: {
        name: 'Monitor IA',
        caption:
          'Raccoglie attività e stato di CLI IA, app desktop e IDE. I dati numerici affidabili alimentano le tendenze dei token e la mappa dei contributi; scegli una data per vedere token di input, output e totali per fornitore e modello. Nelle impostazioni puoi consultare lo storico, esportarlo interamente in .xlsx o cancellarlo. Mostra quote reali, orari di ripristino e avvisi di quota bassa, incluse finestre 5h/7d e budget Cursor in dollari quando disponibili. Non legge il testo di prompt o risposte.',
        points: ['Attività di più strumenti IA', 'Storico dei modelli ed export .xlsx', 'Quote e orari di ripristino'],
      },
      keyboardSound: {
        name: 'Suoni della tastiera',
        caption:
          'Riproduce 20 timbri meccanici integrati per i tasti globali, con volume regolabile e variazione naturale del tono, oltre ai suoni di rilascio quando disponibili. Attiva le statistiche locali per vedere riepilogo, tendenze, cronologia, timeline delle app e mappa dei tasti F1-F12. Totali vocali, durata della dettatura, velocità e tempo risparmiato compaiono anche nel pannello della tastiera. Le nuove configurazioni attivano suoni e statistiche, disattivabili separatamente.',
        points: ['20 timbri integrati', 'Suono di rilascio e variazione del tono', 'Statistiche attivabili separatamente'],
      },
      download: {
        name: 'Downloader',
        caption:
          'Incolla un link o lascia che zisla lo riconosca dagli appunti quando è attivo. Scegli video o audio e scarica nella cartella predefinita o in una tua. I link supportati mostrano origine, progresso in tempo reale e stato finale. Scegli la cartella dei download in Impostazioni → Posizione di salvataggio, separata da schermate e registrazioni. I link Bilibili scaricano la parte scelta.',
        points: ['Modalità video / audio', 'Cartella predefinita o personalizzata', 'Origine e progresso in tempo reale'],
      },
      agenda: {
        name: 'Agenda e meteo',
        caption:
          'Mostra il meteo della posizione attuale e di un massimo di sei luoghi scelti. Consulta, aggiungi o elimina eventi e promemoria e segna questi ultimi come completati. Gli eventi con un link di riunione mostrano un conto alla rovescia 10 minuti prima dell’inizio e permettono di partecipare con un clic. Crea una nota di riunione o collega e scollega note contestuali esistenti.',
        points: ['Meteo e calendario', 'Conto alla rovescia di 10 minuti', 'Partecipa e collega le note'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Legge gli account attivati in Mail. Controlla la posta in arrivo, segna un messaggio o tutti i messaggi in arrivo come letti, rispondi, scrivi e sposta messaggi nel Cestino dall’isola. Scegli gli allegati durante la composizione; le autorizzazioni mancanti sono spiegate chiaramente.',
        points: ['Account Mail', 'Rispondi e componi nell’isola', 'Permessi trasparenti'],
      },
      quickNotes: {
        name: 'Note rapide',
        caption:
          'Usa l’app Note di sistema per visualizzare, modificare, creare ed eliminare note con anteprima Markdown dal vivo, e passare direttamente alle prime nove note con Command+1 a 9. Le bozze vengono riscritte automaticamente in Note. Visualizza gli allegati manoscritti e modifica il testo prima o dopo di essi preservando gli originali.',
        points: ['Dati nelle Note', 'Editor Markdown', 'Bozze salvate automaticamente'],
      },
      volumeMixer: {
        name: 'Mixer del volume per app',
        caption: 'Regola volume e silenzia separatamente le app che riproducono audio. Richiede macOS 14.4 o successivo e il permesso di registrazione audio del sistema.',
        points: ['Volume per ogni applicazione', 'Silenzia separatamente', 'macOS 14.4+'],
      },
      toolbox: {
        name: 'Utility',
        caption:
          'Timer di concentrazione, schermo sempre attivo, pulizia dello schermo e della tastiera con blocco anche di F1-F12, teleprompter, specchio e Cestino su una pagina. Metti in pausa, riprendi o reimposta il Pomodoro e segui i progressi nelle viste compatte orizzontale e verticale.',
        points: ['Timer di concentrazione', 'Blocca F1-F12 durante la pulizia', 'Teleprompter e specchio'],
      },
      system: {
        name: 'Stato del sistema',
        caption:
          'Monitora CPU, GPU, memoria, disco, rete, ventole e temperatura NVMe SMART disponibile. Consulta lo storico al minuto per un intervallo di date, esportalo in .xlsx o cancellalo nelle impostazioni. Controlla salute, cicli, temperatura e capacità della batteria, carica dei dispositivi vicini e IPv4/IPv6 pubblici. Scegli modalità energetiche automatiche con alimentatore o batteria, con risparmio energetico opzionale al 20% o meno. Carica subito al 100% quando macOS lo consente. Esamina cache, registri, preferenze residue e spazi IA orfani prima di spostarli nel Cestino; la pulizia opzionale può avvenire ogni 7, 15 o 30 giorni. La pulizia pianificata è disattivata per impostazione predefinita; scegli solo elementi affidabili o tutti quelli gestibili, inclusi quelli da verificare.',
        points: ['Monitoraggio a livello di chip', 'Grafici dello storico ed export .xlsx', 'Controlla prima di spostare nel Cestino'],
      },
    },
  },
  extensions: {
    eyebrow: 'DENTRO E FUORI DALL’ISOLA',
    title: 'Lontano dall’isola, <span>resta uno strumento desktop.</span>',
    lede:
      'Schermate, strumenti per immagini e audio, dettatura, media, download del browser e gestione IA compaiono dove sono facili da raggiungere.',
    ariaLabel: 'Capacità desktop indipendenti',
    summaryMono: 'OLTRE L’ISOLA',
    summaryLede: 'Funzioni frequenti, ognuna nel suo posto naturale.',
    summaryNote:
      'Anteprime delle finestre, catture e azioni rapide sono a portata di mano; le app consigliate aiutano a scoprire altri strumenti per il desktop.',
    features: {
      floatingIsland: {
        title: 'Un’isola fluttuante che si adatta',
        description: 'Usa la posizione della fotocamera o scegli un punto sul bordo dello schermo. La posizione personalizzata viene ricordata tra le modalità. I layout compatti orizzontali e verticali adattano la lunghezza a icone, attività IA, download e contenuti multimediali, con un’opzione per mostrare più informazioni. Riordina i moduli trascinandoli in Impostazioni → Info o ripristina l’ordine predefinito.',
        detail: 'Posizione personalizzata · Icone persistenti · Informazioni adattive',
      },
      dailyBriefing: {
        title: 'La tua giornata in un resoconto',
        description: 'Scegli tra otto modelli e seleziona dati di utilizzo, digitazione, sistema e attività zisla. Controlla l’anteprima ed esporta un PNG manualmente o ogni giorno all’ora scelta. La cronologia Tempo di utilizzo è inclusa se attiva e disponibile; i dati mancanti non sono mostrati come uno zero misurato. Scegli una cartella di esportazione indipendente in Impostazioni → Posizione di salvataggio. Puoi includere anche le quote reali degli account e l’ora del rilevamento.',
        detail: '8 modelli · Contenuti a scelta · Anteprima ed esportazione PNG programmata',
      },
      userCare: {
        title: 'Promemoria durante il lavoro',
        description: 'Regola l’intervallo per pause, acqua, movimento e riposo degli occhi. I messaggi seguono l’ora del giorno. Pause naturali, blocco e stop azzerano il conteggio. Completare una sessione o lavorare sulle note può mostrare un breve riscontro. Attiva o disattiva nelle Impostazioni.',
        detail: 'Intervallo regolabile · Messaggi in base all’ora · Rispetta inattività e stop',
      },
      contextNotes: {
        title: 'Note legate a un luogo',
        description: 'Salva una nota modificabile per una pagina, una finestra o la scrivania e ritrovala al ritorno. Allega una cattura della finestra, gestisci le note sullo scaffale e imposta promemoria ricorrenti da un’ora a tre giorni, oppure disattivali.',
        detail: 'Note contestuali · Catture di finestre · Promemoria ricorrenti',
      },
      recording: {
        title: 'Registra e monta nello studio',
        description: 'Registra schermo, finestra o area con audio del sistema, microfono e fotocamera opzionali. Modifica video, audio, immagini e testo su più tracce con animazioni, zoom e sottotitoli. Regola levigatura della pelle, luminosità, snellimento di viso e corpo, effetti vocali e scie fluide del cursore nel colore scelto. Riproduci il montaggio nello studio. Scegli proporzioni originali, 16:9, 9:16, 1:1 o 4:3; esporta video, GIF, Live Photo o audio. Alcuni formati richiedono FFmpeg. Controlla le proposte IA opzionali prima di applicarle. La cartella delle registrazioni si imposta separatamente in Impostazioni → Posizione di salvataggio.',
        detail: 'Effetti ritratto e voce · Scie colorate del cursore · Riproduzione ed export multitraccia',
      },
      permissions: {
        title: 'Permessi del sistema in un unico posto',
        description: 'Controlla lo stato in Impostazioni → Permessi, avvia richieste supportate o apri la pagina di sistema corretta. Il benvenuto iniziale usa lo stesso elenco e indica i permessi da configurare manualmente.',
        detail: 'Stato dei permessi · Richieste e collegamenti · Condiviso con il benvenuto',
      },
      imageTools: {
        title: 'Strumenti immagine',
        description: 'Nove strumenti locali nelle impostazioni: compressione; conversione PNG, JPEG, WebP, AVIF e JPEG XL; ridimensionamento e ritaglio; confronto del formato più piccolo; rotazione e specchio; filigrane; mosaico e sfocatura; riconoscimento di testo e tabelle; rimozione dello sfondo. Esporta in gruppo o in ZIP, con una cartella dedicata in Impostazioni → Posizione di salvataggio.',
        detail: '9 strumenti locali · Cinque formati · Export in gruppo e ZIP',
      },
      audioTools: {
        title: 'Strumenti audio',
        description: 'Ventisette operazioni locali nelle impostazioni: conversione, compressione, taglio, divisione, unione e mixaggio, estrazione audio dai video, normalizzazione LUFS, dissolvenze, velocità e tono, riduzione del rumore e rimozione dei silenzi, EQ, dinamica, canali e tag. Richiede FFmpeg e ffprobe; scegli un file o una cartella per l’esportazione.',
        detail: '27 operazioni locali · Modifica e mixaggio · FFmpeg e ffprobe',
      },
      pdf: {
        title: 'Strumenti PDF',
        description: 'Disponibile nelle Impostazioni, fuori dal carosello dei moduli dell’isola. Quattordici operazioni sul Mac: unisci, dividi, ruota, ritaglia, converti immagini e file Office, renderizza immagini, estrai testo, aggiungi filigrane e numeri di pagina, cifra, rimuovi password e modifica metadati.',
        detail: '14 strumenti sul dispositivo · Unisci nell’ordine che vuoi · Nulla lascia il Mac',
      },

      windowPreviews: {
        title: 'Guarda la finestra, passa con un clic',
        description:
          'Visualizza le finestre dal Dock o con Command-Tab e fai clic sulla scheda per attivare la finestra. Le nuove configurazioni attivano questa funzione; gestiscila e controlla i permessi nelle Impostazioni.',
        detail: 'Dock e Command-Tab · Cambia finestra con un clic · Configurabile',
      },
      capture: {
        title: 'Schermate, catture lunghe e fissaggio',
        description:
          'Cattura, fissa o unisci schermate a scorrimento con scorciatoie personalizzabili. Evidenzia, estrai aree di immagine, arrotonda gli angoli e conserva le annotazioni all’esportazione. Riconosci e copia il testo, traducilo e copia il risultato oppure esporta tabelle riconosciute in .xlsx. Conserva le catture sullo scaffale. Le impostazioni verificano i conflitti con voce e azioni rapide. La finestra si apre nella cartella delle schermate definita in Impostazioni → Posizione di salvataggio. Le schermate fissate restano al loro posto nelle catture successive. Le acquisizioni lunghe supportano lo scorrimento automatico lento e i dispositivi compatibili possono acquisire in HDR.',
        detail: 'Evidenziazione ed estrazione · Riconosci, traduci e copia · Angoli arrotondati e .xlsx',
      },
      voice: {
        title: 'Input vocale e pulizia',
        description:
          'Attiva con un tasto o tienilo premuto per parlare usando il riconoscimento di sistema, con vocabolari specialistici e parole personalizzate. Se vuoi, usa Ollama, LM Studio o un modello remoto per correggere la trascrizione mantenendone il senso e formattare gli elementi elencati esplicitamente.',
        detail: 'Due modalità di registrazione · Vocabolari e parole chiave · Pulizia opzionale',
      },
      media: {
        title: 'Media e suoni ambientali di sistema',
        description:
          'Controlla ciò che ascolti dalla parte superiore dell’isola oppure scegli un suono ambientale di macOS. Può fermarsi quando lo schermo si blocca, parte il salvaschermo o il monitor va in stop. Scegli una forma d’onda o il bagliore della copertina; l’avanzamento compare anche nei layout compatti e fluttuanti.',
        detail: 'Controllo riproduzione · Testi sincronizzati · Stop automatico',
      },
      browserDownloads: {
        title: 'Progresso dei download del browser',
        description:
          'Rileva i download di Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera e Arc, mostrando origine e progresso in tempo reale in alto.',
        detail: '8 browser · Rilevamento origine · Avviso di completamento',
      },
      copyAssistant: {
        title: 'Azioni rapide e passi successivi',
        description:
          'Quando è attivo, mostra l’anteprima di testo, link, file o immagini copiati in una barra separata e propone apertura, Finder, ricerca, traduzione, calcolo o salvataggio solo dopo la tua conferma. Apri la cartella del file con le azioni rapide dopo un download del browser o un trasferimento AirDrop. Supporta le cartelle predefinite e scelte in Chrome, con un interruttore indipendente dall’avanzamento dei download. Gli IP hanno azioni separate per la ricerca e l’apertura dei link. Le conversioni riconoscono le unità monetarie minori e il catalogo include Emoji 18.0. Testo e immagini salvati usano la cartella indipendente delle azioni rapide in Impostazioni → Posizione di salvataggio. Se un’app non si apre, le Azioni rapide verificano integrità, firma e criteri di sicurezza di macOS. Superati i controlli, possono rimuovere gli attributi di quarantena e aprirla.',
        detail: 'Attivazione opzionale · Riconoscimento locale · Command+N predefinito',
      },
      aiManagement: {
        title: 'Gestione di CLI IA e Skills',
        description:
          'Rileva, installa, aggiorna e rimuove CLI IA dalle Impostazioni, oltre a esaminare e gestire le Skills locali per cambiare meno tra terminali e strumenti.',
        detail: 'Rileva e installa · Aggiorna e rimuovi · Skills locali',
      },
      pet: {
        title: 'Mascotte dell’isola',
        description: 'Scegli dal catalogo ampliato di animali e personaggi oppure importa un’immagine, animazione o video compatibile con un nome personalizzato. Posiziona il compagno ai lati dell’isola ed elimina quelli importati nelle Impostazioni. Animazioni fino a 30 secondi e file fino a 100 MB.',
        detail: 'Catalogo ampliato · Importa immagini e video · Elimina compagni personalizzati',
      },
      lockScreen: {
        title: 'Informazioni della schermata di blocco',
        description:
          'Mostra facoltativamente data, stato e contenuti in riproduzione nella schermata di blocco di macOS. È una sovrapposizione indipendente e non compare nell’elenco o nel carosello dei moduli.',
        detail: 'Sovrapposizione indipendente · Attivazione volontaria · Non ruba il focus',
      },
      recommendedTools: {
        title: 'App consigliate',
        description:
          'Scopri OpenScreen per registrazione e montaggio video, DockDoor per anteprime delle finestre e cambio di app, e Zshell come spazio di lavoro del terminale nativo di macOS. Sono app di terze parti da installare separatamente.',
        detail: 'Scopri strumenti per il desktop · App di terze parti · Installazione separata',
      },
    },
  },
  ai: {
    eyebrow: 'IA SENZA SCATOLA NERA',
    title: 'Guarda lo stato IA <span>senza leggere la conversazione.</span>',
    lede:
      'Segui le attività per applicazione, l’uso dei modelli per data e le quote reali degli account. Stati e dati numerici restano sul Mac; il testo delle conversazioni non viene letto.',
    summaryMono: 'STATO LOCALE / CONFINI CHIARI',
    summaryLede: 'Collega gli strumenti IA che usi, mantenendo i confini di contesto necessari al lavoro.',
    summaryNote: 'Qui spieghiamo solo ambito di rilevamento, dati e connessione; nessuna sessione dal vivo viene simulata.',
    toolsHeading: 'Strumenti IA supportati',
    toolsLede: 'Rileva attività da CLI, app desktop e IDE supportati e aggrega lo stato delle attività.',
    toolsAriaLabel: 'Strumenti IA supportati',
    usageNote: 'Rilevamento delle sessioni, storico dei token e quote usano fonti diverse. Delta utilizza il suo registro numerico locale; Orca deduplica l’uso del CLI associato e lo attribuisce al fornitore originale. WorkBuddy AI può rilevare sessioni e consultare crediti; occupazione del contesto e crediti non sono convertiti in token o costi in dollari. Le quote disponibili dipendono dal fornitore e dal metodo di accesso.',
    boundariesHeading: 'Viene registrato solo lo stato',
    privacyPoints: [
      'Analizza solo tipo di evento, stato, ora, modello e ID sessione degli eventi strutturati',
      'Non legge mai il testo di prompt o risposte',
      'Protocollo e stato sono salvati sul Mac',
    ],
    bridgeHeading: 'Collega le tue attività',
    bridgeLede: 'Usa zislactl per inviare lo stato strutturato delle attività esterne alla barra superiore.',
    zislactlTaskTitle: 'Build e rilascio',
    copyZislactlAriaLabel: 'Copia il comando zislactl',
  },
  flow: {
    eyebrow: 'RITMO DELL’INTERAZIONE',
    title: 'Sali, <span>guarda e lascia andare.</span>',
    lede: 'Non ruba mai il focus e si ritrae quando hai finito di guardare.',
    ariaLabel: 'Ritmo dell’interazione superiore',
    summaryMono: 'BARRA DI STATO / 3 PASSI',
    summaryLede: 'Si espande quando serve e si ritrae quando hai finito.',
    summaryNote: 'Si attiva con la posizione del puntatore, non occupa spazio da vuota e non ruba il focus.',
    steps: {
      trigger: {
        phase: 'Attiva',
        title: 'Porta il puntatore al centro in alto',
        desc: 'Schermi con notch ed esterni usano lo stesso trigger; quando è nascosta non gira alcun ciclo di frame.',
      },
      review: {
        phase: 'Controlla',
        title: 'Dai un’occhiata allo stato attuale',
        desc: 'Media, file, IA, agenda e strumenti di sistema sono nello stesso posto.',
      },
      dismiss: {
        phase: 'Chiudi',
        title: 'Torna a ciò che stavi facendo',
        desc: 'Allontana il puntatore e si ritrae; l’espansione non attiva l’app né prende il focus.',
      },
    },
  },
  download: {
    eyebrow: 'PRONTO QUANDO LO SEI TU',
    title: 'Scarica zisla',
    copy:
      'Per Mac con Apple Silicon. Versioni, altre architetture e checksum sono nella pagina delle release. Dopo l’installazione, Sparkle verifica prima la firma e poi scarica, installa e riavvia manualmente o automaticamente in base alle impostazioni, e gli aggiornamenti conservano i permessi già concessi. Se una release non ti riguarda, saltala e non verrà più segnalata. Leggi le note di versione prima dell’installazione e dopo il riavvio.',
    primaryCta: 'Scarica',
    primaryCtaAriaLabel: 'Scarica zisla',
    releaseCta: 'Vedi release',
    releaseCtaAriaLabel: 'Vedi i dettagli della release su GitHub',
    brewMono: 'HOMEBREW / UN COMANDO',
    brewNote: 'Sparkle aggiorna zisla da sé, quindi brew upgrade sostituisce l\'app solo se la copia installata è davvero più vecchia di quella nel tap: da Homebrew 5.1.6 viene letta la versione contenuta nell\'app. Indicare il cask, come in brew upgrade --cask zisla, si basa invece sui registri di installazione di Homebrew e dopo un aggiornamento Sparkle può riportarti alla versione del tap. Il tap distribuisce solo versioni stabili. È un tap di terze parti e l\'app non è notarizzata, quindi al primo avvio serve «Apri comunque» in Impostazioni di Sistema → Privacy e sicurezza.',
    copyBrewCommandAriaLabel: 'Copia il comando di installazione Homebrew',
    notes: {
      system: { term: 'Sistema', value: 'macOS 14 o successivo · Configurazione supportata: Mac con Apple Silicon' },
      install: { term: 'Installazione', value: 'Monta il DMG e trascinalo in Applicazioni' },
      package: { term: 'Pacchetto', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Altre architetture', value: 'Pagina delle release' },
      mirror: { term: 'Mirror', value: 'Gitee Releases' },
    },
  },
  changelog: {
    releaseNotes: {
      'v0.1.22': [
        'Lo studio aggiunge levigatura della pelle, luminosità, snellimento di viso e corpo, preset vocali regolabili e monitoraggio opzionale del microfono. Gli effetti si regolano prima di registrare e durante il montaggio.',
        'Le scie fluide del cursore consentono di scegliere il colore. La riproduzione nello studio mostra il montaggio con tracce, effetti e audio.',
        'Impostazioni → Posizione di salvataggio separa download, schermate, registrazioni, azioni rapide e resoconti giornalieri. L’aggiornamento mantiene le posizioni precedenti, poi ogni cartella può essere cambiata indipendentemente.',
        'La pulizia opzionale sposta gli elementi nel Cestino ogni 7, 15 o 30 giorni. Scegli elementi attendibili o tutti quelli gestibili, compresi quelli da verificare; inizialmente è disattivata. La pulizia disco aggiunge cartelle di lavoro IA senza sessioni conservate, proteggendo le sessioni mantenute e le cartelle nuove.',
        'La cronologia degli appunti può eliminare automaticamente voci più vecchie di 7, 15 o 30 giorni mantenendo i preferiti. L’eliminazione automatica è inizialmente disattivata.',
        'Note rapide visualizza gli allegati manoscritti e permette di modificare il testo prima o dopo tramite Note, preservando gli allegati originali.',
        'Il monitor IA nasconde le quote residue, mantiene l’utilizzo giornaliero e migliora lo scorrimento dei grafici e le etichette dei mesi. Le impostazioni batteria sono raggruppate in Stato del sistema.',
        'Quiet.md si aggiunge alle app consigliate per note locali, con installazione e gestione nelle impostazioni.',
        'Bilibili rispetta la parte video selezionata e gestisce più formati di link. La cancellazione del calendario riguarda l’occorrenza ricorrente scelta. Le schermate fissate restano nelle catture successive, con etichette più chiare e indicatori di dimensioni più affidabili.',
      ],
      'v0.1.21': [
        'Il monitoraggio del sistema conserva per impostazione predefinita tutta la cronologia al minuto, esistente e nuova, finché non la cancelli. Restano disponibili i grafici per qualsiasi periodo e l’esportazione .xlsx.',
        'Download, registrazioni e schermate condividono una posizione. Le finestre per salvare le schermate si aprono nella cartella dei download attuale; l’impostazione duplicata della posizione delle registrazioni è stata rimossa.',
        'La posizione degli indicatori di stato e la relativa voce di ricerca compaiono solo per le pillole con posizione personalizzata. La riga è nascosta nei layout con notch o nelle pillole sulla fotocamera quando è disponibile solo la barra dei menu.',
        'Il conto alla rovescia delle azioni rapide usa una barra di avanzamento inferiore nei layout con notch. Le pillole mantengono l’avanzamento lungo tutto il perimetro.',
      ],
      'v0.1.20': [
        'Scegli tra otto modelli e seleziona dati di utilizzo, digitazione, sistema e attività zisla. Controlla l’anteprima ed esporta un PNG manualmente o ogni giorno all’ora scelta. La cronologia Tempo di utilizzo è inclusa se attiva e disponibile; i dati mancanti non sono mostrati come uno zero misurato.',
        'Regola l’intervallo per pause, acqua, movimento e riposo degli occhi. I messaggi seguono l’ora del giorno. Pause naturali, blocco e stop azzerano il conteggio. Completare una sessione o lavorare sulle note può mostrare un breve riscontro. Attiva o disattiva nelle Impostazioni. Salva una nota modificabile per una pagina, una finestra o la scrivania e ritrovala al ritorno. Allega una cattura della finestra, gestisci le note sullo scaffale e imposta promemoria ricorrenti da un’ora a tre giorni, oppure disattivali.',
        'Usa la posizione della fotocamera o scegli un punto sul bordo dello schermo. La posizione personalizzata viene ricordata tra le modalità. I layout compatti orizzontali e verticali adattano la lunghezza a icone, attività IA, download e contenuti multimediali, con un’opzione per mostrare più informazioni. Scegli una forma d’onda o il bagliore della copertina; l’avanzamento compare anche nei layout compatti e fluttuanti.',
        'Scegli dal catalogo ampliato di animali e personaggi oppure importa un’immagine, animazione o video compatibile con un nome personalizzato. Posiziona il compagno ai lati dell’isola ed elimina quelli importati nelle Impostazioni. Animazioni fino a 30 secondi e file fino a 100 MB.',
        'Registra schermo, finestra o area con audio del sistema, microfono e fotocamera opzionali. Modifica video, audio, immagini e testo su più tracce, aggiungi animazioni, zoom e sottotitoli e controlla un’anteprima nitida. Scegli proporzioni originali, 16:9, 9:16, 1:1 o 4:3. Esporta video, GIF, Live Photo o audio; alcuni formati richiedono FFmpeg. Le proposte IA opzionali si controllano prima di applicarle.',
        'Cattura, fissa o unisci schermate a scorrimento con scorciatoie personalizzabili. Evidenzia, estrai aree di immagine, arrotonda gli angoli e conserva le annotazioni all’esportazione. Riconosci e copia il testo, traducilo e copia il risultato oppure esporta tabelle riconosciute in .xlsx. Conserva le catture sullo scaffale. Le impostazioni verificano i conflitti con voce e azioni rapide.',
        'Sono aggiunti il rilevamento delle attività Cursor e l’utilizzo numerico con quote di abbonamento disponibili di Cursor e Muse Code; le lunghe esecuzioni degli strumenti di Cursor restano visibili. Gli IP hanno azioni separate per la ricerca e l’apertura dei link. Le conversioni riconoscono le unità monetarie minori e il catalogo include Emoji 18.0.',
        'Regola volume e silenzia separatamente le app che riproducono audio. Richiede macOS 14.4 o successivo e il permesso di registrazione audio del sistema. Disponibile nelle Impostazioni, fuori dal carosello dei moduli dell’isola. Controlla lo stato in Impostazioni → Permessi, avvia richieste supportate o apri la pagina di sistema corretta. Il benvenuto iniziale usa lo stesso elenco e indica i permessi da configurare manualmente. Totali vocali, durata della dettatura, velocità e tempo risparmiato compaiono anche nel pannello della tastiera. Le nuove configurazioni attivano suoni e statistiche, disattivabili separatamente. Seleziona file durante la composizione per allegarli al messaggio. Leggi le note di versione prima dell’installazione e dopo il riavvio.',
      ],
    },
    eyebrow: 'Registro modifiche',
    title: 'Cosa cambia in ogni release di zisla: nuove funzioni, miglioramenti e correzioni.',
    lede: 'Cosa cambia in ogni release di zisla: nuove funzioni, miglioramenti e correzioni.',
    ariaLabel: 'cronologia delle release di zisla',
    releaseCountLabel: 'release',
    latestLabel: 'ultima',
    shippedLabel: 'pubblicata',
    latestBadge: 'Ultima',
    noteLabel: 'release',
    pagerAriaLabel: 'Pagine del changelog',
    pageLabel: 'Pagina {page}',
    prevPageLabel: 'Precedente',
    nextPageLabel: 'Successiva',
  },
  faq: {
    eyebrow: 'RISPOSTE CHIARE',
    title: 'Domande frequenti.',
    lede: 'Permessi, privacy e compatibilità.',
    items: {
      audience: {
        question: 'Per chi è pensato zisla?',
        answer: 'Per chi usa un Mac e vuole IA, media, file e agenda in un unico posto. Funziona anche sugli schermi senza notch.',
      },
      aiPrivacy: {
        question: 'zisla legge le mie conversazioni IA?',
        answer: 'No. Il monitor IA legge solo lo stato delle attività, mai il testo dei prompt o delle risposte.',
      },
      copyAssistant: {
        question: 'Le azioni rapide aprono o caricano ciò che copio?',
        answer: 'No. Riconoscimento e anteprima restano sul Mac e il passo successivo viene eseguito solo dopo la tua conferma.',
      },
      permissions: {
        question: 'Quali permessi di sistema richiede zisla?',
        answer: '<p>Impostazioni → Permessi riunisce stati, richieste e collegamenti alle Impostazioni di Sistema. Alcuni permessi richiedono configurazione manuale. Scegli tu quali richieste avviare; anche il benvenuto iniziale offre questi controlli.</p><p>Registrazione dello schermo e dell’audio di sistema, microfono e fotocamera servono per catture, registrazioni, mixer e specchio secondo la funzione. La dettatura usa anche riconoscimento vocale. Calendari, Promemoria, Posizione, Bluetooth e Automazione servono alle funzioni associate. Aggiungere una città meteo manualmente non richiede la posizione.</p><p>Le nuove configurazioni attivano suoni della tastiera e statistiche, disattivabili separatamente. Gli eventi globali richiedono monitoraggio input. Le statistiche salvano conteggi, codici dei tasti, orari e nomi delle app, mai il testo digitato. Accessibilità serve a inserimento, gesti, pulizia e controllo finestre.</p><p>L’accesso completo al disco può essere necessario per l’indice locale della posta e la cronologia Tempo di utilizzo dei resoconti giornalieri. Il selettore file concede accesso alla cartella scelta. Disattiva funzioni in zisla o revoca permessi in Impostazioni di Sistema → Privacy e sicurezza.</p>',
      },
      localVoice: {
        question: 'Come uso un modello locale per correggere la trascrizione vocale?',
        answer: `
      <p>Sono supportati Ollama, LM Studio e altri servizi locali compatibili con OpenAI.</p>
      <ol>
        <li>Scarica o carica il modello desiderato nell’app per modelli locali, quindi avvia il servizio.</li>
        <li>Apri Impostazioni → Voce → Modelli Locali, aggiungi e attiva una configurazione, scegli Ollama o LM Studio e inserisci l’URL del servizio. Per altri servizi compatibili con OpenAI, scegli sempre LM Studio. Lascia API Key vuoto se il servizio non richiede autenticazione.</li>
        <li>Seleziona un modello rilevato automaticamente e scegli la relativa configurazione in Modello Organizzazione Vocale → Usa Modello.</li>
      </ol>
      <p>zisla suggerisce un modello Gemma 4 QAT in base al chip e alla memoria RAM totale. Non scarica né carica automaticamente il modello consigliato.</p>
    `.trim(),
      },
      network: {
        question: 'zisla va online?',
        answer: 'Meteo, aggiornamenti firmati, download avviati da te e pulizia vocale remota opzionale usano la rete quando serve. Il rilevamento dei link è locale. Il modello locale corregge il testo dopo la trascrizione; il riconoscimento vocale Apple può ancora usare la rete, a seconda della lingua e del supporto del sistema.',
      },
      multiDisplay: {
        question: 'zisla supporta più schermi?',
        answer: 'Sì: più schermi, Spaces e app normali a tutto schermo; l’espansione non ruba mai il focus.',
      },
      intel: {
        question: 'Posso usarlo su un Mac Intel?',
        answer: 'Può esistere una build per Intel, ma la compatibilità non è garantita. La configurazione supportata oggi è Apple Silicon.',
      },
      storage: {
        question: 'Dove salva i dati zisla?',
        answer: 'I dati locali sono in ~/Library/Application Support/zisla/. Le statistiche di digitazione sono in ~/Library/Application Support/zisla/typing-stats.sqlite3. Note rapide usa l’app Note. Impostazioni → Posizione di salvataggio offre cartelle indipendenti per download, schermate, registrazioni, azioni rapide e resoconti giornalieri. L’aggiornamento conserva la precedente cartella condivisa, poi ciascuna può essere cambiata separatamente.',
      },
    },
  },
  developers: {
    eyebrow: 'OPEN SOURCE PER IMPOSTAZIONE PREDEFINITA',
    title: 'Risorse per sviluppatori.',
    lede: 'Licenza PolyForm Noncommercial 1.0.0: solo uso non commerciale, così com’è o compilato dal codice sorgente.',
    docs: {
      macos: { title: 'Guida allo sviluppo macOS', description: 'Funzioni, build, test e limiti del sistema' },
      architecture: { title: 'Architettura e prestazioni', description: 'Trigger superiore, finestre e progettazione delle prestazioni' },
      cli: { title: 'Integrazione CLI', description: 'Comandi e campi di zislactl' },
      releasing: { title: 'Firma e rilascio', description: 'Firma, notarizzazione e processo di rilascio' },
      contributing: { title: 'Guida ai contributi', description: 'Ambiente, branch, commit e requisiti delle pull request' },
    },
    quickStartMono: 'AVVIO RAPIDO / CODICE',
    quickStartHeading: 'Eseguilo dal codice o collega le tue attività.',
    copyRunCommandAriaLabel: 'Copia il comando per eseguire dal codice sorgente',
    githubRepoLabel: 'Repository GitHub',
    giteeRepoLabel: 'Repository Gitee',
    checksumLabel: 'SHA-256',
    performancePoints: [
      'Supporta più schermi, Spaces e app normali a tutto schermo; l’espansione non attiva l’app né ruba il focus',
      'Quando è nascosto non crea finestre trasparenti persistenti né esegue loop di frame; usa eventi globali e geometria',
      'Usa un solo livello di materiale di sistema e passa a uno sfondo opaco con Riduci trasparenza',
      'Liquid Glass su macOS 26+, con fallback automatico ai materiali nativi su macOS 14 e 15',
      'Il notch fisico è dedotto dall’area sicura; gli schermi esterni senza notch ricevono una barra simulata in un overlay dedicato',
    ],
  },
  film: {
    title: "Video di presentazione",
    videoAriaLabel: "Video di presentazione di zisla",
    openVideoLabel: "Apri il video",
    playbackError: "Impossibile riprodurre il video.",
    musicLabel: "Musica",
    excerptLabel: "Estratto",
  },
  footer: {
    brandHomeAriaLabel: 'Torna alla home di zisla',
    previewChannelLabel: 'Canale Preview',
    tagline: 'Open source, nativo e sotto il tuo controllo.',
  },
  common: {
    copyCommandTitle: 'Copia comando',
    copiedAriaLabel: 'Copiato',
  },
  toast: {
    runCommandCopied: 'Comando di esecuzione copiato',
    zislactlCopied: 'Comando zislactl copiato',
    brewCommandCopied: 'Comando di installazione Homebrew copiato',
  },
});
