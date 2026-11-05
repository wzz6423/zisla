import assert from 'node:assert/strict';
import test from 'node:test';
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
