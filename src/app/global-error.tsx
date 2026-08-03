"use client"; // Error boundaries must be Client Components

import { useEffect } from "react";
import "./globals.css";

/**
 * Last-resort boundary for errors in the root layout itself. It replaces the
 * root layout, so there is no i18n provider, theme script, or fonts here — the
 * copy is inlined in both languages and picked from the browser locale. Keep it
 * dependency-free and guaranteed-readable.
 */
const COPY = {
  en: {
    title: "Something went wrong",
    message: "The app ran into an unexpected problem. Please reload the page.",
    retry: "Reload",
  },
  zh: {
    title: "出了点问题",
    message: "应用遇到了意外错误，请重新加载页面。",
    retry: "重新加载",
  },
} as const;

export default function GlobalError({
  error,
  unstable_retry,
  reset,
}: {
  error: Error & { digest?: string };
  unstable_retry?: () => void;
  reset?: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  const isZh =
    typeof navigator !== "undefined" && navigator.language?.toLowerCase().startsWith("zh");
  const lang = isZh ? "zh" : "en";
  const t = COPY[lang];
  const retry = unstable_retry ?? reset ?? (() => window.location.reload());

  return (
    <html lang={lang}>
      <body
        style={{ background: "oklch(1 0 0)", color: "oklch(0.21 0.006 285.885)" }}
        className="bg-background text-foreground"
      >
        <div className="flex min-h-[100dvh] w-full flex-col items-center justify-center gap-5 p-6 text-center">
          <div className="space-y-1.5">
            <h1 className="text-lg font-semibold">{t.title}</h1>
            <p className="mx-auto max-w-sm text-sm opacity-70">{t.message}</p>
          </div>
          <button
            type="button"
            onClick={retry}
            className="inline-flex h-9 items-center justify-center rounded-lg bg-foreground px-4 text-sm font-medium text-background"
          >
            {t.retry}
          </button>
        </div>
      </body>
    </html>
  );
}
