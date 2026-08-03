"use client";

import { useEffect } from "react";

/**
 * Dev-only guard for a Next.js / React Turbopack bug: performance.measure() is
 * called with a negative timestamp when an RSC aborts (e.g. redirect()). That
 * throws a Runtime TypeError overlay even though the page works. Swallow only
 * that specific browser error; leave real measure failures intact.
 *
 * @see https://github.com/vercel/next.js/issues/86060
 */
export function DevPerfMeasureGuard() {
  useEffect(() => {
    if (process.env.NODE_ENV === "production") return;
    const perf = window.performance as Performance & { __capkaMeasurePatched?: boolean };
    if (!perf?.measure || perf.__capkaMeasurePatched) return;

    const original = perf.measure.bind(perf);
    perf.__capkaMeasurePatched = true;
    perf.measure = ((...args: Parameters<Performance["measure"]>) => {
      try {
        return original(...args);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes("negative time stamp")) return undefined as unknown as PerformanceMeasure;
        throw err;
      }
    }) as Performance["measure"];
  }, []);

  return null;
}
