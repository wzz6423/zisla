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
          'Live cards appear only while a focus session, AI task or download is running, so nothing takes up space when nothing is happening. Running AI work is grouped by application on Home.',
        points: ['Appears on demand', 'Live progress', 'Layout adapts automatically'],
      },
      shelf: {
        name: 'Shelf',
        caption:
          'Drag files, audio, video or links to the top of the screen, then search, filter and select several shelf items to copy, share or send to Quick Notes. Convert images to PDF, recognise image text into Quick Notes, or send videos to the recording studio for editing. Reveal files in Finder whenever needed.',
        points: ['Search and batch actions', 'Images to PDF and Quick Notes', 'Edit videos in the studio'],
      },
      clipboard: {
        name: 'Clipboard',
        caption:
          'Browse clipboard history inside the island, filter by image, URL, path and file type, and see when each entry was copied. Send an entry to Quick Notes, pin it as a favourite, or delete it. Optionally delete history older than 7, 15 or 30 days while keeping favourites; automatic deletion is off by default.',
        points: ['History inside the island', 'Filter by type', 'Quick Notes and favourites'],
      },
      aiMonitor: {
        name: 'AI monitor',
        caption:
          'Aggregates AI tasks and status from CLIs, desktop apps and IDEs. Numeric usage powers token trends and a contribution heatmap; select a date for input, output and total tokens by provider and model. View, export all history as .xlsx or clear it in Settings. Check real account allowances, reset times and low-quota notices, including 5h/7d windows and Cursor USD budgets when available. Prompt and reply text is not read.',
        points: ['Tasks across AI tools', 'Model history and .xlsx export', 'Account allowances and reset times'],
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
          'Paste a link, or let zisla pick links up from the clipboard once enabled. Choose an available video or audio format, and use Cookies from an installed browser when a Douyin download needs them. Download to the default or a folder of your choice, with a source icon, live progress and a completion state. Set the download folder in Settings → Save Location independently of screenshots and recordings. Bilibili links download the selected part.',
        points: ['Choose video or audio formats', 'Douyin browser Cookies', 'Source icon and live progress'],
      },
      agenda: {
        name: 'Agenda and weather',
        caption:
          'Shows weather for your current location and up to six chosen places. View, add and delete calendar events and reminders, and complete reminders. Events with a meeting link show a countdown from 10 minutes before the start and a one-click join action. Create a meeting note or link and unlink existing context notes.',
        points: ['Weather and calendar', '10-minute meeting countdown', 'Join meetings and link notes'],
      },
      mail: {
        name: 'Mail',
        caption:
          'Reads the accounts enabled in Mail. Check the inbox, mark one message or all inbox messages as read, reply, compose and move messages to Trash inside the island. Choose attachments while composing, with clear guidance when a permission is missing.',
        points: ['Mail accounts', 'Reply and compose in the island', 'Transparent permission guidance'],
      },
      quickNotes: {
        name: 'Quick Notes',
        caption:
          'Backed by the system Notes app: view, edit, create and delete notes with live Markdown preview, and jump straight to the first nine notes with Command+1 through 9. Drafts are written back to Notes automatically. Preview handwritten attachments and edit the text before or after them while preserving the originals.',
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
          'Focus countdown, keep the display awake, screen cleaning, keyboard cleaning that blocks keys including F1-F12, a teleprompter, a mirror and the Trash, all on one page. Pause, resume or reset the Pomodoro timer and follow its progress in compact horizontal and vertical layouts.',
        points: ['Focus countdown', 'Blocks F1-F12 while cleaning', 'Teleprompter and mirror'],
      },
      system: {
        name: 'System status',
        caption:
          'Monitor CPU, GPU, memory, disk, network, fans and available NVMe SMART temperature. View minute-level history for any date range, export .xlsx or clear it in Settings. Check battery health, cycle count, temperature, capacity and nearby device levels, plus public IPv4 and IPv6. Choose automatic power modes for plugged-in and battery use, with optional Low Power Mode at 20% or below. Charge to 100% immediately when macOS offers it. Review caches, logs, preference leftovers and orphaned AI workspaces before moving them to Trash; optional cleanup runs every 7, 15 or 30 days. Scheduled cleanup is off by default; choose trusted items only or all actionable items, including those needing review.',
        points: ['Chip-level monitoring', 'History charts and .xlsx export', 'Review before moving to Trash'],
      },
    },
  },
  extensions: {
    eyebrow: 'INSIDE AND OUTSIDE THE ISLAND',
    title: 'Away from the island, <span>still a desktop tool.</span>',
    lede: 'Screenshots, image and audio tools, voice, media, browser downloads and AI management each appear where they are easiest to reach.',
    ariaLabel: 'Standalone desktop capabilities',
    summaryMono: 'BEYOND THE ISLAND',
    summaryLede: 'Frequently used capabilities, each where it feels natural.',
    summaryNote:
      'Window previews, capture and Quick Actions each stay within reach; recommended apps help you discover more desktop tools.',
    features: {
      floatingIsland: {
        title: 'A floating island that follows your layout',
        description: 'Use the camera position or choose a custom position along a screen edge. Your custom placement is remembered when switching modes. Compact horizontal and vertical layouts adapt their length to status icons, AI tasks, downloads and media, with an option to show more information. Reorder island modules or restore the default order in Settings → Info.',
        detail: 'Custom placement · Persistent status icons · Adaptive information',
      },
      dailyBriefing: {
        title: 'Your day, in a daily briefing',
        description: 'Choose from eight templates, select usage, typing, system and zisla activity metrics, and preview the layout. Export a PNG manually or at a chosen daily time. System Screen Time history is used when enabled and available; unavailable data is not presented as measured zero. Choose a separate export folder in Settings → Save Location. Optionally include real account allowances and their sampling times.',
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
        description: 'Record a display, window or region with optional system audio, microphone and camera. Edit video, audio, images and text across tracks with animations, zooms and captions. Adjust portrait smoothing, brightness, face and body slimming, choose voice effects, and add smooth cursor trails in your colour. Play the edited result in the studio. Choose original, 16:9, 9:16, 1:1 or 4:3; export video, GIF, Live Photo or audio, with FFmpeg needed for some formats. Preview optional AI edits before applying them. Recording has its own folder in Settings → Save Location.',
        detail: 'Portrait and voice effects · Coloured cursor trails · Multitrack playback and export',
      },
      permissions: {
        title: 'System permissions in one place',
        description: 'Review permission status in Settings → Permissions, start supported requests or open the relevant System Settings page. The same permission list is available during first-launch onboarding; manual permissions are labelled accordingly.',
        detail: 'Permission status · Requests and settings links · Shared with onboarding',
      },
      imageTools: {
        title: 'Image tools',
        description: 'Nine local tools in Settings: compress; convert PNG, JPEG, WebP, AVIF and JPEG XL; resize and crop; compare the smallest format; rotate and mirror; add watermarks; mosaic and blur; recognise text and tables; and remove backgrounds. Export batches or ZIP files, with a separate image-tools folder in Settings → Save Location.',
        detail: '9 local tools · Five formats · Batch and ZIP export',
      },
      audioTools: {
        title: 'Audio tools',
        description: 'Twenty-seven local operations in Settings, including conversion, compression, trimming, splitting, joining and mixing, extracting audio from video, LUFS normalisation, fades, speed and pitch, noise and silence removal, EQ, dynamics, channels and tags. Requires FFmpeg and ffprobe; choose a file or folder for export.',
        detail: '27 local operations · Editing and mixing · FFmpeg and ffprobe',
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
          'Capture, pin or stitch scrolling screenshots with configurable shortcuts. Highlight areas, extract image regions, round corners and preserve annotations on export. Recognise text and copy it, translate recognised text and copy the result, or export recognised tables as .xlsx. Stash screenshots on the shelf. Shortcut settings check conflicts with voice input and Quick Actions. The save dialog opens in the screenshot folder set in Settings → Save Location. Pinned screenshots stay in place when capturing again. Use slow automatic scrolling for long captures, and capture HDR screenshots on supported devices.',
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
          'Once enabled, copied text, links, files or images are previewed in a separate bar at the top of the screen. It recognises links, locally installed app names and emoji names, and can convert copied currency amounts at current exchange rates; every next step is carried out only after you confirm. Open the containing folder through Quick Actions after a browser download or AirDrop transfer. Supports default and chosen Chrome download folders, with a separate switch from download progress. IP addresses have separate lookup and open-link actions. Currency conversion recognises local minor units, and the emoji catalogue includes Emoji 18.0. Saved text and images use the separate Quick Actions folder in Settings → Save Location. When an app will not open, Quick Actions can check its integrity, signature and macOS security policy, then remove quarantine flags and open it after the checks pass.',
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
          'Discover OpenScreen for screen recording and video editing, DockDoor for window previews and app switching, and Quiet.md for local notes. These third-party apps are installed separately.',
        detail: 'Discover desktop tools · Third-party apps · Separate installation',
      },
    },
  },
  ai: {
    eyebrow: 'AI WITHOUT A BLACK BOX',
    title: 'See AI status <span>without reading the conversation.</span>',
    lede: 'Follow tasks by application, inspect model usage by date and check real account allowances. Status and numeric records stay on your Mac; conversations are not read.',
    summaryMono: 'ON-DEVICE STATUS / CLEAR BOUNDARIES',
    summaryLede: 'Different harnesses. One place for status.',
    summaryNote:
      'WorkBuddy and WorkBuddy AI are detected independently, with separate sessions, branding and open actions — not one interchangeable product.',
    toolsHeading: '{tools} AI tools and harnesses',
    toolsLede:
      'Detects supported CLI, desktop and IDE activity. Delta, Orca, WorkBuddy and WorkBuddy AI each retain their own name.',
    toolsAriaLabel: 'Supported AI tools and harnesses',
    usageNote:
      'Session detection, token history and account allowances have separate data sources. Delta uses its local numeric ledger; Orca deduplicates bound CLI usage under the underlying provider. WorkBuddy AI can detect sessions and query credits; context occupancy and credits are not converted into tokens or USD cost. Quota availability follows the provider and login method.',
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
      'v0.1.22': [
        'Recording Studio adds portrait smoothing, brightening, face and body slimming, adjustable voice presets and optional microphone monitoring. Effects can be adjusted during setup and editing.',
        'Smooth cursor trails have a selectable colour. Studio playback shows the edited result, including its tracks, effects and audio.',
        'Settings → Save Location separates downloads, screenshots, recordings, Quick Actions and daily briefings. Existing locations are preserved on upgrade, then each folder can be changed independently.',
        'Optional system junk cleanup runs every 7, 15 or 30 days and moves items to Trash. Choose trusted items or all actionable items, including those requiring review; it is off by default. Disk cleanup also adds orphaned AI session workspace review, protecting retained sessions and newly created workspaces.',
        'Clipboard history can automatically delete entries older than 7, 15 or 30 days while preserving favourites. Automatic deletion is off by default.',
        'Quick Notes previews handwritten attachments and supports editing the text before or after them through Notes while preserving the original attachments.',
        'AI monitoring hides remaining subscription allowances while keeping daily usage and improves chart scrolling and month labels. Battery monitoring settings are grouped under System Status.',
        'Quiet.md joins recommended desktop apps for local notes, with installation and management in Settings.',
        'Bilibili downloads honour the selected video part and handle more link formats. Calendar deletion targets the selected recurring occurrence. Pinned screenshots stay visible across repeated captures, with clearer tool labels and more reliable size badges.',
      ],
      'v0.1.21': [
        'System monitoring keeps all existing and new minute-level history by default until you clear it. Charts for any time range and .xlsx export remain available.',
        'Downloads, recordings and screenshots share one save location. Screenshot save dialogs open in the current download folder; the duplicate recording save-location setting is removed.',
        'Status Display Location and its search entry appear only for custom-positioned pill layouts. The row is hidden when notch or camera-positioned pill layouts can only use the menu bar.',
        'Quick Actions countdowns use a bottom progress track in notch layouts. Pill layouts retain progress around the full perimeter.',
      ],
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
          'Local data lives in ~/Library/Application Support/zisla/. Typing stats are kept separately in ~/Library/Application Support/zisla/typing-stats.sqlite3. Quick Notes uses the system Notes app. Settings → Save Location provides independent folders for downloads, screenshots, recordings, Quick Actions and daily briefings. On upgrade, each inherits the previous shared folder and can then be changed separately.',
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
  film: {
    title: "Launch film",
    videoAriaLabel: "zisla launch film",
    openVideoLabel: "Open video",
    playbackError: "Unable to play the video.",
    musicLabel: "Music",
    excerptLabel: "Excerpt",
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
