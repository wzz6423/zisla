import type { SiteContent } from '../content';

export const fr: SiteContent = {
  meta: {
    documentTitle: 'zisla · Espace de travail dynamique',
    description:
      'zisla est un espace macOS natif pour les tâches IA, les bilans quotidiens et le montage, avec compagnons personnalisés, captures et autorisations réunis.',
    ogTitle: 'zisla · Mettez ce qui se passe là où vous pouvez le voir',
    ogDescription:
      'Gardez vos tâches IA et votre journée en vue, enregistrez et montez sur Mac, importez votre compagnon et gérez les autorisations au même endroit.',
  },
  tagline: 'Espace de travail dynamique natif pour macOS',
  header: {
    navAriaLabel: 'Navigation principale',
    brandHomeAriaLabel: 'Accueil zisla',
    menuOpenLabel: 'Ouvrir le menu de navigation',
    menuCloseLabel: 'Fermer la navigation',
    menuButtonTitle: 'Ouvrir la navigation',
    navItems: {
      showcase: 'Fonctions',
      ai: 'Flux IA',
      download: 'Télécharger',
      changelog: 'Journal des modifications',
      faq: 'FAQ',
      developers: 'Développeurs',
    },
    downloadCta: 'Télécharger',
    downloadCtaAriaLabel: 'Aller à la section de téléchargement',
    languageLabel: 'Langue de l’interface',
    themeLabel: 'Apparence',
    themeModes: { auto: 'Automatique (système)', light: 'Mode clair', dark: 'Mode sombre' },
  },
  hero: {
    eyebrow: 'ESPACE DE TRAVAIL MACOS NATIF',
    title:
      'zisla<br><em>Ce qui se passe,<br>là où vous pouvez le voir.</em>',
    lede: 'Regroupez tâches IA, médias, fichiers et agenda en haut de l’écran. Après une copie, une barre d’actions rapides distincte en affiche un aperçu et propose l’étape suivante. Elle apparaît quand il faut et s’efface ensuite.',
    downloadCta: 'Télécharger',
    downloadCtaAriaLabel: 'Télécharger',
    sourceCta: 'Voir le code',
    sourceCtaAriaLabel: 'Voir le code source de zisla sur GitHub',
    hints: [
      'Amenez le pointeur en haut de l’écran, sans cliquer',
      'Après une copie, Command+N lance l’étape suivante',
      'Se referme toute seule, sans interrompre votre travail',
    ],
  },
  proof: {
    ariaLabel: 'Aperçu du produit',
    items: {
      modules: { title: '{count} modules en haut', desc: 'Activez les flux dont vous avez besoin' },
      os: { title: 'macOS 14+', desc: 'Une expérience de bureau native' },
      displays: { title: 'Multi-écran', desc: 'Écrans à encoche comme écrans externes' },
      local: { title: 'Local d’abord', desc: 'L’état IA ne lit jamais vos conversations' },
    },
  },
  showcase: {
    eyebrow: 'UN SEUL POINT D’ENTRÉE / FLUX QUOTIDIENS',
    title: 'Les flux du quotidien, <span>installés en haut de l’écran.</span>',
    lede: 'Des tâches IA au presse-papiers, à l’agenda et à l’état du système, zisla réunit des flux de bureau dispersés derrière un seul point d’entrée.',
    ariaLabel: 'Catalogue des fonctions de zisla',
    summaryMono: '{modules} MODULES / {groups} CATÉGORIES',
    summaryLede:
      'Des flux en haut de l’écran aux outils locaux, chaque tâche réellement possible est décrite ici.',
    summaryNote:
      '{modules} modules en haut de l’écran et {features} fonctions indépendantes, des aperçus de fenêtres et captures à la gestion de l’IA et aux apps recommandées.',
    groupNames: {
      island: 'Flux en haut de l’écran',
      ai: 'Flux IA',
      daily: 'Informations du quotidien',
      tools: 'Utilitaires',
    },
    groupCount: '{count} modules',
    pointsAriaLabel: 'Points clés de {name}',
    modules: {
      dashboard: {
        name: 'Accueil',
        caption:
          'Les cartes dynamiques n’apparaissent que pendant une session de concentration, une tâche IA ou un téléchargement en cours : rien n’occupe l’écran quand il ne se passe rien.',
        points: ['Apparaît au besoin', 'Progression en temps réel', 'Mise en page adaptative'],
      },
      shelf: {
        name: 'Casier',
        caption:
          'Faites glisser fichiers, audio, vidéo ou liens sur la bande de déclenchement en haut de l’écran pour les déposer dans le casier, les afficher dans le Finder ou ouvrir le menu de partage de macOS.',
        points: [
          'Glisser vers le haut pour déposer',
          'Afficher dans le Finder',
          'Menu de partage système',
        ],
      },
      clipboard: {
        name: 'Presse-papiers',
        caption:
          'Consultez l’historique du presse-papiers dans la Dynamic Island et filtrez par image, URL, chemin et type de fichier, et voyez quand chaque élément a été copié. Envoyez un élément vers les notes rapides, épinglez-le en favori ou supprimez-le. Vous pouvez supprimer automatiquement l’historique de plus de 7, 15 ou 30 jours en conservant les favoris. La suppression automatique est désactivée par défaut.',
        points: ['Historique dans l’île', 'Filtre par type', 'Notes rapides et favoris'],
      },
      aiMonitor: {
        name: 'Suivi IA',
        caption:
          'Détecte automatiquement l’activité des CLI IA, apps de bureau et IDE pris en charge et affiche les tâches, l’état, l’évolution cumulée des tokens et une carte thermique des contributions. Seuls les événements structurés sont analysés, jamais le texte des conversations. La détection des tâches Cursor est ajoutée, avec l’usage quotidien chiffré, sans afficher les quotas restants de Cursor et Muse Code ; les longues exécutions d’outils Cursor restent visibles.',
        points: [
          'Tâches agrégées entre outils',
          'Évolution de la consommation de tokens',
          'Ne lit ni invites ni réponses',
        ],
      },
      keyboardSound: {
        name: 'Sons de clavier',
        caption:
          'Joue 20 sonorités de clavier mécanique intégrées à chaque frappe globale, avec volume réglable et variation naturelle de hauteur, plus un son de relâchement pour les sonorités qui le prévoient. Avec les statistiques de saisie locales activées, vous consultez dans l’île le résumé du jour, les tendances, l’historique, la chronologie par app et une carte thermique par touche incluant F1-F12. Les totaux vocaux, la durée de dictée, la vitesse et le temps économisé figurent aussi sur le tableau de bord du clavier. Les nouvelles configurations activent les sons et les statistiques, avec des interrupteurs séparés.',
        points: [
          '20 sonorités intégrées',
          'Son de relâchement et variation de hauteur',
          'Statistiques activables séparément',
        ],
      },
      download: {
        name: 'Téléchargeur',
        caption:
          'Collez un lien ou laissez zisla repérer les liens du presse-papiers une fois l’option activée. Choisissez un format vidéo ou audio disponible et utilisez les Cookies d’un navigateur installé lorsqu’un téléchargement Douyin les nécessite. Enregistrez dans le dossier par défaut ou celui de votre choix, avec l’icône de la source, la progression en temps réel et l’état final. Choisissez le dossier de téléchargement dans Réglages → Emplacement de sauvegarde, indépendamment des captures et enregistrements. Les liens Bilibili téléchargent la partie choisie.',
        points: [
          'Choisir les formats vidéo ou audio disponibles',
          'Cookies de navigateur pour Douyin',
          'Icône de source et progression',
        ],
      },
      agenda: {
        name: 'Agenda et météo',
        caption:
          'Affiche la météo de votre position actuelle et de six lieux au maximum que vous choisissez. Consultez, ajoutez et supprimez des événements de calendrier et des rappels, et marquez un rappel comme terminé.',
        points: [
          'Cartes météo multi-lieux',
          'Calendrier et tâches',
          'Rappel terminé en un geste',
        ],
      },
      mail: {
        name: 'Mail',
        caption:
          'Lit les comptes activés dans Mail. Consultez la boîte de réception, marquez comme lu, répondez, rédigez et placez dans la corbeille depuis l’île, avec des indications claires dès qu’une autorisation manque. Choisissez des fichiers à joindre lors de la rédaction.',
        points: ['Comptes de Mail', 'Répondre et rédiger dans l’île', 'Autorisations expliquées'],
      },
      quickNotes: {
        name: 'Notes rapides',
        caption:
          'Adossé à l’app Notes du système : consultez, modifiez, créez et supprimez des notes avec un aperçu Markdown en direct, et rejoignez d’un geste les neuf premières notes avec Command+1 à 9. Les brouillons sont réécrits dans Notes automatiquement. Prévisualisez les pièces jointes manuscrites et modifiez le texte qui les précède ou les suit en conservant les originaux.',
        points: [
          'Les données restent dans Notes',
          'Éditeur Markdown',
          'Brouillons réenregistrés seuls',
        ],
      },
      volumeMixer: {
        name: 'Mixeur de volume par application',
        caption: 'Réglez séparément le volume et la sourdine des apps qui diffusent du son. Nécessite macOS 14.4 ou ultérieur et l’autorisation d’enregistrement audio du système.',
        points: ['Volume par app', 'Sourdine séparée', 'macOS 14.4+'],
      },
      toolbox: {
        name: 'Utilitaires',
        caption:
          'Minuteur de concentration, écran maintenu allumé, nettoyage de l’écran, nettoyage du clavier (qui bloque les frappes, F1-F12 comprises, pendant l’opération), téléprompteur, miroir et corbeille, sur une seule page.',
        points: [
          'Minuteur de concentration',
          'Bloque F1-F12 pendant le nettoyage',
          'Téléprompteur et miroir',
        ],
      },
      system: {
        name: 'État du système',
        caption:
          'Suivez CPU, GPU, mémoire, disque, réseau, ventilateurs et température NVMe SMART disponible. Affichez l’historique à la minute sur la période voulue ou exportez-le en .xlsx ; il reste conservé jusqu’à votre suppression. Consultez la charge, la santé, les cycles, la température et la capacité de la batterie du Mac et les niveaux des appareils proches, avec IPv4 et IPv6 publiques distinctes. Vérifiez caches, journaux, préférences résiduelles et dossiers de travail IA sans session conservée avant de les déplacer à la Corbeille. Le nettoyage facultatif intervient tous les 7, 15 ou 30 jours : éléments fiables seuls ou tous les éléments traitables, y compris ceux à vérifier. Il est désactivé par défaut.',
        points: [
          'Surveillance au niveau de la puce',
          'Graphiques d’historique et export .xlsx',
          'Vérifier avant de mettre à la Corbeille',
        ],
      },
    },
  },
  extensions: {
    eyebrow: 'DANS L’ÎLE ET AUTOUR',
    title: 'Loin de l’île, <span>toujours un outil de bureau.</span>',
    lede: 'Captures, voix, médias, téléchargements du navigateur et gestion de l’IA apparaissent là où c’est le plus pratique.',
    ariaLabel: 'Fonctions de bureau indépendantes',
    summaryMono: 'AU-DELÀ DE L’ÎLE',
    summaryLede: 'Les fonctions les plus utilisées, chacune à sa place naturelle.',
    summaryNote:
      'Aperçus de fenêtres, captures et actions rapides restent à portée de main ; les apps recommandées permettent de découvrir d’autres outils de bureau.',
    features: {
      floatingIsland: {
        title: 'Une île flottante adaptée à votre disposition',
        description: 'Utilisez la position de la caméra ou choisissez un emplacement sur un bord de l’écran. La position personnalisée est conservée entre les modes. Les présentations compactes horizontales et verticales adaptent leur longueur aux icônes, tâches IA, téléchargements et médias, avec une option pour afficher plus d’informations.',
        detail: 'Position personnalisée · Icônes persistantes · Informations adaptatives',
      },
      dailyBriefing: {
        title: 'Le bilan de votre journée',
        description: 'Choisissez parmi huit modèles, sélectionnez les données d’utilisation, de saisie, du système et d’activité zisla, puis prévisualisez le résultat. Exportez un PNG manuellement ou à une heure quotidienne choisie. L’historique Temps d’écran est utilisé quand il est activé et disponible ; une donnée absente n’est pas présentée comme un zéro mesuré. Choisissez un dossier d’export indépendant dans Réglages → Emplacement de sauvegarde.',
        detail: '8 modèles · Contenu au choix · Aperçu et export PNG programmé',
      },
      userCare: {
        title: 'Des rappels pendant le travail',
        description: 'Réglez l’intervalle des rappels de pause, d’hydratation, de mouvement et de repos des yeux. Les messages suivent l’heure de la journée ; les pauses naturelles, le verrouillage et la veille réinitialisent le compteur. La fin d’une séance et les actions sur les notes peuvent aussi afficher un bref retour. Activez ou désactivez ces rappels dans les réglages.',
        detail: 'Intervalle réglable · Messages selon l’heure · Respect de l’inactivité et de la veille',
      },
      contextNotes: {
        title: 'Des notes liées à un lieu',
        description: 'Enregistrez une note modifiable pour une page web, une fenêtre ou le bureau et retrouvez-la en y revenant. Joignez une capture de fenêtre, gérez les notes dans l’étagère et programmez des rappels répétés d’une heure à trois jours, ou désactivez-les.',
        detail: 'Notes contextuelles · Captures de fenêtres · Rappels récurrents',
      },
      recording: {
        title: 'Enregistrer et monter dans le studio',
        description: 'Enregistrez un écran, une fenêtre ou une zone avec son système, microphone et caméra facultatifs. Montez vidéos, sons, images et textes sur plusieurs pistes, avec animations, zooms et sous-titres. Réglez le lissage de la peau, la luminosité, l’affinement du visage et du corps, les effets vocaux et des traînées fluides du curseur dans la couleur choisie. Lisez le montage dans le studio. Formats : original, 16:9, 9:16, 1:1 ou 4:3 ; export vidéo, GIF, Live Photo ou audio, avec FFmpeg pour certains formats. Prévisualisez les propositions IA facultatives avant application. Le dossier d’enregistrement se règle séparément dans Réglages → Emplacement de sauvegarde.',
        detail: 'Effets de portrait et de voix · Traînées colorées du curseur · Lecture et export multipistes',
      },
      permissions: {
        title: 'Les autorisations au même endroit',
        description: 'Consultez les états dans Réglages → Autorisations, lancez les demandes prises en charge ou ouvrez la page système correspondante. L’accueil initial utilise la même liste et indique les réglages manuels.',
        detail: 'État des autorisations · Demandes et liens · Commun avec l’accueil',
      },
      pdf: {
        title: 'Outils PDF',
        description: 'Accessible dans les réglages, en dehors du carrousel de l’île. Quatorze opérations entièrement locales : fusionner, diviser, faire pivoter, recadrer, convertir des images et fichiers Office, convertir en images, exporter le texte, ajouter un filigrane texte ou image, numéroter les pages, chiffrer, supprimer un mot de passe et modifier les métadonnées.',
        detail: '14 outils locaux · Fusion dans votre ordre · Rien ne quitte votre Mac',
      },

      windowPreviews: {
        title: 'Voir une fenêtre, cliquer pour y passer',
        description:
          'Prévisualisez les fenêtres depuis le Dock ou avec Command-Tab, puis cliquez sur une carte pour activer la fenêtre. Les nouvelles configurations activent cette fonction ; gérez-la et ses autorisations dans les réglages.',
        detail: 'Dock et Command-Tab · Changer de fenêtre en un clic · Réglable',
      },
      capture: {
        title: 'Captures, captures défilantes et épinglage',
        description:
          'Capturez, épinglez ou assemblez des captures défilantes avec des raccourcis personnalisables. Surlignez, extrayez des zones d’image, arrondissez les coins et conservez les annotations à l’export. Reconnaissez et copiez du texte, traduisez-le puis copiez le résultat, ou exportez les tableaux reconnus en .xlsx. Rangez les captures dans l’étagère. Les réglages vérifient les conflits avec la dictée et les actions rapides. La boîte de dialogue s’ouvre dans le dossier de captures défini dans Réglages → Emplacement de sauvegarde. Les captures épinglées restent en place lors d’une nouvelle capture.',
        detail: 'Surlignage et extraction · Reconnaissance, traduction et copie · Coins arrondis et .xlsx',
      },
      voice: {
        title: 'Dictée et mise en forme',
        description:
          'Basculez avec une touche ou maintenez-la pour parler, avec la reconnaissance vocale du système, des vocabulaires spécialisés et des mots-clés personnalisés. Utilisez au besoin Ollama, LM Studio ou un modèle distant pour corriger la transcription en préservant le sens et mettre en forme les éléments explicitement énumérés.',
        detail: 'Deux modes d’enregistrement · Vocabulaires et mots-clés · Modèle facultatif',
      },
      media: {
        title: 'Médias et sons d’ambiance du système',
        description:
          'Pilotez la lecture en cours depuis le haut de l’île, ou choisissez un son d’ambiance macOS. La lecture peut s’arrêter d’elle-même au verrouillage, au lancement de l’économiseur d’écran ou à la veille de l’écran. Choisissez une forme d’onde ou une lueur autour de la pochette ; la progression est aussi visible dans les présentations compactes et flottantes.',
        detail: 'Contrôle de lecture · Paroles synchronisées · Arrêt automatique',
      },
      browserDownloads: {
        title: 'Progression des téléchargements',
        description:
          'Détecte les téléchargements de Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera et Arc, et affiche leur source et leur progression en haut de l’écran.',
        detail: '8 navigateurs · Source identifiée · Avis de fin',
      },
      copyAssistant: {
        title: 'Actions rapides et étapes suivantes',
        description:
          'Une fois activé, le texte, les liens, les fichiers ou les images copiés s’affichent dans une barre distincte en haut de l’écran. Il reconnaît les liens, les noms d’apps installées localement et les noms d’émojis, et peut convertir les montants copiés aux taux de change en temps réel ; chaque étape suivante n’est exécutée qu’après votre confirmation. Ouvrez le dossier d’un fichier via les actions rapides après un téléchargement ou un transfert AirDrop. Les dossiers Chrome par défaut ou choisis sont pris en charge, avec une activation indépendante de la progression des téléchargements. Les adresses IP disposent d’actions distinctes pour la recherche et l’ouverture du lien. Les conversions reconnaissent les unités monétaires mineures et le catalogue utilise Emoji 18.0. Les textes et images enregistrés utilisent le dossier indépendant des actions rapides dans Réglages → Emplacement de sauvegarde.',
        detail: 'Reconnaissance locale · Conversion aux taux en temps réel · Command+N par défaut',
      },
      aiManagement: {
        title: 'Gestion des CLI IA et des Skills',
        description:
          'Détectez, installez, mettez à jour et supprimez les CLI IA courantes depuis les réglages, et consultez et gérez les Skills locaux, pour passer moins souvent d’un terminal ou d’un outil à l’autre.',
        detail: 'Détection et installation · Mise à jour et suppression · Skills locaux',
      },
      pet: {
        title: 'Mascotte de l’île',
        description:
          'Choisissez dans le catalogue enrichi d’animaux et de personnages, ou importez une image, une animation ou une vidéo compatible et nommez votre compagnon. Placez-le d’un côté de l’île et supprimez les compagnons importés dans les réglages. Animations de 30 secondes maximum, fichiers de 100 MB maximum.',
        detail: 'Catalogue enrichi · Import d’images et vidéos · Suppression des compagnons personnalisés',
      },
      lockScreen: {
        title: 'Informations sur l’écran verrouillé',
        description:
          'Affichez au besoin la date, l’état et la lecture en cours sur l’écran verrouillé de macOS. Il s’agit d’une surcouche distincte, jamais présente dans la liste des modules ni dans le carrousel de l’île.',
        detail: 'Surcouche distincte · Activation au choix · Ne prend jamais le focus',
      },
      recommendedTools: {
        title: 'Apps recommandées',
        description:
          'Découvrez OpenScreen pour la capture vidéo et le montage, DockDoor pour les aperçus de fenêtres et le changement d’app, et Quiet.md pour les notes locales. Ces applications tierces s’installent séparément.',
        detail: 'Découvrir des outils de bureau · Apps tierces · Installation séparée',
      },
    },
  },
  ai: {
    eyebrow: 'UNE IA SANS BOÎTE NOIRE',
    title: 'Voir l’état de l’IA <span>sans lire la conversation.</span>',
    lede: 'Tâches, état et évolution des tokens restent sur votre Mac. Cette page décrit la fonction et n’invente aucune capture d’une tâche en cours.',
    summaryMono: 'ÉTAT LOCAL / LIMITES CLAIRES',
    summaryLede:
      'Reliez les outils IA que vous utilisez déjà tout en gardant les limites de contexte que votre travail exige.',
    summaryNote:
      'Cette page décrit seulement la portée de la détection, la limite des données et le mode de connexion : elle ne simule aucune session en cours.',
    toolsHeading: 'Outils IA pris en charge',
    toolsLede:
      'Détecte l’activité des CLI, apps de bureau et IDE pris en charge, et agrège l’état des tâches.',
    toolsAriaLabel: 'Outils IA pris en charge',
    boundariesHeading: 'Seules les limites d’état sont enregistrées',
    privacyPoints: [
      'Analyse uniquement le type d’événement, l’état, l’horodatage, le modèle et l’identifiant de session des événements structurés',
      'Ne lit jamais le texte des invites ni des réponses',
      'Protocole et état sont conservés sur votre Mac',
    ],
    bridgeHeading: 'Reliez vos propres tâches',
    bridgeLede:
      'Utilisez zislactl pour envoyer l’état structuré de tâches externes vers la barre d’état.',
    zislactlTaskTitle: 'Compilation et publication',
    copyZislactlAriaLabel: 'Copier la commande zislactl',
  },
  flow: {
    eyebrow: 'RYTHME D’INTERACTION',
    title: 'Monter, <span>regarder, puis laisser filer.</span>',
    lede: 'Elle ne prend jamais le focus et se referme dès que vous avez vu.',
    ariaLabel: 'Rythme d’interaction en haut de l’écran',
    summaryMono: 'BARRE D’ÉTAT / 3 ÉTAPES',
    summaryLede: 'S’ouvre quand vous en avez besoin, se referme la lecture faite.',
    summaryNote:
      'Déclenchée par la position du pointeur. Sans rien à montrer, elle n’occupe aucun espace visuel et ne prend jamais le focus de l’app en cours.',
    steps: {
      trigger: {
        phase: 'Déclencher',
        title: 'Amener le pointeur en haut, au centre',
        desc: 'Même geste sur les écrans à encoche et externes, et aucune boucle de rendu ne tourne quand l’île est masquée.',
      },
      review: {
        phase: 'Consulter',
        title: 'Voir l’état actuel d’un coup d’œil',
        desc: 'Médias, fichiers, IA, agenda et outils système sont réunis au même endroit.',
      },
      dismiss: {
        phase: 'Refermer',
        title: 'Reprendre votre travail',
        desc: 'Éloignez le pointeur et elle se referme ; s’ouvrir n’active jamais l’app et ne prend pas le focus.',
      },
    },
  },
  download: {
    eyebrow: 'DISPONIBLE QUAND VOUS VOULEZ',
    title: 'Télécharger zisla',
    copy: 'Pour les Mac Apple silicon. Versions, autres architectures et sommes de contrôle sont sur la page de publication. Après installation, zisla peut chercher les nouvelles versions sur le canal choisi : Sparkle vérifie d’abord la signature, puis télécharge, installe et redémarre manuellement ou automatiquement selon vos réglages, et les mises à jour conservent les permissions déjà accordées. Les réglages de mise à jour proposent aussi un lien direct vers les issues GitHub pour vos retours. Si une version ne vous concerne pas, ignorez-la : zisla ne la rappellera plus. Consultez les notes de version avant l’installation et après le redémarrage.',
    primaryCta: 'Télécharger',
    primaryCtaAriaLabel: 'Télécharger',
    releaseCta: 'Voir la publication',
    releaseCtaAriaLabel: 'Voir les détails de la publication sur GitHub',
    brewMono: 'HOMEBREW / UNE COMMANDE',
    brewNote: 'Sparkle met zisla à jour lui-même : brew upgrade ne remplace l\'app que si la version installée est réellement plus ancienne que celle du tap, car depuis Homebrew 5.1.6 c\'est la version inscrite dans l\'app qui est lue. Nommer le cask, comme dans brew upgrade --cask zisla, se fonde sur les registres de Homebrew et peut vous ramener à la version du tap après une mise à jour Sparkle. Le tap ne sert que des versions stables. Ce tap est tiers et l\'app n\'est pas notarisée : au premier lancement, choisissez « Ouvrir quand même » dans Réglages Système → Confidentialité et sécurité.',
    copyBrewCommandAriaLabel: 'Copier la commande d\'installation Homebrew',
    notes: {
      system: {
        term: 'Système',
        value: 'macOS 14 ou version ultérieure · les Mac Apple silicon sont la configuration prise en charge aujourd’hui',
      },
      install: { term: 'Installation', value: 'Montez le DMG et déposez l’app dans Applications' },
      package: { term: 'Paquet', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Autres architectures', value: 'Page de publication' },
      mirror: { term: 'Miroir', value: 'Gitee Releases' },
    },
  },
  changelog: {
    releaseNotes: {
      'v0.1.22': [
        'Le studio ajoute lissage de la peau, luminosité, affinement du visage et du corps, préréglages vocaux ajustables et écoute facultative du microphone. Les effets se règlent avant l’enregistrement et pendant le montage.',
        'Les traînées fluides du curseur ont une couleur au choix. La lecture dans le studio restitue le montage avec ses pistes, effets et sons.',
        'Réglages → Emplacement de sauvegarde sépare téléchargements, captures, enregistrements, actions rapides et bilans quotidiens. La mise à jour conserve les anciens emplacements, puis chaque dossier peut être changé indépendamment.',
        'Le nettoyage facultatif déplace les fichiers inutiles à la Corbeille tous les 7, 15 ou 30 jours. Choisissez les éléments fiables ou tous les éléments traitables, y compris ceux à vérifier ; il est désactivé par défaut. L’analyse ajoute les dossiers de travail IA sans session conservée, en protégeant les sessions conservées et les dossiers récents.',
        'L’historique du presse-papiers peut supprimer automatiquement les entrées de plus de 7, 15 ou 30 jours tout en conservant les favoris. Cette option est désactivée par défaut.',
        'Les notes rapides prévisualisent les pièces jointes manuscrites et permettent de modifier le texte avant ou après via Notes, en conservant les pièces jointes originales.',
        'Le suivi IA masque les quotas d’abonnement restants, garde l’usage quotidien et améliore le défilement des graphiques et les libellés des mois. Les réglages de batterie rejoignent l’état du système.',
        'Quiet.md rejoint les apps recommandées pour les notes locales, avec installation et gestion dans les réglages.',
        'Bilibili télécharge la partie choisie et accepte davantage de liens. La suppression dans le calendrier vise l’occurrence récurrente choisie. Les captures épinglées restent visibles entre captures, avec des libellés d’outils plus lisibles et des badges de taille plus fiables.',
      ],
      'v0.1.21': [
        'La surveillance système conserve par défaut tout l’historique à la minute, existant et nouveau, jusqu’à son effacement manuel. Les graphiques par période et l’export .xlsx restent disponibles.',
        'Téléchargements, enregistrements et captures d’écran partagent un emplacement. Les captures s’enregistrent depuis le dossier de téléchargement actuel ; le réglage d’emplacement propre aux enregistrements, qui faisait doublon, a été supprimé.',
        'L’emplacement d’affichage des états et son entrée de recherche n’apparaissent que pour les pilules positionnées librement. La ligne est masquée si une encoche ou une pilule à la caméra ne peut utiliser que la barre des menus.',
        'Le compte à rebours des actions rapides utilise une barre de progression en bas dans les dispositions avec encoche. Les pilules conservent la progression sur tout le pourtour.',
      ],
      'v0.1.20': [
        'Choisissez parmi huit modèles, sélectionnez les données d’utilisation, de saisie, du système et d’activité zisla, puis prévisualisez le résultat. Exportez un PNG manuellement ou à une heure quotidienne choisie. L’historique Temps d’écran est utilisé quand il est activé et disponible ; une donnée absente n’est pas présentée comme un zéro mesuré.',
        'Réglez l’intervalle des rappels de pause, d’hydratation, de mouvement et de repos des yeux. Les messages suivent l’heure de la journée ; les pauses naturelles, le verrouillage et la veille réinitialisent le compteur. La fin d’une séance et les actions sur les notes peuvent aussi afficher un bref retour. Activez ou désactivez ces rappels dans les réglages. Enregistrez une note modifiable pour une page web, une fenêtre ou le bureau et retrouvez-la en y revenant. Joignez une capture de fenêtre, gérez les notes dans l’étagère et programmez des rappels répétés d’une heure à trois jours, ou désactivez-les.',
        'Utilisez la position de la caméra ou choisissez un emplacement sur un bord de l’écran. La position personnalisée est conservée entre les modes. Les présentations compactes horizontales et verticales adaptent leur longueur aux icônes, tâches IA, téléchargements et médias, avec une option pour afficher plus d’informations. Choisissez une forme d’onde ou une lueur autour de la pochette ; la progression est aussi visible dans les présentations compactes et flottantes.',
        'Choisissez dans le catalogue enrichi d’animaux et de personnages, ou importez une image, une animation ou une vidéo compatible et nommez votre compagnon. Placez-le d’un côté de l’île et supprimez les compagnons importés dans les réglages. Animations de 30 secondes maximum, fichiers de 100 MB maximum.',
        'Enregistrez un écran, une fenêtre ou une zone avec son système, microphone et caméra facultatifs. Montez vidéos, sons, images et textes sur plusieurs pistes ; ajoutez animations, zooms et sous-titres avec un aperçu net. Choisissez le format original, 16:9, 9:16, 1:1 ou 4:3. Exportez vidéo, GIF, Live Photo ou audio ; certains formats nécessitent FFmpeg. Les propositions IA facultatives sont prévisualisées avant application.',
        'Capturez, épinglez ou assemblez des captures défilantes avec des raccourcis personnalisables. Surlignez, extrayez des zones d’image, arrondissez les coins et conservez les annotations à l’export. Reconnaissez et copiez du texte, traduisez-le puis copiez le résultat, ou exportez les tableaux reconnus en .xlsx. Rangez les captures dans l’étagère. Les réglages vérifient les conflits avec la dictée et les actions rapides.',
        'La détection des tâches Cursor est ajoutée, avec l’usage numérique et les quotas d’abonnement disponibles de Cursor et Muse Code ; les longues exécutions d’outils Cursor restent visibles. Les adresses IP disposent d’actions distinctes pour la recherche et l’ouverture du lien. Les conversions reconnaissent les unités monétaires mineures et le catalogue utilise Emoji 18.0.',
        'Réglez séparément le volume et la sourdine des apps qui diffusent du son. Nécessite macOS 14.4 ou ultérieur et l’autorisation d’enregistrement audio du système. Accessible dans les réglages, en dehors du carrousel de l’île. Consultez les états dans Réglages → Autorisations, lancez les demandes prises en charge ou ouvrez la page système correspondante. L’accueil initial utilise la même liste et indique les réglages manuels. Les totaux vocaux, la durée de dictée, la vitesse et le temps économisé figurent aussi sur le tableau de bord du clavier. Les nouvelles configurations activent les sons et les statistiques, avec des interrupteurs séparés. Choisissez des fichiers à joindre lors de la rédaction. Consultez les notes de version avant l’installation et après le redémarrage.',
      ],
    },
    eyebrow: 'Journal des modifications',
    title: 'Les changements de chaque version de zisla : nouveautés, améliorations et corrections.',
    lede: 'Les changements de chaque version de zisla : nouveautés, améliorations et corrections.',
    ariaLabel: 'historique des versions de zisla',
    releaseCountLabel: 'versions',
    latestLabel: 'dernière',
    shippedLabel: 'publié',
    latestBadge: 'Dernière',
    noteLabel: 'version',
    pagerAriaLabel: 'Pages du journal des modifications',
    pageLabel: 'Page {page}',
    prevPageLabel: 'Précédent',
    nextPageLabel: 'Suivant',
  },
  faq: {
    eyebrow: 'QUELQUES RÉPONSES NETTES',
    title: 'Questions fréquentes.',
    lede: 'Autorisations, confidentialité et compatibilité.',
    items: {
      audience: {
        question: 'À qui zisla s’adresse-t-il ?',
        answer:
          'Aux utilisateurs de Mac qui veulent réunir IA, médias, fichiers et agenda. Les écrans sans encoche sont pris en charge aussi.',
      },
      aiPrivacy: {
        question: 'zisla lit-il mes conversations avec l’IA ?',
        answer:
          'Non. Le suivi de l’état IA lit uniquement l’état des tâches, jamais le texte des invites ni des réponses.',
      },
      copyAssistant: {
        question: 'Les actions rapides ouvrent-elles ou envoient-elles ce que je copie ?',
        answer:
          'Non. Une fois activé, la reconnaissance et l’aperçu se font entièrement sur votre Mac, et zisla n’exécute une étape qu’après votre clic ou votre raccourci.',
      },
      permissions: {
        question: 'De quelles autorisations système zisla a-t-il besoin ?',
        answer: '<p>Réglages → Autorisations regroupe les états, les demandes et les liens vers les Réglages Système. Certaines autorisations nécessitent une configuration manuelle. Vous choisissez les demandes à lancer ; l’accueil initial propose aussi ces commandes.</p><p>L’enregistrement de l’écran et du son système, le microphone et la caméra servent aux captures, à l’enregistrement, au mixeur et au miroir selon la fonction. La dictée utilise aussi la reconnaissance vocale. Calendriers, Rappels, Localisation, Bluetooth et Automatisation servent aux fonctions associées. Ajouter une ville météo manuellement ne nécessite pas la localisation.</p><p>Les nouvelles configurations activent sons du clavier et statistiques, désactivables séparément. La surveillance de l’entrée est nécessaire pour les événements globaux. Les statistiques gardent uniquement comptes, codes de touches, dates et noms d’apps, jamais le texte saisi. L’accessibilité sert à l’insertion, aux gestes, au nettoyage et aux fenêtres.</p><p>L’accès complet au disque peut être nécessaire pour l’index local du courrier et l’historique Temps d’écran des bilans quotidiens. Le sélecteur de fichiers accorde l’accès au dossier choisi. Désactivez les fonctions dans zisla ou révoquez les autorisations dans Réglages Système → Confidentialité et sécurité.</p>',
      },
      localVoice: {
        question: 'Comment utiliser un modèle local pour corriger une transcription vocale ?',
        answer: `
      <p>Ollama, LM Studio et les autres services locaux compatibles avec OpenAI sont pris en charge.</p>
      <ol>
        <li>Téléchargez ou chargez le modèle souhaité dans votre application de modèles locaux, puis démarrez son service.</li>
        <li>Ouvrez Réglages → Voix → Modèles locaux, ajoutez et activez une configuration, choisissez Ollama ou LM Studio, puis saisissez l’URL du service. Pour un autre service compatible avec OpenAI, choisissez également LM Studio. Laissez API Key vide si le service ne demande pas d’authentification.</li>
        <li>Sélectionnez un modèle détecté automatiquement, puis choisissez cette configuration dans Modèle d'organisation vocale → Utiliser le modèle.</li>
      </ol>
      <p>zisla suggère un modèle Gemma 4 QAT selon votre puce et la mémoire vive totale. Le modèle recommandé n’est ni téléchargé ni chargé automatiquement.</p>
    `.trim(),
      },
      network: {
        question: 'zisla se connecte-t-il à Internet ?',
        answer:
          'La météo, la vérification signée des mises à jour, les téléchargements que vous lancez et la mise en forme vocale distante facultative utilisent le réseau au besoin. La détection des liens du presse-papiers se fait entièrement sur votre Mac et ne lance jamais de téléchargement d’elle-même. Le modèle local corrige le texte après la transcription ; la reconnaissance vocale Apple peut toujours utiliser le réseau, selon la langue et la prise en charge du système.',
      },
      multiDisplay: {
        question: 'zisla prend-il en charge plusieurs écrans ?',
        answer:
          'Oui : plusieurs écrans, les Spaces et les apps en plein écran classique, et l’ouverture ne prend jamais le focus.',
      },
      intel: {
        question: 'Puis-je l’utiliser sur un Mac Intel ?',
        answer:
          'Une version pour machines Intel peut exister, mais la compatibilité n’est pas garantie. Les Mac Apple silicon sont la configuration prise en charge aujourd’hui.',
      },
      storage: {
        question: 'Où zisla stocke-t-il ses données ?',
        answer:
          'Les données locales se trouvent dans ~/Library/Application Support/zisla/. Les statistiques de saisie sont conservées à part dans ~/Library/Application Support/zisla/typing-stats.sqlite3. Les notes rapides utilisent l’app Notes du système. Réglages → Emplacement de sauvegarde propose des dossiers indépendants pour téléchargements, captures, enregistrements, actions rapides et bilans quotidiens. À la mise à jour, chacun conserve le dossier partagé précédent, puis peut être changé séparément.',
      },
    },
  },
  developers: {
    eyebrow: 'OPEN SOURCE PAR DÉFAUT',
    title: 'Ressources pour développeurs.',
    lede: 'Sous licence PolyForm Noncommercial 1.0.0 : usage non commercial uniquement, telle quelle ou compilée depuis les sources.',
    docs: {
      macos: {
        title: 'Guide de développement macOS',
        description: 'Fonctions, compilation, tests et limites système',
      },
      architecture: {
        title: 'Architecture et performances',
        description: 'Déclenchement en haut de l’écran, fenêtres et performances',
      },
      cli: { title: 'Intégration CLI', description: 'Commandes et champs de zislactl' },
      releasing: {
        title: 'Signature et publication',
        description: 'Signature, notarisation et processus de publication',
      },
      contributing: {
        title: 'Guide de contribution',
        description: 'Environnement, branches, commits et exigences des pull requests',
      },
    },
    quickStartMono: 'DÉMARRAGE RAPIDE / SOURCES',
    quickStartHeading: 'Lancez depuis les sources, ou reliez vos propres tâches.',
    copyRunCommandAriaLabel: 'Copier la commande de lancement depuis les sources',
    githubRepoLabel: 'Dépôt GitHub',
    giteeRepoLabel: 'Dépôt Gitee',
    checksumLabel: 'SHA-256',
    performancePoints: [
      'Prend en charge plusieurs écrans, les Spaces et les apps en plein écran classique ; l’ouverture n’active jamais l’app et ne prend pas le focus',
      'Masquée, elle ne crée aucune fenêtre transparente permanente et ne fait tourner aucune boucle de rendu : l’ouverture repose sur l’observation d’événements globaux et un calcul de géométrie',
      'Utilise une seule couche de matériau système et passe à un fond opaque dès que « Réduire la transparence » est activé',
      'Liquid Glass sur macOS 26 et versions ultérieures, avec repli automatique sur les matériaux natifs sur macOS 14 et 15',
      'L’encoche physique est déduite de la zone de sécurité du système ; les écrans externes sans encoche reçoivent une barre d’état simulée dans une surcouche dédiée',
    ],
  },
  footer: {
    brandHomeAriaLabel: 'Retour à l’accueil de zisla',
    previewChannelLabel: 'Canal Preview',
    tagline: 'Open source, natif, et sous votre contrôle.',
  },
  common: {
    copyCommandTitle: 'Copier la commande',
    copiedAriaLabel: 'Copié',
  },
  toast: {
    runCommandCopied: 'Commande de lancement copiée',
    zislactlCopied: 'Commande zislactl copiée',
    brewCommandCopied: 'Commande d\'installation Homebrew copiée',
  },
};
