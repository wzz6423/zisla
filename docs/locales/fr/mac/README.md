# zisla pour macOS

**Français** | [Langues de la documentation](../../README.md)

Ce répertoire contient l'implémentation macOS de zisla. Déplacez le pointeur en haut, au centre de l'écran, pour déployer l'îlot ; éloignez-le pour le masquer. L'application utilise AppKit `NSPanel`, SwiftUI et des services pilotés par les événements, sans fenêtre transparente permanente de zone de déclenchement ni boucle de rendu lorsqu'elle est masquée.

Les cibles Swift, l'identifiant du paquet, le dossier de données locales et `zislactl` utilisent tous l'identifiant zisla. Les mises à niveau migrent automatiquement les données et préférences locales des versions précédentes.

macOS 14 et versions ultérieures sont pris en charge. macOS 26 utilise Liquid Glass ; macOS 14/15 utilisent le matériau natif du système.

## Fonctionnalités

### 12 modules de l'îlot

| Module | Fonctionnalités implémentées |
| --- | --- |
| Accueil | Résume à la demande le minuteur Pomodoro actuel, la première tâche d'IA active, les téléchargements natifs et la progression de plusieurs téléchargements de navigateurs. |
| Sons et statistiques du clavier | 20 sons de clavier intégrés ; activation indépendante des statistiques de frappe locales, tendances, chronologie par application et carte thermique par touche. |
| Transfert | Faites glisser des fichiers, des médias ou des liens vers la zone supérieure pour les conserver dans le plateau de transfert, les afficher dans le Finder ou ouvrir le partage système. Les captures conservées ont des cartes bleues de largeur double et leur propre catégorie, avec copie d'image, export PNG et suppression. Compressez les fichiers et dossiers sélectionnés en ZIP, redimensionnez ou convertissez les images sélectionnées dans les outils d'image et renvoyez les résultats réussis au plateau, ou importez les images, vidéos et fichiers audio sélectionnés dans la bibliothèque du studio d'enregistrement en conservant son projet et sa chronologie actuels. |
| Presse-papiers | Conserve un historique local consultable, filtre par image, URL et fichier et marque les favoris ; l'historique et la détection des liens ont des interrupteurs indépendants. Les nouvelles images de l'historique sont mises en file pour une reconnaissance de texte sur l'appareil ; recherchez leur texte pour retrouver l'image d'origine, ou faites un clic droit sur une image pour reconnaître ou copier son texte. La reconnaissance en cours peut être annulée ; la reconnaissance en arrière-plan ne copie pas automatiquement le texte. |
| Surveillance de l'IA | Regroupe les tâches actives, états, tendances de tokens, cartes thermiques de contributions et notifications latérales des CLI, applications de bureau et IDE pris en charge. |
| Téléchargements | Utilise `yt-dlp` pour la vidéo et l'audio ; sans `ffmpeg`, AVFoundation encapsule les pistes compatibles et une solution de repli Bilibili en lecture seule est disponible. |
| Agenda | Affiche la météo de la position actuelle et de six lieux enregistrés au maximum ; consultez, créez et supprimez les événements et rappels et marquez les rappels comme terminés. |
| Courrier | Lit les comptes Mail.app sélectionnés pour consulter les boîtes de réception, marquer les messages lus, répondre, rédiger et déplacer les messages dans la corbeille. |
| Notes | Utilise Apple Notes comme seule source de données pour consulter, modifier, créer et supprimer des notes Markdown avec aperçu en direct et écriture automatique. |
| Mixeur de volume des applications | Sur macOS 14.4+, règle le volume et coupe le son de chaque application en lecture et mémorise son volume ; nécessite l'autorisation d'enregistrement du son système. |
| Utilitaires | Fournit un minuteur Pomodoro avec une alerte sonore et une notification locale à la fin d'une session, maintien en éveil, prévention de la veille après inactivité, nettoyage de l'écran et du clavier, prompteur, miroir de caméra et vidage confirmé de la corbeille. |
| Système | Affiche le CPU, le GPU, la mémoire, le disque, le réseau, la température et les ventilateurs ; libère la mémoire et analyse les caches, journaux et données temporaires supprimables sans risque ; inclut la santé de la batterie et les niveaux des accessoires. |

### Fonctionnalités transversales

- **Lecture en cours :** MediaRemote affiche la pochette, le titre, la progression, les paroles défilantes et les commandes ; Core Audio identifie la véritable source audio en solution de repli. Les sources en pause, arrêtées ou muettes sont masquées.
- **Téléchargements des navigateurs :** Affiche la source et la progression pour Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera et Arc dans l'accueil, l'état replié et les notifications latérales.
- **Saisie vocale :** Prend en charge les raccourcis à bascule ou à maintien, les raccourcis globaux personnalisés, la reconnaissance vocale système, l'organisation locale ou distante des transcriptions et l'historique local des enregistrements.
- **Actions rapides :** Après chaque copie, une petite notification en forme d'îlot affiche un aperçu enrichi et des actions intelligentes : ouvrir les liens, afficher les fichiers dans le Finder, rechercher avec un moteur au choix, traduire, calculer, créer des événements à partir de dates reconnues et enregistrer les textes longs ou les images. Après un téléchargement du navigateur ou la réception AirDrop, le même raccourci peut ouvrir le dossier contenant le fichier ; ce comportement dépend des actions rapides indépendamment de la progression des téléchargements. Reconnaît les URL, chemins, courriels, numéros de téléphone, couleurs CSS avec échantillons en direct, calculs, dates et heures, textes dans une langue différente du système, extraits de code, textes bruts avec comptages, images avec miniatures et références de fichiers. Déclencheurs : boutons d'action, raccourci supplémentaire par défaut Command+N ou touche modificatrice/bouton latéral de souris configuré. Propose aussi un geste de copie rapide par maintien du bouton gauche et clic droit, désactivé par défaut, une liste d'applications exclues, des interrupteurs par type de reconnaissance et un mode de rappel léger.
- **Gestion des CLI et Skills :** Détecte, installe, met à jour et supprime les CLI d'IA courantes et gère les Skills locaux depuis les réglages.
- **Compagnons de bureau :** Sélectionnez un compagnon intégré ou importé et placez-le de chaque côté de l'îlot.
- **Mises à jour :** Le canal Release ou Preview sélectionné résout une fois par exécution le code pays de la sortie Internet publique. `CN` vérifie d'abord l'appcast signé de Gitee et réessaie GitHub une fois ; les autres codes vérifient GitHub d'abord, puis Gitee une fois. Si la recherche échoue, Gitee reste prioritaire. Sparkle télécharge, vérifie, installe et relance ensuite les mises à jour. Changer de canal concerne les vérifications automatiques et manuelles.
- **Apparence et interaction :** Les réglages suivent le système ou utilisent l'apparence claire ou sombre. L'îlot prend en charge les surfaces transparentes ou dépolies, le déploiement épinglé, plusieurs écrans, Spaces et les écrans externes sans encoche.
- **Valeurs par défaut :** Les nouvelles installations activent les modules fonctionnels par défaut. Chaque fonctionnalité, indicateur replié, notification latérale, indicateur de barre des menus et comportement de mise à jour est réglable indépendamment ; les installations existantes conservent leur configuration.

### Outils autonomes et procédures

- **Studio d'enregistrement :** Ouvrez-le depuis la barre des menus ou les réglages. Enregistrez un écran, une fenêtre ou une région avec, au choix, le son système, le microphone et la caméra. Modifiez la vidéo, le son, les images et le texte sur plusieurs pistes, notamment sous-titres, zooms, animations et effets de portrait et de voix ; prévisualisez avant d'exporter vidéo, GIF, Live Photo ou audio. Certains formats nécessitent FFmpeg ; l'enregistrement HDR dépend de l'appareil. Importez les images, vidéos et fichiers audio de l'étagère dans la bibliothèque multimédia en conservant le projet et la chronologie actuels.
- **Outils d'image, audio et PDF :** Ouvrez les outils autonomes depuis les réglages. Les images disposent de 9 opérations locales et d'un export par lots/ZIP. L'audio dispose de 27 opérations, dont mixage, normalisation LUFS et traitement du bruit, et nécessite FFmpeg et ffprobe. Le PDF dispose de 14 opérations ; la conversion Office nécessite LibreOffice ou OpenOffice.
- **Bulletin quotidien :** Choisissez parmi 8 modèles et sélectionnez les indicateurs dans les réglages, prévisualisez, puis exportez un PNG manuellement ou à une heure quotidienne. Les indicateurs indisponibles ne sont pas présentés comme des zéros mesurés.
- **Aperçus des fenêtres :** Survolez le Dock ou changez d'application avec Command+Tab, puis cliquez sur un aperçu pour activer sa fenêtre. Gérez la fonctionnalité et ses autorisations dans les réglages.
- **Notes contextuelles et réunions :** Maintenez le raccourci configuré et secouez le pointeur pour associer une note à une page web, une fenêtre ou au bureau. Les événements avec lien de réunion affichent un compte à rebours 10 minutes avant le début ; rejoignez la réunion, créez une note ou associez une note existante. Gérez les notes contextuelles sur l'étagère.
- **Secouer pour déposer :** Secouez le pointeur pendant le déplacement de fichiers pour révéler la zone de dépôt ; activez ce geste indépendamment dans les réglages.
- **Sortie audio et préférences du lecteur :** Choisissez un périphérique de sortie dans la zone multimédia. Les réglages sélectionnent une source automatique ou un lecteur préféré, la disposition multimédia compacte et les conditions d'arrêt des sons d'ambiance.
- **Quotas d'IA et réinitialisations :** La surveillance et les réglages affichent les quotas des comptes pris en charge, les heures d'échantillonnage et de réinitialisation et les alertes de quota faible, y compris les fenêtres 5h/7d disponibles et les budgets Cursor en USD. Ces données sont distinctes de l'historique local des tokens.

### Ordre des raccourcis des actions rapides

La fenêtre des actions rapides attribue `Command+1` à `Command+9`, puis `Command+0`, selon l'ordre actuel des actions. Le déclencheur supplémentaire par défaut des nouvelles configurations est `Command+N`, qui exécute la première action ; `Command+Delete` ferme la fenêtre. Configurez le déclencheur, le bouton latéral et l'ordre des actions dans les réglages. Les mises à niveau conservent chaque combinaison explicitement enregistrée, y compris l'ancien `Command+1`, les raccourcis personnalisés et les déclencheurs effacés ; seules les nouvelles configurations ou un champ de déclencheur absent adoptent `Command+N`.

### Emplacements d'enregistrement

Réglages → Emplacement d'enregistrement sélectionne des dossiers distincts pour les téléchargements, captures d'écran, outils d'image, enregistrements, PDF, actions rapides et bulletins quotidiens. Les nouvelles configurations utilisent par défaut les sous-dossiers de `~/Downloads` : `picture` pour captures/images, `video` pour enregistrements, `pdf`, `quick` et `daily`. Les outils audio utilisent une boîte d'export pour choisir un fichier ou un dossier. Les fichiers de l'étagère conservent des références aux originaux ; les captures conservées et l'état des notes contextuelles sont gérés localement sous `~/Library/Application Support/zisla`, tandis que les projets d'enregistrement utilisent le dossier d'enregistrement. Le texte des notes rapides est stocké dans Apple Notes.

[L'aide utilisateur et les guides pas à pas](https://wzz6423.github.io/zisla/?lang=fr#help) couvrent neuf thèmes : presse-papiers, capture, étagère, réunions, IA, outils multimédias, bulletins quotidiens, notes de bureau/aperçus des fenêtres et lecture/mixage, avec de courts extraits vidéo.

### Raccourcis et conservation des captures d'écran

L'action **Conserver** de la barre d'outils de capture se trouve entre **Épingler** et **Copier**. Elle conserve l'image finale modifiée, annotations et captures défilantes terminées comprises, dans le plateau de transfert sans la copier dans le presse-papiers. Le PNG et les métadonnées, dont l'application d'origine et l'heure de capture, sont stockés localement dans SQLite et persistent après redémarrage. La catégorie **Captures conservées** ne montre que ces cartes.

**Surligneur** suit **Pinceau** et trace un surlignage translucide ; les lignes d'extrémité et marqueurs circulaires sont conservés par défaut et peuvent être désactivés dans son menu. **Extraire** suit **Flouter** et permet l'extraction macOS du sujet ou de l'arrière-plan ainsi que la sélection libre de zones arbitraires. Plusieurs contours conservent l'union des zones, avec Tout sélectionner et Effacer ; les pixels non sélectionnés deviennent transparents et l'extraction est annulable. Le rayon des coins de capture est de 0 par défaut. Faites glisser la poignée au-dessus de la sélection ou utilisez le curseur **Rayon des coins** ; le badge de taille affiche `r`. Les exports PNG ont des coins transparents et remettre le rayon à 0 restaure les pixels d'origine.

| Contexte | Action | Raccourci par défaut |
| --- | --- | --- |
| Global | Capture d'écran | `Control+1` |
| Global | Capture d'écran défilante | `Control+2` |
| Éditeur de capture | Épingler | `Control+1` |
| Éditeur de capture | Conserver | `Control+2` |
| Éditeur de capture | Rectangle | `Control+3` |
| Éditeur de capture | Ellipse | `Control+4` |
| Éditeur de capture | Pinceau | `Control+5` |
| Éditeur de capture | Surligneur | `Control+6` |
| Éditeur de capture | Flèche | `Control+7` |
| Éditeur de capture | Numéro | `Control+8` |
| Éditeur de capture | Texte | `Control+9` |
| Éditeur de capture | Flouter | `Control+0` |
| Éditeur de capture | Extraction | `Control+A` |
| Éditeur de capture | Capture défilante | `Control+B` |
| Éditeur de capture | Copier | `Enter` |
| Éditeur de capture | Enregistrer | `Command+S` |
| Éditeur de capture | Annuler | `Command+Z` |
| Éditeur de capture | Rétablir | `Command+Shift+Z` |

Les réglages de capture affichent et enregistrent les raccourcis globaux et de l'éditeur. Copier, Enregistrer, Annuler et Rétablir sont affichés mais ne peuvent pas être réenregistrés. Les raccourcis enregistrés par l'utilisateur sont conservés à la mise à niveau ; Épingler est une action d'éditeur plutôt qu'un raccourci global distinct, et reste disponible dans son menu.

Les raccourcis par défaut de l'éditeur suivent l'ordre de la barre d'outils : `Control+1` à `Control+9`, puis `Control+0`, `Control+A`, `Control+B` et les lettres suivantes. L'attribution par défaut saute `Q`, `M`, `N` et `W` : appuyer par erreur sur Command pourrait quitter l'application, réduire, ouvrir ou fermer une fenêtre. Les combinaisons enregistrées par l'utilisateur restent autorisées.

Lors d'une mise à niveau, les anciennes dispositions non modifiées, dont celle d'Épingler/Conserver, passent une seule fois aux valeurs ci-dessus. Si un raccourci de capture a été personnalisé, la disposition existante est conservée ; les nouvelles actions choisissent une combinaison Control libre dans le même ordre sûr si leur valeur par défaut entre en conflit. Ces combinaisons initiales peuvent aussi être réenregistrées.

## Démarrage rapide

### Environnement

- macOS 14+
- Swift 6 / Xcode 16+ (les outils de ligne de commande seuls peuvent aussi compiler)
- Facultatif : `yt-dlp` et `ffmpeg` ; la conversion Office vers PDF nécessite aussi LibreOffice ou OpenOffice

Avec Homebrew :

```bash
brew install yt-dlp ffmpeg
brew install --cask libreoffice
```

### Exécuter depuis les sources

```bash
swift run zisla
```

L'application démarre comme accessoire de barre des menus. Déplacez le pointeur dans la zone de 6 px en haut, au centre de l'écran actuel, pour la déployer, ou choisissez « Afficher l'îlot » depuis l'icône de la barre des menus.

### Construire une `.app`

```bash
Scripts/generate-icon.sh
Scripts/build-app.sh
open "dist/zisla.app"
```

Pour inclure l'outil auxiliaire officiel `yt-dlp` :

```bash
Scripts/fetch-yt-dlp.sh
Scripts/build-app.sh
```

`fetch-yt-dlp.sh` télécharge un fichier autonome macOS officiel de version fixée et le vérifie avec le fichier officiel `SHA2-256SUMS` avant de l'installer dans `Tools/yt-dlp`.

## Intégration des outils d'IA

### Détection automatique

zisla lit l'état public ou local stable des sessions des outils pris en charge et extrait uniquement les événements structurés et métadonnées locales nécessaires pour déterminer l'état des tâches. Il ne lit pas les invites ni le contenu des réponses.

| Environnement | Détection automatique |
| --- | --- |
| OpenAI / Anthropic | Codex CLI et Desktop, Claude Code et leurs environnements hôtes |
| GitHub / Google / xAI | GitHub Copilot CLI et VS Code, Gemini CLI et Desktop et Grok CLI |
| Outils indépendants et régionaux | Pi, Kimi Code, Qwen Code, Qoder, ZCode Desktop et CLI, TRAE, OpenCode, Harnext/Harness et WorkBuddy |

L'attente d'une approbation ou d'une réponse utilisateur apparaît en jaune, les erreurs d'outil ou de commande en rouge et l'exécution normale en vert ; les sources simultanées sont regroupées dans l'ordre rouge, jaune, vert. Le sidecar d'exécution Qwen n'est actif que tant que son PID existe, pour éviter les rapports périmés après sa sortie.

Si une application de conversation ne conserve pas d'événements d'activité structurés, le système ne peut pas distinguer de façon fiable une application ouverte inactive d'un modèle en cours de génération. Ces outils, dont ChatGPT, doivent utiliser le hook `zislactl` ci-dessous ; zisla ne simule pas l'activité par un processus résident.

### Protocole local `zislactl`

`zislactl` écrit l'état des tâches et l'historique d'utilisation dans SQLite :

```text
~/Library/Application Support/zisla/ai-state.sqlite
```

L'historique d'utilisation survit aux redémarrages, aux mises à jour remplaçant l'application et à l'effacement des tâches. Il ne disparaît que si l'utilisateur supprime manuellement les données de l'application.

Exemple :

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

Les fournisseurs canoniques comprennent `claude`, `codex`, `gemini`, `grok`, `gpt`, `copilot`, `kimi`, `qwen`, `coder`, `zcode`, `trae`, `opencode`, `pi`, `harness` et `doubao` ; les alias courants sont normalisés automatiquement. Appelez la commande depuis tout hook d'outil, wrapper shell ou script de tâche.

La liste des exécutions d'IA et l'état replié utilisent le logo officiel de chaque outil pour identifier sa source.

Consultez la [référence d'intégration CLI](Docs/cli-reference.md) pour le protocole.

## Progression des téléchargements des navigateurs

zisla écoute les informations publiques de progression de fichiers de macOS dans le dossier Téléchargements et combine les extensions temporaires, les attributs étendus de source et les navigateurs en cours d'exécution pour identifier la source. Il ne lit pas les bases d'historique et ne fait aucune requête réseau pour déterminer la progression ; le marqueur de fin reste visible environ trois secondes. Les actions rapides utilisent la même source et proposent Ouvrir le dossier après l'arrivée d'un transfert réussi à sa destination finale. Leur durée suit le réglage des actions rapides et la dernière notification de copie ou transfert remplace la précédente.

## Téléchargeur

Les exécutables sont recherchés dans cet ordre :

1. `zisla.app/Contents/Helpers/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`
4. `~/.local/bin/yt-dlp`

L'URL est transmise à `Process` comme valeur argv distincte, sans passer par un shell. La configuration d'exécution et les plugins sont ignorés, `--exec` est désactivé, les limites à un seul élément sont appliquées et le fichier final est vérifié pour rester dans le dossier autorisé.

Sans `ffmpeg` :

- La vidéo privilégie les pistes vidéo AVC/MP4 et audio M4A, puis les encapsule en MP4 avec AVFoundation ; un format monofichier est conservé tel quel.
- L'audio privilégie M4A, sinon conserve le format audio d'origine.
- Si yt-dlp reçoit HTTP 412, ne trouve pas de format ou est indisponible localement, Bilibili utilise son API en lecture seule pour obtenir les pistes DASH et suit la même encapsulation native sans installer d'autre outil.

## Notes

Les notes Markdown de l'îlot utilisent Apple Notes comme seule source de données. Vous pouvez créer, consulter, modifier et supprimer les notes existantes, et pas seulement en ajouter.

- **Liste :** À l'ouverture, JXA (`osascript -l JavaScript`) lit les titres et dates de modification des notes non supprimées et les trie par modification la plus récente. Le retour de Notes actualise la liste ; les notes Supprimées récemment sont masquées. Sélectionnez une note pour la modifier, actualisez, créez une note ou supprimez-la depuis le menu contextuel.
- **Consultation et modification :** AppleScript lit le `plaintext` de la note sélectionnée, source Markdown, dans l'éditeur. Le `TextEditor` natif écrit les changements après environ 0,8 seconde d'inactivité pour éviter un appel AppleScript par frappe. Les nouvelles notes sont créées dans Apple Notes puis sélectionnées.
- **Aperçu :** Le parseur de blocs intégré rend les titres, listes non ordonnées/ordonnées/de tâches, citations, blocs de code, séparateurs, gras, italique, code en ligne, texte barré et liens sous forme d'`AttributedString`.
- **Stockage :** La source Markdown est stockée comme texte ordinaire dans le `body` de la note, avec échappement HTML et lignes vides conservées. La lecture de `plaintext` restaure la source ; Apple Notes affiche le texte brut au lieu de rendre le Markdown.
- **Autorisations :** La première lecture ou écriture déclenche l'autorisation d'automatisation macOS pour Apple Notes ; un refus renvoie une notification d'échec dans la liste ou l'éditeur.

Le module Notes ne conserve pas de seconde copie locale ; Apple Notes est le moteur de stockage.

## Autorisations et confidentialité

- **Calendrier :** Les autorisations Calendrier et Rappels sont demandées séparément à la première ouverture ; événements et rappels sont actualisés après création, suppression ou achèvement.
- **Position :** La météo demande une seule fois la position actuelle, sans suivi continu ; les autres lieux peuvent être recherchés, enregistrés et supprimés dans les réglages.
- **Fichiers et téléchargements :** Les dossiers sélectionnés utilisent des signets à portée de sécurité ; le transfert ne copie pas l'original.
- **Presse-papiers :** Les nouvelles installations activent l'historique et la détection de liens par défaut avec des interrupteurs indépendants. À chaque `changeCount`, au plus un lien est reconnu localement ; les paramètres de requête ne sont pas journalisés et aucune API d'effacement, de déclaration de type ou d'écriture n'est appelée, donc le presse-papiers universel n'est pas remplacé.
- **Actions rapides :** S'exécutent localement à chaque `changeCount` lorsque activées et traitent les téléchargements terminés et fichiers AirDrop reçus. Le déclencheur peut utiliser la surveillance de l'entrée pour les touches modificatrices seules et les boutons latéraux ; le geste de copie rapide facultatif émet aussi un ⌘C synthétique et nécessite donc Accessibilité. La reconnaissance n'utilise jamais le réseau ; l'ouverture de liens, la recherche, la traduction et l'enregistrement suivent uniquement un clic ou un déclenchement explicite. La liste d'exclusion et les interrupteurs par type contrôlent les notifications de copie ; l'interrupteur des actions rapides contrôle aussi les notifications de transfert terminé.
- **État de l'IA :** La détection automatique lit seulement les événements structurés et métadonnées locales nécessaires pour déterminer l'état des tâches.
- **Voix :** Le microphone et la reconnaissance vocale ne sont accessibles qu'après une action explicite. Les enregistrements, transcriptions brutes et textes organisés sont gérés localement ; le texte organisé est envoyé uniquement au modèle local, au fournisseur distant ou au profil CLI choisi, et les identifiants distants restent dans une base privée.
- **Bluetooth et appareils :** La batterie des accessoires et appareils mobiles Apple approuvés n'est lue que lorsque la vue Batterie de Système est ouverte.
- **Caméra et surveillance de l'entrée :** Le miroir et l'aperçu/enregistrement du studio demandent l'accès caméra. Sons du clavier, statistiques, nettoyage et déclencheurs de touches modificatrices/boutons latéraux utilisent la surveillance de l'entrée ; statistiques locales et interrupteurs indépendants.
- **Écran et son système :** Les captures, enregistrements et aperçus lisent l'écran avec l'autorisation d'enregistrement d'écran. L'enregistrement conserve localement les sources sélectionnées ; les autorisations facultatives microphone/caméra sont demandées uniquement pour les sources activées. Le mixeur nécessite macOS 14.4+ et l'autorisation d'enregistrement du son système et utilise des taps Core Audio locaux.
- **Téléchargements des navigateurs :** Seuls la progression système publique et les fichiers temporaires de téléchargement sont inspectés ; l'historique et le contenu des pages ne sont pas lus.
- **Médias :** MediaRemote fournit les métadonnées et l'état de sortie des processus Core Audio confirme la lecture. MediaRemote est un framework privé ; la version actuelle ne convient donc pas à une soumission directe au Mac App Store. Sans métadonnées, l'application source audio active est utilisée.
- **Réseau :** La météo utilise Open-Meteo et les alertes publiques chinoises lorsque pertinentes, et privilégie WeatherKit ailleurs. Le canal de mise à jour résout une fois par exécution le code pays de sortie publique via `ipinfo.io/country` : `CN` utilise Gitee puis GitHub, les autres codes GitHub puis Gitee, et l'indisponibilité conserve Gitee d'abord. Le repli Bilibili utilise des informations vidéo en lecture seule, les URL de lecture et son CDN ; la reconnaissance de liens du presse-papiers ne se connecte pas. Les vérifications activées des quotas contactent les fournisseurs sélectionnés ; traduction, modifications d'enregistrement par IA et nettoyage de transcription facultatifs contactent le modèle ou la CLI choisi. La reconnaissance vocale peut utiliser Apple selon le système/la langue. Installer ou mettre à jour dépendances et CLI, rechercher l'IP publique et les actions réseau explicitement choisies envoient aussi des requêtes.
- **Automatisation :** Notes utilise AppleScript/JXA pour lister, consulter, modifier, créer et supprimer les notes Apple Notes. Une autorisation d'automatisation est requise, aucun réseau n'est utilisé et les données restent dans Apple Notes.

## Tests

Avec une installation complète de Xcode :

```bash
swift test
```

Avec les outils de ligne de commande seuls :

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Documentation

- [Conception de l'architecture et des performances](Docs/architecture.md)
- [Référence d'intégration CLI](Docs/cli-reference.md)
- [Conception des signatures et des publications](Docs/releasing.md)
- [Dépendances intégrées au dépôt (anglais)](../../../../mac/Vendor/README.md)
- [Avis relatifs aux tiers (anglais)](../../../../mac/Resources/ThirdPartyLicenses/README.md)

## Limites du système

- macOS n'a pas d'API publique Dynamic Island ; l'encoche physique est déduite de `safeAreaInsets` et de la zone auxiliaire supérieure, tandis que les écrans sans encoche utilisent la même superposition simulée personnalisée.
- Les vidéos DRM, fenêtres de connexion, écran verrouillé et certaines applications plein écran exclusives peuvent ne pas fournir de données de lecture ou autoriser une superposition.
- Les applications sans intégration au centre multimédia peuvent exposer leur source audio mais ne garantissent pas titre, pochette ou progression ; les vidéos en pause, arrêtées ou muettes sont intentionnellement masquées.
- Un navigateur doit publier la progression macOS ou utiliser des fichiers temporaires reconnaissables dans Téléchargements pour que zisla affiche un pourcentage.
- La santé de batterie, température, puissance instantanée et niveaux des accessoires dépendent du matériel, de la connexion et des données macOS ; les champs manquants sont indiqués indisponibles.
- La conversion Office vers PDF nécessite LibreOffice ou OpenOffice ; les autres opérations PDF s'exécutent localement.
- Les paquets ne sont pas notariés et peuvent nécessiter **Ouvrir quand même** au premier lancement. Les versions stables utilisent le même certificat autosigné afin de conserver les autorisations macOS lors des mises à jour ; Sparkle vérifie séparément chaque mise à jour avec la clé publique EdDSA intégrée avant extraction, remplacement et relancement.

## Licence

[PolyForm Noncommercial License 1.0.0](../../../../LICENSE.md). L'utilisation non commerciale est autorisée ; vendre ce logiciel ou l'utiliser commercialement est interdit.
