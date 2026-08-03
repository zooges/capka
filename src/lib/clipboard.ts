/**
 * Clipboard write that works in ordinary browsers AND Capka's iOS WKWebView shell.
 *
 * WKWebView often rejects `navigator.clipboard.writeText` without a permission
 * grant; the native shell polyfills it via `webkit.messageHandlers.capkaNative`
 * → UIPasteboard. We still keep an `execCommand('copy')` fallback for desktop
 * insecure contexts / older WebViews.
 */
export async function copyToClipboard(text: string): Promise<boolean> {
  if (typeof text !== "string") return false;

  // 1) Async Clipboard API (polyfilled on iOS native to postMessage → UIPasteboard).
  try {
    if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    /* fall through */
  }

  // 2) Explicit native bridge (in case polyfill was overwritten by a SPA chunk).
  try {
    const w = typeof window !== "undefined" ? (window as Window & {
      webkit?: { messageHandlers?: { capkaNative?: { postMessage: (m: unknown) => void } } };
      CapkaNativeApp?: { copyText?: (t: string) => boolean | Promise<boolean> };
    }) : undefined;
    if (w?.CapkaNativeApp?.copyText) {
      const ok = await w.CapkaNativeApp.copyText(text);
      if (ok) return true;
    }
    if (w?.webkit?.messageHandlers?.capkaNative) {
      w.webkit.messageHandlers.capkaNative.postMessage({ type: "clipboardWrite", text });
      return true;
    }
  } catch {
    /* fall through */
  }

  // 3) Legacy execCommand — works in many WebViews when called from a click handler.
  try {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.top = "0";
    ta.style.left = "0";
    ta.style.width = "1px";
    ta.style.height = "1px";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    ta.setSelectionRange(0, ta.value.length);
    const ok = document.execCommand("copy");
    document.body.removeChild(ta);
    return ok;
  } catch {
    return false;
  }
}
