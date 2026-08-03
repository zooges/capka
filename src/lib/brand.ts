/**
 * Deploy-time product branding for this China-team fork (Boss & Young).
 *
 * Set NEXT_PUBLIC_PRODUCT_NAME (client + server) and optionally PRODUCT_NAME.
 * Default brand wordmark text is "BOSS & YOUNG" (ampersand, not hyphen).
 */
/** Normalize legacy hyphenated env values to the official ampersand form. */
function normalizeProductName(name: string): string {
  const trimmed = name.trim();
  if (/^boss\s*[-–—]\s*young$/i.test(trimmed)) return "BOSS & YOUNG";
  return trimmed.replace(/\bBOSS\s*[-–—]\s*YOUNG\b/gi, "BOSS & YOUNG");
}

export function productName(): string {
  const raw =
    process.env.NEXT_PUBLIC_PRODUCT_NAME?.trim() ||
    process.env.PRODUCT_NAME?.trim() ||
    "BOSS & YOUNG";
  return normalizeProductName(raw);
}

/** Optional short tagline under the brand mark. */
export function productTagline(): string {
  return (
    process.env.NEXT_PUBLIC_PRODUCT_TAGLINE?.trim() ||
    process.env.PRODUCT_TAGLINE?.trim() ||
    "Shanghai Boss & Young Attorneys-at-Law"
  );
}

/** Firm burgundy used in the B emblem. */
export const BRAND_BURGUNDY = "#8B1E23";
