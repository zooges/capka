/**
 * Single source of truth for the supported locales.
 *
 * Capka runs without locale-based URL routing: there is no `/[locale]` segment
 * and no middleware. The active locale is resolved per request (see `locale.ts`).
 * This China-team fork ships Simplified Chinese + English only.
 */
export const locales = ["zh-CN", "en"] as const;

export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = "zh-CN";

/** Human-readable names for the language switcher (in their own language). */
export const localeNames: Record<Locale, string> = {
  "zh-CN": "简体中文",
  en: "English",
};

export function isLocale(value: unknown): value is Locale {
  return typeof value === "string" && (locales as readonly string[]).includes(value);
}

/**
 * Pick the best supported locale from an `Accept-Language` header.
 * Returns `null` when nothing matches, so the caller can fall back.
 *
 * Prefer an exact tag match (`zh-CN`), then map Chinese primary tags
 * (`zh`, `zh-Hans`, `zh-TW` → Simplified for this fork) to `zh-CN`, then fall
 * back to the primary subtag when it is a supported locale (`en-US` → `en`).
 */
export function matchAcceptLanguage(header: string | null | undefined): Locale | null {
  if (!header) return null;
  const ranked = header
    .split(",")
    .map((part) => {
      const [tag, ...params] = part.trim().split(";");
      const q = params.find((p) => p.trim().startsWith("q="));
      const weight = q ? Number.parseFloat(q.trim().slice(2)) : 1;
      return { tag: tag.trim().toLowerCase(), weight: Number.isNaN(weight) ? 0 : weight };
    })
    .sort((a, b) => b.weight - a.weight);

  for (const { tag } of ranked) {
    if (isLocale(tag)) return tag;
    const primary = tag.split("-")[0];
    if (primary === "zh") return "zh-CN";
    if (isLocale(primary)) return primary;
  }
  return null;
}
