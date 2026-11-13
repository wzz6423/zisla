import { createCatalog } from './createCatalog';

export const nl = createCatalog({
  meta: {
    documentTitle: 'zisla · Dynamische werkruimte',
    description:
      'zisla is een native macOS-werkruimte voor AI-taken, dagoverzichten en opnames bewerken, met eigen dieren, schermafbeeldingen en centrale toestemmingen.',
    ogTitle: 'zisla · Zet wat er gebeurt waar je het kunt zien',
    ogDescription:
      'Houd AI-taken en uw dag in beeld, neem op en bewerk op uw Mac, importeer een eigen dier en beheer toestemmingen op één plek.',
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
      changelog: 'Wijzigingslog',
      faq: 'Veelgestelde vragen',
      developers: 'Ontwikkelaars',
    },
    downloadCta: 'Download',
    downloadCtaAriaLabel: 'Naar de downloadsectie',
    languageLabel: 'Interfacetaal',
    themeLabel: 'Weergave',
    themeModes: { auto: 'Automatisch (systeem)', light: 'Lichte modus', dark: 'Donkere modus' },
  },
  hero: {
    eyebrow: 'NATIVE MACOS-WERKRUIMTE',
    title: 'zisla<br><em>Wat er gebeurt,<br>precies waar je het ziet.</em>',
    lede:
      'Verzamel AI-taken, media, bestanden en je agenda bovenaan het scherm. Na het kopiëren toont een aparte balk met snelle acties een voorbeeld en stelt de volgende stap voor. Ze verschijnt wanneer nodig en verdwijnt daarna weer.',
    downloadCta: 'Download',
    downloadCtaAriaLabel: 'Download',
    sourceCta: 'Broncode bekijken',
    sourceCtaAriaLabel: 'De broncode van zisla op GitHub bekijken',
    hints: [
      'Beweeg naar de bovenkant om uit te klappen, zonder klik',
      'Druk na het kopiëren op Command+N voor de slimme volgende stap',
      'Klapt vanzelf in zonder je werk te onderbreken',
    ],
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
      '{modules} modules bovenaan en {features} zelfstandige functies, van venstervoorbeelden en opnamen tot AI-beheer en aanbevolen apps.',
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
          'Livekaarten verschijnen alleen tijdens een focussessie, AI-taak of download; als er niets gebeurt, nemen ze geen ruimte in. Op de startpagina wordt lopend AI-werk per app gegroepeerd.',
        points: ['Verschijnt op aanvraag', 'Live voortgang', 'Lay-out past zich aan'],
      },
      shelf: {
        name: 'Plank',
        caption:
          'Sleep bestanden, audio, video of links naar de bovenkant van het scherm. Zoek en filter items, selecteer er meerdere en kopieer, deel of stuur ze naar Snelle notities. Zet afbeeldingen om naar PDF, stuur herkende tekst naar Snelle notities of bewerk video’s in de opnamestudio. Je kunt bestanden ook in Finder tonen.',
        points: ['Zoeken en batchacties', 'Afbeeldingen naar PDF en Snelle notities', 'Video’s bewerken in de studio'],
      },
      clipboard: {
        name: 'Klembord',
        caption:
          'Bekijk de klembordgeschiedenis in het eiland en filter op afbeelding, URL, pad of bestandstype en zie wanneer elk item is gekopieerd. Stuur een item naar Snelle notities, maak het favoriet of verwijder het. Je kunt geschiedenis ouder dan 7, 15 of 30 dagen automatisch verwijderen en favorieten behouden. Automatisch verwijderen staat standaard uit.',
        points: ['Geschiedenis in het eiland', 'Filteren op type', 'Snelle notities en favorieten'],
      },
      aiMonitor: {
        name: 'AI-monitor',
        caption:
          'Bundelt taken en status van AI-CLI’s, desktopapps en IDE’s. Betrouwbare cijfers vormen tokentrends en een bijdrageheatmap; kies een datum voor invoer-, uitvoer- en totaaltokens per aanbieder en model. Bekijk de geschiedenis in Instellingen, exporteer alles als .xlsx of wis het. Toont echte accountquota, resettijden en waarschuwingen bij weinig quota, waaronder 5h/7d-periodes en Cursor-budgetten in dollars wanneer beschikbaar. Leest geen prompt- of antwoordtekst.',
        points: ['Taken uit meerdere AI-tools', 'Modelgeschiedenis en .xlsx-export', 'Accountquota en resettijden'],
      },
      keyboardSound: {
        name: 'Toetsenbordgeluiden',
        caption:
          'Speelt 20 ingebouwde mechanische toetsenbordgeluiden af voor globale toetsaanslagen, met instelbaar volume en natuurlijke toonvariatie. Schakel lokale typestatistieken in voor overzicht, trends, geschiedenis, app-tijdlijn en een heatmap met F1-F12. Spraaktotalen, dicteerduur, snelheid en bespaarde tijd staan ook in het toetsenborddashboard. Nieuwe configuraties schakelen geluiden en typstatistieken in; beide zijn apart uit te zetten.',
        points: ['20 ingebouwde geluiden', 'Loslaatgeluid en toonvariatie', 'Typstatistieken apart schakelbaar'],
      },
      download: {
        name: 'Downloader',
        caption:
          'Plak een link of laat zisla links uit het klembord herkennen zodra de functie is ingeschakeld. Kies video of audio en download naar de standaardmap of een map naar keuze. Ondersteunde links tonen bron, live voortgang en voltooiingsstatus. Kies de downloadmap onder Instellingen → Opslaglocatie, los van schermafbeeldingen en opnamen. Bilibili-links downloaden het gekozen videodeel.',
        points: ['Video- / audiomodi', 'Standaard- of eigen map', 'Bron en live voortgang'],
      },
      agenda: {
        name: 'Agenda en weer',
        caption:
          'Toont het weer op je locatie en op maximaal zes gekozen plaatsen. Bekijk, voeg toe of verwijder agenda-items en herinneringen en markeer herinneringen als voltooid. Items met een vergaderlink tellen vanaf 10 minuten voor de start af en laten je met één klik deelnemen. Maak een vergadernotitie of koppel en ontkoppel bestaande contextnotities.',
        points: ['Weer en agenda', 'Aftellen vanaf 10 minuten vooraf', 'Deelnemen en notities koppelen'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Leest de accounts die in Mail zijn ingeschakeld. Bekijk de inbox, markeer één bericht of alle inboxberichten als gelezen, antwoord, schrijf en verplaats berichten naar de prullenmand vanuit het eiland. Kies bijlagen tijdens het schrijven; ontbrekende rechten worden duidelijk uitgelegd.',
        points: ['Mail-accounts', 'Antwoorden en opstellen in het eiland', 'Heldere machtigingsuitleg'],
      },
      quickNotes: {
        name: 'Snelle notities',
        caption:
          'Gebruikt de systeemapp Notities om notities te bekijken, bewerken, maken en verwijderen met live Markdown-voorbeeld, en met Command+1 tot 9 meteen naar de eerste negen notities te springen. Concepten worden automatisch teruggeschreven. Bekijk handgeschreven bijlagen en bewerk de tekst ervoor of erna, met behoud van de originelen.',
        points: ['Gegevens in Notities', 'Markdown-editor', 'Concepten automatisch opgeslagen'],
      },
      volumeMixer: {
        name: 'Volumemixer per app',
        caption: 'Pas het volume en dempen apart aan voor apps die geluid afspelen. Vereist macOS 14.4 of nieuwer en toestemming voor opname van systeemaudio.',
        points: ['Volume per toepassing', 'Apart dempen', 'macOS 14.4+'],
      },
      toolbox: {
        name: 'Hulpprogramma’s',
        caption:
          'Focustimer, scherm wakker houden, schermreiniging, toetsenbordreiniging die ook F1-F12 blokkeert, teleprompter, spiegel en prullenmand op één pagina. Pauzeer, hervat of reset de Pomodoro en volg de voortgang in compacte horizontale en verticale weergaven.',
        points: ['Focusafteller', 'Blokkeert F1-F12 tijdens reinigen', 'Teleprompter en spiegel'],
      },
      system: {
        name: 'Systeemstatus',
        caption:
          'Bewaakt CPU, GPU, geheugen, schijf, netwerk, ventilatoren en beschikbare NVMe-SMART-temperatuur. Bekijk geschiedenis per minuut voor een datumbereik, exporteer .xlsx of wis het in Instellingen. Controleer batterijconditie, cycli, temperatuur, capaciteit, apparaten in de buurt en openbare IPv4/IPv6. Kies automatische energiemodi voor netstroom en batterij, optioneel met energiebesparing bij 20% of minder. Laad direct tot 100% wanneer macOS dat aanbiedt. Controleer caches, logs, achtergebleven voorkeuren en verweesde AI-werkruimten voor je ze naar de prullenmand verplaatst; optioneel opruimen kan elke 7, 15 of 30 dagen. Gepland opruimen staat standaard uit; kies alleen vertrouwde items of alle verwerkbare items, ook die nog beoordeeld moeten worden.',
        points: ['Monitoring op chipniveau', 'Geschiedenisgrafieken en .xlsx-export', 'Controleren vóór verplaatsen naar prullenmand'],
      },
    },
  },
  extensions: {
    eyebrow: 'BINNEN EN BUITEN HET EILAND',
    title: 'Buiten het eiland, <span>nog steeds een desktoptool.</span>',
    lede:
      'Schermafbeeldingen, beeld- en audiotools, dicteren, media, browserdownloads en AI-beheer verschijnen waar ze makkelijk bereikbaar zijn.',
    ariaLabel: 'Zelfstandige desktopfuncties',
    summaryMono: 'VOORBIJ HET EILAND',
    summaryLede: 'Veelgebruikte functies, elk op een natuurlijke plek.',
    summaryNote:
      'Venstervoorbeelden, opnamen en snelle acties zijn binnen handbereik; aanbevolen apps helpen je meer hulpmiddelen voor je bureaublad te ontdekken.',
    features: {
      floatingIsland: {
        title: 'Een zwevend eiland dat zich aanpast',
        description: 'Gebruik de camerapositie of kies een plek aan een schermrand. De eigen positie blijft bewaard bij het wisselen van modus. Horizontale en verticale compacte weergaven passen hun lengte aan pictogrammen, AI-taken, downloads en media aan en kunnen meer informatie tonen. Sleep modules in Instellingen → Info naar een andere plek of herstel de standaardvolgorde.',
        detail: 'Eigen positie · Blijvende statuspictogrammen · Aanpasbare informatie',
      },
      dailyBriefing: {
        title: 'Uw dag in een dagoverzicht',
        description: 'Kies uit acht sjablonen, selecteer gebruiks-, typ-, systeem- en zisla-activiteitsgegevens en bekijk de voorvertoning. Exporteer een PNG handmatig of dagelijks op een gekozen tijd. Schermtijdgeschiedenis wordt gebruikt als deze is ingeschakeld en beschikbaar; ontbrekende gegevens gelden niet als gemeten nul. Kies een aparte exportmap onder Instellingen → Opslaglocatie. Je kunt ook echte accountquota en de tijd van de meting opnemen.',
        detail: '8 sjablonen · Inhoud kiezen · Voorvertoning en geplande PNG-export',
      },
      userCare: {
        title: 'Herinneringen tijdens het werk',
        description: 'Stel een interval in voor pauzes, water, beweging en rust voor de ogen. Berichten volgen het tijdstip. Natuurlijke pauzes, vergrendelen en sluimerstand resetten de tijdmeting. Voltooide focus en notitiehandelingen kunnen korte feedback tonen. In Instellingen aan of uit te zetten.',
        detail: 'Instelbaar interval · Berichten per tijdstip · Houdt rekening met inactiviteit en sluimeren',
      },
      contextNotes: {
        title: 'Notities op de juiste plek',
        description: 'Bewaar een bewerkbare notitie voor een webpagina, appvenster of bureaublad en zie die bij terugkeer. Voeg een vensterafbeelding toe, beheer notities op de plank en stel herhalingen van één uur tot drie dagen in, of zet ze uit.',
        detail: 'Plaatsgebonden notities · Vensterafbeeldingen · Terugkerende herinneringen',
      },
      recording: {
        title: 'Opnemen en bewerken in de studio',
        description: 'Neem scherm, venster of gebied op met optionele systeemaudio, microfoon en camera. Bewerk video, audio, afbeeldingen en tekst op meerdere sporen met animaties, zoom en ondertitels. Pas huidverzachting, helderheid, versmalling van gezicht en lichaam, stemeffecten en vloeiende cursorsporen in je eigen kleur aan. Speel de bewerking af in de studio. Kies origineel, 16:9, 9:16, 1:1 of 4:3; exporteer video, GIF, Live Photo of audio. Sommige formaten vereisen FFmpeg. Bekijk optionele AI-plannen voordat je ze toepast. De opnamemap kies je apart onder Instellingen → Opslaglocatie.',
        detail: 'Portret- en stemeffecten · Gekleurde cursorsporen · Meersporenweergave en export',
      },
      permissions: {
        title: 'Systeemtoestemmingen op één plek',
        description: 'Bekijk status in Instellingen → Toestemmingen, start ondersteunde aanvragen of open de juiste systeempagina. Het eerste welkomstscherm gebruikt dezelfde lijst en markeert handmatige instellingen.',
        detail: 'Toestemmingsstatus · Aanvragen en links · Gedeeld met het welkom',
      },
      imageTools: {
        title: 'Afbeeldingstools',
        description: 'Negen lokale tools in Instellingen: comprimeren; PNG, JPEG, WebP, AVIF en JPEG XL omzetten; schalen en bijsnijden; het kleinste formaat vergelijken; draaien en spiegelen; watermerken; mozaïek en vervaging; tekst en tabellen herkennen; achtergronden verwijderen. Exporteer batches of ZIP-bestanden, met een eigen map in Instellingen → Opslaglocatie.',
        detail: '9 lokale tools · Vijf formaten · Batch- en ZIP-export',
      },
      audioTools: {
        title: 'Audiogereedschap',
        description: '27 lokale bewerkingen in Instellingen, zoals omzetten, comprimeren, knippen, splitsen, samenvoegen en mixen, audio uit video halen, LUFS-normalisatie, fades, snelheid en toonhoogte, ruis en stilte verwijderen, EQ, dynamiek, kanalen en tags. Vereist FFmpeg en ffprobe; kies een bestand of map voor de export.',
        detail: '27 lokale bewerkingen · Bewerken en mixen · FFmpeg en ffprobe',
      },
      pdf: {
        title: 'PDF-tools',
        description: 'Beschikbaar in Instellingen, buiten de modulecarrousel van het eiland. Veertien bewerkingen op je Mac: samenvoegen, splitsen, draaien, bijsnijden, afbeeldingen en Office-bestanden converteren, renderen, tekst exporteren, watermerken en paginanummers toevoegen, versleutelen, wachtwoord verwijderen en metadata bewerken.',
        detail: '14 lokale tools · Samenvoegen in eigen volgorde · Niets verlaat je Mac',
      },

      windowPreviews: {
        title: 'Bekijk een venster, wissel met een klik',
        description:
          'Bekijk vensters vanuit het Dock of met Command-Tab en klik op een kaart om dat venster te activeren. Nieuwe configuraties schakelen dit in; beheer de functie en toestemming in Instellingen.',
        detail: 'Dock en Command-Tab · Klik om te wisselen · Instelbaar',
      },
      capture: {
        title: 'Schermafbeeldingen, scrollcaptures en vastzetten',
        description:
          'Maak, zet vast of voeg scrollende schermafbeeldingen samen met eigen sneltoetsen. Markeer gebieden, haal afbeeldingsdelen eruit, rond hoeken af en behoud annotaties bij export. Herken en kopieer tekst, vertaal en kopieer het resultaat of exporteer herkende tabellen als .xlsx. Bewaar afbeeldingen op de plank. Instellingen controleren conflicten met spraak en snelle acties. Het opslagvenster opent in de screenshotmap onder Instellingen → Opslaglocatie. Vastgezette afbeeldingen blijven bij nieuwe captures staan. Gebruik langzaam automatisch scrollen voor lange schermafbeeldingen; ondersteunde apparaten kunnen HDR vastleggen.',
        detail: 'Markeren en extraheren · Herkennen, vertalen en kopiëren · Ronde hoeken en .xlsx',
      },
      voice: {
        title: 'Spraakinvoer en opschonen',
        description:
          'Schakel met een toets of houd die ingedrukt om te praten via de spraakherkenning van het systeem, met vakwoordenlijsten en eigen trefwoorden. Gebruik desgewenst Ollama, LM Studio of een extern model om de transcriptie met behoud van betekenis te corrigeren en expliciet opgesomde punten op te maken.',
        detail: 'Twee opnamemodi · Woordenlijsten en trefwoorden · Optionele modelbewerking',
      },
      media: {
        title: 'Media en omgevingsgeluiden',
        description:
          'Bedien wat er speelt bovenaan het eiland of kies een omgevingsgeluid van macOS. Het kan stoppen wanneer het scherm vergrendelt, de schermbeveiliging start of het scherm slaapt. Kies een golfvorm of hoesgloed; de afspeelvoortgang staat ook in compacte en zwevende weergaven.',
        detail: 'Afspeelbediening · Gesynchroniseerde songteksten · Automatisch stoppen',
      },
      browserDownloads: {
        title: 'Voortgang van browserdownloads',
        description:
          'Herkent downloads in Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera en Arc en toont bron en live voortgang bovenaan.',
        detail: '8 browsers · Bronherkenning · Melding bij voltooiing',
      },
      copyAssistant: {
        title: 'Snelle acties en volgende stappen',
        description:
          'Na inschakelen worden gekopieerde tekst, links, bestanden of afbeeldingen in een aparte balk getoond, met opties om te openen, in Finder te tonen, te zoeken, vertalen, berekenen of opslaan — alleen na jouw bevestiging. Open de bestandsmap via snelle acties na een browserdownload of AirDrop-overdracht. Ondersteunt standaard en zelfgekozen Chrome-downloadmappen, met een aparte schakelaar naast de downloadvoortgang. IP-adressen hebben aparte acties voor opzoeken en links openen. Conversies herkennen kleine munteenheden; de catalogus bevat Emoji 18.0. Opgeslagen tekst en afbeeldingen gebruiken de aparte map voor snelle acties onder Instellingen → Opslaglocatie. Als een app niet opent, kunnen Snelle acties de integriteit, handtekening en het macOS-beveiligingsbeleid controleren. Na geslaagde controles kunnen ze quarantainekenmerken verwijderen en de app openen.',
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
        description: 'Kies uit de uitgebreide dieren- en personagecatalogus of importeer een ondersteunde afbeelding, animatie of video met een eigen naam. Plaats het dier aan een kant van het eiland en verwijder geïmporteerde dieren in Instellingen. Animaties tot 30 seconden en bestanden tot 100 MB.',
        detail: 'Uitgebreide catalogus · Afbeeldingen en video importeren · Eigen dieren verwijderen',
      },
      lockScreen: {
        title: 'Informatie op het vergrendelscherm',
        description:
          'Toon optioneel datum, status en huidige media op het macOS-vergrendelscherm. Het is een aparte overlay en verschijnt nooit in de modulelijst of carrousel.',
        detail: 'Aparte vergrendeloverlay · Opt-in · Neemt geen focus',
      },
      recommendedTools: {
        title: 'Aanbevolen apps',
        description:
          'Ontdek OpenScreen voor schermopnamen en videobewerking, DockDoor voor venstervoorbeelden en appwissels en Zshell als native macOS-terminalwerkruimte. Deze apps van andere ontwikkelaars installeer je apart.',
        detail: 'Ontdek bureaubladtools · Apps van derden · Aparte installatie',
      },
    },
  },
  ai: {
    eyebrow: 'AI ZONDER BLACK BOX',
    title: 'Zie AI-status <span>zonder het gesprek te lezen.</span>',
    lede:
      'Bekijk taken per app, modelgebruik per datum en echte accountquota. Status en numerieke gegevens blijven op je Mac; gesprekken worden niet gelezen.',
    summaryMono: 'LOKALE STATUS / DUIDELIJKE GRENZEN',
    summaryLede: 'Verbind de AI-tools die je gebruikt en houd de contextgrenzen van je werk intact.',
    summaryNote: 'Alleen detectiebereik, gegevensgrenzen en verbinding worden uitgelegd; er wordt geen sessie nagebootst.',
    toolsHeading: 'Ondersteunde AI-tools',
    toolsLede: 'Detecteert activiteit van ondersteunde CLI’s, desktopapps en IDE’s en bundelt de taakstatus.',
    toolsAriaLabel: 'Ondersteunde AI-tools',
    usageNote: 'Sessiedetectie, tokengeschiedenis en accountquota gebruiken aparte bronnen. Delta gebruikt zijn lokale cijferregister; Orca ontdubbelt het gebruik van de gekoppelde CLI en wijst het toe aan de oorspronkelijke aanbieder. WorkBuddy AI kan sessies detecteren en credits opvragen; contextbezetting en credits worden niet omgerekend naar tokens of kosten in dollars. Beschikbare quota hangen af van de aanbieder en inlogmethode.',
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
      'Voor Macs met Apple Silicon. Versies, andere architecturen en checksums staan op de releasepagina. Na installatie controleert Sparkle eerst de handtekening en downloadt, installeert en herstart het handmatig of automatisch volgens je instellingen; updates behouden de al verleende machtigingen. Sla je een versie over, dan wordt die niet meer gemeld. Lees versienotities vóór installatie en na het herstarten.',
    primaryCta: 'Download',
    primaryCtaAriaLabel: 'zisla downloaden',
    releaseCta: 'Release bekijken',
    releaseCtaAriaLabel: 'Releasedetails op GitHub bekijken',
    brewMono: 'HOMEBREW / ÉÉN OPDRACHT',
    brewNote: 'Sparkle houdt zisla zelf bij, dus brew upgrade vervangt de app alleen als de geïnstalleerde versie echt ouder is dan die in de tap — vanaf Homebrew 5.1.6 wordt de versie in de app zelf gelezen. Noem je de cask expliciet, zoals in brew upgrade --cask zisla, dan gelden de installatiegegevens van Homebrew en kun je na een Sparkle-update terugvallen op de versie uit de tap. De tap levert alleen stabiele releases. Het is een tap van derden en de app is niet genotariseerd, dus de eerste start vraagt om "Toch openen" in Systeeminstellingen → Privacy en beveiliging.',
    copyBrewCommandAriaLabel: 'Homebrew-installatieopdracht kopiëren',
    notes: {
      system: { term: 'Systeem', value: 'macOS 14 of later · Huidige ondersteunde configuratie: Mac met Apple Silicon' },
      install: { term: 'Installeren', value: 'Koppel de DMG en sleep hem naar Programma’s' },
      package: { term: 'Pakket', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Andere architecturen', value: 'Releasepagina' },
      mirror: { term: 'Mirror', value: 'Gitee Releases' },
    },
  },
  changelog: {
    releaseNotes: {
      'v0.1.22': [
        'De studio voegt huidverzachting, helderheid, versmalling van gezicht en lichaam, verstelbare stempresets en optionele microfoonmonitoring toe. Effecten zijn vóór opname en tijdens bewerken aanpasbaar.',
        'Vloeiende cursorsporen hebben een kleur naar keuze. De studio speelt het bewerkte resultaat af met sporen, effecten en audio.',
        'Instellingen → Opslaglocatie scheidt downloads, schermafbeeldingen, opnamen, snelle acties en dagoverzichten. De update behoudt bestaande locaties; daarna is elke map afzonderlijk aanpasbaar.',
        'Optionele systeemopruiming verplaatst items elke 7, 15 of 30 dagen naar de prullenmand. Kies vertrouwde of alle verwerkbare items, inclusief items die controle vereisen; standaard uit. Schijfopruiming voegt AI-werkmappen zonder bewaarde sessie toe voor controle en beschermt bewaarde sessies en nieuwe mappen.',
        'Klembordgeschiedenis kan items ouder dan 7, 15 of 30 dagen automatisch verwijderen en favorieten behouden. Automatisch verwijderen staat standaard uit.',
        'Snelle notities toont handgeschreven bijlagen en laat tekst ervoor of erna via Notities bewerken, met behoud van originele bijlagen.',
        'AI-monitoring verbergt resterende abonnementsquota, houdt dagelijks gebruik bij en verbetert grafiekscrollen en maandlabels. Batterijinstellingen staan onder Systeemstatus.',
        'Quiet.md voor lokale notities hoort bij de aanbevolen apps en is via Instellingen te installeren en beheren.',
        'Bilibili downloadt het gekozen videodeel en verwerkt meer linkformaten. Kalenderverwijdering richt zich op het gekozen herhalingsmoment. Vastgezette afbeeldingen blijven tussen captures zichtbaar; gereedschapslabels en maatbadges zijn betrouwbaarder.',
      ],
      'v0.1.21': [
        'De systeembewaking bewaart standaard alle bestaande en nieuwe geschiedenis per minuut totdat je die wist. Grafieken voor elke periode en export naar .xlsx blijven beschikbaar.',
        'Downloads, opnamen en schermafbeeldingen delen één opslaglocatie. Het opslagvenster voor schermafbeeldingen opent in de huidige downloadmap; de dubbele instelling voor de opslaglocatie van opnamen is verwijderd.',
        'De locatie voor statusindicatoren en de bijbehorende zoekvermelding verschijnen alleen bij pillen met een aangepaste positie. De rij is verborgen bij inkepingen of pillen op de camerapositie wanneer alleen de menubalk beschikbaar is.',
        'De aftelling van snelle acties gebruikt een voortgangsbalk onderaan bij inkepingslayouts. Pillen houden de voortgang langs de volledige omtrek.',
      ],
      'v0.1.20': [
        'Kies uit acht sjablonen, selecteer gebruiks-, typ-, systeem- en zisla-activiteitsgegevens en bekijk de voorvertoning. Exporteer een PNG handmatig of dagelijks op een gekozen tijd. Schermtijdgeschiedenis wordt gebruikt als deze is ingeschakeld en beschikbaar; ontbrekende gegevens gelden niet als gemeten nul.',
        'Stel een interval in voor pauzes, water, beweging en rust voor de ogen. Berichten volgen het tijdstip. Natuurlijke pauzes, vergrendelen en sluimerstand resetten de tijdmeting. Voltooide focus en notitiehandelingen kunnen korte feedback tonen. In Instellingen aan of uit te zetten. Bewaar een bewerkbare notitie voor een webpagina, appvenster of bureaublad en zie die bij terugkeer. Voeg een vensterafbeelding toe, beheer notities op de plank en stel herhalingen van één uur tot drie dagen in, of zet ze uit.',
        'Gebruik de camerapositie of kies een plek aan een schermrand. De eigen positie blijft bewaard bij het wisselen van modus. Horizontale en verticale compacte weergaven passen hun lengte aan pictogrammen, AI-taken, downloads en media aan en kunnen meer informatie tonen. Kies een golfvorm of hoesgloed; de afspeelvoortgang staat ook in compacte en zwevende weergaven.',
        'Kies uit de uitgebreide dieren- en personagecatalogus of importeer een ondersteunde afbeelding, animatie of video met een eigen naam. Plaats het dier aan een kant van het eiland en verwijder geïmporteerde dieren in Instellingen. Animaties tot 30 seconden en bestanden tot 100 MB.',
        'Neem scherm, venster of gebied op met optionele systeemaudio, microfoon en camera. Bewerk video, audio, afbeeldingen en tekst op meerdere sporen, voeg animaties, zoom en ondertitels toe en bekijk een scherpe voorvertoning. Kies origineel, 16:9, 9:16, 1:1 of 4:3. Exporteer video, GIF, Live Photo of audio; sommige formaten vereisen FFmpeg. Optionele AI-plannen worden bekeken voor toepassing.',
        'Maak, zet vast of voeg scrollende schermafbeeldingen samen met eigen sneltoetsen. Markeer gebieden, haal afbeeldingsdelen eruit, rond hoeken af en behoud annotaties bij export. Herken en kopieer tekst, vertaal en kopieer het resultaat of exporteer herkende tabellen als .xlsx. Bewaar afbeeldingen op de plank. Instellingen controleren conflicten met spraak en snelle acties.',
        'Taakdetectie voor Cursor en numeriek gebruik met beschikbare abonnementsquota voor Cursor en Muse Code zijn toegevoegd; lange tooltaken in Cursor blijven zichtbaar. IP-adressen hebben aparte acties voor opzoeken en links openen. Conversies herkennen kleine munteenheden; de catalogus bevat Emoji 18.0.',
        'Pas het volume en dempen apart aan voor apps die geluid afspelen. Vereist macOS 14.4 of nieuwer en toestemming voor opname van systeemaudio. Beschikbaar in Instellingen, buiten de modulecarrousel van het eiland. Bekijk status in Instellingen → Toestemmingen, start ondersteunde aanvragen of open de juiste systeempagina. Het eerste welkomstscherm gebruikt dezelfde lijst en markeert handmatige instellingen. Spraaktotalen, dicteerduur, snelheid en bespaarde tijd staan ook in het toetsenborddashboard. Nieuwe configuraties schakelen geluiden en typstatistieken in; beide zijn apart uit te zetten. Kies tijdens het schrijven bestanden om als bijlagen toe te voegen. Lees versienotities vóór installatie en na het herstarten.',
      ],
    },
    eyebrow: 'Wijzigingslog',
    title: 'Wat er in elke zisla-release is veranderd: nieuwe functies, verbeteringen en oplossingen.',
    lede: 'Wat er in elke zisla-release is veranderd: nieuwe functies, verbeteringen en oplossingen.',
    ariaLabel: 'zisla-releasegeschiedenis',
    releaseCountLabel: 'releases',
    latestLabel: 'nieuwste',
    shippedLabel: 'uitgebracht',
    latestBadge: 'Nieuwste',
    noteLabel: 'release',
    pagerAriaLabel: "Changelog-pagina's",
    pageLabel: 'Pagina {page}',
    prevPageLabel: 'Vorige',
    nextPageLabel: 'Volgende',
  },
  faq: {
    eyebrow: 'EEN PAAR DUIDELIJKE ANTWOORDEN',
    title: 'Veelgestelde vragen.',
    lede: 'Machtigingen, privacy en compatibiliteit.',
    items: {
      audience: { question: 'Voor wie is zisla?', answer: 'Voor Mac-gebruikers die AI, media, bestanden en agenda op één plek willen. Ook schermen zonder notch worden ondersteund.' },
      aiPrivacy: { question: 'Leest zisla mijn AI-gesprekken?', answer: 'Nee. AI-statusbewaking leest alleen de taakstatus, nooit de tekst van prompts of antwoorden.' },
      copyAssistant: { question: 'Openen of uploaden snelle acties wat ik kopieer?', answer: 'Nee. Herkenning en voorbeeldweergave gebeuren op je Mac; een volgende stap wordt pas na jouw bevestiging uitgevoerd.' },
      permissions: {
        question: 'Welke systeemmachtigingen heeft zisla nodig?',
        answer: '<p>Instellingen → Toestemmingen bundelt status, aanvragen en links naar Systeeminstellingen. Sommige toestemmingen moeten handmatig worden ingesteld. U kiest welke aanvragen starten; het eerste welkomstscherm biedt dezelfde bediening.</p><p>Schermopname, systeemaudio, microfoon en camera ondersteunen opname, mixer en spiegel waar nodig. Dictaat gebruikt ook spraakherkenning. Agenda’s, Herinneringen, Locatie, Bluetooth en Automatisering horen bij hun functies. Een weerstad handmatig toevoegen vereist geen locatie.</p><p>Nieuwe configuraties schakelen toetsenbordgeluid en typstatistieken in; beide zijn apart uit te zetten. Globale toetsen vereisen invoermonitoring. Statistieken bewaren aantallen, toetscodes, tijden en appnamen, nooit uw ingevoerde tekst. Toegankelijkheid dient voor invoegen, gebaren, reinigen en vensterbediening.</p><p>Volledige schijftoegang kan nodig zijn voor de lokale mailindex en Schermtijdgeschiedenis van dagoverzichten. De bestandskiezer geeft toegang tot de gekozen map. Schakel functies uit in zisla of trek toestemming in via Systeeminstellingen → Privacy en beveiliging.</p>',
      },
      localVoice: {
        question: 'Hoe gebruik ik een lokaal model om spraaktranscripties te corrigeren?',
        answer: `
      <p>Ollama, LM Studio en andere lokale OpenAI-compatibele diensten worden ondersteund.</p>
      <ol>
        <li>Download of laad het gewenste model in je lokale model-app en start de dienst.</li>
        <li>Open Instellingen → Spraak → Lokale modellen, voeg een configuratie toe en schakel die in. Kies Ollama of LM Studio en vul de URL van de dienst in. Kies ook voor andere OpenAI-compatibele diensten LM Studio. Laat API Key leeg als de dienst geen authenticatie vereist.</li>
        <li>Selecteer een automatisch gevonden model en kies die configuratie onder Spraakorganisatiemodel → Gebruik model.</li>
      </ol>
      <p>zisla stelt een Gemma 4 QAT-model voor op basis van je chip en het totale werkgeheugen. Het aanbevolen model wordt niet automatisch gedownload of geladen.</p>
    `.trim(),
      },
      network: { question: 'Gaat zisla online?', answer: 'Weer, ondertekende updatecontroles, downloads die je start en optionele externe spraakbewerking gebruiken indien nodig het netwerk. Linkherkenning gebeurt lokaal. Een lokaal model corrigeert de tekst na de transcriptie; de spraakherkenning van Apple kan nog steeds het netwerk gebruiken, afhankelijk van de taal en de systeemondersteuning.' },
      multiDisplay: { question: 'Ondersteunt zisla meerdere schermen?', answer: 'Ja: meerdere schermen, Spaces en gewone apps op volledig scherm; uitklappen neemt nooit de focus.' },
      intel: { question: 'Kan ik zisla op een Intel-Mac gebruiken?', answer: 'Er kan een Intel-build bestaan, maar compatibiliteit is niet gegarandeerd. De huidige ondersteunde configuratie is Apple Silicon.' },
      storage: { question: 'Waar slaat zisla gegevens op?', answer: 'Lokale gegevens staan in ~/Library/Application Support/zisla/. Typestatistieken staan apart in ~/Library/Application Support/zisla/typing-stats.sqlite3. Snelle notities gebruikt de systeemapp Notities. Instellingen → Opslaglocatie biedt aparte mappen voor downloads, schermafbeeldingen, opnamen, snelle acties en dagoverzichten. Na een update behouden ze de oude gedeelde map; daarna kun je ze afzonderlijk wijzigen.' },
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
  film: {
    title: "Productvideo",
    videoAriaLabel: "Productvideo van zisla",
    openVideoLabel: "Video openen",
    playbackError: "De video kan niet worden afgespeeld.",
    musicLabel: "Muziek",
    excerptLabel: "Fragment",
  },
  footer: {
    brandHomeAriaLabel: 'Terug naar de zisla-home',
    previewChannelLabel: 'Previewkanaal',
    tagline: 'Open source, native en onder jouw controle.',
  },
  common: { copyCommandTitle: 'Opdracht kopiëren', copiedAriaLabel: 'Gekopieerd' },
  toast: { runCommandCopied: 'Startopdracht gekopieerd', zislactlCopied: 'zislactl-opdracht gekopieerd', brewCommandCopied: 'Homebrew-installatieopdracht gekopieerd' },
});
