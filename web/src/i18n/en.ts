import type { SiteContent } from '../content';

export const en: SiteContent = {
  meta: {
    documentTitle: 'zisla · Dynamic workspace',
    description:
      'zisla is a native macOS workspace for AI tasks, daily briefings and recording, with custom pets, screenshots and permissions in one place.',
    ogTitle: 'zisla · Put what is happening where you can see it',
    ogDescription:
      'Keep AI tasks and daily activity in view, record and edit on your Mac, import your own pet and manage permissions from one place.',
  },
  tagline: 'Native macOS dynamic workspace',
  header: {
    navAriaLabel: 'Main navigation',
    brandHomeAriaLabel: 'zisla home',
    menuOpenLabel: 'Open navigation menu',
    menuCloseLabel: 'Close navigation',
    menuButtonTitle: 'Open navigation',
    navItems: {
      showcase: 'Features',
      ai: 'AI workflow',
      download: 'Download',
      changelog: 'Changelog',
      faq: 'FAQ',
      developers: 'Developers',
    },
    downloadCta: 'Download',
    downloadCtaAriaLabel: 'Jump to the download section',
    languageLabel: 'Interface language',
    themeLabel: 'Appearance',
    themeModes: { auto: 'Automatic (system)', light: 'Light mode', dark: 'Dark mode' },
  },
  hero: {
    eyebrow: 'NATIVE MACOS WORKSPACE',
    title:
      'zisla<br><em>What is happening,<br>right where you can see it.</em>',
    lede: 'Collect AI tasks, media, files and your agenda at the top of the screen. After you copy something, a separate Quick Actions bar previews it up there and suggests the next step. It appears when needed and steps aside when you are done.',
    downloadCta: 'Download',
    downloadCtaAriaLabel: 'Download',
    sourceCta: 'View source',
    sourceCtaAriaLabel: 'View the zisla source code on GitHub',
    hints: [
      'Move to the top of the screen to expand — no click needed',
      'After copying, press Command+N for the smart next step',
      'Collapses on its own, without interrupting your work',
    ],
  },
  proof: {
    ariaLabel: 'Product overview',
    items: {
      modules: { title: '{count} top-of-screen modules', desc: 'Enable the workflows you need' },
      os: { title: 'macOS 14+', desc: 'A native desktop experience' },
      displays: { title: 'Multi-display', desc: 'Works on notched and external screens' },
      local: { title: 'Local first', desc: 'AI status never reads your conversations' },
    },
  },
  showcase: {
    eyebrow: 'ONE ENTRY POINT / EVERYDAY WORKFLOWS',
    title: 'Everyday workflows, <span>parked at the top of the screen.</span>',
    lede: 'From AI tasks to the clipboard, your agenda and system status, zisla gathers scattered desktop workflows behind a single entry point.',
    ariaLabel: 'zisla feature catalogue',
    summaryMono: '{modules} MODULES / {groups} WORKFLOWS',
    summaryLede:
      'From top-of-screen workflows to local tools, every task you can actually complete is spelled out here.',
    summaryNote:
      '{modules} top-of-screen modules and {features} standalone capabilities, from window previews and capture to AI management and recommended apps.',
    groupNames: {
      island: 'Top-of-screen workflows',
      ai: 'AI workflow',
      daily: 'Everyday information',
      tools: 'Utilities',
    },
    groupCount: '{count} modules',
    pointsAriaLabel: 'Highlights of {name}',
    modules: {
      dashboard: {
        name: 'Home',
        caption:
          'Live cards appear only while a focus session, AI task or download is running, so nothing takes up space when nothing is happening.',
        points: ['Appears on demand', 'Live progress', 'Layout adapts automatically'],
      },
      shelf: {
        name: 'Shelf',
        caption:
          'Drag files, audio, video or links onto the trigger strip at the top of the screen to drop them on the shelf, reveal them in Finder, or open the macOS share menu.',
        points: ['Drag to the top to stash', 'Reveal in Finder', 'System share menu'],
      },
      clipboard: {
        name: 'Clipboard',
        caption:
          'Browse clipboard history inside the island, filter by image, URL, path and file type, and see when each entry was copied. Send an entry to Quick Notes, pin it as a favourite, or delete it.',
        points: ['History inside the island', 'Filter by type', 'Quick Notes and favourites'],
      },
      aiMonitor: {
        name: 'AI monitor',
        caption:
          'Aggregates tasks and status from AI CLIs, desktop apps and IDEs, including Delta, Orca, WorkBuddy and WorkBuddy AI. Cumulative token trends and a contribution heatmap use reliable numeric usage where available, without parsing prompt or reply text. Cursor task detection is added, while Cursor and Muse Code provide numeric usage and available subscription quotas; Cursor tasks stay visible during long tool runs.',
        points: [
          'Tasks aggregated across tools',
          'Token consumption trends',
          'Never reads prompts or replies',
        ],
      },
      keyboardSound: {
        name: 'Keyboard sounds',
        caption:
          'Plays 20 built-in mechanical keyboard voices for global key presses, with adjustable volume and natural pitch variation, plus release sounds where the voice supports them. Turn on local typing stats to see today at a glance, typing trends, history, an app timeline and a per-key heatmap that includes F1-F12. Voice totals, dictation duration, speed and saved time share the keyboard dashboard. New configurations enable sounds and typing stats; each can be disabled separately.',
        points: ['20 built-in voices', 'Release sounds and pitch variation', 'Typing stats can be switched separately'],
      },
      download: {
        name: 'Downloader',
        caption:
          'Paste a link, or let zisla pick links up from the clipboard once enabled. Choose an available video or audio format, and use Cookies from an installed browser when a Douyin download needs them. Download to the default or a folder of your choice, with a source icon, live progress and a completion state.',
        points: ['Choose video or audio formats', 'Douyin browser Cookies', 'Source icon and live progress'],
      },
      agenda: {
        name: 'Agenda and weather',
        caption:
          'Shows weather for your current location plus up to six places you pick. View, add and delete calendar events and reminders, and mark reminders as done.',
        points: ['Weather cards for several places', 'Calendar and to-dos', 'Complete a reminder in one tap'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Reads the accounts you have enabled in Mail. Check the inbox, mark messages as read, reply, compose and move to Trash inside the island, with clear guidance whenever a permission is missing. Choose files while composing to attach them to the message.',
        points: ['Mail accounts', 'Reply and compose in the island', 'Transparent permission guidance'],
      },
      quickNotes: {
        name: 'Quick Notes',
        caption:
          'Backed by the system Notes app: view, edit, create and delete notes with live Markdown preview, and jump straight to the first nine notes with Command+1 through 9. Drafts are written back to Notes automatically.',
        points: ['Data lives in Notes', 'Markdown editor', 'Drafts saved back automatically'],
      },
      volumeMixer: {
        name: 'Application volume mixer',
        caption: 'Adjust volume and mute separately for apps that are playing audio. Available on macOS 14.4 or later, with System Audio Recording permission.',
        points: ['Volume per app', 'Mute separately', 'macOS 14.4+'],
      },
      toolbox: {
        name: 'Utilities',
        caption:
          'Focus countdown, keep the display awake, screen cleaning, keyboard cleaning (which blocks key presses including F1-F12 while it runs), a teleprompter, a mirror and the Trash, all on one page.',
        points: ['Focus countdown', 'Blocks F1-F12 while cleaning', 'Teleprompter and mirror'],
      },
      system: {
        name: 'System status',
        caption:
          'Check CPU, GPU, memory, disk, network and fan status, read NVMe SMART temperature where the hardware reports it, keep a minute-level history you can chart for any time range and export as .xlsx. Scan app caches, Apple user caches, logs and leftover preference files, then review and move selected items to Trash with visible results. See detailed metrics for this Mac — charge, health, cycle count, temperature and capacity — plus the battery level of nearby devices the system exposes. Public IPv4 and IPv6 addresses are displayed separately.',
        points: ['Chip-level monitoring', 'History charts and .xlsx export', 'Review before moving to Trash'],
      },
    },
  },
  extensions: {
    eyebrow: 'INSIDE AND OUTSIDE THE ISLAND',
    title: 'Away from the island, <span>still a desktop tool.</span>',
    lede: 'Screenshots, voice, media, browser downloads and AI management each show up wherever they are easiest to reach.',
    ariaLabel: 'Standalone desktop capabilities',
    summaryMono: 'BEYOND THE ISLAND',
    summaryLede: 'Frequently used capabilities, each where it feels natural.',
    summaryNote:
      'Window previews, capture and Quick Actions each stay within reach; recommended apps help you discover more desktop tools.',
    features: {
      floatingIsland: {
        title: 'A floating island that follows your layout',
        description: 'Use the camera position or choose a custom position along a screen edge. Your custom placement is remembered when switching modes. Compact horizontal and vertical layouts adapt their length to status icons, AI tasks, downloads and media, with an option to show more information.',
        detail: 'Custom placement · Persistent status icons · Adaptive information',
      },
      dailyBriefing: {
        title: 'Your day, in a daily briefing',
        description: 'Choose from eight templates, select usage, typing, system and zisla activity metrics, and preview the layout. Export a PNG manually or at a chosen daily time. System Screen Time history is used when enabled and available; unavailable data is not presented as measured zero.',
        detail: '8 templates · Select content · Preview and scheduled PNG export',
      },
      userCare: {
        title: 'Care reminders while you work',
        description: 'Set a reminder interval for breaks, water, movement and eye rest, with messages adapted to the time of day. Timing resets after natural breaks, locking or sleep. Focus completion and note actions can also show brief feedback in the island. Turn care reminders on or off in Settings.',
        detail: 'Adjustable interval · Time-aware messages · Respects idle and sleep',
      },
      contextNotes: {
        title: 'Notes tied to where you are',
        description: 'Save an editable note for a webpage, app window or desktop, and see it when you return. Attach an app-window screenshot, manage notes on the shelf and set recurring reminders from one hour to three days, or turn reminders off.',
        detail: 'Location notes · Window screenshots · Recurring reminders',
      },
      recording: {
        title: 'Record and edit in the recording studio',
        description: 'Record a display, window or region with optional system audio, microphone and camera. Edit video, audio, images and text across tracks, add animations, zooms and captions, and review a sharp live preview. Choose original, 16:9, 9:16, 1:1 or 4:3 canvas ratios. Export video, GIF, Live Photo or audio; some formats require FFmpeg. Optional AI edits are previewed before you apply them.',
        detail: 'Multitrack editing · Canvas ratios and preview · Video, GIF, Live Photo and audio',
      },
      permissions: {
        title: 'System permissions in one place',
        description: 'Review permission status in Settings → Permissions, start supported requests or open the relevant System Settings page. The same permission list is available during first-launch onboarding; manual permissions are labelled accordingly.',
        detail: 'Permission status · Requests and settings links · Shared with onboarding',
      },
      pdf: {
        title: 'PDF tools',
        description: 'Available in Settings rather than the island module carousel. Fourteen operations that all run on your Mac: merge, split, rotate, crop, convert images and Office files, render to images, extract text, add text or image watermarks, add page numbers, encrypt, remove a password and edit metadata.',
        detail: '14 on-device tools · Merge in your own order · Nothing leaves your Mac',
      },

      windowPreviews: {
        title: 'Preview a window. Click to switch.',
        description:
          'Preview windows from the Dock or while switching with Command-Tab, then click a card to activate its window. New configurations enable this feature; manage it and its permissions in Settings.',
        detail: 'Dock and Command-Tab · Click to switch windows · Configurable in Settings',
      },
      capture: {
        title: 'Screenshots, scrolling captures and pinning',
        description:
          'Capture, pin or stitch scrolling screenshots with configurable shortcuts. Highlight areas, extract image regions, round corners and preserve annotations on export. Recognise text and copy it, translate recognised text and copy the result, or export recognised tables as .xlsx. Stash screenshots on the shelf. Shortcut settings check conflicts with voice input and Quick Actions.',
        detail: 'Highlight and extract · OCR, translation and copy · Rounded corners and .xlsx',
      },
      voice: {
        title: 'Voice input and cleanup',
        description:
          'Toggle with a key or hold to talk using system speech recognition, with domain vocabularies and custom hot words. Optionally use Ollama, LM Studio or a remote model to correct the transcript while preserving your meaning, and format explicitly listed items.',
        detail: 'Two recording modes · Vocabularies and hot words · Optional model cleanup',
      },
      media: {
        title: 'Media and system ambient sounds',
        description:
          'Control what is playing from the top of the island, or pick a macOS system ambient sound. It can stop by itself when the screen locks, the screen saver starts or the display sleeps. Choose a waveform or artwork glow; playback progress also appears in compact and floating layouts.',
        detail: 'Playback control · Synced lyrics · Ambient sound stops automatically',
      },
      browserDownloads: {
        title: 'Browser download progress',
        description:
          'Detects downloads in Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera and Arc, and shows their source and live progress at the top of the screen.',
        detail: '8 browsers · Source detection · Completion notice',
      },
      copyAssistant: {
        title: 'Quick Actions and smart next steps',
        description:
          'Once enabled, copied text, links, files or images are previewed in a separate bar at the top of the screen. It recognises links, locally installed app names and emoji names, and can convert copied currency amounts at current exchange rates; every next step is carried out only after you confirm. Open the containing folder through Quick Actions after a browser download or AirDrop transfer. Supports default and chosen Chrome download folders, with a separate switch from download progress. IP addresses have separate lookup and open-link actions. Currency conversion recognises local minor units, and the emoji catalogue includes Emoji 18.0.',
        detail: 'On-device recognition · Live currency conversion · Command+N by default',
      },
      aiManagement: {
        title: 'AI CLI and Skills management',
        description:
          'Detect, install, update and remove popular AI CLIs from Settings, and review and manage local Skills, so you switch between terminals and tools less often.',
        detail: 'Detect and install · Update and remove · Local Skills',
      },
      pet: {
        title: 'Island pet',
        description:
          'Choose from the expanded built-in animal and character catalogue, or import a supported image, animated image or video as a named pet. Place it on either side of the island and remove imported pets in Settings. Imports support animations up to 30 seconds and files up to 100 MB.',
        detail: 'Expanded catalogue · Image and video import · Remove custom pets',
      },
      lockScreen: {
        title: 'Lock screen information',
        description:
          'Optionally show the date, status and now playing on the macOS lock screen. It is a separate lock screen overlay and never appears in the island module list or carousel.',
        detail: 'Separate lock screen overlay · Opt in · Never takes focus',
      },
      recommendedTools: {
        title: 'Recommended apps',
        description:
          'Discover tools such as OpenScreen for screen recording and video editing, and DockDoor for Dock window previews and app switching. These are third-party apps installed separately.',
        detail: 'Discover desktop tools · Third-party apps · Separate installation',
      },
    },
  },
  ai: {
    eyebrow: 'AI WITHOUT A BLACK BOX',
    title: 'See AI status <span>without reading the conversation.</span>',
    lede: 'Bring session status from CLIs, desktop apps and IDEs into the island. Token trends use reliable numeric usage, never context occupancy as consumption.',
    summaryMono: 'ON-DEVICE STATUS / CLEAR BOUNDARIES',
    summaryLede: 'Different harnesses. One place for status.',
    summaryNote:
      'WorkBuddy and WorkBuddy AI are detected independently, with separate sessions, branding and open actions — not one interchangeable product.',
    toolsHeading: '{tools} AI tools and harnesses',
    toolsLede:
      'Detects supported CLI, desktop and IDE activity. Delta, Orca, WorkBuddy and WorkBuddy AI each retain their own name.',
    toolsAriaLabel: 'Supported AI tools and harnesses',
    usageNote:
      'Session detection does not imply usage tracking. Delta uses its local numeric usage ledger. Orca reuses and deduplicates bound CLI usage under the underlying provider. WorkBuddy AI is session-only for now: context occupancy and credits are not converted into cumulative tokens or USD cost.',
    boundariesHeading: 'Only status boundaries are recorded',
    privacyPoints: [
      'Parses status metadata (including session titles, timestamps, models and session identifiers) and reliable numeric usage only',
      'Does not parse prompt or reply text, or upload conversations',
      'Third-party session stores are read-only; protocol, status and usage records stay on your Mac',
    ],
    bridgeHeading: 'Bring in your own tasks',
    bridgeLede: 'Use zislactl to push structured status from external tasks into the status bar.',
    zislactlTaskTitle: 'Build and release',
    copyZislactlAriaLabel: 'Copy the zislactl command',
  },
  flow: {
    eyebrow: 'INTERACTION RHYTHM',
    title: 'Move up, <span>take a look, then let it go.</span>',
    lede: 'It never takes focus, and it collapses once you have looked.',
    ariaLabel: 'Top-of-screen interaction rhythm',
    summaryMono: 'STATUS BAR / 3 STEPS',
    summaryLede: 'Expands when you need it, retracts when you are done reading.',
    summaryNote:
      'Triggered by pointer position. With nothing to show it takes up no visual space, and it never steals focus from the app you are using.',
    steps: {
      trigger: {
        phase: 'Trigger',
        title: 'Move to the top centre of the screen',
        desc: 'Notched and external displays use the same trigger, and no frame loop runs while it is hidden.',
      },
      review: {
        phase: 'Review',
        title: 'Glance at the current status',
        desc: 'Media, files, AI, agenda and system tools all live in the same place.',
      },
      dismiss: {
        phase: 'Dismiss',
        title: 'Get back to what you were doing',
        desc: 'Move the pointer away and it collapses; expanding never activates the app or takes focus.',
      },
    },
  },
  download: {
    eyebrow: 'READY WHEN YOU ARE',
    title: 'Download zisla',
    copy: 'For Apple silicon Macs. Versions, other architectures and checksums are on the release page. After installing, zisla can check for new versions on your chosen update channel: Sparkle verifies the signature first, then downloads, installs and restarts manually or automatically according to your settings, and updates keep the permissions you have already granted. The Updates settings also link directly to the issue tracker for feedback. If a release does not concern you, skip it and zisla will not bring it up again. Read release notes before installing an update and after restarting.',
    primaryCta: 'Download',
    primaryCtaAriaLabel: 'Download',
    releaseCta: 'View release',
    releaseCtaAriaLabel: 'View the release details on GitHub',
    brewMono: 'HOMEBREW / ONE COMMAND',
    brewNote: 'Sparkle keeps zisla up to date, so brew upgrade replaces the app only when the installed copy really is older than the one in the tap — Homebrew 5.1.6 and later read the version inside the app itself. Naming the cask, as in brew upgrade --cask zisla, goes by the Homebrew install records instead, which can move you back to the tap version after a Sparkle update. The tap serves stable releases only. It is a third-party tap and the app is not notarized, so the first launch needs Open Anyway in System Settings → Privacy & Security.',
    copyBrewCommandAriaLabel: 'Copy the Homebrew install command',
    notes: {
      system: {
        term: 'System',
        value: 'macOS 14 or later · Apple silicon Macs are the supported configuration today',
      },
      install: { term: 'Install', value: 'Mount the DMG and drag it into Applications' },
      package: { term: 'Package', value: 'Apple Silicon (arm64) · DMG' },
      architectures: { term: 'Other architectures', value: 'Release page' },
      mirror: { term: 'Mirror', value: 'Gitee Releases' },
    },
  },
  changelog: {
    releaseNotes: {
      'v0.1.20': [
        'Daily briefings offer eight templates, selectable usage, typing, system and zisla activity content, previews, and manual or scheduled local PNG export. Optional system Screen Time history is included only when available.',
        'Contextual care reminders have an adjustable interval, time-of-day messages and feedback for focus and note actions. Idle, lock and sleep reset timing. Location notes can attach app-window screenshots and repeat reminders from one hour to three days.',
        'Floating islands support remembered custom placement, adaptive horizontal and vertical compact layouts, persistent status icons and more-information mode. Media gains waveform or artwork-glow styles with playback progress across layouts.',
        'The expanded pet catalogue includes more animals and characters. Import images, animations or videos as pets, name them and remove custom entries; animations are limited to 30 seconds and source files to 100 MB.',
        'Recording Studio captures displays, windows or regions with optional system audio, microphone and camera. Multitrack video, audio, image and text editing adds animations, captions, zooms, sharper previews and five canvas ratios, with video, GIF, Live Photo and audio export. Optional AI proposals require applying the previewed plan.',
        'Screenshots add highlighting, region extraction and rounded corners. Text recognition can copy text or translate and copy it; table recognition exports .xlsx. Capture and recording reliability, including recording audio, is improved.',
        'AI monitoring adds Cursor task detection and numeric usage plus available subscription quotas for Cursor and Muse Code. Long Cursor tool runs remain visible. Clipboard actions separate IP lookup from opening links, recognise currency minor units and use Emoji 18.0 names.',
        'Application volume and mute controls replace PDF tools in the island; PDF tools move to Settings and battery information joins system status. Permissions are centralised in Settings. New configurations enable keyboard sounds, typing stats, window previews and care reminders; voice totals appear on the keyboard dashboard. Mail can attach selected files, and updates show release notes before installation and after restart.',
      ],
    },
    eyebrow: 'Changelog',
    title: 'What changed in each zisla release: new features, improvements, and fixes.',
    lede: 'What changed in each zisla release: new features, improvements, and fixes.',
    ariaLabel: 'zisla release history',
    releaseCountLabel: 'releases',
    latestLabel: 'latest',
    shippedLabel: 'shipped',
    latestBadge: 'Latest',
    noteLabel: 'release',
    pagerAriaLabel: 'Changelog pages',
    pageLabel: 'Page {page}',
    prevPageLabel: 'Previous',
    nextPageLabel: 'Next',
  },
  faq: {
    eyebrow: 'A FEW STRAIGHT ANSWERS',
    title: 'Frequently asked questions.',
    lede: 'Permissions, privacy and compatibility.',
    items: {
      audience: {
        question: 'Who is zisla for?',
        answer:
          'Mac users who want AI, media, files and their agenda in one place. Displays without a notch are supported too.',
      },
      aiPrivacy: {
        question: 'Does zisla read my AI conversations?',
        answer:
          'No. AI status monitoring reads task status only, never prompt or reply text.',
      },
      copyAssistant: {
        question: 'Do Quick Actions open or upload what I copy?',
        answer:
          'No. Once enabled, recognition and preview happen entirely on your Mac, and zisla only carries out a next step after you click it or press the quick trigger.',
      },
      permissions: {
        question: 'Which system permissions does zisla need?',
        answer: '<p>Settings → Permissions brings system permission status, requests and links to System Settings together. Some permissions require manual setup. You choose which requests to start; the welcome screen also offers permission controls.</p><p>Screen Recording, System Audio Recording, microphone and camera access support capture, recording, the volume mixer and the mirror as applicable. Voice input additionally uses Speech Recognition. Calendars, Reminders, Location, Bluetooth and Automation support their related features. Adding a weather city manually needs no location permission.</p><p>New configurations enable keyboard sounds and typing stats, with separate switches. Input Monitoring is required for global key events; stats store counts, key codes, timestamps and app names, never the text you type. Accessibility supports insertion, gestures, cleaning and window controls.</p><p>Full Disk Access may be needed for the local mail index and system Screen Time history used by daily briefings. A folder chosen in the system file picker grants access to that folder. You can disable features in zisla or revoke permissions in System Settings → Privacy &amp; Security.</p>',
      },
      localVoice: {
        question: 'How do I use a local model for voice cleanup?',
        answer: `
      <p>Ollama, LM Studio and other OpenAI-compatible local services are supported.</p>
      <ol>
        <li>Download or load the model you want in your local model app, then start its service.</li>
        <li>Open Settings → Voice → Local Models, add and enable a configuration, choose Ollama or LM Studio, and enter the service URL. For another OpenAI-compatible service, also choose LM Studio. Leave API Key empty unless the service requires authentication.</li>
        <li>Select an automatically discovered model, then choose that configuration under Voice Organization Model → Use Model.</li>
      </ol>
      <p>zisla suggests a Gemma 4 QAT model based on your chip and total RAM. It does not automatically download or load the recommended model.</p>
    `.trim(),
      },
      network: {
        question: 'Does zisla go online?',
        answer:
          'Weather, signed update checks, downloads you start and the optional remote voice cleanup use the network on demand. Clipboard link detection runs entirely on your Mac and never starts a download on its own. A local model handles the text cleanup after transcription; Apple speech recognition may still use the network, depending on the language and system support.',
      },
      multiDisplay: {
        question: 'Does zisla support multiple displays?',
        answer:
          'Yes — multiple displays, Spaces and ordinary full-screen apps, and expanding never takes focus.',
      },
      intel: {
        question: 'Can I use it on an Intel Mac?',
        answer:
          'A build may be available for Intel machines, but compatibility is not guaranteed. Apple silicon Macs are the supported configuration today.',
      },
      storage: {
        question: 'Where does zisla store its data?',
        answer:
          'Local data lives in ~/Library/Application Support/zisla/. Typing stats are kept separately in ~/Library/Application Support/zisla/typing-stats.sqlite3. Quick Notes uses the system Notes app.',
      },
    },
  },
  developers: {
    eyebrow: 'OPEN SOURCE BY DEFAULT',
    title: 'Developer resources.',
    lede: 'PolyForm Noncommercial 1.0.0 — noncommercial use only; take it as is, or build it from source.',
    docs: {
      macos: {
        title: 'macOS development guide',
        description: 'Features, building, testing and system limits',
      },
      architecture: {
        title: 'Architecture and performance',
        description: 'Top-of-screen triggering, windows and performance design',
      },
      cli: { title: 'CLI integration', description: 'zislactl commands and fields' },
      releasing: {
        title: 'Signing and releasing',
        description: 'Signing, notarisation and the release process',
      },
      contributing: {
        title: 'Contributing guide',
        description: 'Environment, branches, commits and pull request expectations',
      },
    },
    quickStartMono: 'QUICK START / SOURCE',
    quickStartHeading: 'Run it from source, or connect your own tasks.',
    copyRunCommandAriaLabel: 'Copy the command to run from source',
    githubRepoLabel: 'GitHub repository',
    giteeRepoLabel: 'Gitee repository',
    checksumLabel: 'SHA-256',
    performancePoints: [
      'Supports multiple displays, Spaces and ordinary full-screen apps; expanding never activates the app or takes focus',
      'While hidden it creates no persistent transparent hot-zone window and runs no frame loop; expansion is triggered by global event monitoring and geometry checks',
      'Uses a single layer of system material, and switches to an opaque background when Reduce Transparency is on',
      'Liquid Glass on macOS 26+, with an automatic fallback to native system materials on macOS 14 and 15',
      'A physical notch is inferred from the system safe area; external displays without one get a simulated status bar in a dedicated overlay',
    ],
  },
  footer: {
    brandHomeAriaLabel: 'Back to the zisla home page',
    previewChannelLabel: 'Preview channel',
    tagline: 'Open source, native, and under your control.',
  },
  common: {
    copyCommandTitle: 'Copy command',
    copiedAriaLabel: 'Copied',
  },
  toast: {
    runCommandCopied: 'Source run command copied',
    zislactlCopied: 'zislactl command copied',
    brewCommandCopied: 'Homebrew install command copied',
  },
};
