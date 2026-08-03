"use client";

import { useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { Library, Plug, Package, MessageSquare } from "lucide-react";
import { cn } from "@/lib/utils";
import { useIsAdmin } from "@/hooks/use-is-admin";
import SkillLibrary from "@/components/settings/skill-library";
import ConnectorList from "@/components/settings/connector-list";
import PluginsPanel, { type PluginsView } from "@/components/settings/plugins-panel";

type Tab = "library" | "connectors" | "plugins";

export default function CustomizePage() {
  const t = useTranslations("settings.skills");
  const isAdmin = useIsAdmin();
  const [tab, setTab] = useState<Tab>("library");
  const [pluginsView, setPluginsView] = useState<PluginsView>("installed");

  // Honor ?tab= (old /settings/{marketplace,connectors} redirects, the MCP OAuth
  // round-trip, and the library's "Browse marketplace" link). Marketplace is now
  // the Browse view inside the merged Plugins tab.
  //
  // Must read the LIVE param, not window.location.search once on mount: the
  // "Browse marketplace" button links to this same pathname with a different
  // query, so React never remounts this page (RouteTransition keys its boundary
  // by pathname) and a mount-only effect never re-ran — the URL changed and the
  // view didn't, which is exactly how that button looked broken.
  const tabParam = useSearchParams().get("tab");
  useEffect(() => {
    if (tabParam === "connectors") setTab("connectors");
    else if (tabParam === "installed" || tabParam === "plugins") setTab("plugins");
    else if (tabParam === "marketplace") {
      setTab("plugins");
      setPluginsView("browse");
    }
  }, [tabParam]);

  const tabs: { key: Tab; label: string; icon: typeof Library; adminOnly?: boolean }[] = [
    { key: "library", label: t("tab.library"), icon: Library },
    { key: "connectors", label: t("tab.connectors"), icon: Plug },
    // Plugins is visible to everyone (read-only + per-user OAuth sign-in); only
    // admins get the management actions + the Browse/marketplace view inside it.
    { key: "plugins", label: t("tab.installed"), icon: Package },
  ];
  const visibleTabs = tabs.filter((tb) => !tb.adminOnly || isAdmin);
  const active = visibleTabs.some((tb) => tb.key === tab) ? tab : "library";

  return (
    <div className="w-full min-w-0 max-w-2xl space-y-6">
      <div className="min-w-0">
        <h2 className="text-base font-medium">{t("title")}</h2>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
        <p className="mt-1 flex min-w-0 items-start gap-1.5 text-xs text-muted-foreground/80">
          <MessageSquare className="mt-0.5 h-3 w-3 shrink-0" />
          <span className="min-w-0 break-words">{t("chatHint")}</span>
        </p>
      </div>

      {/* Segmented control — wrap on narrow phones so Connectors never clips */}
      <div
        role="tablist"
        className="flex w-full min-w-0 flex-wrap gap-1 rounded-lg border bg-muted/40 p-1"
      >
        {visibleTabs.map((tb) => (
          <button
            key={tb.key}
            role="tab"
            aria-selected={active === tb.key}
            onClick={() => setTab(tb.key)}
            className={cn(
              "flex min-w-0 flex-1 items-center justify-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm transition-colors sm:flex-none sm:px-3",
              active === tb.key ? "bg-card font-medium shadow-sm" : "text-muted-foreground hover:text-foreground",
            )}
          >
            <tb.icon className="h-4 w-4 shrink-0" />
            <span className="truncate">{tb.label}</span>
          </button>
        ))}
      </div>

      {active === "library" && <SkillLibrary chrome={false} />}
      {active === "connectors" && <ConnectorList chrome={false} />}
      {active === "plugins" && <PluginsPanel view={pluginsView} onView={setPluginsView} />}
    </div>
  );
}
