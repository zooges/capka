import { and, eq } from "drizzle-orm";
import { nanoid } from "nanoid";
import { serializeSignedCookie } from "better-call";
import { db } from "@/lib/db";
import * as schema from "@/lib/db/schema";
import { getAuth, normalizeAccountStatus, type AccountStatus } from "@/lib/auth";
import {
  FEISHU_PROVIDER_ID,
  FEISHU_USERINFO_URL,
  exchangeFeishuAuthorizationCode,
  mapFeishuProfile,
  syntheticFeishuEmail,
} from "@/lib/auth/feishu-oauth";
import { getFeishuOAuthConfig, getMasterKey, getRegistrationMode, isSetupComplete } from "@/lib/settings";
import { resolveRegistration } from "@/lib/auth/telegram-oidc";

async function fetchFeishuProfile(accessToken: string, rawTok?: Record<string, unknown> | null) {
  try {
    const res = await fetch(FEISHU_USERINFO_URL, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    const raw = await res.json().catch(() => null);
    if (res.ok) {
      const profile = mapFeishuProfile(raw);
      if (profile) return profile;
    } else {
      console.error("[auth] Feishu native userinfo HTTP", res.status, raw);
    }
  } catch (e) {
    console.error("[auth] Feishu native userinfo failed:", e);
  }
  const openId =
    (typeof rawTok?.open_id === "string" && rawTok.open_id) ||
    (typeof rawTok?.data === "object" &&
      rawTok.data &&
      typeof (rawTok.data as Record<string, unknown>).open_id === "string" &&
      ((rawTok.data as Record<string, unknown>).open_id as string)) ||
    null;
  if (!openId) return null;
  const name =
    (typeof rawTok?.name === "string" && rawTok.name) ||
    (typeof rawTok?.data === "object" &&
      rawTok.data &&
      typeof (rawTok.data as Record<string, unknown>).name === "string" &&
      ((rawTok.data as Record<string, unknown>).name as string)) ||
    openId;
  return { openId, name, email: undefined as string | undefined, picture: undefined as string | undefined };
}

function fail(
  opts: { request: Request; responseMode?: "redirect" | "json" },
  reason: string,
  status = 401,
): Response {
  console.error(`[auth] Feishu native sign-in failed: ${reason}`);
  if (opts.responseMode === "json") {
    return Response.json({ error: "feishu", reason }, { status });
  }
  return Response.redirect(new URL("/login?error=feishu", opts.request.url).toString(), 302);
}

/**
 * Complete Feishu Mobile SSO (LarkSSO) for the iOS shell: exchange code, upsert
 * user/account, mint a better-auth session cookie, redirect (or JSON) to /chat.
 *
 * Cookie signing must match better-call's `serializeSignedCookie` (HMAC-SHA256 +
 * standard base64 with padding). `createHMAC(..., "base64urlnopad")` produces a
 * signature better-auth's `getSignedCookie` rejects (expects len 44 + trailing `=`).
 */
export async function completeFeishuNativeSignIn(opts: {
  code: string;
  codeVerifier?: string;
  request: Request;
  /** iOS URLSession path prefers JSON + Set-Cookie over a 302 that WKWebView may mishandle. */
  responseMode?: "redirect" | "json";
}): Promise<Response> {
  const feishu = await getFeishuOAuthConfig();
  if (!feishu.enabled || !feishu.clientId || !feishu.clientSecret) {
    return Response.json({ error: "Feishu login is not configured" }, { status: 503 });
  }

  let tokens;
  try {
    // LarkSSO does not use a web redirect_uri during authorize; sending a scheme
    // or web callback here can make Feishu reject the code. Omit redirect_uri.
    tokens = await exchangeFeishuAuthorizationCode({
      clientId: feishu.clientId,
      clientSecret: feishu.clientSecret,
      code: opts.code,
      codeVerifier: opts.codeVerifier,
    });
  } catch (e) {
    console.error("[auth] Feishu native token exchange failed:", e);
    return fail(opts, e instanceof Error ? e.message : "token_exchange");
  }

  const profile = await fetchFeishuProfile(tokens.accessToken, tokens.raw ?? null);
  if (!profile) {
    return fail(opts, "userinfo_unavailable");
  }

  const accountId = profile.openId;
  const email = profile.email || syntheticFeishuEmail(profile.openId);

  const [existing] = await db
    .select({
      userId: schema.accounts.userId,
      status: schema.users.status,
    })
    .from(schema.accounts)
    .innerJoin(schema.users, eq(schema.users.id, schema.accounts.userId))
    .where(and(eq(schema.accounts.providerId, FEISHU_PROVIDER_ID), eq(schema.accounts.accountId, accountId)))
    .limit(1);

  let userId: string;
  let status: AccountStatus;

  if (existing) {
    userId = existing.userId;
    status = normalizeAccountStatus(existing.status);
    await db
      .update(schema.accounts)
      .set({
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessTokenExpiresAt: tokens.accessTokenExpiresAt,
        refreshTokenExpiresAt: tokens.refreshTokenExpiresAt,
        updatedAt: new Date(),
      })
      .where(
        and(eq(schema.accounts.providerId, FEISHU_PROVIDER_ID), eq(schema.accounts.accountId, accountId)),
      );
  } else {
    if (!(await isSetupComplete())) {
      return fail(opts, "setup_incomplete");
    }
    const decision = resolveRegistration({
      mode: await getRegistrationMode(),
      setupDone: true,
    });
    if (!decision.allow) {
      return fail(opts, "registration_closed");
    }

    // Prefer linking by real work email when present (same as better-auth linking).
    if (profile.email) {
      const [byEmail] = await db
        .select({ id: schema.users.id, status: schema.users.status })
        .from(schema.users)
        .where(eq(schema.users.email, profile.email))
        .limit(1);
      if (byEmail) {
        userId = byEmail.id;
        status = normalizeAccountStatus(byEmail.status);
        await db.insert(schema.accounts).values({
          id: nanoid(),
          accountId,
          providerId: FEISHU_PROVIDER_ID,
          userId,
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          accessTokenExpiresAt: tokens.accessTokenExpiresAt,
          refreshTokenExpiresAt: tokens.refreshTokenExpiresAt,
          scope: tokens.scopes?.join(" "),
        });
      } else {
        userId = nanoid();
        status = decision.status as AccountStatus;
        await db.insert(schema.users).values({
          id: userId,
          name: profile.name,
          email,
          emailVerified: !!profile.email,
          image: profile.picture,
          role: decision.role,
          status: decision.status,
        });
        await db.insert(schema.accounts).values({
          id: nanoid(),
          accountId,
          providerId: FEISHU_PROVIDER_ID,
          userId,
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          accessTokenExpiresAt: tokens.accessTokenExpiresAt,
          refreshTokenExpiresAt: tokens.refreshTokenExpiresAt,
          scope: tokens.scopes?.join(" "),
        });
      }
    } else {
      userId = nanoid();
      status = decision.status as AccountStatus;
      await db.insert(schema.users).values({
        id: userId,
        name: profile.name,
        email,
        emailVerified: false,
        image: profile.picture,
        role: decision.role,
        status: decision.status,
      });
      await db.insert(schema.accounts).values({
        id: nanoid(),
        accountId,
        providerId: FEISHU_PROVIDER_ID,
        userId,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessTokenExpiresAt: tokens.accessTokenExpiresAt,
        refreshTokenExpiresAt: tokens.refreshTokenExpiresAt,
        scope: tokens.scopes?.join(" "),
      });
    }
  }

  if (status === "pending") {
    if (opts.responseMode === "json") {
      return Response.json({ ok: false, redirect: "/pending", reason: "pending" }, { status: 403 });
    }
    return Response.redirect(new URL("/pending", opts.request.url).toString(), 302);
  }
  if (status !== "active") {
    return fail(opts, `status_${status}`);
  }

  const auth = await getAuth();
  // better-auth exposes $context for adapters / cookie signing secret.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const ctx = await (auth as any).$context;
  const session = await ctx.internalAdapter.createSession(userId);
  if (!session?.token) {
    return fail(opts, "create_session", 500);
  }

  const secret = await getMasterKey();
  const maxAge = 60 * 60 * 24 * 7;
  // Must match better-auth / better-call signed cookie format (standard base64 + padding).
  const cookie = await serializeSignedCookie("better-auth.session_token", session.token, secret, {
    path: "/",
    maxAge,
    httpOnly: true,
    sameSite: "lax",
    // HTTP IP deploy; TRUSTED_ORIGINS includes http:// — never set Secure here.
    secure: false,
  });

  const dest = new URL("/chat", opts.request.url);
  if (opts.responseMode === "json") {
    return Response.json(
      { ok: true, redirect: "/chat" },
      {
        status: 200,
        headers: { "Set-Cookie": cookie },
      },
    );
  }

  return new Response(null, {
    status: 302,
    headers: {
      Location: dest.toString(),
      "Set-Cookie": cookie,
    },
  });
}
