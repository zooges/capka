import { describe, it, expect } from "vitest";
import { serializeSignedCookie } from "better-call";
import { createHMAC } from "@better-auth/utils/hmac";
import { getWebcryptoSubtle } from "@better-auth/utils";
import { feishuNativeRedirectUri, feishuNativeUrlScheme } from "../feishu-oauth";

describe("feishu native redirect helpers", () => {
  it("builds the App ID URL scheme without underscores", () => {
    expect(feishuNativeUrlScheme("cli_aaeda20205b41ce4")).toBe("cliaaeda20205b41ce4");
    expect(feishuNativeRedirectUri("cli_aaeda20205b41ce4")).toBe("cliaaeda20205b41ce4://");
  });
});

describe("better-auth session cookie signing (native SSO)", () => {
  it("matches better-call format that getSignedCookie accepts (base64 + padding)", async () => {
    const secret = "test-master-key-for-native-sso";
    const token = "sess_native_token_abc";
    const cookie = await serializeSignedCookie("better-auth.session_token", token, secret, {
      path: "/",
      maxAge: 60,
      httpOnly: true,
      sameSite: "lax",
    });
    expect(cookie.startsWith("better-auth.session_token=")).toBe(true);

    const raw = cookie.slice("better-auth.session_token=".length).split(";")[0]!;
    const decoded = decodeURIComponent(raw);
    const dot = decoded.lastIndexOf(".");
    const value = decoded.slice(0, dot);
    const signature = decoded.slice(dot + 1);
    expect(value).toBe(token);
    // better-call getSignedCookie rejects anything else
    expect(signature.length).toBe(44);
    expect(signature.endsWith("=")).toBe(true);

    const algorithm = { name: "HMAC", hash: "SHA-256" } as const;
    const key = await getWebcryptoSubtle().importKey(
      "raw",
      new TextEncoder().encode(secret),
      algorithm,
      false,
      ["verify"],
    );
    const signatureBinStr = atob(signature);
    const sigBytes = new Uint8Array(signatureBinStr.length);
    for (let i = 0; i < signatureBinStr.length; i++) sigBytes[i] = signatureBinStr.charCodeAt(i);
    const ok = await getWebcryptoSubtle().verify(
      algorithm,
      key,
      sigBytes,
      new TextEncoder().encode(value),
    );
    expect(ok).toBe(true);
  });

  it("base64urlnopad signatures are NOT accepted by better-call checks", async () => {
    const secret = "test-master-key-for-native-sso";
    const token = "sess_native_token_abc";
    const bad = await createHMAC("SHA-256", "base64urlnopad").sign(secret, token);
    // This is what the buggy feishu-native minting used — length 43, no padding.
    expect(bad.length).toBe(43);
    expect(bad.endsWith("=")).toBe(false);
  });
});
