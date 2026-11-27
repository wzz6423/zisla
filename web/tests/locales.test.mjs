import assert from 'node:assert/strict';
import test from 'node:test';
import { existsSync, readFileSync } from 'node:fs';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import {
  defaultLocale,
  isSiteLocale,
  localeDirection,
  localeNativeNames,
  localeStorageKey,
  matchLocale,
  openGraphLocales,
  resolvePreferredLocale,
  siteLocales,
} from '../src/locales.ts';

// Catalog imports use Vite's extensionless resolution; keep the test on that same source path.
const sourceRoot = new URL('../src/', import.meta.url);
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith('.') && context.parentURL?.startsWith(sourceRoot.href)
      && !/\.[a-z]+$/i.test(specifier)) {
      for (const suffix of ['.ts', '/index.ts']) {
        const candidate = new URL(specifier + suffix, context.parentURL);
        if (existsSync(candidate)) return nextResolve(candidate.href, context);
      }
    }
    return nextResolve(specifier, context);
  },
});

const site = await import('../src/content.ts');
for (const locale of siteLocales) await site.loadSiteContent(locale);

const changedFeatureIds = [
  'floatingIsland', 'dailyBriefing', 'userCare', 'contextNotes', 'recording', 'permissions', 'pdf',
  'imageTools', 'audioTools', 'lockScreen',
];
const english = site.getSiteContent('en');
// Read authored overrides before createCatalog can silently merge missing fields from English.
const authoredCatalogs = new Map(siteLocales.map((locale) => {
  const source = readFileSync(new URL(`../src/i18n/${locale}.ts`, import.meta.url), 'utf8');
  const name = source.match(/export const (\w+)/)[1];
  const script = stripTypeScriptTypes(source).replace(/^import .*;$/gm, '').replace('export const', 'const');
  return [locale, vm.runInNewContext(`${script}\n${name}`, { createCatalog: (value) => value })];
}));
const escapedText = (value) => value.replace(/[&<>"']/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[character]));
const mainSource = readFileSync(new URL('../src/main.ts', import.meta.url), 'utf8');
const iconNames = mainSource.match(/const siteIcons = \{([\s\S]*?)\};/)[1].match(/\w+/g);
const renderSource = stripTypeScriptTypes(mainSource.slice(mainSource.indexOf('const app = ')))
  .replace('void showLocale(currentLocale);', '');

const renderInMemory = (locale, releases = site.changelogEntries, runtimeNodes = {}, options = {}) => {
  const classList = { add() {}, remove() {}, toggle() {} };
  const node = () => ({ style: {}, dataset: {}, classList, setAttribute(name, value) { this[name] = value; }, append() {} });
  const app = { ...node(), innerHTML: '' };
  const metadata = [];
  const document = {
    documentElement: { ...node(), dataset: { page: options.page }, scrollHeight: 800 },
    body: node(),
    head: { querySelector: () => null, append: (element) => metadata.push(element) },
    querySelector: (selector) => selector === '#app' ? app : runtimeNodes[selector] ?? null,
    querySelectorAll: (selector) => options.selectors?.[selector] ?? [],
    getElementById: (id) => options.targets?.[id] ?? null,
    createElement: node,
  };
  const navigations = [];
  const location = new URL(options.url ?? `https://example.test/zisla/${options.page === 'help' ? 'help.html' : ''}`);
  location.replace = (address) => navigations.push(new URL(address, location));
  const window = {
    location,
    history: {
      replaceState(_state, _title, address) { window.location = new URL(address, window.location); },
      pushState(_state, _title, address) { window.location = new URL(address, window.location); },
    },
    localStorage: { getItem: () => options.storedLocale ?? null, setItem(key, value) { this[key] = value; } },
    matchMedia: (query) => ({ matches: query.includes('reduced-motion'), addEventListener() {} }),
    addEventListener(event, listener) { options.windowHandlers?.set(event, listener); },
    dispatchEvent() {},
    innerHeight: 800,
    scrollY: 0,
    pageYOffset: 0,
    requestAnimationFrame(callback) { callback(); },
    scrollTo({ top }) { window.scrollY = top; },
  };
  const context = vm.createContext({
    ...site,
    defaultLocale, isSiteLocale, localeDirection, localeNativeNames, localeStorageKey,
    openGraphLocales, resolvePreferredLocale, siteLocales,
    changelogEntries: releases,
    document, window, navigator: { languages: [] }, Event, URL, URLSearchParams,
    ...Object.fromEntries(iconNames.map((name) => [name, {}])),
    createIcons() {},
  });
  vm.runInContext(renderSource, context);
  vm.runInContext(`renderSite(${JSON.stringify(locale)})`, context);
  return { html: app.innerHTML, document, metadata, window, context, navigations };
};

const renderHelpInMemory = (locale, releases = site.changelogEntries, runtimeNodes = {}, options = {}) =>
  renderInMemory(locale, releases, runtimeNodes, { ...options, page: 'help' });

const strings = (value, path) => {
  if (typeof value === 'string') return [[path, value]];
  return Object.entries(value).flatMap(([key, child]) => strings(child, `${path}.${key}`));
};

const updatedStrings = (content) => [
  ...changedFeatureIds.flatMap((id) => strings(content.extensions.features[id], `extensions.features.${id}`)),
  ...strings(content.showcase.modules.volumeMixer, 'showcase.modules.volumeMixer'),
  ...['aiMonitor', 'keyboardSound', 'mail', 'system', 'download', 'clipboard', 'quickNotes', 'shelf', 'agenda', 'toolbox', 'dashboard'].map((id) =>
    [`showcase.modules.${id}.caption`, content.showcase.modules[id].caption]),
  ...['shelf', 'aiMonitor', 'agenda'].flatMap((id) => strings(content.showcase.modules[id].points, `showcase.modules.${id}.points`)),
  ['showcase.modules.keyboardSound.points.2', content.showcase.modules.keyboardSound.points[2]],
  ...['windowPreviews', 'capture', 'pet'].flatMap((id) =>
    ['description', 'detail'].map((field) =>
      [`extensions.features.${id}.${field}`, content.extensions.features[id][field]])),
  ...['recording', 'permissions'].map((id) =>
    [`extensions.features.${id}.description`, content.extensions.features[id].description]),
  ...['copyAssistant', 'media', 'recommendedTools', 'voice', 'browserDownloads'].map((id) =>
    [`extensions.features.${id}.description`, content.extensions.features[id].description]),
  ['meta.description', content.meta.description],
  ['meta.ogDescription', content.meta.ogDescription],
  ['extensions.lede', content.extensions.lede],
  ...['eyebrow', 'title', 'lede', 'summaryMono', 'summaryLede', 'toolsLede', 'boundariesHeading', 'privacyPoints', 'bridgeLede']
    .flatMap((field) => strings(content.ai[field], `ai.${field}`)),
  ['flow.steps.trigger.desc', content.flow.steps.trigger.desc],
  ...strings(content.developers.performancePoints, 'developers.performancePoints'),
  ['download.copy', content.download.copy],
  ['faq.items.permissions.answer', content.faq.items.permissions.answer],
  ['faq.items.storage.answer', content.faq.items.storage.answer],
  ['faq.items.network.answer', content.faq.items.network.answer],
  ['faq.items.multiDisplay.answer', content.faq.items.multiDisplay.answer],
  ...strings(content.changelog.releaseNotes['v0.1.20'], 'changelog.releaseNotes.v0.1.20'),
  ...strings(content.changelog.releaseNotes['v0.1.21'], 'changelog.releaseNotes.v0.1.21'),
  ...strings(content.changelog.releaseNotes['v0.1.22'], 'changelog.releaseNotes.v0.1.22'),
  ...strings(content.changelog.releaseNotes['v0.1.23'], 'changelog.releaseNotes.v0.1.23'),
  ...strings(content.changelog.releaseNotes['v0.1.24'], 'changelog.releaseNotes.v0.1.24'),
  ...strings(content.changelog.releaseNotes['v0.1.25'], 'changelog.releaseNotes.v0.1.25'),
  ...strings(content.film, 'film'),
  ...strings(content.help, 'help'),
  ['header.navItems.help', content.header.navItems.help],
];

test('per-display modes are authored and rendered in every locale', () => {
  for (const locale of siteLocales) {
    const content = site.getSiteContent(locale);
    const description = authoredCatalogs.get(locale)?.extensions?.features?.floatingIsland?.description;
    const answer = authoredCatalogs.get(locale)?.faq?.items?.multiDisplay?.answer;
    assert.equal(description, content.extensions.features.floatingIsland.description, `${locale} feature fallback`);
    assert.equal(answer, content.faq.items.multiDisplay.answer, `${locale} FAQ fallback`);
    const faqHTML = renderInMemory(locale).html;
    assert.ok(faqHTML.includes(escapedText(answer)), `${locale} FAQ is rendered`);
    if (locale !== 'en') {
      assert.notEqual(description, english.extensions.features.floatingIsland.description, `${locale} copied English feature`);
      assert.notEqual(answer, english.faq.items.multiDisplay.answer, `${locale} copied English FAQ`);
    }
  }
  assert.match(english.faq.items.multiDisplay.answer, /Settings → General → Display Modes/);
  assert.match(english.faq.items.multiDisplay.answer, /Hide on This Display/);
  assert.match(english.faq.items.multiDisplay.answer, /With one screen.*hidden.*reconnecting restores/);
});

test('clipboard image text search is authored and rendered in every locale', () => {
  for (const locale of siteLocales) {
    const authored = authoredCatalogs.get(locale)?.showcase?.modules?.clipboard?.caption;
    assert.equal(typeof authored, 'string', `${locale} must author its clipboard caption`);
    const content = site.getSiteContent(locale);
    assert.equal(content.showcase.modules.clipboard.caption, authored);
    if (locale !== 'en') assert.notEqual(authored, english.showcase.modules.clipboard.caption);
    assert.ok(renderInMemory(locale).html.includes(escapedText(authored)), `${locale} must render its clipboard overview`);
    const authoredGuide = authoredCatalogs.get(locale)?.help?.guides?.clipboard;
    assert.ok(authoredGuide?.steps.length > 0, `${locale} must author its clipboard instructions`);
    const { html } = renderHelpInMemory(locale);
    for (const step of authoredGuide.steps) {
      assert.ok(html.includes(escapedText(step)), `${locale} must render its clipboard instructions`);
    }
  }
  assert.match(english.showcase.modules.clipboard.caption, /search local clipboard history, including text in images/);
  const instructions = english.help.guides.clipboard.steps.join(' ');
  assert.match(instructions, /on-device recognition.*search.*original image/);
  assert.match(instructions, /Right-click.*recognize or copy its text/);
});

test('launch film sits after the changelog and before the footer with explicit playback', () => {
  const content = site.getSiteContent('zh-Hans');
  const { html } = renderInMemory('zh-Hans');
  const film = html.match(/<section[^>]+id="film"[\s\S]*?<\/section>/)?.[0];
  assert.ok(film, 'inline film section is rendered');
  assert.ok(html.indexOf('id="changelog"') < html.indexOf('id="film"'));
  assert.ok(html.indexOf('id="film"') < html.indexOf('<footer'));
  const nav = html.match(/<nav class="nav"[^>]*>([\s\S]*?)<\/nav>/)?.[1];
  assert.ok(nav.indexOf('href="#film"') < nav.indexOf('href="#showcase"'));
  assert.ok(nav.includes(`<a class="nav-link" href="#film">${escapedText(content.film.title)}</a>`));
  assert.doesNotMatch(html.match(/<nav class="section-progress-nav"[\s\S]*?<\/nav>/)[0], /href="#film"/);
  const video = film.match(/<video\b[^>]*>/)?.[0];
  assert.ok(video, 'native video player is rendered');
  assert.match(video, /\scontrols(?:\s|>)/);
  assert.match(video, /\splaysinline(?:\s|>)/);
  assert.match(video, /preload="none"/);
  assert.match(video, /src="\.\/media\/zisla-launch-1080p60\.mp4"/);
  assert.match(video, /poster="\.\/media\/zisla-launch-poster\.webp"/);
  assert.match(video, /width="1920" height="1080"/);
  assert.ok(video.includes(`aria-label="${escapedText(content.film.videoAriaLabel)}"`));
  assert.doesNotMatch(video, /\s(?:autoplay|loop)(?:\s|=|>)/);
  assert.doesNotMatch(film, /<dialog\b|role="dialog"/);
  assert.ok(film.includes(`<a href="./media/zisla-launch-1080p60.mp4">${escapedText(content.film.openVideoLabel)}</a>`));
  assert.match(film, /id="filmError" hidden role="status"/);
  const links = [...film.matchAll(/\bhref="([^"]+)"/g)].map((match) => match[1]);
  assert.ok(links.some((href) => href === 'https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474'));
  assert.ok(links.some((href) => href === 'https://creativecommons.org/licenses/by/4.0/'));
  assert.ok(film.includes('Funkorama — Kevin MacLeod'));
});

test('a media error exposes the localized original-video link', () => {
  const handlers = new Map();
  const errorMessage = { hidden: true };
  renderInMemory('ar', site.changelogEntries, {
    '#launchFilm': { pause() {}, addEventListener: (event, listener) => handlers.set(event, listener) },
    '#filmError': errorMessage,
  });
  assert.equal(errorMessage.hidden, true, 'no error is shown before playback fails');
  assert.equal(typeof handlers.get('error'), 'function');
  handlers.get('error')();
  assert.equal(errorMessage.hidden, false, 'playback failure exposes the recovery link');
});

test('rendering another locale pauses the outgoing player', () => {
  const outgoing = { paused: false, pause() { this.paused = true; }, addEventListener() {} };
  renderInMemory('en', site.changelogEntries, { '#launchFilm': outgoing });
  assert.equal(outgoing.paused, true, 'language changes must not leave detached media playing');
});

test('a detached player error cannot affect the new locale', () => {
  const handlers = new Map();
  const outgoingError = { hidden: true };
  const currentError = { hidden: true };
  const runtimeNodes = {
    '#launchFilm': { pause() {}, addEventListener: (event, listener) => handlers.set(event, listener) },
    '#filmError': outgoingError,
  };
  renderInMemory('en', site.changelogEntries, runtimeNodes);
  runtimeNodes['#filmError'] = currentError;
  handlers.get('error')();
  assert.equal(outgoingError.hidden, false, 'the failure belongs to its original player');
  assert.equal(currentError.hidden, true, 'a fresh locale retains its own playback state');
});

test('every supported locale has its own name, Open Graph tag, and direction', () => {
  assert.equal(siteLocales.length, 17);
  assert.equal(new Set(siteLocales).size, siteLocales.length);
  assert.deepEqual(Object.keys(localeNativeNames).sort(), [...siteLocales].sort());
  assert.deepEqual(Object.keys(openGraphLocales).sort(), [...siteLocales].sort());
  for (const locale of siteLocales) {
    assert.ok(localeNativeNames[locale].length > 0, locale);
    assert.match(openGraphLocales[locale], /^[a-z]{2}_[A-Z]{2}$/, locale);
    assert.equal(localeDirection(locale), locale === 'ar' ? 'rtl' : 'ltr', locale);
    assert.equal(matchLocale(locale), locale);
  }
});

test('browser language tags normalize case, whitespace, and underscores', () => {
  for (const [tag, locale] of [[' EN_us ', 'en'], ['pt_PT', 'pt-BR'], ['in-ID', 'id'], ['fr-CA', 'fr']]) {
    assert.equal(matchLocale(tag), locale, tag);
  }
});

test('Chinese scripts take precedence over regional aliases', () => {
  for (const [tag, locale] of [
    ['zh-CN', 'zh-Hans'], ['zh-SG', 'zh-Hans'], ['zh-HK', 'zh-Hant'],
    ['zh-MO', 'zh-Hant'], ['zh-Hant-CN', 'zh-Hant'], ['zh-Hans-HK', 'zh-Hans'],
  ]) {
    assert.equal(matchLocale(tag), locale, tag);
  }
});

test('empty and unsupported browser tags have no match', () => {
  for (const tag of ['', ' ', 'xx-YY', 'not-a-language']) {
    assert.equal(matchLocale(tag), undefined, tag);
  }
});

test('browser preference order selects the first supported locale and preserves the input', () => {
  const preferred = Object.freeze(['xx-YY', 'fr-CA', 'en-US']);
  assert.equal(resolvePreferredLocale(preferred), 'fr');
  assert.deepEqual(preferred, ['xx-YY', 'fr-CA', 'en-US']);
  assert.equal(resolvePreferredLocale(), defaultLocale);
  assert.equal(resolvePreferredLocale(['xx-YY', '']), defaultLocale);
});

test('persisted locale values accept canonical supported identifiers only', () => {
  for (const locale of siteLocales) assert.equal(isSiteLocale(locale), true, locale);
  for (const value of [undefined, null, 17, {}, '', 'en-US', 'zh-CN', 'EN']) {
    assert.equal(isSiteLocale(value), false);
  }
});

test('website modules match macOS and standalone media tools live outside the carousel', () => {
  const settingsSource = readFileSync(new URL('../../mac/Sources/ZislaCore/FeatureSettings.swift', import.meta.url), 'utf8');
  const moduleOrder = settingsSource.slice(settingsSource.indexOf('public enum IslandModuleOrder'))
    .match(/public static let defaultOrder: \[Self\] = \[([\s\S]*?)\]/)?.[1];
  assert.ok(moduleOrder, 'macOS module order exists');
  const macModuleIds = [...moduleOrder.matchAll(/\.(\w+)/g)].map((match) => match[1]);
  assert.deepEqual([...site.showcaseModuleIds].sort(), macModuleIds.sort());
  assert.equal(site.showcaseModuleIds.length, 12);
  assert.deepEqual(site.showcaseModuleGroups.map(({ id }) => id).sort(), [...site.showcaseModuleIds].sort());
  assert.equal(new Set(site.crossModuleFeatureIds).size, site.crossModuleFeatureIds.length);
  for (const id of ['pdf', 'imageTools', 'audioTools']) {
    assert.ok(site.crossModuleFeatureIds.includes(id), `${id} has a standalone capability card`);
    assert.ok(!site.showcaseModuleIds.includes(id), `${id} is not an island module`);
  }
  assert.deepEqual(Object.keys(site.crossModuleFeatureIcons).sort(), [...site.crossModuleFeatureIds].sort());
});

test('image and audio capabilities describe the native operation counts and export requirements in every language', () => {
  const imageSource = readFileSync(new URL('../../mac/Sources/ZislaKit/ImageProcessingOptions.swift', import.meta.url), 'utf8');
  const audioSource = readFileSync(new URL('../../mac/Sources/ZislaKit/AudioProcessingModels.swift', import.meta.url), 'utf8');
  const imageEnum = imageSource.match(/public enum ImageToolOperation[^\{]*\{([\s\S]*?)public var id/)[1];
  const audioEnum = audioSource.match(/public enum AudioToolOperation[^\{]*\{([\s\S]*?)public var id/)[1];
  const imageCount = [...imageEnum.matchAll(/^\s*case (\w+)/gm)].length;
  const audioCount = [...audioEnum.matchAll(/^\s*case ([\w, ]+)/gm)].flatMap((match) => match[1].split(',')).length;
  assert.equal(imageCount, 9);
  assert.equal(audioCount, 27);
  assert.match(imageSource, /conversionFormats: \[Self\] = \[\.png, \.jpeg, \.webp, \.avif, \.jpegXL\]/);
  for (const locale of siteLocales) {
    const features = site.getSiteContent(locale).extensions.features;
    assert.ok(features.imageTools.detail.includes(String(imageCount)), `${locale}: native image tool count`);
    assert.ok(features.audioTools.detail.includes(String(audioCount)), `${locale}: native audio tool count`);
    for (const format of ['PNG', 'JPEG', 'WebP', 'AVIF', 'JPEG XL', 'ZIP']) {
      assert.ok(features.imageTools.description.includes(format), `${locale}: image export ${format}`);
    }
    for (const requirement of ['FFmpeg', 'ffprobe', 'LUFS']) {
      assert.ok(features.audioTools.description.includes(requirement), `${locale}: audio ${requirement}`);
    }
    assert.ok(features.capture.description.includes('HDR'), `${locale}: conditional HDR capture`);
    const ai = site.getSiteContent(locale).showcase.modules.aiMonitor.caption;
    for (const term of ['5h/7d', 'Cursor', '.xlsx']) assert.ok(ai.includes(term), `${locale}: AI ${term}`);
  }
});

test('current feature descriptions keep meeting, power and application-repair conditions explicit', () => {
  const content = site.getSiteContent('en');
  assert.match(content.showcase.modules.dashboard.caption, /AI work is grouped by application on Home/);
  assert.match(content.showcase.modules.agenda.caption, /Events with a meeting link.*10 minutes before the start.*one-click join/);
  assert.match(content.showcase.modules.agenda.caption, /Create a meeting note.*link and unlink existing context notes/);
  assert.match(content.showcase.modules.shelf.caption, /Search, select and share.*ZIP or PDF.*resize or convert images/);
  assert.match(content.showcase.modules.shelf.caption, /Quick Notes or the recording studio/);
  assert.match(content.showcase.modules.mail.caption, /one message or all inbox messages as read/);
  assert.match(content.showcase.modules.toolbox.caption, /Pause, resume or reset.*compact horizontal and vertical/);
  assert.match(content.showcase.modules.system.caption, /automatic power modes for plugged-in and battery use.*20% or below/);
  assert.match(content.showcase.modules.system.caption, /100% immediately when macOS offers it/);
  assert.match(content.extensions.features.copyAssistant.description, /integrity, signature and macOS security policy.*after the checks pass/);
  assert.match(content.extensions.features.capture.description, /slow automatic scrolling.*HDR screenshots on supported devices/);
  assert.match(content.extensions.features.floatingIsland.description, /Reorder.*Settings → Dynamic Island Layout/);
  assert.match(content.extensions.features.dailyBriefing.description, /real account allowances and their sampling times/);
  assert.match(content.ai.lede, /tasks by application.*model usage by date.*remaining account allowances/);
  assert.match(content.ai.privacyPoints[0], /Task status and usage stay on your Mac/);
  assert.match(content.ai.privacyPoints[1], /Prompts and replies are not read/);
  assert.match(content.ai.privacyPoints[2], /Conversations are not uploaded/);
  assert.match(content.help.guides.ai.permissions, /Allowance checks contact the provider/);
  assert.match(content.help.guides.ai.output, /provider samples, not token estimates.*unavailable data stays unavailable/);
  assert.doesNotMatch(content.showcase.modules.aiMonitor.caption, /remaining allowances hidden/);
  assert.match(content.showcase.modules.aiMonitor.caption, /Remaining-quota rings.*compact island layouts/);
  assert.match(content.showcase.modules.download.caption, /Settings → Dependency Components.*daily updates for installed components/);
  assert.match(content.extensions.features.floatingIsland.description, /priority of compact status information/);
  assert.match(content.extensions.features.voice.description, /System Monitor and Cleanup.*7, 15 or 30 days.*preserving transcripts.*off by default/);
  assert.match(content.extensions.features.browserDownloads.description, /actual target filename.*browser makes it available/);
  assert.match(content.extensions.features.copyAssistant.description, /Reorder actions for each recognised type.*Settings → Quick Actions/);
  assert.match(content.extensions.features.copyAssistant.description, /regional symbols and prefixed currency codes/);
  assert.match(content.faq.items.storage.answer, /independent folders for downloads, PDF tools, image tools, screenshots, recordings, Quick Actions and daily briefings/);
  assert.match(content.faq.items.network.answer, /AI account quota checks.*selected providers’ services/);
});

test('current release describes source grouping, cleanup, HDR and saved preferences', () => {
  assert.match(english.showcase.modules.clipboard.caption, /search local clipboard history.*text in images.*type or source app/);
  assert.match(english.showcase.modules.system.caption, /background.*island progress and results/);
  assert.match(english.showcase.modules.system.caption, /duplicate application installations.*leftovers/);
  assert.match(english.showcase.modules.quickNotes.caption, /Command-arrow.*native body typography/);
  assert.match(english.showcase.modules.volumeMixer.caption, /remembered per application.*stale audio sources/);
  assert.match(english.showcase.modules.aiMonitor.caption, /account regions independently.*daily usage records/i);
  assert.match(english.extensions.features.recording.description, /HDR on compatible devices.*media imports from the shelf/);
  assert.match(english.extensions.features.permissions.description, /status refreshes after access is granted/);
  assert.match(english.extensions.features.capture.description, /settings window/);
  assert.match(english.extensions.features.windowPreviews.description, /duplicate windows.*context menus/);
  assert.match(english.extensions.features.copyAssistant.description, /here-documents/);
  assert.match(english.faq.items.storage.answer, /Restore all save folders to their defaults/);
});

test('supported AI tools retain Cursor and Muse Code identities', () => {
  const tools = site.supportedAITools();
  assert.ok(tools.includes('Cursor'));
  assert.ok(tools.includes('Muse Code'));
  assert.equal(new Set(tools).size, tools.length);
});

for (const locale of siteLocales) {
  test(`${locale} loads and renders complete current features without English fallback`, () => {
    const content = site.getSiteContent(locale);
    assert.deepEqual(Object.keys(content.showcase.modules).sort(), [...site.showcaseModuleIds].sort());
    assert.deepEqual(Object.keys(content.extensions.features).sort(), [...site.crossModuleFeatureIds].sort());
    assert.match(content.extensions.features.recommendedTools.description, /Zshell/);
    assert.doesNotMatch(content.extensions.features.recommendedTools.description, /Quiet\.md/);
    const authored = new Map(strings(authoredCatalogs.get(locale), '').map(([path, value]) => [path.slice(1), value]));
    const baseline = new Map(updatedStrings(english));
    for (const [path, value] of updatedStrings(content)) {
      assert.equal(authored.get(path), value, `${locale}: ${path} must be authored without fallback`);
      assert.equal(typeof value, 'string', path);
      assert.ok(value.trim().length > 0, path);
      assert.doesNotMatch(value, /\bTODO\b|\bTBD\b/, path);
      assert.deepEqual(value.match(/\{\w+\}/g) ?? [], baseline.get(path).match(/\{\w+\}/g) ?? [], path);
      // "Privacy" is also the native heading in Italian and Dutch; authored-source checks still reject fallback.
      const sharedPrivacyHeading = path === 'ai.boundariesHeading' && ['it', 'nl'].includes(locale);
      if (locale !== 'en' && path !== 'showcase.modules.volumeMixer.points.2' && !sharedPrivacyHeading) {
        assert.notEqual(value, baseline.get(path), `${locale}: ${path} must have its own translation`);
      }
    }
    assert.equal(content.changelog.releaseNotes['v0.1.20'].length, 8);
    assert.equal(content.changelog.releaseNotes['v0.1.21'].length, 4);
    assert.equal(content.changelog.releaseNotes['v0.1.22'].length, 9);
    assert.equal(content.changelog.releaseNotes['v0.1.23'].length, 13);
    assert.equal(content.changelog.releaseNotes['v0.1.24'].length, 9);
    const rendered = renderInMemory(locale);
    const help = renderHelpInMemory(locale);
    for (const [path, value] of updatedStrings(content)) {
      if (path.startsWith('meta.')) continue;
      const expected = path.startsWith('faq.') || path === 'ai.title' ? value : escapedText(value);
      assert.ok((path.startsWith('help.') ? help.html : rendered.html).includes(expected), `${locale}: ${path} is rendered on its page`);
    }
    assert.equal((rendered.html.match(/class="workflow-module reveal-step"/g) ?? []).length, 12);
    assert.equal((rendered.html.match(/class="extension-item reveal-step"/g) ?? []).length, site.crossModuleFeatureIds.length);
    for (const id of changedFeatureIds) {
      const title = escapedText(content.extensions.features[id].title);
      assert.ok(rendered.html.includes(`<h3>${title}</h3>`), `${locale}: rendered ${id}`);
    }
    for (const id of ['imageTools', 'audioTools']) {
      const title = escapedText(content.extensions.features[id].title);
      const card = rendered.html.split('<article class="extension-item reveal-step"').find((part) =>
        part.slice(0, part.indexOf('</article>')).includes(`<h3>${title}</h3>`));
      assert.ok(card, `${locale}: standalone ${id} card`);
      assert.ok(card.slice(0, card.indexOf('</article>')).includes(`data-lucide="${id === 'imageTools' ? 'image' : 'waves'}"`),
        `${locale}: ${id} has its matching icon`);
    }
    assert.equal(rendered.document.documentElement.lang, locale);
    assert.equal(rendered.document.documentElement.dir, localeDirection(locale));
    assert.equal(rendered.document.title, content.meta.documentTitle);
    assert.ok(rendered.metadata.some(({ content: value }) => value === openGraphLocales[locale]));
    assert.ok(rendered.metadata.some(({ content: value }) => value === content.meta.description));
  });
}

test('release notes render by version while historical wording remains available', () => {
  const prepared = { version: 'v0.1.24', date: '2026-11-22', notes: ['ENGLISH FALLBACK SENTINEL'] };
  const historical = { version: 'v0.1.19', date: '2026-10-15', notes: ['HISTORICAL NOTE SENTINEL'] };
  const rendered = renderInMemory('zh-Hans', [prepared, historical]);
  for (const note of site.getSiteContent('zh-Hans').changelog.releaseNotes['v0.1.24']) {
    assert.ok(rendered.html.includes(note), 'prepared Chinese release note is rendered');
  }
  assert.ok(!rendered.html.includes('ENGLISH FALLBACK SENTINEL'));
  assert.ok(rendered.html.includes('HISTORICAL NOTE SENTINEL'), 'historical notes retain their original wording');
  const current = renderInMemory('zh-Hans', [historical]);
  assert.ok(!current.html.includes(site.getSiteContent('zh-Hans').changelog.releaseNotes['v0.1.24'][0]),
    'prepared notes do not replace the currently published release');
  const metadataOnly = renderInMemory('zh-Hans', [{ ...prepared, notes: [] }]);
  assert.ok(metadataOnly.html.includes(site.getSiteContent('zh-Hans').changelog.releaseNotes['v0.1.24'][0]),
    'a release entry can use its catalog notes without duplicating English source notes');
});


test('latest release downloads and README match the newest changelog entry', () => {
  const latest = site.changelogEntries[0];
  assert.equal(site.latestRelease.version, latest.version);
  assert.equal(site.latestRelease.date, latest.date);
  const releasePage = `https://github.com/wzz6423/zisla/releases/tag/${latest.version}`;
  const downloadRoot = `https://github.com/wzz6423/zisla/releases/download/${latest.version}/`;
  assert.equal(site.latestRelease.releasePage, releasePage);
  for (const key of ['dmg', 'zip', 'checksum', 'universalDmg', 'universalZip', 'intelDmg', 'intelZip']) {
    const url = site.latestRelease[key];
    assert.ok(url.startsWith(downloadRoot), key);
    const architecture = key.startsWith('universal') ? 'universal' : key.startsWith('intel') ? 'x86_64' : 'arm64';
    const extension = key === 'checksum' ? 'zip.sha256' : key.toLowerCase().endsWith('zip') ? 'zip' : 'dmg';
    assert.equal(url, `${downloadRoot}zisla-${latest.version}-macOS-${architecture}.${extension}`, key);
  }
  for (const filename of ['README.md', 'README.zh-CN.md']) {
    const readme = readFileSync(new URL(`../${filename}`, import.meta.url), 'utf8');
    assert.ok(readme.includes(releasePage), `${filename} includes the release page`);
    for (const key of ['dmg', 'zip', 'universalDmg', 'universalZip', 'intelDmg', 'intelZip']) {
      assert.ok(readme.includes(site.latestRelease[key]), `${filename} includes ${key}`);
    }
    for (const url of readme.match(/https:\/\/github\.com\/wzz6423\/zisla\/releases\/(?:tag|download)\/v[^\s]+/g)) {
      assert.ok(url.startsWith(releasePage) || url.startsWith(downloadRoot), `${filename}: ${url}`);
    }
  }
});

test('help languages mirror the native AppLanguage values', () => {
  const source = readFileSync(new URL('../../mac/Sources/ZislaCore/AppLocalization.swift', import.meta.url), 'utf8');
  const declaration = source.slice(source.indexOf('public enum AppLanguage'), source.indexOf('public var', source.indexOf('public enum AppLanguage')));
  const values = [...declaration.matchAll(/case \w+ = "([^"]+)"/g)].map((match) => match[1]);
  assert.deepEqual(values.sort(), [...siteLocales].sort());
});

test('the homepage stays concise while linked help retains translated guides and demonstrations', () => {
  for (const locale of siteLocales) {
    const content = site.getSiteContent(locale);
    const homepage = renderInMemory(locale);
    assert.ok(homepage.html.includes(`href="./help.html?lang=${locale}">${escapedText(content.header.navItems.help)}</a>`), locale);
    assert.doesNotMatch(homepage.html, /class="user-guide|class="workflow-video|id="help"/);
    const { html, document, metadata } = renderHelpInMemory(locale);
    assert.doesNotMatch(html, /class="hero"|id="showcase"|id="changelog"/);
    assert.ok(html.includes(`href="./?lang=${locale}"`), `${locale}: help returns home`);
    for (const markup of [homepage.html, html]) {
      const footer = markup.match(/<footer\b[\s\S]*?<\/footer>/)?.[0];
      assert.ok(footer?.includes(`<a href="./help.html?lang=${locale}">${escapedText(content.header.navItems.help)}</a>`),
        `${locale}: both footers link to localized user help`);
    }
    for (const id of site.guideIds) {
      const guide = content.help.guides[id];
      assert.ok(guide.steps.length > 0, `${locale}: ${id} has actionable steps`);
      assert.ok(html.includes(`id="guide-${id}"`), `${locale}: ${id} has a stable destination`);
      assert.ok(html.includes(`href="#guide-${id}"`), `${locale}: ${id} is reachable`);
    }
    for (const id of site.workflowIds) {
      const { start, end, guide } = site.workflowExcerpts[id];
      assert.ok(start >= 0 && end > start && end <= 160, id);
      assert.ok(html.includes(`id="workflow-${id}"`), `${locale}: workflow destination`);
      assert.ok(html.includes(`src="${site.launchFilmMedia.video}#t=${start},${end}"`), `${locale}: inline excerpt`);
      assert.ok(html.includes(`href="#guide-${guide}"`), `${locale}: workflow has instructions`);
    }
    assert.equal((html.match(/class="workflow-video" controls playsinline preload="none"/g) ?? []).length, site.workflowIds.length);
    assert.equal(document.documentElement.lang, locale);
    assert.equal(document.documentElement.dir, locale === 'ar' ? 'rtl' : 'ltr');
    assert.ok(metadata.some((entry) => entry.content === openGraphLocales[locale]));
  }
});

test('developer resources select complete documents in the chosen locale', () => {
  for (const locale of siteLocales) {
    const { html } = renderInMemory(locale);
    for (const id of site.documentationIds) {
      const link = site.documentationLink(id, locale);
      assert.equal(link.language, locale, `${locale}: document language`);
      const sourcePath = link.url.split('/blob/main/')[1];
      const original = site.documentationUrls[id].split('/blob/main/')[1];
      const expected = locale === 'en' ? original : locale === 'zh-Hans' ? original.replace(/\.md$/, '.zh-CN.md') :
        `docs/locales/${locale}/${original}`;
      assert.equal(sourcePath, expected, `${locale}: localized resource path`);
      assert.ok(existsSync(new URL(`../../${sourcePath}`, import.meta.url)), `${locale}: ${sourcePath} exists`);
      assert.ok(html.includes(`href="${link.url}"`), `${locale}: resource links to ${sourcePath}`);
    }
  }
});

const localizedDocuments = [
  'README.md', 'mac/README.md', 'mac/Docs/architecture.md',
  'mac/Docs/cli-reference.md', 'mac/Docs/releasing.md', 'CONTRIBUTING.md',
];
const fencedExamples = (markdown) => [...markdown.matchAll(/^[ \t]*```[^\n]*\n[\s\S]*?^[ \t]*```[ \t]*$/gm)].map((match) => match[0]);
const proseOnly = (markdown) => markdown.replace(/^[ \t]*```[^\n]*\n[\s\S]*?^[ \t]*```[ \t]*$/gm, '');
const markdownAnchors = (markdown) => {
  const anchors = new Set();
  const repeats = new Map();
  for (const match of proseOnly(markdown).matchAll(/^#{1,6} (.+)$/gm)) {
    const slug = match[1].replace(/<[^>]*>/g, '').replace(/[^\p{L}\p{N}\p{M}_\-\s]/gu, '')
      .trim().toLowerCase().replace(/\s/g, '-');
    const count = repeats.get(slug) ?? 0;
    repeats.set(slug, count + 1);
    anchors.add(count ? `${slug}-${count}` : slug);
  }
  return anchors;
};

test('all 17 documentation sets retain executable examples and local navigation', () => {
  const index = new URL('../../docs/locales/README.md', import.meta.url);
  const indexText = readFileSync(index, 'utf8');
  const documents = [index];
  for (const locale of siteLocales) {
    for (const path of localizedDocuments) {
      const source = new URL(`../../${path}`, import.meta.url);
      const localized = new URL(`../../${locale === 'en' ? path : locale === 'zh-Hans' ? path.replace(/\.md$/, '.zh-CN.md') :
        `docs/locales/${locale}/${path}`}`, import.meta.url);
      assert.ok(existsSync(localized), `${locale}: ${path} exists`);
      const markdown = readFileSync(localized, 'utf8');
      assert.ok(/^# .+/m.test(markdown) && /^## .+/m.test(markdown), `${locale}: ${path} has full document sections`);
      assert.equal((markdown.match(/^[ \t]*```/gm) ?? []).length, fencedExamples(markdown).length * 2,
        `${locale}: ${path} has closed code fences`);
      const indexedPath = locale === 'en' ? `../../${path}` : locale === 'zh-Hans' ?
        `../../${path.replace(/\.md$/, '.zh-CN.md')}` : `${locale}/${path}`;
      assert.ok(indexText.includes(indexedPath), `${locale}: ${path} is indexed`);
      if (locale !== 'en' && locale !== 'zh-Hans') {
        const englishMarkdown = readFileSync(source, 'utf8');
        assert.notEqual(proseOnly(markdown), proseOnly(englishMarkdown), `${locale}: ${path} contains authored translated prose`);
        assert.deepEqual(fencedExamples(markdown), fencedExamples(englishMarkdown), `${locale}: ${path} preserves executable examples`);
      }
      documents.push(localized);
    }
  }
  for (const document of documents) {
    for (const match of proseOnly(readFileSync(document, 'utf8')).matchAll(/!?\[[^\]]*\]\(([^\s)]+)(?:\s+[^)]*)?\)/g)) {
      if (/^[a-z][a-z0-9+.-]*:/i.test(match[1])) continue;
      const target = new URL(match[1], document);
      const hash = decodeURIComponent(target.hash.slice(1));
      target.hash = '';
      assert.ok(existsSync(target), `${document.pathname}: ${match[1]} exists`);
      if (hash && target.pathname.endsWith('.md')) {
        assert.ok(markdownAnchors(readFileSync(target, 'utf8')).has(hash), `${document.pathname}: ${match[1]} anchor exists`);
      }
    }
  }
});

test('explicit language links override saved preferences while invalid values leave preferences intact', () => {
  for (const locale of siteLocales) {
    const page = renderInMemory(locale, site.changelogEntries, {}, {
      url: `https://example.test/zisla/?lang=${locale}#guide-clipboard`, storedLocale: 'en',
    });
    assert.equal(vm.runInContext('readInitialLocale()', page.context), locale);
  }
  for (const value of ['xx', 'en-US', '<script>', 'javascript:alert(1)', '']) {
    const page = renderInMemory('fr', site.changelogEntries, {}, {
      url: `https://example.test/zisla/?lang=${encodeURIComponent(value)}#help`, storedLocale: 'fr',
    });
    assert.equal(vm.runInContext('readInitialLocale()', page.context), 'fr', value);
  }
  const page = renderInMemory('zh-Hans', site.changelogEntries, {}, { storedLocale: 'invalid' });
  assert.equal(vm.runInContext('readInitialLocale()', page.context), defaultLocale);
});

test('legacy homepage help links forward with language, query and destination intact', () => {
  for (const locale of siteLocales) {
    for (const destination of ['help', ...site.guideIds.map((id) => 'guide-' + id), ...site.workflowIds.map((id) => 'workflow-' + id)]) {
      const page = renderInMemory('en', site.changelogEntries, {}, {
        url: `https://example.test/zisla/?campaign=help&lang=${locale}#${destination}`, storedLocale: 'en',
      });
      assert.equal(page.navigations.length, 1);
      const url = page.navigations[0];
      assert.equal(url.pathname, '/zisla/help.html');
      assert.equal(url.searchParams.get('lang'), locale);
      assert.equal(url.searchParams.get('campaign'), 'help');
      assert.equal(url.hash, '#' + destination);
    }
  }
  for (const destination of ['showcase', 'film', 'guide-unknown', '%3Cimg%20onerror=alert(1)%3E']) {
    const page = renderInMemory('en', site.changelogEntries, {}, { url: `https://example.test/zisla/#${destination}` });
    assert.equal(page.navigations.length, 0, destination);
  }
  for (const search of ['', '?lang=xx&campaign=help']) {
    const page = renderInMemory('en', site.changelogEntries, {}, {
      url: `https://example.test/zisla/${search}#guide-shelf`, storedLocale: 'fr',
    });
    assert.equal(page.navigations[0].searchParams.get('lang'), 'fr', 'saved language applies to old links without a supported language');
    assert.equal(page.navigations[0].searchParams.get('campaign'), search ? 'help' : null);
  }
  const handlers = new Map();
  const page = renderInMemory('en', site.changelogEntries, {}, { windowHandlers: handlers });
  page.window.location.hash = '#guide-shelf';
  handlers.get('hashchange')();
  assert.equal(page.navigations[0].hash, '#guide-shelf');
});

test('help metadata and cross-page links retain locale and safely encode the query', () => {
  for (const locale of siteLocales) {
    const page = renderHelpInMemory(locale);
    const content = site.getSiteContent(locale);
    assert.equal(page.document.title, content.help.title + ' · zisla');
    assert.ok(page.metadata.some((entry) => entry.name === 'description' && entry.content === content.help.lede));
    assert.ok(page.metadata.some((entry) => entry.property === 'og:title' && entry.content === page.document.title));
    assert.ok(page.metadata.some((entry) => entry.property === 'og:description' && entry.content === content.help.lede));
    assert.equal(page.document.documentElement.dir, localeDirection(locale));
  }
  const page = renderInMemory('ar', site.changelogEntries, {}, {
    url: 'https://example.test/zisla/?campaign=sample&lang=ar&source=docs',
  });
  assert.ok(page.html.includes('href="./help.html?campaign=sample&amp;lang=ar&amp;source=docs"'));
  const help = renderHelpInMemory('ar', site.changelogEntries, {}, {
    url: 'https://example.test/zisla/help.html?campaign=sample&lang=ar&source=docs#guide-ai',
  });
  assert.ok(help.html.includes('href="./?campaign=sample&amp;lang=ar&amp;source=docs#showcase"'));
  assert.ok(help.html.includes('class="header-cta" href="./?campaign=sample&amp;lang=ar&amp;source=docs#download"'));
  for (const markup of [page.html, help.html]) {
    const footer = markup.match(/<footer\b[\s\S]*?<\/footer>/)?.[0];
    assert.ok(footer?.includes(`<a href="./help.html?campaign=sample&amp;lang=ar&amp;source=docs">${escapedText(site.getSiteContent('ar').header.navItems.help)}</a>`),
      'footer help keeps the selected language and query on both pages');
  }
  assert.equal(help.navigations.length, 0, 'the help page must not redirect itself');
});

test('initial guide deep links reach the selected section without interpreting arbitrary hash markup', () => {
  let visits = 0;
  const target = { scrollIntoView() { visits++; } };
  const page = renderHelpInMemory('ar', site.changelogEntries, {}, {
    url: 'https://example.test/zisla/help.html?lang=ar#guide-meeting', targets: { 'guide-meeting': target },
  });
  assert.equal(visits, 1);
  assert.equal(page.document.documentElement.dir, 'rtl');
  assert.doesNotThrow(() => renderInMemory('en', site.changelogEntries, {}, {
    url: 'https://example.test/zisla/#%3Cimg%20onerror=alert(1)%3E',
  }));
});

test('language switching preserves the guide and query, and help navigation retains the locale', async () => {
  const handlers = new Map();
  const control = { addEventListener(event, handler) { handlers.set(event, handler); } };
  const anchor = { getAttribute: () => '#guide-ai', addEventListener(event, handler) { handlers.set('anchor-' + event, handler); } };
  const target = { getBoundingClientRect: () => ({ top: 400 }), scrollIntoView() {} };
  const page = renderHelpInMemory('en', site.changelogEntries, { '#languageSelect': control }, {
    url: 'https://example.test/zisla/help.html?campaign=guide&lang=en#guide-clipboard',
    selectors: { 'a[href^="#"]': [anchor] }, targets: { 'guide-ai': target },
  });
  handlers.get('change')({ currentTarget: { value: 'ar' } });
  await vm.runInContext('showLocale("ar", true)', page.context);
  assert.equal(page.window.location.searchParams.get('lang'), 'ar');
  assert.equal(page.window.location.searchParams.get('campaign'), 'guide');
  assert.equal(page.window.location.hash, '#guide-clipboard');
  assert.equal(page.document.documentElement.lang, 'ar');
  const before = page.window.location.href;
  handlers.get('change')({ currentTarget: { value: 'javascript:alert(1)' } });
  assert.equal(page.window.location.href, before);
  let prevented = false;
  handlers.get('anchor-click')({ preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
  assert.equal(page.window.location.hash, '#guide-ai');
  assert.equal(page.window.location.searchParams.get('lang'), 'ar');
  assert.equal(page.window.location.searchParams.get('campaign'), 'guide');
  assert.equal(page.window.scrollY, 302);
});

test('browser back restores the language and help destination from its URL', async () => {
  const handlers = new Map();
  const visits = [];
  const targets = Object.fromEntries(['guide-clipboard', 'guide-meeting'].map((id) => [id, {
    scrollIntoView() { visits.push(id); },
  }]));
  const page = renderHelpInMemory('en', site.changelogEntries, {}, {
    url: 'https://example.test/zisla/help.html?lang=en#guide-clipboard', targets, windowHandlers: handlers,
  });
  page.window.location = new URL('https://example.test/zisla/help.html?lang=ja#guide-meeting');
  await handlers.get('popstate')();
  assert.equal(page.document.documentElement.lang, 'ja');
  assert.equal(visits.at(-1), 'guide-meeting');
  page.window.location = new URL('https://example.test/zisla/help.html?lang=en#guide-clipboard');
  await handlers.get('popstate')();
  assert.equal(page.document.documentElement.lang, 'en');
  assert.equal(visits.at(-1), 'guide-clipboard');
});

test('guide content is escaped as text and cannot inject markup or URL attributes', () => {
  const content = site.getSiteContent('en');
  const original = content.help.guides.clipboard;
  const payload = '<img src=x onerror="alert(1)"><a href="javascript:alert(1)">unsafe</a>';
  try {
    content.help.guides.clipboard = {
      title: payload, summary: payload, entry: payload, steps: [payload], shortcuts: payload,
      permissions: payload, output: payload,
    };
    const { html: help } = renderHelpInMemory('en');
    assert.ok(help.includes(escapedText(payload)));
    assert.doesNotMatch(help, /<img src=x|href="javascript:/);
    assert.ok(help.includes('id="guide-clipboard"'), 'untrusted copy cannot replace the stable id');
  } finally {
    content.help.guides.clipboard = original;
  }
});
