"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { authClient } from "@/lib/auth-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { AuthShell, AUTH_FIELD } from "@/components/auth/auth-shell";
import { TelegramSignIn, AuthDivider } from "@/components/auth/telegram-sign-in";
import { FeishuSignIn } from "@/components/auth/feishu-sign-in";
import { authErrorKey } from "@/lib/auth/client-error";
import { toast } from "sonner";

export default function LoginPage() {
  const router = useRouter();
  const t = useTranslations("auth");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [telegramEnabled, setTelegramEnabled] = useState<boolean | null>(null);
  const [feishuEnabled, setFeishuEnabled] = useState<boolean | null>(null);
  const [registrationEnabled, setRegistrationEnabled] = useState(false);
  // Keep OAuth failures visible even when the toast host mounts late / is missed.
  const [ssoError, setSsoError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/auth/registration-status")
      .then((r) => r.json())
      .then((d) => {
        setTelegramEnabled(!!d.telegram?.enabled);
        setFeishuEnabled(!!d.feishu?.enabled);
        setRegistrationEnabled(d.enabled !== false);
      })
      .catch(() => {
        setTelegramEnabled(false);
        setFeishuEnabled(false);
      });
    // Surface a failed SSO round-trip (the error callback redirects here).
    // better-auth may send error=feishu, or only a technical code
    // (state_mismatch / unable_to_get_user_info / account_not_linked / …).
    const p = new URLSearchParams(window.location.search);
    const errs = p.getAll("error").filter(Boolean);
    const detail =
      errs.find((e) => e !== "feishu" && e !== "telegram") ||
      p.get("error_description") ||
      null;
    if (errs.length === 0) return;
    const isTelegram = errs.includes("telegram") || errs[0] === "telegram";
    const message = isTelegram
      ? detail
        ? `${t("telegram.failed")} (${detail})`
        : t("telegram.failed")
      : detail === "account_not_linked"
        ? t("feishu.accountNotLinked")
        : detail
          ? `${t("feishu.failed")} (${detail})`
          : errs.includes("feishu")
            ? t("feishu.failed")
            : `${t("feishu.failed")} (${errs.join(", ")})`;
    setSsoError(message);
    toast.error(message);
    window.history.replaceState({}, "", "/login");
  }, [t]);
  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);

    const { error } = await authClient.signIn.email({
      email,
      password,
    });

    if (error) {
      const key = authErrorKey(error);
      toast.error(key ? t(`errors.${key}`) : t("login.invalidCredentials"));
      setLoading(false);
      return;
    }

    router.push("/chat");
  }

  return (
    <AuthShell
      title={t("login.title")}
      description={t("login.description")}
      footer={
        registrationEnabled ? (
          <>
            {t("login.noAccount")}{" "}
            <Link href="/register" className="font-medium text-foreground hover:underline">
              {t("login.createOne")}
            </Link>
          </>
        ) : undefined
      }
    >
      {ssoError && (
        <div
          role="alert"
          className="mb-4 rounded-xl border border-destructive/30 bg-destructive/10 px-3.5 py-3 text-sm text-destructive"
        >
          {ssoError}
        </div>
      )}
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="email">{t("emailLabel")}</Label>
          <Input
            id="email"
            type="email"
            placeholder="you@example.com"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            disabled={loading}
            autoFocus
            className={AUTH_FIELD}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="password">{t("passwordLabel")}</Label>
          <Input
            id="password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            disabled={loading}
            className={AUTH_FIELD}
          />
        </div>
        <Button type="submit" disabled={loading} className="h-11 w-full rounded-xl text-[15px]">
          {loading ? t("login.submitting") : t("login.submit")}
        </Button>
      </form>
      {/* SSO is the alternative, not the headline: credentials first, then the
          usual small brand marks underneath. */}
      {(telegramEnabled || feishuEnabled) && (
        <div className="mt-6 space-y-4">
          <AuthDivider label={t("otherSignIn")} />
          <div className="flex items-start justify-center gap-6">
            <FeishuSignIn enabled={feishuEnabled} />
            <TelegramSignIn enabled={telegramEnabled} />
          </div>
        </div>
      )}
    </AuthShell>
  );
}
