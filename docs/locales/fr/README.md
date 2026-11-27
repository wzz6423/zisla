# zisla

**Français** | [Langues de la documentation](../README.md)

**zisla est un espace de travail macOS natif qui apparaît lorsque vous en avez besoin, puis s'efface.** Déplacez le pointeur en haut, au centre de l'écran, pour ouvrir un espace léger réunissant les travaux d'IA en cours, les médias, le transfert de fichiers, les téléchargements et les utilitaires du bureau. Les écrans sans encoche utilisent la même zone d'état simulée.

Implémentation actuelle : **macOS 14+**. Apple Silicon est la configuration prise en charge ; les paquets de publication Intel peuvent fonctionner, mais leur compatibilité n'est pas garantie.

[Voir la présentation complète des fonctionnalités — 2:40 · 1080p / 60 fps](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

[![Voir le film de lancement de zisla](../../../web/public/media/zisla-launch-poster.webp)](https://wzz6423.github.io/zisla/media/zisla-launch-1080p60.mp4)

Musique : « Funkorama » de Kevin MacLeod · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Source](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474).

## Pourquoi le haut de votre écran est sa place

- **À la demande, sans prendre le focus.** Déployez l'interface depuis le bord supérieur, épinglez-la si nécessaire et poursuivez votre travail dans l'application actuelle.
- **Un seul endroit pour le travail en cours.** Consultez la lecture multimédia, les tâches d'IA, les téléchargements, les minuteurs, les courriels, l'état du système et la batterie sans ouvrir un tableau de bord complet.
- **L'activité de l'IA sans accès aux conversations.** zisla lit uniquement les événements structurés et les métadonnées d'activité locales nécessaires pour déterminer l'état des tâches. Il ne lit jamais les invites ni le contenu des réponses.
- **Les commandes restent locales.** Les modules, l'historique du presse-papiers et la détection de liens ont des interrupteurs indépendants ; les autorisations ne sont demandées qu'à la première utilisation d'une fonctionnalité.

## Ce qu'il peut faire

### Faciliter le travail sur le bureau

| Fonctionnalité | Description |
| --- | --- |
| Lecture en cours | Affiche la pochette, le titre, la progression, les paroles et les commandes de lecture ; Core Audio peut identifier l'application qui produit réellement le son lorsque les métadonnées manquent. |
| Transfert et partage | Déposez des fichiers, des médias ou des liens sur la zone de déclenchement supérieure pour les conserver dans le plateau de transfert, les afficher dans le Finder ou ouvrir le menu de partage de macOS. Compressez les fichiers et dossiers sélectionnés en ZIP, redimensionnez ou convertissez les images sélectionnées dans les outils d'image et renvoyez les résultats réussis au plateau, ou importez les images, vidéos et fichiers audio sélectionnés dans la bibliothèque du studio d'enregistrement en conservant son projet et sa chronologie actuels. |
| Presse-papiers et notifications | Enregistre facultativement l'historique local du presse-papiers, reconnaît les nouveaux liens localement et affiche les médias, l'activité d'IA, les téléchargements du navigateur, les minuteurs, les courriels et les mises à jour dans l'état replié. Les actions rapides facultatives affichent après chaque copie une petite notification en forme d'îlot, avec un aperçu enrichi et des actions intelligentes (ouvrir, afficher dans le Finder, rechercher, traduire, calculer, enregistrer). Après un téléchargement du navigateur ou la réception d'un fichier AirDrop, le même raccourci peut ouvrir son dossier. Les nouvelles images de l'historique sont mises en file pour une reconnaissance de texte sur l'appareil ; recherchez leur texte pour retrouver l'image d'origine, ou faites un clic droit sur une image pour reconnaître ou copier son texte. |
| Espace de travail quotidien | Comprend la météo, le calendrier, les rappels, Mail.app, les notes Markdown stockées dans Apple Notes, les informations de l'écran verrouillé et des compagnons de bureau facultatifs. |

### Rendre le travail de l'IA visible

zisla surveille l'activité locale de Codex, Claude Code, Pi, GitHub Copilot, Gemini, Grok, Kimi Code, Qwen Code, Qoder, ZCode, Zed Agent, Delta, Orca, TRAE, OpenCode, Harnext, WorkBuddy, WorkBuddy AI et d'autres sources prises en charge. Il affiche les tâches, leur état, les tendances de tokens, les cartes thermiques de contributions et les notifications latérales.

Pour les outils sans source d'activité locale stable, `zislactl` permet aux scripts, à la CI et aux hooks d'outils de signaler la progression, l'utilisation et les notifications en conservant l'état du protocole sur ce Mac. Les réglages peuvent aussi détecter, installer, mettre à jour et supprimer les CLI d'IA courantes et gérer les Skills locaux. Consultez la [référence d'intégration CLI](mac/Docs/cli-reference.md) pour les fournisseurs et les commandes.

### Gérer les petites tâches utiles

| Domaine | Outils inclus |
| --- | --- |
| Téléchargements et documents | Téléchargement de vidéos et de fichiers audio avec `yt-dlp` ; fusion, division, rotation, recadrage, conversion, rendu, export de texte, filigranes, numéros de page, chiffrement, déverrouillage et modification des métadonnées PDF en local. |
| Concentration et présentation | Minuteur Pomodoro avec une alerte sonore et une notification locale à la fin d'une session, mode de maintien en éveil, prévention de la veille après inactivité, nettoyage de l'écran et du clavier, prompteur et miroir de caméra. Le nom du minuteur ne vaut que pour la session en cours et revient au nom par défaut à la fin ou après annulation. |
| Système et batterie | Informations sur le CPU, le GPU, la mémoire, le disque, le réseau, les ventilateurs et la batterie, ainsi que nettoyage des caches et journaux pouvant être supprimés sans risque. |
| Saisie vocale | Raccourcis globaux d'enregistrement et de transcription, organisation facultative des transcriptions en local ou à distance et historique vocal local. |

### Points d'accès et procédures actuels

L'îlot comporte 12 modules : Accueil, Transfert, Presse-papiers, Surveillance de l'IA, Sons du clavier, Téléchargements, Agenda, Courrier, Notes, Mixeur de volume des applications, Utilitaires et Système. Les détails de la batterie se trouvent dans Système ; l'affichage de l'écran verrouillé est distinct. Ouvrez les outils PDF, image et audio depuis les réglages ; ouvrez le studio d'enregistrement depuis les réglages ou la barre des menus.

- **Enregistrement et création :** Enregistrez un écran, une fenêtre ou une région avec, au choix, le son système, le microphone et la caméra. Modifiez les sous-titres, les zooms, les effets de portrait et de voix sur plusieurs pistes, prévisualisez, puis exportez une vidéo, un GIF, une Live Photo ou du son. Les outils d'image proposent 9 opérations locales ; les outils audio en proposent 27.
- **Mixage et lecture :** macOS 14.4+ permet le réglage du volume et la mise en sourdine par application. Choisissez la sortie audio dans la zone multimédia et les préférences du lecteur dans les réglages.
- **Bureau et réunions :** Aperçus de fenêtres du Dock et de Command+Tab, notes contextuelles de page web/fenêtre/bureau, compte à rebours de réunion de 10 minutes, accès aux réunions et notes associées. Secouez le pointeur en faisant glisser des fichiers pour afficher la zone de dépôt de l'étagère.
- **Bulletin quotidien :** 8 modèles, aperçu, export PNG manuel ou programmé, choix des indicateurs et dossier d'enregistrement indépendant.
- **Comptes d'IA :** Consultez les quotas disponibles des comptes pris en charge, les heures de réinitialisation, les alertes de quota faible et les heures d'échantillonnage ; exportez l'historique local des tokens au format `.xlsx`.
- **Actions rapides :** Les actions de la fenêtre utilisent `Command+1` à `Command+0` dans l'ordre. Le déclencheur supplémentaire par défaut des nouvelles configurations est `Command+N` pour la première action. Les mises à niveau conservent les raccourcis enregistrés et les déclencheurs effacés.

[L'aide utilisateur](https://wzz6423.github.io/zisla/help.html?lang=fr#help) fournit neuf guides pas à pas : presse-papiers, capture, étagère, réunions, IA, outils multimédias, bulletins quotidiens, notes de bureau/aperçus des fenêtres et lecture/mixage. Le [guide macOS](mac/README.md) indique les dossiers d'enregistrement des outils et leurs dépendances.

## Premiers pas

### Installer l'application

Téléchargez le dernier DMG depuis [GitHub Releases](https://github.com/wzz6423/zisla/releases) ou [Gitee Releases](https://gitee.com/wzz6423/zisla/releases), montez-le et faites glisser `zisla.app` dans `Applications`.

Homebrew constitue une autre méthode d'installation :

```bash
brew install --cask wzz6423/tap/zisla
```

Homebrew récupère la version correspondant à votre puce ; un Mac Apple Silicon ou Intel ne télécharge donc que sa propre architecture. Le cask provient du tap tiers `wzz6423/tap`, et non du dépôt de casks de Homebrew ; l'installer signifie donc faire confiance à ce tap.

Après le lancement, déplacez le pointeur en haut, au centre de l'écran actuel, ou choisissez **Afficher l'îlot** depuis l'icône de la barre des menus. Les paquets ne sont pas notariés ; quelle que soit la méthode d'installation, le premier lancement nécessite **Ouvrir quand même** dans **Réglages Système > Confidentialité et sécurité**, ou la suppression manuelle de l'attribut de quarantaine :

```bash
xattr -d com.apple.quarantine /Applications/zisla.app
```

### Mettre à jour l'application

zisla se met à jour via Sparkle, quelle que soit la méthode d'installation. L'installation Homebrew mérite une précision : `brew upgrade` ne remplace l'application que si la copie installée est réellement plus ancienne que celle du tap, car Homebrew 5.1.6 et versions ultérieures lisent la version dans le paquet de l'application. Homebrew laisse ainsi Sparkle fonctionner sans conserver une installation périmée. Une commande nommant le cask utilise en revanche les enregistrements d'installation de Homebrew et peut remettre une application mise à jour par Sparkle à la version du tap :

```bash
brew upgrade --cask zisla
```

Le tap ne distribue que les versions stables ; les versions Preview restent sur Releases, donc `brew upgrade` ne vous fait jamais passer à une préversion. Nommer le cask lorsque vous utilisez une Preview la remplace par la version stable actuelle. Sparkle ne rétrograde jamais : revenir au canal Release conserve la version Preview jusqu'à ce qu'une version stable la dépasse. `brew uninstall --cask zisla` supprime l'application, et `brew uninstall --zap --cask zisla` supprime également ses données locales.

### Exécuter depuis les sources

Swift 6 / Xcode 16+ est requis ; les outils de ligne de commande seuls peuvent également construire le projet.

```bash
cd mac
swift run zisla
```

Le téléchargeur nécessite `yt-dlp` ; `ffmpeg` est facultatif. La conversion Office vers PDF nécessite LibreOffice ou OpenOffice. Les instructions de compilation, de test et de création de paquets figurent dans le [guide de développement macOS](mac/README.md).

## Conçu pour rester discret

- Prend en charge plusieurs écrans, Spaces et les applications plein écran ordinaires sans activer l'application ni détourner le focus de l'application actuelle.
- L'état masqué n'a aucune fenêtre transparente permanente de zone de déclenchement et n'exécute aucune boucle de rendu ; la surveillance globale des événements et les vérifications géométriques déclenchent le déploiement.
- Utilise un seul matériau système et passe à un fond opaque lorsque Réduire la transparence est activé.
- Détecte une encoche physique à partir de la zone de sécurité du système ; les écrans externes sans encoche utilisent une superposition de même contour.

Consultez la [conception de l'architecture et des performances](mac/Docs/architecture.md) pour les compromis d'implémentation.

## Confidentialité et autorisations

zisla ne demande une autorisation que lorsqu'une fonctionnalité activée en a besoin pour la première fois. Vous pouvez désactiver les modules dans les réglages et révoquer les autorisations dans les Réglages Système de macOS à tout moment.

| Domaine | Limites |
| --- | --- |
| Activité de l'IA | Lit uniquement les événements structurés et les métadonnées d'activité locales. Les invites et le contenu des réponses ne sont jamais lus. |
| Presse-papiers et fichiers | L'historique du presse-papiers, la détection de liens et les actions rapides sont des interrupteurs locaux distincts ; les actions rapides traitent les téléchargements terminés du navigateur et les fichiers AirDrop reçus indépendamment de l'interrupteur de progression des téléchargements. La reconnaissance se fait entièrement sur l'appareil ; l'ouverture des liens et l'exécution des actions suivent uniquement un clic explicite ou une pression du déclencheur. Le transfert utilise des signets à portée de sécurité et ne copie pas le fichier original. |
| Notes, Courrier et voix | Notes et Courrier utilisent AppleScript/JXA avec l'autorisation d'automatisation. La voix n'est enregistrée que pendant l'utilisation active ; l'organisation des transcriptions envoie le texte uniquement au modèle local, au fournisseur distant ou au profil CLI sélectionné. |
| Téléchargements du navigateur et médias | Utilise les informations publiques de progression des fichiers de macOS, les métadonnées MediaRemote et l'état de sortie Core Audio. Ne lit pas les bases de données d'historique des navigateurs. Les formes d'onde système et le mixage des applications traitent le son localement ; l'enregistrement ne sauvegarde le son que lorsque la source correspondante est activée. |
| Réseau | La météo, la recherche d'IP publique, la sélection du miroir de mise à jour, les téléchargements, les vérifications activées des quotas de comptes d'IA et l'installation de dépendances/CLI contactent leurs services. La traduction, le nettoyage vocal et les modifications d'enregistrement par IA facultatifs utilisent le fournisseur ou la CLI sélectionnés. La reconnaissance vocale Apple peut utiliser le réseau selon le système et la langue. |

### Autorisations par fonctionnalité

zisla demande l'autorisation requise lors de la première utilisation d'une fonctionnalité. Si vous avez auparavant refusé l'accès, ouvrez l'élément correspondant dans **Réglages Système > Confidentialité et sécurité** et autorisez `zisla` ; les noms peuvent varier selon la version de macOS.

| Autorisation ou réglage système | Quand elle est nécessaire | Portée autorisée |
| --- | --- | --- |
| Contrôle de l'appareil et accès aux données (Accessibilité sur certaines versions) | Insertion automatique des transcriptions vocales dans le champ de texte de l'application actuelle | Lit et localise les champs non protégés par mot de passe, puis transmet la transcription via les API d'accessibilité ou `Cmd+V`. Sans autorisation, la transcription est tout de même copiée dans le presse-papiers. |
| Microphone | Saisie vocale ou activation du microphone du studio | Capture le microphone sélectionné pour l'enregistrement ou l'écoute activée. |
| Reconnaissance vocale | Conversion de la parole enregistrée en texte | Traite uniquement la parole enregistrée activement. La saisie vocale nécessite les autorisations Microphone et Reconnaissance vocale. |
| Accès complet au disque | Consultation des courriels lorsque Mail.app ne s'exécute pas | Lit l'index local de `~/Library/Mail` pour afficher les comptes, expéditeurs, objets, résumés, dates et états de lecture. Cette voie d'accès à l'index Mail nécessite une autorisation. |
| Automatisation | Lecture, rédaction, réponse, marquage ou suppression des messages Mail.app ; lecture et écriture dans Apple Notes | Autorise zisla à contrôler les applications système correspondantes. Les autorisations de Courrier et de Notes peuvent être révoquées séparément dans les Réglages Système. |
| Calendriers ; Rappels | Utilisation du module Agenda | Lit et gère les événements de calendrier et les rappels avec des autorisations distinctes. |
| Service de localisation | Météo de la position actuelle | Demande une seule fois la position actuelle, sans suivi continu. Les lieux ajoutés manuellement ne nécessitent pas d'accès à la position. |
| Caméra | Ouverture du miroir ou activation de l'aperçu/enregistrement caméra du studio | Utilise la caméra sélectionnée pendant que la fonctionnalité correspondante est active. |
| Surveillance de l'entrée | Sons du clavier, statistiques de frappe, nettoyage du clavier et raccourcis de touches modificatrices seules ou de boutons latéraux de souris | Observe les événements de la fonctionnalité activée ; les statistiques de frappe restent locales. Les raccourcis globaux ordinaires ne nécessitent pas cette autorisation. |
| Bluetooth | Consultation de la batterie des accessoires dans Système → Batterie | Lit uniquement les informations publiques de batterie des appareils connectés ou jumelés. |
| Enregistrement de l'écran et du son système (Enregistrement de l'écran sur les anciennes versions de macOS) | Captures d'écran, aperçus de fenêtres, enregistrement, formes d'onde du son système et mixeur d'applications | Lit les images d'écran et les sources audio sélectionnées. L'enregistrement sauvegarde les sources activées localement ; le mixeur nécessite macOS 14.4+. |
| Notifications | Alertes Pomodoro | Émet une alerte sonore et affiche une notification locale à la fin du minuteur. |
| Dossiers sélectionnés par l'utilisateur (aucune autorisation manuelle requise) | Transfert de fichiers, importation et exportation ou choix d'un dossier de téléchargement | Le sélecteur de fichiers système accorde l'accès au dossier choisi. Ces fonctionnalités ne nécessitent pas l'accès complet au disque. |

Révoquer une autorisation désactive uniquement la fonctionnalité correspondante. Si une fonctionnalité reste indisponible après une modification de réglage, quittez puis rouvrez zisla et réessayez.

Le [guide macOS](mac/README.md) décrit l'ensemble des autorisations et du comportement réseau.

## Documentation

| Document | Objectif |
| --- | --- |
| [Guide de développement macOS](mac/README.md) | Modules, intégration de l'IA, dépendances, compilation, tests, autorisations et limites du système. |
| [Guide du site web (anglais)](../../../web/README.md) | Développement local, compilations de production et liens de téléchargement actuels. |
| [Guide du film de lancement (anglais)](../../../promo/README.md) | Aperçu Remotion, rendu, compositions, bandes sonores et licences des ressources. |
| [Conception de l'architecture et des performances](mac/Docs/architecture.md) | Déclenchement au bord supérieur, comportement des fenêtres, concurrence, médias et sécurité des téléchargements. |
| [Référence d'intégration CLI](mac/Docs/cli-reference.md) | Fournisseurs, commandes, champs et codes de sortie de `zislactl`. |
| [Conception des signatures et des publications](mac/Docs/releasing.md) | Signature, notarisation, DMG, canaux de mise à jour et validation des publications. |
| [Guide de contribution](CONTRIBUTING.md) | Environnement de développement, branches, commits et exigences des pull requests. |

## Contribuer

Les issues et les pull requests sont les bienvenues. Lisez d'abord le [guide de contribution](CONTRIBUTING.md). Signalez les problèmes de sécurité en privé via [GitHub Security Advisories](https://github.com/wzz6423/zisla/security/advisories/new), plutôt que d'ouvrir une issue publique.

## Licence

[PolyForm Noncommercial License 1.0.0](../../../LICENSE.md). L'utilisation non commerciale est autorisée ; la vente de ce logiciel et toute autre utilisation commerciale sont interdites.
