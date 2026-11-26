# Ondertekenen, notarisatie en releases

**Nederlands** | [English](../../../../../mac/Docs/releasing.md) | [简体中文](../../../../../mac/Docs/releasing.zh-CN.md) | [Andere talen](../../../README.md)

Het volledige releaseproces, twee updatekanalen en GitHub/Gitee-assetsynchronisatie staan in [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md). Deze pagina beschrijft alleen ontwerpgrenzen voor ondertekening, notarisatie en updatepakketten; volg de skill voor publiceren.

Alle updates gebruiken Sparkle en EdDSA-ondertekende ZIP's. Het gekozen kanaal bepaalt eenmaal per start de openbare landcode. `CN` probeert Gitee vóór GitHub, andere landen andersom; mislukte opvraag houdt Gitee eerst. `package-release.sh` vereist `SPARKLE_GENERATE_APPCAST` naar Sparkle 2.9.4's `generate_appcast` en schrijft `appcast-gitee.xml` en `appcast-github.xml` naast ZIP/DMG. Elke appcast wordt afzonderlijk ondertekend en verwijst naar de ZIP van dezelfde run op zijn eigen host.

`build-package.sh` voert dit per architectuur uit en levert drie paren. Upload Universal als `appcast.xml`, nog gebruikt door apps van vóór architectuurfeeds, en aparte paren als `appcast-arm64.xml` en `appcast-x86_64.xml`. Een enkele architectuur herschrijft de Info.plist-feed naar haar draaiende slice; vertaald x86_64 vraagt `arm64`, zodat het geen Universal wordt. Universal telt eigen slices en houdt de gedeelde naam.

Gitee heeft permanente `update-release` en `preview`; GitHub gebruikt `latest` voor Release en permanente prerelease `preview`. Stel `SPARKLE_ED_KEY_FILE` in op een privaat EdDSA-bestand voor niet-interactief publiceren; laat weg voor login-sleutelhangeraccount `zisla-update-ed25519`. De privésleutel mag nooit in de repository komen. Stabiele releases gebruiken standaard één zelfondertekend certificaat, zodat aangewezen vereiste en macOS-rechten behouden blijven. Ze zijn nog niet genotariseerd. Developer ID-pakketten horen notarisatie te krijgen; gratis ad-hocpreviews kunnen dat ook niet.

## Voorwaarden

- `zisla Release Signing` in de aparte release-sleutelhanger of Developer ID Application-certificaat
- Apple-notarisatiegegevens bij Developer ID
- Officiële `yt-dlp`-helper via `Scripts/fetch-yt-dlp.sh` opgehaald en geverifieerd

## 1. Ondertekende app bouwen

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Stabiel gebruikt standaard `RELEASE_SIGNING_MODE=selfsigned`, leest `zisla Release Signing` uit `~/Library/Keychains/zisla-release-signing.keychain-db` en ontgrendelt via `dev.wzz.zisla.release-signing-keychain` in de login-sleutelhanger. Dit verwijdert de eerste Gatekeeper-waarschuwing niet, maar behoudt een certificaatgebonden vereiste in plaats van een buildgebonden cdhash.

Kies met Developer ID het notariseerbare pad expliciet:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

Uitvoer:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Gratis previews verspreiden

Zonder Apple Developer Program bouw je een ad-hocondertekende preview:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

Niet genotariseerd en zonder WeatherKit-entitlement. Na publiceren van de ondertekende appcast op de permanente Preview-feed controleert, downloadt, verifieert, installeert en herstart Sparkle Preview-updates. Eerste start kan **Systeeminstellingen > Privacy en beveiliging > Open toch** vereisen. Developer ID en notarisatie blijven aanbevolen voor distributie zonder beveiligingsmelding.

## 2. Notariseren

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

## 3. Publiceren en controleren

Upload ZIP's, DMG's, checksums en GitHub-appcasts naar dezelfde versietag: `appcast.xml` voor Universal, `appcast-arm64.xml`, `appcast-x86_64.xml`. Upload overeenkomstige Gitee-assets en appcasts met die namen naar dezelfde Gitee-tag. Stabiel mag geen prerelease zijn. Kopieer drie Gitee-feeds naar permanent `update-release`, Preview-feeds naar permanent `preview` op beide sites. Het kanaal probeert Gitee/GitHub bij `CN`, anders GitHub/Gitee.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

Routine-releases behouden lokale checks op artefact, ondertekening, checksum, pakketindeling en appcast, beide sites en permanente feeds, en metadata. Opnieuw downloaden, installatiechecks en echte Sparkle-upgrades worden alleen op expliciet verzoek getest.

Begin voor gevraagde updatecontrole met een oudere app. Controleer automatische/handmatige checks via openbaar `CN` eerst op gekozen Gitee-feed, dan eenmaal GitHub; andere landen andersom. Verifieer installatie/herstart van ZIP voor draaiende architectuur, met behoud van één architectuur. Test Release→Preview, Preview→Release en updates binnen hetzelfde kanaal. Niet-gevraagde checks zijn `Not verified` en niet vereist om release af te ronden.

## 4. Homebrew-cask synchroniseren

Een stabiele release eindigt bij Homebrew. Previews stoppen vóór deze stap, want de tap levert alleen stabiel en `brew upgrade` gaat niet naar prerelease.

Vanaf repositoryroot na publiceren:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

Het script schrijft `version` en beide `sha256` in `Casks/zisla.rb`. Digests komen uit `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` en x86_64-equivalent als aanwezig, anders uit gepubliceerde GitHub-assets. `#{arch}` wordt per machine opgelost, dus elke Mac krijgt haar slice. De controle weigert één digest voor beide. Een cask die `homebrew-cask.rb verify` faalt wordt niet geschreven; daarna wordt naar `wzz6423/homebrew-tap` gespiegeld. Zonder `PUBLISH_TAP` wijzigt alleen de lokale cask als proef.

`auto_updates true` staat erin omdat Sparkle updates beheert. `brew upgrade` vervangt alleen een bundle achter de tap; Homebrew 5.1.6+ leest dat uit de appversie. `brew upgrade --cask zisla` en `--greedy` gebruiken de installatieregistratie en kunnen een Sparkle-update terugzetten. Commit de cask samen met site's `latestRelease`: CI faalt bij verschillende versies. Controleer vanaf de root:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Homebrew-download, installatie, upgrade en `livecheck` alleen op verzoek. Installatievoorbeeld:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

Niet-gevraagde Homebrew-checks zijn `Not verified` en geen afrondingsvoorwaarde.
