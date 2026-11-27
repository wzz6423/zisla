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
      help: "Aide",
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
          'Les cartes dynamiques n’apparaissent que pendant une session de concentration, une tâche IA ou un téléchargement en cours : rien n’occupe l’écran quand il ne se passe rien. L’accueil regroupe les tâches IA en cours par application.',
        points: ['Apparaît au besoin', 'Progression en temps réel', 'Mise en page adaptative'],
      },
      shelf: {
        name: 'Casier',
        caption:
          "Gardez vos fichiers sur l’étagère pour chercher, sélectionner et partager. Créez un ZIP ou PDF, redimensionnez ou convertissez les images, puis envoyez vers les notes ou le studio.",
        points: ['Recherche et actions groupées', 'Images vers PDF et Notes rapides', 'Montage vidéo dans le studio'],
      },
      clipboard: {
        name: 'Presse-papiers',
        caption:
          "Parcourez et cherchez l’historique local, y compris le texte des images. Filtrez par type ou application, gardez des favoris et envoyez vers les notes rapides.",
        points: ['Historique dans l’île', 'Filtre par type', 'Notes rapides et favoris'],
      },
      aiMonitor: {
        name: 'Suivi IA',
        caption:
          'Rassemble les tâches et l’état des CLI IA, apps de bureau et IDE. Les données chiffrées fiables alimentent les tendances de tokens et la carte des contributions ; choisissez une date pour voir les tokens d’entrée, de sortie et totaux par fournisseur et modèle. Consultez l’historique dans les réglages, exportez-le entièrement en .xlsx ou effacez-le. Affiche les quotas réels, leur réinitialisation et les alertes de quota faible, dont les fenêtres 5h/7d et les budgets Cursor en dollars lorsqu’ils sont disponibles. Ne lit pas le texte des invites ni des réponses. Les présentations compactes affichent aussi les quotas restants sous forme d’anneaux. Choisissez les régions des comptes indépendamment ; les relevés quotidiens et les couleurs du quota restant concordent dans toutes les présentations. Les quotas Gemini et Claude/GPT d’Antigravity ont un suivi, un affichage et des alertes indépendants. Les quotas de conversation de Gemini App utilisent un Cookie web du même compte Google ; Gemini CLI reste distinct.',
        points: ['Tâches de plusieurs outils IA', 'Historique par modèle et export .xlsx', 'Quotas et dates de réinitialisation'],
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
          'Collez un lien ou laissez zisla repérer les liens du presse-papiers une fois l’option activée. Choisissez un format vidéo ou audio disponible et utilisez les Cookies d’un navigateur installé lorsqu’un téléchargement Douyin les nécessite. Enregistrez dans le dossier par défaut ou celui de votre choix, avec l’icône de la source, la progression en temps réel et l’état final. Choisissez le dossier de téléchargement dans Réglages → Emplacement de sauvegarde, indépendamment des captures et enregistrements. Les liens Bilibili téléchargent la partie choisie. Gérez les composants dans Réglages → Composants requis, avec la possibilité de mettre à jour chaque jour ceux déjà installés.',
        points: [
          'Choisir les formats vidéo ou audio disponibles',
          'Cookies de navigateur pour Douyin',
          'Icône de source et progression',
        ],
      },
      agenda: {
        name: 'Agenda et météo',
        caption:
          'Affiche la météo de votre position et de six lieux choisis au maximum. Consultez, ajoutez ou supprimez des événements et rappels, puis marquez les rappels comme terminés. Les événements avec un lien de réunion affichent un compte à rebours 10 minutes avant le début et permettent de rejoindre en un clic. Créez une note de réunion ou associez et dissociez des notes contextuelles existantes. L’heure de mise à jour de la météo apparaît dans l’en-tête, à gauche du bouton d’actualisation.',
        points: ['Météo et calendrier', 'Compte à rebours de 10 minutes', 'Rejoindre et associer des notes'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Lit les comptes activés dans Mail. Consultez la boîte de réception, marquez un message ou tous les messages reçus comme lus, répondez, rédigez et déplacez des messages dans la Corbeille depuis l’île. Choisissez des pièces jointes pendant la rédaction ; les autorisations manquantes sont clairement indiquées.',
        points: ['Comptes de Mail', 'Répondre et rédiger dans l’île', 'Autorisations expliquées'],
      },
      quickNotes: {
        name: 'Notes rapides',
        caption:
          'Adossé à l’app Notes du système : consultez, modifiez, créez et supprimez des notes avec un aperçu Markdown en direct, et rejoignez d’un geste les neuf premières notes avec Command+1 à 9. Les brouillons sont réécrits dans Notes automatiquement. Prévisualisez les pièces jointes manuscrites et modifiez le texte qui les précède ou les suit en conservant les originaux. Naviguez entre les notes avec Command et les flèches. Le texte collé reprend la typographie native du corps de texte.',
        points: [
          'Les données restent dans Notes',
          'Éditeur Markdown',
          'Brouillons réenregistrés seuls',
        ],
      },
      volumeMixer: {
        name: 'Mixeur de volume par application',
        caption: 'Réglez séparément le volume et la sourdine des apps qui diffusent du son. Nécessite macOS 14.4 ou ultérieur et l’autorisation d’enregistrement audio du système. Les réglages de volume sont mémorisés par application ; les sources audio périmées disparaissent à l’arrêt de la lecture.',
        points: ['Volume par app', 'Sourdine séparée', 'macOS 14.4+'],
      },
      toolbox: {
        name: 'Utilitaires',
        caption:
          'Minuteur de concentration, maintien de l’écran éveillé, nettoyage de l’écran ou du clavier avec blocage des touches F1-F12, téléprompteur, miroir et Corbeille sur une même page. Mettez le Pomodoro en pause, reprenez-le, réinitialisez-le et suivez sa progression dans les vues compactes horizontale et verticale. Lancez le nettoyage des fichiers inutiles depuis les utilitaires avec vos réglages de nettoyage système, puis suivez la progression et le résultat dans l’îlot. Le nom du minuteur ne vaut que pour la session en cours et revient au nom par défaut à la fin ou après annulation.',
        points: [
          'Minuteur de concentration',
          'Bloque F1-F12 pendant le nettoyage',
          'Téléprompteur et miroir',
        ],
      },
      system: {
        name: 'État du système',
        caption:
          'Surveille CPU, GPU, mémoire, disque, réseau, ventilateurs et température NVMe SMART disponible. Consultez l’historique à la minute sur une période choisie, exportez-le en .xlsx ou effacez-le dans les réglages. Vérifiez santé, cycles, température et capacité de la batterie, charge des appareils proches et IPv4/IPv6 publiques. Choisissez des modes d’alimentation automatiques sur secteur ou batterie, avec économie d’énergie à 20 % ou moins en option. Chargez immédiatement à 100 % lorsque macOS le permet. Vérifiez caches, journaux, préférences résiduelles et espaces IA orphelins avant de les mettre à la Corbeille ; le nettoyage peut aussi être planifié tous les 7, 15 ou 30 jours. Le nettoyage planifié est désactivé par défaut ; choisissez les éléments fiables seuls ou tous les éléments traitables, y compris ceux à vérifier. Exécutez le nettoyage en arrière-plan et consultez sa progression et ses résultats dans l’île. Repérez les applications installées en double et les fichiers laissés par leurs mises à jour.',
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
    lede: 'Captures, outils d’image et d’audio, dictée, médias, téléchargements du navigateur et gestion de l’IA apparaissent là où ils sont faciles à atteindre.',
    ariaLabel: 'Fonctions de bureau indépendantes',
    summaryMono: 'AU-DELÀ DE L’ÎLE',
    summaryLede: 'Les fonctions les plus utilisées, chacune à sa place naturelle.',
    summaryNote:
      'Aperçus de fenêtres, captures et actions rapides restent à portée de main ; les apps recommandées permettent de découvrir d’autres outils de bureau.',
    features: {
      floatingIsland: {
        title: 'Une île flottante adaptée à votre disposition',
        description: 'Utilisez la position de la caméra ou choisissez un emplacement sur un bord de l’écran. La position personnalisée est conservée entre les modes. Les présentations compactes horizontales et verticales adaptent leur longueur aux icônes, tâches IA, téléchargements et médias, avec une option pour afficher plus d’informations. Réorganisez les modules par glisser-déposer dans Réglages → Disposition de Dynamic Island, ou rétablissez l’ordre par défaut. La même page permet de définir la priorité des informations d’état compactes.',
        detail: 'Position personnalisée · Icônes persistantes · Informations adaptatives',
      },
      dailyBriefing: {
        title: 'Le bilan de votre journée',
        description: "Choisissez parmi huit modèles, sélectionnez les données d’utilisation, de saisie, du système et d’activité zisla, puis prévisualisez le résultat. Exportez un PNG manuellement ou à une heure quotidienne choisie. L’historique Temps d’écran est utilisé quand il est activé et disponible. Choisissez un dossier d’export indépendant dans Réglages → Emplacement de sauvegarde. Vous pouvez aussi inclure les quotas réels des comptes et l’heure de leur relevé.",
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
        description: "Enregistrez écran, fenêtre ou zone, montez les pistes et sous-titres avec effets portrait/voix, puis exportez. HDR compatible et import depuis l’étagère.",
        detail: 'Effets de portrait et de voix · Traînées colorées du curseur · Lecture et export multipistes',
      },
      permissions: {
        title: 'Les autorisations au même endroit',
        description: "Consultez les états dans Réglages → Autorisations, lancez les demandes prises en charge ou ouvrez la page système correspondante. L’état des autorisations se met à jour après l’octroi de l’accès. Une aide au glisser-déposer facilite l’ajout de l’application quand il est nécessaire.",
        detail: "État des autorisations · Demandes et liens",
      },
      imageTools: {
        title: 'Outils d’image',
        description: 'Neuf outils locaux dans les réglages : compression ; conversion PNG, JPEG, WebP, AVIF et JPEG XL ; redimensionnement et recadrage ; comparaison du format le plus léger ; rotation et miroir ; filigranes ; mosaïque et flou ; reconnaissance de texte et de tableaux ; détourage. Exportez par lots ou en ZIP, avec un dossier dédié dans Réglages → Emplacement de sauvegarde.',
        detail: '9 outils locaux · Cinq formats · Export par lots et ZIP',
      },
      audioTools: {
        title: 'Outils audio',
        description: 'Vingt-sept opérations locales dans les réglages : conversion, compression, découpe, segmentation, assemblage et mixage, extraction audio d’une vidéo, normalisation LUFS, fondus, vitesse et hauteur, réduction du bruit et suppression des silences, égaliseur, dynamique, canaux et tags. FFmpeg et ffprobe sont nécessaires ; choisissez un fichier ou un dossier pour l’export.',
        detail: '27 opérations locales · Montage et mixage · FFmpeg et ffprobe',
      },
      pdf: {
        title: 'Outils PDF',
        description: "Accessible dans les réglages. Quatorze opérations entièrement locales : fusionner, diviser, faire pivoter, recadrer, convertir des images et fichiers Office, convertir en images, exporter le texte, ajouter un filigrane texte ou image, numéroter les pages, chiffrer, supprimer un mot de passe et modifier les métadonnées.",
        detail: '14 outils locaux · Fusion dans votre ordre · Rien ne quitte votre Mac',
      },

      windowPreviews: {
        title: 'Voir une fenêtre, cliquer pour y passer',
        description:
          'Prévisualisez les fenêtres depuis le Dock ou avec Command-Tab, puis cliquez sur une carte pour activer la fenêtre. Les nouvelles configurations activent cette fonction ; gérez-la et ses autorisations dans les réglages. Les fenêtres fermées ou en double sont filtrées ; les aperçus du Dock restent masqués quand un menu contextuel est ouvert.',
        detail: 'Dock et Command-Tab · Changer de fenêtre en un clic · Réglable',
      },
      capture: {
        title: 'Captures, captures défilantes et épinglage',
        description:
          'Capturez, épinglez ou assemblez des captures défilantes avec des raccourcis personnalisables. Surlignez, extrayez des zones d’image, arrondissez les coins et conservez les annotations à l’export. Reconnaissez et copiez du texte, traduisez-le puis copiez le résultat, ou exportez les tableaux reconnus en .xlsx. Rangez les captures dans l’étagère. Les réglages vérifient les conflits avec la dictée et les actions rapides. La boîte de dialogue s’ouvre dans le dossier de captures défini dans Réglages → Emplacement de sauvegarde. Les captures épinglées restent en place lors d’une nouvelle capture. Utilisez le défilement automatique lent pour les captures longues et capturez en HDR sur les appareils compatibles. L’accrochage aux fenêtres inclut la fenêtre des réglages de zisla. Les images épinglées suivent la taille de leur cadre lors du zoom par la barre d’outils, le trackpad ou le déplacement d’un coin.',
        detail: 'Surlignage et extraction · Reconnaissance, traduction et copie · Coins arrondis et .xlsx',
      },
      voice: {
        title: 'Dictée et mise en forme',
        description:
          'Basculez avec une touche ou maintenez-la pour parler, avec la reconnaissance vocale du système, des vocabulaires spécialisés et des mots-clés personnalisés. Utilisez au besoin Ollama, LM Studio ou un modèle distant pour corriger la transcription en préservant le sens et mettre en forme les éléments explicitement énumérés. Réglages → Moniteur système et nettoyage peut supprimer les fichiers audio de plus de 7, 15 ou 30 jours en conservant les transcriptions ; le nettoyage automatique est désactivé par défaut.',
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
          'Détecte les téléchargements de Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera et Arc, et affiche leur source et leur progression en haut de l’écran. La progression indique le vrai nom du fichier cible lorsque le navigateur le fournit.',
        detail: '8 navigateurs · Source identifiée · Avis de fin',
      },
      copyAssistant: {
        title: 'Actions rapides et étapes suivantes',
        description:
          'Une fois activé, le texte, les liens, les fichiers ou les images copiés s’affichent dans une barre distincte en haut de l’écran. Il reconnaît les liens, les noms d’apps installées localement et les noms d’émojis, et peut convertir les montants copiés aux taux de change en temps réel ; chaque étape suivante n’est exécutée qu’après votre confirmation. Ouvrez le dossier d’un fichier via les actions rapides après un téléchargement ou un transfert AirDrop. Les dossiers Chrome par défaut ou choisis sont pris en charge, avec une activation indépendante de la progression des téléchargements. Les adresses IP disposent d’actions distinctes pour la recherche et l’ouverture du lien. Les conversions reconnaissent les unités monétaires mineures et le catalogue utilise Emoji 18.0. Les textes et images enregistrés utilisent le dossier indépendant des actions rapides dans Réglages → Emplacement de sauvegarde. Si une app ne s’ouvre pas, les actions rapides peuvent vérifier son intégrité, sa signature et la politique de sécurité de macOS, puis retirer les attributs de quarantaine et l’ouvrir après validation. Réordonnez les actions de chaque type reconnu dans Réglages → Actions rapides. Les montants prennent en charge les symboles régionaux et les codes de devise préfixés. La détection des commandes prend en charge les here-documents.',
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
          "Affichez au besoin la date, l’état et la lecture en cours sur l’écran verrouillé de macOS.",
        detail: "Activation au choix · Ne prend jamais le focus",
      },
      recommendedTools: {
        title: 'Apps recommandées',
        description:
          'Découvrez OpenScreen pour la capture vidéo et le montage, DockDoor pour les aperçus de fenêtres et le changement d’app, et Zshell pour un espace de travail de terminal natif macOS. Ces applications tierces s’installent séparément.',
        detail: 'Découvrir des outils de bureau · Apps tierces · Installation séparée',
      },
    },
  },
  ai: {
    eyebrow: "ACTIVITÉ IA",
    title: "Suivez les tâches IA, <span>l’usage et les quotas.</span>",
    lede: "Consultez les tâches par application, l’usage des modèles par date et les quotas restants de vos comptes.",
    summaryMono: "TÂCHES / USAGE / QUOTAS",
    summaryLede:
      "Tâches IA, usage et quotas au même endroit.",
    toolsHeading: 'Outils IA pris en charge',
    toolsLede:
      "Détecte les tâches des CLI, applications de bureau et IDE compatibles.",
    toolsAriaLabel: 'Outils IA pris en charge',
    boundariesHeading: "Confidentialité",
    privacyPoints: [
      "L’état des tâches et l’usage restent sur votre Mac",
      "Les prompts et les réponses ne sont pas lus",
      "Les conversations ne sont pas envoyées",
    ],
    bridgeHeading: 'Reliez vos propres tâches',
    bridgeLede:
      "Utilisez zislactl pour afficher vos scripts et vos tâches de compilation dans la barre d’état.",
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
        desc: "Fonctionne sur les écrans à encoche et les écrans externes.",
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
  help: {
    "title": "Commencer avec zisla",
    "lede": "Choisissez une tâche, puis suivez son accès, ses étapes, ses autorisations et son dossier de sortie.",
    "labels": {
      "entry": "Accès",
      "shortcuts": "Raccourcis",
      "permissions": "Autorisations",
      "output": "Résultat et stockage"
    },
    "guides": {
      "clipboard": {
        "title": "Réutiliser un contenu copié",
        "summary": "Retrouvez un élément ou choisissez une action après la copie.",
        "entry": "Îlot → Presse-papiers ; Réglages → Actions rapides.",
        "steps": [
          "Activez l’historique ou les actions rapides et copiez un texte ou lien d’exemple.",
          "Ouvrez le presse-papiers, filtrez ou cherchez, puis copiez un élément.",
          "Copiez une image d’exemple avec du texte lisible, attendez la reconnaissance locale en arrière-plan, puis cherchez un mot de l’image pour retrouver l’original.",
          "Faites un clic droit sur l’image pour reconnaître ou copier son texte ; annulez si nécessaire pendant la reconnaissance. Celle en arrière-plan ne copie pas le texte automatiquement.",
          "Collez dans l’application cible ; pour une nouvelle copie, choisissez une action dans la fenêtre rapide."
        ],
        "shortcuts": "Command+1…9 puis Command+0 suivent l’ordre des actions. Pour une nouvelle configuration, Command+N déclenche aussi la première action et Command+Delete ferme la fenêtre. Les choix enregistrés ou effacés sont conservés.",
        "permissions": "Historique et reconnaissance restent locaux. Les déclencheurs souris/touche modificatrice nécessitent Surveillance de l’entrée ; le geste de copie utilise Accessibilité. La traduction utilise le service choisi.",
        "output": "Historique dans les données locales. Le dossier Actions rapides se règle dans Emplacement de sauvegarde ; nouveau défaut : ~/Downloads/quick."
      },
      "capture": {
        "title": "Capturer et monter l’écran",
        "summary": "Modifiez une capture ou un enregistrement, puis exportez.",
        "entry": "Barre de menus → Capture/Enregistrement ; Réglages → Enregistrement → Studio.",
        "steps": [
          "Capturez une région ou une fenêtre ; modifiez, copiez, sauvegardez ou rangez-la.",
          "Choisissez écran, fenêtre ou région et activez uniquement les sources audio/caméra nécessaires.",
          "Arrêtez, montez et prévisualisez dans le studio, puis exportez au format choisi."
        ],
        "shortcuts": "Control+1 capture ; Control+2 capture longue. Control+Shift+1/2/3 enregistrent écran/fenêtre/région ; Control+Shift+6 ouvre le studio. Modifiables dans les réglages.",
        "permissions": "Enregistrement de l’écran requis. Microphone et caméra demandent leurs autorisations, y compris l’aperçu caméra.",
        "output": "Nouveaux dossiers : ~/Downloads/picture pour les captures, ~/Downloads/video pour enregistrements/projets. Réglables séparément. Certains exports nécessitent FFmpeg."
      },
      "shelf": {
        "title": "Transmettre des fichiers par le relais",
        "summary": "Gardez les fichiers prêts sans copier les originaux.",
        "entry": "Îlot → Relais ; glissez vers la zone supérieure.",
        "steps": [
          "Déposez un fichier d’exemple en haut, ou secouez pendant le glissement si ce geste est activé.",
          "Ouvrez le relais et choisissez une catégorie ou les éléments nécessaires.",
          "Glissez vers la destination, affichez dans Finder ou partagez ; une capture rangée peut être exportée en PNG.",
          "Sélectionnez des fichiers ou dossiers et choisissez la compression ZIP dans le menu contextuel ; l’archive revient sur l’étagère.",
          "Sélectionnez les images de l’étagère et choisissez le redimensionnement ou la conversion de format ; lancez les outils d’image pour renvoyer les résultats réussis sur l’étagère.",
          "Sélectionnez des images, vidéos ou fichiers audio et importez-les dans la bibliothèque du studio ; le projet et la chronologie actuels sont conservés."
        ],
        "shortcuts": "Glissement au pointeur. Le geste de secousse se règle séparément ; aucun raccourci fixe requis.",
        "permissions": "Le sélecteur et les signets sécurisés donnent accès aux fichiers choisis. Une capture nécessite Enregistrement de l’écran.",
        "output": "Les originaux restent en place. Références et captures rangées persistent localement ; le PNG va vers la destination choisie. Les ZIP et les résultats d’image réussis reviennent sur l’étagère ; les médias importés rejoignent la bibliothèque du projet d’enregistrement."
      },
      "meeting": {
        "title": "Rejoindre une réunion et prendre une note",
        "summary": "Associez une réunion du calendrier à une note de contexte.",
        "entry": "Îlot → Agenda ; activez calendrier et notes de contexte dans Réglages.",
        "steps": [
          "Créez ou ouvrez un événement avec un lien de réunion pris en charge et des horaires valides.",
          "Cliquez sur Rejoindre ; le compte à rebours commence 10 minutes avant.",
          "Créez, sauvegardez ou associez une note depuis l’événement ; rouvrez-la depuis l’agenda ou le relais."
        ],
        "shortcuts": "Boutons de réunion et de note. Pour un autre lieu, maintenez la touche configurée et secouez ; touche par défaut : Command.",
        "permissions": "Calendrier requis. Les notes liées aux fenêtres peuvent nécessiter Accessibilité ; les captures jointes nécessitent Enregistrement de l’écran.",
        "output": "Notes de réunion dans les données locales du relais. Les notes rapides sont une fonction distincte utilisant Apple Notes."
      },
      "ai": {
        "title": "Connecter l’IA et vérifier les quotas",
        "summary": "Suivez tâches, usage enregistré et quotas du compte.",
        "entry": "Réglages → IA ; îlot → Moniteur IA.",
        "steps": [
          "Activez un outil local compatible ou déclarez une tâche avec zislactl selon la référence CLI.",
          "Activez le suivi du fournisseur souhaité et choisissez séparément le suivi et l’affichage de Gemini et Claude/GPT dans Antigravity. Pour Gemini App, connectez le même compte Google sur gemini.google.com/usage et enregistrez son Cookie dans les identifiants de quota web ; sélectionnez Gemini CLI séparément.",
          "Consultez prélèvement, réinitialisation et alerte de quota ; affichez l’historique ou exportez en .xlsx."
        ],
        "shortcuts": "Utilisez le moniteur ou Réglages, sans raccourci global fixe. zislactl prend les arguments documentés.",
        "permissions": "La détection locale lit un état structuré. Les quotas contactent le fournisseur ; les modifications IA facultatives utilisent le modèle ou CLI choisi.",
        "output": "Tâches et usage : ~/Library/Application Support/zisla/ai-state.sqlite. Quotas issus du fournisseur, sans estimation par token ; données absentes indiquées indisponibles."
      },
      "media-tools": {
        "title": "Traiter images, audio et PDF",
        "summary": "Utilisez les outils locaux indépendants sur un exemple.",
        "entry": "Réglages → Outils image / Outils audio / Outils PDF.",
        "steps": [
          "Ajoutez une image, choisissez opération et options, exécutez puis exportez le résultat ou ZIP.",
          "Sélectionnez les images de l’étagère et choisissez le redimensionnement ou la conversion de format ; lancez les outils d’image pour renvoyer les résultats réussis sur l’étagère.",
          "Installez FFmpeg et ffprobe dans les composants, ajoutez un audio, choisissez découpage ou mixage et la destination d’export.",
          "Ajoutez les PDF dans l’ordre voulu, exécutez l’opération et sauvegardez. La conversion Office nécessite LibreOffice ou OpenOffice."
        ],
        "shortcuts": "Boutons des outils ; aucun raccourci global fixe.",
        "permissions": "Le sélecteur donne accès aux fichiers et dossiers choisis. Traitement local ; installation des composants par téléchargement.",
        "output": "Nouveaux dossiers : images ~/Downloads/picture, PDF ~/Downloads/pdf, réglables séparément. L’audio utilise la fenêtre d’export."
      },
      "daily-briefing": {
        "title": "Créer un bilan quotidien",
        "summary": "Prévisualisez les statistiques avant l’export PNG.",
        "entry": "Réglages → Bilan quotidien.",
        "steps": [
          "Choisissez le modèle et les statistiques.",
          "Prévisualisez les données disponibles et choisissez le dossier de sortie.",
          "Exportez aujourd’hui ou activez l’export quotidien et son horaire."
        ],
        "shortcuts": "Boutons Aperçu et Export ; aucun raccourci fixe.",
        "permissions": "Activez les fonctions de statistiques concernées. L’historique Temps d’écran peut nécessiter Accès complet au disque ; les quotas consultent le fournisseur.",
        "output": "PNG dans le dossier du bilan ; nouveau défaut ~/Downloads/daily. Une donnée absente ne devient pas un zéro mesuré."
      },
      "desktop": {
        "title": "Prévisualiser une fenêtre et noter son contexte",
        "summary": "Passez à une fenêtre puis laissez une note à cet endroit.",
        "entry": "Réglages → Aperçus de fenêtres / Notes de contexte ; Dock, Command+Tab et relais.",
        "steps": [
          "Activez les aperçus et autorisez-les ; survolez une app du Dock ou utilisez Command+Tab puis cliquez sur sa carte.",
          "Sur une page, fenêtre ou bureau d’exemple, maintenez la touche configurée et secouez ; saisissez et sauvegardez la note.",
          "Revenez au lieu ou ouvrez la note depuis le relais ; ajoutez éventuellement rappel récurrent ou capture de fenêtre."
        ],
        "shortcuts": "Command+Tab change d’app. Les notes utilisent Command maintenu par défaut, modifiable dans Réglages.",
        "permissions": "Aperçus : Accessibilité et Enregistrement de l’écran. Détection de fenêtre : Accessibilité ; captures jointes : Enregistrement de l’écran.",
        "output": "Notes et captures dans les données locales du relais sous ~/Library/Application Support/zisla."
      },
      "playback": {
        "title": "Choisir la lecture et mixer les applications",
        "summary": "Sélectionnez la sortie et réglez les apps en lecture.",
        "entry": "Zone média → Sortie audio ; Réglages → Source média ; îlot → Mélangeur.",
        "steps": [
          "Lancez un audio d’exemple et choisissez une sortie disponible.",
          "Choisissez source automatique ou lecteur préféré dans Réglages, puis vérifiez les contrôles de lecture.",
          "Sous macOS 14.4+, ouvrez le mélangeur, autorisez l’audio système et réglez ou coupez une app en lecture."
        ],
        "shortcuts": "Boutons de lecture et curseurs ; aucun raccourci fixe.",
        "permissions": "Le mélangeur nécessite macOS 14.4+ et Enregistrement audio système. Les appareils dépendent des connexions ; Bluetooth peut demander une autorisation.",
        "output": "La sortie est le choix du système. Les volumes par app sont mémorisés localement ; aucun fichier exporté."
      }
    },
    "workflowsTitle": "Démonstrations courtes",
    "workflows": {
      "copy-next": {
        "title": "Retrouver, copier et réutiliser",
        "steps": [
          "Cherchez le mot d’exemple « brew » dans l’historique.",
          "Copiez l’élément correspondant.",
          "Collez dans l’application cible. L’extrait montre recherche et copie ; une nouvelle copie permet une action rapide séparée."
        ]
      },
      "drop-output": {
        "title": "Déposer un fichier et préparer la sortie",
        "steps": [
          "Glissez une image d’exemple de Finder vers le relais supérieur.",
          "Ouvrez le relais et sélectionnez l’image.",
          "Glissez vers la cible ou exportez une capture rangée en PNG. L’extrait montre le dépôt dans le relais."
        ]
      },
      "meeting-note": {
        "title": "Passer de la réunion à la note",
        "steps": [
          "Ouvrez la réunion avec son lien de participation.",
          "Choisissez Nouvelle note ou Associer une note existante.",
          "Sauvegardez et rouvrez depuis l’événement ou le relais. L’extrait montre création et association."
        ]
      }
    },
    "excerptLabel": "Lire l’extrait",
    "guideLinkLabel": "Lire le guide",
    "videoNotice": "Extraits de la présentation existante, avec données de démonstration. Les sous-titres vidéo sont en anglais ; les étapes suivent votre langue. La présentation complète de 2 min 40 et les crédits musicaux sont plus bas.",
    "preferencesTitle": "Préférences utiles",
    "preferences": [
      "Activez le dépôt par secousse dans Réglages. Les notes de contexte utilisent leur propre touche maintenue.",
      "Choisissez la sortie audio dans la zone média, puis la source automatique ou le lecteur préféré dans Réglages. Ce choix ne répartit pas les applications entre appareils.",
      "Sons et statistiques clavier ont des interrupteurs distincts et utilisent Surveillance de l’entrée. Le mélangeur nécessite macOS 14.4+ et Enregistrement audio système.",
      "Le bilan quotidien propose 8 modèles, une prévisualisation et un export PNG manuel ou journalier, avec un dossier indépendant."
    ]
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
      'v0.1.25': [
        'Lancez le nettoyage des fichiers inutiles depuis les utilitaires avec vos réglages existants. La progression et les résultats apparaissent dans l’îlot ; les messages de résultat de l’IA restent lisibles avant le retour du suivi du nettoyage.',
        'Le contenu des captures épinglées suit la taille du cadre lors du zoom par la barre d’outils, le trackpad ou le déplacement d’un coin, y compris pour les images HDR.',
        'La météo affiche une seule date de mise à jour pour la liste et regroupe les sources sans entrées répétées.',
        'Les statistiques de frappe retrouvent leur barre de défilement verticale et le tableau de bord reste dans sa zone visible.',
        'Les outils audio s’adaptent à la zone visible des réglages, avec un défilement séparé pour la liste des opérations et le panneau d’édition.',
        'Le mélangeur de volume des applications masque les sources audio inactives, conserve les réglages de volume et de sourdine et permet de relancer une détection audio en échec.',
      ],
      'v0.1.24': [
        'L’historique du presse-papiers permet la recherche et le regroupement par application source. Les actions rapides reconnaissent les commandes contenant des here-documents.',
        'Le nettoyage système peut s’exécuter en arrière-plan avec progression et résultats dans l’île. Le nettoyage du disque repère les applications installées en double et les fichiers laissés par les mises à jour.',
        'Tous les dossiers de sortie peuvent être rétablis par défaut en une action. Les groupes et l’ordre des pages des réglages ont été réorganisés.',
        'L’enregistrement HDR est disponible sur les appareils compatibles. La reconnaissance de texte, la traduction et les aperçus HDR des captures sont rétablis ; l’accrochage aux fenêtres inclut celle des réglages.',
        'Les notes rapides se parcourent avec Command et les flèches. Le texte collé garde la typographie native du corps de texte.',
        'Les réglages des quotas IA proposent des régions indépendantes. L’historique quotidien et les couleurs du quota restant concordent entre cartes déployées et notifications compactes. L’annulation d’un tour Kimi efface les erreurs ; une actualisation d’abonnement annulée ne lit plus les identifiants.',
        'Les aperçus filtrent les fenêtres fermées et les doublons, respectent leur identité lors d’un recours alternatif et restent masqués pendant l’ouverture des menus contextuels du Dock.',
        'La surveillance des médias actualise les sources périmées et termine l’activité audio quand les échantillons cessent. Le volume par application est conservé ; les fondus suivent le temps des échantillons décodés. Les sons et statistiques du clavier traitent mieux l’absence de lecture ou de données.',
        'Les autorisations se mettent à jour après l’octroi de l’accès, avec une aide pour faire glisser l’application. Les messages d’échec des outils recommandés restent lisibles.',
      ],
      'v0.1.23': [
        'Les outils image ajoutent neuf opérations locales : compression, conversion entre cinq formats, redimensionnement et recadrage, comparaison du format le plus léger, rotation et symétrie, filigranes, mosaïque et flou, reconnaissance de texte et de tableaux, et suppression du fond. Exportez par lots ou en ZIP et choisissez des dossiers distincts pour les outils PDF et image.',
        'Les outils audio ajoutent 27 opérations locales de conversion, montage, découpage, assemblage, mixage, extraction audio, normalisation LUFS, effets, canaux et métadonnées. FFmpeg et ffprobe sont nécessaires ; choisissez un fichier ou dossier d’export.',
        'Le suivi des comptes IA affiche les quotas restants en anneaux, les heures de réinitialisation et les alertes de quota faible dans les présentations de l’îlot, y compris les fenêtres 5h/7d et les budgets USD de Cursor lorsqu’ils sont disponibles. Les bilans quotidiens peuvent inclure les quotas réels et leur heure de relevé.',
        'Sélectionnez une date dans les tendances IA ou la carte thermique pour voir les tokens d’entrée, de sortie et totaux par fournisseur et modèle. Consultez, exportez tout l’historique en .xlsx ou effacez-le dans Réglages. L’accueil regroupe les tâches IA par application et l’îlot affiche les résultats d’export des bilans.',
        'Les événements avec un lien de réunion affichent un compte à rebours dès 10 minutes avant le début et un bouton pour rejoindre. Créez une note de réunion ou liez et déliez des notes contextuelles. Mail permet de marquer toute la boîte de réception comme lue.',
        'La zone de dépôt ajoute recherche, filtres et sélection multiple pour copier, partager ou envoyer vers les notes rapides. Convertissez les images en PDF, reconnaissez leur texte pour une note et ouvrez les vidéos sélectionnées dans le studio d’enregistrement.',
        'Choisissez des modes d’alimentation automatiques distincts sur secteur et sur batterie, avec maintien facultatif du mode économie d’énergie à 20% ou moins. Chargez immédiatement à 100% lorsque macOS le permet. Réglages donne accès à l’historique système, à son export .xlsx et à son effacement.',
        'Les présentations Pomodoro compactes horizontales et verticales ajoutent progression, pause, reprise et remise à zéro. Survoler les commandes conserve l’îlot replié, y compris en présentation verticale avec davantage d’informations.',
        'Les captures longues ajoutent le défilement automatique lent de la fenêtre choisie. La capture HDR est disponible sur les appareils compatibles et l’édition conserve les réglages de rendu et d’export des images.',
        'Les actions rapides peuvent réparer une app qui ne s’ouvre pas après vérification de son intégrité, de sa signature et de la politique de sécurité macOS. Réordonnez les actions par type, consultez davantage d’exemples et utilisez les symboles monétaires régionaux ou codes préfixés. Les recherches de vols, trains et colis sont prioritaires.',
        'Réglages sépare la disposition de Dynamic Island, le bilan quotidien, les notifications et conseils, et le workflow en pages distinctes. Réordonnez les priorités compactes et activez au besoin la mise à jour quotidienne des composants installés. Le nettoyage des enregistrements rejoint Moniteur système et nettoyage et conserve les transcriptions.',
        'Les téléchargements affichent le vrai nom du fichier cible lorsqu’il est disponible. Le rendu au repos, les scans IA, le chargement de l’historique système et la lecture en studio consomment moins de ressources. Les logos IA compacts, cartes de quota et animations de résultat sont ajustés ; le défilement météo, les dépôts, les écritures Mail et la conservation du presse-papiers sont corrigés.',
        'L’accueil ajoute une visite de 160 secondes lancée au clic, avec un lien vers la vidéo originale. Le site reste utilisable sans WebGL et les apps recommandées incluent désormais l’espace de travail terminal Zshell.',
      ],
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
          'La météo, la vérification signée des mises à jour, les téléchargements que vous lancez et la mise en forme vocale distante facultative utilisent le réseau au besoin. La détection des liens du presse-papiers se fait entièrement sur votre Mac et ne lance jamais de téléchargement d’elle-même. Le modèle local corrige le texte après la transcription ; la reconnaissance vocale Apple peut toujours utiliser le réseau, selon la langue et la prise en charge du système. Le suivi activé des quotas IA interroge aussi les services des fournisseurs sélectionnés.',
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
          'Les données locales se trouvent dans ~/Library/Application Support/zisla/. Les statistiques de saisie sont conservées à part dans ~/Library/Application Support/zisla/typing-stats.sqlite3. Les notes rapides utilisent l’app Notes du système. Réglages → Emplacement de sauvegarde propose des dossiers indépendants pour les téléchargements, les outils PDF et image, les captures, les enregistrements, les actions rapides et les bilans quotidiens. La mise à jour conserve les emplacements déjà choisis ; chaque dossier peut ensuite être modifié séparément. Rétablissez tous les dossiers d’enregistrement par défaut en une seule action.',
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
      "Utilise un fond opaque lorsque « Réduire la transparence » est activé",
      'Liquid Glass sur macOS 26 et versions ultérieures, avec repli automatique sur les matériaux natifs sur macOS 14 et 15',
    ],
  },
  film: {
    title: "Film de présentation",
    videoAriaLabel: "Film de présentation de zisla",
    openVideoLabel: "Ouvrir la vidéo",
    playbackError: "Impossible de lire la vidéo.",
    musicLabel: "Musique",
    excerptLabel: "Extrait",
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
