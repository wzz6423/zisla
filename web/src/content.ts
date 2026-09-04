import { loadCatalog, loadedCatalog } from './i18n';
import type { SiteLocale } from './locales';

/* ===== Locale-independent structure =====
 * Ids and ordering live here so translations never have to repeat layout data,
 * and so grouping never depends on matching a translated string.
 */

export const navIds = ['showcase', 'ai', 'download', 'faq', 'developers'] as const;
export type NavId = (typeof navIds)[number];

export const navHrefs: Record<NavId, string> = {
  showcase: '#showcase',
  ai: '#ai',
  download: '#download',
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
  'capture',
  'voice',
  'media',
  'browserDownloads',
  'copyAssistant',
  'aiManagement',
  'pet',
  'lockScreen',
] as const;
export type CrossModuleFeatureId = (typeof crossModuleFeatureIds)[number];

export const crossModuleFeatureIcons: Record<CrossModuleFeatureId, string> = {
  capture: 'image',
  voice: 'mic',
  media: 'waves',
  browserDownloads: 'download',
  copyAssistant: 'copy',
  aiManagement: 'bot',
  pet: 'sparkles',
  lockScreen: 'lock',
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
  version: 'v0.1.6',
  channel: 'Release',
  releasePage: 'https://github.com/wzz6423/zisla/releases/tag/v0.1.6',
  dmg: 'https://github.com/wzz6423/zisla/releases/download/v0.1.6/zisla-v0.1.6-macOS-arm64.dmg',
  zip: 'https://github.com/wzz6423/zisla/releases/download/v0.1.6/zisla-v0.1.6-macOS-arm64.zip',
  checksum: 'https://github.com/wzz6423/zisla/releases/download/v0.1.6/zisla-v0.1.6-macOS-arm64.zip.sha256',
  universalDmg: 'https://github.com/wzz6423/zisla/releases/download/v0.1.6/zisla-v0.1.6-macOS-universal.dmg',
  universalZip: 'https://github.com/wzz6423/zisla/releases/download/v0.1.6/zisla-v0.1.6-macOS-universal.zip',
  intelDmg: 'https://github.com/wzz6423/zisla/releases/download/v0.1.6/zisla-v0.1.6-macOS-x86_64.dmg',
  intelZip: 'https://github.com/wzz6423/zisla/releases/download/v0.1.6/zisla-v0.1.6-macOS-x86_64.zip',
  previewPage: 'https://github.com/wzz6423/zisla/releases/tag/v0.1.3-preview.1',
};

export const license = 'MIT';

export const runCommand = 'cd mac && swift run zisla';

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
    identityCaption: string;
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
    notes: Record<DownloadNoteId, DownloadNoteCopy>;
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
