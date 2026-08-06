"use client";

import { useState } from "react";
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
 * Picking updates local state only (chip label) — no full-page navigation. The
 * parent persists the choice onto an empty chat / first send. Chats that already
 * have history keep their locked project (server rejects retarget); the parent
 * may open a fresh chat when the user picks a different project then.
 */
export function ProjectChip({
  projectId,
  projectName,
  onChange,
  disabled,
}: {
  projectId?: string;
  projectName?: string;
  onChange?: (project: ProjectOption | null) => void;
  disabled?: boolean;
}) {
  const t = useTranslations("chat.panel");
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

  const pick = (p: ProjectOption | null) => {
    onChange?.(p);
  };

  return (
    <DropdownMenu onOpenChange={(open) => open && load()}>
      <DropdownMenuTrigger
        disabled={disabled}
        title={projectName ?? t("selectProject")}
        aria-label={projectName ? `${t("project")}: ${projectName}` : t("selectProject")}
        className={cn(
          "inline-flex max-w-[10rem] items-center gap-1.5 rounded-full px-2.5 py-1.5 text-xs transition-colors",
          projectName
            ? "bg-accent font-medium text-foreground"
            : "border text-muted-foreground hover:text-foreground",
          disabled && "pointer-events-none opacity-50",
        )}
      >
        {projectName ? <Folder className="h-3.5 w-3.5 shrink-0" /> : <FolderPlus className="h-3.5 w-3.5 shrink-0" />}
        <span className="truncate">{projectName ?? t("selectProject")}</span>
      </DropdownMenuTrigger>

      <DropdownMenuContent align="start" className="max-h-72 w-56 overflow-y-auto">
        <DropdownMenuItem onClick={() => pick(null)}>
          <span className="flex-1">{t("noProject")}</span>
          {!projectId && <Check className="h-3.5 w-3.5" />}
        </DropdownMenuItem>
        {projects && projects.length > 0 && <DropdownMenuSeparator />}
        {projects?.map((p) => (
          <DropdownMenuItem key={p.id} onClick={() => pick(p)}>
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
