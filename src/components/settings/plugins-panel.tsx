"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { Package, Store } from "lucide-react";
import { cn } from "@/lib/utils";
import InstalledPlugins from "@/components/settings/installed-plugins";
import { MarketplaceBrowser } from "@/components/settings/marketplace-browser";
import MemberPluginBrowser from "@/components/settings/member-plugin-browser";

export type PluginsView = "installed" | "browse";

/** The Plugins hub (app-store pattern): "Installed" is what's added, "Browse" is the
 *  marketplace. Browse appears only for those allowed to install (admins always;
 *  members when the admin opted in). Admins get full marketplace management; members
 *  get a read-only browse that installs personally. */
export default function PluginsPanel({ view, onView }: { view: PluginsView; onView: (v: PluginsView) => void }) {
  const t = useTranslations("settings.skills.pluginsView");
  const [cap, setCap] = useState<{ isAdmin: boolean; canInstall: boolean } | null>(null);

  useEffect(() => {
    fetch("/api/extensions/capability")
      .then((r) => (r.ok ? r.json() : { isAdmin: false, canInstall: false }))
      .then(setCap)
      .catch(() => setCap({ isAdmin: false, canInstall: false }));
  }, []);

  // Until we know (or if browsing isn't allowed), just the installed list.
  if (!cap?.canInstall) return <InstalledPlugins />;

  const views: { key: PluginsView; label: string; icon: typeof Package }[] = [
    { key: "installed", label: t("installed"), icon: Package },
    { key: "browse", label: t("browse"), icon: Store },
  ];

  return (
    <div className="w-full min-w-0 space-y-4">
      <div className="flex w-full min-w-0 flex-wrap gap-1 rounded-lg border bg-muted/40 p-1">
        {views.map((v) => (
          <button
            key={v.key}
            onClick={() => onView(v.key)}
            className={cn(
              "flex min-w-0 flex-1 items-center justify-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm transition-colors sm:flex-none sm:px-3",
              view === v.key ? "bg-card font-medium shadow-sm" : "text-muted-foreground hover:text-foreground",
            )}
          >
            <v.icon className="h-4 w-4 shrink-0" />
            <span className="truncate">{v.label}</span>
          </button>
        ))}
      </div>

      {view === "installed" ? <InstalledPlugins /> : cap.isAdmin ? <MarketplaceBrowser /> : <MemberPluginBrowser />}
    </div>
  );
}
