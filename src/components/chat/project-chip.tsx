"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { Folder, FolderPlus, Check } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";

type ProjectOption = { id: string; name: string };

/**
 * The project a chat runs in, chosen from the composer.
 *
 * Not a label: sessions are keyed by `projectId ?? chatId`, so a chat in a
 * project runs in that project's shared sandbox and workspace, starting with its
 * files and instructions in hand. Putting the control beside the attach button
 * and the model picker is what makes that legible — the working context, then
 * what you add to it, then who answers.
 *
 * Picking navigates to a fresh chat in that project rather than re-homing the
 * current one: an existing chat keeps the sandbox it was created in (moving one
 * is the project hub's job). This is the same rule the iOS client follows.
 */
export function ProjectChip({ projectId, projectName }: { projectId?: string; projectName?: string }) {
  const t = useTranslations("chat.panel");
  const router = useRouter();
  const [projects, setProjects] = useState<ProjectOption[] | null>(null);

  // Loaded on first open, not on mount: most chats never touch this control and
  // the composer shouldn't cost a request it probably doesn't need.
  const load = () => {
    if (projects) return;
    fetch("/api/projects")
      .then((r) => (r.ok ? r.json() : []))
      .then((rows: ProjectOption[]) => setProjects(Array.isArray(rows) ? rows : []))
      .catch(() => setProjects([]));
  };

  const go = (id?: string) => router.push(id ? `/chat?projectId=${encodeURIComponent(id)}` : "/chat");

  return (
    <DropdownMenu onOpenChange={(open) => open && load()}>
      <DropdownMenuTrigger
        title={projectName ?? t("selectProject")}
        aria-label={projectName ? `${t("project")}: ${projectName}` : t("selectProject")}
        className={cn(
          "inline-flex max-w-[10rem] items-center gap-1.5 rounded-full px-2.5 py-1.5 text-xs transition-colors",
          projectName
            ? "bg-accent font-medium text-foreground"
            : "border text-muted-foreground hover:text-foreground",
        )}
      >
        {projectName ? <Folder className="h-3.5 w-3.5 shrink-0" /> : <FolderPlus className="h-3.5 w-3.5 shrink-0" />}
        <span className="truncate">{projectName ?? t("selectProject")}</span>
      </DropdownMenuTrigger>

      <DropdownMenuContent align="start" className="max-h-72 w-56 overflow-y-auto">
        <DropdownMenuItem onSelect={() => go(undefined)}>
          <span className="flex-1">{t("noProject")}</span>
          {!projectId && <Check className="h-3.5 w-3.5" />}
        </DropdownMenuItem>
        {projects && projects.length > 0 && <DropdownMenuSeparator />}
        {projects?.map((p) => (
          <DropdownMenuItem key={p.id} onSelect={() => go(p.id)}>
            <span className="flex-1 truncate">{p.name}</span>
            {p.id === projectId && <Check className="h-3.5 w-3.5 shrink-0" />}
          </DropdownMenuItem>
        ))}
        {projects?.length === 0 && (
          <p className="px-2 py-1.5 text-xs text-muted-foreground">{t("noProjectsYet")}</p>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
