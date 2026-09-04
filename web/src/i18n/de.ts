import type { SiteContent } from '../content';

export const de: SiteContent = {
  meta: {
    documentTitle: 'zisla · Dynamischer Arbeitsbereich',
    description:
      'zisla ist ein nativer dynamischer Arbeitsbereich für macOS. Behalte KI-Aufgaben wie Zed Agent, Medien, Dateien und Termine an einem Ort – mit Tastaturklängen, Tippstatistik, Bildschirmfoto-Anmerkungen und Kopierassistent.',
    ogTitle: 'zisla · Bring das Aktuelle dorthin, wo du es siehst',
    ogDescription:
      'Von KI-Aufgaben wie Zed Agent und Medienwiedergabe bis zu Tastaturklängen, Tippstatistik, Kopierassistent, Bildschirmfoto-Anmerkungen und Schreibtisch-Werkzeugen: ein nativer macOS-Arbeitsbereich, der nur erscheint, wenn du ihn brauchst.',
  },
  tagline: 'Nativer dynamischer Arbeitsbereich für macOS',
  header: {
    navAriaLabel: 'Hauptnavigation',
    brandHomeAriaLabel: 'zisla Startseite',
    menuOpenLabel: 'Navigationsmenü öffnen',
    menuCloseLabel: 'Navigation schließen',
    menuButtonTitle: 'Navigation öffnen',
    navItems: {
      showcase: 'Funktionen',
      ai: 'KI-Ablauf',
      download: 'Download',
      faq: 'FAQ',
      developers: 'Entwickler',
    },
    downloadCta: 'Laden',
    downloadCtaAriaLabel: 'Zum Download-Abschnitt springen',
    languageLabel: 'Sprache der Oberfläche',
  },
  hero: {
    eyebrow: 'NATIVER MACOS-ARBEITSBEREICH',
    title: 'zisla<br><em>Was gerade<br>passiert, dort,<br>wo du es siehst.</em>',
    lede: 'Sammle KI-Aufgaben, Medien, Dateien und Termine am oberen Bildschirmrand. Nach dem Kopieren zeigt eine eigene Assistentenleiste dort oben eine Vorschau und schlägt den nächsten Schritt vor. Sie erscheint bei Bedarf und tritt danach zurück.',
    downloadCta: 'Laden',
    downloadCtaAriaLabel: 'Laden',
    sourceCta: 'Quellcode ansehen',
    sourceCtaAriaLabel: 'Den Quellcode von zisla auf GitHub ansehen',
    hints: [
      'Zeiger nach oben bewegen – ohne Klick öffnet sich alles',
      'Nach dem Kopieren führt Command+N den nächsten Schritt aus',
      'Klappt von selbst zu und unterbricht die Arbeit nicht',
    ],
    identityCaption: 'Oberer Bildschirmrand',
  },
  proof: {
    ariaLabel: 'Produktübersicht',
    items: {
      modules: { title: '{count} Module oben', desc: 'Nur die Abläufe, die du brauchst' },
      os: { title: 'macOS 14+', desc: 'Ein natives Desktop-Erlebnis' },
      displays: { title: 'Mehrere Displays', desc: 'Mit Notch und an externen Bildschirmen' },
      local: { title: 'Lokal zuerst', desc: 'Der KI-Status liest keine Gespräche' },
    },
  },
  showcase: {
    eyebrow: 'EIN EINSTIEG / ABLÄUFE DES ALLTAGS',
    title: 'Alltägliche Abläufe, <span>oben am Bildschirm geparkt.</span>',
    lede: 'Von KI-Aufgaben über die Zwischenablage bis zu Terminen und Systemstatus: zisla bündelt verstreute Schreibtisch-Abläufe an einem Einstiegspunkt.',
    ariaLabel: 'Funktionsübersicht von zisla',
    summaryMono: '{modules} MODULE / {groups} KATEGORIEN',
    summaryLede:
      'Von den Abläufen oben am Bildschirm bis zu lokalen Werkzeugen: hier steht Punkt für Punkt, was sich wirklich erledigen lässt.',
    summaryNote:
      '{modules} Module oben am Bildschirm und {features} eigenständige Funktionen für Bildschirmfotos, Sprache, Medien, Downloads, Kopierassistent, KI-Verwaltung, Maskottchen und Sperrbildschirm.',
    groupNames: {
      island: 'Abläufe oben am Bildschirm',
      ai: 'KI-Ablauf',
      daily: 'Alltägliche Informationen',
      tools: 'Werkzeuge',
    },
    groupCount: '{count} Module',
    pointsAriaLabel: 'Kernpunkte von {name}',
    modules: {
      dashboard: {
        name: 'Start',
        caption:
          'Live-Karten erscheinen nur, solange eine Fokuszeit, eine KI-Aufgabe oder ein Download läuft – ohne Aktivität nimmt nichts zusätzlichen Platz ein.',
        points: ['Erscheint bei Bedarf', 'Fortschritt in Echtzeit', 'Layout passt sich selbst an'],
      },
      shelf: {
        name: 'Ablage',
        caption:
          'Zieh Dateien, Audio, Video oder Links auf den Auslösestreifen am oberen Bildschirmrand, um sie in der Ablage zu parken, im Finder anzuzeigen oder das Teilen-Menü von macOS zu öffnen.',
        points: ['Nach oben ziehen und parken', 'Im Finder anzeigen', 'Teilen-Menü des Systems'],
      },
      clipboard: {
        name: 'Zwischenablage',
        caption:
          'Sieh den Verlauf der Zwischenablage in der Dynamic Island und filtere nach Bild, URL, Pfad und Dateityp. Einträge lassen sich an die Kurznotizen senden, als Favorit anheften oder löschen.',
        points: ['Verlauf in der Island', 'Filter nach Typ', 'Kurznotizen und Favoriten'],
      },
      aiMonitor: {
        name: 'KI-Überblick',
        caption:
          'Erkennt automatisch Aktivität unterstützter KI-CLIs, Desktop-Apps und IDEs – Zed-Agent-Threads eingeschlossen – und zeigt Aufgaben, Status, den Verlauf verbrauchter Tokens und eine Beitrags-Heatmap. Ausgewertet werden nur strukturierte Ereignisse, niemals Gesprächstext.',
        points: [
          'Aufgaben aus mehreren Werkzeugen',
          'Verlauf des Token-Verbrauchs',
          'Liest keine Prompts und Antworten',
        ],
      },
      keyboardSound: {
        name: 'Tastaturklänge',
        caption:
          'Spielt zu jedem Tastendruck eine von 20 integrierten Klangfarben mechanischer Tastaturen, mit regelbarer Lautstärke und natürlicher Tonhöhenstreuung sowie Loslassgeräusch, wo die Klangfarbe es vorsieht. Mit aktivierter lokaler Tippstatistik siehst du in der Island die Tagesübersicht, Verläufe, Historie, eine Zeitleiste je App und eine Heatmap je Taste inklusive F1-F12.',
        points: [
          '20 integrierte Klangfarben',
          'Loslassgeräusch und Tonhöhenstreuung',
          'Tippstatistik optional',
        ],
      },
      download: {
        name: 'Downloader',
        caption:
          'Füge einen Link ein oder lass zisla nach dem Aktivieren Links aus der Zwischenablage erkennen. Wähle Video oder Audio und speichere in den Standardordner oder einen eigenen. Bei gängigen Videoplattformen und weiteren unterstützten Links erscheinen Quellsymbol, Fortschritt in Echtzeit und der Abschlussstatus.',
        points: [
          'Video- / Audiomodus',
          'Standard- oder eigener Ordner',
          'Quellsymbol und Fortschritt',
        ],
      },
      agenda: {
        name: 'Termine und Wetter',
        caption:
          'Zeigt das Wetter am aktuellen Standort und an bis zu sechs selbst gewählten Orten. Kalendertermine und Erinnerungen lassen sich ansehen, hinzufügen und löschen, Erinnerungen zusätzlich als erledigt markieren.',
        points: ['Wetterkarten für mehrere Orte', 'Kalender und Aufgaben', 'Erinnerung sofort erledigt'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Liest die in Mail aktivierten Accounts. In der Island kannst du den Eingang ansehen, als gelesen markieren, antworten, neue Nachrichten verfassen und in den Papierkorb legen – mit klarem Hinweis, sobald eine Berechtigung fehlt.',
        points: ['Accounts aus Mail', 'Antworten und verfassen', 'Nachvollziehbare Hinweise'],
      },
      quickNotes: {
        name: 'Kurznotizen',
        caption:
          'Basiert auf der System-App Notizen: Notizen ansehen, bearbeiten, neu anlegen und löschen, mit Markdown-Vorschau in Echtzeit. Entwürfe werden automatisch nach Notizen zurückgeschrieben.',
        points: ['Daten liegen in Notizen', 'Markdown-Editor', 'Entwürfe automatisch gesichert'],
      },
      pdf: {
        name: 'PDF-Werkzeuge',
        caption:
          'Vierzehn Vorgänge, die vollständig auf deinem Mac laufen: zusammenführen, aufteilen, drehen, beschneiden, Bilder und Office-Dateien umwandeln, in Bilder umwandeln, Text exportieren, Text- oder Bildwasserzeichen setzen, Seitenzahlen ergänzen, verschlüsseln, Passwort entfernen und Metadaten bearbeiten.',
        points: ['14 lokale Werkzeuge', 'Reihenfolge selbst bestimmen', 'Nichts verlässt den Mac'],
      },
      toolbox: {
        name: 'Kleine Werkzeuge',
        caption:
          'Fokus-Timer, Display wach halten, Bildschirmreinigung, Tastaturreinigung (blockiert währenddessen Tastendrücke einschließlich F1-F12), Weckzeiten, Teleprompter, Spiegel und Papierkorb auf einer Seite.',
        points: [
          'Fokus-Timer',
          'Blockiert F1-F12 beim Reinigen',
          'Teleprompter und Spiegel',
        ],
      },
      system: {
        name: 'Systemstatus',
        caption:
          'Sieh den Status von CPU, GPU, Speicher, Datenträger, Netzwerk und Lüftern, lies die NVMe-SMART-Temperatur, wo die Hardware sie meldet, und räume Caches und Protokolle auf, die sicher gelöscht werden können.',
        points: [
          'Überwachung bis zum Chip',
          'NVMe-Temperatur, wo unterstützt',
          'Caches in einem Schritt leeren',
        ],
      },
      battery: {
        name: 'Batterie',
        caption:
          'Sieh detaillierte Werte dieses Mac – Ladung, Zustand, Ladezyklen, Temperatur und Kapazität – und dazu den Ladestand nahegelegener Geräte, soweit das System ihn bereitstellt.',
        points: ['Zustandswerte des Mac', 'Restlaufzeit', 'Ladestand nahegelegener Geräte'],
      },
    },
  },
  extensions: {
    eyebrow: 'IN DER ISLAND UND DANEBEN',
    title: 'Auch abseits der Island <span>ein Werkzeug für den Schreibtisch.</span>',
    lede: 'Bildschirmfotos, Sprache, Medien, Browser-Downloads und KI-Verwaltung erscheinen dort, wo sie am schnellsten zur Hand sind.',
    ariaLabel: 'Eigenständige Schreibtisch-Funktionen',
    summaryMono: 'JENSEITS DER ISLAND',
    summaryLede: 'Häufig genutzte Funktionen, jede an ihrem natürlichen Platz.',
    summaryNote:
      'Bildschirmfotos, Aufnahme, Medien, Browser-Downloads, Kopierassistent, KI-Verwaltung, Maskottchen und Sperrbildschirm arbeiten jeweils eigenständig.',
    features: {
      capture: {
        title: 'Bildschirmfotos, Scroll-Aufnahmen und Anheften',
        description:
          'Nimm mit einem globalen Kürzel einen Bildschirmausschnitt auf oder hefte ihn an, setze anschließend Anmerkungen, füge Scroll-Aufnahmen zusammen und erkenne oder exportiere Tabellen. Textanmerkungen, die du noch bearbeitest, bleiben beim Export erhalten.',
        detail: 'Globales Kürzel · Anmerken und widerrufen · Änderungen bleiben beim Export',
      },
      voice: {
        title: 'Spracheingabe und Aufbereitung',
        description:
          'Mit einer Taste umschalten oder zum Sprechen halten, mit der Spracherkennung des Systems. Bei Bedarf kommen Fachwortlisten, eigene Schlüsselwörter, ein strukturiertes Format oder die Aufbereitung durch ein lokales oder entferntes Modell hinzu.',
        detail: 'Zwei Aufnahmearten · Wortlisten und Schlüsselwörter · Modell optional',
      },
      media: {
        title: 'Medien und Systemklänge',
        description:
          'Steuere die laufende Wiedergabe oben in der Island oder wähle einen Hintergrundklang von macOS. Beim Sperren, beim Bildschirmschoner oder im Ruhezustand des Displays kann er sich automatisch beenden.',
        detail: 'Wiedergabesteuerung · Songtexte synchron · Klang endet automatisch',
      },
      browserDownloads: {
        title: 'Fortschritt von Browser-Downloads',
        description:
          'Erkennt Downloads in Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera und Arc und zeigt Quelle und Fortschritt in Echtzeit am oberen Bildschirmrand.',
        detail: '8 Browser · Quelle erkannt · Hinweis bei Abschluss',
      },
      copyAssistant: {
        title: 'Kopierassistent und nächste Schritte',
        description:
          'Nach dem Aktivieren erscheinen kopierter Text, Links, Dateien oder Bilder in einer eigenen Leiste am oberen Bildschirmrand – mit passenden nächsten Schritten wie öffnen, im Finder anzeigen, suchen, übersetzen, rechnen oder speichern, ausgeführt erst nach deiner Bestätigung.',
        detail: 'Optional aktivierbar · Erkennung lokal · Standard Command+N',
      },
      aiManagement: {
        title: 'KI-CLIs und Skills verwalten',
        description:
          'Erkenne, installiere, aktualisiere und entferne verbreitete KI-CLIs in den Einstellungen und sieh und verwalte lokale Skills – so wechselst du seltener zwischen Terminals und Werkzeugen.',
        detail: 'Erkennen und installieren · Aktualisieren und entfernen · Lokale Skills',
      },
      pet: {
        title: 'Maskottchen in der Island',
        description:
          'Wähle ein integriertes Maskottchen und stelle es links oder rechts an der Island auf. Du kannst es jederzeit abschalten.',
        detail: 'Integrierte Figuren · Links oder rechts · Nur bei Bedarf',
      },
      lockScreen: {
        title: 'Informationen im Sperrbildschirm',
        description:
          'Zeig bei Bedarf Datum, Status und laufende Wiedergabe im Sperrbildschirm von macOS. Es ist ein eigenes Overlay und erscheint nie in der Modulliste oder im Karussell der Island.',
        detail: 'Eigenes Overlay · Selbst aktivieren · Nimmt keinen Fokus',
      },
    },
  },
  ai: {
    eyebrow: 'KI OHNE BLACKBOX',
    title: 'KI-Status sehen, <span>ohne das Gespräch zu lesen.</span>',
    lede: 'Aufgaben, Status und Token-Verläufe bleiben auf deinem Mac. Diese Seite beschreibt die Funktion und erfindet kein Bild einer laufenden Aufgabe.',
    summaryMono: 'LOKALER STATUS / KLARE GRENZEN',
    summaryLede:
      'Verbinde die KI-Werkzeuge, die du schon nutzt, und behalte die Kontextgrenzen, die deine Arbeit braucht.',
    summaryNote:
      'Diese Seite beschreibt nur Erkennungsumfang, Datengrenze und Anbindung – sie simuliert keine laufende Sitzung.',
    toolsHeading: 'Unterstützte KI-Werkzeuge',
    toolsLede:
      'Erkennt Aktivität unterstützter CLIs, Desktop-Apps und IDEs und bündelt den Aufgabenstatus.',
    toolsAriaLabel: 'Unterstützte KI-Werkzeuge',
    doubaoName: 'Doubao',
    boundariesHeading: 'Aufgezeichnet werden nur Statusgrenzen',
    privacyPoints: [
      'Wertet aus strukturierten Ereignissen nur Ereignistyp, Status, Zeit, Modell und Sitzungs-ID aus',
      'Liest weder Prompt- noch Antworttext',
      'Protokoll und Status bleiben auf deinem Mac',
    ],
    bridgeHeading: 'Eigene Aufgaben anbinden',
    bridgeLede:
      'Mit zislactl schickst du den strukturierten Status externer Aufgaben in die Statusleiste oben.',
    zislactlTaskTitle: 'Build und Release',
    copyZislactlAriaLabel: 'zislactl-Befehl kopieren',
  },
  flow: {
    eyebrow: 'RHYTHMUS DER BEDIENUNG',
    title: 'Nach oben, <span>hinsehen, wieder zuklappen.</span>',
    lede: 'Nimmt keinen Fokus und klappt nach dem Blick von selbst zu.',
    ariaLabel: 'Bedienrhythmus am oberen Bildschirmrand',
    summaryMono: 'STATUSLEISTE / 3 SCHRITTE',
    summaryLede: 'Öffnet sich bei Bedarf und zieht sich nach dem Lesen zurück.',
    summaryNote:
      'Ausgelöst durch die Zeigerposition. Ohne Inhalt nimmt sie keinen sichtbaren Platz ein und entzieht der aktiven App nie den Fokus.',
    steps: {
      trigger: {
        phase: 'Auslösen',
        title: 'Zeiger nach oben in die Mitte bewegen',
        desc: 'Displays mit Notch und externe Bildschirme nutzen dieselbe Bewegung, und im verborgenen Zustand läuft kein Frame-Loop.',
      },
      review: {
        phase: 'Ansehen',
        title: 'Den aktuellen Stand auf einen Blick',
        desc: 'Medien, Dateien, KI, Termine und Systemwerkzeuge liegen an derselben Stelle.',
      },
      dismiss: {
        phase: 'Zuklappen',
        title: 'Weiterarbeiten',
        desc: 'Zeiger weg – und sie klappt zu; beim Öffnen wird die App weder aktiviert noch der Fokus entzogen.',
      },
    },
  },
  download: {
    eyebrow: 'JEDERZEIT EINSATZBEREIT',
    title: 'zisla laden',
    copy: 'Für Macs mit Apple Silicon. Versionen, weitere Architekturen und Prüfsummen stehen auf der Release-Seite. Nach der Installation prüft zisla im gewählten Update-Kanal auf neue Versionen: Sparkle verifiziert zuerst die Signatur und lädt, installiert und startet dann je nach Einstellung manuell oder automatisch neu.',
    primaryCta: 'Laden',
    primaryCtaAriaLabel: 'Laden',
    releaseCta: 'Release ansehen',
    releaseCtaAriaLabel: 'Details des Release auf GitHub ansehen',
    notes: {
      system: {
        term: 'System',
        value: 'macOS 14 oder neuer · unterstützte Konfiguration sind derzeit Macs mit Apple Silicon',
      },
      install: { term: 'Installation', value: 'DMG öffnen und in „Programme“ ziehen' },
      package: { term: 'Paket', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Weitere Architekturen', value: 'Release-Seite' },
      mirror: { term: 'Spiegel', value: 'Gitee Releases' },
    },
  },
  faq: {
    eyebrow: 'EIN PAAR KLARE ANTWORTEN',
    title: 'Häufige Fragen.',
    lede: 'Berechtigungen, Datenschutz und Kompatibilität.',
    items: {
      audience: {
        question: 'Für wen ist zisla gedacht?',
        answer:
          'Für Mac-Nutzer, die KI, Medien, Dateien und Termine an einem Ort sehen wollen. Displays ohne Notch werden ebenfalls unterstützt.',
      },
      aiPrivacy: {
        question: 'Liest zisla meine KI-Gespräche?',
        answer:
          'Nein. Die KI-Statusüberwachung liest nur den Aufgabenstatus, niemals Prompt- oder Antworttext.',
      },
      copyAssistant: {
        question: 'Öffnet oder überträgt der Kopierassistent, was ich kopiere?',
        answer:
          'Nein. Nach dem Aktivieren laufen Erkennung und Vorschau vollständig auf deinem Mac, und zisla führt einen nächsten Schritt erst aus, wenn du ihn anklickst oder das Kürzel drückst.',
      },
      permissions: {
        question: 'Welche Systemberechtigungen braucht zisla?',
        answer: `
      <p>zisla fragt beim ersten Start nicht alle Berechtigungen auf einmal ab. macOS zeigt jede Abfrage erst, wenn du die zugehörige Funktion aktivierst und tatsächlich nutzt:</p>
      <ul>
        <li><strong>Kalender und Erinnerungen:</strong> werden beim Öffnen des Terminmoduls einzeln abgefragt, um Kalendertermine und datierte Erinnerungen zu lesen, zu erstellen und zu verwalten.</li>
        <li><strong>Ortungsdienste:</strong> werden abgefragt, wenn du beim Wetter den aktuellen Standort wählst. zisla ermittelt den Standort einmalig und verfolgt dich nicht dauerhaft. Städte von Hand hinzuzufügen braucht keine Ortung.</li>
        <li><strong>Mikrofon und Spracherkennung:</strong> werden beim Start der Spracheingabe abgefragt. Ton wird nur während der laufenden Aufnahme erfasst, und nur diese Aufnahme wird transkribiert.</li>
        <li><strong>Bedienungshilfen:</strong> nötig, um ein Transkript automatisch in die aktive App einzusetzen, für das schnelle Kopieren per Mausgeste, für die Tastaturreinigung und für die Steuerung einiger unterstützter Player. Sie dienen dazu, Eingabefelder ohne Passwortschutz zu finden oder die erforderlichen Systemtasten zu senden.</li>
        <li><strong>Eingabeüberwachung:</strong> wird für Tastaturklänge, die optionale lokale Tippstatistik und globale Auslöser wie eine einzelne Sondertaste oder eine Maus-Seitentaste genutzt. Beobachtet werden nur die globalen Ereignisse, die diese Funktionen benötigen – gewöhnliche globale Kürzel brauchen sie nicht.</li>
        <li><strong>Bildschirmaufnahme und Systemaudioaufnahme:</strong> nötig für Bildschirmfotos, deren Bearbeitung und die Wellenform der Systemwiedergabe. Bildschirmfotos lesen das Bildschirmbild; die Wellenform wertet nur den aktuellen Systemton-Pegel aus und speichert oder überträgt keine Audioinhalte.</li>
        <li><strong>Kamera:</strong> wird nur genutzt, solange das Spiegelfenster geöffnet ist.</li>
        <li><strong>Bluetooth:</strong> wird nur genutzt, solange das Batteriemodul geöffnet ist, um den von verbundenen oder gekoppelten Geräten veröffentlichten Ladestand zu lesen.</li>
        <li><strong>Automation:</strong> bei der ersten Nutzung von Kurznotizen, Mail, Schreibtisch-Aufräumen oder direkter Steuerung eines unterstützten Players fragt macOS einzeln, ob zisla Notizen, Mail, den Finder oder die jeweilige App steuern darf. Kurznotizen lesen und schreiben in Notizen; Mail kann Nachrichten lesen, verfassen, beantworten, markieren und löschen.</li>
        <li><strong>Festplattenvollzugriff:</strong> nur nötig, wenn Mail nicht läuft und zisla dennoch den lokalen Mail-Index lesen soll, um Accounts, Absender, Betreff, Auszug, Zeit und Lesestatus anzuzeigen.</li>
        <li><strong>Mitteilungen:</strong> werden beim Aktivieren von Pomodoro-Timer oder Weckzeiten abgefragt und nur genutzt, um eine lokale Mitteilung anzuzeigen, wenn ein Timer endet oder eine Weckzeit fällig ist.</li>
      </ul>
      <p><strong>Ein Ordner ist kein Festplattenvollzugriff:</strong> Für Ablage-, Import-/Export- oder Downloadordner, die du im Dateiauswahl-Dialog des Systems bestimmst, erhält zisla nur Zugriff auf diesen Ordner, nie Leserechte für den gesamten Datenträger.</p>
      <p><strong>Tastaturklänge und Tippstatistik:</strong> Beide sind standardmäßig aus, und globale Tastaturereignisse werden erst beobachtet, sobald eine davon an ist. Bei Tastaturklängen dienen Tastenereignisse allein der Klangausgabe; bei der Tippstatistik werden nur aggregierte Daten gespeichert – Zeichenanzahl, physische Tastencodes, Zeit und vorderste App – niemals der Inhalt. Du kannst beide getrennt in den Einstellungen abschalten, danach wird nichts mehr aufgezeichnet. Bereits gespeicherte Daten bleiben in einer lokalen Datenbankdatei, die du selbst löschen kannst.</p>
      <p>Du kannst die jeweilige Funktion in den Einstellungen der App abschalten oder eine Berechtigung jederzeit unter „Systemeinstellungen → Datenschutz &amp; Sicherheit“ widerrufen. Widerrufst du eine, wird nur die zugehörige Funktion deaktiviert; andere Module bleiben unberührt. Die Bezeichnungen unterscheiden sich je nach macOS-Version leicht.</p>
    `.trim(),
      },
      network: {
        question: 'Geht zisla ins Netz?',
        answer:
          'Wetter, signierte Update-Prüfungen, von dir gestartete Downloads und die optionale entfernte Sprachaufbereitung nutzen das Netz nach Bedarf. Die Linkerkennung in der Zwischenablage läuft rein lokal und startet nie selbst einen Download.',
      },
      multiDisplay: {
        question: 'Unterstützt zisla mehrere Displays?',
        answer:
          'Ja – mehrere Displays, Spaces und gewöhnliche Vollbild-Apps, und das Öffnen nimmt nie den Fokus.',
      },
      intel: {
        question: 'Läuft es auf einem Intel-Mac?',
        answer:
          'Für Intel-Rechner kann ein Build verfügbar sein, die Kompatibilität ist aber nicht garantiert. Unterstützte Konfiguration sind derzeit Macs mit Apple Silicon.',
      },
      storage: {
        question: 'Wo speichert zisla seine Daten?',
        answer:
          'Lokale Daten liegen in ~/Library/Application Support/zisla/. Die Tippstatistik wird getrennt in ~/Library/Application Support/SimuBoard/typing-stats.sqlite3 gespeichert. Kurznotizen nutzen die System-App Notizen.',
      },
    },
  },
  developers: {
    eyebrow: 'STANDARDMÄSSIG OPEN SOURCE',
    title: 'Ressourcen für Entwickler.',
    lede: 'MIT-Lizenz: direkt nutzen oder aus dem Quellcode bauen.',
    docs: {
      macos: {
        title: 'macOS-Entwicklungsleitfaden',
        description: 'Funktionen, Build, Tests und Systemgrenzen',
      },
      architecture: {
        title: 'Architektur und Leistung',
        description: 'Auslösen am oberen Rand, Fenster und Leistung',
      },
      cli: { title: 'CLI-Anbindung', description: 'Befehle und Felder von zislactl' },
      releasing: {
        title: 'Signatur und Release',
        description: 'Signatur, Notarisierung und Release-Ablauf',
      },
      contributing: {
        title: 'Leitfaden für Beiträge',
        description: 'Umgebung, Branches, Commits und Anforderungen an Pull Requests',
      },
    },
    quickStartMono: 'SCHNELLSTART / QUELLCODE',
    quickStartHeading: 'Aus dem Quellcode starten oder eigene Aufgaben anbinden.',
    copyRunCommandAriaLabel: 'Befehl zum Start aus dem Quellcode kopieren',
    githubRepoLabel: 'GitHub-Repository',
    giteeRepoLabel: 'Gitee-Repository',
    checksumLabel: 'SHA-256',
    performancePoints: [
      'Unterstützt mehrere Displays, Spaces und gewöhnliche Vollbild-Apps; beim Öffnen wird die App weder aktiviert noch der Fokus entzogen',
      'Im verborgenen Zustand entsteht kein dauerhaftes transparentes Hotzone-Fenster und es läuft kein Frame-Loop; geöffnet wird über globale Ereignisbeobachtung und Geometrieprüfung',
      'Nutzt eine einzige Schicht Systemmaterial und wechselt bei aktiviertem „Transparenz reduzieren“ automatisch auf einen deckenden Hintergrund',
      'Liquid Glass ab macOS 26, mit automatischem Rückfall auf native Systemmaterialien unter macOS 14 und 15',
      'Eine physische Notch wird aus dem Sicherheitsbereich des Systems abgeleitet; externe Displays ohne Notch erhalten eine simulierte Statusleiste in einem eigenen Overlay',
    ],
  },
  footer: {
    brandHomeAriaLabel: 'Zurück zur Startseite von zisla',
    previewChannelLabel: 'Preview-Kanal',
    tagline: 'Open Source, nativ – und in deiner Hand.',
  },
  common: {
    copyCommandTitle: 'Befehl kopieren',
    copiedAriaLabel: 'Kopiert',
  },
  toast: {
    runCommandCopied: 'Befehl zum Start aus dem Quellcode kopiert',
    zislactlCopied: 'zislactl-Befehl kopiert',
  },
};
