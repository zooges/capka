"use client";

import { useCallback, useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { Loader2, Copy, Check, Send, ArrowRight } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

type Mode = "open" | "approval" | "closed";
interface ProviderCfg {
  enabledToggle: boolean;
  ready: boolean;
  clientId: string;
  hasClientSecret: boolean;
  redirectUri: string;
}
interface Config {
  telegram: ProviderCfg;
  feishu: ProviderCfg;
  registrationMode: Mode;
  emailSignupEnabled: boolean;
}

export default function AuthenticationPage() {
  const t = useTranslations("settings.authentication");

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [enabled, setEnabled] = useState(false);
  const [clientId, setClientId] = useState("");
  const [clientSecret, setClientSecret] = useState("");
  const [hasSecret, setHasSecret] = useState(false);
  const [redirectUri, setRedirectUri] = useState("");
  const [feishuEnabled, setFeishuEnabled] = useState(false);
  const [feishuClientId, setFeishuClientId] = useState("");
  const [feishuClientSecret, setFeishuClientSecret] = useState("");
  const [feishuHasSecret, setFeishuHasSecret] = useState(false);
  const [feishuRedirectUri, setFeishuRedirectUri] = useState("");
  const [mode, setMode] = useState<Mode>("closed");
  const [emailSignup, setEmailSignup] = useState(true);
  const [copied, setCopied] = useState<"tg" | "feishu" | null>(null);

  const load = useCallback(async () => {
    try {
      const res = await fetch("/api/admin/auth-config");
      if (res.ok) {
        const data: Config = await res.json();
        setEnabled(data.telegram.enabledToggle);
        setClientId(data.telegram.clientId);
        setHasSecret(data.telegram.hasClientSecret);
        setRedirectUri(data.telegram.redirectUri);
        setFeishuEnabled(data.feishu.enabledToggle);
        setFeishuClientId(data.feishu.clientId);
        setFeishuHasSecret(data.feishu.hasClientSecret);
        setFeishuRedirectUri(data.feishu.redirectUri);
        setMode(data.registrationMode);
        setEmailSignup(data.emailSignupEnabled);
      }
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => {
    load();
  }, [load]);

  const save = async () => {
    setSaving(true);
    try {
      const body: Record<string, unknown> = {
        enabled,
        registrationMode: mode,
        emailSignupEnabled: emailSignup,
        clientId: clientId.trim(),
        feishuEnabled,
        feishuClientId: feishuClientId.trim(),
      };
      if (clientSecret.trim()) body.clientSecret = clientSecret.trim();
      if (feishuClientSecret.trim()) body.feishuClientSecret = feishuClientSecret.trim();
      const res = await fetch("/api/admin/auth-config", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (res.ok) {
        toast.success(t("saved"));
        setClientSecret("");
        setFeishuClientSecret("");
        await load();
      } else {
        toast.error(t("saveFailed"));
      }
    } finally {
      setSaving(false);
    }
  };

  const copyRedirect = (which: "tg" | "feishu", value: string) => {
    navigator.clipboard.writeText(value);
    setCopied(which);
    toast.success(t("copied"));
    setTimeout(() => setCopied(null), 2000);
  };

  const modes: { key: Mode }[] = [{ key: "open" }, { key: "approval" }, { key: "closed" }];
  const ready = enabled && !!clientId.trim() && (hasSecret || !!clientSecret.trim());
  const feishuReady =
    feishuEnabled && !!feishuClientId.trim() && (feishuHasSecret || !!feishuClientSecret.trim());

  if (loading) {
    return (
      <div className="flex justify-center py-12">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="max-w-lg space-y-6">
      <div>
        <h2 className="text-base font-medium">{t("title")}</h2>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <Separator />

      {/* Telegram login provider */}
      <div className="space-y-4 rounded-md border p-4">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-start gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[#229ED9]/10">
              <Send className="h-4.5 w-4.5 text-[#229ED9]" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-sm font-medium">{t("telegram.title")}</h3>
                {enabled && (
                  <Badge variant={ready ? "secondary" : "outline"} className="text-xs">
                    {ready ? t("telegram.active") : t("telegram.incomplete")}
                  </Badge>
                )}
              </div>
              <p className="text-sm text-muted-foreground">{t("telegram.desc")}</p>
            </div>
          </div>
          <Switch checked={enabled} onCheckedChange={setEnabled} aria-label={t("telegram.toggleAria")} />
        </div>

        {enabled && (
          <div className="space-y-3 pt-1">
            <p className="text-xs text-muted-foreground">{t("telegram.botFatherHint")}</p>
            <div className="space-y-1.5">
              <Label htmlFor="clientId">{t("telegram.clientId")}</Label>
              <Input id="clientId" value={clientId} onChange={(e) => setClientId(e.target.value)} placeholder="8521897198" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="clientSecret">{t("telegram.clientSecret")}</Label>
              <Input
                id="clientSecret"
                type="password"
                value={clientSecret}
                onChange={(e) => setClientSecret(e.target.value)}
                placeholder={hasSecret ? t("telegram.secretStored") : t("telegram.secretPlaceholder")}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("telegram.redirectUri")}</Label>
              <div className="flex items-center gap-2">
                <code className="flex-1 truncate rounded-md bg-muted px-3 py-2 text-xs font-mono">{redirectUri}</code>
                <Button
                  variant="outline"
                  size="icon"
                  className="h-9 w-9 shrink-0"
                  onClick={() => copyRedirect("tg", redirectUri)}
                  aria-label={copied === "tg" ? t("copied") : t("copyRedirect")}
                >
                  {copied === "tg" ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                </Button>
              </div>
              <p className="text-xs text-muted-foreground">{t("telegram.redirectHint")}</p>
            </div>
          </div>
        )}
      </div>

      {/* Feishu login provider */}
      <div className="space-y-4 rounded-md border p-4">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-start gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[#3370ff]/10">
              <span className="text-sm font-semibold text-[#3370ff]">飞</span>
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-sm font-medium">{t("feishu.title")}</h3>
                {feishuEnabled && (
                  <Badge variant={feishuReady ? "secondary" : "outline"} className="text-xs">
                    {feishuReady ? t("feishu.active") : t("feishu.incomplete")}
                  </Badge>
                )}
              </div>
              <p className="text-sm text-muted-foreground">{t("feishu.desc")}</p>
            </div>
          </div>
          <Switch
            checked={feishuEnabled}
            onCheckedChange={setFeishuEnabled}
            aria-label={t("feishu.toggleAria")}
          />
        </div>

        {feishuEnabled && (
          <div className="space-y-3 pt-1">
            <p className="text-xs text-muted-foreground">{t("feishu.hint")}</p>
            <div className="space-y-1.5">
              <Label htmlFor="feishuClientId">{t("feishu.clientId")}</Label>
              <Input
                id="feishuClientId"
                value={feishuClientId}
                onChange={(e) => setFeishuClientId(e.target.value)}
                placeholder="cli_xxx"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="feishuClientSecret">{t("feishu.clientSecret")}</Label>
              <Input
                id="feishuClientSecret"
                type="password"
                value={feishuClientSecret}
                onChange={(e) => setFeishuClientSecret(e.target.value)}
                placeholder={feishuHasSecret ? t("feishu.secretStored") : t("feishu.secretPlaceholder")}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("feishu.redirectUri")}</Label>
              <div className="flex items-center gap-2">
                <code className="flex-1 truncate rounded-md bg-muted px-3 py-2 text-xs font-mono">
                  {feishuRedirectUri}
                </code>
                <Button
                  variant="outline"
                  size="icon"
                  className="h-9 w-9 shrink-0"
                  onClick={() => copyRedirect("feishu", feishuRedirectUri)}
                  aria-label={copied === "feishu" ? t("copied") : t("copyRedirect")}
                >
                  {copied === "feishu" ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                </Button>
              </div>
              <p className="text-xs text-muted-foreground">{t("feishu.redirectHint")}</p>
            </div>
          </div>
        )}
      </div>

      {/* Registration mode */}
      <div className="space-y-3">
        <div>
          <h3 className="text-sm font-medium">{t("mode.title")}</h3>
          <p className="text-sm text-muted-foreground">{t("mode.desc")}</p>
        </div>
        <div className="grid gap-2">
          {modes.map(({ key }) => (
            <button
              key={key}
              type="button"
              onClick={() => setMode(key)}
              className={cn(
                "flex items-start gap-3 rounded-md border p-3 text-left transition-colors",
                mode === key ? "border-foreground/40 bg-accent" : "hover:bg-accent/40",
              )}
            >
              <div
                className={cn(
                  "mt-0.5 h-4 w-4 shrink-0 rounded-full border-2",
                  mode === key ? "border-foreground bg-foreground" : "border-muted-foreground/40",
                )}
              />
              <div>
                <p className="text-sm font-medium">{t(`mode.${key}.label`)}</p>
                <p className="text-xs text-muted-foreground">{t(`mode.${key}.desc`)}</p>
              </div>
            </button>
          ))}
        </div>
      </div>

      <div className="space-y-3 rounded-md border p-4">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h3 className="text-sm font-medium">{t("email.title")}</h3>
            <p className="text-sm text-muted-foreground">{t("email.desc")}</p>
          </div>
          <Switch checked={emailSignup} onCheckedChange={setEmailSignup} aria-label={t("email.toggleAria")} />
        </div>
        {!emailSignup && !ready && !feishuReady && (
          <p className="rounded-md border border-warning-border bg-warning-surface px-3 py-2 text-xs text-foreground">
            {t("email.deadEndWarning")}
          </p>
        )}
      </div>

      <div className="flex justify-end">
        <Button onClick={save} disabled={saving}>
          {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
          {t("save")}
        </Button>
      </div>

      {mode === "approval" && (
        <Link
          href="/settings/users"
          className="flex items-center justify-between gap-3 rounded-md border px-4 py-3 text-sm transition-colors hover:bg-accent/40"
        >
          <span className="text-muted-foreground">{t("pending.moved")}</span>
          <ArrowRight className="h-4 w-4 shrink-0 text-muted-foreground" />
        </Link>
      )}
    </div>
  );
}
