import {
  ArrowDownToLine,
  ArrowUpRight,
  Bot,
  Check,
  Code2,
  Copy,
  Download,
  ExternalLink,
  Image,
  Lock,
  Menu,
  Mic,
  Plus,
  Shield,
  Sparkles,
  Waves,
  X,
  createIcons,
} from 'lucide';
import {
  crossModuleFeatureIcons,
  crossModuleFeatureIds,
  documentationCardIds,
  documentationUrls,
  downloadLinks,
  downloadNoteIds,
  faqIds,
  flowStepIds,
  format,
  getSiteContent,
  latestRelease,
  license,
  loadSiteContent,
  navHrefs,
  navIds,
  repositoryLinks,
  runCommand,
  showcaseModuleGroups,
  supportedAITools,
  zislactlCommandTemplate,
} from './content';
import {
  defaultLocale,
  isSiteLocale,
  localeDirection,
  localeNativeNames,
  localeStorageKey,
  openGraphLocales,
  resolvePreferredLocale,
  siteLocales,
  type SiteLocale,
} from './locales';
import './styles.css';

const app = document.querySelector<HTMLDivElement>('#app');

if (!app) {
  throw new Error('找不到官网挂载节点');
}

const siteIcons = {
  ArrowDownToLine,
  ArrowUpRight,
  Bot,
  Check,
  Code2,
  Copy,
  Download,
  ExternalLink,
  Image,
  Lock,
  Menu,
  Mic,
  Plus,
  Shield,
  Sparkles,
  Waves,
  X,
};

const icon = (name: string, size = 16) =>
  '<i data-lucide="' + name + '" width="' + size + '" height="' + size + '" aria-hidden="true"></i>';

const escapeHtml = (value: string): string =>
  value.replace(
    /[&<>"']/g,
    (character) =>
      ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;',
      })[character] ?? character,
  );

const readInitialLocale = (): SiteLocale => {
  try {
    const stored = window.localStorage.getItem(localeStorageKey);
    if (isSiteLocale(stored)) return stored;
  } catch {
    // Storage can be unavailable in private or embedded browsing contexts.
  }

  const preferred =
    typeof navigator !== 'undefined' && navigator.languages?.length
      ? navigator.languages
      : typeof navigator !== 'undefined' && navigator.language
        ? [navigator.language]
        : [];
  return resolvePreferredLocale(preferred);
};

let currentLocale = readInitialLocale();
let revealObserver: IntersectionObserver | undefined;
let toastTimer: number | undefined;
const copyFeedbackTimers = new WeakMap<HTMLButtonElement, number>();
const progressBar = document.createElement('div');
progressBar.className = 'scroll-progress';
document.body.append(progressBar);

const setMetaContent = (
  selector: string,
  attributes: Readonly<Record<string, string>>,
  content: string,
) => {
  let element = document.head.querySelector<HTMLMetaElement>(selector);
  if (!element) {
    element = document.createElement('meta');
    Object.entries(attributes).forEach(([key, value]) => element?.setAttribute(key, value));
    document.head.append(element);
  }
  element.content = content;
};

const updateDocumentMetadata = (
  locale: SiteLocale,
  content: ReturnType<typeof getSiteContent>,
) => {
  document.documentElement.lang = locale;
  document.documentElement.dir = localeDirection(locale);
  document.documentElement.dataset.locale = locale;
  document.title = content.meta.documentTitle;
  setMetaContent('meta[name="description"]', { name: 'description' }, content.meta.description);
  setMetaContent('meta[property="og:title"]', { property: 'og:title' }, content.meta.ogTitle);
  setMetaContent(
    'meta[property="og:description"]',
    { property: 'og:description' },
    content.meta.ogDescription,
  );
  setMetaContent('meta[property="og:locale"]', { property: 'og:locale' }, openGraphLocales[locale]);
};

const getZislactlCommand = (content: ReturnType<typeof getSiteContent>) =>
  zislactlCommandTemplate.replace('{title}', content.ai.zislactlTaskTitle);

const setMenuOpen = (isOpen: boolean) => {
  const nav = document.querySelector<HTMLElement>('.nav');
  const menuToggle = document.querySelector<HTMLButtonElement>('.menu-toggle');
  const content = getSiteContent(currentLocale);

  nav?.classList.toggle('is-open', isOpen);
  document.body.classList.toggle('is-locked', isOpen);
  menuToggle?.setAttribute('aria-expanded', String(isOpen));
  if (!menuToggle) return;
  menuToggle.setAttribute(
    'aria-label',
    isOpen ? content.header.menuCloseLabel : content.header.menuOpenLabel,
  );
  menuToggle.title = isOpen ? content.header.menuCloseLabel : content.header.menuButtonTitle;
  menuToggle.innerHTML = icon(isOpen ? 'x' : 'menu', 18);
  createIcons({ icons: siteIcons });
};

const showToast = (message: string) => {
  const toast = document.querySelector<HTMLElement>('#toast');
  if (!toast) return;
  toast.textContent = message;
  toast.classList.add('is-visible');
  if (toastTimer) window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(
    () => document.querySelector<HTMLElement>('#toast')?.classList.remove('is-visible'),
    3600,
  );
};

const showCopyFeedback = (button: HTMLButtonElement | null) => {
  if (!button) return;
  const content = getSiteContent(currentLocale);
  const previousTimer = copyFeedbackTimers.get(button);
  if (previousTimer) window.clearTimeout(previousTimer);
  button.dataset.copyLabel ??= button.getAttribute('aria-label') ?? content.common.copyCommandTitle;
  button.classList.add('is-copied');
  button.setAttribute('aria-label', content.common.copiedAriaLabel);
  button.innerHTML = icon('check', 15);
  createIcons({ icons: siteIcons });

  const timer = window.setTimeout(() => {
    button.classList.remove('is-copied');
    button.setAttribute('aria-label', button.dataset.copyLabel ?? content.common.copyCommandTitle);
    button.innerHTML = icon('copy', 15);
    createIcons({ icons: siteIcons });
    copyFeedbackTimers.delete(button);
  }, 1600);
  copyFeedbackTimers.set(button, timer);
};

const copyText = async (text: string, message: string, button: HTMLButtonElement | null) => {
  let copied = false;
  try {
    await navigator.clipboard.writeText(text);
    copied = true;
  } catch {
    const input = document.createElement('textarea');
    input.value = text;
    input.setAttribute('readonly', 'true');
    input.style.position = 'fixed';
    input.style.opacity = '0';
    document.body.append(input);
    try {
      input.select();
      copied = document.execCommand('copy');
    } catch {
      copied = false;
    } finally {
      input.remove();
    }
  }
  if (copied) {
    showToast(message);
    showCopyFeedback(button);
  }
};

const bindReveals = () => {
  revealObserver?.disconnect();
  revealObserver = undefined;
  const revealItems = document.querySelectorAll<HTMLElement>('.reveal, .reveal-sequence');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reducedMotion) {
    document.documentElement.classList.remove('reveal-ready');
    revealItems.forEach((element) => element.classList.add('visible'));
    return;
  }

  document.documentElement.classList.add('reveal-ready');
  revealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting || entry.boundingClientRect.top < 0) {
          entry.target.classList.add('visible');
          revealObserver?.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.08, rootMargin: '0px 0px -60px 0px' },
  );
  window.requestAnimationFrame(() => {
    revealItems.forEach((element) => {
      if (element.getBoundingClientRect().top < window.innerHeight) {
        element.classList.add('visible');
      } else {
        revealObserver?.observe(element);
      }
    });
  });
};

const updateScrollProgress = () => {
  const scrollableHeight = document.documentElement.scrollHeight - window.innerHeight;
  const progress = scrollableHeight > 0 ? window.scrollY / scrollableHeight : 0;
  progressBar.style.transform = 'scaleX(' + Math.min(1, Math.max(0, progress)) + ')';
};

const renderSite = (locale: SiteLocale, preserveScroll = false) => {
  const content = getSiteContent(locale);
  const previousScroll = preserveScroll ? window.scrollY : 0;
  currentLocale = locale;
  updateDocumentMetadata(locale, content);

  const workflowMarkup = (['island', 'ai', 'daily', 'tools'] as const)
    .map((group, groupIndex) => {
      const modules = showcaseModuleGroups.filter((module) => module.group === group);
      const moduleMarkup = modules
        .map((module, moduleIndex) => {
          const copy = content.showcase.modules[module.id];
          return (
            '<article class="workflow-module reveal-step" style="--reveal-index: ' +
            (moduleIndex + 1) +
            '">' +
            '<span class="workflow-module-order">' +
            String(moduleIndex + 1).padStart(2, '0') +
            '</span>' +
            '<div class="workflow-module-copy"><h4>' +
            escapeHtml(copy.name) +
            '</h4><p>' +
            escapeHtml(copy.caption) +
            '</p><ul class="workflow-points" aria-label="' +
            escapeHtml(format(content.showcase.pointsAriaLabel, { name: copy.name })) +
            '">' +
            copy.points.map((point) => '<li>' + escapeHtml(point) + '</li>').join('') +
            '</ul></div></article>'
          );
        })
        .join('');
      return (
        '<section class="workflow-group reveal-sequence"><header class="workflow-group-head reveal-step" style="--reveal-index: 0">' +
        '<span class="workflow-group-order">' +
        String(groupIndex + 1).padStart(2, '0') +
        '</span><h3>' +
        escapeHtml(content.showcase.groupNames[group]) +
        '</h3><span class="workflow-group-count">' +
        escapeHtml(format(content.showcase.groupCount, { count: modules.length })) +
        '</span></header><div class="workflow-module-list">' +
        moduleMarkup +
        '</div></section>'
      );
    })
    .join('');

  const toolMarkup = supportedAITools(content.ai.doubaoName)
    .map((tool) => '<span class="tool-chip"><span class="tool-chip-dot"></span>' + escapeHtml(tool) + '</span>')
    .join('');

  const crossModuleMarkup = crossModuleFeatureIds
    .map((featureId, index) => {
      const feature = content.extensions.features[featureId];
      return (
        '<article class="extension-item reveal-step" style="--reveal-index: ' +
        index +
        '"><header class="extension-item-head"><span class="extension-item-order">' +
        String(index + 1).padStart(2, '0') +
        '</span><span class="extension-item-icon">' +
        icon(crossModuleFeatureIcons[featureId], 18) +
        '</span><h3>' +
        escapeHtml(feature.title) +
        '</h3></header><p>' +
        escapeHtml(feature.description) +
        '</p><span class="extension-item-detail">' +
        escapeHtml(feature.detail) +
        '</span></article>'
      );
    })
    .join('');

  const docsMarkup = documentationCardIds
    .map((docId, index) => {
      const doc = content.developers.docs[docId];
      return (
        '<a class="doc-link reveal-step" style="--reveal-index: ' +
        index +
        '" href="' +
        documentationUrls[docId] +
        '" target="_blank" rel="noreferrer"><span><span class="mono-label">' +
        escapeHtml(doc.title) +
        '</span><span class="doc-description">' +
        escapeHtml(doc.description) +
        '</span></span>' +
        icon('arrow-up-right', 16) +
        '</a>'
      );
    })
    .join('');

  const faqMarkup = faqIds
    .map((faqId) => {
      const item = content.faq.items[faqId];
      return (
        '<details class="faq-item reveal"><summary>' +
        escapeHtml(item.question) +
        icon('plus', 18) +
        '</summary><div class="faq-answer">' +
        item.answer +
        '</div></details>'
      );
    })
    .join('');

  const flowMarkup = flowStepIds
    .map((stepId, index) => {
      const step = content.flow.steps[stepId];
      return (
        '<li class="flow-step reveal-step" style="--reveal-index: ' +
        index +
        '"><span class="flow-step-number">' +
        String(index + 1).padStart(2, '0') +
        '</span><div><span class="flow-step-phase">' +
        escapeHtml(step.phase) +
        '</span><h3>' +
        escapeHtml(step.title) +
        '</h3><p>' +
        escapeHtml(step.desc) +
        '</p></div></li>'
      );
    })
    .join('');

  const languageOptions = siteLocales
    .map(
      (value) =>
        '<option value="' +
        escapeHtml(value) +
        '"' +
        (value === locale ? ' selected' : '') +
        '>' +
        escapeHtml(localeNativeNames[value]) +
        '</option>',
    )
    .join('');

  const zislactlCommand = getZislactlCommand(content);
  const renderDownloadNote = (noteId: (typeof downloadNoteIds)[number]) => {
    const note = content.download.notes[noteId];
    let value = escapeHtml(note.value);
    if (noteId === 'architectures') {
      value = '<a href="' + latestRelease.releasePage + '" target="_blank" rel="noreferrer">' + value + '</a>';
    } else if (noteId === 'mirror') {
      value =
        '<a href="' +
        (downloadLinks[1]?.url ?? repositoryLinks.gitee + '/releases') +
        '" target="_blank" rel="noreferrer">' +
        value +
        '</a>';
    }
    return '<div class="download-note"><dt>' + escapeHtml(note.term) + '</dt><dd>' + value + '</dd></div>';
  };

  const proofMarkup = (['modules', 'os', 'displays', 'local'] as const)
    .map((id, index) => {
      const item = content.proof.items[id];
      const title = id === 'modules' ? format(item.title, { count: showcaseModuleGroups.length }) : item.title;
      return (
        '<div class="proof-item reveal-step" style="--reveal-index: ' +
        index +
        '"><strong>' +
        escapeHtml(title) +
        '</strong><span>' +
        escapeHtml(item.desc) +
        '</span></div>'
      );
    })
    .join('');

  app.innerHTML =
    '<main><section class="hero" id="top"><header class="site-header">' +
    '<a class="brand" href="#top" aria-label="' +
    escapeHtml(content.header.brandHomeAriaLabel) +
    '"><img class="brand-mark" src="./assets/zisla-icon.png" alt="" /><span>zisla <span class="brand-subtitle">/ ' +
    escapeHtml(content.tagline) +
    '</span></span></a><button class="menu-toggle" type="button" aria-label="' +
    escapeHtml(content.header.menuOpenLabel) +
    '" aria-expanded="false" title="' +
    escapeHtml(content.header.menuButtonTitle) +
    '">' +
    icon('menu', 18) +
    '</button><nav class="nav" aria-label="' +
    escapeHtml(content.header.navAriaLabel) +
    '">' +
    navIds
      .map((id) => '<a class="nav-link" href="' + navHrefs[id] + '">' + escapeHtml(content.header.navItems[id]) + '</a>')
      .join('') +
    '<label class="language-picker"><span class="sr-only">' +
    escapeHtml(content.header.languageLabel) +
    '</span><select id="languageSelect" aria-label="' +
    escapeHtml(content.header.languageLabel) +
    '" dir="auto">' +
    languageOptions +
    '</select></label><a class="header-cta" href="#download" aria-label="' +
    escapeHtml(content.header.downloadCtaAriaLabel) +
    '">' +
    escapeHtml(content.header.downloadCta) +
    icon('arrow-down-to-line', 14) +
    '</a></nav></header><div class="section-wrap hero-inner"><div class="hero-copy"><p class="eyebrow">' +
    escapeHtml(content.hero.eyebrow) +
    '</p><h1 class="hero-title">' +
    content.hero.title +
    '</h1><p class="hero-lede">' +
    escapeHtml(content.hero.lede) +
    '</p><div class="hero-actions"><a class="button button-primary" href="' +
    latestRelease.dmg +
    '" download aria-label="' +
    escapeHtml(content.hero.downloadCtaAriaLabel) +
    '">' +
    icon('download', 16) +
    escapeHtml(content.hero.downloadCta) +
    '</a><a class="button button-ghost" href="' +
    repositoryLinks.github +
    '" target="_blank" rel="noreferrer" aria-label="' +
    escapeHtml(content.hero.sourceCtaAriaLabel) +
    '">' +
    icon('code-2', 15) +
    escapeHtml(content.hero.sourceCta) +
    '</a></div><ul class="hero-hints">' +
    content.hero.hints.map((hint) => '<li>' + icon('check', 13) + '<span>' + escapeHtml(hint) + '</span></li>').join('') +
    '</ul></div><div class="hero-identity" aria-hidden="true"><span class="hero-identity-rule"></span><img class="hero-identity-mark" src="./assets/zisla-icon.png" alt="" /><span class="hero-identity-caption">' +
    escapeHtml(content.hero.identityCaption) +
    '</span></div></div></section><section class="proof-band" aria-label="' +
    escapeHtml(content.proof.ariaLabel) +
    '"><div class="section-wrap proof-grid reveal-sequence">' +
    proofMarkup +
    '</div></section><section class="section" id="showcase"><div class="section-wrap"><div class="section-heading reveal"><div><p class="eyebrow">' +
    escapeHtml(content.showcase.eyebrow) +
    '</p><h2 class="section-title">' +
    content.showcase.title +
    '</h2></div><p class="section-lede">' +
    escapeHtml(content.showcase.lede) +
    '</p></div><div class="workflow-overview" aria-label="' +
    escapeHtml(content.showcase.ariaLabel) +
    '"><aside class="workflow-summary reveal"><span class="mono-label">' +
    escapeHtml(format(content.showcase.summaryMono, { modules: showcaseModuleGroups.length, groups: 4 })) +
    '</span><p>' +
    escapeHtml(content.showcase.summaryLede) +
    '</p><span>' +
    escapeHtml(format(content.showcase.summaryNote, { modules: showcaseModuleGroups.length, features: crossModuleFeatureIds.length })) +
    '</span></aside><div class="workflow-groups">' +
    workflowMarkup +
    '</div></div></div></section><section class="section extensions-section" id="capabilities"><div class="section-wrap"><div class="section-heading reveal"><div><p class="eyebrow">' +
    escapeHtml(content.extensions.eyebrow) +
    '</p><h2 class="section-title">' +
    content.extensions.title +
    '</h2></div><p class="section-lede">' +
    escapeHtml(content.extensions.lede) +
    '</p></div><div class="extension-overview" aria-label="' +
    escapeHtml(content.extensions.ariaLabel) +
    '"><aside class="extension-summary reveal"><span class="mono-label">' +
    escapeHtml(content.extensions.summaryMono) +
    '</span><p>' +
    escapeHtml(content.extensions.summaryLede) +
    '</p><span>' +
    escapeHtml(content.extensions.summaryNote) +
    '</span></aside><div class="extension-list reveal-sequence">' +
    crossModuleMarkup +
    '</div></div></div></section><section class="section ai-section" id="ai"><div class="section-wrap"><div class="section-heading reveal"><div><p class="eyebrow">' +
    escapeHtml(content.ai.eyebrow) +
    '</p><h2 class="section-title">' +
    content.ai.title +
    '</h2></div><p class="section-lede">' +
    escapeHtml(content.ai.lede) +
    '</p></div><div class="ai-overview"><aside class="ai-summary reveal"><span class="mono-label">' +
    escapeHtml(content.ai.summaryMono) +
    '</span><p>' +
    escapeHtml(content.ai.summaryLede) +
    '</p><span>' +
    escapeHtml(content.ai.summaryNote) +
    '</span></aside><div class="ai-detail-list reveal-sequence"><article class="ai-detail reveal-step" style="--reveal-index: 0"><span class="ai-detail-order">01</span><div><h3>' +
    escapeHtml(content.ai.toolsHeading) +
    '</h3><p>' +
    escapeHtml(content.ai.toolsLede) +
    '</p><div class="tool-list" aria-label="' +
    escapeHtml(content.ai.toolsAriaLabel) +
    '">' +
    toolMarkup +
    '</div></div></article><article class="ai-detail reveal-step" style="--reveal-index: 1"><span class="ai-detail-order">02</span><div><h3>' +
    escapeHtml(content.ai.boundariesHeading) +
    '</h3><ul class="privacy-list">' +
    content.ai.privacyPoints.map((point) => '<li>' + icon('shield', 15) + '<span>' + escapeHtml(point) + '</span></li>').join('') +
    '</ul></div></article><article class="ai-detail reveal-step" style="--reveal-index: 2"><span class="ai-detail-order">03</span><div><h3>' +
    escapeHtml(content.ai.bridgeHeading) +
    '</h3><p>' +
    escapeHtml(content.ai.bridgeLede) +
    '</p><div class="command-box"><code>' +
    escapeHtml(zislactlCommand) +
    '</code><button id="copyZislactl" type="button" aria-label="' +
    escapeHtml(content.ai.copyZislactlAriaLabel) +
    '" title="' +
    escapeHtml(content.common.copyCommandTitle) +
    '">' +
    icon('copy', 15) +
    '</button></div></div></article></div></div></div></section><section class="section flow-section" id="how-it-works"><div class="section-wrap"><div class="section-heading reveal"><div><p class="eyebrow">' +
    escapeHtml(content.flow.eyebrow) +
    '</p><h2 class="section-title">' +
    content.flow.title +
    '</h2></div><p class="section-lede">' +
    escapeHtml(content.flow.lede) +
    '</p></div><div class="flow-overview" aria-label="' +
    escapeHtml(content.flow.ariaLabel) +
    '"><aside class="flow-summary reveal"><span class="mono-label">' +
    escapeHtml(content.flow.summaryMono) +
    '</span><p>' +
    escapeHtml(content.flow.summaryLede) +
    '</p><span>' +
    escapeHtml(content.flow.summaryNote) +
    '</span></aside><ol class="flow-list reveal-sequence">' +
    flowMarkup +
    '</ol></div></div></section><section class="download-section" id="download"><div class="section-wrap download-layout reveal-sequence"><div class="download-copy-block reveal-step" style="--reveal-index: 0"><p class="eyebrow">' +
    escapeHtml(content.download.eyebrow) +
    '</p><h2 class="download-title">' +
    escapeHtml(content.download.title) +
    '</h2><p class="download-copy">' +
    escapeHtml(content.download.copy) +
    '</p><div class="download-actions"><a class="button button-light" href="' +
    latestRelease.dmg +
    '" download aria-label="' +
    escapeHtml(content.download.primaryCtaAriaLabel) +
    '">' +
    icon('download', 16) +
    escapeHtml(content.download.primaryCta) +
    '</a><a class="button button-ghost" href="' +
    latestRelease.releasePage +
    '" target="_blank" rel="noreferrer" aria-label="' +
    escapeHtml(content.download.releaseCtaAriaLabel) +
    '">' +
    icon('external-link', 16) +
    escapeHtml(content.download.releaseCta) +
    '</a></div></div><dl class="download-notes reveal-step" style="--reveal-index: 1">' +
    downloadNoteIds.map(renderDownloadNote).join('') +
    '</dl></div></section><section class="section faq-section" id="faq"><div class="section-wrap"><div class="section-heading reveal"><div><p class="eyebrow">' +
    escapeHtml(content.faq.eyebrow) +
    '</p><h2 class="section-title">' +
    escapeHtml(content.faq.title) +
    '</h2></div><p class="section-lede">' +
    escapeHtml(content.faq.lede) +
    '</p></div><div class="faq-list">' +
    faqMarkup +
    '</div></div></section><section class="section developers-section" id="developers"><div class="section-wrap"><div class="section-heading reveal"><div><p class="eyebrow">' +
    escapeHtml(content.developers.eyebrow) +
    '</p><h2 class="section-title">' +
    escapeHtml(content.developers.title) +
    '</h2></div><p class="section-lede">' +
    escapeHtml(content.developers.lede) +
    '</p></div><div class="docs-grid reveal-sequence">' +
    docsMarkup +
    '</div><div class="docs-detail reveal"><div><span class="mono-label">' +
    escapeHtml(content.developers.quickStartMono) +
    '</span><h3>' +
    escapeHtml(content.developers.quickStartHeading) +
    '</h3><div class="command-box"><code>' +
    escapeHtml(runCommand) +
    '</code><button id="copyCommand" type="button" aria-label="' +
    escapeHtml(content.developers.copyRunCommandAriaLabel) +
    '" title="' +
    escapeHtml(content.common.copyCommandTitle) +
    '">' +
    icon('copy', 15) +
    '</button></div><div class="developer-actions"><a href="' +
    repositoryLinks.github +
    '" target="_blank" rel="noreferrer">' +
    icon('code-2', 14) +
    escapeHtml(content.developers.githubRepoLabel) +
    '</a><a href="' +
    repositoryLinks.gitee +
    '" target="_blank" rel="noreferrer">' +
    icon('code-2', 14) +
    escapeHtml(content.developers.giteeRepoLabel) +
    '</a><a href="' +
    latestRelease.checksum +
    '" target="_blank" rel="noreferrer">' +
    icon('check', 14) +
    escapeHtml(content.developers.checksumLabel) +
    '</a></div></div><ul class="performance-list">' +
    content.developers.performancePoints.map((point) => '<li>' + icon('check', 14) + '<span>' + escapeHtml(point) + '</span></li>').join('') +
    '</ul></div></div></section></main><footer class="site-footer"><div class="section-wrap reveal-sequence"><div class="footer-top reveal-step" style="--reveal-index: 0"><a class="brand" href="#top" aria-label="' +
    escapeHtml(content.footer.brandHomeAriaLabel) +
    '"><img class="brand-mark" src="./assets/zisla-icon.png" alt="" /><span>zisla</span></a><div class="footer-links"><a href="' +
    repositoryLinks.github +
    '" target="_blank" rel="noreferrer">GitHub</a><a href="' +
    repositoryLinks.gitee +
    '" target="_blank" rel="noreferrer">Gitee</a><a href="' +
    latestRelease.previewPage +
    '" target="_blank" rel="noreferrer">' +
    escapeHtml(content.footer.previewChannelLabel) +
    '</a><a href="' +
    documentationUrls.contributing +
    '" target="_blank" rel="noreferrer">' +
    escapeHtml(content.developers.docs.contributing.title) +
    '</a></div></div><div class="footer-bottom reveal-step" style="--reveal-index: 1"><span>' +
    escapeHtml(content.footer.tagline) +
    '</span><span class="footer-meta">' +
    license +
    ' · ' +
    latestRelease.version +
    ' · macOS</span></div></div></footer><div class="toast" id="toast" role="status" aria-live="polite"></div>';

  createIcons({ icons: siteIcons });
  setMenuOpen(false);
  bindReveals();

  document.querySelector<HTMLButtonElement>('.menu-toggle')?.addEventListener('click', () => {
    const nav = document.querySelector<HTMLElement>('.nav');
    setMenuOpen(!(nav?.classList.contains('is-open') ?? false));
  });

  document.querySelector<HTMLSelectElement>('#languageSelect')?.addEventListener('change', (event) => {
    const value = (event.currentTarget as HTMLSelectElement).value;
    if (!isSiteLocale(value)) return;
    try {
      window.localStorage.setItem(localeStorageKey, value);
    } catch {
      // Keep the in-memory selection when persistence is unavailable.
    }
    void showLocale(value, true);
  });

  document.querySelectorAll<HTMLAnchorElement>('.nav a, .header-cta').forEach((link) => {
    link.addEventListener('click', () => setMenuOpen(false));
  });
  document.querySelector<HTMLButtonElement>('#copyCommand')?.addEventListener('click', (event) => {
    copyText(runCommand, content.toast.runCommandCopied, event.currentTarget as HTMLButtonElement);
  });
  document.querySelector<HTMLButtonElement>('#copyZislactl')?.addEventListener('click', (event) => {
    copyText(zislactlCommand, content.toast.zislactlCopied, event.currentTarget as HTMLButtonElement);
  });

  document.querySelectorAll<HTMLAnchorElement>('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener('click', (event) => {
      const href = anchor.getAttribute('href');
      if (!href || href === '#') return;
      const target = document.getElementById(href.substring(1));
      if (!target) return;
      event.preventDefault();
      const headerOffset =
        document.querySelector<HTMLElement>('.site-header')?.getBoundingClientRect().height ?? 82;
      const y = target.getBoundingClientRect().top + window.pageYOffset - headerOffset - 16;
      window.scrollTo({
        top: y,
        behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth',
      });
      setMenuOpen(false);
    });
  });

  updateScrollProgress();
  if (preserveScroll) {
    window.requestAnimationFrame(() => window.scrollTo({ top: previousScroll, behavior: 'auto' }));
  }
};

let pendingLocale: SiteLocale = currentLocale;

/** Renders `locale` once its catalog chunk resolved; on rapid switching the last request wins. */
const showLocale = async (locale: SiteLocale, preserveScroll = false) => {
  pendingLocale = locale;
  try {
    await loadSiteContent(locale);
  } catch (error) {
    if (pendingLocale !== locale) return;
    if (locale === defaultLocale) throw error;
    // A chunk that never arrives would leave the page blank, so fall back to the default catalog.
    await showLocale(defaultLocale, preserveScroll);
    return;
  }
  if (pendingLocale !== locale) return;
  renderSite(locale, preserveScroll);
};

window.addEventListener('scroll', updateScrollProgress, { passive: true });
window.addEventListener('resize', updateScrollProgress);
const desktopQuery = window.matchMedia('(min-width: 901px)');
desktopQuery.addEventListener?.('change', ({ matches }) => {
  if (matches) setMenuOpen(false);
});

void showLocale(currentLocale);
