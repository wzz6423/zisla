# zisla für macOS

**Deutsch** | [Dokumentationssprachen](../../README.md)

Dieses Verzeichnis enthält die macOS-Implementierung von zisla. Bewegen Sie den Zeiger zur oberen Bildschirmmitte, um die Insel aufzuklappen, und weg, um sie zu verbergen. Die App nutzt AppKit `NSPanel`, SwiftUI und ereignisgesteuerte Dienste ohne dauerhaftes transparentes Auslösefenster und ohne Bildschleife im verborgenen Zustand.

Swift-Targets, Bundle-ID, lokaler Datenordner und `zislactl` verwenden alle den Bezeichner zisla. Updates migrieren lokale Daten und Einstellungen älterer Versionen automatisch.

macOS 14 und neuer werden unterstützt. macOS 26 nutzt Liquid Glass; macOS 14/15 greifen auf das native Systemmaterial zurück.

## Funktionen

### 12 Inselmodule

| Modul | Umgesetzte Funktionen |
| --- | --- |
| Startseite | Fasst bei Bedarf den aktuellen Pomodoro-Timer, die erste aktive KI-Aufgabe, native Downloads und den Fortschritt mehrerer Browserdownloads zusammen. |
| Tastaturklänge und Statistik | 20 integrierte Tastaturklänge; lokale Tippstatistik, Trends, Anwendungszeitleiste und Heatmap pro Taste lassen sich unabhängig umschalten. |
| Übergabe | Ziehen Sie Dateien, Medien oder Links in den oberen Auslösebereich, um sie in der Ablage zu behalten, im Finder anzuzeigen oder das Teilen-Menü zu öffnen. Abgelegte Screenshots haben blaue Karten doppelter Breite und eine eigene Kategorie mit Bildkopie, PNG-Export und Löschen. Komprimieren Sie ausgewählte Dateien und Ordner zu ZIP, ändern Sie die Größe ausgewählter Bilder oder konvertieren Sie sie in den Bildwerkzeugen und legen Sie erfolgreiche Ergebnisse wieder in die Ablage, oder importieren Sie ausgewählte Bilder, Videos und Audiodateien in die Medienbibliothek des Aufnahmestudios, während dessen aktuelles Projekt und Zeitleiste erhalten bleiben. |
| Zwischenablage | Speichert einen durchsuchbaren lokalen Verlauf, filtert nach Bild, URL und Datei und markiert Favoriten; Verlauf und Linkerkennung haben unabhängige Schalter. Neue Verlaufsbilder werden zur Texterkennung auf dem Gerät eingereiht; suchen Sie ihren Text, um das Originalbild zu finden, oder klicken Sie mit der rechten Maustaste auf ein Bild, um seinen Text zu erkennen oder zu kopieren. Laufende Erkennung lässt sich abbrechen; Hintergrund-Erkennung kopiert Text nicht automatisch. |
| KI-Überwachung | Bündelt aktive Aufgaben, Status, Token-Trends, Beitrags-Heatmaps und seitliche Hinweise unterstützter CLIs, Desktop-Apps und IDEs. |
| Downloads | Nutzt `yt-dlp` für Video und Audio; ohne `ffmpeg` verpackt AVFoundation kompatible Spuren, und ein schreibgeschützter Bilibili-Ausweichweg steht bereit. |
| Terminplan | Zeigt Wetter am aktuellen Standort und bis zu sechs gespeicherten Orten; Kalenderereignisse und Erinnerungen ansehen, erstellen und löschen sowie Erinnerungen abschließen. Die Aktualisierungszeit der Wetterliste steht in der Kopfzeile links neben der Schaltfläche zum Aktualisieren. Bei unvollständigen Wetterdaten ergänzen weitere Quellen das vollständigste Ergebnis. Verfügbare Teilinformationen bleiben erhalten, wenn die übrigen Daten nicht abrufbar sind. |
| E-Mail | Liest ausgewählte Mail.app-Konten, zeigt Posteingänge, markiert Nachrichten als gelesen, beantwortet und verfasst E-Mails und verschiebt sie in den Papierkorb. |
| Notizen | Nutzt ausschließlich Apple Notizen als Datenquelle für Anzeige, Bearbeitung, Erstellung und Löschung von Markdown-Notizen mit Live-Vorschau und automatischem Zurückschreiben. |
| Anwendungslautstärkemixer | Unter macOS 14.4+ Lautstärke jeder wiedergebenden App einstellen, stummschalten und merken; benötigt Systemaudioaufnahmeberechtigung. |
| Werkzeuge | Pomodoro-Timer mit einem Signalton und einer lokalen Mitteilung bei Sitzungsende, Wachhaltemodus, Verhinderung von Inaktivitätsruhe, Bildschirm- und Tastaturreinigung, Teleprompter, Kameraspiegel und bestätigtes Leeren des Papierkorbs. Der Timername gilt nur für die aktuelle Sitzung und wird nach deren Ende oder Abbruch auf den Standardnamen zurückgesetzt. In der eingeklappten Insel zeigt eine Sonne an, dass das Display eingeschaltet bleibt. Ein Laptop zeigt an, dass der Mac bei Inaktivität nicht in den Ruhezustand wechselt. |
| System | Zeigt CPU, GPU, Speicher, Datenträger, Netzwerk, Temperatur und Lüfterstatus; gibt Speicher frei und prüft sicher entfernbaren Cache, Protokolle und temporäre Daten; enthält Batteriezustand und Zubehörladestände. |

### Modulübergreifende Funktionen

- **Aktuelle Wiedergabe:** MediaRemote zeigt Cover, Titel, Fortschritt, laufenden Liedtext und Steuerung; Core Audio erkennt ersatzweise die tatsächliche Audioquelle. Pausierte, gestoppte und stumme Quellen werden verborgen.
- **Browserdownloads:** Zeigt Quelle und Fortschritt für Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera und Arc auf der Startseite, im eingeklappten Zustand und in seitlichen Hinweisen.
- **Spracheingabe:** Unterstützt Umschalt- oder Push-to-talk-Kurzbefehle, eigene globale Kurzbefehle, Systemspracherkennung, lokale oder entfernte Transkriptaufbereitung und lokalen Aufnahmeverlauf.
- **Schnellaktionen:** Nach jedem Kopieren erscheint eine kleine Inselmitteilung mit ausführlicher Vorschau und passenden Folgeaktionen: Links öffnen, Dateien im Finder zeigen, mit wählbarer Suchmaschine suchen, übersetzen, berechnen, Termine aus erkannten Daten anlegen und langen Text oder Bilder speichern. Nach Browserdownload oder AirDrop-Empfang öffnet derselbe Kurzbefehl den Zielordner; dies wird unabhängig vom Downloadfortschritt durch Schnellaktionen gesteuert. Erkennt URLs, Dateipfade, E-Mail-Adressen, Telefonnummern, CSS-Farben mit Farbvorschau, Rechenoperationen, Datum und Uhrzeit, Text in anderer Systemsprache, Code, einfachen Text mit Zählwerten, Bilder mit Miniaturen und Dateireferenzen. Auslöser sind Aktionsschaltflächen, der zusätzliche Standardkurzbefehl Command+N oder konfigurierte Modifikatortasten/Maus-Seitentasten. Außerdem gibt es eine standardmäßig ausgeschaltete Kopiergeste mit gehaltenem linken und gedrücktem rechten Mausknopf, eine App-Sperrliste, Erkennungsschalter pro Typ und einen schlanken Erinnerungsmodus.
- **CLI- und Skills-Verwaltung:** Erkennt, installiert, aktualisiert und entfernt verbreitete KI-CLIs und verwaltet lokale Skills in den Einstellungen.
- **Desktop-Haustiere:** Unter „Einstellungen → Haustier“ sehen Sie integrierte und importierte Tiere in der Vorschau. „Festes Haustier“ zeigt immer dasselbe Tier. „Zufälliger Wechsel“ lost standardmäßig unter allen Tieren aus. Unter „Haustiere für die Auslosung“ schränken Sie die Auswahl ein. Der Wechsel erfolgt standardmäßig um Mitternacht nach Ortszeit. Wählen Sie beim Wechselintervall „Eigen“, um eine Dauer zwischen 1 Sekunde und 99:59:59 einzustellen. Voreingestellt ist 1 Stunde. Platzieren Sie das Tier links oder rechts der Insel. Wenn Sie die Insel auf einem Bildschirm ausklappen, bleiben die Haustiere auf den anderen Bildschirmen an ihrem Platz.
- **Updates:** Der gewählte Release- oder Preview-Kanal ermittelt einmal pro App-Lauf den Ländercode des öffentlichen Netzausgangs. `CN` prüft zuerst den signierten Gitee-Appcast und versucht GitHub einmal; andere Ländercodes prüfen GitHub zuerst und versuchen Gitee einmal. Bei fehlender Abfrage bleibt Gitee zuerst. Sparkle lädt, prüft, installiert und startet Updates neu. Ein Kanalwechsel gilt für automatische und manuelle Prüfungen.
- **Darstellung und Bedienung:** Die Einstellungen folgen dem System oder nutzen helles beziehungsweise dunkles Design. Die Insel unterstützt transparente oder matte Flächen, angeheftetes Aufklappen, mehrere Displays, Spaces und externe Displays ohne Notch.
- **Voreinstellungen:** Neuinstallationen aktivieren Funktionsmodule standardmäßig. Jede Funktion, eingeklappte Anzeige, seitliche Mitteilung, Menüleistenkennzahl und das Updateverhalten sind einzeln einstellbar; bestehende Installationen behalten ihre Konfiguration.
- Bei mehreren angeschlossenen Bildschirmen lässt sich unter Einstellungen → Allgemein → Bildschirmmodi für jeden Bildschirm der Dynamic Island-Modus (Kameraposition oder eigene Position), der Notch-Modus oder das Ausblenden wählen. Bei einem Bildschirm ist diese Einstellung verborgen und die globale Darstellung gilt; beim erneuten Anschließen werden die gespeicherten Einstellungen wiederhergestellt. Auf allen eingeblendeten Bildschirmen bleibt die eingeklappte Insel gleichzeitig sichtbar. Aufklappen, Schnellaktionen, Aufnahmen und vorübergehende Meldungen ersetzen nur die Insel auf dem jeweiligen Bildschirm; die Auswahl der Benachrichtigungsbildschirme filtert Inhalte, ohne die inaktive Insel auszublenden.

### Eigenständige Werkzeuge und Abläufe

- **Aufnahmestudio:** Öffnen Sie es über die Menüleiste oder Einstellungen. Nehmen Sie Display, Fenster oder Bereich mit optionalem Systemaudio, Mikrofon und Kamera auf. Bearbeiten Sie Video, Audio, Bilder und Text auf mehreren Spuren mit Untertiteln, Zooms, Animationen sowie Porträt- und Stimmeffekten; prüfen Sie die Vorschau vor Export von Video, GIF, Live Photo oder Audio. Einige Formate benötigen FFmpeg; HDR-Aufnahme hängt von der Geräteunterstützung ab. Importieren Sie Bilder, Videos und Audio aus der Ablage in die Medienbibliothek und behalten Sie das aktuelle Projekt und die Zeitleiste.
- **Bild-, Audio- und PDF-Werkzeuge:** Öffnen Sie die eigenständigen Werkzeuge in den Einstellungen. Bilder bieten 9 lokale Vorgänge und Stapel-/ZIP-Export. Audio bietet 27 Vorgänge einschließlich Mixing, LUFS-Normalisierung und Rauschbearbeitung und benötigt FFmpeg sowie ffprobe. PDF bietet 14 Vorgänge; Office-Konvertierung benötigt LibreOffice oder OpenOffice.
- **Tagesbericht:** Wählen Sie aus 8 Vorlagen und bestimmen Sie Kennzahlen in den Einstellungen, prüfen Sie eine Vorschau und exportieren Sie PNG manuell oder zu einer täglichen Uhrzeit. Fehlende Kennzahlen werden nicht als gemessene Null dargestellt.
- **Fenstervorschauen:** Bewegen Sie den Zeiger über das Dock oder wechseln Sie mit Command+Tab, dann aktivieren Sie ein Fenster per Klick auf seine Vorschau. Funktion und Berechtigungen stehen in den Einstellungen.
- **Kontextnotizen und Besprechungen:** Halten Sie den Notizkurzbefehl und schütteln Sie den Zeiger, um eine Notiz mit Webseite, Fenster oder Desktop zu verknüpfen. Kalendereinträge mit Besprechungslinks zeigen 10 Minuten vor Beginn einen Countdown; beitreten, eine Notiz erstellen oder eine vorhandene verknüpfen. Kontextnotizen werden in der Ablage verwaltet.
- **Schütteln zum Ablegen:** Schütteln Sie den Zeiger beim Ziehen von Dateien, um das Ablageziel zu zeigen; die Geste lässt sich unabhängig einstellen.
- **Audioausgabe und Player-Präferenzen:** Wählen Sie ein Ausgabegerät im Medienbereich. Die Einstellungen wählen automatische Quelle oder bevorzugten Player, kompakte Medienansicht und Stoppbedingungen für Umgebungsgeräusche.
- **KI-Kontingente und Rücksetzungen:** KI-Überwachung und Einstellungen zeigen unterstützte Kontingente, Stichproben- und Rücksetzungszeiten sowie Niedrigkontingenthinweise, einschließlich verfügbarer 5h/7d-Fenster und Cursor-USD-Budgets. Diese Daten sind vom lokalen Token-Verlauf getrennt. Die Gemini- und Claude/GPT-Kontingente von Antigravity werden unabhängig überwacht, angezeigt und gemeldet. Gemini App nutzt für Chat-Kontingente ein Web-Cookie desselben Google-Kontos; Gemini CLI bleibt getrennt.

### Tastenreihenfolge der Schnellaktionen

Das Schnellaktions-Popup vergibt `Command+1` bis `Command+9`, danach `Command+0`, in der aktuellen Aktionsreihenfolge. Der zusätzliche Standardauslöser für neue Konfigurationen ist `Command+N` für die erste Aktion; `Command+Delete` schließt das Popup. Stellen Sie Auslöser, Maus-Seitentaste und Reihenfolge in den Einstellungen ein. Aktualisierungen behalten jede ausdrücklich gespeicherte Kombination, darunter das alte `Command+1`, eigene Kurzbefehle und gelöschte Auslöser; nur neue Konfigurationen oder ein fehlendes Auslöserfeld übernehmen `Command+N`.

### Menüleistenverwaltung

Öffne Einstellungen → Sonstige → Menüleistenverwaltung. Schalte den Schalter neben einem Symbol aus, um es auszublenden, oder wieder ein, um es anzuzeigen. Ausgeblendete Symbole bleiben in der Liste. Für Symbole anderer Apps ist der Zugriff auf die Bedienungshilfen erforderlich.

### Speicherorte

Einstellungen → Speicherort wählt separate Ordner für Downloads, Screenshots, Bildwerkzeuge, Aufnahmen, PDF, Schnellaktionen und Tagesberichte. Neue Konfigurationen verwenden Unterordner von `~/Downloads`: `picture` für Screenshots/Bilder, `video` für Aufnahmen, `pdf`, `quick` und `daily`. Audiowerkzeuge wählen Datei oder Ordner über einen Exportdialog. Ablagedateien behalten Verweise auf die Originale; abgelegte Screenshots und Kontextnotizstatus werden lokal unter `~/Library/Application Support/zisla` verwaltet, Aufnahmeprojekte im Aufnahmeordner. Schnellnotiztext liegt in Apple Notizen.

[Benutzerhilfe und Schrittanleitungen](https://wzz6423.github.io/zisla/help.html?lang=de#help) behandeln neun Themen: Zwischenablage, Aufnahme, Ablage, Besprechungen, KI, Medienwerkzeuge, Tagesberichte, Desktop-Notizen/Fenstervorschauen und Wiedergabe/Mixing, mit kurzen Filmausschnitten.

### Screenshot-Kurzbefehle und Ablage

Die Aktion **Ablegen** in der Screenshot-Leiste steht zwischen **Anheften** und **Kopieren**. Sie speichert das fertig bearbeitete Bild einschließlich Anmerkungen und abgeschlossener Scroll-Aufnahmen in der Übergabeablage, ohne es in die Zwischenablage zu kopieren. PNG und Aufnahmemetadaten mit Ursprungs-App und Aufnahmezeit werden lokal in SQLite gespeichert und überstehen App-Neustarts. Die Kategorie **Abgelegte Screenshots** zeigt nur diese Karten.

**Textmarker** folgt auf **Pinsel** und zeichnet transparente Markierungen; Endlinien und kreisförmige Marken bleiben standardmäßig erhalten und lassen sich im Menü deaktivieren. **Extrahieren** folgt auf **Weichzeichnen** und bietet macOS-Motiv- oder Hintergrundextraktion sowie freie Auswahl beliebiger Bereiche. Mehrere Schleifen erhalten ihre vereinigten Bereiche; Alles auswählen und Leeren stehen bereit. Nicht gewählte Pixel werden transparent, die Extraktion lässt sich rückgängig machen. Screenshot-Ecken haben standardmäßig Radius 0. Ziehen Sie den Radiusgriff oberhalb der Auswahl oder nutzen Sie **Eckenradius**; die Größenmarke zeigt `r`. PNG-Exporte haben transparente Ecken, und Radius 0 stellt die ursprünglichen Eckpixel wieder her.

| Kontext | Aktion | Standardkurzbefehl |
| --- | --- | --- |
| Global | Screenshot | `Control+1` |
| Global | Scroll-Screenshot | `Control+2` |
| Screenshot-Editor | Anheften | `Control+1` |
| Screenshot-Editor | Ablegen | `Control+2` |
| Screenshot-Editor | Rechteck | `Control+3` |
| Screenshot-Editor | Ellipse | `Control+4` |
| Screenshot-Editor | Pinsel | `Control+5` |
| Screenshot-Editor | Textmarker | `Control+6` |
| Screenshot-Editor | Pfeil | `Control+7` |
| Screenshot-Editor | Nummer | `Control+8` |
| Screenshot-Editor | Text | `Control+9` |
| Screenshot-Editor | Weichzeichnen | `Control+0` |
| Screenshot-Editor | Extraktion | `Control+A` |
| Screenshot-Editor | Scroll-Aufnahme | `Control+B` |
| Screenshot-Editor | Kopieren | `Enter` |
| Screenshot-Editor | Speichern | `Command+S` |
| Screenshot-Editor | Rückgängig | `Command+Z` |
| Screenshot-Editor | Wiederholen | `Command+Shift+Z` |

Screenshot-Einstellungen zeigen und erfassen globale und Editor-Kurzbefehle. Kopieren, Speichern, Rückgängig und Wiederholen werden angezeigt, lassen sich aber nicht neu aufzeichnen. Benutzerkurzbefehle bleiben beim Update erhalten; Anheften ist eine Editoraktion statt eines eigenen globalen Kurzbefehls, der Menüeintrag bleibt bestehen.

Standard-Editor-Kurzbefehle folgen der Werkzeugreihenfolge: `Control+1` bis `Control+9`, dann `Control+0`, `Control+A`, `Control+B` und weitere Buchstaben. Die Standardvergabe überspringt `Q`, `M`, `N` und `W`, weil versehentliches Command die App beenden oder Fenster minimieren, öffnen oder schließen könnte. Eigene aufgezeichnete Kombinationen sind weiterhin erlaubt.

Beim Update wechseln unveränderte ältere Belegungen, einschließlich der bisherigen Anheften/Ablegen-Belegung, einmal zu den obigen Standards. Wurde irgendein Screenshot-Kurzbefehl angepasst, bleibt die bestehende Belegung erhalten; neue Aktionen wählen bei Konflikten eine freie Control-Kombination in derselben sicheren Reihenfolge. Auch diese Anfangskombinationen lassen sich ändern.

## Schnellstart

### Umgebung

- macOS 14+
- Swift 6 / Xcode 16+ (Command Line Tools allein reichen auch zum Bauen)
- Optional: `yt-dlp` und `ffmpeg`; Office-zu-PDF benötigt zusätzlich LibreOffice oder OpenOffice

Mit Homebrew:

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### Aus dem Quellcode starten

```bash
swift run zisla
```

Die App startet als Menüleistenzubehör. Bewegen Sie den Zeiger in den 6 px hohen Bereich oben in der Mitte des aktuellen Displays oder wählen Sie „Insel anzeigen“ im Menüleistensymbol.

Um im Debug-Build alle 5 Sekunden zu wechseln, führen Sie im Stammverzeichnis des Repositorys `ZISLA_DEBUG_PET_ROTATION_SECONDS=5 make run` aus. Aktivieren Sie „Zufälliger Wechsel“ und wählen Sie mindestens zwei Tiere aus. Mit `make update` ohne die Variable gilt wieder das gespeicherte Intervall.

### Eine `.app` bauen

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

Zum Einpacken des offiziellen `yt-dlp`-Hilfsprogramms:

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh` lädt eine festgelegte offizielle eigenständige macOS-Datei, prüft sie gegen die offiziellen `SHA2-256SUMS` und installiert sie unter `Tools/yt-dlp`.

## KI-Werkzeugintegration

### Automatische Erkennung

zisla liest öffentliche oder stabile lokale Sitzungszustände unterstützter Werkzeuge und entnimmt ausschließlich strukturierte Ereignisse und lokale Metadaten zur Aufgabenstatusbestimmung. Prompts oder Antwortinhalte werden nicht gelesen.

| Umgebung | Automatische Erkennung |
| --- | --- |
| OpenAI / Anthropic | Codex CLI und Desktop, Claude Code und deren Hostumgebungen |
| GitHub / Google / xAI | GitHub Copilot CLI und VS Code, Gemini CLI und Desktop sowie Grok CLI |
| Unabhängige und regionale Werkzeuge | Pi, Kimi Code, Qwen Code, Qoder, ZCode Desktop und CLI, TRAE, OpenCode, Harnext/Harness und WorkBuddy |

Warten auf Freigabe oder Benutzerantwort ist gelb, Werkzeug- oder Befehlsfehler sind rot, normale Ausführung grün; gleichzeitige Quellen werden in der Reihenfolge rot, gelb, grün gruppiert. Der Qwen-Laufzeit-Sidecar gilt nur als aktiv, solange sein PID lebt, um veraltete Meldungen nach seinem Ende zu vermeiden.

Speichert eine Gesprächs-Desktop-App keine strukturierten Aktivitätsereignisse, kann das System eine geöffnete inaktive App nicht zuverlässig von einem gerade generierenden Modell unterscheiden. Solche Werkzeuge einschließlich ChatGPT sollten den folgenden `zislactl`-Hook nutzen; zisla täuscht keine Aktivität durch einen residenten Prozess vor.

### Lokales `zislactl`-Protokoll

`zislactl` schreibt Aufgabenstatus und Nutzungsverlauf in SQLite:

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

Nutzungsverlauf übersteht Neustarts, Austauschupdates und das Leeren von Aufgaben. Er geht nur verloren, wenn der Benutzer App-Daten manuell löscht.

Beispiel:

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

Kanonische Anbieter sind `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `zcode`, `trae`, `opencode`, `pi`, `harness` und `doubao`; verbreitete Aliase werden automatisch normalisiert. Rufen Sie die CLI aus Werkzeug-Hooks, Shell-Wrappern oder Aufgabenskripten auf.

KI-Ausführungsliste und eingeklappter Zustand verwenden das offizielle Logo jedes Werkzeugs zur Quellenkennung.

Das Protokoll steht in der [CLI-Integrationsreferenz](Docs/cli-reference.md).

## Browserdownloadfortschritt

zisla hört auf öffentliche macOS-Dateifortschrittsinformationen im Downloadordner und kombiniert temporäre Endungen, erweiterte Downloadquellenattribute und laufende Browser zur Quellenerkennung. Es liest keine Browser-Verlaufsdatenbanken und sendet keine Netzwerkabfragen für den Fortschritt; die Abschlussmarke bleibt etwa drei Sekunden sichtbar. Schnellaktionen verwenden dieselbe Ereignisquelle und bieten Ordner öffnen, sobald ein erfolgreicher Transfer sein endgültiges Ziel erreicht. Die Anzeigedauer folgt den Schnellaktionseinstellungen; die neueste Kopier- oder Transfermitteilung ersetzt die vorherige.

## Downloader

Ausführbare Dateien werden in dieser Reihenfolge aufgelöst:

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

Die URL wird als eigener argv-Wert an `Process` statt an eine Shell übergeben. Laufzeitkonfiguration und Plugins werden ignoriert, `--exec` deaktiviert, Einzelobjektgrenzen angewendet und der endgültige Dateipfad auf Verbleib im freigegebenen Ordner geprüft.

Ohne `ffmpeg`:

- Video bevorzugt AVC/MP4-Video und M4A-Audio und verpackt sie mit AVFoundation in MP4; ein Ein-Datei-Format bleibt unverändert.
- Audio bevorzugt M4A und behält andernfalls das Originalformat.
- Bei HTTP 412, fehlendem Format oder lokal fehlendem yt-dlp beschafft Bilibili DASH-Spuren über seine schreibgeschützte API und nutzt dieselbe native Verpackung ohne weiteres Werkzeug.

## Notizen

Markdown-Notizen in der Insel verwenden Apple Notizen als einzige Datenquelle. Sie können bestehende Notizen erstellen, ansehen, bearbeiten und löschen statt nur neue hinzuzufügen.

- **Liste:** Beim Einstieg liest JXA (`osascript -l JavaScript`) Titel und Änderungsdaten nicht gelöschter Notizen und sortiert nach letzter Änderung. Rückkehr aus Notizen aktualisiert die Liste; Zuletzt gelöscht bleibt verborgen. Wählen Sie eine Notiz zum Bearbeiten, aktualisieren oder erstellen Sie eine oder löschen Sie sie im Kontextmenü.
- **Ansehen und bearbeiten:** AppleScript liest das `plaintext` der gewählten Notiz, den Markdown-Quelltext, in den Editor. Der native `TextEditor` schreibt nach etwa 0,8 Sekunden Inaktivität zurück, damit nicht jeder Tastendruck AppleScript ausführt. Neue Notizen werden in Apple Notizen angelegt und ausgewählt.
- **Vorschau:** Der integrierte Blockparser stellt Überschriften, ungeordnete/geordnete/Aufgabenlisten, Zitate, Codeblöcke, Linien, Fett, Kursiv, Inline-Code, Durchstreichungen und Links als `AttributedString` dar.
- **Speicherung:** Markdown liegt als gewöhnlicher Text im `body` der Notiz, mit HTML-Escaping und erhaltenen Leerzeilen. `plaintext` stellt den Quelltext wieder her; Apple Notizen zeigt Klartext statt gerendertem Markdown.
- **Berechtigungen:** Der erste Lese- oder Schreibzugriff fordert macOS-Automatisierungszugriff auf Apple Notizen an; eine Ablehnung zeigt eine Fehlermitteilung in Liste oder Editor.

Das Notizenmodul hält keine zweite lokale Kopie; Apple Notizen ist das Speicherbackend.

## Berechtigungen und Datenschutz

- **Kalender:** Kalender- und Erinnerungsberechtigungen werden beim ersten Öffnen getrennt angefragt; Ereignisse und Erinnerungen aktualisieren sich nach Erstellung, Löschung oder Abschluss.
- **Standort:** Wetter fragt den Standort einmal ohne laufende Verfolgung ab; weitere Orte lassen sich in den Einstellungen suchen, speichern und entfernen.
- **Dateien und Downloads:** Vom Benutzer gewählte Ordner verwenden sicherheitsbezogene Lesezeichen; Übergabe kopiert das Original nicht.
- **Zwischenablage:** Neuinstallationen aktivieren Verlauf und Linkerkennung standardmäßig mit unabhängigen Schaltern. Bei jedem `changeCount` wird höchstens ein Link lokal erkannt; Abfrageparameter werden nicht protokolliert und keine Lösch-, Typdeklarations- oder Schreib-API aufgerufen, sodass die universelle Zwischenablage nicht ersetzt wird.
- **Schnellaktionen:** Laufen aktiviert lokal bei jedem `changeCount` und behandeln fertige Browserdownloads und AirDrop-Dateien. Reine Modifikatortasten und Maus-Seitentasten können Eingabeüberwachung benötigen; die optionale Kopiergeste sendet zusätzlich ein synthetisches ⌘C und braucht Bedienungshilfen. Erkennung nutzt niemals das Netzwerk; Öffnen, Suchen, Übersetzen und Speichern folgen erst auf ausdrücklichen Klick oder Auslöserdruck. App-Sperrliste und Typschalter steuern Kopierhinweise; der Schnellaktionsschalter steuert auch abgeschlossene Transfers.
- **KI-Status:** Automatische Erkennung liest ausschließlich strukturierte Ereignisse und lokale Metadaten zur Aufgabenstatusbestimmung.
- **Sprache:** Mikrofon und Spracherkennung werden nur nach ausdrücklicher Benutzeraktion genutzt. Aufnahmen, Rohtranskripte und aufbereiteter Text bleiben lokal verwaltet; aufbereiteter Text geht nur an das gewählte lokale Modell, den entfernten Anbieter oder das CLI-Profil, entfernte Zugangsdaten liegen in einer privaten Datenbank.
- **Bluetooth und Geräte:** Batterieinformationen von Zubehör und vertrauenswürdigen mobilen Apple-Geräten werden nur bei geöffneter Batterieansicht unter System gelesen.
- **Kamera und Eingabeüberwachung:** Spiegel und Studio-Kameravorschau/-aufnahme verlangen Kamerazugriff. Tastaturklänge, Tippstatistik, Reinigung und reine Modifikator-/Seitentasten-Auslöser nutzen Eingabeüberwachung; Statistiken bleiben lokal und die Schalter sind unabhängig.
- **Bildschirm und Systemaudio:** Screenshots, Aufnahmen und Vorschauen lesen Bildschirminhalte mit Bildschirmaufnahmeberechtigung. Aufnahmen speichern ausgewählte Quellen lokal; Mikrofon-/Kamerazugriff wird nur für aktivierte Quellen angefordert. Der Lautstärkemixer benötigt macOS 14.4+ und Systemaudioaufnahmeberechtigung und nutzt lokale Core-Audio-Taps.
- **Browserdownloads:** Nur öffentlicher Systemdateifortschritt und temporäre Download-Dateien werden geprüft; Browser-Verlauf und Seiteninhalte bleiben ungelesen.
- **Medien:** MediaRemote liefert Metadaten, der Core-Audio-Prozessausgabestatus bestätigt Wiedergabe. MediaRemote ist ein privates Framework; der aktuelle Build eignet sich deshalb nicht zur direkten Mac-App-Store-Einreichung. Fehlende Metadaten weichen auf die aktive Audioquell-App aus.
- **Netzwerk:** Vorhersagen fragen je nach Region China Weather, Open-Meteo und MET Norway ab und ziehen bei unvollständigen Daten weitere Quellen hinzu. Amtliche Warnungen werden separat von China Weather oder WeatherKit abgerufen. Der Updatekanal ermittelt einmal pro Lauf über `ipinfo.io/country` den öffentlichen Ausgangsländercode: `CN` Gitee dann GitHub, andere GitHub dann Gitee, fehlende Abfrage Gitee zuerst. Bilibili nutzt schreibgeschützte Videoinformationen, Wiedergabe-URLs und Medien-CDN; Zwischenablage-Linkerkennung verbindet sich nicht. Aktivierte Kontingentprüfungen kontaktieren gewählte Anbieter; optionale Übersetzung, KI-Aufnahmebearbeitung und Transkriptbereinigung das gewählte Modell oder CLI. Spracherkennung kann je nach System/Sprache Apple-Dienste nutzen. Installation oder Updates von Abhängigkeiten und CLIs, öffentliche IP-Abfrage und ausdrücklich gewählte Netzwerkaktionen senden ebenfalls Anfragen.
- **Automation:** Notizen verwendet AppleScript/JXA zum Auflisten, Anzeigen, Bearbeiten, Erstellen und Löschen von Apple Notizen. Automatisierungsfreigabe ist nötig, das Netzwerk wird nicht verwendet, die Daten bleiben in Apple Notizen.

## Tests

Mit vollständiger Xcode-Installation:

```bash
swift test
```

Nur mit Command Line Tools:

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Dokumentation

- [Architektur- und Leistungsplanung](Docs/architecture.md)
- [CLI-Integrationsreferenz](Docs/cli-reference.md)
- [Signatur- und Veröffentlichungsplanung](Docs/releasing.md)
- [Im Repository enthaltene Abhängigkeiten (Englisch)](../../../../mac/Vendor/README.md)
- [Drittanbieterhinweise (Englisch)](../../../../mac/Resources/ThirdPartyLicenses/README.md)

## Systemgrenzen

- macOS besitzt keine öffentliche Dynamic-Island-API; eine physische Notch wird aus `safeAreaInsets` und dem oberen Hilfsbereich abgeleitet, Displays ohne Notch nutzen dieselbe eigene Overlay-Simulation.
- DRM-Video, Anmeldefenster, Sperrbildschirm und einige exklusive Vollbild-Apps stellen möglicherweise keine Wiedergabedaten oder Overlay-Möglichkeiten bereit.
- Apps ohne Systemmedienintegration können ihre Audioquelle zeigen, aber Titel, Cover und Fortschritt nicht garantieren; pausierte, gestoppte und stumme Videos werden absichtlich verborgen.
- Ein Browser muss macOS-Dateifortschritt veröffentlichen oder erkennbare temporäre Dateien im Downloadordner nutzen, damit zisla einen Prozentsatz zeigt.
- Batteriezustand, Temperatur, aktuelle Leistung und Zubehörladestand hängen von Hardware, Verbindung und macOS-Daten ab; fehlende Felder werden als nicht verfügbar angezeigt.
- Office-zu-PDF benötigt LibreOffice oder OpenOffice; andere PDF-Vorgänge laufen lokal.
- Pakete sind nicht notarisiert und können beim ersten Start **Dennoch öffnen** benötigen. Stabile Releases verwenden ein selbstsigniertes Zertifikat, damit macOS-Freigaben spätere Updates überstehen; Sparkle prüft jedes Update zusätzlich mit dem eingebetteten öffentlichen EdDSA-Schlüssel vor Entpacken, Ersetzen und Neustart.

## Lizenz

[PolyForm Noncommercial License 1.0.0](../../../../LICENSE.md). Nichtkommerzielle Nutzung ist erlaubt; Verkauf und andere kommerzielle Nutzung dieser Software sind untersagt.
