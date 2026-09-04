import type { SiteContent } from '../content';

export const en: SiteContent = {
  meta: {
    documentTitle: 'zisla · Dynamic workspace',
    description:
      'zisla is a native dynamic workspace for macOS. Keep AI tasks such as Zed Agent, media, files and your agenda in one place, with keyboard sounds, typing stats, screenshot annotation and a copy assistant.',
    ogTitle: 'zisla · Put what is happening where you can see it',
    ogDescription:
      'From AI tasks such as Zed Agent and media playback to keyboard sounds, typing stats, the copy assistant, screenshot annotation and desktop tools — a native macOS workspace that appears only when you need it.',
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
      faq: 'FAQ',
      developers: 'Developers',
    },
    downloadCta: 'Download',
    downloadCtaAriaLabel: 'Jump to the download section',
    languageLabel: 'Interface language',
  },
  hero: {
    eyebrow: 'NATIVE MACOS WORKSPACE',
    title:
      'zisla<br><em>What is happening,<br>right where you<br class="hero-mobile-break"> can see it.</em>',
    lede: 'Collect AI tasks, media, files and your agenda at the top of the screen. After you copy something, a separate assistant bar previews it up there and suggests the next step. It appears when needed and steps aside when you are done.',
    downloadCta: 'Download',
    downloadCtaAriaLabel: 'Download',
    sourceCta: 'View source',
    sourceCtaAriaLabel: 'View the zisla source code on GitHub',
    hints: [
      'Move to the top of the screen to expand — no click needed',
      'After copying, press Command+N for the smart next step',
      'Collapses on its own, without interrupting your work',
    ],
    identityCaption: 'Top of the screen',
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
      '{modules} top-of-screen modules plus {features} standalone capabilities covering screenshots, voice, media, downloads, the copy assistant, AI management, the pet and the lock screen.',
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
          'Browse clipboard history inside the island and filter by image, URL, path and file type. Send an entry to Quick Notes, pin it as a favourite, or delete it.',
        points: ['History inside the island', 'Filter by type', 'Quick Notes and favourites'],
      },
      aiMonitor: {
        name: 'AI monitor',
        caption:
          'Automatically detects activity from supported AI CLIs, desktop apps and IDEs, including Zed Agent threads, and shows tasks, status, cumulative token trends and a contribution heatmap. It parses structured events only and never reads conversation text.',
        points: [
          'Tasks aggregated across tools',
          'Token consumption trends',
          'Never reads prompts or replies',
        ],
      },
      keyboardSound: {
        name: 'Keyboard sounds',
        caption:
          'Plays 20 built-in mechanical keyboard voices for global key presses, with adjustable volume and natural pitch variation, plus release sounds where the voice supports them. Turn on local typing stats to see today at a glance, typing trends, history, an app timeline and a per-key heatmap that includes F1-F12.',
        points: ['20 built-in voices', 'Release sounds and pitch variation', 'Typing stats optional'],
      },
      download: {
        name: 'Downloader',
        caption:
          'Paste a link, or let zisla pick links up from the clipboard once enabled. Choose video or audio and download to the default or a folder of your choice. Common video platforms and other supported links show a source icon, live progress and a completion state.',
        points: ['Video / audio modes', 'Default or custom folder', 'Source icon and live progress'],
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
          'Reads the accounts you have enabled in Mail. Check the inbox, mark messages as read, reply, compose and move to Trash inside the island, with clear guidance whenever a permission is missing.',
        points: ['Mail accounts', 'Reply and compose in the island', 'Transparent permission guidance'],
      },
      quickNotes: {
        name: 'Quick Notes',
        caption:
          'Backed by the system Notes app: view, edit, create and delete notes with live Markdown preview. Drafts are written back to Notes automatically.',
        points: ['Data lives in Notes', 'Markdown editor', 'Drafts saved back automatically'],
      },
      pdf: {
        name: 'PDF tools',
        caption:
          'Fourteen operations that all run on your Mac: merge, split, rotate, crop, convert images and Office files, render to images, extract text, add text or image watermarks, add page numbers, encrypt, remove a password and edit metadata.',
        points: ['14 on-device tools', 'Merge in your own order', 'Nothing leaves your Mac'],
      },
      toolbox: {
        name: 'Utilities',
        caption:
          'Focus countdown, keep the display awake, screen cleaning, keyboard cleaning (which blocks key presses including F1-F12 while it runs), alarms, a teleprompter, a mirror and the Trash, all on one page.',
        points: ['Focus countdown', 'Blocks F1-F12 while cleaning', 'Teleprompter and mirror'],
      },
      system: {
        name: 'System status',
        caption:
          'Check CPU, GPU, memory, disk, network and fan status, read NVMe SMART temperature where the hardware reports it, and clear caches and logs that are safe to delete.',
        points: ['Chip-level monitoring', 'NVMe temperature where supported', 'Clear caches in one tap'],
      },
      battery: {
        name: 'Battery',
        caption:
          'See detailed metrics for this Mac — charge, health, cycle count, temperature and capacity — plus the battery level of nearby devices the system exposes.',
        points: ['Health metrics for this Mac', 'Time remaining', 'Nearby device battery'],
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
      'Screenshots, recording, media, browser downloads, the copy assistant, AI management, the pet and the lock screen are each presented on their own.',
    features: {
      capture: {
        title: 'Screenshots, scrolling captures and pinning',
        description:
          'Capture or pin part of the screen with a global shortcut, then annotate, stitch a scrolling capture, and recognise or export tables. Text annotations you are still editing are preserved when you export.',
        detail: 'Global shortcut · Annotate and undo · Edits kept on export',
      },
      voice: {
        title: 'Voice input and cleanup',
        description:
          'Toggle with a key or hold to talk, using the system speech recogniser. Add domain vocabularies, custom hot words, structured formatting, or cleanup by a local or remote model as needed.',
        detail: 'Two recording modes · Vocabularies and hot words · Optional model cleanup',
      },
      media: {
        title: 'Media and system ambient sounds',
        description:
          'Control what is playing from the top of the island, or pick a macOS system ambient sound. It can stop by itself when the screen locks, the screen saver starts or the display sleeps.',
        detail: 'Playback control · Synced lyrics · Ambient sound stops automatically',
      },
      browserDownloads: {
        title: 'Browser download progress',
        description:
          'Detects downloads in Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera and Arc, and shows their source and live progress at the top of the screen.',
        detail: '8 browsers · Source detection · Completion notice',
      },
      copyAssistant: {
        title: 'Copy assistant and smart next steps',
        description:
          'Once enabled, copied text, links, files or images are previewed in a separate bar at the top of the screen, with next steps suited to the content — open, reveal in Finder, search, translate, calculate or save — carried out only after you confirm.',
        detail: 'Optional toggle · On-device recognition · Command+N by default',
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
          'Pick one of the built-in pets and place it on the left or right side of the island. Turn it off whenever you like.',
        detail: 'Built-in characters · Left or right · On when you want it',
      },
      lockScreen: {
        title: 'Lock screen information',
        description:
          'Optionally show the date, status and now playing on the macOS lock screen. It is a separate lock screen overlay and never appears in the island module list or carousel.',
        detail: 'Separate lock screen overlay · Opt in · Never takes focus',
      },
    },
  },
  ai: {
    eyebrow: 'AI WITHOUT A BLACK BOX',
    title: 'See AI status <span>without reading the conversation.</span>',
    lede: 'Tasks, status and token trends stay on your Mac. This page describes what the feature does and does not invent a screenshot of a running task.',
    summaryMono: 'ON-DEVICE STATUS / CLEAR BOUNDARIES',
    summaryLede:
      'Connect the AI tools you already use while keeping the context boundaries your work requires.',
    summaryNote:
      'This page only describes the detection scope, the data boundary and how to connect — it does not simulate a live session.',
    toolsHeading: 'Supported AI tools',
    toolsLede:
      'Detects activity from supported CLIs, desktop apps and IDEs, and aggregates task status.',
    toolsAriaLabel: 'Supported AI tools',
    doubaoName: 'Doubao',
    boundariesHeading: 'Only status boundaries are recorded',
    privacyPoints: [
      'Parses only the event type, status, timestamp, model and session ID from structured events',
      'Never reads prompt or reply text',
      'Protocol and status are stored on your Mac',
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
    copy: 'For Apple silicon Macs. Versions, other architectures and checksums are on the release page. After installing, zisla can check for new versions on your chosen update channel: Sparkle verifies the signature first, then downloads, installs and restarts manually or automatically according to your settings.',
    primaryCta: 'Download',
    primaryCtaAriaLabel: 'Download',
    releaseCta: 'View release',
    releaseCtaAriaLabel: 'View the release details on GitHub',
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
        question: 'Does the copy assistant open or upload what I copy?',
        answer:
          'No. Once enabled, recognition and preview happen entirely on your Mac, and zisla only carries out a next step after you click it or press the quick trigger.',
      },
      permissions: {
        question: 'Which system permissions does zisla need?',
        answer: `
      <p>zisla does not ask for every permission at first launch. macOS shows each prompt only when you turn on and actually use the matching feature:</p>
      <ul>
        <li><strong>Calendars and Reminders:</strong> requested separately when you open the agenda module, to read, create and manage calendar events and dated reminders.</li>
        <li><strong>Location Services:</strong> requested when you choose weather for your current location. zisla takes a single location fix and does not track you continuously. Adding a city manually needs no location permission.</li>
        <li><strong>Microphone and Speech Recognition:</strong> requested when you start voice input. Audio is captured only while you are actively recording, and only that recording is transcribed.</li>
        <li><strong>Accessibility:</strong> needed to insert a transcript into the current app automatically, for mouse-gesture quick copy, for keyboard cleaning and for controlling some supported players. It is used to locate non-password input fields or send the required system keys.</li>
        <li><strong>Input Monitoring:</strong> used for keyboard sounds, the optional local typing stats, and global triggers such as a lone modifier key or a mouse side button. It listens only for the global events those features need — ordinary global shortcuts do not require it.</li>
        <li><strong>Screen Recording and System Audio Recording:</strong> needed for screenshots, screenshot editing and the waveform for system audio playback. Screenshots read the screen image; the waveform only analyses current system audio levels and never stores or uploads audio.</li>
        <li><strong>Camera:</strong> used only while the mirror window is open.</li>
        <li><strong>Bluetooth:</strong> used only while the battery module is open, to read the battery level that connected or paired devices publish.</li>
        <li><strong>Automation:</strong> the first time you use Quick Notes, Mail, desktop tidy-up or direct control of a supported player, macOS asks separately whether zisla may control Notes, Mail, Finder or that app. Quick Notes reads and writes Notes; Mail can read, compose, reply, flag and delete messages.</li>
        <li><strong>Full Disk Access:</strong> needed only when Mail is not running and zisla still has to read the local mail index to show accounts, senders, subjects, previews, timestamps and read state.</li>
        <li><strong>Notifications:</strong> requested when you enable the Pomodoro timer or alarms, purely to show a local notification when a timer ends or an alarm fires.</li>
      </ul>
      <p><strong>Folders are not Full Disk Access:</strong> for the shelf, import/export or download folders you pick in the system file picker, zisla receives access to that folder only, never read access to the whole disk.</p>
      <p><strong>Keyboard sounds and typing stats:</strong> both are off by default, and global keyboard events are only observed once one of them is on. With keyboard sounds on, key events are used solely to play a sound; with typing stats on, only aggregate data — character counts, physical key codes, timestamps and the frontmost app — is stored, never what you typed. You can turn each off separately in Settings, after which nothing more is recorded. Data already stored stays in a local database file that you are free to delete.</p>
      <p>You can turn a feature off in the app's settings, or revoke a permission at any time in System Settings → Privacy &amp; Security. Revoking one permission only disables the related feature and leaves other modules untouched. Item names differ slightly between macOS versions.</p>
    `.trim(),
      },
      network: {
        question: 'Does zisla go online?',
        answer:
          'Weather, signed update checks, downloads you start and the optional remote voice cleanup use the network on demand. Clipboard link detection runs entirely on your Mac and never starts a download on its own.',
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
          'Local data lives in ~/Library/Application Support/zisla/. Typing stats are kept separately in ~/Library/Application Support/SimuBoard/typing-stats.sqlite3. Quick Notes uses the system Notes app.',
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
  },
};
