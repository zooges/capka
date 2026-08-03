/**
 * Boss & Young brand — official PNG wordmark (correct typefaces) + B mark.
 * Sized by height so the full lockup stays visible and never dominates the UI.
 */
import Image from "next/image";
import { cn } from "@/lib/utils";

type MarkSize = "sm" | "md" | "lg" | "xl";

const MARK_BOX: Record<MarkSize, string> = {
  sm: "h-7 w-7",
  md: "h-9 w-9",
  lg: "h-12 w-12",
  xl: "h-16 w-16",
};

const MARK_PX: Record<MarkSize, number> = {
  sm: 28,
  md: 36,
  lg: 48,
  xl: 64,
};

/** Official square B emblem — burgundy on transparent. */
export function BrandMark({
  className,
  size = "md",
  animated,
}: {
  className?: string;
  size?: MarkSize;
  animated?: boolean;
}) {
  void animated;
  return (
    <span className={cn("relative inline-flex shrink-0", MARK_BOX[size], className)}>
      <Image
        src="/brand/boss-young-mark-light.png"
        alt=""
        width={MARK_PX[size]}
        height={MARK_PX[size]}
        className="h-full w-full object-contain"
        priority
      />
    </span>
  );
}

type WordmarkSize = "sm" | "md" | "lg";

/** Display height for the horizontal lockup — keep compact so nothing clips. */
const WORDMARK_H: Record<WordmarkSize, string> = {
  sm: "h-9", // ~36px — login / compact chrome
  md: "h-11", // ~44px — chat empty state
  lg: "h-14", // ~56px — rare large surfaces
};

/**
 * Official horizontal lockup PNG (邦信阳律师事务所 / BOSS & YOUNG).
 * Height-capped + width:auto so the full artwork shows at a modest size.
 * Light mode keeps the dark-type wordmark; dark mode swaps to the white-type
 * on-dark asset so the name stays readable on charcoal surfaces.
 */
export function BrandWordmark({
  className,
  priority = false,
  size = "sm",
}: {
  className?: string;
  priority?: boolean;
  size?: WordmarkSize;
}) {
  const frame = cn(
    WORDMARK_H[size],
    "w-auto max-w-full object-contain object-center",
    className,
  );
  return (
    <span className="relative inline-flex max-w-full items-center justify-center">
      <Image
        src="/brand/boss-young-wordmark-light.png"
        alt="邦信阳律师事务所 BOSS & YOUNG"
        width={617}
        height={127}
        sizes="280px"
        className={cn(frame, "dark:hidden")}
        style={{ width: "auto" }}
        priority={priority}
      />
      <Image
        src="/brand/boss-young-wordmark-on-dark.png"
        alt="邦信阳律师事务所 BOSS & YOUNG"
        width={617}
        height={127}
        sizes="280px"
        className={cn(frame, "hidden dark:block")}
        style={{ width: "auto" }}
        priority={priority}
      />
    </span>
  );
}

/** Homepage / auth hero — compact official wordmark. */
export function BrandHero({
  className,
  size = "sm",
}: {
  className?: string;
  size?: WordmarkSize;
}) {
  return (
    <div
      className={cn(
        "relative z-10 mx-auto flex w-full items-center justify-center overflow-visible",
        className,
      )}
      aria-label="邦信阳律师事务所 BOSS & YOUNG"
    >
      <BrandWordmark priority size={size} className="mx-auto" />
    </div>
  );
}

export function BossYoungEmblem({ className }: { className?: string }) {
  return <BrandMark size="md" className={className} />;
}

export function BrandLockup({
  className,
  size = "md",
  stacked = false,
}: {
  className?: string;
  size?: "sm" | "md" | "lg" | "hero";
  stacked?: boolean;
}) {
  if (size === "hero" || stacked) {
    return <BrandHero className={className} size="md" />;
  }
  const markSize: MarkSize = size === "sm" ? "sm" : size === "lg" ? "lg" : "md";
  return (
    <span className={cn("inline-flex items-center gap-2", className)} aria-label="Boss & Young">
      <BrandMark size={markSize} />
    </span>
  );
}
