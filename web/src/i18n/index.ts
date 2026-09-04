import type { SiteContent } from '../content';
import type { SiteLocale } from '../locales';

/**
 * Every catalog is its own chunk, so a visit downloads the language it renders
 * instead of all 17. Vite keeps the shared English base in one extra chunk.
 */
const catalogLoaders: Record<SiteLocale, () => Promise<SiteContent>> = {
  'zh-Hans': () => import('./zh-Hans').then((module) => module.zhHans),
  'zh-Hant': () => import('./zh-Hant').then((module) => module.zhHant),
  en: () => import('./en').then((module) => module.en),
  ja: () => import('./ja').then((module) => module.ja),
  ko: () => import('./ko').then((module) => module.ko),
  fr: () => import('./fr').then((module) => module.fr),
  de: () => import('./de').then((module) => module.de),
  es: () => import('./es').then((module) => module.es),
  'pt-BR': () => import('./pt-BR').then((module) => module.ptBR),
  it: () => import('./it').then((module) => module.it),
  nl: () => import('./nl').then((module) => module.nl),
  ru: () => import('./ru').then((module) => module.ru),
  ar: () => import('./ar').then((module) => module.ar),
  th: () => import('./th').then((module) => module.th),
  id: () => import('./id').then((module) => module.id),
  vi: () => import('./vi').then((module) => module.vi),
  tr: () => import('./tr').then((module) => module.tr),
};

const resolved = new Map<SiteLocale, SiteContent>();
const inFlight = new Map<SiteLocale, Promise<SiteContent>>();

/** Resolves the catalog for `locale`, fetching its chunk at most once. */
export const loadCatalog = async (locale: SiteLocale): Promise<SiteContent> => {
  const cached = resolved.get(locale);
  if (cached) return cached;

  // Rapid switching can ask for the same locale twice before the chunk lands.
  const pending = inFlight.get(locale) ?? catalogLoaders[locale]();
  inFlight.set(locale, pending);
  try {
    const catalog = await pending;
    resolved.set(locale, catalog);
    return catalog;
  } finally {
    inFlight.delete(locale);
  }
};

export const loadedCatalog = (locale: SiteLocale): SiteContent | undefined => resolved.get(locale);
