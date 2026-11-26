# Firma, autenticazione e rilascio

**Italiano** | [English](../../../../../mac/Docs/releasing.md) | [简体中文](../../../../../mac/Docs/releasing.zh-CN.md) | [Altre lingue](../../../README.md)

Il processo completo, i due canali di aggiornamento e la sincronizzazione degli asset GitHub/Gitee sono mantenuti in [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md). Questa pagina descrive soltanto i vincoli di firma, autenticazione Apple e pacchetti di aggiornamento; per pubblicare segui la skill.

Tutti i pacchetti di aggiornamento usano Sparkle: ZIP firmati EdDSA. A ogni avvio, il canale selezionato determina il paese dell'IP pubblico. `CN` usa Gitee prima di GitHub, gli altri paesi GitHub prima di Gitee, e una ricerca indisponibile conserva Gitee primo. `package-release.sh` richiede `SPARKLE_GENERATE_APPCAST` impostato sul `generate_appcast` di Sparkle 2.9.4 e scrive `appcast-gitee.xml` e `appcast-github.xml` accanto a ZIP e DMG. Ogni appcast va firmato separatamente e deve puntare allo ZIP della stessa esecuzione sul proprio sito.

`build-package.sh` esegue lo script per ogni architettura, producendo tre coppie. Pubblica la coppia Universal come `appcast.xml`, nome ancora richiesto dalle app precedenti agli aggiornamenti separati, e le coppie singole come `appcast-arm64.xml` e `appcast-x86_64.xml`. L'installazione singola riscrive il feed Info.plist per la slice in esecuzione; x86_64 tramite traduzione richiede `arm64`, così resta a singola architettura. Universal conta le proprie slice e mantiene il feed condiviso.

Gitee usa feed permanenti `update-release` e `preview`; GitHub usa `latest` per Release e prerelease permanente `preview`. Per pubblicare senza interazione, imposta `SPARKLE_ED_KEY_FILE` sul file EdDSA privato; altrimenti usa l'account `zisla-update-ed25519` nel portachiavi login. La chiave privata non deve entrare nel repository. I rilasci stabili usano per default un certificato autofirmato comune per mantenere il designated requirement e le autorizzazioni macOS dopo aggiornamento. Non sono comunque autenticati. I pacchetti Developer ID dovrebbero essere autenticati; nemmeno le anteprime ad hoc gratuite possono esserlo.

## Prerequisiti

- Identità `zisla Release Signing` nel portachiavi dedicato oppure certificato Developer ID Application
- Credenziali Apple per autenticazione quando si usa Developer ID
- Helper ufficiale `yt-dlp` scaricato e verificato da `Scripts/fetch-yt-dlp.sh`

## 1. Compilare un'app firmata

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Per un rilascio stabile, lo script usa `RELEASE_SIGNING_MODE=selfsigned`, legge `zisla Release Signing` da `~/Library/Keychains/zisla-release-signing.keychain-db` e sblocca il portachiavi tramite la voce `dev.wzz.zisla.release-signing-keychain` del login. Non elimina l'avviso Gatekeeper al primo avvio, ma conserva un requisito basato sul certificato anziché sul cdhash specifico della build.

Con Developer ID, seleziona esplicitamente il percorso autenticabile:

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

Output:

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Distribuzione gratuita di anteprime

Senza Apple Developer Program, crea un'anteprima firmata ad hoc:

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

Il pacchetto non è autenticato e non include l'entitlement WeatherKit. Dopo la pubblicazione dell'appcast firmato nel feed Preview permanente, Sparkle verifica, scarica, controlla, installa e riavvia gli aggiornamenti Preview. Al primo avvio può servire **Impostazioni di Sistema > Privacy e sicurezza > Apri comunque**. Firma Developer ID e autenticazione restano consigliate per distribuire senza avvisi di sicurezza.

## 2. Autenticare

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

## 3. Pubblicare e verificare

Carica ZIP, DMG, checksum e appcast GitHub nello stesso tag versione GitHub, come `appcast.xml` (Universal), `appcast-arm64.xml`, `appcast-x86_64.xml`; carica asset corrispondenti e appcast Gitee con gli stessi nomi nello stesso tag Gitee. Un rilascio stabile non va segnato prerelease. Copia i tre appcast Gitee in `update-release` permanente e quelli Preview in `preview` permanente su entrambi i siti. Il canale controlla Gitee/GitHub per `CN`, GitHub/Gitee altrove.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

I rilasci normali mantengono controlli locali su artefatti, firma, checksum, layout dei pacchetti e appcast, verifica asset/feed permanenti su entrambi i siti e metadati. Nuovi download dei pacchetti, installazione e test reali di aggiornamento Sparkle vengono eseguiti soltanto su richiesta esplicita.

Per verifiche di aggiornamento richieste, parti da una versione precedente. Conferma che verifiche automatiche e manuali con IP `CN` inizino dal feed Gitee selezionato e ritentino GitHub una volta; gli altri IP fanno il contrario. Verifica che Sparkle installi e riavvii lo ZIP dell'architettura corrente, mantenendo singola un'installazione singola. Prova Release→Preview, Preview→Release e aggiornamenti sullo stesso canale. I controlli non richiesti sono indicati `Not verified` e non sono prerequisiti per completare il rilascio.

## 4. Sincronizzare il cask Homebrew

Il rilascio stabile termina con Homebrew. Le anteprime si fermano prima: il tap distribuisce solo stabili e `brew upgrade` non porta a prerelease.

Dalla radice, dopo la pubblicazione degli asset:

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

Lo script aggiorna `version` e i due `sha256` in `Casks/zisla.rb`, leggendo `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` e l'equivalente `x86_64` quando presenti, altrimenti dagli asset GitHub. Il cask risolve `#{arch}` per macchina; ogni Mac scarica la propria slice. La verifica rifiuta lo stesso digest per le due architetture. Non scrive cask che falliscono `homebrew-cask.rb verify`, poi copia su `wzz6423/homebrew-tap`. Ometti `PUBLISH_TAP` per una prova che modifica solo il cask del repository.

`auto_updates true` indica che Sparkle gestisce gli aggiornamenti. `brew upgrade` sostituisce l'app solo se il bundle è precedente al tap, cosa che Homebrew 5.1.6+ determina leggendo la versione nell'app. `brew upgrade --cask zisla` e `--greedy` usano invece i registri Homebrew e possono annullare un aggiornamento Sparkle ripristinando il tap. Committa il cask insieme all'aumento di `latestRelease` del sito: CI fallisce se fissano versioni diverse. Verifica cask e metadati dalla radice:

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

Download, installazione, aggiornamento e `livecheck` Homebrew si provano solo se richiesti. Esempio di verifica installazione:

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

I controlli Homebrew non richiesti sono `Not verified` e non impediscono il completamento del rilascio.
