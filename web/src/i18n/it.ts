import { createCatalog } from './createCatalog';

export const it = createCatalog({
  meta: {
    documentTitle: 'zisla · Spazio di lavoro dinamico',
    description:
      'zisla è uno spazio di lavoro dinamico nativo per macOS. Riunisce attività IA, media, file e agenda, oltre a suoni della tastiera, statistiche di digitazione, annotazioni delle schermate e assistente di copia.',
    ogTitle: 'zisla · Porta ciò che accade dove puoi vederlo',
    ogDescription:
      'Dalle attività IA ai media, dai suoni della tastiera alle statistiche di digitazione, alle annotazioni e agli strumenti desktop: uno spazio macOS nativo che appare quando serve.',
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
      faq: 'Domande frequenti',
      developers: 'Sviluppatori',
    },
    downloadCta: 'Scarica',
    downloadCtaAriaLabel: 'Vai alla sezione download',
    languageLabel: 'Lingua dell’interfaccia',
  },
  hero: {
    eyebrow: 'SPAZIO DI LAVORO NATIVO PER MACOS',
    title: 'zisla<br><em>Ciò che accade,<br>proprio dove<br class="hero-mobile-break"> puoi vederlo.</em>',
    lede:
      'Riunisci attività IA, media, file e agenda nella parte superiore dello schermo. Dopo una copia, una barra assistente separata mostra un’anteprima e suggerisce il passo successivo. Appare quando serve e si fa da parte quando hai finito.',
    downloadCta: 'Scarica',
    downloadCtaAriaLabel: 'Scarica',
    sourceCta: 'Vedi il codice',
    sourceCtaAriaLabel: 'Vedi il codice sorgente di zisla su GitHub',
    hints: [
      'Porta il puntatore in alto per espandere, senza clic',
      'Dopo una copia, premi Command+N per il passo intelligente successivo',
      'Si richiude da sola senza interrompere il lavoro',
    ],
    identityCaption: 'Parte superiore dello schermo',
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
      '{modules} moduli superiori e {features} capacità indipendenti per schermate, voce, media, download, assistente di copia, gestione IA, mascotte e blocco schermo.',
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
          'Le schede dinamiche compaiono solo durante una sessione di concentrazione, un’attività IA o un download; quando non succede nulla non occupano spazio.',
        points: ['Appare quando serve', 'Progresso in tempo reale', 'Layout adattivo'],
      },
      shelf: {
        name: 'Scaffale',
        caption:
          'Trascina file, audio, video o link sulla fascia superiore per conservarli nello scaffale, mostrarli nel Finder o aprire il menu Condividi di macOS.',
        points: ['Trascina in alto per riporre', 'Mostra nel Finder', 'Menu Condividi di sistema'],
      },
      clipboard: {
        name: 'Appunti',
        caption:
          'Sfoglia la cronologia degli appunti nell’isola e filtra per immagine, URL, percorso o tipo di file. Invia un elemento a Note rapide, fissalo tra i preferiti o eliminalo.',
        points: ['Cronologia nell’isola', 'Filtro per tipo', 'Note rapide e preferiti'],
      },
      aiMonitor: {
        name: 'Monitor IA',
        caption:
          'Rileva automaticamente l’attività di CLI, app desktop e IDE supportati, inclusi i thread di Zed Agent, mostrando attività, stato, tendenze dei token e una mappa dei contributi. Analizza solo eventi strutturati e non legge le conversazioni.',
        points: ['Attività aggregate tra gli strumenti', 'Tendenze del consumo di token', 'Non legge prompt o risposte'],
      },
      keyboardSound: {
        name: 'Suoni della tastiera',
        caption:
          'Riproduce 20 timbri meccanici integrati per i tasti globali, con volume regolabile e variazione naturale del tono, oltre ai suoni di rilascio quando disponibili. Attiva le statistiche locali per vedere riepilogo, tendenze, cronologia, timeline delle app e mappa dei tasti F1-F12.',
        points: ['20 timbri integrati', 'Suono di rilascio e variazione del tono', 'Statistiche opzionali'],
      },
      download: {
        name: 'Downloader',
        caption:
          'Incolla un link o lascia che zisla lo riconosca dagli appunti quando è attivo. Scegli video o audio e scarica nella cartella predefinita o in una tua. I link supportati mostrano origine, progresso in tempo reale e stato finale.',
        points: ['Modalità video / audio', 'Cartella predefinita o personalizzata', 'Origine e progresso in tempo reale'],
      },
      agenda: {
        name: 'Agenda e meteo',
        caption:
          'Mostra il meteo della posizione attuale e di fino a sei luoghi scelti. Visualizza, aggiungi ed elimina eventi e promemoria, quindi segna i promemoria come completati.',
        points: ['Schede meteo per più luoghi', 'Calendario e attività', 'Completa un promemoria con un tocco'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Legge gli account attivati in Mail, mostra la posta in arrivo e consente di segnare, rispondere, comporre e spostare i messaggi nel Cestino dall’isola, con indicazioni chiare quando manca un permesso.',
        points: ['Account Mail', 'Rispondi e componi nell’isola', 'Permessi trasparenti'],
      },
      quickNotes: {
        name: 'Note rapide',
        caption:
          'Usa l’app Note di sistema per visualizzare, modificare, creare ed eliminare note con anteprima Markdown dal vivo. Le bozze vengono riscritte automaticamente in Note.',
        points: ['Dati nelle Note', 'Editor Markdown', 'Bozze salvate automaticamente'],
      },
      pdf: {
        name: 'Strumenti PDF',
        caption:
          'Quattordici operazioni sul Mac: unisci, dividi, ruota, ritaglia, converti immagini e file Office, renderizza immagini, estrai testo, aggiungi filigrane e numeri di pagina, cifra, rimuovi password e modifica metadati.',
        points: ['14 strumenti sul dispositivo', 'Unisci nell’ordine che vuoi', 'Nulla lascia il Mac'],
      },
      toolbox: {
        name: 'Utility',
        caption:
          'Timer di concentrazione, schermo sempre attivo, pulizia dello schermo e della tastiera (blocca anche F1-F12), sveglie, teleprompter, specchio e Cestino in un’unica pagina.',
        points: ['Timer di concentrazione', 'Blocca F1-F12 durante la pulizia', 'Teleprompter e specchio'],
      },
      system: {
        name: 'Stato del sistema',
        caption:
          'Controlla CPU, GPU, memoria, disco, rete e ventole; leggi la temperatura SMART NVMe quando l’hardware la espone e cancella cache e log sicuri da rimuovere.',
        points: ['Monitoraggio a livello di chip', 'Temperatura NVMe quando supportata', 'Pulisci la cache con un tocco'],
      },
      battery: {
        name: 'Batteria',
        caption:
          'Visualizza carica, salute, cicli, temperatura e capacità del Mac, oltre al livello della batteria dei dispositivi vicini esposto dal sistema.',
        points: ['Indicatori di salute del Mac', 'Tempo rimanente', 'Batteria dei dispositivi vicini'],
      },
    },
  },
  extensions: {
    eyebrow: 'DENTRO E FUORI DALL’ISOLA',
    title: 'Lontano dall’isola, <span>resta uno strumento desktop.</span>',
    lede:
      'Schermate, voce, media, download del browser e gestione IA compaiono dove sono più facili da raggiungere.',
    ariaLabel: 'Capacità desktop indipendenti',
    summaryMono: 'OLTRE L’ISOLA',
    summaryLede: 'Funzioni frequenti, ognuna nel suo posto naturale.',
    summaryNote:
      'Schermate, registrazione, media, download del browser, assistente di copia, gestione IA, mascotte e blocco schermo sono presentati separatamente.',
    features: {
      capture: {
        title: 'Schermate, catture lunghe e fissaggio',
        description:
          'Cattura o fissa una parte dello schermo con una scorciatoia globale, annota, unisci una cattura a scorrimento e riconosci o esporta tabelle. Le annotazioni ancora in modifica restano nell’esportazione.',
        detail: 'Scorciatoia globale · Annotazione e annullamento · Modifiche conservate',
      },
      voice: {
        title: 'Input vocale e pulizia',
        description:
          'Attiva con un tasto o tieni premuto per parlare usando il riconoscimento vocale di sistema. Aggiungi vocabolari, parole personalizzate, formattazione strutturata o pulizia con un modello locale o remoto.',
        detail: 'Due modalità di registrazione · Vocabolari e parole chiave · Pulizia opzionale',
      },
      media: {
        title: 'Media e suoni ambientali di sistema',
        description:
          'Controlla ciò che ascolti dalla parte superiore dell’isola oppure scegli un suono ambientale di macOS. Può fermarsi quando lo schermo si blocca, parte il salvaschermo o il monitor va in stop.',
        detail: 'Controllo riproduzione · Testi sincronizzati · Stop automatico',
      },
      browserDownloads: {
        title: 'Progresso dei download del browser',
        description:
          'Rileva i download di Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera e Arc, mostrando origine e progresso in tempo reale in alto.',
        detail: '8 browser · Rilevamento origine · Avviso di completamento',
      },
      copyAssistant: {
        title: 'Assistente di copia e passi successivi',
        description:
          'Quando è attivo, mostra l’anteprima di testo, link, file o immagini copiati in una barra separata e propone apertura, Finder, ricerca, traduzione, calcolo o salvataggio solo dopo la tua conferma.',
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
        description: 'Scegli una mascotte integrata e posizionala a sinistra o a destra dell’isola. Disattivala quando vuoi.',
        detail: 'Personaggi integrati · Sinistra o destra · Attiva quando serve',
      },
      lockScreen: {
        title: 'Informazioni della schermata di blocco',
        description:
          'Mostra facoltativamente data, stato e contenuti in riproduzione nella schermata di blocco di macOS. È una sovrapposizione indipendente e non compare nell’elenco o nel carosello dei moduli.',
        detail: 'Sovrapposizione indipendente · Attivazione volontaria · Non ruba il focus',
      },
    },
  },
  ai: {
    eyebrow: 'IA SENZA SCATOLA NERA',
    title: 'Guarda lo stato IA <span>senza leggere la conversazione.</span>',
    lede:
      'Attività, stato e tendenze dei token restano sul Mac. Questa pagina descrive la funzione senza simulare un’attività in esecuzione.',
    summaryMono: 'STATO LOCALE / CONFINI CHIARI',
    summaryLede: 'Collega gli strumenti IA che usi, mantenendo i confini di contesto necessari al lavoro.',
    summaryNote: 'Qui spieghiamo solo ambito di rilevamento, dati e connessione; nessuna sessione dal vivo viene simulata.',
    toolsHeading: 'Strumenti IA supportati',
    toolsLede: 'Rileva attività da CLI, app desktop e IDE supportati e aggrega lo stato delle attività.',
    toolsAriaLabel: 'Strumenti IA supportati',
    doubaoName: 'Doubao',
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
      'Per Mac con Apple Silicon. Versioni, altre architetture e checksum sono nella pagina delle release. Dopo l’installazione, Sparkle verifica prima la firma e poi scarica, installa e riavvia manualmente o automaticamente in base alle impostazioni.',
    primaryCta: 'Scarica',
    primaryCtaAriaLabel: 'Scarica zisla',
    releaseCta: 'Vedi release',
    releaseCtaAriaLabel: 'Vedi i dettagli della release su GitHub',
    brewMono: 'HOMEBREW / UN COMANDO',
    brewNote: 'Sparkle aggiorna zisla da sé, quindi un semplice brew upgrade non tocca l\'app: esegui brew upgrade --cask zisla se vuoi che ci pensi Homebrew. Il tap distribuisce solo versioni stabili. È un tap di terze parti e l\'app non è notarizzata, quindi al primo avvio serve «Apri comunque» in Impostazioni di Sistema → Privacy e sicurezza.',
    copyBrewCommandAriaLabel: 'Copia il comando di installazione Homebrew',
    notes: {
      system: { term: 'Sistema', value: 'macOS 14 o successivo · Configurazione supportata: Mac con Apple Silicon' },
      install: { term: 'Installazione', value: 'brew install --cask, oppure monta il DMG e trascinalo in Applicazioni' },
      package: { term: 'Pacchetto', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Altre architetture', value: 'Pagina delle release' },
      mirror: { term: 'Mirror', value: 'Gitee Releases' },
    },
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
        question: 'L’assistente di copia apre o carica ciò che copio?',
        answer: 'No. Riconoscimento e anteprima restano sul Mac e il passo successivo viene eseguito solo dopo la tua conferma.',
      },
      permissions: {
        question: 'Quali permessi di sistema richiede zisla?',
        answer: `
      <p>zisla non richiede tutti i permessi al primo avvio. macOS mostra ogni richiesta solo quando attivi e usi davvero la funzione corrispondente:</p>
      <ul>
        <li><strong>Calendari e Promemoria:</strong> richiesti separatamente quando apri il modulo agenda, per leggere, creare e gestire eventi del calendario e promemoria con data.</li>
        <li><strong>Servizi di localizzazione:</strong> richiesti quando scegli il meteo della posizione attuale. zisla rileva la posizione una sola volta e non ti segue continuamente. Aggiungere manualmente una città non richiede il permesso di localizzazione.</li>
        <li><strong>Microfono e riconoscimento vocale:</strong> richiesti quando avvii l'input vocale. L'audio viene acquisito solo durante la registrazione attiva e viene trascritta solo quella registrazione.</li>
        <li><strong>Accessibilità:</strong> necessaria per inserire automaticamente una trascrizione nell'app in uso, copiare rapidamente con un gesto del mouse, pulire la tastiera e controllare alcuni player supportati. Serve a individuare i campi di input che non sono password o a inviare i tasti di sistema necessari.</li>
        <li><strong>Monitoraggio input:</strong> usato per i suoni della tastiera, le statistiche locali opzionali di digitazione e i trigger globali come un singolo tasto modificatore o un pulsante laterale del mouse. Ascolta solo gli eventi globali necessari a queste funzioni; le normali scorciatoie globali non lo richiedono.</li>
        <li><strong>Registrazione schermo e registrazione audio di sistema:</strong> necessarie per gli screenshot, la loro modifica e la forma d'onda dell'audio riprodotto dal sistema. Gli screenshot leggono l'immagine dello schermo; la forma d'onda analizza solo i livelli audio correnti e non salva né invia contenuti audio.</li>
        <li><strong>Fotocamera:</strong> usata solo mentre la finestra specchio è aperta.</li>
        <li><strong>Bluetooth:</strong> usato solo mentre il modulo batteria è aperto, per leggere il livello pubblicato dai dispositivi connessi o abbinati.</li>
        <li><strong>Automazione:</strong> la prima volta che usi Note rapide, Mail, la pulizia della scrivania o il controllo diretto di un player supportato, macOS chiede separatamente se zisla può controllare Note, Mail, Finder o l'app interessata. Note rapide legge e scrive in Note; Mail può leggere, comporre, rispondere, contrassegnare ed eliminare i messaggi.</li>
        <li><strong>Accesso completo al disco:</strong> necessario solo quando Mail non è in esecuzione e zisla deve comunque leggere l'indice locale della posta per mostrare account, mittenti, oggetti, anteprime, orari e stato di lettura.</li>
        <li><strong>Notifiche:</strong> richieste quando attivi il timer Pomodoro o le sveglie, esclusivamente per mostrare una notifica locale alla fine del timer o quando scatta una sveglia.</li>
      </ul>
      <p><strong>Le cartelle non equivalgono all'accesso completo al disco:</strong> per le cartelle di deposito, importazione/esportazione o download scelte nel selettore file di sistema, zisla ottiene accesso solo a quella cartella, mai la lettura dell'intero disco.</p>
      <p><strong>Suoni della tastiera e statistiche di digitazione:</strong> entrambe le funzioni sono disattivate per impostazione predefinita e gli eventi globali della tastiera vengono osservati solo quando una delle due è attiva. Con i suoni della tastiera, gli eventi dei tasti servono esclusivamente a riprodurre un suono; con le statistiche vengono salvati solo dati aggregati — conteggio dei caratteri, codici fisici dei tasti, orari e app in primo piano — mai ciò che hai digitato. Puoi disattivare ciascuna opzione separatamente nelle impostazioni; da quel momento non viene registrato altro. I dati già salvati restano in un file di database locale che puoi eliminare.</p>
      <p>Puoi disattivare una funzione nelle impostazioni dell'app o revocare un permesso in qualsiasi momento in Impostazioni di Sistema → Privacy e sicurezza. La revoca di un permesso disattiva solo la funzione collegata e non tocca gli altri moduli. I nomi delle voci possono variare leggermente a seconda della versione di macOS.</p>
    `.trim(),
      },
      network: {
        question: 'zisla va online?',
        answer: 'Meteo, aggiornamenti firmati, download avviati da te e pulizia vocale remota opzionale usano la rete quando serve. Il rilevamento dei link è locale.',
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
        answer: 'I dati locali sono in ~/Library/Application Support/zisla/. Le statistiche di digitazione sono in ~/Library/Application Support/SimuBoard/typing-stats.sqlite3. Note rapide usa l’app Note.',
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
