# Conception de l'architecture et des performances

**Français** | [Langues de la documentation](../../../README.md)

## Déclenchement au bord supérieur

L'état masqué n'a aucune fenêtre transparente. `PointerEdgeMonitor` installe des observateurs globaux et locaux `NSEvent` pour les déplacements de souris et les glissements ; `ScreenLayoutEngine` utilise uniquement la géométrie pour déterminer si le pointeur entre dans la zone de 6 px en haut, au centre de chaque écran.

Chaque écran dispose d'une identité stable associant `NSScreenNumber` à son `CGDirectDisplayID`. La disposition s'ancre sur `screen.frame.maxY`, ce qui prend en charge les coordonnées négatives, les écrans superposés verticalement et les écrans externes sans encoche.

## Fenêtre

L'îlot principal conserve un seul `.borderless + .nonactivatingPanel` :

- Il utilise le niveau `.statusBar` et ne recouvre ni l'écran verrouillé ni le menu système.
- `.canJoinAllSpaces + .fullScreenAuxiliary` prend en charge Spaces et les applications plein écran ordinaires.
- Le déploiement au survol n'appelle jamais `NSApp.activate` et ne détourne donc pas le focus de l'application actuelle.
- L'état masqué utilise `orderOut`, de sorte qu'une fenêtre transparente n'occupe pas la zone de la barre des menus.

Les panneaux de notification gauche et droit sont créés à la demande et masqués dès que leurs files sont vides.

## État et concurrence

- AppKit, l'état SwiftUI et le contrôle des fenêtres restent sur `MainActor`.
- Les téléchargements, la météo et les requêtes GitHub utilisent des actors.
- L'état d'IA écrit par les hooks est surveillé via les événements du système de fichiers des répertoires. Chaque source de session compare la date de modification et la taille du dernier fichier local de session ou d'activité et réutilise le cache d'analyse si rien n'a changé.
- La détection automatique lit seulement les événements structurés, marqueurs d'état fixes et métadonnées nécessaires pour déterminer l'état des tâches. Elle ne lit pas les invites ni les réponses, et l'échec d'un parseur de fournisseur ne bloque pas les autres.
- Les délais de repli utilisent des `Task` annulables et un jeton de génération afin qu'une ancienne tâche ne puisse pas masquer un îlot déjà rouvert.
- L'état masqué n'utilise ni `TimelineView`, ni minuteur à 60 Hz, ni soumission continue d'animations.

## Détection des médias

MediaRemote fournit le titre, la pochette, la progression et les commandes. Les propriétés d'objets de processus de Core Audio 14.4+ confirment l'existence d'un flux de sortie actif et fournissent une application source de repli si les métadonnées manquent. Les listes de processus et l'état de sortie utilisent des observateurs de propriétés et une vérification périodique bornée ; aucun contenu audio n'est capturé et aucune autorisation d'enregistrement d'écran ou d'accessibilité n'est demandée. Les sources en pause, arrêtées ou muettes ne restent pas dans la zone multimédia.

## Enregistrement et mixage des applications

L'enregistrement d'écran et le mixeur de volume des applications sont distincts de la détection des métadonnées. L'enregistrement demande l'autorisation d'enregistrement d'écran et celles des microphone/caméra activés, conserve les médias sélectionnés localement et gère les projets dans le dossier d'enregistrement choisi. Le mixeur utilise des taps Core Audio sur macOS 14.4+ et nécessite l'autorisation d'enregistrement du son système.

## Matériaux

macOS 26 utilise une seule couche SwiftUI `glassEffect` ; macOS 14/15 utilisent une seule couche `NSVisualEffectView`. Réduire la transparence active un fond opaque. L'îlot n'empile pas plusieurs couches de flou ou de matériau.

## Limite de sécurité des téléchargements

Swift démarre `yt-dlp` avec `Process.executableURL` et un tableau d'arguments ; l'URL est toujours une valeur argv distincte après `--`. La configuration d'exécution, les plugins et exec sont désactivés, les flux de sortie sont drainés simultanément et la progression est analysée via une sentinelle JSON.

Une tâche réussit uniquement si le code de sortie est 0, le chemin de sortie existe et le chemin résolu reste dans le dossier autorisé. Chaque tâche nettoie uniquement son propre dossier temporaire nommé par UUID.

## Vérification et téléchargement des mises à jour

Le canal de mise à jour sélectionné résout une fois par exécution le code pays de la sortie Internet publique, puis utilise Sparkle pour récupérer l'appcast signé de la version installée, télécharger le ZIP référencé via HTTPS, vérifier les signatures EdDSA de l'archive et du flux avant extraction, remplacer l'application et la relancer. `CN` commence par Gitee (`update-release` pour Release, `preview` pour Preview) et réessaie une fois le flux GitHub correspondant ; les autres codes commencent par GitHub puis réessaient Gitee une fois. Une recherche indisponible conserve Gitee d'abord ; chaque flux pointe vers un ZIP signé sur son propre hôte. Une publication fournit un appcast par architecture à côté de `appcast.xml` ; une installation monoarchitecture demande celui de sa propre tranche, une tranche x86_64 exécutée par traduction demandant `arm64`, et n'est donc jamais remplacée par la version universelle. Une installation universelle compte les tranches de son exécutable et conserve `appcast.xml`, également utilisé par les versions antérieures aux mises à jour par architecture. Changer le réglage affecte les vérifications automatiques et manuelles et réinitialise le prochain cycle Sparkle. La clé publique intégrée ne contient aucune information de compte ; la clé privée de signature reste dans le trousseau macOS du responsable des publications ou dans un fichier privé sécurisé séparément.
