import type { SiteContent } from '../content';

export const fr: SiteContent = {
  meta: {
    documentTitle: 'zisla · Espace de travail dynamique',
    description:
      'zisla est un espace de travail dynamique et natif pour macOS. Regroupez les tâches IA comme Zed Agent, les médias, les fichiers et votre agenda, avec les sons de clavier, les statistiques de saisie, l’annotation de captures et l’assistant de copie.',
    ogTitle: 'zisla · Mettez ce qui se passe là où vous pouvez le voir',
    ogDescription:
      'Des tâches IA comme Zed Agent et de la lecture multimédia jusqu’aux sons de clavier, aux statistiques de saisie, à l’assistant de copie, à l’annotation de captures et aux outils de bureau : un espace de travail macOS natif qui n’apparaît que lorsque vous en avez besoin.',
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
      faq: 'FAQ',
      developers: 'Développeurs',
    },
    downloadCta: 'Télécharger',
    downloadCtaAriaLabel: 'Aller à la section de téléchargement',
    languageLabel: 'Langue de l’interface',
  },
  hero: {
    eyebrow: 'ESPACE DE TRAVAIL MACOS NATIF',
    title:
      'zisla<br><em>Ce qui se passe,<br>là où vous<br class="hero-mobile-break"> pouvez le voir.</em>',
    lede: 'Regroupez tâches IA, médias, fichiers et agenda en haut de l’écran. Après une copie, une barre d’assistance distincte en affiche un aperçu et propose l’étape suivante. Elle apparaît quand il faut et s’efface ensuite.',
    downloadCta: 'Télécharger',
    downloadCtaAriaLabel: 'Télécharger',
    sourceCta: 'Voir le code',
    sourceCtaAriaLabel: 'Voir le code source de zisla sur GitHub',
    hints: [
      'Amenez le pointeur en haut de l’écran, sans cliquer',
      'Après une copie, Command+N lance l’étape suivante',
      'Se referme toute seule, sans interrompre votre travail',
    ],
    identityCaption: 'Haut de l’écran',
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
      '{modules} modules en haut de l’écran et {features} fonctions indépendantes couvrant les captures, la voix, les médias, les téléchargements, l’assistant de copie, la gestion de l’IA, la mascotte et l’écran verrouillé.',
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
          'Consultez l’historique du presse-papiers dans la Dynamic Island et filtrez par image, URL, chemin et type de fichier. Envoyez un élément vers les notes rapides, épinglez-le en favori ou supprimez-le.',
        points: ['Historique dans l’île', 'Filtre par type', 'Notes rapides et favoris'],
      },
      aiMonitor: {
        name: 'Suivi IA',
        caption:
          'Détecte automatiquement l’activité des CLI IA, apps de bureau et IDE pris en charge, y compris les fils Zed Agent, et affiche les tâches, l’état, l’évolution cumulée des tokens et une carte thermique des contributions. Seuls les événements structurés sont analysés, jamais le texte des conversations.',
        points: [
          'Tâches agrégées entre outils',
          'Évolution de la consommation de tokens',
          'Ne lit ni invites ni réponses',
        ],
      },
      keyboardSound: {
        name: 'Sons de clavier',
        caption:
          'Joue 20 sonorités de clavier mécanique intégrées à chaque frappe globale, avec volume réglable et variation naturelle de hauteur, plus un son de relâchement pour les sonorités qui le prévoient. Avec les statistiques de saisie locales activées, vous consultez dans l’île le résumé du jour, les tendances, l’historique, la chronologie par app et une carte thermique par touche incluant F1-F12.',
        points: [
          '20 sonorités intégrées',
          'Son de relâchement et variation de hauteur',
          'Statistiques facultatives',
        ],
      },
      download: {
        name: 'Téléchargeur',
        caption:
          'Collez un lien ou laissez zisla repérer les liens du presse-papiers une fois l’option activée. Choisissez vidéo ou audio et enregistrez dans le dossier par défaut ou celui de votre choix. Les plateformes vidéo courantes et les autres liens pris en charge affichent l’icône de la source, la progression en temps réel et l’état final.',
        points: [
          'Modes vidéo / audio',
          'Dossier par défaut ou personnalisé',
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
          'Lit les comptes activés dans Mail. Consultez la boîte de réception, marquez comme lu, répondez, rédigez et placez dans la corbeille depuis l’île, avec des indications claires dès qu’une autorisation manque.',
        points: ['Comptes de Mail', 'Répondre et rédiger dans l’île', 'Autorisations expliquées'],
      },
      quickNotes: {
        name: 'Notes rapides',
        caption:
          'Adossé à l’app Notes du système : consultez, modifiez, créez et supprimez des notes avec un aperçu Markdown en direct. Les brouillons sont réécrits dans Notes automatiquement.',
        points: [
          'Les données restent dans Notes',
          'Éditeur Markdown',
          'Brouillons réenregistrés seuls',
        ],
      },
      pdf: {
        name: 'Outils PDF',
        caption:
          'Quatorze opérations entièrement locales : fusionner, diviser, faire pivoter, recadrer, convertir des images et fichiers Office, convertir en images, exporter le texte, ajouter un filigrane texte ou image, numéroter les pages, chiffrer, supprimer un mot de passe et modifier les métadonnées.',
        points: ['14 outils locaux', 'Fusion dans votre ordre', 'Rien ne quitte votre Mac'],
      },
      toolbox: {
        name: 'Utilitaires',
        caption:
          'Minuteur de concentration, écran maintenu allumé, nettoyage de l’écran, nettoyage du clavier (qui bloque les frappes, F1-F12 comprises, pendant l’opération), alarmes, téléprompteur, miroir et corbeille, sur une seule page.',
        points: [
          'Minuteur de concentration',
          'Bloque F1-F12 pendant le nettoyage',
          'Téléprompteur et miroir',
        ],
      },
      system: {
        name: 'État du système',
        caption:
          'Consultez l’état du processeur, du GPU, de la mémoire, du disque, du réseau et des ventilateurs, lisez la température NVMe SMART quand le matériel la publie, et videz les caches et journaux qu’il est sûr de supprimer.',
        points: [
          'Surveillance au niveau de la puce',
          'Température NVMe si prise en charge',
          'Vider les caches en un geste',
        ],
      },
      battery: {
        name: 'Batterie',
        caption:
          'Consultez les indicateurs détaillés de ce Mac — charge, état, cycles, température et capacité — et le niveau de batterie des appareils proches que le système expose.',
        points: ['Indicateurs de ce Mac', 'Autonomie restante', 'Batterie des appareils proches'],
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
      'Captures, enregistrement, médias, téléchargements du navigateur, assistant de copie, gestion de l’IA, mascotte et écran verrouillé fonctionnent chacun de leur côté.',
    features: {
      capture: {
        title: 'Captures, captures défilantes et épinglage',
        description:
          'Capturez ou épinglez une zone de l’écran avec un raccourci global, puis annotez, assemblez une capture défilante, reconnaissez ou exportez des tableaux. Les annotations textuelles en cours d’édition sont conservées à l’export.',
        detail: 'Raccourci global · Annoter et annuler · Modifications conservées à l’export',
      },
      voice: {
        title: 'Dictée et mise en forme',
        description:
          'Basculez avec une touche ou maintenez-la pour parler, avec la reconnaissance vocale du système. Ajoutez au besoin des vocabulaires spécialisés, des mots-clés personnalisés, un format structuré ou une mise en forme par modèle local ou distant.',
        detail: 'Deux modes d’enregistrement · Vocabulaires et mots-clés · Modèle facultatif',
      },
      media: {
        title: 'Médias et sons d’ambiance du système',
        description:
          'Pilotez la lecture en cours depuis le haut de l’île, ou choisissez un son d’ambiance macOS. La lecture peut s’arrêter d’elle-même au verrouillage, au lancement de l’économiseur d’écran ou à la veille de l’écran.',
        detail: 'Contrôle de lecture · Paroles synchronisées · Arrêt automatique',
      },
      browserDownloads: {
        title: 'Progression des téléchargements',
        description:
          'Détecte les téléchargements de Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera et Arc, et affiche leur source et leur progression en haut de l’écran.',
        detail: '8 navigateurs · Source identifiée · Avis de fin',
      },
      copyAssistant: {
        title: 'Assistant de copie et étapes suivantes',
        description:
          'Une fois activé, le texte, les liens, les fichiers ou les images copiés s’affichent dans une barre distincte en haut de l’écran, avec des étapes adaptées au contenu — ouvrir, afficher dans le Finder, rechercher, traduire, calculer ou enregistrer — exécutées seulement après votre confirmation.',
        detail: 'Option activable · Reconnaissance locale · Command+N par défaut',
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
          'Choisissez une mascotte intégrée et placez-la à gauche ou à droite de l’île. Désactivez-la quand vous voulez.',
        detail: 'Personnages intégrés · Gauche ou droite · Activée au besoin',
      },
      lockScreen: {
        title: 'Informations sur l’écran verrouillé',
        description:
          'Affichez au besoin la date, l’état et la lecture en cours sur l’écran verrouillé de macOS. Il s’agit d’une surcouche distincte, jamais présente dans la liste des modules ni dans le carrousel de l’île.',
        detail: 'Surcouche distincte · Activation au choix · Ne prend jamais le focus',
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
    doubaoName: 'Doubao',
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
    copy: 'Pour les Mac Apple silicon. Versions, autres architectures et sommes de contrôle sont sur la page de publication. Après installation, zisla peut chercher les nouvelles versions sur le canal choisi : Sparkle vérifie d’abord la signature, puis télécharge, installe et redémarre manuellement ou automatiquement selon vos réglages.',
    primaryCta: 'Télécharger',
    primaryCtaAriaLabel: 'Télécharger',
    releaseCta: 'Voir la publication',
    releaseCtaAriaLabel: 'Voir les détails de la publication sur GitHub',
    brewMono: 'HOMEBREW / UNE COMMANDE',
    brewNote: 'Sparkle met zisla à jour lui-même : un simple brew upgrade laisse l\'app intacte. Lancez brew upgrade --cask zisla pour laisser Homebrew la remplacer. Le tap ne sert que des versions stables. Ce tap est tiers et l\'app n\'est pas notarisée : au premier lancement, choisissez « Ouvrir quand même » dans Réglages Système → Confidentialité et sécurité.',
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
        question: 'L’assistant de copie ouvre-t-il ou envoie-t-il ce que je copie ?',
        answer:
          'Non. Une fois activé, la reconnaissance et l’aperçu se font entièrement sur votre Mac, et zisla n’exécute une étape qu’après votre clic ou votre raccourci.',
      },
      permissions: {
        question: 'De quelles autorisations système zisla a-t-il besoin ?',
        answer: `
      <p>zisla ne demande pas toutes les autorisations au premier lancement. macOS affiche chaque demande seulement quand vous activez et utilisez réellement la fonction concernée :</p>
      <ul>
        <li><strong>Calendrier et Rappels :</strong> demandés séparément à l’ouverture du module agenda, pour lire, créer et gérer les événements de calendrier et les rappels datés.</li>
        <li><strong>Service de localisation :</strong> demandé quand vous choisissez la météo de votre position actuelle. zisla relève la position une seule fois et ne vous suit pas en continu. Ajouter une ville à la main n’exige aucune autorisation de localisation.</li>
        <li><strong>Microphone et reconnaissance vocale :</strong> demandés au démarrage de la dictée. Le son n’est capté que pendant l’enregistrement, et seule cette prise est transcrite.</li>
        <li><strong>Accessibilité :</strong> nécessaire pour insérer automatiquement une transcription dans l’app active, pour la copie rapide par geste de souris, pour le nettoyage du clavier et pour piloter certains lecteurs pris en charge. Elle sert à repérer les champs de saisie non protégés par mot de passe ou à envoyer les touches système requises.</li>
        <li><strong>Surveillance de la saisie :</strong> utilisée pour les sons de clavier, les statistiques de saisie locales facultatives et les déclencheurs globaux comme une touche de modification seule ou un bouton latéral de souris. Seuls les événements globaux nécessaires à ces fonctions sont observés ; les raccourcis globaux ordinaires n’en ont pas besoin.</li>
        <li><strong>Enregistrement de l’écran et enregistrement audio du système :</strong> nécessaires aux captures, à leur édition et à l’affichage de la forme d’onde de l’audio système. Les captures lisent l’image de l’écran ; la forme d’onde analyse seulement le niveau audio courant et n’enregistre ni n’envoie aucun contenu sonore.</li>
        <li><strong>Appareil photo :</strong> utilisé uniquement pendant que la fenêtre du miroir est ouverte.</li>
        <li><strong>Bluetooth :</strong> utilisé uniquement pendant que le module batterie est ouvert, pour lire le niveau de charge publié par les appareils connectés ou associés.</li>
        <li><strong>Automatisation :</strong> à la première utilisation des notes rapides, de Mail, du rangement du bureau ou du pilotage direct d’un lecteur pris en charge, macOS demande séparément si zisla peut contrôler Notes, Mail, le Finder ou l’app concernée. Les notes rapides lisent et écrivent dans Notes ; Mail permet de lire, rédiger, répondre, marquer et supprimer des messages.</li>
        <li><strong>Accès complet au disque :</strong> nécessaire seulement quand Mail n’est pas lancé et que zisla doit tout de même lire l’index local des messages pour afficher comptes, expéditeurs, objets, extraits, horodatages et état de lecture.</li>
        <li><strong>Notifications :</strong> demandées à l’activation du minuteur Pomodoro ou des alarmes, uniquement pour afficher une notification locale à la fin d’un minuteur ou au déclenchement d’une alarme.</li>
      </ul>
      <p><strong>Un dossier n’est pas un accès complet au disque :</strong> pour les dossiers de dépôt, d’import/export ou de téléchargement choisis dans le sélecteur de fichiers du système, zisla n’obtient l’accès qu’à ce dossier, jamais la lecture du disque entier.</p>
      <p><strong>Sons de clavier et statistiques de saisie :</strong> les deux sont désactivés par défaut, et les événements clavier globaux ne sont observés qu’après activation de l’un d’eux. Avec les sons de clavier, les événements de touche servent uniquement à jouer un son ; avec les statistiques, seules des données agrégées sont conservées — nombre de caractères, codes de touches physiques, horodatages et app au premier plan — jamais ce que vous avez tapé. Vous pouvez désactiver chaque option séparément dans les réglages, et plus rien n’est alors enregistré. Les données déjà conservées restent dans un fichier de base local que vous pouvez supprimer.</p>
      <p>Vous pouvez désactiver la fonction dans les réglages de l’app, ou révoquer une autorisation à tout moment dans Réglages Système → Confidentialité et sécurité. Révoquer une autorisation désactive seulement la fonction associée et laisse les autres modules intacts. Le nom des éléments varie légèrement selon la version de macOS.</p>
    `.trim(),
      },
      network: {
        question: 'zisla se connecte-t-il à Internet ?',
        answer:
          'La météo, la vérification signée des mises à jour, les téléchargements que vous lancez et la mise en forme vocale distante facultative utilisent le réseau au besoin. La détection des liens du presse-papiers se fait entièrement sur votre Mac et ne lance jamais de téléchargement d’elle-même.',
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
          'Les données locales se trouvent dans ~/Library/Application Support/zisla/. Les statistiques de saisie sont conservées à part dans ~/Library/Application Support/SimuBoard/typing-stats.sqlite3. Les notes rapides utilisent l’app Notes du système.',
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
