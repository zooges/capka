"use client";

import { useState } from "react";
import Image from "next/image";
import { useTranslations } from "next-intl";
import { Loader2 } from "lucide-react";
import { authClient } from "@/lib/auth-client";
import { authErrorKey } from "@/lib/auth/client-error";
import { toast } from "sonner";
import { FEISHU_PROVIDER_ID } from "@/lib/auth/feishu-oauth";
import { SsoMarkButton } from "@/components/auth/sso-mark-button";

/**
 * "Sign in with Feishu" — starts better-auth genericOAuth against Feishu/Lark.
 * Renders nothing when the admin has not fully configured Feishu login.
 */
export function FeishuSignIn({ enabled, callbackURL = "/chat" }: { enabled: boolean | null; callbackURL?: string }) {
  const t = useTranslations("auth");
  const [loading, setLoading] = useState(false);

  if (!enabled) return null;

  const start = async () => {
    setLoading(true);
    const { error } = await authClient.signIn.oauth2({
      providerId: FEISHU_PROVIDER_ID,
      callbackURL,
      errorCallbackURL: "/login?error=feishu",
    });
    if (error) {
      const key = authErrorKey(error);
      toast.error(key ? t(`errors.${key}`) : t("feishu.failed"));
      setLoading(false);
    }
  };

  return (
    <SsoMarkButton onClick={start} disabled={loading} label={t("feishu.name")} title={t("feishu.signIn")}>
      {loading ? (
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      ) : (
        // The official mark, straight from feishu.cn. It is a three-tone swallow
        // on transparent, so it is never tinted — SsoMarkButton gives it the
        // white plate it is drawn for.
        <Image src="/brand/feishu-mark.png" alt="" width={26} height={26} className="h-[26px] w-[26px]" />
      )}
    </SsoMarkButton>
  );
}
