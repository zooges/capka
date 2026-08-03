import {
  getRegistrationMode,
  getEmailSignupEnabled,
  isSetupComplete,
  getTelegramOidcConfig,
  getFeishuOAuthConfig,
} from "@/lib/settings";
import { emailSignupAllowed } from "@/lib/auth/telegram-oidc";

export async function GET() {
  // `enabled` here means "email sign-up is offered". Mirror the gate in
  // /api/auth/[...all] exactly so the register page never shows a form that the
  // server would reject. When email is off but Telegram/Feishu is on, the
  // register page falls back to the OAuth-only path.
  const [setupDone, mode, emailEnabled, telegram, feishu] = await Promise.all([
    isSetupComplete(),
    getRegistrationMode(),
    getEmailSignupEnabled(),
    getTelegramOidcConfig(),
    getFeishuOAuthConfig(),
  ]);
  const enabled = emailSignupAllowed({ mode, emailEnabled, setupDone });
  // Whether SSO buttons should appear (admin-configured and fully credentialed).
  // Public, non-secret — just booleans.
  return Response.json({
    enabled,
    telegram: { enabled: telegram.enabled },
    feishu: {
      enabled: feishu.enabled,
      // Public App ID for Feishu Mobile SSO (LarkSSO) registration in the iOS shell.
      appId: feishu.enabled ? feishu.clientId : null,
    },
  });
}
