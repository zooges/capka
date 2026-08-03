import { SidebarTrigger } from "@/components/ui/sidebar";

export function Header({ title, children }: { title?: string; children?: React.ReactNode }) {
  return (
    <header className="sticky top-0 z-20 flex min-w-0 shrink-0 items-center gap-2 bg-background px-4 pb-2 pt-[max(0.75rem,var(--capka-sat,env(safe-area-inset-top,0px)))] pl-[max(1rem,var(--capka-sal,env(safe-area-inset-left,0px)))] pr-[max(1rem,var(--capka-sar,env(safe-area-inset-right,0px)))]">
      {/* On mobile the sidebar is an off-canvas sheet with no always-visible
          handle, so every page header carries the trigger to open it. Hidden
          on md+ where the sidebar is docked. */}
      <SidebarTrigger className="-ml-1 size-9 shrink-0 md:hidden" />
      {children}
      {title && <h1 className="truncate text-base font-medium">{title}</h1>}
    </header>
  );
}
