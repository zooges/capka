import { getAuth } from "@/lib/auth";
import { toNextJsHandler } from "better-auth/next-js";
import { getRegistrationMode, getEmailSignupEnabled, isSetupComplete } from "@/lib/settings";
import { emailSignupAllowed, isReservedTelegramEmail } from "@/lib/auth/telegram-oidc";
import { isReservedFeishuEmail, isFeishuInAppUserAgent } from "@/lib/auth/feishu-oauth";
import { getPublicUrl, getRequestOrigin } from "@/lib/url";

/**
 * Next/Docker often sees request.url as http://0.0.0.0:3000/... (listen bind).
 * Better Auth builds OAuth redirect_uri from that origin when baseURL is unset,
 * and even with PUBLIC_URL set, cookie Host must match the browser. Rewrite to
 * the browser/proxy origin (Host / X-Forwarded-*) before handing off.
 */
function withBrowserOrigin(request: Request): Request {
  const origin =
    getRequestOrigin(request.headers) || getPublicUrl({ headers: request.headers });
  const incoming = new URL(request.url);
  const fixed = new URL(incoming.pathname + incoming.search, origin);
  if (fixed.origin === incoming.origin) return request;
  return new Request(fixed.toString(), request);
}

function hasCapkaNativeCookie(cookieHeader: string | null): boolean {
  return /(?:^|;\s*)capka_native=1(?:;|$)/.test(cookieHeader || "");
}

function isMobileUserAgent(ua: string | null): boolean {
  return /iPhone|iPad|iPod|Android/i.test(ua || "");
}

/**
 * After Feishu OAuth, Safari (system browser) may land on the HTTP callback
 * outside our WKWebView. Bounce those — and only those — into the iOS shell
 * URL scheme so WKWebView can replay the callback. Never bridge Feishu/Lark
 * webviews. Scheme defaults to `bossyoung` (邦信阳); intranet 邦信阳2 sets
 * `CAPKA_IOS_URL_SCHEME=bossyoung2`.
 */
function iosShellUrlScheme(): string {
  const raw = (process.env.CAPKA_IOS_URL_SCHEME ?? "bossyoung").trim().toLowerCase();
  return raw.replace(/[^a-z0-9+-]/g, "") || "bossyoung";
}

function feishuNativeBridgeRedirect(request: Request, url: URL): Response | null {
  if (!url.pathname.includes("/oauth2/callback/feishu")) return null;
  if (!url.searchParams.has("code")) return null;
  if (hasCapkaNativeCookie(request.headers.get("cookie"))) return null;
  const ua = request.headers.get("user-agent");
  if (!isMobileUserAgent(ua)) return null;
  if (isFeishuInAppUserAgent(ua)) {
    console.info("[auth] feishu callback in Feishu/Lark webview — skip iOS shell bridge");
    return null;
  }
  const scheme = iosShellUrlScheme();
  const bridge = `${scheme}://oauth${url.search}`;
  console.info("[auth] feishu native bridge →", bridge);
  return Response.redirect(bridge, 302);
}

export async function GET(request: Request) {
  const req = withBrowserOrigin(request);
  const url = new URL(req.url);
  const bridged = feishuNativeBridgeRedirect(request, url);
  if (bridged) return bridged;

  const isOauthCb = url.pathname.includes("/oauth2/callback/");
  if (isOauthCb) {
    console.info("[auth] oauth callback", {
      path: url.pathname,
      origin: url.origin,
      host: request.headers.get("host"),
      hasCode: url.searchParams.has("code"),
      hasState: url.searchParams.has("state"),
      providerError: url.searchParams.get("error"),
      cookie: request.headers.get("cookie")?.includes("oauth_state") ? "oauth_state" : "none",
      native: hasCapkaNativeCookie(request.headers.get("cookie")),
    });
  }
  const auth = await getAuth();
  const handler = toNextJsHandler(auth);
  const res = await handler.GET(req);
  if (isOauthCb) {
    console.info("[auth] oauth callback result", {
      status: res.status,
      location: res.headers.get("location"),
      setCookie: (res.headers.getSetCookie?.() ?? []).map((c) => c.split("=")[0]).join(",")
        || res.headers.get("set-cookie")?.split(",").map((c) => c.trim().split("=")[0]).join(",")
        || "none",
    });
  }
  return res;
}

export async function POST(request: Request) {
  const req = withBrowserOrigin(request);
  // Email sign-up is governed by the registration mode ("closed" blocks it) AND
  // the standalone email toggle — an admin can forbid email account creation
  // while leaving Telegram open. emailSignupAllowed composes both with the
  // bootstrap exception: before setup is complete self-signup must work so the
  // first admin can create their account.
  const url = new URL(req.url);
  if (url.pathname.endsWith("/sign-up/email")) {
    const [setupDone, mode, emailEnabled] = await Promise.all([
      isSetupComplete(),
      getRegistrationMode(),
      getEmailSignupEnabled(),
    ]);
    if (!emailSignupAllowed({ mode, emailEnabled, setupDone })) {
      return Response.json({ error: "Registration is disabled" }, { status: 403 });
    }
    // Reserve the synthetic Telegram domain: nobody may register an
    // @telegram.local address, which would otherwise let an attacker pre-seed
    // the predictable placeholder email of a Telegram user (account-takeover
    // vector). Read via clone() so the original body still reaches the handler.
    const email = await req
      .clone()
      .json()
      .then((b: { email?: string }) => b?.email ?? "")
      .catch(() => "");
    if (email && (isReservedTelegramEmail(email) || isReservedFeishuEmail(email))) {
      return Response.json({ error: "This email address is not allowed" }, { status: 400 });
    }
  }

  const auth = await getAuth();
  const handler = toNextJsHandler(auth);
  return handler.POST(req);
}
