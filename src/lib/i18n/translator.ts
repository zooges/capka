/**
 * A translator usable OUTSIDE Next.js's request context — the Telegram bot polls
 * in a long-running process and the worker runs detached, so neither can use
 * next-intl's request-scoped `getTranslations`. We load the message catalogs
 * statically and build a translator on demand from a locale.
 *
 * English is the fallback: any unsupported or unknown locale (e.g. a Telegram
 * `language_code` we don't ship, like "ru" or "de") resolves to "en".
 */
import { createTranslator } from "next-intl";
import { defaultLocale, isLocale } from "@/i18n/config";
import en from "../../../messages/en.json";
import zhCN from "../../../messages/zh-CN.json";
import uk from "../../../messages/uk.json";

/**
 * UI locales are zh-CN + en only. Ukrainian message catalog is kept for
 * Telegram / legacy `language_code=uk` clients, but is not offered in settings.
 */
const MESSAGES: Record<string, Record<string, unknown>> = { en, "zh-CN": zhCN, uk };

/**
 * Normalize an arbitrary locale-ish string to a supported locale. Accepts BCP-47
 * tags (Telegram sends `language_code` like "uk", "en-US", "ru") and matches on
 * the primary subtag; Chinese maps to `zh-CN`; Ukrainian keeps `uk` messages for
 * Telegram; everything else unsupported falls back to the fork default (`zh-CN`).
 */
export function toLocale(value: string | null | undefined): string {
  if (!value) return defaultLocale;
  const lower = value.toLowerCase();
  if (lower === "uk" || lower.startsWith("uk-")) return "uk";
  if (isLocale(lower)) return lower;
  const primary = lower.split("-")[0];
  if (primary === "zh") return "zh-CN";
  return isLocale(primary) ? primary : defaultLocale;
}

/**
 * A loosely-typed translator. next-intl's `createTranslator` derives strict
 * literal key types from the globally-augmented `Messages`, which collapses to
 * `never` once the namespace is a runtime string — so outside the request
 * context we accept any key and validate against the catalogs at runtime
 * (a missing key surfaces as the visible key, the standard next-intl behavior).
 */
export type Translator = (key: string, values?: Record<string, string | number>) => string;

/** Build a translator for the given locale, optionally scoped to a namespace. */
export function getTranslator(value: string | null | undefined, namespace?: string): Translator {
  const locale = toLocale(value);
  return createTranslator({ locale, messages: MESSAGES[locale], namespace }) as unknown as Translator;
}
