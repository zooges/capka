import { z } from "zod";
import { requireAdmin, apiHandler, resetAuth, telegramRedirectUri, feishuRedirectUri } from "@/lib/auth";
import {
  getSetting,
  setSetting,
  getTelegramOidcConfig,
  getFeishuOAuthConfig,
  getRegistrationMode,
  getEmailSignupEnabled,
} from "@/lib/settings";
import { getPublicUrl, getRequestOrigin, resolveTrustedAuthOrigins } from "@/lib/url";
import { audit } from "@/lib/governance/audit";

/**
 * Admin config for SSO providers (Telegram + Feishu). Secrets are write-only —
 * never echoed back; the UI shows only whether one is stored. Redirect URIs are
 * derived from the request origin so the admin can copy them into BotFather /
 * the Feishu open platform.
 */
export const GET = apiHandler(async (req: Request) => {
  await requireAdmin();
  // Prefer the browser origin that opened Settings — must match OAuth baseURL
  // inference (Host / X-Forwarded-*). Fall back to PUBLIC_URL when absent.
  const origin = getRequestOrigin(req.headers) || getPublicUrl({ headers: req.headers });
  const allOrigins = resolveTrustedAuthOrigins({ headers: req.headers });
  const [tg, feishu, mode, emailSignupEnabled, tgToggle, feishuToggle] = await Promise.all([
    getTelegramOidcConfig(),
    getFeishuOAuthConfig(),
    getRegistrationMode(),
    getEmailSignupEnabled(),
    getSetting("telegram_login_enabled"),
    getSetting("feishu_login_enabled"),
  ]);
  return Response.json({
    telegram: {
      enabledToggle: tgToggle === "true",
      ready: tg.enabled,
      clientId: tg.clientId ?? "",
      hasClientSecret: !!tg.clientSecret,
      redirectUri: telegramRedirectUri(origin),
      redirectUris: allOrigins.map(telegramRedirectUri),
    },
    feishu: {
      enabledToggle: feishuToggle === "true",
      ready: feishu.enabled,
      clientId: feishu.clientId ?? "",
      hasClientSecret: !!feishu.clientSecret,
      redirectUri: feishuRedirectUri(origin),
      redirectUris: allOrigins.map(feishuRedirectUri),
    },
    registrationMode: mode,
    emailSignupEnabled,
  });
});

const bodySchema = z.object({
  clientId: z.string().trim().max(200).optional(),
  clientSecret: z.string().optional(),
  enabled: z.boolean().optional(),
  feishuClientId: z.string().trim().max(200).optional(),
  feishuClientSecret: z.string().optional(),
  feishuEnabled: z.boolean().optional(),
  registrationMode: z.enum(["open", "approval", "closed"]).optional(),
  emailSignupEnabled: z.boolean().optional(),
});

export const POST = apiHandler(async (req: Request) => {
  const { userId: adminId } = await requireAdmin();
  const body = bodySchema.parse(await req.json());

  if (body.clientId !== undefined) await setSetting("telegram_oidc_client_id", body.clientId, false);
  if (body.clientSecret) await setSetting("telegram_oidc_client_secret", body.clientSecret, true);
  if (body.enabled !== undefined) await setSetting("telegram_login_enabled", body.enabled ? "true" : "false", false);
  if (body.feishuClientId !== undefined) await setSetting("feishu_oauth_client_id", body.feishuClientId, false);
  if (body.feishuClientSecret) await setSetting("feishu_oauth_client_secret", body.feishuClientSecret, true);
  if (body.feishuEnabled !== undefined) {
    await setSetting("feishu_login_enabled", body.feishuEnabled ? "true" : "false", false);
  }
  if (body.registrationMode !== undefined) await setSetting("registration_mode", body.registrationMode, false);
  if (body.emailSignupEnabled !== undefined) {
    await setSetting("email_signup_enabled", body.emailSignupEnabled ? "true" : "false", false);
  }

  await audit({
    actorId: adminId,
    action: "auth_config.update",
    targetType: "auth_config",
    detail: {
      ...(body.clientId !== undefined ? { clientId: true } : {}),
      ...(body.clientSecret ? { clientSecret: "changed" } : {}),
      ...(body.enabled !== undefined ? { telegramLogin: body.enabled } : {}),
      ...(body.feishuClientId !== undefined ? { feishuClientId: true } : {}),
      ...(body.feishuClientSecret ? { feishuClientSecret: "changed" } : {}),
      ...(body.feishuEnabled !== undefined ? { feishuLogin: body.feishuEnabled } : {}),
      ...(body.registrationMode !== undefined ? { registrationMode: body.registrationMode } : {}),
      ...(body.emailSignupEnabled !== undefined ? { emailSignup: body.emailSignupEnabled } : {}),
    },
  });

  resetAuth();
  return Response.json({ ok: true });
});
