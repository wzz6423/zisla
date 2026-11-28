# Architektur- und Leistungsplanung

**Deutsch** | [Dokumentationssprachen](../../../README.md)

## Auslösung am oberen Rand

Der verborgene Zustand hat kein transparentes Fenster. `PointerEdgeMonitor` installiert globale und lokale `NSEvent`-Beobachter für Mausbewegung und Ziehen; `ScreenLayoutEngine` ermittelt allein geometrisch, ob der Zeiger den 6 px hohen Bereich oben in der Mitte eines Displays betritt.

Jedes Display besitzt eine stabile Kennung aus `NSScreenNumber` und seinem `CGDirectDisplayID`. Das Layout wird an `screen.frame.maxY` verankert und unterstützt deshalb negative Koordinaten, vertikal angeordnete Displays und externe Displays ohne Notch.

Bei mehreren angeschlossenen Bildschirmen lässt sich unter Einstellungen → Allgemein → Bildschirmmodi für jeden Bildschirm der Dynamic Island-Modus (Kameraposition oder eigene Position), der Notch-Modus oder das Ausblenden wählen. Bei einem Bildschirm ist diese Einstellung verborgen und die globale Darstellung gilt; beim erneuten Anschließen werden die gespeicherten Einstellungen wiederhergestellt. Auf allen eingeblendeten Bildschirmen bleibt die eingeklappte Insel gleichzeitig sichtbar. Aufklappen, Schnellaktionen, Aufnahmen und vorübergehende Meldungen ersetzen nur die Insel auf dem jeweiligen Bildschirm; die Auswahl der Benachrichtigungsbildschirme filtert Inhalte, ohne die inaktive Insel auszublenden.

## Fenster

Die Hauptinsel behält ein einziges `.borderless + .nonactivatingPanel`:

- Es nutzt die Ebene `.statusBar` und überdeckt weder Systemsperrbildschirm noch Systemmenü.
- `.canJoinAllSpaces + .fullScreenAuxiliary` unterstützt Spaces und gewöhnliche Vollbild-Apps.
- Aufklappen beim Zeigerkontakt ruft niemals `NSApp.activate` auf und nimmt der aktuellen App deshalb nicht den Fokus.
- Der verborgene Zustand verwendet `orderOut`, sodass kein transparentes Fenster den Menüleistenbereich belegt.

Linke und rechte Mitteilungsfenster werden bei Bedarf erstellt und sofort verborgen, wenn ihre Warteschlangen leer sind.

## Status und Nebenläufigkeit

- AppKit, SwiftUI-Status und Fenstersteuerung bleiben auf `MainActor`.
- Bei aktivierter Menüleistenverwaltung legt zisla zwei `NSStatusItem`-Elemente an. Solange die Symbolliste geöffnet ist, liest zisla `AXExtrasMenuBar` und prüft nach dem Verschieben die Position des gewählten Symbols.
- Downloads, Wetter und GitHub-Anfragen verwenden Actors.
- Von Hooks geschriebener KI-Status wird durch Dateisystemereignisse des Ordners überwacht. Jede KI-Sitzungsquelle vergleicht Änderungszeit und Größe der neuesten lokalen Sitzungs- oder Aktivitätsdatei und verwendet bei unveränderten Daten den Parsing-Cache erneut.
- Automatische Erkennung liest nur strukturierte Ereignisse, feste Statusmarker und Aktivitätsmetadaten zur Aufgabenstatusbestimmung. Prompts und Antwortinhalte werden nicht gelesen; ein Anbieterparserfehler blockiert andere Anbieter nicht.
- KI-Kontingente werden für jeden Anbieter getrennt abgefragt. Die Gemini- und Claude/GPT-Kontingente von Antigravity behalten eigene Rücksetzungsfenster und Warnungen. Das normale Chat-Kontingent von Gemini App nutzt das gespeicherte Web-Cookie desselben Google-Kontos; Gemini CLI behält die lokale OAuth-Quelle. Fehlende Kontingente werden nie geschätzt.
- Einklappverzögerungen nutzen abbrechbare `Task`s und einen Generations-Token, damit eine alte Aufgabe keine bereits wieder geöffnete Insel verbergen kann.
- Im verborgenen Zustand gibt es weder `TimelineView` noch 60-Hz-Timer oder dauerhaft eingereichte Animationen.

## Medienerkennung

MediaRemote liefert Titel, Cover, Fortschritt und Steuerung. Prozessobjekteigenschaften von Core Audio 14.4+ bestätigen aktive Ausgabestreams und liefern bei fehlenden Metadaten eine Ersatzquell-App. Prozesslisten und Ausgabestatus verwenden Eigenschaftsbeobachter und begrenzte regelmäßige Überprüfung; Audioinhalte werden niemals aufgenommen, und Bildschirmaufnahme- oder Bedienungshilfenberechtigung wird nicht angefordert. Pausierte, gestoppte und stumme Quellen bleiben nicht im Medienbereich.

## Aufnahme und Anwendungsmixing

Bildschirmaufnahme und Anwendungslautstärkemixer sind von der Metadatenerkennung getrennt. Aufnahmen verlangen Bildschirmaufnahmefreigabe und die Berechtigungen aktivierter Mikrofon-/Kameraquellen, speichern ausgewählte Medien lokal und verwalten Projekte im gewählten Aufnahmeordner. Der App-Mixer nutzt Core-Audio-Taps unter macOS 14.4+ und benötigt Systemaudioaufnahmeberechtigung.

## Materialien

macOS 26 nutzt eine einzelne SwiftUI-`glassEffect`-Ebene; macOS 14/15 nutzen eine einzelne `NSVisualEffectView`. Transparenzreduzierung schaltet auf einen undurchsichtigen Hintergrund um. Die Insel stapelt keine mehreren Unschärfe- oder Materialebenen.

## Sicherheitsgrenze für Downloads

Swift startet `yt-dlp` mit `Process.executableURL` und einem Argumentarray; die URL ist immer ein eigener argv-Wert nach `--`. Laufzeitkonfiguration, Plugins und exec sind deaktiviert, Ausgabepipes werden gleichzeitig geleert und Fortschritt über einen JSON-Sentinel ausgewertet.

Eine Aufgabe ist nur erfolgreich, wenn Exit-Code 0 vorliegt, der Ausgabepfad existiert und der aufgelöste Pfad im freigegebenen Verzeichnis bleibt. Jede Aufgabe bereinigt nur ihr eigenes nach UUID benanntes temporäres Verzeichnis.

## Updateprüfungen und Downloads

Der gewählte Updatekanal ermittelt einmal pro App-Lauf den öffentlichen Ausgangsländercode und verwendet dann Sparkle, um den signierten Appcast des installierten Builds abzurufen, das referenzierte ZIP über HTTPS herunterzuladen, EdDSA-Archiv- und Feed-Signaturen vor Entpacken zu prüfen, die App zu ersetzen und neu zu starten. `CN` beginnt mit Gitee, `update-release` für Release und `preview` für Preview, und versucht den passenden GitHub-Feed einmal; andere Ländercodes beginnen mit GitHub und versuchen Gitee einmal. Fehlende Abfrage erhält Gitee zuerst; jeder Feed verweist auf ein signiertes ZIP auf seinem eigenen Host. Ein Release stellt neben dem gemeinsamen `appcast.xml` einen Appcast je Architektur bereit. Eine Einzelarchitekturinstallation fragt die eigene Slice an, eine übersetzt laufende x86_64-Slice dabei `arm64`, und wird nie durch den Universal-Build ersetzt. Eine Universalinstallation zählt ihre eigenen ausführbaren Slices und bleibt bei `appcast.xml`, das auch ältere Apps vor architekturspezifischen Updates versorgt. Ein Einstellungswechsel betrifft automatische und manuelle Prüfungen und setzt Sparkles nächsten Updatezyklus zurück. Der eingebettete öffentliche Schlüssel enthält keine Kontodaten; der private Signaturschlüssel bleibt im macOS-Schlüsselbund des Release-Verantwortlichen oder einer separat gesicherten privaten Datei.
