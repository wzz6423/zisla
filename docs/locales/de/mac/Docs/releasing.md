# Signatur- und Veröffentlichungsplanung

**Deutsch** | [Dokumentationssprachen](../../../README.md)

Der vollständige Release-Ablauf, zwei Updatekanäle und die GitHub/Gitee-Ressourcensynchronisierung werden durch [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md) gepflegt. Diese Seite beschreibt ausschließlich Entwurfsgrenzen für Signierung, Notarisierung und Updatepakete; folgen Sie bei Veröffentlichungen dem Skill.

Beide gewählten Updatekanäle verwenden Sparkle, um signiertes ZIP und Appcast vor Austausch und Neustart zu prüfen. Die App ermittelt einmal pro Lauf den öffentlichen Ausgangsländercode: `CN` prüft Gitee zuerst und versucht GitHub genau einmal, andere Codes GitHub zuerst und Gitee einmal; eine fehlende Abfrage erhält Gitee zuerst. `package-release.sh` verlangt `SPARKLE_GENERATE_APPCAST` als Pfad zu Sparkle 2.9.4s `generate_appcast` und schreibt `appcast-gitee.xml` und `appcast-github.xml` neben ZIP und DMG. Jeder Appcast wird unabhängig signiert und muss auf das ZIP dieses Laufs auf dem eigenen Host zeigen. `build-package.sh` führt das Skript pro Architektur aus; ein Release enthält deshalb drei Paare: das Universalpaar als `appcast.xml`, weiterhin von älteren Apps vor Architekturupdates angefragt, und Einzelarchitekturpaare als `appcast-arm64.xml` und `appcast-x86_64.xml`. Eine Einzelarchitekturinstallation schreibt die Feed-URL in Info.plist auf den Appcast der laufenden Slice um; eine übersetzte x86_64-Slice fragt `arm64` an. So bleibt die Architektur erhalten statt zur Universal-App zu werden. Eine Universalinstallation zählt eigene Slices, behält den gemeinsamen Namen und bleibt universal. Gitee behält permanente `update-release`- und `preview`-Feeds für Release und Preview; GitHub verwendet `latest` für Release und die permanente Vorabveröffentlichung `preview` für Preview. Setzen Sie bei nichtinteraktiver Veröffentlichung `SPARKLE_ED_KEY_FILE` auf die privat gesicherte EdDSA-Datei oder lassen Sie es weg, um das Anmeldeschlüsselbundkonto `zisla-update-ed25519` zu nutzen. Der private Schlüssel darf niemals ins Repository. Stabile Veröffentlichungen verwenden standardmäßig dasselbe selbstsignierte Zertifikat, damit die designated requirement stabil bleibt und macOS-Freigaben Updates überstehen. Sie sind weiterhin nicht notarisiert. Developer-ID-Pakete sollten notarisiert werden; kostenlose Ad-hoc-Previews können ebenfalls nicht notarisiert werden.

## Voraussetzungen

- Identität `zisla Release Signing` im eigenen Release-Schlüsselbund oder ein Developer-ID-Application-Zertifikat
- Apple-Notarisierungszugangsdaten bei Developer ID
- Offizielles `yt-dlp`-Hilfsprogramm über `Scripts/fetch-yt-dlp.sh` geladen und geprüft

## 1. Signierte App bauen

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Für stabile Releases verwendet das Skript standardmäßig `RELEASE_SIGNING_MODE=selfsigned`, liest `zisla Release Signing` aus `~/Library/Keychains/zisla-release-signing.keychain-db` und entsperrt den Schlüsselbund über den Eintrag `dev.wzz.zisla.release-signing-keychain` im Anmeldeschlüsselbund. Das entfernt Gatekeepers Erststartwarnung nicht, erhält aber eine zertifikatsbasierte designated requirement statt eines buildspezifischen cdhash.

Wählen Sie mit Developer-ID-Zertifikat ausdrücklich den notarisierbaren Weg:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

Ausgabe:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Kostenlose Preview-Verteilung

Ohne Apple Developer Program bauen Sie eine ad hoc signierte Preview:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

Dieses Paket ist nicht notarisiert und enthält kein WeatherKit-Entitlement. Nach Veröffentlichung des signierten Appcasts im permanenten Preview-Feed prüft, lädt, verifiziert, installiert und startet die App Preview-Updates mit Sparkle. Beim ersten Start kann weiterhin **Systemeinstellungen > Datenschutz & Sicherheit > Dennoch öffnen** nötig sein. Developer-ID-Signierung und Notarisierung bleiben der empfohlene Weg zur Verteilung ohne Sicherheitsabfragen.

## 2. Notarisieren

```bash
xcrun notarytool submit \
  dist/zisla-v1.0.0-macOS-universal.zip \
  --keychain-profile AC_NOTARY \
  --wait

xcrun stapler staple 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'

# Repackage the stapled app so both the ZIP and DMG contain the final artifact.
export SKIP_BUILD=true
Scripts/package-release.sh
```

## 3. Veröffentlichen und prüfen

Laden Sie ZIPs, DMGs, Prüfsummen und GitHub-Appcasts unter denselben versionierten GitHub-Tag; Appcasts heißen `appcast.xml` für Universal, `appcast-arm64.xml` und `appcast-x86_64.xml`. Laden Sie passende Ressourcen und Gitee-Appcasts unter denselben drei Namen zum gleichen Gitee-Tag. Stabile Releases dürfen nicht als Vorabversion markiert sein. Kopieren Sie alle drei Gitee-Appcasts nach permanent `update-release` und Preview-Appcasts auf beiden Hosts nach permanent `preview`. Der gewählte Kanal prüft für `CN` Gitee dann GitHub, für andere Ländercodes GitHub dann Gitee.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

Regelmäßige Releases behalten lokale Artefakt-, Signatur-, Prüfsummen-, Paketstruktur- und Appcastprüfungen, Prüfungen beider Hosts und permanenter Feeds sowie Release-Metadatenvalidierung. Erneute Downloads, Installationsprüfungen und reale Sparkle-Upgradeabnahme laufen nur auf ausdrückliche Anforderung.

Bei angeforderter Updateabnahme prüfen Sie das neue Release mit einer älteren App. Bestätigen Sie, dass automatische und manuelle Checks von einem öffentlichen `CN`-Ausgang zuerst den gewählten Gitee-Feed und dann einmal GitHub verwenden, andere Ausgänge zuerst GitHub und dann einmal Gitee. Prüfen Sie, dass Sparkle das ZIP für die laufende Architektur installiert und neu startet und Einzelarchitekturinstallationen erhalten bleiben. Testen Sie Release→Preview, Preview→Release und Updates desselben Kanals. Nicht angeforderte Prüfungen werden als `Not verified` erfasst und sind keine Voraussetzung für den Releaseabschluss.

## 4. Homebrew-Cask synchronisieren

Ein stabiles Release endet bei Homebrew. Preview-Releases enden vor diesem Schritt: Der Tap enthält nur stabile Versionen, sodass `brew upgrade` nie auf Vorabversionen wechselt.

Nach Veröffentlichung der Ressourcen aus der Repository-Wurzel:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

Das Skript schreibt `version` und beide `sha256`-Werte in `Casks/zisla.rb` um. Es liest Prüfsummen aus `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` und der entsprechenden `x86_64`-Datei, falls vorhanden, sonst aus veröffentlichten GitHub-Ressourcen. Der Cask löst `#{arch}` pro Maschine auf, sodass Apple Silicon und Intel nur ihre eigene Slice laden; identische Prüfsummen für beide Architekturen werden abgelehnt. Ein bei `homebrew-cask.rb verify` fehlgeschlagener Cask wird nicht geschrieben; danach wird die Datei nach `wzz6423/homebrew-tap` gespiegelt. Ohne `PUBLISH_TAP` läuft ein Probelauf, der nur den Repository-Cask aktualisiert.

Der Cask setzt `auto_updates true`, weil Sparkle den Updatepfad verwaltet: `brew upgrade` ersetzt die App nur bei wirklich älterem installiertem Bundle, was Homebrew ab 5.1.6 anhand der internen App-Version entscheidet. `brew upgrade --cask zisla` und `--greedy` nutzen dagegen Installationsaufzeichnungen und können ein Sparkle-Update durch Wiederherstellen der Tap-Version rückgängig machen. Committen Sie den geänderten Cask zusammen mit dem `latestRelease`-Update der Website; unterschiedliche Versionen lassen CI fehlschlagen. Prüfen Sie Cask und Website-Metadaten aus der Repository-Wurzel:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Homebrew-Download-, Installations-, Upgrade- und `livecheck`-Abnahmen laufen nur bei ausdrücklicher Anforderung. Beispiel für Installationsabnahme:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

Nicht angeforderte Homebrew-Abnahmeprüfungen werden als `Not verified` erfasst und sind keine Voraussetzung für den Releaseabschluss.
