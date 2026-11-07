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

const renderInMemory = (locale, releases = site.changelogEntries) => {
  const classList = { add() {}, remove() {}, toggle() {} };
  const node = () => ({ style: {}, dataset: {}, classList, setAttribute() {}, append() {} });
  const app = { ...node(), innerHTML: '' };
  const metadata = [];
  const document = {
    documentElement: { ...node(), scrollHeight: 800 },
    body: node(),
    head: { querySelector: () => null, append: (element) => metadata.push(element) },
    querySelector: (selector) => selector === '#app' ? app : null,
    querySelectorAll: () => [],
    getElementById: () => null,
    createElement: node,
  };
  const window = {
    localStorage: { getItem: () => null },
    matchMedia: (query) => ({ matches: query.includes('reduced-motion'), addEventListener() {} }),
    addEventListener() {},
    dispatchEvent() {},
    innerHeight: 800,
    scrollY: 0,
  };
  const context = vm.createContext({
    ...site,
    defaultLocale, isSiteLocale, localeDirection, localeNativeNames,
    openGraphLocales, resolvePreferredLocale, siteLocales,
    changelogEntries: releases,
    document, window, navigator: { languages: [] }, Event,
    ...Object.fromEntries(iconNames.map((name) => [name, {}])),
    createIcons() {},
  });
  vm.runInContext(renderSource, context);
  vm.runInContext(`renderSite(${JSON.stringify(locale)})`, context);
  return { html: app.innerHTML, document, metadata };
};

const strings = (value, path) => {
  if (typeof value === 'string') return [[path, value]];
  return Object.entries(value).flatMap(([key, child]) => strings(child, `${path}.${key}`));
};

const updatedStrings = (content) => [
  ...changedFeatureIds.flatMap((id) => strings(content.extensions.features[id], `extensions.features.${id}`)),
  ...strings(content.showcase.modules.volumeMixer, 'showcase.modules.volumeMixer'),
  ...['aiMonitor', 'keyboardSound', 'mail', 'system', 'download', 'clipboard', 'quickNotes'].map((id) =>
    [`showcase.modules.${id}.caption`, content.showcase.modules[id].caption]),
  ['showcase.modules.keyboardSound.points.2', content.showcase.modules.keyboardSound.points[2]],
  ...['windowPreviews', 'capture', 'pet'].flatMap((id) =>
    ['description', 'detail'].map((field) =>
      [`extensions.features.${id}.${field}`, content.extensions.features[id][field]])),
  ...['copyAssistant', 'media', 'recommendedTools'].map((id) =>
    [`extensions.features.${id}.description`, content.extensions.features[id].description]),
  ['meta.description', content.meta.description],
  ['meta.ogDescription', content.meta.ogDescription],
  ['download.copy', content.download.copy],
  ['faq.items.permissions.answer', content.faq.items.permissions.answer],
  ['faq.items.storage.answer', content.faq.items.storage.answer],
  ...strings(content.changelog.releaseNotes['v0.1.20'], 'changelog.releaseNotes.v0.1.20'),
  ...strings(content.changelog.releaseNotes['v0.1.21'], 'changelog.releaseNotes.v0.1.21'),
  ...strings(content.changelog.releaseNotes['v0.1.22'], 'changelog.releaseNotes.v0.1.22'),
];

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

test('website modules match the current macOS module list and PDF lives outside the carousel', () => {
  const settingsSource = readFileSync(new URL('../../mac/Sources/ZislaCore/FeatureSettings.swift', import.meta.url), 'utf8');
  const moduleOrder = settingsSource.slice(settingsSource.indexOf('public enum IslandModuleOrder'))
    .match(/public static let defaultOrder: \[Self\] = \[([\s\S]*?)\]/)?.[1];
  assert.ok(moduleOrder, 'macOS module order exists');
  const macModuleIds = [...moduleOrder.matchAll(/\.(\w+)/g)].map((match) => match[1]);
  assert.deepEqual([...site.showcaseModuleIds].sort(), macModuleIds.sort());
  assert.equal(site.showcaseModuleIds.length, 12);
  assert.deepEqual(site.showcaseModuleGroups.map(({ id }) => id).sort(), [...site.showcaseModuleIds].sort());
  assert.equal(new Set(site.crossModuleFeatureIds).size, 17);
  assert.ok(site.crossModuleFeatureIds.includes('pdf'));
  assert.ok(!site.showcaseModuleIds.includes('pdf'));
  assert.deepEqual(Object.keys(site.crossModuleFeatureIcons).sort(), [...site.crossModuleFeatureIds].sort());
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
    const authored = new Map(strings(authoredCatalogs.get(locale), '').map(([path, value]) => [path.slice(1), value]));
    const baseline = new Map(updatedStrings(english));
    for (const [path, value] of updatedStrings(content)) {
      assert.equal(authored.get(path), value, `${locale}: ${path} must be authored without fallback`);
      assert.equal(typeof value, 'string', path);
      assert.ok(value.trim().length > 0, path);
      assert.doesNotMatch(value, /\bTODO\b|\bTBD\b/, path);
      assert.deepEqual(value.match(/\{\w+\}/g) ?? [], baseline.get(path).match(/\{\w+\}/g) ?? [], path);
      if (locale !== 'en' && path !== 'showcase.modules.volumeMixer.points.2') {
        assert.notEqual(value, baseline.get(path), `${locale}: ${path} must have its own translation`);
      }
    }
    assert.equal(content.changelog.releaseNotes['v0.1.20'].length, 8);
    assert.equal(content.changelog.releaseNotes['v0.1.21'].length, 4);
    assert.equal(content.changelog.releaseNotes['v0.1.22'].length, 9);
    const rendered = renderInMemory(locale);
    for (const [path, value] of updatedStrings(content)) {
      if (path.startsWith('meta.')) continue;
      const expected = path.startsWith('faq.') ? value : escapedText(value);
      assert.ok(rendered.html.includes(expected), `${locale}: ${path} is rendered`);
    }
    assert.equal((rendered.html.match(/class="workflow-module reveal-step"/g) ?? []).length, 12);
    assert.equal((rendered.html.match(/class="extension-item reveal-step"/g) ?? []).length, 17);
    for (const id of changedFeatureIds) {
      const title = escapedText(content.extensions.features[id].title);
      assert.ok(rendered.html.includes(`<h3>${title}</h3>`), `${locale}: rendered ${id}`);
    }
    assert.equal(rendered.document.documentElement.lang, locale);
    assert.equal(rendered.document.documentElement.dir, localeDirection(locale));
    assert.equal(rendered.document.title, content.meta.documentTitle);
    assert.ok(rendered.metadata.some(({ content: value }) => value === openGraphLocales[locale]));
    assert.ok(rendered.metadata.some(({ content: value }) => value === content.meta.description));
  });
}

test('release notes render by version while historical wording remains available', () => {
  const prepared = { version: 'v0.1.22', date: '2026-11-07', notes: ['ENGLISH FALLBACK SENTINEL'] };
  const historical = { version: 'v0.1.19', date: '2026-10-15', notes: ['HISTORICAL NOTE SENTINEL'] };
  const rendered = renderInMemory('zh-Hans', [prepared, historical]);
  for (const note of site.getSiteContent('zh-Hans').changelog.releaseNotes['v0.1.22']) {
    assert.ok(rendered.html.includes(note), 'prepared Chinese release note is rendered');
  }
  assert.ok(!rendered.html.includes('ENGLISH FALLBACK SENTINEL'));
  assert.ok(rendered.html.includes('HISTORICAL NOTE SENTINEL'), 'historical notes retain their original wording');
  const current = renderInMemory('zh-Hans', [historical]);
  assert.ok(!current.html.includes(site.getSiteContent('zh-Hans').changelog.releaseNotes['v0.1.22'][0]),
    'prepared notes do not replace the currently published release');
  const metadataOnly = renderInMemory('zh-Hans', [{ ...prepared, notes: [] }]);
  assert.ok(metadataOnly.html.includes(site.getSiteContent('zh-Hans').changelog.releaseNotes['v0.1.22'][0]),
    'a release entry can use its catalog notes without duplicating English source notes');
});


test('latest release downloads and README match the newest changelog entry', () => {
  const latest = site.changelogEntries[0];
  assert.equal(latest.version, 'v0.1.22');
  assert.equal(latest.date, '2026-11-07');
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
  const readme = readFileSync(new URL('../README.md', import.meta.url), 'utf8');
  assert.ok(readme.includes(releasePage));
  for (const key of ['dmg', 'zip', 'universalDmg', 'universalZip', 'intelDmg', 'intelZip']) {
    assert.ok(readme.includes(site.latestRelease[key]), `README includes ${key}`);
  }
  for (const url of readme.match(/https:\/\/github\.com\/wzz6423\/zisla\/releases\/(?:tag|download)\/v[^\s]+/g)) {
    assert.ok(url.startsWith(releasePage) || url.startsWith(downloadRoot), url);
  }
});
