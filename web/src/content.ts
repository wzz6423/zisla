import { loadCatalog, loadedCatalog } from './i18n';
import type { SiteLocale } from './locales';

/* ===== Locale-independent structure =====
 * Ids and ordering live here so translations never have to repeat layout data,
 * and so grouping never depends on matching a translated string.
 */

export const navIds = ['showcase', 'ai', 'download', 'faq', 'developers', 'changelog'] as const;
export type NavId = (typeof navIds)[number];

export const navHrefs: Record<NavId, string> = {
  showcase: '#showcase',
  ai: '#ai',
  download: '#download',
  changelog: '#changelog',
  faq: '#faq',
  developers: '#developers',
};

export const proofIds = ['modules', 'os', 'displays', 'local'] as const;
export type ProofId = (typeof proofIds)[number];

export const showcaseGroupKeys = ['island', 'ai', 'daily', 'tools'] as const;
export type ShowcaseGroupKey = (typeof showcaseGroupKeys)[number];

export const showcaseModuleIds = [
  'dashboard',
  'shelf',
  'clipboard',
  'aiMonitor',
  'keyboardSound',
  'download',
  'agenda',
  'mail',
  'quickNotes',
  'pdf',
  'toolbox',
  'system',
  'battery',
] as const;
export type ShowcaseModuleId = (typeof showcaseModuleIds)[number];

/** Rendering order inside each group follows this array, as it did before. */
export const showcaseModuleGroups: readonly {
  id: ShowcaseModuleId;
  group: ShowcaseGroupKey;
}[] = [
  { id: 'dashboard', group: 'island' },
  { id: 'shelf', group: 'island' },
  { id: 'clipboard', group: 'island' },
  { id: 'aiMonitor', group: 'ai' },
  { id: 'keyboardSound', group: 'tools' },
  { id: 'download', group: 'tools' },
  { id: 'agenda', group: 'daily' },
  { id: 'mail', group: 'daily' },
  { id: 'quickNotes', group: 'daily' },
  { id: 'system', group: 'daily' },
  { id: 'battery', group: 'daily' },
  { id: 'pdf', group: 'tools' },
  { id: 'toolbox', group: 'tools' },
];

export const crossModuleFeatureIds = [
  'windowPreviews',
  'capture',
  'voice',
  'media',
  'browserDownloads',
  'copyAssistant',
  'aiManagement',
  'pet',
  'lockScreen',
  'recommendedTools',
] as const;
export type CrossModuleFeatureId = (typeof crossModuleFeatureIds)[number];

export const crossModuleFeatureIcons: Record<CrossModuleFeatureId, string> = {
  windowPreviews: 'app-window',
  capture: 'image',
  voice: 'mic',
  media: 'waves',
  browserDownloads: 'download',
  copyAssistant: 'copy',
  aiManagement: 'bot',
  pet: 'sparkles',
  lockScreen: 'lock',
  recommendedTools: 'external-link',
};

export const flowStepIds = ['trigger', 'review', 'dismiss'] as const;
export type FlowStepId = (typeof flowStepIds)[number];

export const downloadNoteIds = [
  'system',
  'install',
  'package',
  'architectures',
  'mirror',
] as const;
export type DownloadNoteId = (typeof downloadNoteIds)[number];

export const faqIds = [
  'audience',
  'aiPrivacy',
  'copyAssistant',
  'permissions',
  'network',
  'multiDisplay',
  'intel',
  'storage',
] as const;
export type FaqId = (typeof faqIds)[number];

export const documentationIds = [
  'macos',
  'architecture',
  'cli',
  'releasing',
  'contributing',
] as const;
export type DocumentationId = (typeof documentationIds)[number];

export const documentationUrls: Record<DocumentationId, string> = {
  macos: 'https://github.com/wzz6423/zisla/blob/main/mac/README.md',
  architecture: 'https://github.com/wzz6423/zisla/blob/main/mac/Docs/architecture.md',
  cli: 'https://github.com/wzz6423/zisla/blob/main/mac/Docs/cli-reference.md',
  releasing: 'https://github.com/wzz6423/zisla/blob/main/mac/Docs/releasing.md',
  contributing: 'https://github.com/wzz6423/zisla/blob/main/CONTRIBUTING.md',
};

/** The four docs cards rendered in the developers grid, in order. */
export const documentationCardIds = documentationIds.slice(0, 4) as readonly DocumentationId[];

/**
 * Brand names stay in their original script in every locale; Doubao is the one
 * product with a widely used native name, so the label comes from the catalog.
 */
export const supportedAITools = (doubaoName: string): readonly string[] => [
  'Claude Code',
  'Codex',
  'ChatGPT',
  'Gemini',
  'Grok',
  'GitHub Copilot',
  'Kimi Code',
  'Qwen Code',
  'Qoder',
  'ZCode',
  'TRAE',
  'OpenCode',
  'Harnext',
  'WorkBuddy',
  doubaoName,
  'Pi',
  'Zed Agent',
];

export const repositoryLinks = {
  github: 'https://github.com/wzz6423/zisla',
  gitee: 'https://gitee.com/wzz6423/zisla',
};

export interface DownloadLink {
  platform: string;
  url: string;
}

export const downloadLinks: readonly DownloadLink[] = [
  { platform: 'GitHub', url: 'https://github.com/wzz6423/zisla/releases' },
  { platform: 'Gitee', url: 'https://gitee.com/wzz6423/zisla/releases' },
];

export const latestRelease = {
  version: 'v0.1.12',
  date: '2026-09-23',
  channel: 'Release',
  releasePage: 'https://github.com/wzz6423/zisla/releases/tag/v0.1.12',
  dmg: 'https://github.com/wzz6423/zisla/releases/download/v0.1.12/zisla-v0.1.12-macOS-arm64.dmg',
  zip: 'https://github.com/wzz6423/zisla/releases/download/v0.1.12/zisla-v0.1.12-macOS-arm64.zip',
  checksum: 'https://github.com/wzz6423/zisla/releases/download/v0.1.12/zisla-v0.1.12-macOS-arm64.zip.sha256',
  universalDmg: 'https://github.com/wzz6423/zisla/releases/download/v0.1.12/zisla-v0.1.12-macOS-universal.dmg',
  universalZip: 'https://github.com/wzz6423/zisla/releases/download/v0.1.12/zisla-v0.1.12-macOS-universal.zip',
  intelDmg: 'https://github.com/wzz6423/zisla/releases/download/v0.1.12/zisla-v0.1.12-macOS-x86_64.dmg',
  intelZip: 'https://github.com/wzz6423/zisla/releases/download/v0.1.12/zisla-v0.1.12-macOS-x86_64.zip',
  previewPage: 'https://github.com/wzz6423/zisla/releases/tag/v0.1.3-preview.1',
};

export interface ChangelogEntry {
  version: string;
  date: string;
  /** GitHub release 的 Highlights，统一以英文原文展示，不随界面语言切换。 */
  notes: readonly string[];
}

/**
 * 发版历史，倒序排列，首项即当前版本。notes 取自各版本 GitHub release 的 Highlights，
 * 统一以英文原文展示（11 版 × 17 语翻译不可维护）；v0.1.8/v0.1.0 无 Highlights 段，取其正文概述。
 */
export const changelogEntries: readonly ChangelogEntry[] = [
  {
    version: 'v0.1.12',
    date: '2026-09-23',
    notes: [
      'The island shows a compact low-battery notice and expands the shelf to accept browser file promises, local files, links, selected text, and dragged images with pixel-based previews.',
      'Clipboard actions now recognize addresses, flights, trains, parcels, phone numbers, meeting invitations, date ranges, timestamps, and conversions, with labels across all 17 supported languages.',
      'AirDrop transfers are grouped by batch while browser downloads keep separate progress cards, using a read-only private Sharing stream where available.',
      'Update checks choose the first mirror by public egress country and retry the other mirror once on failure.',
    ],
  },
  {
    version: 'v0.1.11',
    date: '2026-09-21',
    notes: [
      'Mail renders HTML content in the themed glass view, reads complete messages, and preserves inbox pagination.',
      'Mail links that open external destinations or new windows now follow the application external-link policy.',
      'Now Playing clears stale lyrics when switching to generic audio sources.',
      'Refined lock-screen, clipboard, and release metadata behavior.',
    ],
  },
  {
    version: 'v0.1.10',
    date: '2026-09-19',
    notes: [
      'Choose source formats before a video or audio download, with Douyin support and browser-cookie discovery across the available browsers.',
      'The copy assistant now recognizes live currency conversions, emoji names, locally installed app names, and more copied link types.',
      'Screenshot exports preserve window framing and keep in-progress text annotations.',
      'Update settings now include a direct GitHub feedback entry.',
    ],
  },
  {
    version: 'v0.1.9',
    date: '2026-09-12',
    notes: [
      'Added system metrics history with range-aware charts and export support.',
      'Added the lid-close animation and depth-based island transitions.',
      'Improved AI session and usage detection, including zcode turn progress and WorkBuddy sessions.',
      'Improved screenshot capture and editing, Quick Notes, Mail, media controls, and clipboard workflows.',
      'Vendored the zstd dependency and tightened release and update validation.',
    ],
  },
  {
    version: 'v0.1.8',
    date: '2026-09-06',
    notes: [
      'First release an installed copy can update to on its own: 0.1.7 introduced Sparkle, and 0.1.8 is the update it finds, verifies, and installs.',
      'Fixed Mail change detection by matching the lowercase com.apple.mail bundle id, and stopped the AI monitor trend chart from overlapping its title.',
    ],
  },
  {
    version: 'v0.1.7',
    date: '2026-09-05',
    notes: [
      'Automatic updates via Sparkle: each install follows the appcast for the architecture it was installed as, with the feed on Gitee plus a GitHub fallback, and both feed and update ZIP must pass EdDSA verification.',
      'Homebrew install --cask resolves the download per architecture, so Apple Silicon and Intel each get their own package instead of the universal build.',
      'Full interface localization across 19 language catalogs, with layouts refitted to the longer translations.',
      'The website is multilingual, redesigned, and published to GitHub Pages.',
      'The project is now licensed under PolyForm Noncommercial 1.0.0.',
    ],
  },
  {
    version: 'v0.1.6',
    date: '2026-08-26',
    notes: [
      'Adds the smart clipboard assistant and expands clipboard history workflows.',
      'Refines screenshot editing, AI-agent activity, voice processing, and system-status interactions.',
      'Strengthens release integrity, debug-build isolation, localization coverage, and regression tests.',
    ],
  },
  {
    version: 'v0.1.5',
    date: '2026-08-22',
    notes: [
      'Expanded AI monitoring and system tooling, including richer AI-agent and system-status surfaces.',
      'Refined system monitoring, cleanup presentation, window behavior, shortcuts, screenshot editing, and rich-note workflows.',
      'Added compatibility and regression coverage across the macOS application.',
    ],
  },
  {
    version: 'v0.1.4',
    date: '2026-08-20',
    notes: [
      'Adds a configurable screenshot workspace with region, window, and full-screen capture, plus annotation, pinning, scrolling capture, and image/table export.',
      'Adds the macOS Background Sounds catalog with asset download, playback lifecycle, and Settings integration.',
      'Extends the AI workspace with ZCode activity detection, DeepSeek and ZCode identities, and CLI management improvements.',
      'Improves voice input with system-dictation handling, configurable lexicons, and optional structured transcript formatting.',
      'Makes development, ad-hoc, and release signing modes explicit and adds targeted regression coverage.',
    ],
  },
  {
    version: 'v0.1.3',
    date: '2026-08-17',
    notes: [
      'Brings 13 configurable top-island modules together for media, files, clipboard, AI activity, downloads, agenda, mail, notes, PDF tools, system controls, battery details, and lock-screen workflows.',
      'Improves battery and system monitoring with health, power, Bluetooth, trusted Apple-device, memory, CPU, and per-fan metrics.',
      'Strengthens voice input with reliable transcript delivery, recording playback and history, optional retention, cleanup, and usage statistics.',
      'Streamlines AI workflows around privacy-conscious activity monitoring, zislactl, and CLI and Skills management.',
      'Refines shelf and clipboard interactions, browser download progress, focus notices, settings navigation, and multi-display behavior.',
    ],
  },
  {
    version: 'v0.1.0',
    date: '2026-07-25',
    notes: [
      'First public preview: a native, notch-aware macOS workspace built with SwiftUI and AppKit that expands only when it has something useful to show.',
      'Bundles Now Playing controls, file relay and sharing, secure video and audio downloads, weather, calendar, reminders, and Notes integration.',
      'Includes a privacy-conscious AI activity monitor that shows task progress and usage trends without reading prompt or response content, plus the zislactl hook.',
    ],
  },
] as const;

export const license = 'PolyForm Noncommercial 1.0.0';

export const runCommand = 'cd mac && swift run zisla';

/** Third-party tap: `wzz6423/homebrew-tap` is addressed as `wzz6423/tap`. */
export const brewInstallCommand = 'brew install --cask wzz6423/tap/zisla';

/** `{title}` is filled from the catalog so the sample task reads naturally. */
export const zislactlCommandTemplate =
  'zislactl update --id build --provider coder --title "{title}" --progress 62';

/* ===== Translated content contract ===== */

export interface ProofItem {
  title: string;
  desc: string;
}

export interface ShowcaseModuleCopy {
  name: string;
  caption: string;
  points: readonly [string, string, string];
}

export interface CrossModuleFeatureCopy {
  title: string;
  description: string;
  detail: string;
}

export interface FlowStepCopy {
  phase: string;
  title: string;
  desc: string;
}

export interface DownloadNoteCopy {
  term: string;
  value: string;
}

export interface FAQItemCopy {
  question: string;
  /** Authored markup; the permissions entry uses paragraphs and a list. */
  answer: string;
}

export interface DocumentationCopy {
  title: string;
  description: string;
}

export interface SiteContent {
  meta: {
    documentTitle: string;
    description: string;
    ogTitle: string;
    ogDescription: string;
  };
  tagline: string;
  header: {
    navAriaLabel: string;
    brandHomeAriaLabel: string;
    menuOpenLabel: string;
    menuCloseLabel: string;
    menuButtonTitle: string;
    navItems: Record<NavId, string>;
    downloadCta: string;
    downloadCtaAriaLabel: string;
    languageLabel: string;
  };
  hero: {
    eyebrow: string;
    /** Authored markup: `<br>` sets the line rhythm, `<em>` carries the payoff. */
    title: string;
    lede: string;
    downloadCta: string;
    downloadCtaAriaLabel: string;
    sourceCta: string;
    sourceCtaAriaLabel: string;
    hints: readonly [string, string, string];
  };
  proof: {
    ariaLabel: string;
    items: Record<ProofId, ProofItem>;
  };
  showcase: {
    eyebrow: string;
    /** Authored markup: the `<span>` half is tinted with the accent colour. */
    title: string;
    lede: string;
    ariaLabel: string;
    summaryMono: string;
    summaryLede: string;
    summaryNote: string;
    groupNames: Record<ShowcaseGroupKey, string>;
    groupCount: string;
    pointsAriaLabel: string;
    modules: Record<ShowcaseModuleId, ShowcaseModuleCopy>;
  };
  extensions: {
    eyebrow: string;
    title: string;
    lede: string;
    ariaLabel: string;
    summaryMono: string;
    summaryLede: string;
    summaryNote: string;
    features: Record<CrossModuleFeatureId, CrossModuleFeatureCopy>;
  };
  ai: {
    eyebrow: string;
    title: string;
    lede: string;
    summaryMono: string;
    summaryLede: string;
    summaryNote: string;
    toolsHeading: string;
    toolsLede: string;
    toolsAriaLabel: string;
    doubaoName: string;
    boundariesHeading: string;
    privacyPoints: readonly [string, string, string];
    bridgeHeading: string;
    bridgeLede: string;
    zislactlTaskTitle: string;
    copyZislactlAriaLabel: string;
  };
  flow: {
    eyebrow: string;
    title: string;
    lede: string;
    ariaLabel: string;
    summaryMono: string;
    summaryLede: string;
    summaryNote: string;
    steps: Record<FlowStepId, FlowStepCopy>;
  };
  download: {
    eyebrow: string;
    title: string;
    copy: string;
    primaryCta: string;
    primaryCtaAriaLabel: string;
    releaseCta: string;
    releaseCtaAriaLabel: string;
    brewMono: string;
    brewNote: string;
    copyBrewCommandAriaLabel: string;
    notes: Record<DownloadNoteId, DownloadNoteCopy>;
  };
  changelog: {
    eyebrow: string;
    title: string;
    lede: string;
    ariaLabel: string;
    releaseCountLabel: string;
    latestLabel: string;
    shippedLabel: string;
    latestBadge: string;
    noteLabel: string;
    pagerAriaLabel: string;
    pageLabel: string;
    prevPageLabel: string;
    nextPageLabel: string;
  };
  faq: {
    eyebrow: string;
    title: string;
    lede: string;
    items: Record<FaqId, FAQItemCopy>;
  };
  developers: {
    eyebrow: string;
    title: string;
    lede: string;
    docs: Record<DocumentationId, DocumentationCopy>;
    quickStartMono: string;
    quickStartHeading: string;
    copyRunCommandAriaLabel: string;
    githubRepoLabel: string;
    giteeRepoLabel: string;
    checksumLabel: string;
    performancePoints: readonly [string, string, string, string, string];
  };
  footer: {
    brandHomeAriaLabel: string;
    previewChannelLabel: string;
    tagline: string;
  };
  common: {
    copyCommandTitle: string;
    copiedAriaLabel: string;
  };
  toast: {
    runCommandCopied: string;
    zislactlCopied: string;
    brewCommandCopied: string;
  };
}

/** Replace `{token}` placeholders; used for the few count-dependent strings. */
export const format = (
  template: string,
  values: Readonly<Record<string, string | number>>,
): string =>
  template.replace(/\{(\w+)\}/g, (match, key: string) =>
    key in values ? String(values[key]) : match,
  );

/** Fetches the locale's catalog chunk; already resolved catalogs return instantly. */
export const loadSiteContent = loadCatalog;

/** Sync accessor for the locale already rendered; every render awaits its load first. */
export const getSiteContent = (locale: SiteLocale): SiteContent => {
  const catalog = loadedCatalog(locale);
  if (!catalog) throw new Error('语言包尚未加载：' + locale);
  return catalog;
};
