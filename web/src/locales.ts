/**
 * Site locales mirror `AppLanguage` in mac/Sources/ZislaKit/AppLanguageStore.swift,
 * so the website and the macOS app always offer the same set of languages.
 */
export const siteLocales = [
  'zh-Hans',
  'zh-Hant',
  'en',
  'ja',
  'ko',
  'fr',
  'de',
  'es',
  'pt-BR',
  'it',
  'nl',
  'ru',
  'ar',
  'th',
  'id',
  'vi',
  'tr',
] as const;

export type SiteLocale = (typeof siteLocales)[number];

export const defaultLocale: SiteLocale = 'zh-Hans';

/** Native names, kept identical to `languageDisplayName` in the macOS settings picker. */
export const localeNativeNames: Record<SiteLocale, string> = {
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
  en: 'English',
  ja: '日本語',
  ko: '한국어',
  fr: 'Français',
  de: 'Deutsch',
  es: 'Español',
  'pt-BR': 'Português (Brasil)',
  it: 'Italiano',
  nl: 'Nederlands',
  ru: 'Русский',
  ar: 'العربية',
  th: 'ไทย',
  id: 'Bahasa Indonesia',
  vi: 'Tiếng Việt',
  tr: 'Türkçe',
};

/** Arabic is the only right-to-left locale, matching `AppLanguage.isRightToLeft`. */
export const isRightToLeft = (locale: SiteLocale): boolean => locale === 'ar';

export const localeDirection = (locale: SiteLocale): 'ltr' | 'rtl' =>
  isRightToLeft(locale) ? 'rtl' : 'ltr';

/** `og:locale` wants an underscore-separated tag with a region. */
export const openGraphLocales: Record<SiteLocale, string> = {
  'zh-Hans': 'zh_CN',
  'zh-Hant': 'zh_TW',
  en: 'en_US',
  ja: 'ja_JP',
  ko: 'ko_KR',
  fr: 'fr_FR',
  de: 'de_DE',
  es: 'es_ES',
  'pt-BR': 'pt_BR',
  it: 'it_IT',
  nl: 'nl_NL',
  ru: 'ru_RU',
  ar: 'ar_AR',
  th: 'th_TH',
  id: 'id_ID',
  vi: 'vi_VN',
  tr: 'tr_TR',
};

export const localeStorageKey = 'zisla.interface-language';

const lowercasedLocales = new Map<string, SiteLocale>(
  siteLocales.map((locale) => [locale.toLowerCase(), locale]),
);

/**
 * Region and script subtags that browsers report but that we fold into one of the
 * supported locales, e.g. `zh-CN` and `zh-SG` both resolve to Simplified Chinese.
 */
const scriptAliases: Record<string, SiteLocale> = {
  'zh-cn': 'zh-Hans',
  'zh-sg': 'zh-Hans',
  'zh-my': 'zh-Hans',
  'zh-chs': 'zh-Hans',
  'zh-tw': 'zh-Hant',
  'zh-hk': 'zh-Hant',
  'zh-mo': 'zh-Hant',
  'zh-cht': 'zh-Hant',
};

/** Primary subtags whose only available translation lives under a regional code. */
const primaryFallbacks: Record<string, SiteLocale> = {
  zh: 'zh-Hans',
  pt: 'pt-BR',
  in: 'id', // Legacy ISO 639 code for Indonesian, still emitted by some runtimes.
};

/** Resolve a single BCP-47 tag such as `pt-BR`, `zh-Hant-HK` or `fr-CA`. */
export const matchLocale = (tag: string): SiteLocale | undefined => {
  const normalized = tag.trim().toLowerCase().replace(/_/g, '-');
  if (!normalized) return undefined;

  const exact = lowercasedLocales.get(normalized);
  if (exact) return exact;

  const subtags = normalized.split('-');
  const primary = subtags[0] ?? '';

  // Script subtag wins over region: zh-Hant-HK must stay Traditional Chinese.
  for (const subtag of subtags.slice(1)) {
    const scripted = lowercasedLocales.get(`${primary}-${subtag}`);
    if (scripted) return scripted;
  }

  if (subtags.length > 1) {
    const aliased = scriptAliases[`${primary}-${subtags[1]}`];
    if (aliased) return aliased;
  }

  return lowercasedLocales.get(primary) ?? primaryFallbacks[primary];
};

/** Pick the first browser-preferred language we can serve, else Simplified Chinese. */
export const resolvePreferredLocale = (
  preferred: readonly string[] = [],
): SiteLocale => {
  for (const tag of preferred) {
    const matched = matchLocale(tag);
    if (matched) return matched;
  }
  return defaultLocale;
};

export const isSiteLocale = (value: unknown): value is SiteLocale =>
  typeof value === 'string' && (siteLocales as readonly string[]).includes(value);
