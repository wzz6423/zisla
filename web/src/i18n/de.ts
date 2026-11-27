import type { SiteContent } from '../content';

export const de: SiteContent = {
  meta: {
    documentTitle: 'zisla · Dynamischer Arbeitsbereich',
    description:
      'zisla ist ein nativer macOS-Arbeitsbereich für KI-Aufgaben, Tagesberichte und Aufnahmen, mit eigenen Tieren, Screenshots und zentralen Berechtigungen.',
    ogTitle: 'zisla · Bring das Aktuelle dorthin, wo du es siehst',
    ogDescription:
      'Behalten Sie KI-Aufgaben und Ihren Tag im Blick, nehmen Sie auf dem Mac auf, bearbeiten Sie Videos, importieren Sie Tiere und verwalten Sie Berechtigungen zentral.',
  },
  tagline: 'Nativer dynamischer Arbeitsbereich für macOS',
  header: {
    navAriaLabel: 'Hauptnavigation',
    brandHomeAriaLabel: 'zisla Startseite',
    menuOpenLabel: 'Navigationsmenü öffnen',
    menuCloseLabel: 'Navigation schließen',
    menuButtonTitle: 'Navigation öffnen',
    navItems: {
      help: "Hilfe",
      showcase: 'Funktionen',
      ai: 'KI-Ablauf',
      download: 'Download',
      changelog: 'Änderungsprotokoll',
      faq: 'FAQ',
      developers: 'Entwickler',
    },
    downloadCta: 'Laden',
    downloadCtaAriaLabel: 'Zum Download-Abschnitt springen',
    languageLabel: 'Sprache der Oberfläche',
    themeLabel: 'Erscheinungsbild',
    themeModes: { auto: 'Automatisch (System)', light: 'Heller Modus', dark: 'Dunkler Modus' },
  },
  hero: {
    eyebrow: 'NATIVER MACOS-ARBEITSBEREICH',
    title: 'zisla<br><em>Was gerade<br>passiert, dort,<br>wo du es siehst.</em>',
    lede: 'Sammle KI-Aufgaben, Medien, Dateien und Termine am oberen Bildschirmrand. Nach dem Kopieren zeigt eine eigene Aktionsleiste dort oben eine Vorschau und schlägt den nächsten Schritt vor. Sie erscheint bei Bedarf und tritt danach zurück.',
    downloadCta: 'Laden',
    downloadCtaAriaLabel: 'Laden',
    sourceCta: 'Quellcode ansehen',
    sourceCtaAriaLabel: 'Den Quellcode von zisla auf GitHub ansehen',
    hints: [
      'Zeiger nach oben bewegen – ohne Klick öffnet sich alles',
      'Nach dem Kopieren führt Command+N den nächsten Schritt aus',
      'Klappt von selbst zu und unterbricht die Arbeit nicht',
    ],
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
      '{modules} Module am oberen Bildschirmrand und {features} eigenständige Funktionen: von Fenstervorschauen und Aufnahmen bis zur KI-Verwaltung und empfohlenen Apps.',
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
          'Live-Karten erscheinen nur, solange eine Fokuszeit, eine KI-Aufgabe oder ein Download läuft – ohne Aktivität nimmt nichts zusätzlichen Platz ein. Auf der Startseite werden laufende KI-Aufgaben nach Anwendung gruppiert.',
        points: ['Erscheint bei Bedarf', 'Fortschritt in Echtzeit', 'Layout passt sich selbst an'],
      },
      shelf: {
        name: 'Ablage',
        caption:
          "Dateien auf der Ablage suchen, auswählen und teilen. ZIP oder PDF erstellen, Bilder skalieren oder konvertieren und an Notizen oder das Studio senden.",
        points: ['Suche und Sammelaktionen', 'Bilder als PDF und Schnellnotizen', 'Videos im Studio bearbeiten'],
      },
      clipboard: {
        name: 'Zwischenablage',
        caption:
          "Durchsuche den lokalen Verlauf und Text in Bildern. Filtere nach Typ oder Quell-App, speichere Favoriten und sende Einträge an Schnellnotizen.",
        points: ['Verlauf in der Island', 'Filter nach Typ', 'Kurznotizen und Favoriten'],
      },
      aiMonitor: {
        name: 'KI-Überblick',
        caption:
          'Bündelt Aufgaben und Status aus KI-CLIs, Desktop-Apps und IDEs. Verlässliche Zahlen liefern Token-Verläufe und eine Beitrags-Heatmap; wählen Sie ein Datum für Eingabe-, Ausgabe- und Gesamttokens nach Anbieter und Modell. In den Einstellungen können Sie den Verlauf ansehen, vollständig als .xlsx exportieren oder löschen. Zeigt echte Kontingente, Rücksetzzeiten und Warnungen bei wenig Restkontingent, einschließlich 5h/7d-Fenstern und Cursor-Budgets in US-Dollar, soweit verfügbar. Prompt- und Antworttexte werden nicht gelesen. Auch die kompakten Ansichten zeigen verbleibende Kontingente als Ringe. Wählen Sie Kontoregionen unabhängig voneinander; tägliche Nutzungswerte und Farben des verbleibenden Kontingents stimmen in allen Ansichten überein.',
        points: ['Aufgaben aus mehreren KI-Werkzeugen', 'Modellverlauf und .xlsx-Export', 'Kontingente und Rücksetzzeiten'],
      },
      keyboardSound: {
        name: 'Tastaturklänge',
        caption:
          'Spielt zu jedem Tastendruck eine von 20 integrierten Klangfarben mechanischer Tastaturen, mit regelbarer Lautstärke und natürlicher Tonhöhenstreuung sowie Loslassgeräusch, wo die Klangfarbe es vorsieht. Mit aktivierter lokaler Tippstatistik siehst du in der Island die Tagesübersicht, Verläufe, Historie, eine Zeitleiste je App und eine Heatmap je Taste inklusive F1-F12. Sprachmengen, Diktierdauer, Geschwindigkeit und eingesparte Zeit erscheinen ebenfalls im Tastatur-Dashboard. Neue Konfigurationen aktivieren Klänge und Tippstatistik; beide lassen sich einzeln abschalten.',
        points: [
          '20 integrierte Klangfarben',
          'Loslassgeräusch und Tonhöhenstreuung',
          'Tippstatistik separat schaltbar',
        ],
      },
      download: {
        name: 'Downloader',
        caption:
          'Füge einen Link ein oder lass zisla nach dem Aktivieren Links aus der Zwischenablage erkennen. Wähle ein verfügbares Video- oder Audioformat und nutze Cookies eines installierten Browsers, wenn ein Douyin-Download sie benötigt. Speichere im Standardordner oder einem eigenen, mit Quellsymbol, Fortschritt in Echtzeit und Abschlussstatus. Wähle den Downloadordner unter Einstellungen → Speicherort unabhängig von Screenshots und Aufnahmen. Bilibili-Links laden den ausgewählten Videoteil. Verwalte Komponenten unter Einstellungen → Benötigte Komponenten und aktiviere bei Bedarf tägliche Updates für bereits installierte Komponenten.',
        points: [
          'Verfügbare Video- oder Audioformate wählen',
          'Browser-Cookies für Douyin',
          'Quellsymbol und Fortschritt',
        ],
      },
      agenda: {
        name: 'Termine und Wetter',
        caption:
          'Zeigt das Wetter am aktuellen Standort und an bis zu sechs gewählten Orten. Kalenderereignisse und Erinnerungen lassen sich ansehen, hinzufügen, löschen und abschließen. Ereignisse mit einem Besprechungslink zeigen ab 10 Minuten vor Beginn einen Countdown und erlauben den Beitritt per Klick. Erstellen Sie eine Besprechungsnotiz oder verknüpfen und lösen Sie vorhandene ortsbezogene Notizen.',
        points: ['Wetter und Kalender', 'Countdown 10 Minuten vorher', 'Beitreten und Notizen verknüpfen'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Liest die in Mail aktivierten Konten. Prüfen Sie den Posteingang, markieren Sie eine oder alle Posteingangsnachrichten als gelesen, antworten Sie, verfassen Sie Nachrichten oder verschieben Sie sie in den Papierkorb. Anhänge lassen sich beim Schreiben auswählen; fehlende Berechtigungen werden klar erklärt.',
        points: ['Accounts aus Mail', 'Antworten und verfassen', 'Nachvollziehbare Hinweise'],
      },
      quickNotes: {
        name: 'Kurznotizen',
        caption:
          'Basiert auf der System-App Notizen: Notizen ansehen, bearbeiten, neu anlegen und löschen, mit Markdown-Vorschau in Echtzeit – und mit Command+1 bis 9 direkt zu den ersten neun Notizen springen. Entwürfe werden automatisch nach Notizen zurückgeschrieben. Handschriftliche Anhänge lassen sich ansehen und der Text davor oder danach bearbeiten, während die Originale erhalten bleiben. Navigieren Sie mit Command und den Pfeiltasten zwischen Notizen. Eingefügter Text übernimmt die native Schrift des Fließtexts.',
        points: ['Daten liegen in Notizen', 'Markdown-Editor', 'Entwürfe automatisch gesichert'],
      },
      volumeMixer: {
        name: 'Lautstärkemixer für Apps',
        caption: 'Regeln Sie Lautstärke und Stummschaltung einzeln für Apps, die Audio abspielen. Erfordert macOS 14.4 oder neuer und die Berechtigung zur Aufnahme von Systemaudio. Lautstärkeeinstellungen bleiben je Anwendung gespeichert; veraltete Audioquellen verschwinden, wenn die Wiedergabe endet.',
        points: ['Lautstärke pro App', 'Einzeln stummschalten', 'macOS 14.4+'],
      },
      toolbox: {
        name: 'Kleine Werkzeuge',
        caption:
          'Fokustimer, Bildschirm wach halten, Bildschirmreinigung, Tastaturreinigung mit Sperre auch für F1-F12, Teleprompter, Spiegel und Papierkorb auf einer Seite. Den Pomodoro können Sie auch in der horizontalen und vertikalen Kompaktansicht pausieren, fortsetzen oder zurücksetzen und den Fortschritt verfolgen. Starten Sie die Bereinigung unnötiger Dateien in den Dienstprogrammen mit Ihren Systemeinstellungen und verfolgen Sie Fortschritt und Ergebnisse in der Insel.',
        points: [
          'Fokus-Timer',
          'Blockiert F1-F12 beim Reinigen',
          'Teleprompter und Spiegel',
        ],
      },
      system: {
        name: 'Systemstatus',
        caption:
          'Überwacht CPU, GPU, Arbeitsspeicher, Laufwerke, Netzwerk, Lüfter und verfügbare NVMe-SMART-Temperatur. Sehen Sie in den Einstellungen den minütlichen Verlauf für einen Zeitraum an, exportieren Sie .xlsx oder löschen Sie ihn. Prüfen Sie Batteriezustand, Zyklen, Temperatur, Kapazität, Geräte in der Nähe und öffentliche IPv4/IPv6. Wählen Sie automatische Energiemodi für Netz- und Batteriebetrieb, optional mit Stromsparmodus bei 20 % oder weniger. Laden Sie sofort auf 100 %, wenn macOS dies anbietet. Prüfen Sie Caches, Protokolle, Einstellungsreste und verwaiste KI-Arbeitsbereiche vor dem Verschieben in den Papierkorb; die Bereinigung kann alle 7, 15 oder 30 Tage laufen. Die geplante Bereinigung ist standardmäßig aus; wählen Sie nur vertrauenswürdige oder alle bearbeitbaren Elemente, auch solche mit Prüfbedarf. Führen Sie die Bereinigung im Hintergrund aus und sehen Sie Fortschritt und Ergebnis in der Insel. Finden Sie doppelte App-Installationen und Überreste von App-Updates.',
        points: [
          'Überwachung bis zum Chip',
          'Verlaufsdiagramme und .xlsx-Export',
          'Vor dem Verschieben in den Papierkorb prüfen',
        ],
      },
    },
  },
  extensions: {
    eyebrow: 'IN DER ISLAND UND DANEBEN',
    title: 'Auch abseits der Island <span>ein Werkzeug für den Schreibtisch.</span>',
    lede: 'Bildschirmfotos, Bild- und Audiowerkzeuge, Spracheingabe, Medien, Browser-Downloads und KI-Verwaltung erscheinen dort, wo sie leicht erreichbar sind.',
    ariaLabel: 'Eigenständige Schreibtisch-Funktionen',
    summaryMono: 'JENSEITS DER ISLAND',
    summaryLede: 'Häufig genutzte Funktionen, jede an ihrem natürlichen Platz.',
    summaryNote:
      'Fenstervorschauen, Aufnahmen und Schnellaktionen bleiben griffbereit; empfohlene Apps helfen dir, weitere Desktop-Werkzeuge zu entdecken.',
    features: {
      floatingIsland: {
        title: 'Eine schwebende Insel für Ihre Anordnung',
        description: 'Nutzen Sie die Kameraposition oder wählen Sie eine eigene Position an einem Bildschirmrand. Sie bleibt beim Moduswechsel gespeichert. Horizontale und vertikale Kompaktansichten passen ihre Länge an Statussymbole, KI-Aufgaben, Downloads und Medien an und können weitere Informationen anzeigen. Ordnen Sie die Module unter Einstellungen → Dynamic Island-Layout per Drag-and-drop neu oder stellen Sie die Standardreihenfolge wieder her. Auf derselben Seite können Sie die Priorität kompakter Statusinformationen ändern. Bei mehreren angeschlossenen Bildschirmen lässt sich unter Einstellungen → Allgemein → Bildschirmmodi für jeden Bildschirm der Dynamic Island-Modus (Kameraposition oder eigene Position), der Notch-Modus oder das Ausblenden wählen. Bei einem Bildschirm ist diese Einstellung verborgen und die globale Darstellung gilt; beim erneuten Anschließen werden die gespeicherten Einstellungen wiederhergestellt. Auf allen eingeblendeten Bildschirmen bleibt die eingeklappte Insel gleichzeitig sichtbar. Aufklappen, Schnellaktionen, Aufnahmen und vorübergehende Meldungen ersetzen nur die Insel auf dem jeweiligen Bildschirm; die Auswahl der Benachrichtigungsbildschirme filtert Inhalte, ohne die inaktive Insel auszublenden.',
        detail: 'Eigene Position · Dauerhafte Statussymbole · Anpassbare Informationen',
      },
      dailyBriefing: {
        title: 'Ihr Tag als Tagesbericht',
        description: "Wählen Sie aus acht Vorlagen und bestimmen Sie Nutzungs-, Tipp-, System- und zisla-Aktivitätsdaten. Prüfen Sie die Vorschau und exportieren Sie ein PNG manuell oder täglich zur gewählten Zeit. Der Bildschirmzeitverlauf wird nur bei Aktivierung und Verfügbarkeit verwendet. Wählen Sie einen eigenen Exportordner unter Einstellungen → Speicherort. Echte Kontingente der Konten und die Zeit ihrer Abfrage lassen sich ebenfalls aufnehmen.",
        detail: '8 Vorlagen · Inhalte wählen · Vorschau und geplanter PNG-Export',
      },
      userCare: {
        title: 'Erinnerungen während der Arbeit',
        description: 'Stellen Sie das Intervall für Pausen, Trinken, Bewegung und Augenruhe ein. Meldungen berücksichtigen die Tageszeit. Natürliche Pausen, Sperren und Ruhezustand setzen die Zeitmessung zurück. Fokusabschluss und Notizaktionen können kurze Rückmeldungen zeigen. In den Einstellungen aktivierbar.',
        detail: 'Einstellbares Intervall · Tageszeitbezogene Meldungen · Beachtet Inaktivität und Ruhe',
      },
      contextNotes: {
        title: 'Notizen am passenden Ort',
        description: 'Speichern Sie eine bearbeitbare Notiz zu einer Webseite, einem App-Fenster oder dem Schreibtisch und sehen Sie sie bei der Rückkehr. Hängen Sie Fensterbilder an, verwalten Sie Notizen in der Ablage und setzen Sie wiederkehrende Erinnerungen von einer Stunde bis drei Tagen oder schalten Sie sie aus.',
        detail: 'Ortsbezogene Notizen · Fensterbilder · Wiederkehrende Erinnerungen',
      },
      recording: {
        title: 'Aufnehmen und bearbeiten im Studio',
        description: "Bildschirm, Fenster oder Bereich aufnehmen, Spuren, Untertitel und Bild-/Stimmeffekte bearbeiten und exportieren. Mit HDR auf unterstützten Geräten und Medienimport aus der Ablage.",
        detail: 'Porträt- und Stimmeffekte · Farbige Cursorspuren · Mehrspurwiedergabe und Export',
      },
      permissions: {
        title: 'Systemberechtigungen an einem Ort',
        description: "Prüfen Sie den Status unter Einstellungen → Berechtigungen, starten Sie unterstützte Anfragen oder öffnen Sie die zuständige Systemseite. Nach erteilter Freigabe wird der Berechtigungsstatus aktualisiert. Eine Ziehhilfe erleichtert das Hinzufügen der Anwendung bei entsprechenden Berechtigungen.",
        detail: "Berechtigungsstatus · Anfragen und Links",
      },
      imageTools: {
        title: 'Bildwerkzeuge',
        description: 'Neun lokale Werkzeuge in den Einstellungen: Komprimieren; PNG, JPEG, WebP, AVIF und JPEG XL umwandeln; Skalieren und Zuschneiden; das kleinste Format vergleichen; Drehen und Spiegeln; Wasserzeichen; Mosaik und Weichzeichnen; Text- und Tabellenerkennung; Freistellen. Exportieren Sie Stapel oder ZIP-Dateien mit eigenem Bildordner unter Einstellungen → Speicherort.',
        detail: '9 lokale Werkzeuge · Fünf Formate · Stapel- und ZIP-Export',
      },
      audioTools: {
        title: 'Audiowerkzeuge',
        description: '27 lokale Vorgänge in den Einstellungen, etwa Umwandeln, Komprimieren, Schneiden, Aufteilen, Verbinden und Mischen, Audio aus Videos extrahieren, LUFS-Normalisierung, Blenden, Tempo und Tonhöhe, Rausch- und Stilleentfernung, EQ, Dynamik, Kanäle und Tags. FFmpeg und ffprobe sind erforderlich; wählen Sie eine Datei oder einen Ordner für den Export.',
        detail: '27 lokale Vorgänge · Bearbeiten und Mischen · FFmpeg und ffprobe',
      },
      pdf: {
        title: 'PDF-Werkzeuge',
        description: "In den Einstellungen verfügbar. Vierzehn Vorgänge, die vollständig auf deinem Mac laufen: zusammenführen, aufteilen, drehen, beschneiden, Bilder und Office-Dateien umwandeln, in Bilder umwandeln, Text exportieren, Text- oder Bildwasserzeichen setzen, Seitenzahlen ergänzen, verschlüsseln, Passwort entfernen und Metadaten bearbeiten.",
        detail: '14 lokale Werkzeuge · Reihenfolge selbst bestimmen · Nichts verlässt den Mac',
      },

      windowPreviews: {
        title: 'Fenster ansehen, per Klick wechseln',
        description:
          'Sehen Sie Fenster vom Dock oder über Command-Tab in der Vorschau und aktivieren Sie ein Fenster per Klick auf seine Karte. Neue Konfigurationen aktivieren die Funktion; verwalten Sie sie und ihre Berechtigungen in den Einstellungen. Geschlossene und doppelte Fenster werden herausgefiltert; bei geöffneten Dock-Kontextmenüs bleiben die Vorschauen ausgeblendet.',
        detail: 'Dock und Command-Tab · Fenster per Klick wechseln · In Einstellungen regelbar',
      },
      capture: {
        title: 'Bildschirmfotos, Scroll-Aufnahmen und Anheften',
        description:
          'Erstellen, anheften oder verbinden Sie scrollende Screenshots mit eigenen Kurzbefehlen. Markieren Sie Bereiche, extrahieren Sie Bildteile, runden Sie Ecken ab und behalten Sie Anmerkungen beim Export. Erkennen und kopieren Sie Text, übersetzen und kopieren Sie ihn oder exportieren Sie erkannte Tabellen als .xlsx. Legen Sie Screenshots in der Ablage ab. Kurzbefehle werden auf Konflikte mit Spracheingabe und Schnellaktionen geprüft. Der Speicherdialog öffnet sich im Screenshotordner unter Einstellungen → Speicherort. Angeheftete Screenshots bleiben bei weiteren Aufnahmen erhalten. Lange Aufnahmen unterstützen langsames automatisches Scrollen; auf kompatiblen Geräten sind HDR-Bildschirmfotos möglich. Das Einrasten an Fenstern berücksichtigt auch das Einstellungsfenster von zisla. Angeheftete Bilder passen sich ihrem Rahmen an, wenn Sie über die Werkzeugleiste oder das Trackpad zoomen oder eine Ecke ziehen.',
        detail: 'Markieren und extrahieren · Erkennen, übersetzen und kopieren · Runde Ecken und .xlsx',
      },
      voice: {
        title: 'Spracheingabe und Aufbereitung',
        description:
          'Mit einer Taste umschalten oder zum Sprechen gedrückt halten: Die Spracherkennung des Systems lässt sich mit Fachwortlisten und eigenen Schlüsselwörtern ergänzen. Optional korrigieren Ollama, LM Studio oder ein entferntes Modell das Transkript unter Beibehaltung des Sinns und formatieren ausdrücklich aufgezählte Punkte. Einstellungen → Systemmonitor und Bereinigung kann gespeicherte Audiodateien nach 7, 15 oder 30 Tagen löschen und Transkripte behalten; die automatische Bereinigung ist standardmäßig aus.',
        detail: 'Zwei Aufnahmearten · Wortlisten und Schlüsselwörter · Modell optional',
      },
      media: {
        title: 'Medien und Systemklänge',
        description:
          'Steuere die laufende Wiedergabe oben in der Island oder wähle einen Hintergrundklang von macOS. Beim Sperren, beim Bildschirmschoner oder im Ruhezustand des Displays kann er sich automatisch beenden. Wählen Sie Wellenform oder Cover-Leuchten; der Wiedergabefortschritt erscheint auch in kompakten und schwebenden Ansichten.',
        detail: 'Wiedergabesteuerung · Songtexte synchron · Klang endet automatisch',
      },
      browserDownloads: {
        title: 'Fortschritt von Browser-Downloads',
        description:
          'Erkennt Downloads in Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera und Arc und zeigt Quelle und Fortschritt in Echtzeit am oberen Bildschirmrand. Der Fortschritt zeigt den tatsächlichen Zieldateinamen, wenn der Browser ihn bereitstellt.',
        detail: '8 Browser · Quelle erkannt · Hinweis bei Abschluss',
      },
      copyAssistant: {
        title: 'Schnellaktionen und nächste Schritte',
        description:
          'Nach dem Aktivieren erscheinen kopierter Text, Links, Dateien oder Bilder in einer eigenen Leiste am oberen Bildschirmrand. Er erkennt Links, Namen lokal installierter Apps und Emoji-Namen und kann kopierte Geldbeträge zu aktuellen Wechselkursen umrechnen; alle nächsten Schritte führt er erst nach deiner Bestätigung aus. Öffne nach einem Browserdownload oder AirDrop-Empfang den Zielordner über Schnellaktionen. Unterstützt die standardmäßigen und selbst gewählten Chrome-Downloadordner, unabhängig von der Anzeige des Downloadfortschritts. IP-Abfragen und das Öffnen von Links sind getrennte Aktionen. Währungsumrechnungen erkennen lokale Untereinheiten; der Emoji-Katalog enthält Emoji 18.0. Gespeicherte Texte und Bilder verwenden den separaten Schnellaktionenordner unter Einstellungen → Speicherort. Wenn sich eine App nicht öffnen lässt, prüfen Schnellaktionen ihre Integrität, Signatur und die macOS-Sicherheitsrichtlinien. Nach bestandener Prüfung können sie Quarantänemerkmale entfernen und die App öffnen. Ändere unter Einstellungen → Schnellaktionen die Aktionsreihenfolge je erkanntem Typ. Geldbeträge unterstützen regionale Währungssymbole und vorangestellte Währungscodes. Die Befehlserkennung unterstützt Here-Dokumente.',
        detail: 'Lokale Erkennung · Live-Wechselkursumrechnung · Standard Command+N',
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
          'Wählen Sie aus dem erweiterten Tier- und Figurenkatalog oder importieren Sie ein unterstütztes Bild, eine Animation oder ein Video mit eigenem Namen. Platzieren Sie das Tier auf einer Seite der Insel und entfernen Sie importierte Tiere in den Einstellungen. Animationen dürfen höchstens 30 Sekunden, Dateien höchstens 100 MB umfassen.',
        detail: 'Erweiterter Katalog · Bilder und Videos importieren · Eigene Tiere entfernen',
      },
      lockScreen: {
        title: 'Informationen im Sperrbildschirm',
        description:
          "Zeig bei Bedarf Datum, Status und laufende Wiedergabe im Sperrbildschirm von macOS.",
        detail: "Selbst aktivieren · Nimmt keinen Fokus",
      },
      recommendedTools: {
        title: 'Empfohlene Apps',
        description:
          'Entdecke OpenScreen für Bildschirmaufnahmen und Videoschnitt, DockDoor für Fenstervorschauen und App-Wechsel sowie Zshell als nativen macOS-Terminal-Arbeitsbereich. Diese Drittanbieter-Apps werden separat installiert.',
        detail: 'Desktop-Werkzeuge entdecken · Drittanbieter-Apps · Separate Installation',
      },
    },
  },
  ai: {
    eyebrow: "KI-WORKFLOW",
    title: "KI-Aufgaben verfolgen, <span>Nutzung und Kontingente prüfen.</span>",
    lede: "Aufgaben nach App, Modellnutzung nach Datum und verbleibende Kontingente der Konten anzeigen.",
    summaryMono: "AUFGABEN / NUTZUNG / KONTINGENTE",
    summaryLede:
      "KI-Aufgaben, Nutzung und Kontingente an einem Ort.",
    toolsHeading: 'Unterstützte KI-Werkzeuge',
    toolsLede:
      "Erkennt Aufgaben unterstützter CLIs, Desktop-Apps und IDEs.",
    toolsAriaLabel: 'Unterstützte KI-Werkzeuge',
    boundariesHeading: "Datenschutz",
    privacyPoints: [
      "Aufgabenstatus und Nutzung bleiben auf deinem Mac",
      "Prompts und Antworten werden nicht gelesen",
      "Gespräche werden nicht hochgeladen",
    ],
    bridgeHeading: 'Eigene Aufgaben anbinden',
    bridgeLede:
      "Mit zislactl zeigst du Skripte und Build-Aufgaben in der Statusleiste an.",
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
        desc: "Funktioniert auf Displays mit Notch und externen Bildschirmen.",
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
  help: {
    "title": "Mit zisla beginnen",
    "lede": "Wähle eine Aufgabe und prüfe Zugang, Schritte, Rechte und Speicherort.",
    "labels": {
      "entry": "Zugang",
      "shortcuts": "Tastenkürzel",
      "permissions": "Berechtigungen",
      "output": "Ergebnis und Speicherort"
    },
    "guides": {
      "clipboard": {
        "title": "Kopierte Inhalte wiederverwenden",
        "summary": "Suche im Verlauf oder wähle nach dem Kopieren eine Aktion.",
        "entry": "Insel → Zwischenablage; Einstellungen → Schnellaktionen.",
        "steps": [
          "Aktiviere Verlauf oder Schnellaktionen und kopiere einen Beispieltext oder Link.",
          "Öffne die Zwischenablage, filtere oder suche und kopiere einen Eintrag.",
          "Kopiere ein Beispielbild mit lesbarem Text, warte auf die lokale Erkennung im Hintergrund und suche dann nach einem Wort, um das Originalbild zu finden.",
          "Klicke mit der rechten Maustaste auf das Bild, um Text zu erkennen oder zu kopieren; laufende Erkennung kannst du abbrechen. Die Hintergrund-Erkennung kopiert den Text nicht automatisch.",
          "Füge ihn in der Ziel-App ein. Bei einer neuen Kopie kannst du im Aktionsfenster den nächsten Schritt wählen."
        ],
        "shortcuts": "Command+1…9 und Command+0 folgen der Aktionsreihenfolge. Neue Konfigurationen nutzen zusätzlich Command+N für die erste Aktion; Command+Delete schließt das Fenster. Gespeicherte oder gelöschte Belegungen bleiben erhalten.",
        "permissions": "Verlauf und Erkennung sind lokal. Sondertasten/Maustasten benötigen Eingabeüberwachung, die optionale Kopiergeste Bedienungshilfen. Übersetzung nutzt den gewählten Dienst.",
        "output": "Verlauf in lokalen App-Daten. Text/Bild speichern nutzt Einstellungen → Speicherort → Schnellaktionen; neuer Standard: ~/Downloads/quick."
      },
      "capture": {
        "title": "Bildschirm aufnehmen und bearbeiten",
        "summary": "Bearbeite ein Bildschirmfoto oder eine Aufnahme und exportiere es.",
        "entry": "Menüleiste → Bildschirmfoto/Aufnahme; Einstellungen → Aufnahme → Studio.",
        "steps": [
          "Wähle einen Bereich oder ein Fenster für ein Bildschirmfoto und bearbeite, kopiere, speichere oder parke es.",
          "Wähle Bildschirm, Fenster oder Bereich für die Aufnahme und aktiviere nur benötigte Audio-/Kameraquellen.",
          "Stoppe die Aufnahme, bearbeite und prüfe sie im Studio, dann exportiere das gewünschte Format."
        ],
        "shortcuts": "Control+1 Bildschirmfoto; Control+2 langes Bildschirmfoto. Control+Shift+1/2/3 nehmen Bildschirm/Fenster/Bereich auf; Control+Shift+6 öffnet das Studio. In Einstellungen änderbar.",
        "permissions": "Bildschirmaufnahme erforderlich. Mikrofon und Kamera benötigen ihre eigenen Rechte; dies gilt auch für die Kameravorschau.",
        "output": "Neue Standards: ~/Downloads/picture für Bilder, ~/Downloads/video für Aufnahmen/Projekte. Ordner separat einstellbar. Manche Exporte brauchen FFmpeg."
      },
      "shelf": {
        "title": "Dateien über die Ablage weiterreichen",
        "summary": "Halte Dateien bereit, ohne die Originale zu kopieren.",
        "entry": "Insel → Ablage; an den oberen Auslöser ziehen.",
        "steps": [
          "Ziehe eine Beispieldatei nach oben oder schüttle beim Ziehen, wenn die Geste aktiv ist.",
          "Öffne die Ablage und wähle Kategorie oder benötigte Einträge.",
          "Ziehe zur Ziel-App, zeige in Finder oder teile; geparkte Bildschirmfotos kannst du als PNG speichern.",
          "Wähle Dateien oder Ordner und die ZIP-Komprimierung im Kontextmenü; das Archiv erscheint wieder in der Ablage.",
          "Wähle Bilder in der Ablage und Größenänderung oder Formatkonvertierung; führe die Bildwerkzeuge aus, damit erfolgreiche Ergebnisse in die Ablage zurückkehren.",
          "Wähle Bilder, Video oder Audio und importiere sie in die Medienbibliothek des Aufnahmestudios; das aktuelle Projekt und die Zeitleiste bleiben erhalten."
        ],
        "shortcuts": "Mit dem Zeiger ziehen. Die Schüttelgeste ist separat einstellbar; kein festes Tastenkürzel nötig.",
        "permissions": "Dateiauswahl und sichere Lesezeichen erlauben Zugriff auf ausgewählte Dateien. Bildschirmfotos benötigen Bildschirmaufnahme.",
        "output": "Originale bleiben am Ort. Verweise und geparkte Bilder bleiben lokal gespeichert; PNG geht an den gewählten Zielort. ZIP-Archive und erfolgreiche Bildergebnisse kehren in die Ablage zurück; importierte Medien kommen in die Bibliothek des Aufnahmeprojekts."
      },
      "meeting": {
        "title": "An einem Meeting teilnehmen und Notizen behalten",
        "summary": "Verknüpfe einen Kalendertermin mit einer Kontextnotiz.",
        "entry": "Insel → Kalender; Kalender und Kontextnotizen in Einstellungen aktivieren.",
        "steps": [
          "Erstelle oder öffne einen Termin mit unterstütztem Meeting-Link und gültiger Start-/Endzeit.",
          "Wähle Teilnehmen; der Countdown erscheint 10 Minuten vor Beginn.",
          "Erstelle, speichere oder verknüpfe eine Notiz über die Terminaktion und öffne sie später über Termin oder Ablage."
        ],
        "shortcuts": "Teilnahme und Notizen sind Schaltflächen. Für andere Orte halte die konfigurierte Taste und schüttle; Standard ist Command.",
        "permissions": "Kalenderzugriff nötig. Fensternotizen können Bedienungshilfen benötigen; angehängte Bildschirmfotos benötigen Bildschirmaufnahme.",
        "output": "Meeting-Kontextnotizen sind lokale Ablagedaten. Schnellnotizen sind separat und verwenden Apple Notizen."
      },
      "ai": {
        "title": "KI verbinden und Kontingente prüfen",
        "summary": "Verfolge Aufgaben, aufgezeichnete Nutzung und Kontokontingente.",
        "entry": "Einstellungen → KI; Insel → KI-Monitor.",
        "steps": [
          "Aktiviere ein unterstütztes lokales Werkzeug oder melde eine Aufgabe über zislactl gemäß CLI-Referenz.",
          "Aktiviere Kontingentüberwachung für den Anbieter und trage Zugangsdaten nur bei Aufforderung ein.",
          "Prüfe Abfrage-/Rücksetzzeit und Warnungen; öffne den Verlauf oder exportiere .xlsx."
        ],
        "shortcuts": "KI-Monitor oder Einstellungen verwenden; kein festes globales Kürzel nötig. zislactl nutzt dokumentierte Argumente.",
        "permissions": "Lokale Erkennung liest strukturierte Zustände. Kontingente werden beim Anbieter abgefragt; optionale KI-Bearbeitung nutzt das gewählte Modell oder CLI.",
        "output": "Aufgaben/Nutzung: ~/Library/Application Support/zisla/ai-state.sqlite. Kontingente sind Anbieterwerte statt token-Schätzungen; fehlende Daten bleiben nicht verfügbar."
      },
      "media-tools": {
        "title": "Bilder, Audio und PDF verarbeiten",
        "summary": "Nutze die unabhängigen lokalen Werkzeuge mit Beispieldateien.",
        "entry": "Einstellungen → Bildwerkzeuge / Audiowerkzeuge / PDF-Werkzeuge.",
        "steps": [
          "Füge ein Bild hinzu, wähle Aktion und Optionen, führe sie aus und exportiere Ergebnis oder ZIP.",
          "Wähle Bilder in der Ablage und Größenänderung oder Formatkonvertierung; führe die Bildwerkzeuge aus, damit erfolgreiche Ergebnisse in die Ablage zurückkehren.",
          "Installiere FFmpeg und ffprobe über Abhängigkeiten, lade Audio, wähle Schneiden oder Mischen und eine Ausgabedatei oder einen Ordner.",
          "Füge PDF in der gewünschten Reihenfolge hinzu, führe die Aktion aus und speichere. Office-Konvertierung benötigt LibreOffice oder OpenOffice."
        ],
        "shortcuts": "Werkzeugschaltflächen; kein festes globales Kürzel.",
        "permissions": "Dateiauswahl erlaubt Zugriff auf gewählte Dateien und Ordner. Verarbeitung lokal; Abhängigkeiten werden heruntergeladen.",
        "output": "Neue Standards: Bilder ~/Downloads/picture, PDF ~/Downloads/pdf, separat einstellbar. Audio nutzt den Exportdialog."
      },
      "daily-briefing": {
        "title": "Einen Tagesbericht erstellen",
        "summary": "Prüfe gewählte Statistiken vor dem PNG-Export.",
        "entry": "Einstellungen → Tagesbericht.",
        "steps": [
          "Wähle Vorlage und Statistiken.",
          "Prüfe verfügbare Daten in der Vorschau und wähle den Ausgabeordner.",
          "Exportiere heute oder aktiviere tägliche Ausgabe mit Uhrzeit."
        ],
        "shortcuts": "Vorschau- und Exportknöpfe; kein festes Kürzel.",
        "permissions": "Aktiviere die zugehörigen Statistikfunktionen. Bildschirmzeit kann Festplattenvollzugriff benötigen; Kontingente werden beim Anbieter abgefragt.",
        "output": "PNG im Tagesberichtordner; neuer Standard ~/Downloads/daily. Fehlende Daten sind keine gemessene Null."
      },
      "desktop": {
        "title": "Fenster ansehen und Kontextnotizen schreiben",
        "summary": "Wechsle zum Fenster und hinterlasse eine Ortsnotiz.",
        "entry": "Einstellungen → Fenstervorschau / Kontextnotizen; Dock, Command+Tab und Ablage.",
        "steps": [
          "Aktiviere und erlaube Vorschauen, zeige auf eine Dock-App oder nutze Command+Tab und klicke eine Karte.",
          "Halte auf einer Beispielseite, einem Fenster oder Desktop die konfigurierte Taste und schüttle; schreibe und speichere die Notiz.",
          "Kehre zurück oder öffne die Notiz über die Ablage; ergänze bei Bedarf Erinnerungen oder Fensterbilder."
        ],
        "shortcuts": "Command+Tab wechselt Apps. Kontextnotizen nutzen standardmäßig gehaltenes Command, in Einstellungen änderbar.",
        "permissions": "Vorschauen brauchen Bedienungshilfen und Bildschirmaufnahme. Fenstererkennung nutzt Bedienungshilfen; Bildanhänge Bildschirmaufnahme.",
        "output": "Notizen und Bilder in lokalen Ablagedaten unter ~/Library/Application Support/zisla."
      },
      "playback": {
        "title": "Wiedergabe wählen und App-Lautstärke mischen",
        "summary": "Wähle Ausgabe und passe spielende Apps an.",
        "entry": "Medienbereich → Ausgabegerät; Einstellungen → Medienquelle; Insel → App-Mixer.",
        "steps": [
          "Spiele Beispielaudio und wähle ein verfügbares Ausgabegerät.",
          "Wähle automatische Quelle oder bevorzugten Player und prüfe die Wiedergabeknöpfe.",
          "Öffne unter macOS 14.4+ den Mixer, erlaube Systemaudioaufnahme und regle oder mute eine App."
        ],
        "shortcuts": "Wiedergabeknöpfe und Regler; kein festes Kürzel.",
        "permissions": "Mixer benötigt macOS 14.4+ und Systemaudioaufnahme. Geräte hängen von Verbindungen ab; Bluetooth kann eine Berechtigung benötigen.",
        "output": "Ausgabegerät ist die Systemwahl. App-Lautstärken werden lokal gespeichert; keine Dateiausgabe."
      }
    },
    "workflowsTitle": "Kurze Ablaufdemos",
    "workflows": {
      "copy-next": {
        "title": "Finden, kopieren und wiederverwenden",
        "steps": [
          "Suche im Verlauf nach dem Beispielwort „brew“.",
          "Kopiere den passenden Eintrag.",
          "Füge ihn in der Ziel-App ein. Der Ausschnitt zeigt Suche und Kopie; für neue Kopien sind Schnellaktionen separat verfügbar."
        ]
      },
      "drop-output": {
        "title": "Datei ablegen und Ausgabe vorbereiten",
        "steps": [
          "Ziehe ein Beispielbild aus Finder in die obere Ablage.",
          "Öffne die Ablage und wähle das Bild.",
          "Ziehe es zum Ziel oder speichere ein geparktes Bild als PNG. Der Ausschnitt zeigt das Ablegen."
        ]
      },
      "meeting-note": {
        "title": "Vom Meeting zur Notiz",
        "steps": [
          "Öffne das Meeting mit seinem Teilnahmelink.",
          "Wähle neue Meeting-Notiz oder vorhandene Notiz verknüpfen.",
          "Speichere und öffne sie über Termin oder Ablage. Der Ausschnitt zeigt Erstellen und Verknüpfen."
        ]
      }
    },
    "excerptLabel": "Ausschnitt abspielen",
    "guideLinkLabel": "Anleitung lesen",
    "videoNotice": "Ausschnitte der vorhandenen Produkttour mit Demodaten. Video-Untertitel sind Englisch, die Schritte folgen deiner Sprache. Die vollständige 2:40-Tour und Musikangaben stehen weiter unten.",
    "preferencesTitle": "Nützliche Einstellungen",
    "preferences": [
      "Aktiviere Schütteln beim Ziehen, um die Ablage einzublenden. Kontextnotizen nutzen eine eigene gehaltene Taste.",
      "Wähle die Audioausgabe im Medienbereich und automatische Quelle oder bevorzugten Player in Einstellungen. Diese Wahl weist Apps keine getrennten Geräte zu.",
      "Tastentöne und Tippstatistik sind unabhängig und nutzen Eingabeüberwachung. Der App-Mixer benötigt macOS 14.4+ und Systemaudioaufnahme.",
      "Der Tagesbericht bietet 8 Vorlagen, Vorschau und manuelle oder tägliche PNG-Ausgabe mit eigenem Ordner."
    ]
  },
  download: {
    eyebrow: 'JEDERZEIT EINSATZBEREIT',
    title: 'zisla laden',
    copy: 'Für Macs mit Apple Silicon. Versionen, weitere Architekturen und Prüfsummen stehen auf der Release-Seite. Nach der Installation prüft zisla im gewählten Update-Kanal auf neue Versionen: Sparkle verifiziert zuerst die Signatur und lädt, installiert und startet dann je nach Einstellung manuell oder automatisch neu; Updates behalten die bereits erteilten Berechtigungen. Die Update-Einstellungen verlinken außerdem direkt zu GitHub Issues für Feedback. Ein Release, der dich nicht betrifft, lässt sich überspringen und wird nicht mehr gemeldet. Lesen Sie Versionshinweise vor der Installation und nach dem Neustart.',
    primaryCta: 'Laden',
    primaryCtaAriaLabel: 'Laden',
    releaseCta: 'Release ansehen',
    releaseCtaAriaLabel: 'Details des Release auf GitHub ansehen',
    brewMono: 'HOMEBREW / EIN BEFEHL',
    brewNote: 'Sparkle hält zisla selbst aktuell, deshalb ersetzt brew upgrade die App nur, wenn die installierte Version wirklich älter ist als die im Tap – ab Homebrew 5.1.6 wird die Version in der App selbst gelesen. Wird der Cask ausdrücklich genannt, etwa mit brew upgrade --cask zisla, zählen stattdessen die Installationsdaten von Homebrew, was nach einem Sparkle-Update zurück auf die Tap-Version führen kann. Der Tap liefert nur stabile Releases. Es ist ein Tap von Dritten und die App ist nicht notarisiert, daher braucht der erste Start „Dennoch öffnen“ unter „Systemeinstellungen → Datenschutz & Sicherheit“.',
    copyBrewCommandAriaLabel: 'Homebrew-Installationsbefehl kopieren',
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
  changelog: {
    releaseNotes: {
      'v0.1.25': [
        'Starten Sie die Bereinigung unnötiger Dateien in den Dienstprogrammen mit den vorhandenen Einstellungen. Fortschritt und Ergebnisse erscheinen in der Insel; KI-Ergebnisse bleiben lesbar, bevor die Bereinigungsanzeige zurückkehrt.',
        'Der Inhalt angehefteter Bildschirmaufnahmen skaliert beim Zoomen über Werkzeugleiste, Trackpad oder Ecken mit dem Rahmen, auch bei HDR-Bildern.',
        'Die Wetterliste zeigt einen gemeinsamen Aktualisierungszeitpunkt und fasst Quellenangaben ohne doppelte Einträge zusammen.',
        'Die Tippstatistik erhält ihre vertikale Bildlaufleiste zurück und das Dashboard bleibt innerhalb des sichtbaren Bereichs.',
        'Audiowerkzeuge passen in den sichtbaren Bereich der Einstellungen. Operationsliste und Bearbeitungsbereich lassen sich getrennt scrollen.',
        'Der Lautstärkemixer blendet inaktive Audioquellen aus, behält gespeicherte Lautstärke- und Stummschaltungssteuerungen bei und ermöglicht erneute Versuche bei fehlgeschlagener Audioerkennung.',
      ],
      'v0.1.24': [
        'Der Zwischenablageverlauf lässt sich nach Quellanwendung durchsuchen und gruppieren. Schnellaktionen erkennen Befehle mit Here-Dokumenten.',
        'Die Systembereinigung kann im Hintergrund laufen und Fortschritt sowie Ergebnisse in der Insel anzeigen. Die Datenträgerbereinigung erkennt doppelte App-Installationen und Überreste von App-Updates.',
        'Alle Ausgabeordner lassen sich mit einer Aktion auf ihre Standardwerte zurücksetzen. Einstellungsgruppen und Seitenreihenfolge wurden neu geordnet.',
        'Unterstützte Geräte können HDR aufnehmen. Texterkennung, Übersetzung und HDR-Vorschauen für Screenshots funktionieren wieder; das Einrasten an Fenstern berücksichtigt die Einstellungen.',
        'Schnellnotizen lassen sich mit Command und den Pfeiltasten durchblättern. Eingefügter Text übernimmt die native Schrift des Fließtexts.',
        'KI-Kontingente unterstützen unabhängige Regionen. Täglicher Nutzungsverlauf und Farben des Restkontingents stimmen zwischen ausgeklappten Karten und kompakten Hinweisen überein. Abgebrochene Kimi-Runden löschen Fehler; abgebrochene Abo-Aktualisierungen lesen keine Zugangsdaten mehr.',
        'Fenstervorschauen filtern geschlossene und doppelte Fenster, berücksichtigen bei alternativen Abrufen deren Identität und bleiben bei geöffneten Dock-Kontextmenüs ausgeblendet.',
        'Die Medienüberwachung aktualisiert veraltete Quellen und beendet den Audiostatus, wenn keine Samples mehr eintreffen. App-Lautstärken bleiben gespeichert; Überblendungen richten sich nach der Zeit dekodierter Samples. Tastaturklänge und Statistiken behandeln fehlende Wiedergabe und leere Daten zuverlässiger.',
        'Nach erteilter Freigabe aktualisiert sich der Berechtigungsstatus; eine Ziehhilfe unterstützt die Einrichtung. Fehlermeldungen empfohlener Werkzeuge bleiben lesbar.',
      ],
      'v0.1.23': [
        'Bildwerkzeuge bieten neun lokale Vorgänge: Komprimierung, Konvertierung zwischen fünf Formaten, Skalierung und Zuschnitt, Vergleich des kleinsten Formats, Drehen und Spiegeln, Wasserzeichen, Mosaik und Unschärfe, Text- und Tabellenerkennung sowie Hintergrundentfernung. Stapel- und ZIP-Export sowie eigene Speicherordner für PDF- und Bildwerkzeuge sind verfügbar.',
        'Audiowerkzeuge bieten 27 lokale Vorgänge für Konvertierung, Bearbeitung, Aufteilen, Verbinden, Mischen, Audioextraktion, LUFS-Normalisierung, Effekte, Kanäle und Tags. FFmpeg und ffprobe sind erforderlich; eine Exportdatei oder ein Ordner lässt sich wählen.',
        'Die KI-Kontoüberwachung zeigt Kontingentringe, Rücksetzzeiten und Hinweise bei niedrigem Kontingent in den Inselansichten, einschließlich 5h/7d-Fenstern und Cursor-Budgets in USD, sofern verfügbar. Tagesberichte können echte Kontingente und deren Erfassungszeiten enthalten.',
        'Wähle ein Datum im KI-Nutzungsverlauf oder in der Heatmap, um Eingabe-, Ausgabe- und Gesamttokens je Anbieter und Modell zu sehen. In Einstellungen kannst du den Verlauf anzeigen, vollständig als .xlsx exportieren oder löschen. Home gruppiert laufende KI-Arbeit je Anwendung und zeigt Berichtsexporte auf der Insel.',
        'Kalendertermine mit Meeting-Link zeigen ab 10 Minuten vor Beginn einen Countdown und einen Beitritt per Klick. Erstelle Meeting-Notizen oder verknüpfe und löse vorhandene Kontextnotizen. Mail kann den gesamten Posteingang als gelesen markieren.',
        'Die Ablage bietet Suche, Filter und Mehrfachauswahl zum Kopieren, Teilen oder Senden an Schnellnotizen. Wandle Bilder in PDF um, übernimm erkannten Bildtext in Notizen oder öffne ausgewählte Videos im Aufnahmestudio.',
        'Wähle automatische Energiemodi für Netz- und Akkubetrieb, optional mit Stromsparmodus bei 20% oder weniger. Lade sofort auf 100%, wenn macOS die Aktion anbietet. Systemverlauf, .xlsx-Export und Löschen sind in Einstellungen erreichbar.',
        'Horizontale und vertikale kompakte Pomodoro-Ansichten bieten Fortschritt, Pause, Fortsetzen und Zurücksetzen. Beim Überfahren der Bedienelemente bleibt die Insel eingeklappt, auch in vertikalen Ansichten mit mehr Informationen.',
        'Lange Screenshots unterstützen langsames automatisches Scrollen im gewählten Fenster. Auf unterstützten Geräten ist HDR-Aufnahme möglich; die Bearbeitung behält Einstellungen für Bilddarstellung und Export bei.',
        'Schnellaktionen können eine nicht startende App nach Prüfung von Integrität, Signatur und macOS-Sicherheitsrichtlinien reparieren. Ordne Aktionen je Typ neu, nutze erweiterte Beispiele sowie regionale Währungssymbole oder Codes mit Präfix. Flug-, Zug- und Paketsuchen werden bevorzugt erkannt.',
        'Einstellungen trennen Dynamic Island-Layout, Tagesbericht, Benachrichtigungen und Fürsorge sowie Workflow in eigene Seiten. Kompakte Statusprioritäten lassen sich ändern und installierte Komponenten optional täglich aktualisieren. Die Aufnahmebereinigung befindet sich unter Systemmonitor und Bereinigung und behält Transkripte.',
        'Browserdownloads zeigen echte Zieldateinamen, sofern verfügbar. Leerlaufdarstellung, KI-Scans, Laden des Systemverlaufs und Studiowiedergabe benötigen weniger Ressourcen. Kompakte KI-Logos, Kontingentkarten und Ergebnisanimationen wurden angepasst; Wetterscrollen, Ablagedrops, Mail-Schreibvorgänge und Erhalt des Zwischenablageverlaufs wurden korrigiert.',
        'Die Homepage bietet eine 160-sekündige Funktionstour mit Start per Klick und einem Link zum Originalvideo. Die Seite bleibt ohne WebGL nutzbar; zu den empfohlenen Apps gehört nun der Terminalarbeitsbereich Zshell.',
      ],
      'v0.1.22': [
        'Das Aufnahmestudio ergänzt Hautglättung, Aufhellung, Gesichts- und Körperkorrektur, einstellbare Stimmvorlagen und optionales Mikrofon-Monitoring. Die Effekte lassen sich vor der Aufnahme und beim Bearbeiten einstellen.',
        'Sanfte Cursorspuren haben eine frei wählbare Farbe. Die Studiowiedergabe zeigt das bearbeitete Ergebnis mit Spuren, Effekten und Audio.',
        'Einstellungen → Speicherort trennt Downloads, Screenshots, Aufnahmen, Schnellaktionen und Tagesberichte. Beim Update bleiben bisherige Speicherorte erhalten und können danach unabhängig geändert werden.',
        'Optionale Systembereinigung verschiebt Einträge alle 7, 15 oder 30 Tage in den Papierkorb. Wählbar sind vertrauenswürdige oder alle bearbeitbaren Einträge, einschließlich prüfpflichtiger; standardmäßig ist sie aus. KI-Arbeitsordner ohne gespeicherte Sitzung können geprüft werden, während gespeicherte Sitzungen und neue Ordner geschützt bleiben.',
        'Zwischenablageverlauf kann Einträge über 7, 15 oder 30 Tage automatisch löschen und Favoriten behalten. Automatisches Löschen ist standardmäßig aus.',
        'Kurznotizen zeigen handschriftliche Anhänge und erlauben das Bearbeiten des Texts davor oder danach über Notizen, während die Originalanhänge erhalten bleiben.',
        'Die KI-Überwachung blendet verbleibende Abonnementkontingente aus und behält tägliche Nutzung. Diagrammscrollen und Monatsbeschriftungen sind verbessert. Batterieeinstellungen sind unter Systemstatus zusammengefasst.',
        'Quiet.md für lokale Notizen gehört zu den empfohlenen Desktop-Apps und lässt sich in den Einstellungen installieren und verwalten.',
        'Bilibili lädt den ausgewählten Videoteil und unterstützt mehr Linkformate. Kalenderlöschen betrifft das ausgewählte wiederkehrende Vorkommen. Angeheftete Screenshots bleiben bei weiteren Aufnahmen sichtbar; Werkzeugbeschriftungen und Größenanzeigen sind zuverlässiger.',
      ],
      'v0.1.21': [
        'Die Systemüberwachung behält standardmäßig den gesamten vorhandenen und neuen minütlichen Verlauf, bis er manuell gelöscht wird. Diagramme für beliebige Zeiträume und der .xlsx-Export bleiben verfügbar.',
        'Downloads, Aufnahmen und Screenshots teilen einen Speicherort. Der Speicherdialog für Screenshots öffnet sich im aktuellen Download-Ordner; die doppelte Speicherort-Einstellung für Aufnahmen wurde entfernt.',
        'Die Einstellung für den Statusanzeigeort und ihr Sucheintrag erscheinen nur bei frei positionierten Pillenlayouts. Bei Notch- oder Kameraposition bleibt die Zeile verborgen, wenn nur die Menüleiste verfügbar ist.',
        'Der Countdown der Schnellaktionen verwendet im Notch-Layout einen unteren Fortschrittsbalken. Pillenlayouts behalten die Fortschrittsanzeige entlang des gesamten Randes.',
      ],
      'v0.1.20': [
        'Wählen Sie aus acht Vorlagen und bestimmen Sie Nutzungs-, Tipp-, System- und zisla-Aktivitätsdaten. Prüfen Sie die Vorschau und exportieren Sie ein PNG manuell oder täglich zur gewählten Zeit. Der Bildschirmzeitverlauf wird nur bei Aktivierung und Verfügbarkeit verwendet; fehlende Daten gelten nicht als gemessene Null.',
        'Stellen Sie das Intervall für Pausen, Trinken, Bewegung und Augenruhe ein. Meldungen berücksichtigen die Tageszeit. Natürliche Pausen, Sperren und Ruhezustand setzen die Zeitmessung zurück. Fokusabschluss und Notizaktionen können kurze Rückmeldungen zeigen. In den Einstellungen aktivierbar. Speichern Sie eine bearbeitbare Notiz zu einer Webseite, einem App-Fenster oder dem Schreibtisch und sehen Sie sie bei der Rückkehr. Hängen Sie Fensterbilder an, verwalten Sie Notizen in der Ablage und setzen Sie wiederkehrende Erinnerungen von einer Stunde bis drei Tagen oder schalten Sie sie aus.',
        'Nutzen Sie die Kameraposition oder wählen Sie eine eigene Position an einem Bildschirmrand. Sie bleibt beim Moduswechsel gespeichert. Horizontale und vertikale Kompaktansichten passen ihre Länge an Statussymbole, KI-Aufgaben, Downloads und Medien an und können weitere Informationen anzeigen. Wählen Sie Wellenform oder Cover-Leuchten; der Wiedergabefortschritt erscheint auch in kompakten und schwebenden Ansichten.',
        'Wählen Sie aus dem erweiterten Tier- und Figurenkatalog oder importieren Sie ein unterstütztes Bild, eine Animation oder ein Video mit eigenem Namen. Platzieren Sie das Tier auf einer Seite der Insel und entfernen Sie importierte Tiere in den Einstellungen. Animationen dürfen höchstens 30 Sekunden, Dateien höchstens 100 MB umfassen.',
        'Nehmen Sie Bildschirm, Fenster oder Bereich mit optionalem Systemaudio, Mikrofon und Kamera auf. Bearbeiten Sie Video, Audio, Bilder und Text auf mehreren Spuren, ergänzen Sie Animationen, Zooms und Untertitel und prüfen Sie eine scharfe Vorschau. Wählen Sie Original, 16:9, 9:16, 1:1 oder 4:3. Exportieren Sie Video, GIF, Live Photo oder Audio; manche Formate benötigen FFmpeg. Optionale KI-Vorschläge werden vor der Anwendung geprüft.',
        'Erstellen, anheften oder verbinden Sie scrollende Screenshots mit eigenen Kurzbefehlen. Markieren Sie Bereiche, extrahieren Sie Bildteile, runden Sie Ecken ab und behalten Sie Anmerkungen beim Export. Erkennen und kopieren Sie Text, übersetzen und kopieren Sie ihn oder exportieren Sie erkannte Tabellen als .xlsx. Legen Sie Screenshots in der Ablage ab. Kurzbefehle werden auf Konflikte mit Spracheingabe und Schnellaktionen geprüft.',
        'Die Aufgabenerkennung für Cursor sowie numerische Nutzung und verfügbare Abonnementkontingente für Cursor und Muse Code sind ergänzt. Lange Werkzeugläufe in Cursor bleiben sichtbar. IP-Abfragen und das Öffnen von Links sind getrennte Aktionen. Währungsumrechnungen erkennen lokale Untereinheiten; der Emoji-Katalog enthält Emoji 18.0.',
        'Regeln Sie Lautstärke und Stummschaltung einzeln für Apps, die Audio abspielen. Erfordert macOS 14.4 oder neuer und die Berechtigung zur Aufnahme von Systemaudio. In den Einstellungen verfügbar, außerhalb des Modulkarussells der Insel. Prüfen Sie den Status unter Einstellungen → Berechtigungen, starten Sie unterstützte Anfragen oder öffnen Sie die zuständige Systemseite. Die erste Begrüßung nutzt dieselbe Liste und kennzeichnet manuelle Einstellungen. Sprachmengen, Diktierdauer, Geschwindigkeit und eingesparte Zeit erscheinen ebenfalls im Tastatur-Dashboard. Neue Konfigurationen aktivieren Klänge und Tippstatistik; beide lassen sich einzeln abschalten. Wählen Sie beim Verfassen Dateien als Anhänge aus. Lesen Sie Versionshinweise vor der Installation und nach dem Neustart.',
      ],
    },
    eyebrow: 'Änderungsprotokoll',
    title: 'Was sich in jeder zisla-Version geändert hat: neue Funktionen, Verbesserungen und Fehlerbehebungen.',
    lede: 'Was sich in jeder zisla-Version geändert hat: neue Funktionen, Verbesserungen und Fehlerbehebungen.',
    ariaLabel: 'zisla-Änderungsprotokoll',
    releaseCountLabel: 'Versionen',
    latestLabel: 'Neueste',
    shippedLabel: 'Ausgeliefert',
    latestBadge: 'Neueste',
    noteLabel: 'Version',
    pagerAriaLabel: 'Changelog-Seiten',
    pageLabel: 'Seite {page}',
    prevPageLabel: 'Zurück',
    nextPageLabel: 'Weiter',
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
        question: 'Öffnen oder übertragen Schnellaktionen, was ich kopiere?',
        answer:
          'Nein. Nach dem Aktivieren laufen Erkennung und Vorschau vollständig auf deinem Mac, und zisla führt einen nächsten Schritt erst aus, wenn du ihn anklickst oder das Kürzel drückst.',
      },
      permissions: {
        question: 'Welche Systemberechtigungen braucht zisla?',
        answer: '<p>Einstellungen → Berechtigungen bündelt Status, Anfragen und Links zu den Systemeinstellungen. Einige Berechtigungen erfordern manuelle Einrichtung. Sie wählen die Anfragen; auch die Begrüßung beim ersten Start bietet diese Steuerung.</p><p>Bildschirmaufnahme, Systemaudioaufnahme, Mikrofon und Kamera dienen je nach Funktion Aufnahmen, Mixer und Spiegel. Spracheingabe nutzt zusätzlich Spracherkennung. Kalender, Erinnerungen, Ortung, Bluetooth und Automation unterstützen die jeweiligen Funktionen. Manuell hinzugefügte Wetterorte benötigen keine Ortung.</p><p>Neue Konfigurationen aktivieren Tastaturklänge und Tippstatistik; beide sind einzeln abschaltbar. Globale Tastenereignisse benötigen Eingabeüberwachung. Die Statistik speichert nur Mengen, Tastencodes, Zeiten und App-Namen, niemals den eingegebenen Text. Bedienungshilfen unterstützen Einfügen, Gesten, Reinigung und Fenstersteuerung.</p><p>Vollzugriff auf die Festplatte kann für den lokalen Mail-Index und den Bildschirmzeitverlauf der Tagesberichte nötig sein. Die Dateiauswahl gewährt Zugriff auf den gewählten Ordner. Deaktivieren Sie Funktionen in zisla oder widerrufen Sie Berechtigungen unter Systemeinstellungen → Datenschutz &amp; Sicherheit.</p>',
      },
      localVoice: {
        question: 'Wie nutze ich ein lokales Modell zur Aufbereitung von Spracheingaben?',
        answer: `
      <p>Ollama, LM Studio und andere lokale OpenAI-kompatible Dienste werden unterstützt.</p>
      <ol>
        <li>Lade das gewünschte Modell in deiner lokalen Modell-App herunter oder in den Speicher und starte den Dienst.</li>
        <li>Öffne Einstellungen → Sprache → Lokale Modelle, füge eine Konfiguration hinzu und aktiviere sie. Wähle Ollama oder LM Studio und gib die Dienst-URL ein. Für andere OpenAI-kompatible Dienste wählst du ebenfalls LM Studio. Lass API Key leer, sofern der Dienst keine Authentifizierung verlangt.</li>
        <li>Wähle ein automatisch erkanntes Modell und anschließend diese Konfiguration unter Sprachorganisationsmodell → Modell verwenden.</li>
      </ol>
      <p>zisla empfiehlt anhand deines Chips und des gesamten Arbeitsspeichers ein Gemma 4 QAT-Modell. Das empfohlene Modell wird nicht automatisch heruntergeladen oder geladen.</p>
    `.trim(),
      },
      network: {
        question: 'Geht zisla ins Netz?',
        answer:
          'Wetter, signierte Update-Prüfungen, von dir gestartete Downloads und die optionale entfernte Sprachaufbereitung nutzen das Netz nach Bedarf. Die Linkerkennung in der Zwischenablage läuft rein lokal und startet nie selbst einen Download. Ein lokales Modell bereitet den Text nach der Transkription auf. Die Spracherkennung von Apple kann je nach Sprache und Systemunterstützung weiterhin das Netzwerk nutzen. Die aktivierte KI-Kontingentüberwachung fragt auch die Dienste der ausgewählten Anbieter ab.',
      },
      multiDisplay: {
        question: 'Unterstützt zisla mehrere Displays?',
        answer:
          'Ja – mehrere Displays, Spaces und gewöhnliche Vollbild-Apps, und das Öffnen nimmt nie den Fokus. Bei mehreren angeschlossenen Bildschirmen lässt sich unter Einstellungen → Allgemein → Bildschirmmodi für jeden Bildschirm der Dynamic Island-Modus (Kameraposition oder eigene Position), der Notch-Modus oder das Ausblenden wählen. Bei einem Bildschirm ist diese Einstellung verborgen und die globale Darstellung gilt; beim erneuten Anschließen werden die gespeicherten Einstellungen wiederhergestellt. Auf allen eingeblendeten Bildschirmen bleibt die eingeklappte Insel gleichzeitig sichtbar. Aufklappen, Schnellaktionen, Aufnahmen und vorübergehende Meldungen ersetzen nur die Insel auf dem jeweiligen Bildschirm; die Auswahl der Benachrichtigungsbildschirme filtert Inhalte, ohne die inaktive Insel auszublenden.',
      },
      intel: {
        question: 'Läuft es auf einem Intel-Mac?',
        answer:
          'Für Intel-Rechner kann ein Build verfügbar sein, die Kompatibilität ist aber nicht garantiert. Unterstützte Konfiguration sind derzeit Macs mit Apple Silicon.',
      },
      storage: {
        question: 'Wo speichert zisla seine Daten?',
        answer:
          'Lokale Daten liegen in ~/Library/Application Support/zisla/. Die Tippstatistik wird getrennt in ~/Library/Application Support/zisla/typing-stats.sqlite3 gespeichert. Schnellnotizen verwenden die Notizen-App des Systems. Einstellungen → Speicherort bietet separate Ordner für Downloads, PDF-Werkzeuge, Bildwerkzeuge, Screenshots, Aufnahmen, Schnellaktionen und Tagesberichte. Beim Update bleiben zuvor gewählte Speicherorte erhalten; danach lässt sich jeder Ordner unabhängig ändern. Stellen Sie alle Speicherordner mit einer Aktion auf ihre Standardwerte zurück.',
      },
    },
  },
  developers: {
    eyebrow: 'STANDARDMÄSSIG OPEN SOURCE',
    title: 'Ressourcen für Entwickler.',
    lede: 'PolyForm Noncommercial 1.0.0: nur nicht-kommerzielle Nutzung – direkt nutzen oder aus dem Quellcode bauen.',
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
      "Verwendet bei aktivierter Option „Transparenz reduzieren“ einen deckenden Hintergrund",
      'Liquid Glass ab macOS 26, mit automatischem Rückfall auf native Systemmaterialien unter macOS 14 und 15',
    ],
  },
  film: {
    title: "Produktfilm",
    videoAriaLabel: "zisla-Produktfilm",
    openVideoLabel: "Video öffnen",
    playbackError: "Das Video kann nicht abgespielt werden.",
    musicLabel: "Musik",
    excerptLabel: "Auszug",
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
    brewCommandCopied: 'Homebrew-Installationsbefehl kopiert',
  },
};
