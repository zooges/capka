"use client";

/**
 * A third-party sign-in choice rendered as its brand mark on a white plate, with
 * the provider name underneath — the conventional "other ways to sign in" row
 * that sits below the credential form, not above it.
 *
 * The plate is white in both themes on purpose: these marks are supplied as
 * full-colour artwork drawn for a light backdrop, and recolouring a trademark to
 * suit dark mode is not ours to do.
 */
export function SsoMarkButton({
  onClick,
  disabled,
  label,
  title,
  children,
}: {
  onClick: () => void;
  disabled?: boolean;
  label: string;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-1.5">
      <button
        type="button"
        onClick={onClick}
        disabled={disabled}
        title={title}
        aria-label={title}
        className="flex h-12 w-12 items-center justify-center rounded-full border bg-white shadow-sm transition-transform active:scale-[0.97] disabled:opacity-60 motion-reduce:transition-none motion-reduce:active:scale-100"
      >
        {children}
      </button>
      <span className="text-xs text-muted-foreground">{label}</span>
    </div>
  );
}
