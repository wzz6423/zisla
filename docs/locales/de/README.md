# zisla

**Deutsch** | [Dokumentationssprachen](../README.md)

**zisla ist ein nativer macOS-Arbeitsbereich, der erscheint, wenn Sie ihn brauchen, und sich danach zurückzieht.** Bewegen Sie den Zeiger zur oberen Bildschirmmitte, um einen schlanken Bereich für laufende KI-Arbeit, Medien, Dateiübergabe, Downloads und Desktop-Werkzeuge zu öffnen. Displays ohne Notch nutzen denselben simulierten Statusbereich.

Aktuelle Implementierung: **macOS 14+**. Apple Silicon ist die unterstützte Konfiguration; Intel-Veröffentlichungspakete können funktionieren, ihre Kompatibilität ist jedoch nicht garantiert.

[Vollständige Funktionsvorstellung ansehen — 2:40 · 1080p / 60 fps](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

[![zisla-Einführungsfilm ansehen](../../../web/public/media/zisla-launch-poster.webp)](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

Musik: „Funkorama“ von Kevin MacLeod · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Quelle](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474).

## Warum es an den oberen Bildschirmrand gehört

- **Bei Bedarf, ohne den Fokus zu übernehmen.** Klappen Sie den Bereich vom oberen Rand aus auf, heften Sie ihn bei Bedarf an und arbeiten Sie in der aktuellen App weiter.
- **Ein Ort für laufende Arbeit.** Sehen Sie Wiedergabe, KI-Aufgaben, Downloads, Timer, E-Mails, Systemstatus und Batteriedetails, ohne ein vollständiges Dashboard zu öffnen.
- **KI-Aktivität ohne Zugriff auf Gespräche.** zisla liest ausschließlich strukturierte Ereignisse und lokale Aktivitätsmetadaten, die zur Ermittlung des Aufgabenstatus nötig sind. Prompts und Antwortinhalte werden niemals gelesen.
- **Die Steuerung bleibt lokal.** Module, Zwischenablageverlauf und Linkerkennung besitzen unabhängige Schalter; Berechtigungen werden erst bei der ersten Nutzung einer Funktion angefordert.

## Was es kann

### Desktop-Arbeit in Bewegung halten

| Funktion | Beschreibung |
| --- | --- |
| Aktuelle Wiedergabe | Zeigt Cover, Titel, Fortschritt, Liedtext und Wiedergabesteuerung; fehlen Metadaten, kann Core Audio die tatsächlich Audio ausgebende App erkennen. |
| Übergabe und Teilen | Legen Sie Dateien, Medien oder Links im oberen Auslösebereich ab, um sie in der Übergabeablage zu behalten, im Finder anzuzeigen oder das macOS-Teilen-Menü zu öffnen. Komprimieren Sie ausgewählte Dateien und Ordner zu ZIP, ändern Sie die Größe ausgewählter Bilder oder konvertieren Sie sie in den Bildwerkzeugen und legen Sie erfolgreiche Ergebnisse wieder in die Ablage, oder importieren Sie ausgewählte Bilder, Videos und Audiodateien in die Medienbibliothek des Aufnahmestudios, während dessen aktuelles Projekt und Zeitleiste erhalten bleiben. |
| Zwischenablage und Mitteilungen | Zeichnet optional den lokalen Zwischenablageverlauf auf, erkennt neue Links lokal und zeigt Medien, KI-Aktivität, Browserdownloads, Timer, E-Mails und Updates im eingeklappten Zustand. Optionale Schnellaktionen zeigen nach jedem Kopieren eine kleine Inselmitteilung mit ausführlicher Vorschau und passenden Aktionen: öffnen, im Finder anzeigen, suchen, übersetzen, berechnen und speichern. Nach einem abgeschlossenen Browserdownload oder empfangenen AirDrop-Datei kann derselbe Kurzbefehl den Ordner öffnen. Neue Verlaufsbilder werden zur Texterkennung auf dem Gerät eingereiht; suchen Sie ihren Text, um das Originalbild zu finden, oder klicken Sie mit der rechten Maustaste auf ein Bild, um seinen Text zu erkennen oder zu kopieren. |
| Täglicher Arbeitsbereich | Enthält Wetter, Kalender, Erinnerungen, Mail.app, in Apple Notizen gespeicherte Markdown-Notizen, Sperrbildschirminformationen und optionale Desktop-Haustiere. |

### KI-Arbeit sichtbar machen

zisla überwacht lokale Aktivität von Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, Delta, Orca, TRAE, OpenCode, Harnext, WorkBuddy, WorkBuddy AI und weiteren unterstützten Quellen. Es zeigt Aufgaben, Status, Token-Trends, Beitrags-Heatmaps und seitliche Mitteilungen.

Bei Werkzeugen ohne stabile lokale Aktivitätsquelle können Skripte, CI und Werkzeug-Hooks über `zislactl` Fortschritt, Nutzung und Mitteilungen melden; der Protokollstatus bleibt auf diesem Mac. Die Einstellungen können außerdem verbreitete KI-CLIs erkennen, installieren, aktualisieren und entfernen sowie lokale Skills verwalten. Anbieter und Befehle stehen in der [CLI-Integrationsreferenz](mac/Docs/cli-reference.md).

### Nützliche kleine Aufgaben erledigen

| Bereich | Enthaltene Werkzeuge |
| --- | --- |
| Downloads und Dokumente | Video- und Audiodownloads mit `yt-dlp`; lokale PDF-Zusammenführung, Aufteilung, Drehung, Zuschnitt, Konvertierung, Darstellung, Textexport, Wasserzeichen, Seitenzahlen, Verschlüsselung, Entsperrung und Metadatenbearbeitung. |
| Konzentration und Präsentation | Pomodoro-Timer mit einem Signalton und einer lokalen Mitteilung bei Sitzungsende, Wachhaltemodus, Verhinderung des Ruhezustands bei Inaktivität, Bildschirm- und Tastaturreinigung, Teleprompter und Kameraspiegel. |
| System und Batterie | Informationen zu CPU, GPU, Arbeitsspeicher, Datenträger, Netzwerk, Lüfter und Batterie sowie Bereinigung sicher entfernbarer Caches und Protokolle. |
| Spracheingabe | Globale Kurzbefehle zum Aufnehmen und Transkribieren, optionale lokale oder entfernte Aufbereitung von Transkripten und lokaler Sprachverlauf. |

### Aktuelle Zugänge und Abläufe

Die Insel hat 12 Module: Startseite, Übergabe, Zwischenablage, KI-Überwachung, Tastaturklänge, Downloads, Terminplan, E-Mail, Notizen, Anwendungslautstärkemixer, Werkzeuge und System. Batteriedetails stehen unter System; die Sperrbildschirmdarstellung ist separat. Öffnen Sie PDF-, Bild- und Audiowerkzeuge in den Einstellungen und das Aufnahmestudio dort oder über die Menüleiste.

- **Aufnahme und Gestaltung:** Nehmen Sie ein Display, Fenster oder einen Bereich auf, optional mit Systemaudio, Mikrofon und Kamera. Bearbeiten Sie Untertitel, Zooms, Porträt- und Stimmeffekte über mehrere Spuren, sehen Sie eine Vorschau an und exportieren Sie Video, GIF, Live Photo oder Audio. Bildwerkzeuge bieten 9 lokale Vorgänge, Audiowerkzeuge 27.
- **Mischen und Wiedergabe:** macOS 14.4+ unterstützt Lautstärke und Stummschaltung pro App. Wählen Sie die Audioausgabe im Medienbereich und Player-Präferenzen in den Einstellungen.
- **Desktop und Besprechungen:** Fenstervorschauen im Dock und mit Command+Tab, Kontextnotizen für Webseiten/Fenster/Desktop, ein 10-minütiger Besprechungs-Countdown, Beitritt und verknüpfte Notizen. Schütteln Sie den Zeiger beim Ziehen von Dateien, um das Ablageziel einzublenden.
- **Tagesbericht:** 8 Vorlagen, Vorschau, manueller oder geplanter PNG-Export, ausgewählte Messwerte und eigener Speicherordner.
- **KI-Konten:** Zeigt verfügbare Kontingente unterstützter Konten, Zurücksetzungszeiten, Hinweise bei geringem Kontingent und Stichprobenzeiten; exportiert den lokalen Token-Verlauf als `.xlsx`. Die Gemini- und Claude/GPT-Kontingente von Antigravity werden unabhängig überwacht, angezeigt und gemeldet. Gemini App nutzt für Chat-Kontingente ein Web-Cookie desselben Google-Kontos; Gemini CLI bleibt getrennt.
- **Schnellaktionen:** Popup-Aktionen verwenden `Command+1` bis `Command+0` in ihrer Reihenfolge. Der zusätzliche Standardauslöser für neue Konfigurationen ist `Command+N` für die erste Aktion. Aktualisierungen behalten gespeicherte Kurzbefehle und gelöschte Auslöser bei.

Die [Benutzerhilfe](https://wzz6423.github.io/zisla/help.html?lang=de#help) bietet neun Schrittanleitungen: Zwischenablage, Aufnahme, Ablage, Besprechungen, KI, Medienwerkzeuge, Tagesberichte, Desktop-Notizen/Fenstervorschauen und Wiedergabe/Mixing. Der [macOS-Leitfaden](mac/README.md) nennt Speicherordner und Abhängigkeiten der Werkzeuge.

## Einstieg

### App installieren

Laden Sie die neueste DMG von [GitHub Releases](https://github.com/wzz6423/zisla/releases) oder [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), binden Sie sie ein und ziehen Sie `zisla.app` nach `Applications`.

Alternativ können Sie Homebrew verwenden:

```bash
brew install --cask wzz6423/tap/zisla
```

Homebrew lädt den passenden Build für Ihren Chip, sodass Apple-Silicon- und Intel-Macs jeweils nur ihre eigene Architektur herunterladen. Der Cask stammt aus dem Drittanbieter-Tap `wzz6423/tap` statt aus Homebrews eigenem Cask-Repository; mit der Installation vertrauen Sie diesem Tap.

Bewegen Sie nach dem Start den Zeiger zur oberen Mitte des aktuellen Bildschirms oder wählen Sie **Insel anzeigen** im Menüleistensymbol. Die Pakete sind nicht notarisiert; unabhängig von der Installationsmethode ist beim ersten Start **Dennoch öffnen** unter **Systemeinstellungen > Datenschutz & Sicherheit** nötig, oder Sie entfernen das Quarantäneattribut selbst:

```bash
xattr -d com.apple.quarantine /Applications/zisla.app
```

### App aktualisieren

zisla aktualisiert sich unabhängig von der Installation mit Sparkle. Für Homebrew gilt: `brew upgrade` ersetzt die App nur, wenn die installierte Kopie tatsächlich älter als die Tap-Version ist, weil Homebrew ab 5.1.6 die Version im App-Bundle liest. So behindert Homebrew Sparkle nicht und lässt auch keine veraltete Installation zurück. Bei ausdrücklicher Angabe des Casks gelten stattdessen Homebrews Installationsaufzeichnungen; dadurch kann eine durch Sparkle aktualisierte App wieder auf die Tap-Version gesetzt werden:

```bash
brew upgrade --cask zisla
```

Der Tap enthält nur stabile Veröffentlichungen; Preview-Builds bleiben auf Releases, damit `brew upgrade` niemals auf eine Vorabversion wechselt. Die ausdrückliche Angabe des Casks ersetzt eine Preview durch den aktuellen stabilen Build. Sparkle führt selbst niemals Downgrades durch; nach Rückkehr zu Release bleibt die Preview installiert, bis eine stabile Veröffentlichung sie überholt. `brew uninstall --cask zisla` entfernt die App; `brew uninstall --zap --cask zisla` entfernt auch ihre lokalen Daten.

### Aus dem Quellcode starten

Swift 6 / Xcode 16+ ist erforderlich; auch die Command Line Tools allein können das Projekt bauen.

```bash
cd mac
swift run zisla
```

Der Downloader benötigt `yt-dlp`; `ffmpeg` ist optional. Office-zu-PDF-Konvertierung benötigt LibreOffice oder OpenOffice. Hinweise zu Build, Tests und Paketierung stehen im [macOS-Entwicklungsleitfaden](mac/README.md).

## Für ungestörtes Arbeiten gestaltet

- Unterstützt mehrere Displays, Spaces und gewöhnliche Vollbild-Apps, ohne die aktuelle App zu aktivieren oder ihr den Fokus zu nehmen.
- Im verborgenen Zustand gibt es keine dauerhafte transparente Auslösefensterfläche und keine Bildschleife; globale Ereignisüberwachung und Geometrieprüfungen lösen das Aufklappen aus.
- Nutzt ein Systemmaterial und wechselt bei aktivierter Transparenzreduzierung zu einem undurchsichtigen Hintergrund.
- Erkennt eine physische Notch anhand des sicheren Systembereichs; externe Displays ohne Notch erhalten ein Overlay mit demselben Umriss.

Die [Architektur- und Leistungsplanung](mac/Docs/architecture.md) erläutert die Implementierungsentscheidungen.

## Datenschutz und Berechtigungen

zisla fordert eine Berechtigung erst an, wenn eine aktivierte Funktion sie erstmals benötigt. Module können jederzeit in den Einstellungen deaktiviert und Berechtigungen in den macOS-Systemeinstellungen widerrufen werden.

| Bereich | Grenze |
| --- | --- |
| KI-Aktivität | Liest nur strukturierte Ereignisse und lokale Aktivitätsmetadaten. Prompts und Antwortinhalte werden niemals gelesen. |
| Zwischenablage und Dateien | Verlauf, Linkerkennung und Schnellaktionen haben separate lokale Schalter; Schnellaktionen behandeln abgeschlossene Browserdownloads und empfangene AirDrop-Dateien unabhängig vom Downloadfortschrittschalter. Die Erkennung läuft vollständig auf dem Gerät; Links und Aktionen werden erst nach ausdrücklichem Klick oder Auslöserdruck geöffnet beziehungsweise ausgeführt. Die Übergabe nutzt sicherheitsbezogene Lesezeichen und kopiert die Originaldatei nicht. |
| Notizen, E-Mail und Sprache | Notizen und E-Mail nutzen AppleScript/JXA mit Automatisierungsberechtigung. Sprachaufnahme läuft nur während aktiver Nutzung; die Transkriptaufbereitung sendet Text ausschließlich an das gewählte lokale Modell, den entfernten Anbieter oder das CLI-Profil. |
| Browserdownloads und Medien | Nutzt öffentliche macOS-Dateifortschrittsinformationen, MediaRemote-Metadaten und Core-Audio-Ausgabestatus. Browser-Verlaufsdatenbanken werden nicht gelesen. Systemwellenformen und App-Mixing verarbeiten Audio lokal; Aufnahmen speichern Audio nur bei aktivierter entsprechender Quelle. |
| Netzwerk | Wetter, öffentliche IP-Abfrage, Update-Spiegelwahl, Downloads, aktivierte KI-Kontingentprüfungen und Abhängigkeits-/CLI-Installation kontaktieren ihre Dienste. Optionale Übersetzung, Sprachbereinigung und KI-Aufnahmebearbeitung nutzen den gewählten Anbieter oder die CLI. Apple-Spracherkennung kann je nach System und Sprache das Netzwerk verwenden. |

### Berechtigungen nach Funktion

zisla fordert die nötige Freigabe bei der ersten Nutzung an. Haben Sie sie zuvor verweigert, öffnen Sie den entsprechenden Eintrag unter **Systemeinstellungen > Datenschutz & Sicherheit** und erlauben Sie `zisla`; die Namen können sich zwischen macOS-Versionen unterscheiden.

| Berechtigung oder Systemeinstellung | Wann sie nötig ist | Freigegebener Umfang |
| --- | --- | --- |
| Gerätesteuerung und Datenzugriff (in einigen Versionen Bedienungshilfen) | Automatisches Einfügen von Sprachtranskripten in das Textfeld der aktuellen App | Liest und findet Eingabefelder ohne Passwortschutz und überträgt das Transkript über Bedienungshilfen-APIs oder `Cmd+V`. Ohne Freigabe wird es weiterhin in die Zwischenablage kopiert. |
| Mikrofon | Spracheingabe oder Aktivierung des Studiomikrofons | Erfasst das ausgewählte Mikrofon für Aufnahme oder aktiviertes Monitoring. |
| Spracherkennung | Umwandlung aufgenommener Sprache in Text | Verarbeitet nur aktiv aufgenommene Sprache. Spracheingabe benötigt sowohl Mikrofon- als auch Spracherkennungsfreigabe. |
| Festplattenvollzugriff | E-Mail-Anzeige, während Mail.app nicht läuft | Liest den lokalen Index unter `~/Library/Mail` für Konten, Absender, Betreff, Zusammenfassungen, Zeitstempel und Lesestatus. Dieser Zugriff auf den Mail-Index benötigt die Freigabe. |
| Automation | Mail.app-Nachrichten lesen, verfassen, beantworten, markieren oder löschen; Apple Notizen lesen und schreiben | Erlaubt zisla die Steuerung der betreffenden System-Apps. Mail- und Notizenfreigaben lassen sich getrennt widerrufen. |
| Kalender; Erinnerungen | Nutzung des Terminmoduls | Liest und verwaltet Kalenderereignisse und Erinnerungen mit getrennten Freigaben. |
| Ortungsdienste | Wetter am aktuellen Standort | Fragt den Standort einmal ohne dauernde Verfolgung ab. Manuell hinzugefügte Orte benötigen keinen Standortzugriff. |
| Kamera | Spiegel oder Kameravorschau/-aufnahme des Studios | Verwendet die ausgewählte Kamera nur während die entsprechende Funktion aktiv ist. |
| Eingabeüberwachung | Tastaturklänge, Tippstatistik, Tastaturreinigung sowie reine Modifikatortasten- oder Maus-Seitentasten-Kurzbefehle | Beobachtet Ereignisse der aktivierten Funktion; Tippstatistiken bleiben lokal. Gewöhnliche globale Kurzbefehle benötigen diese Berechtigung nicht. |
| Bluetooth | Zubehörbatterien unter System → Batterie | Liest ausschließlich öffentlich verfügbare Batterieinformationen verbundener oder gekoppelter Geräte. |
| Bildschirm- und Systemaudioaufnahme (auf älterem macOS Bildschirmaufnahme) | Screenshots, Fenstervorschauen, Aufnahmen, Systemaudio-Wellenformen und App-Mixer | Liest Bildschirmbilder und gewählte Audioquellen. Aufnahmen speichern aktivierte Quellen lokal; der Mixer benötigt macOS 14.4+. |
| Mitteilungen | Pomodoro-Hinweise | Spielt bei Timerende einen Signalton und zeigt eine lokale Mitteilung. |
| Vom Benutzer gewählte Ordner (keine manuelle Freigabe nötig) | Dateiübergabe, Import/Export oder Downloadordnerwahl | Der Systemdateidialog gibt Zugriff auf den gewählten Ordner. Diese Funktionen benötigen keinen Festplattenvollzugriff. |

Ein Widerruf deaktiviert nur die betreffende Funktion. Bleibt sie nach einer Einstellungsänderung unzugänglich, beenden und öffnen Sie zisla erneut und versuchen es nochmals.

Der [macOS-Leitfaden](mac/README.md) beschreibt das vollständige Berechtigungs- und Netzwerkverhalten.

## Dokumentation

| Dokument | Zweck |
| --- | --- |
| [macOS-Entwicklungsleitfaden](mac/README.md) | Module, KI-Integration, Abhängigkeiten, Build, Tests, Berechtigungen und Systemgrenzen. |
| [Website-Leitfaden (Englisch)](../../../web/README.md) | Lokale Entwicklung, Produktionsbuilds und aktuelle Downloadlinks. |
| [Einführungsfilm-Leitfaden (Englisch)](../../../promo/README.md) | Remotion-Vorschau, Rendering, Kompositionen, Musik und Ressourcenlizenzen. |
| [Architektur- und Leistungsplanung](mac/Docs/architecture.md) | Auslösung am oberen Rand, Fensterverhalten, Nebenläufigkeit, Medien und Downloadsicherheit. |
| [CLI-Integrationsreferenz](mac/Docs/cli-reference.md) | `zislactl`-Anbieter, Befehle, Felder und Exit-Codes. |
| [Signatur- und Veröffentlichungsplanung](mac/Docs/releasing.md) | Signierung, Notarisierung, DMGs, Updatekanäle und Veröffentlichungsabnahme. |
| [Beitragsleitfaden](CONTRIBUTING.md) | Entwicklungsumgebung, Branches, Commits und Pull-Request-Anforderungen. |

## Beiträge

Issues und Pull Requests sind willkommen. Lesen Sie zuerst den [Beitragsleitfaden](CONTRIBUTING.md). Melden Sie Sicherheitsprobleme vertraulich über [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), statt ein öffentliches Issue zu öffnen.

## Lizenz

[PolyForm Noncommercial License 1.0.0](../../../LICENSE.md). Nichtkommerzielle Nutzung ist erlaubt; der Verkauf dieser Software oder jede andere kommerzielle Nutzung ist untersagt.
