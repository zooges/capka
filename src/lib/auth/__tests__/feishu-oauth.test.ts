import { describe, it, expect, vi } from "vitest";
import {
  exchangeFeishuAuthorizationCode,
  FEISHU_TOKEN_URL,
  mapFeishuProfile,
  syntheticFeishuEmail,
  feishuRedirectUri,
  isFeishuInAppUserAgent,
} from "../feishu-oauth";

describe("mapFeishuProfile", () => {
  it("unwraps { code, data } and maps open_id", () => {
    expect(
      mapFeishuProfile({
        code: 0,
        data: { open_id: "ou_abc", name: "Ada", email: "ada@example.com", avatar_url: "https://x/a.png" },
      }),
    ).toEqual({
      openId: "ou_abc",
      unionId: undefined,
      name: "Ada",
      email: "ada@example.com",
      picture: "https://x/a.png",
    });
  });

  it("rejects Feishu error payloads (HTTP 200 + non-zero code)", () => {
    expect(mapFeishuProfile({ code: 20005, msg: "user_access_token is empty" })).toBeNull();
  });

  it("falls back to open_id when name is missing", () => {
    expect(mapFeishuProfile({ open_id: "ou_x" })?.name).toBe("ou_x");
  });
});

describe("syntheticFeishuEmail / feishuRedirectUri", () => {
  it("builds a stable placeholder email", () => {
    expect(syntheticFeishuEmail("ou-ab/c")).toBe("feishu_ou-ab_c@feishu.local");
  });

  it("builds the better-auth callback path", () => {
    expect(feishuRedirectUri("http://111.231.24.43:3100/")).toBe(
      "http://111.231.24.43:3100/api/auth/oauth2/callback/feishu",
    );
  });
});

describe("isFeishuInAppUserAgent", () => {
  it("detects Feishu / Lark clients and ignores Safari", () => {
    expect(
      isFeishuInAppUserAgent(
        "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 Mobile/15E148 Lark/7.20.0 LarkLocale/zh_CN",
      ),
    ).toBe(true);
    expect(
      isFeishuInAppUserAgent(
        "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1",
      ),
    ).toBe(false);
  });
});

describe("exchangeFeishuAuthorizationCode", () => {
  it("POSTs JSON (not form-urlencoded) and maps tokens", async () => {
    const fetchImpl = vi.fn(async (_url: string, init?: RequestInit) => {
      expect(_url).toBe(FEISHU_TOKEN_URL);
      expect(init?.method).toBe("POST");
      expect(String(init?.headers && (init.headers as Record<string, string>)["Content-Type"])).toMatch(
        /application\/json/,
      );
      const body = JSON.parse(String(init?.body));
      expect(body).toMatchObject({
        grant_type: "authorization_code",
        client_id: "cli_x",
        client_secret: "sec",
        code: "authcode",
        redirect_uri: "http://example/api/auth/oauth2/callback/feishu",
        code_verifier: "verifier",
      });
      return new Response(
        JSON.stringify({
          code: 0,
          access_token: "tok",
          token_type: "Bearer",
          expires_in: 7200,
          scope: "contact:user.base:readonly",
        }),
        { status: 200 },
      );
    });

    const tokens = await exchangeFeishuAuthorizationCode({
      clientId: "cli_x",
      clientSecret: "sec",
      code: "authcode",
      redirectURI: "http://example/api/auth/oauth2/callback/feishu",
      codeVerifier: "verifier",
      fetchImpl: fetchImpl as unknown as typeof fetch,
    });
    expect(tokens.accessToken).toBe("tok");
    expect(tokens.scopes).toEqual(["contact:user.base:readonly"]);
    expect(tokens.accessTokenExpiresAt).toBeInstanceOf(Date);
  });

  it("throws with Feishu error_description when code != 0", async () => {
    const fetchImpl = vi.fn(async () =>
      new Response(
        JSON.stringify({
          code: 20049,
          error: "invalid_grant",
          error_description: "PKCE code challenge failed.",
        }),
        { status: 400 },
      ),
    );
    await expect(
      exchangeFeishuAuthorizationCode({
        clientId: "cli_x",
        clientSecret: "sec",
        code: "x",
        redirectURI: "http://example/cb",
        fetchImpl: fetchImpl as unknown as typeof fetch,
      }),
    ).rejects.toThrow(/PKCE code challenge failed/);
  });
});
