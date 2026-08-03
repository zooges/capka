import { describe, it, expect } from "vitest";
import { manageT, loc, locValue, keyOf } from "../i18n";
import { buildRegistry } from "../controls";

const reg = buildRegistry();

describe("manage/i18n", () => {
  it("keyOf flattens control-id dots so they don't nest", () => {
    expect(keyOf("user.locale")).toBe("user_locale");
    expect(keyOf("org.sandbox_network")).toBe("org_sandbox_network");
  });

  it("falls back to the English literal when a key is untranslated", () => {
    const t = manageT("zh-CN");
    expect(loc(t, "control.does_not_exist.title", "English default")).toBe("English default");
  });

  it("resolves a real Chinese translation when present", () => {
    const t = manageT("zh-CN");
    expect(loc(t, "control.user_locale.title", "Interface language")).not.toBe("Interface language");
  });

  it("English locale falls back to the in-code literals (no separate en catalog to drift)", () => {
    const t = manageT("en");
    expect(loc(t, "control.user_locale.title", "Interface language")).toBe("Interface language");
    expect(locValue(t, "org.sandbox_network", "bridge", "Network access")).toBe("Network access");
  });

  it("ANTI-DIVERGENCE: every registered control has a Chinese title translation", () => {
    const t = manageT("zh-CN");
    for (const c of reg.all()) {
      const localized = loc(t, `control.${keyOf(c.id)}.title`, c.title);
      expect(localized, `missing zh-CN translation for control.${keyOf(c.id)}.title`).not.toBe(c.title);
    }
  });

  it("ANTI-DIVERGENCE: every collection has a Chinese title translation", () => {
    const t = manageT("zh-CN");
    for (const coll of reg.collections()) {
      const localized = loc(t, `collection.${keyOf(coll.id)}`, coll.title);
      expect(localized, `missing zh-CN translation for collection.${keyOf(coll.id)}`).not.toBe(coll.title);
    }
  });
});
