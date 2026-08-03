/**
 * Feishu / Lark OAuth helpers. Feishu is not a standard OIDC discovery provider —
 * endpoints are fixed, userinfo is wrapped in `{ code, data }`, and the token
 * endpoint requires JSON (`application/json`), not form-urlencoded.
 */

export const FEISHU_PROVIDER_ID = "feishu";

export const FEISHU_AUTHORIZATION_URL =
  "https://accounts.feishu.cn/open-apis/authen/v1/authorize";
export const FEISHU_TOKEN_URL = "https://open.feishu.cn/open-apis/authen/v2/oauth/token";
export const FEISHU_USERINFO_URL = "https://open.feishu.cn/open-apis/authen/v1/user_info";

/** Redirect URI an admin must register in the Feishu open platform app. */
export function feishuRedirectUri(origin: string): string {
  return `${origin.replace(/\/$/, "")}/api/auth/oauth2/callback/${FEISHU_PROVIDER_ID}`;
}

/**
 * Feishu / Lark in-app browsers (workplace web app, etc.). OAuth must finish
 * there — do not bounce these UAs to a native URL scheme.
 */
export function isFeishuInAppUserAgent(ua: string | null | undefined): boolean {
  return /Lark|Feishu|LarkLocale|ByteLocale|LarkApp|FeishuApp/i.test(ua || "");
}

/** URL scheme Feishu Mobile SSO uses to return to the host app (App ID without `_`). */
export function feishuNativeUrlScheme(appId: string): string {
  return appId.replace(/_/g, "");
}

/** redirect_uri registered / sent for Feishu Mobile SSO token exchange. */
export function feishuNativeRedirectUri(appId: string): string {
  return `${feishuNativeUrlScheme(appId)}://`;
}

export function syntheticFeishuEmail(openId: string): string {
  return `feishu_${openId.replace(/[^a-zA-Z0-9_-]/g, "_")}@feishu.local`;
}

export function isReservedFeishuEmail(email: string): boolean {
  return email.trim().toLowerCase().endsWith("@feishu.local");
}

export interface FeishuUserInfo {
  openId: string;
  unionId?: string;
  name: string;
  email?: string;
  picture?: string;
}

/** Map Feishu userinfo JSON (wrapped or flat) into a better-auth user shape. */
export function mapFeishuProfile(raw: unknown): FeishuUserInfo | null {
  if (!raw || typeof raw !== "object") return null;
  const root = raw as Record<string, unknown>;
  // Feishu error payloads are HTTP 200 with `{ code: non-zero, msg }` and no data.
  if (typeof root.code === "number" && root.code !== 0) return null;
  const data =
    root.data && typeof root.data === "object"
      ? (root.data as Record<string, unknown>)
      : root;
  const openId = typeof data.open_id === "string" ? data.open_id : null;
  if (!openId) return null;
  const name =
    (typeof data.name === "string" && data.name) ||
    (typeof data.en_name === "string" && data.en_name) ||
    openId;
  return {
    openId,
    unionId: typeof data.union_id === "string" ? data.union_id : undefined,
    name,
    email: typeof data.email === "string" && data.email ? data.email : undefined,
    picture:
      (typeof data.avatar_url === "string" && data.avatar_url) ||
      (typeof data.avatar_big === "string" && data.avatar_big) ||
      undefined,
  };
}

export interface FeishuOAuthTokens {
  tokenType?: string;
  accessToken: string;
  refreshToken?: string;
  accessTokenExpiresAt?: Date;
  refreshTokenExpiresAt?: Date;
  scopes?: string[];
  raw?: Record<string, unknown>;
}

/**
 * Exchange an authorization code for tokens via Feishu's JSON token endpoint.
 * better-auth's default exchange uses `application/x-www-form-urlencoded`, which
 * Feishu documents as unsupported (Content-Type must be `application/json`).
 */
export async function exchangeFeishuAuthorizationCode(opts: {
  clientId: string;
  clientSecret: string;
  code: string;
  /** Required for web OAuth; optional / scheme URL for Feishu Mobile SSO. */
  redirectURI?: string;
  codeVerifier?: string;
  fetchImpl?: typeof fetch;
}): Promise<FeishuOAuthTokens> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const body: Record<string, string> = {
    grant_type: "authorization_code",
    client_id: opts.clientId,
    client_secret: opts.clientSecret,
    code: opts.code,
  };
  if (opts.redirectURI) body.redirect_uri = opts.redirectURI;
  if (opts.codeVerifier) body.code_verifier = opts.codeVerifier;

  const res = await fetchImpl(FEISHU_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8", Accept: "application/json" },
    body: JSON.stringify(body),
  });
  const raw = (await res.json().catch(() => null)) as Record<string, unknown> | null;
  if (!raw || typeof raw !== "object") {
    throw new Error(`Feishu token exchange failed: empty response (HTTP ${res.status})`);
  }
  const feishuCode = typeof raw.code === "number" ? raw.code : null;
  const accessToken = typeof raw.access_token === "string" ? raw.access_token : null;
  if (!res.ok || (feishuCode !== null && feishuCode !== 0) || !accessToken) {
    const detail =
      (typeof raw.error_description === "string" && raw.error_description) ||
      (typeof raw.error === "string" && raw.error) ||
      (typeof raw.msg === "string" && raw.msg) ||
      `HTTP ${res.status}`;
    throw new Error(`Feishu token exchange failed: ${detail} (code=${feishuCode ?? "n/a"})`);
  }

  const expiresIn = typeof raw.expires_in === "number" ? raw.expires_in : undefined;
  const refreshExpiresIn =
    typeof raw.refresh_token_expires_in === "number" ? raw.refresh_token_expires_in : undefined;
  const now = Date.now();
  return {
    tokenType: typeof raw.token_type === "string" ? raw.token_type : "Bearer",
    accessToken,
    refreshToken: typeof raw.refresh_token === "string" ? raw.refresh_token : undefined,
    accessTokenExpiresAt: expiresIn ? new Date(now + expiresIn * 1000) : undefined,
    refreshTokenExpiresAt: refreshExpiresIn ? new Date(now + refreshExpiresIn * 1000) : undefined,
    scopes:
      typeof raw.scope === "string"
        ? raw.scope.split(/\s+/).filter(Boolean)
        : Array.isArray(raw.scope)
          ? (raw.scope as string[])
          : [],
    raw,
  };
}
