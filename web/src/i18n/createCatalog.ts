import type { SiteContent } from '../content';
import { en } from './en';

type DeepPartial<T> = T extends readonly (infer Item)[]
  ? readonly DeepPartial<Item>[]
  : T extends object
    ? { [Key in keyof T]?: DeepPartial<T[Key]> }
    : T;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const mergeCatalog = (base: unknown, overrides: unknown): unknown => {
  if (overrides === undefined) return base;
  if (isRecord(base) && isRecord(overrides)) {
    const merged: Record<string, unknown> = { ...base };
    Object.entries(overrides).forEach(([key, value]) => {
      merged[key] = mergeCatalog(merged[key], value);
    });
    return merged;
  }
  return overrides;
};

export const createCatalog = (overrides: DeepPartial<SiteContent>): SiteContent =>
  mergeCatalog(en, overrides) as SiteContent;
