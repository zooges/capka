import { useEffect } from "react";

/**
 * Publishes the on-screen keyboard's height as a `--kb` CSS variable on <html>,
 * so bottom-pinned UI (the chat composer) can lift above it via padding.
 *
 * Android Chrome shrinks the layout viewport for the keyboard (we ask for that
 * with `interactive-widget=resizes-content`), so there `innerHeight` already
 * tracks it and `--kb` stays ~0 — no double counting. iOS overlays the keyboard
 * without resizing layout, so we read the gap from `visualViewport` and expose
 * it here. Mount once, app-wide.
 *
 * In-chat / home docks use in-flow `padding-bottom: var(--kb)` (not
 * `translateY`). Subtracting `visualViewport.offsetTop` under-counts when WK
 * has scrolled the focused field and our pin resets that scroll — the composer
 * then sits under the keyboard. Pin first, then use the raw height gap.
 *
 * The iOS WK shell also injects `--native-kb` from UIKeyboard frame overlap;
 * we take the max so a flaky visualViewport still lifts the dock.
 */
export function useKeyboardInset() {
  useEffect(() => {
    const vv = window.visualViewport;
    const root = document.documentElement;
    if (!vv) return;

    const readNativeKb = () => {
      const raw = getComputedStyle(root).getPropertyValue("--native-kb").trim();
      if (!raw) return 0;
      const n = Number.parseFloat(raw);
      return Number.isFinite(n) ? Math.max(0, n) : 0;
    };

    const pinDocumentScroll = () => {
      // iOS often scrolls the layout under the keyboard (vv.offsetTop > 0). Undo
      // that so --kb padding alone owns the composer lift.
      if (
        window.scrollY ||
        window.scrollX ||
        root.scrollTop ||
        document.body?.scrollTop ||
        vv.offsetTop > 0 ||
        vv.offsetLeft > 0
      ) {
        window.scrollTo(0, 0);
        root.scrollTop = 0;
        if (document.body) document.body.scrollTop = 0;
      }
    };

    const update = () => {
      // Pin before measuring so residual offsetTop cannot shrink the inset.
      pinDocumentScroll();
      // Raw keyboard gap — do NOT subtract offsetTop (undercounts after pin).
      const webInset = Math.max(0, window.innerHeight - vv.height);
      const inset = Math.max(webInset, readNativeKb());
      // Snap tiny values to 0 — sub-pixel jitter from the scroll listener would
      // otherwise nudge the composer while idle.
      const open = inset > 24;
      root.style.setProperty("--kb", open ? `${Math.round(inset)}px` : "0px");
      // Lets CSS drop home-indicator padding under the composer while the
      // keyboard is up (avoids a solid “bar” between the input and keyboard).
      if (open) root.setAttribute("data-kb-open", "");
      else root.removeAttribute("data-kb-open");
    };

    // Chat composer already lifts via --kb. Browser/WK scroll-into-view on the
    // focused textarea double-counts and overlaps messages; only Settings forms
    // (narrow fields near the home indicator) still want a gentle scroll.
    const onFocusIn = (ev: FocusEvent) => {
      const el = ev.target;
      if (!(el instanceof HTMLElement)) return;
      const tag = el.tagName.toLowerCase();
      if (tag !== "input" && tag !== "textarea" && tag !== "select") return;
      if (el.closest("[data-capka-settings='1']")) return;
      if (el.closest("[data-capka-composer='1'], .capka-composer-pad")) {
        requestAnimationFrame(update);
        setTimeout(update, 50);
        setTimeout(update, 300);
      }
    };

    update();
    vv.addEventListener("resize", update);
    vv.addEventListener("scroll", update);
    window.addEventListener("scroll", pinDocumentScroll, { passive: true });
    document.addEventListener("focusin", onFocusIn, true);
    // Native shell pushes --native-kb asynchronously; remeasure when it lands.
    window.addEventListener("capka-native-kb", update);
    return () => {
      vv.removeEventListener("resize", update);
      vv.removeEventListener("scroll", update);
      window.removeEventListener("scroll", pinDocumentScroll);
      document.removeEventListener("focusin", onFocusIn, true);
      window.removeEventListener("capka-native-kb", update);
      root.style.removeProperty("--kb");
      root.removeAttribute("data-kb-open");
    };
  }, []);
}
