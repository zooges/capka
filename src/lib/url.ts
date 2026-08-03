/**
 * The single source of truth for the app's public origin — used for auth
 * (better-auth baseURL + trustedOrigins) and any absolute link we emit.
 *
 * Resolution order, so the URL is a RUNTIME concern (never baked into the
 * build) and works on a fresh box with zero config:
 *   1. PUBLIC_URL — explicit operator override (set once for prod / behind a
 *      proxy whose forwarded headers we don't fully trust).
 *   2. Proxy headers — X-Forwarded-Proto + X-Forwarded-Host (or Host), so a
 *      reverse proxy / PaaS that terminates TLS gets the right origin for free.
 *   3. http://localhost:3000 — local default; `docker compose up` just works.
 */

const stripTrailingSlash = (url: string) => url.replace(/\/+$/, "");

const firstValue = (header: string | null | undefined) =>
  header?.split(",")[0]?.trim() || undefined;

/** Origin derived only from this request's Host / X-Forwarded-* (ignores PUBLIC_URL). */
export function getRequestOrigin(headers?: Headers): string | undefined {
  if (!headers) return undefined;
  const host = firstValue(headers.get("x-forwarded-host")) || headers.get("host")?.trim();
  if (!host) return undefined;
  const proto = firstValue(headers.get("x-forwarded-proto")) || "http";
  return stripTrailingSlash(`${proto}://${host}`);
}

/**
 * Comma/space-separated extra origins for better-auth CSRF (e.g. LAN IP while
 * PUBLIC_URL is the Cloudflare tunnel hostname).
 * Example: TRUSTED_ORIGINS=http://10.0.40.100:3100,http://127.0.0.1:3100
 */
export function parseTrustedOrigins(raw?: string | null): string[] {
  return String(raw || "")
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean)
    .map(stripTrailingSlash);
}

/**
 * Origins Better Auth should accept for this request: PUBLIC_URL (if set), any
 * TRUSTED_ORIGINS extras, and the request's own Host-derived origin so a tunnel
 * domain and a LAN IP can both log in.
 */
export function resolveTrustedAuthOrigins(opts: {
  env?: Record<string, string | undefined>;
  headers?: Headers;
} = {}): string[] {
  const env = opts.env ?? process.env;
  const out = new Set<string>();
  const explicit = env.PUBLIC_URL?.trim() || env.BETTER_AUTH_URL?.trim();
  if (explicit) out.add(stripTrailingSlash(explicit));
  for (const o of parseTrustedOrigins(env.TRUSTED_ORIGINS)) out.add(o);
  const fromReq = getRequestOrigin(opts.headers);
  if (fromReq) out.add(fromReq);
  if (out.size === 0) out.add("http://localhost:3000");
  return [...out];
}

export function getPublicUrl(opts: {
  env?: Record<string, string | undefined>;
  headers?: Headers;
} = {}): string {
  const env = opts.env ?? process.env;

  const explicit = env.PUBLIC_URL?.trim();
  if (explicit) return stripTrailingSlash(explicit);

  return getRequestOrigin(opts.headers) || "http://localhost:3000";
}
