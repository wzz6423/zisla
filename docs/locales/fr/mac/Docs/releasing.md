# Conception des signatures et des publications

**Français** | [Langues de la documentation](../../../README.md)

Le processus complet de publication, les deux canaux de mise à jour et la synchronisation des ressources GitHub/Gitee sont maintenus par [`skills/zisla-release`](../../../../../skills/zisla-release/SKILL.md). Cette page décrit seulement les contraintes de conception pour la signature, la notarisation et les paquets de mise à jour ; suivez le skill pour publier une version.

Les deux canaux utilisent Sparkle pour vérifier un ZIP signé et son appcast avant de remplacer et relancer l'application. Celle-ci résout une fois par exécution le code pays de sa sortie Internet publique : `CN` vérifie Gitee d'abord, puis GitHub exactement une fois ; les autres codes vérifient GitHub puis Gitee une fois. Une recherche indisponible conserve Gitee prioritaire. `package-release.sh` exige que `SPARKLE_GENERATE_APPCAST` pointe vers `generate_appcast` de Sparkle 2.9.4 et écrit `appcast-gitee.xml` et `appcast-github.xml` à côté du ZIP et du DMG. Chaque appcast doit être signé indépendamment et pointer vers le ZIP de cette exécution hébergé sur son propre site. `build-package.sh` exécute le script une fois par architecture : une publication contient donc trois paires. Envoyez la paire universelle sous `appcast.xml`, nom toujours demandé par les versions antérieures aux mises à jour par architecture, et les paires monoarchitecture sous `appcast-arm64.xml` et `appcast-x86_64.xml`. Une installation monoarchitecture réécrit l'URL du flux Info.plist vers l'appcast de la tranche en cours, une tranche x86_64 traduite demandant `arm64`, et reste donc sur son architecture plutôt que de devenir universelle. Une installation universelle compte ses tranches, conserve le nom commun et reste universelle. Gitee conserve les flux permanents `update-release` (Release) et `preview` (Preview) ; GitHub utilise `latest` pour Release et la préversion permanente `preview` pour Preview. Pour publier sans interaction, définissez `SPARKLE_ED_KEY_FILE` vers le fichier EdDSA privé sécurisé, ou ne le définissez pas pour utiliser le compte de trousseau de session `zisla-update-ed25519`. La clé privée ne doit jamais entrer dans le dépôt. Les versions stables utilisent par défaut un même certificat autosigné pour stabiliser leur exigence désignée et conserver les autorisations macOS après mise à jour. Elles restent non notariées. Les paquets Developer ID doivent être notariés ; les Preview gratuites signées ad hoc ne peuvent pas l'être.

## Prérequis

- L'identité `zisla Release Signing` dans le trousseau de publication dédié ou un certificat Developer ID Application
- Les identifiants de notarisation Apple lors de l'utilisation de Developer ID
- L'outil officiel `yt-dlp` récupéré et vérifié via `Scripts/fetch-yt-dlp.sh`

## 1. Construire une application signée

```bash
export VERSION=1.0.0
export BUILD_NUMBER=100
export UPDATE_CHANNEL=release
Scripts/fetch-yt-dlp.sh
Scripts/package-release.sh
```

Pour une version stable, le script utilise par défaut `RELEASE_SIGNING_MODE=selfsigned`, lit `zisla Release Signing` dans `~/Library/Keychains/zisla-release-signing.keychain-db` et déverrouille ce trousseau via l'entrée `dev.wzz.zisla.release-signing-keychain` du trousseau de session. Cela ne supprime pas l'avertissement du premier lancement de Gatekeeper, mais conserve une exigence désignée fondée sur le certificat plutôt qu'un cdhash propre à chaque compilation.

Avec un certificat Developer ID, sélectionnez explicitement la voie permettant la notarisation :

```bash
export RELEASE_SIGNING_MODE=release
export CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
Scripts/package-release.sh
```

Sortie :

```text
dist/zisla-v1.0.0-macOS-universal.zip
dist/zisla-v1.0.0-macOS-universal.zip.sha256
dist/zisla-v1.0.0-macOS-universal.dmg
dist/zisla-v1.0.0-macOS-universal.dmg.sha256
dist/appcast-gitee.xml
dist/appcast-github.xml
```

### Distribution gratuite de Preview

Sans Apple Developer Program, construisez une Preview signée ad hoc :

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export UPDATE_CHANNEL=preview
export RELEASE_SIGNING_MODE=adhoc
export CODE_SIGN_IDENTITY=-
Scripts/package-release.sh
```

Ce paquet n'est pas notarié et n'inclut pas le droit WeatherKit. Après publication de son appcast signé sur le flux Preview permanent, l'application vérifie, télécharge, valide, installe et relance les mises à jour Preview avec Sparkle. Le premier lancement peut encore nécessiter **Réglages Système > Confidentialité et sécurité > Ouvrir quand même**. La signature Developer ID et la notarisation restent recommandées pour une distribution sans alertes de sécurité.

## 2. Notariser

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

## 3. Publier et vérifier

Envoyez les ZIP, DMG, sommes de contrôle et appcasts GitHub dans le même tag GitHub versionné, sous `appcast.xml` (universel), `appcast-arm64.xml` et `appcast-x86_64.xml` ; envoyez les ressources correspondantes et les appcasts Gitee sous les mêmes trois noms dans le même tag Gitee. Une version stable ne doit pas être marquée comme préversion. Copiez les trois appcasts Gitee vers `update-release` permanent ; copiez les appcasts Preview vers `preview` permanent sur les deux sites. Le canal choisi vérifie Gitee puis GitHub pour `CN`, et GitHub puis Gitee pour les autres codes pays.

```bash
codesign --verify --deep --strict --all-architectures --verbose=4 'dist/zisla.app'
spctl --assess --type execute --verbose=4 'dist/zisla.app'
xcrun stapler validate 'dist/zisla.app'
shasum -a 256 dist/zisla-v1.0.0-macOS-universal.dmg

diskutil image attach --mountOptions nobrowse 'dist/zisla-v1.0.0-macOS-universal.dmg'
test -L /Volumes/zisla/Applications
diskutil eject /Volumes/zisla
```

Les publications ordinaires conservent les contrôles locaux des fichiers, signatures, sommes de contrôle, structure des paquets et appcasts, la vérification des ressources et flux permanents des deux sites et la validation des métadonnées. Les nouveaux téléchargements des paquets, les contrôles d'installation et la validation réelle d'une mise à niveau Sparkle s'exécutent uniquement sur demande explicite.

Lorsqu'une validation de mise à jour est demandée, utilisez une ancienne version pour vérifier la nouvelle publication. Confirmez que les contrôles automatiques et manuels depuis une sortie publique `CN` utilisent le flux Gitee sélectionné d'abord et réessaient GitHub une fois ; ailleurs, GitHub précède Gitee avec un seul nouvel essai. Vérifiez que Sparkle installe et relance le ZIP de l'architecture en cours et qu'une installation monoarchitecture le reste. Testez les passages Release→Preview et Preview→Release ainsi que les mises à jour sur un même canal. Les contrôles non demandés sont indiqués `Not verified` et ne conditionnent pas l'achèvement d'une publication.

## 4. Synchroniser le cask Homebrew

Une publication stable se termine par Homebrew. Les Preview s'arrêtent avant cette étape : le tap ne sert que les versions stables, donc `brew upgrade` ne fait jamais passer un utilisateur à une préversion.

Depuis la racine du dépôt, après publication des ressources :

```bash
VERSION=1.0.0 RELEASE_OUTPUT_DIRECTORY=mac/dist PUBLISH_TAP=true make sync-cask
```

Le script réécrit `version` et les deux valeurs `sha256` dans `Casks/zisla.rb`, en lisant les empreintes dans `$RELEASE_OUTPUT_DIRECTORY/zisla-v$VERSION-macOS-arm64.zip.sha256` et son équivalent `x86_64` s'ils existent, sinon dans les ressources GitHub publiées. Le cask résout `#{arch}` pour chaque machine : Apple Silicon et Intel téléchargent seulement leur tranche ; la vérification refuse une empreinte identique pour les deux. Le script refuse d'écrire un cask échouant à `homebrew-cask.rb verify`, puis réplique le fichier vers `wzz6423/homebrew-tap`. Omettez `PUBLISH_TAP` pour une simulation qui ne met à jour que le cask du dépôt.

Le cask déclare `auto_updates true` car Sparkle gère les mises à jour : `brew upgrade` ne remplace alors l'application que si sa version est réellement plus ancienne que celle du tap, ce que Homebrew 5.1.6 et versions ultérieures déterminent en lisant le paquet. `brew upgrade --cask zisla` et `--greedy` utilisent plutôt les enregistrements d'installation Homebrew et peuvent annuler une mise à jour Sparkle en restaurant la version du tap. Commitez le cask réécrit avec l'augmentation de `latestRelease` du site : la CI échoue si les deux versions diffèrent. Validez le cask et les métadonnées du site depuis la racine :

```bash
ruby .github/scripts/homebrew-cask.rb verify --version "$VERSION" --content web/src/content.ts
```

La validation Homebrew du téléchargement, de l'installation, de la mise à niveau et de `livecheck` s'exécute uniquement sur demande explicite. Exemple de validation d'installation :

```bash
brew update
brew install --cask wzz6423/tap/zisla
brew list --cask --versions zisla
brew livecheck --cask wzz6423/tap/zisla
```

Les contrôles de validation Homebrew non demandés sont indiqués `Not verified` et ne conditionnent pas l'achèvement d'une publication.
