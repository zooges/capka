import { describe, expect, it } from "vitest";
import { isLocale, matchAcceptLanguage, locales } from "../config";
import { toLocale } from "@/lib/i18n/translator";

describe("i18n locales", () => {
  it("includes zh-CN", () => {
    expect(locales).toContain("zh-CN");
    expect(isLocale("zh-CN")).toBe(true);
  });

  it("maps Chinese Accept-Language tags to zh-CN", () => {
    expect(matchAcceptLanguage("zh-CN,zh;q=0.9,en;q=0.8")).toBe("zh-CN");
    expect(matchAcceptLanguage("zh-Hans-CN,zh;q=0.9")).toBe("zh-CN");
    expect(matchAcceptLanguage("zh;q=1")).toBe("zh-CN");
  });

  it("resolves en; Ukrainian is not a shipped locale", () => {
    expect(matchAcceptLanguage("uk-UA,uk;q=0.9")).toBeNull();
    expect(isLocale("uk")).toBe(false);
    expect(matchAcceptLanguage("en-US,en;q=0.9")).toBe("en");
    expect(locales).not.toContain("uk");
  });
});

describe("toLocale", () => {
  it("maps zh tags to zh-CN", () => {
    expect(toLocale("zh-CN")).toBe("zh-CN");
    expect(toLocale("zh")).toBe("zh-CN");
    expect(toLocale("zh-Hans")).toBe("zh-CN");
  });
});
