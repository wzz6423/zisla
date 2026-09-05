import { createCatalog } from './createCatalog';

export const nl = createCatalog({
  meta: {
    documentTitle: 'zisla · Dynamische werkruimte',
    description:
      'zisla is een native dynamische werkruimte voor macOS. Houd AI-taken, media, bestanden en je agenda bij elkaar, met toetsenbordgeluiden, typestatistieken, schermaantekeningen en een kopieerassistent.',
    ogTitle: 'zisla · Zet wat er gebeurt waar je het kunt zien',
    ogDescription:
      'Van AI-taken en media tot toetsenbordgeluiden, typestatistieken, schermaantekeningen en desktoptools: een native macOS-werkruimte die verschijnt wanneer je haar nodig hebt.',
  },
  tagline: 'Native dynamische werkruimte voor macOS',
  header: {
    navAriaLabel: 'Hoofdnavigatie',
    brandHomeAriaLabel: 'zisla-home',
    menuOpenLabel: 'Navigatiemenu openen',
    menuCloseLabel: 'Navigatie sluiten',
    menuButtonTitle: 'Navigatie openen',
    navItems: {
      showcase: 'Functies',
      ai: 'AI-workflow',
      download: 'Download',
      faq: 'Veelgestelde vragen',
      developers: 'Ontwikkelaars',
    },
    downloadCta: 'Download',
    downloadCtaAriaLabel: 'Naar de downloadsectie',
    languageLabel: 'Interfacetaal',
  },
  hero: {
    eyebrow: 'NATIVE MACOS-WERKRUIMTE',
    title: 'zisla<br><em>Wat er gebeurt,<br>precies waar<br class="hero-mobile-break"> je het ziet.</em>',
    lede:
      'Verzamel AI-taken, media, bestanden en je agenda bovenaan het scherm. Na het kopiëren toont een aparte assistentbalk een voorbeeld en stelt de volgende stap voor. Ze verschijnt wanneer nodig en verdwijnt daarna weer.',
    downloadCta: 'Download',
    downloadCtaAriaLabel: 'Download',
    sourceCta: 'Broncode bekijken',
    sourceCtaAriaLabel: 'De broncode van zisla op GitHub bekijken',
    hints: [
      'Beweeg naar de bovenkant om uit te klappen, zonder klik',
      'Druk na het kopiëren op Command+N voor de slimme volgende stap',
      'Klapt vanzelf in zonder je werk te onderbreken',
    ],
    identityCaption: 'Bovenkant van het scherm',
  },
  proof: {
    ariaLabel: 'Productoverzicht',
    items: {
      modules: { title: '{count} modules bovenaan', desc: 'Schakel de workflows in die je nodig hebt' },
      os: { title: 'macOS 14+', desc: 'Een native desktopervaring' },
      displays: { title: 'Meerdere schermen', desc: 'Werkt op schermen met notch en externe schermen' },
      local: { title: 'Lokaal eerst', desc: 'AI-status leest nooit je gesprekken' },
    },
  },
  showcase: {
    eyebrow: 'ÉÉN INGANG / DAGELIJKSE WORKFLOWS',
    title: 'Dagelijkse workflows, <span>bovenaan het scherm.</span>',
    lede:
      'Van AI-taken tot klembord, agenda en systeemstatus: zisla verzamelt verspreide desktopworkflows achter één ingang.',
    ariaLabel: 'Functiecatalogus van zisla',
    summaryMono: '{modules} MODULES / {groups} WORKFLOWS',
    summaryLede:
      'Van workflows bovenaan tot lokale tools: elke taak die je echt kunt uitvoeren staat hier beschreven.',
    summaryNote:
      '{modules} modules bovenaan en {features} zelfstandige functies voor schermafbeeldingen, spraak, media, downloads, kopieerassistent, AI-beheer, huisdier en vergrendelscherm.',
    groupNames: {
      island: 'Workflows bovenaan',
      ai: 'AI-workflow',
      daily: 'Dagelijkse informatie',
      tools: 'Hulpprogramma’s',
    },
    groupCount: '{count} modules',
    pointsAriaLabel: 'Hoogtepunten van {name}',
    modules: {
      dashboard: {
        name: 'Home',
        caption:
          'Livekaarten verschijnen alleen tijdens een focussessie, AI-taak of download; als er niets gebeurt, nemen ze geen ruimte in.',
        points: ['Verschijnt op aanvraag', 'Live voortgang', 'Lay-out past zich aan'],
      },
      shelf: {
        name: 'Plank',
        caption:
          'Sleep bestanden, audio, video of links naar de strook bovenaan om ze op de plank te zetten, in Finder te tonen of het macOS-deelmenu te openen.',
        points: ['Sleep naar boven om te bewaren', 'Tonen in Finder', 'Systeemdeelmenu'],
      },
      clipboard: {
        name: 'Klembord',
        caption:
          'Bekijk de klembordgeschiedenis in het eiland en filter op afbeelding, URL, pad of bestandstype. Stuur een item naar Snelle notities, maak het favoriet of verwijder het.',
        points: ['Geschiedenis in het eiland', 'Filteren op type', 'Snelle notities en favorieten'],
      },
      aiMonitor: {
        name: 'AI-monitor',
        caption:
          'Detecteert activiteit van ondersteunde AI-CLI’s, desktopapps en IDE’s, waaronder Zed Agent-threads, en toont taken, status, tokentrends en een bijdrageheatmap. Alleen gestructureerde gebeurtenissen worden gelezen; gesprekken nooit.',
        points: ['Taken uit tools samengevoegd', 'Trends in tokenverbruik', 'Leest geen prompts of antwoorden'],
      },
      keyboardSound: {
        name: 'Toetsenbordgeluiden',
        caption:
          'Speelt 20 ingebouwde mechanische toetsenbordgeluiden af voor globale toetsaanslagen, met instelbaar volume en natuurlijke toonvariatie. Schakel lokale typestatistieken in voor overzicht, trends, geschiedenis, app-tijdlijn en een heatmap met F1-F12.',
        points: ['20 ingebouwde geluiden', 'Loslaatgeluid en toonvariatie', 'Typestatistieken optioneel'],
      },
      download: {
        name: 'Downloader',
        caption:
          'Plak een link of laat zisla links uit het klembord herkennen zodra de functie is ingeschakeld. Kies video of audio en download naar de standaardmap of een map naar keuze. Ondersteunde links tonen bron, live voortgang en voltooiingsstatus.',
        points: ['Video- / audiomodi', 'Standaard- of eigen map', 'Bron en live voortgang'],
      },
      agenda: {
        name: 'Agenda en weer',
        caption:
          'Toont het weer op je huidige locatie en op maximaal zes gekozen plaatsen. Bekijk, voeg toe en verwijder agenda-items en herinneringen, en markeer herinneringen als klaar.',
        points: ['Weerkaarten voor meerdere plaatsen', 'Agenda en taken', 'Herinnering met één tik voltooien'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Leest ingeschakelde Mail-accounts, toont de inbox en laat je berichten markeren, beantwoorden, opstellen en naar de prullenmand verplaatsen in het eiland, met duidelijke uitleg als een machtiging ontbreekt.',
        points: ['Mail-accounts', 'Antwoorden en opstellen in het eiland', 'Heldere machtigingsuitleg'],
      },
      quickNotes: {
        name: 'Snelle notities',
        caption:
          'Gebruikt de systeemapp Notities om notities te bekijken, bewerken, maken en verwijderen met live Markdown-voorbeeld. Concepten worden automatisch teruggeschreven.',
        points: ['Gegevens in Notities', 'Markdown-editor', 'Concepten automatisch opgeslagen'],
      },
      pdf: {
        name: 'PDF-tools',
        caption:
          'Veertien bewerkingen op je Mac: samenvoegen, splitsen, draaien, bijsnijden, afbeeldingen en Office-bestanden converteren, renderen, tekst exporteren, watermerken en paginanummers toevoegen, versleutelen, wachtwoord verwijderen en metadata bewerken.',
        points: ['14 lokale tools', 'Samenvoegen in eigen volgorde', 'Niets verlaat je Mac'],
      },
      toolbox: {
        name: 'Hulpprogramma’s',
        caption:
          'Focusafteller, scherm wakker houden, scherm- en toetsenbordreiniging (blokkeert ook F1-F12), alarmen, teleprompter, spiegel en prullenmand op één pagina.',
        points: ['Focusafteller', 'Blokkeert F1-F12 tijdens reinigen', 'Teleprompter en spiegel'],
      },
      system: {
        name: 'Systeemstatus',
        caption:
          'Controleer CPU, GPU, geheugen, schijf, netwerk en ventilatoren; lees de NVMe-SMART-temperatuur wanneer de hardware die aanbiedt en ruim veilige caches en logboeken op.',
        points: ['Monitoring op chipniveau', 'NVMe-temperatuur indien ondersteund', 'Caches met één tik opruimen'],
      },
      battery: {
        name: 'Batterij',
        caption:
          'Bekijk lading, gezondheid, cycli, temperatuur en capaciteit van deze Mac, plus batterijniveaus van nabije apparaten die het systeem deelt.',
        points: ['Gezondheidsgegevens van deze Mac', 'Resterende tijd', 'Batterij van nabije apparaten'],
      },
    },
  },
  extensions: {
    eyebrow: 'BINNEN EN BUITEN HET EILAND',
    title: 'Buiten het eiland, <span>nog steeds een desktoptool.</span>',
    lede:
      'Schermafbeeldingen, spraak, media, browserdownloads en AI-beheer verschijnen waar ze het makkelijkst bereikbaar zijn.',
    ariaLabel: 'Zelfstandige desktopfuncties',
    summaryMono: 'VOORBIJ HET EILAND',
    summaryLede: 'Veelgebruikte functies, elk op een natuurlijke plek.',
    summaryNote:
      'Schermafbeeldingen, opname, media, browserdownloads, kopieerassistent, AI-beheer, huisdier en vergrendelscherm worden afzonderlijk getoond.',
    features: {
      capture: {
        title: 'Schermafbeeldingen, scrollcaptures en vastzetten',
        description:
          'Maak of pin een deel van het scherm met een globale sneltoets, annoteer, voeg een scrollcapture samen en herken of exporteer tabellen. Bewerkte tekstannotaties blijven behouden bij export.',
        detail: 'Globale sneltoets · Annoteren en ongedaan maken · Bewerkingen blijven behouden',
      },
      voice: {
        title: 'Spraakinvoer en opschonen',
        description:
          'Schakel met een toets of houd vast om te praten met de systeemherkenner. Voeg vakwoorden, eigen trefwoorden, gestructureerde opmaak of opschoning door een lokaal of extern model toe.',
        detail: 'Twee opnamemodi · Woordenlijsten en trefwoorden · Optionele modelbewerking',
      },
      media: {
        title: 'Media en omgevingsgeluiden',
        description:
          'Bedien wat er speelt bovenaan het eiland of kies een omgevingsgeluid van macOS. Het kan stoppen wanneer het scherm vergrendelt, de schermbeveiliging start of het scherm slaapt.',
        detail: 'Afspeelbediening · Gesynchroniseerde songteksten · Automatisch stoppen',
      },
      browserDownloads: {
        title: 'Voortgang van browserdownloads',
        description:
          'Herkent downloads in Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera en Arc en toont bron en live voortgang bovenaan.',
        detail: '8 browsers · Bronherkenning · Melding bij voltooiing',
      },
      copyAssistant: {
        title: 'Kopieerassistent en volgende stappen',
        description:
          'Na inschakelen worden gekopieerde tekst, links, bestanden of afbeeldingen in een aparte balk getoond, met opties om te openen, in Finder te tonen, te zoeken, vertalen, berekenen of opslaan — alleen na jouw bevestiging.',
        detail: 'Optionele schakelaar · Lokale herkenning · Command+N standaard',
      },
      aiManagement: {
        title: 'AI-CLI- en Skills-beheer',
        description:
          'Detecteer, installeer, werk AI-CLI’s bij en verwijder ze via Instellingen, en bekijk en beheer lokale Skills zodat je minder tussen terminals hoeft te wisselen.',
        detail: 'Detecteren en installeren · Bijwerken en verwijderen · Lokale Skills',
      },
      pet: {
        title: 'Huisdier in het eiland',
        description: 'Kies een ingebouwd huisdier en plaats het links of rechts van het eiland. Zet het uit wanneer je wilt.',
        detail: 'Ingebouwde figuren · Links of rechts · Alleen wanneer gewenst',
      },
      lockScreen: {
        title: 'Informatie op het vergrendelscherm',
        description:
          'Toon optioneel datum, status en huidige media op het macOS-vergrendelscherm. Het is een aparte overlay en verschijnt nooit in de modulelijst of carrousel.',
        detail: 'Aparte vergrendeloverlay · Opt-in · Neemt geen focus',
      },
    },
  },
  ai: {
    eyebrow: 'AI ZONDER BLACK BOX',
    title: 'Zie AI-status <span>zonder het gesprek te lezen.</span>',
    lede:
      'Taken, status en tokentrends blijven op je Mac. Deze pagina beschrijft de functie en doet niet alsof er een live taakscherm is.',
    summaryMono: 'LOKALE STATUS / DUIDELIJKE GRENZEN',
    summaryLede: 'Verbind de AI-tools die je gebruikt en houd de contextgrenzen van je werk intact.',
    summaryNote: 'Alleen detectiebereik, gegevensgrenzen en verbinding worden uitgelegd; er wordt geen sessie nagebootst.',
    toolsHeading: 'Ondersteunde AI-tools',
    toolsLede: 'Detecteert activiteit van ondersteunde CLI’s, desktopapps en IDE’s en bundelt de taakstatus.',
    toolsAriaLabel: 'Ondersteunde AI-tools',
    doubaoName: 'Doubao',
    boundariesHeading: 'Alleen statusgrenzen worden vastgelegd',
    privacyPoints: [
      'Leest uit gestructureerde gebeurtenissen alleen type, status, tijd, model en sessie-ID',
      'Leest nooit de tekst van prompts of antwoorden',
      'Protocol en status worden op je Mac opgeslagen',
    ],
    bridgeHeading: 'Verbind je eigen taken',
    bridgeLede: 'Gebruik zislactl om gestructureerde status van externe taken naar de statusbalk te sturen.',
    zislactlTaskTitle: 'Build en release',
  },
  flow: {
    eyebrow: 'INTERACTIERITME',
    title: 'Ga omhoog, <span>kijk en laat los.</span>',
    lede: 'Het neemt nooit de focus over en klapt weer in zodra je klaar bent met kijken.',
    ariaLabel: 'Interactieritme bovenaan',
    summaryMono: 'STATUSBALK / 3 STAPPEN',
    summaryLede: 'Klapt uit wanneer je haar nodig hebt en in wanneer je klaar bent.',
    summaryNote: 'Wordt door de cursorpositie geactiveerd, neemt geen ruimte in als ze leeg is en steelt nooit de focus.',
    steps: {
      trigger: { phase: 'Activeren', title: 'Beweeg naar het midden bovenaan', desc: 'Schermen met notch en externe schermen gebruiken dezelfde trigger; verborgen draait er geen frameloop.' },
      review: { phase: 'Bekijken', title: 'Bekijk de huidige status', desc: 'Media, bestanden, AI, agenda en systeemtools staan op één plek.' },
      dismiss: { phase: 'Sluiten', title: 'Ga terug naar je werk', desc: 'Beweeg de cursor weg en het eiland klapt in; uitklappen activeert de app niet en neemt geen focus.' },
    },
  },
  download: {
    eyebrow: 'KLAAR WANNEER JIJ KLAAR BENT',
    title: 'zisla downloaden',
    copy:
      'Voor Macs met Apple Silicon. Versies, andere architecturen en checksums staan op de releasepagina. Na installatie controleert Sparkle eerst de handtekening en downloadt, installeert en herstart het handmatig of automatisch volgens je instellingen.',
    primaryCta: 'Download',
    primaryCtaAriaLabel: 'zisla downloaden',
    releaseCta: 'Release bekijken',
    releaseCtaAriaLabel: 'Releasedetails op GitHub bekijken',
    brewMono: 'HOMEBREW / ÉÉN OPDRACHT',
    brewNote: 'Sparkle houdt zisla zelf bij, dus een gewone brew upgrade laat de app staan; voer brew upgrade --cask zisla uit als Homebrew hem moet vervangen. De tap levert alleen stabiele releases. Het is een tap van derden en de app is niet genotariseerd, dus de eerste start vraagt om "Toch openen" in Systeeminstellingen → Privacy en beveiliging.',
    copyBrewCommandAriaLabel: 'Homebrew-installatieopdracht kopiëren',
    notes: {
      system: { term: 'Systeem', value: 'macOS 14 of later · Huidige ondersteunde configuratie: Mac met Apple Silicon' },
      install: { term: 'Installeren', value: 'Koppel de DMG en sleep hem naar Programma’s' },
      package: { term: 'Pakket', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Andere architecturen', value: 'Releasepagina' },
      mirror: { term: 'Mirror', value: 'Gitee Releases' },
    },
  },
  faq: {
    eyebrow: 'EEN PAAR DUIDELIJKE ANTWOORDEN',
    title: 'Veelgestelde vragen.',
    lede: 'Machtigingen, privacy en compatibiliteit.',
    items: {
      audience: { question: 'Voor wie is zisla?', answer: 'Voor Mac-gebruikers die AI, media, bestanden en agenda op één plek willen. Ook schermen zonder notch worden ondersteund.' },
      aiPrivacy: { question: 'Leest zisla mijn AI-gesprekken?', answer: 'Nee. AI-statusbewaking leest alleen de taakstatus, nooit de tekst van prompts of antwoorden.' },
      copyAssistant: { question: 'Opent of uploadt de kopieerassistent wat ik kopieer?', answer: 'Nee. Herkenning en voorbeeldweergave gebeuren op je Mac; een volgende stap wordt pas na jouw bevestiging uitgevoerd.' },
      permissions: {
        question: 'Welke systeemmachtigingen heeft zisla nodig?',
        answer: `
      <p>zisla vraagt niet bij de eerste start om alle machtigingen tegelijk. macOS toont elke vraag pas wanneer je de bijbehorende functie inschakelt en echt gebruikt:</p>
      <ul>
        <li><strong>Agenda's en Herinneringen:</strong> afzonderlijk gevraagd wanneer je de agendamodule opent, om agenda-afspraken en herinneringen met een datum te lezen, maken en beheren.</li>
        <li><strong>Locatievoorzieningen:</strong> gevraagd wanneer je het weer voor je huidige locatie kiest. zisla bepaalt je locatie één keer en volgt je niet voortdurend. Handmatig een stad toevoegen vereist geen locatiemachtiging.</li>
        <li><strong>Microfoon en spraakherkenning:</strong> gevraagd wanneer je spraakinvoer start. Audio wordt alleen opgenomen terwijl je actief opneemt, en alleen die opname wordt getranscribeerd.</li>
        <li><strong>Toegankelijkheid:</strong> nodig om een transcript automatisch in de huidige app te plaatsen, snel te kopiëren met een muisgebaar, het toetsenbord schoon te maken en sommige ondersteunde spelers te bedienen. De machtiging wordt gebruikt om invoervelden die geen wachtwoordvelden zijn te vinden of de vereiste systeemtoetsen te versturen.</li>
        <li><strong>Invoercontrole:</strong> gebruikt voor toetsenbordgeluiden, optionele lokale typestatistieken en globale triggers zoals één losse modificatietoets of een muisknop aan de zijkant. Alleen de globale gebeurtenissen die deze functies nodig hebben worden gevolgd; gewone globale sneltoetsen hebben dit niet nodig.</li>
        <li><strong>Schermopname en opname van systeemgeluid:</strong> nodig voor screenshots, het bewerken ervan en de golfvorm van afgespeeld systeemgeluid. Screenshots lezen het schermbeeld; de golfvorm analyseert alleen het huidige geluidsniveau en slaat geen audio op en verstuurt die ook niet.</li>
        <li><strong>Camera:</strong> alleen gebruikt zolang het spiegelvenster open is.</li>
        <li><strong>Bluetooth:</strong> alleen gebruikt zolang de batterijmodule open is, om het batterijniveau te lezen dat verbonden of gekoppelde apparaten publiceren.</li>
        <li><strong>Automatisering:</strong> wanneer je Snelle notities, Mail, het opruimen van het bureaublad of directe bediening van een ondersteunde speler voor het eerst gebruikt, vraagt macOS afzonderlijk of zisla Notities, Mail, Finder of die app mag bedienen. Snelle notities leest en schrijft in Notities; Mail kan berichten lezen, opstellen, beantwoorden, markeren en verwijderen.</li>
        <li><strong>Volledige schijftoegang:</strong> alleen nodig wanneer Mail niet actief is en zisla toch de lokale mailindex moet lezen om accounts, afzenders, onderwerpen, voorbeelden, tijdstippen en leesstatus te tonen.</li>
        <li><strong>Meldingen:</strong> gevraagd wanneer je de Pomodoro-timer of alarmen inschakelt, uitsluitend om een lokale melding te tonen wanneer een timer afloopt of een alarm afgaat.</li>
      </ul>
      <p><strong>Mappen zijn geen volledige schijftoegang:</strong> voor de opslag-, import/export- of downloadmappen die je in de systeemkiezer selecteert, krijgt zisla alleen toegang tot die map, nooit leesrechten voor de hele schijf.</p>
      <p><strong>Toetsenbordgeluiden en typestatistieken:</strong> beide staan standaard uit en globale toetsenbordgebeurtenissen worden pas gevolgd wanneer één van beide is ingeschakeld. Met toetsenbordgeluiden worden toetsaanslagen uitsluitend gebruikt om geluid af te spelen; met typestatistieken worden alleen geaggregeerde gegevens opgeslagen — tekentaantallen, fysieke toetscodes, tijdstippen en de app op de voorgrond — nooit wat je hebt getypt. Je kunt beide opties afzonderlijk uitschakelen in Instellingen; daarna wordt niets meer vastgelegd. Eerder opgeslagen gegevens blijven in een lokaal databasebestand staan dat je zelf kunt verwijderen.</p>
      <p>Je kunt een functie uitschakelen in de instellingen van de app of een machtiging op elk moment intrekken via Systeeminstellingen → Privacy en beveiliging. Het intrekken van één machtiging schakelt alleen de bijbehorende functie uit en laat andere modules ongemoeid. Namen van onderdelen kunnen per macOS-versie iets verschillen.</p>
    `.trim(),
      },
      network: { question: 'Gaat zisla online?', answer: 'Weer, ondertekende updatecontroles, downloads die je start en optionele externe spraakbewerking gebruiken indien nodig het netwerk. Linkherkenning gebeurt lokaal.' },
      multiDisplay: { question: 'Ondersteunt zisla meerdere schermen?', answer: 'Ja: meerdere schermen, Spaces en gewone apps op volledig scherm; uitklappen neemt nooit de focus.' },
      intel: { question: 'Kan ik zisla op een Intel-Mac gebruiken?', answer: 'Er kan een Intel-build bestaan, maar compatibiliteit is niet gegarandeerd. De huidige ondersteunde configuratie is Apple Silicon.' },
      storage: { question: 'Waar slaat zisla gegevens op?', answer: 'Lokale gegevens staan in ~/Library/Application Support/zisla/. Typestatistieken staan apart in ~/Library/Application Support/SimuBoard/typing-stats.sqlite3. Snelle notities gebruikt de systeemapp Notities.' },
    },
  },
  developers: {
    eyebrow: 'STANDAARD OPEN SOURCE',
    title: 'Bronnen voor ontwikkelaars.',
    lede: 'PolyForm Noncommercial 1.0.0-licentie: alleen niet-commercieel gebruik, zoals het is of gebouwd vanuit de broncode.',
    docs: {
      macos: { title: 'macOS-ontwikkelgids', description: 'Functies, bouwen, testen en systeemgrenzen' },
      architecture: { title: 'Architectuur en prestaties', description: 'Triggers, vensters en prestatieontwerp bovenaan' },
      cli: { title: 'CLI-integratie', description: 'zislactl-opdrachten en velden' },
      releasing: { title: 'Ondertekenen en releasen', description: 'Ondertekening, notarization en releaseproces' },
      contributing: { title: 'Bijdragegids', description: 'Omgeving, branches, commits en pull-requestvereisten' },
    },
    quickStartMono: 'SNEL STARTEN / BRONCODE',
    quickStartHeading: 'Voer het uit vanuit de broncode of verbind je eigen taken.',
    copyRunCommandAriaLabel: 'Opdracht om vanuit de broncode te starten kopiëren',
    githubRepoLabel: 'GitHub-repository',
    giteeRepoLabel: 'Gitee-repository',
    checksumLabel: 'SHA-256',
    performancePoints: [
      'Ondersteunt meerdere schermen, Spaces en gewone apps op volledig scherm; uitklappen activeert de app niet en neemt geen focus',
      'Verborgen wordt geen permanente transparante hotspot en geen frameloop gebruikt; uitbreiding werkt via globale gebeurtenissen en geometrie',
      'Gebruikt één laag systeemmateriaal en schakelt naar een ondoorzichtige achtergrond bij Verminder transparantie',
      'Liquid Glass op macOS 26+, met automatische terugval naar native materialen op macOS 14 en 15',
      'Een fysieke notch wordt afgeleid uit de veilige systeemzone; externe schermen zonder notch krijgen een gesimuleerde statusbalk in een eigen overlay',
    ],
  },
  footer: {
    brandHomeAriaLabel: 'Terug naar de zisla-home',
    previewChannelLabel: 'Previewkanaal',
    tagline: 'Open source, native en onder jouw controle.',
  },
  common: { copyCommandTitle: 'Opdracht kopiëren', copiedAriaLabel: 'Gekopieerd' },
  toast: { runCommandCopied: 'Startopdracht gekopieerd', zislactlCopied: 'zislactl-opdracht gekopieerd', brewCommandCopied: 'Homebrew-installatieopdracht gekopieerd' },
});
