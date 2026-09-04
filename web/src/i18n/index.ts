import type { SiteContent } from '../content';
import type { SiteLocale } from '../locales';
import { de } from './de';
import { en } from './en';
import { es } from './es';
import { fr } from './fr';
import { id } from './id';
import { it } from './it';
import { ja } from './ja';
import { ko } from './ko';
import { nl } from './nl';
import { ptBR } from './pt-BR';
import { ru } from './ru';
import { ar } from './ar';
import { th } from './th';
import { tr } from './tr';
import { vi } from './vi';
import { zhHans } from './zh-Hans';
import { zhHant } from './zh-Hant';

export const catalogs: Record<SiteLocale, SiteContent> = {
  'zh-Hans': zhHans,
  'zh-Hant': zhHant,
  en,
  ja,
  ko,
  fr,
  de,
  es,
  'pt-BR': ptBR,
  it,
  nl,
  ru,
  ar,
  th,
  id,
  vi,
  tr,
};
