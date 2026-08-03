import { describe, it, expect } from "vitest";
import { getPublicUrl, resolveTrustedAuthOrigins, parseTrustedOrigins } from "../url";

describe("getPublicUrl", () => {
  it("prefers explicit PUBLIC_URL over everything", () => {
    const headers = new Headers({ host: "internal:3000", "x-forwarded-proto": "http" });
    expect(getPublicUrl({ env: { PUBLIC_URL: "https://app.example.com" }, headers })).toBe(
      "https://app.example.com",
    );
  });

  it("trims a trailing slash from PUBLIC_URL", () => {
    expect(getPublicUrl({ env: { PUBLIC_URL: "https://app.example.com/" } })).toBe(
      "https://app.example.com",
    );
  });

  it("treats a blank PUBLIC_URL as unset", () => {
    const headers = new Headers({ host: "example.com", "x-forwarded-proto": "https" });
    expect(getPublicUrl({ env: { PUBLIC_URL: "   " }, headers })).toBe("https://example.com");
  });

  it("derives from X-Forwarded-Proto and X-Forwarded-Host behind a proxy", () => {
    const headers = new Headers({
      host: "platform:3000",
      "x-forwarded-host": "capka.example.com",
      "x-forwarded-proto": "https",
    });
    expect(getPublicUrl({ env: {}, headers })).toBe("https://capka.example.com");
  });

  it("takes the first value when X-Forwarded-Proto is a comma list", () => {
    const headers = new Headers({ host: "example.com", "x-forwarded-proto": "https, http" });
    expect(getPublicUrl({ env: {}, headers })).toBe("https://example.com");
  });

  it("falls back to the Host header with http when no forwarded proto", () => {
    const headers = new Headers({ host: "example.com" });
    expect(getPublicUrl({ env: {}, headers })).toBe("http://example.com");
  });

  it("falls back to localhost when there is nothing to derive from", () => {
    expect(getPublicUrl({ env: {} })).toBe("http://localhost:3000");
  });
});

describe("resolveTrustedAuthOrigins", () => {
  it("parses TRUSTED_ORIGINS list", () => {
    expect(parseTrustedOrigins("http://10.0.40.100:3100, http://127.0.0.1:3100/")).toEqual([
      "http://10.0.40.100:3100",
      "http://127.0.0.1:3100",
    ]);
  });

  it("includes PUBLIC_URL, extras, and the request Host origin", () => {
    const headers = new Headers({ host: "10.0.40.100:3100" });
    expect(
      resolveTrustedAuthOrigins({
        env: {
          PUBLIC_URL: "https://agent.example.com",
          TRUSTED_ORIGINS: "http://10.0.40.100:3100",
        },
        headers,
      }).sort(),
    ).toEqual([
      "http://10.0.40.100:3100",
      "https://agent.example.com",
    ].sort());
  });
});
