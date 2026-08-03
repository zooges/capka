import { completeFeishuNativeSignIn } from "@/lib/auth/feishu-native";
import { getRequestOrigin, getPublicUrl } from "@/lib/url";

export const dynamic = "force-dynamic";

/** Rewrite Docker bind URL so redirects land on the browser Host (IP). */
function withBrowserOrigin(request: Request): Request {
  const origin =
    getRequestOrigin(request.headers) || getPublicUrl({ headers: request.headers });
  const incoming = new URL(request.url);
  const fixed = new URL(incoming.pathname + incoming.search, origin);
  if (fixed.origin === incoming.origin) return request;
  return new Request(fixed.toString(), request);
}

function wantsJson(request: Request): boolean {
  const accept = request.headers.get("accept") || "";
  return accept.includes("application/json");
}

/**
 * Feishu Mobile SSO (LarkSSO) landing: iOS shell opens this after Feishu returns
 * a code via the native URL scheme. Completes login and Set-Cookies the session.
 */
export async function GET(request: Request) {
  const req = withBrowserOrigin(request);
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  if (!code) {
    return Response.redirect(new URL("/login?error=feishu", req.url).toString(), 302);
  }
  return completeFeishuNativeSignIn({
    code,
    codeVerifier: url.searchParams.get("code_verifier") || undefined,
    request: req,
    responseMode: wantsJson(req) ? "json" : "redirect",
  });
}

export async function POST(request: Request) {
  const req = withBrowserOrigin(request);
  const body = (await req.json().catch(() => null)) as {
    code?: string;
    codeVerifier?: string;
  } | null;
  if (!body?.code) {
    return Response.json({ error: "code required" }, { status: 400 });
  }
  return completeFeishuNativeSignIn({
    code: body.code,
    codeVerifier: body.codeVerifier,
    request: req,
    // iOS URLSession always asks for JSON so we can inject the cookie then load /chat.
    responseMode: wantsJson(req) ? "json" : "redirect",
  });
}
