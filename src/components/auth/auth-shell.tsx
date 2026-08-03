"use client";

import type { ReactNode } from "react";
import { BrandHero } from "@/components/brand/brand-lockup";
import { productName } from "@/lib/brand";

/** Shared field styling for auth/setup forms — filled, rounded, calm. */
export const AUTH_FIELD =
  "h-11 rounded-xl border-transparent bg-muted/60 px-3.5 text-[15px] font-sans focus-visible:border-ring focus-visible:bg-card";

/**
 * Sign-in / register chrome with the official Boss & Young wordmark.
 * Mobile / native shell: flat full-bleed (no floating card). Desktop keeps the card.
 */
export function AuthShell({
  title,
  description,
  children,
  footer,
}: {
  title: string;
  description?: ReactNode;
  children: ReactNode;
  footer?: ReactNode;
}) {
  const brand = productName();
  return (
    <div className="relative min-h-dvh overflow-x-hidden bg-background font-sans">
      {/* Soft wash — desktop only; mobile stays flat. */}
      <div className="pointer-events-none absolute left-1/2 top-1/2 hidden h-[40vmin] w-[40vmin] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle,color-mix(in_oklch,#8B1E23_10%,transparent),transparent_70%)] opacity-50 md:block" />

      {/* Mobile/native: center in the safe region (was top-pinned under the status bar). */}
      <div
        className={[
          "relative flex min-h-dvh flex-col justify-center overflow-y-auto overscroll-contain",
          "px-6 pt-[max(1.5rem,var(--capka-sat,env(safe-area-inset-top,0px)))] pb-[max(1.5rem,var(--capka-sab,env(safe-area-inset-bottom,0px)))]",
          "md:items-center md:px-5 md:py-12",
        ].join(" ")}
      >
        <div
          className={[
            "flex w-full flex-col",
            // Desktop: centered card. Mobile stays flat full-bleed.
            "md:max-w-md md:animate-card-morph md:rounded-[1.75rem] md:border md:border-border/60 md:bg-card md:p-8 md:shadow-[0_1px_2px_oklch(0_0_0/0.05),0_28px_60px_-32px_oklch(0.2_0.01_60/0.28)] md:pt-8 md:pb-8",
          ].join(" ")}
        >
          <div className="flex flex-col items-center gap-3 text-center">
            <BrandHero size="sm" />
            <span className="sr-only">{brand}</span>
          </div>

          <div className="mt-8 space-y-6 md:mt-7 md:animate-blur-rise">
            <div className="space-y-1.5">
              <h1 className="font-sans text-2xl font-semibold leading-snug tracking-tight text-balance text-foreground">
                {title}
              </h1>
              {description && (
                <p className="font-sans text-sm leading-relaxed text-muted-foreground text-pretty">
                  {description}
                </p>
              )}
            </div>
            {children}
          </div>

          {footer && (
            <div className="auth-shell-footer mt-6 hidden text-center font-sans text-sm text-muted-foreground md:block">
              {footer}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
