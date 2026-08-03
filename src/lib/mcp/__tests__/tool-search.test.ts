import { describe, it, expect } from "vitest";
import type { Tool } from "ai";
import { planToolSearch, FIND_TOOL_NAME, deferTokenBudget } from "../tool-search";

/** A structural stand-in for an adapted tool — planToolSearch only reads
 *  `.description` and `.inputSchema.jsonSchema`. */
function fakeTool(description: string, schema: object = { type: "object", properties: {} }): Tool {
  return { description, inputSchema: { jsonSchema: schema } } as unknown as Tool;
}

/** A description padded so a handful of MCP tools comfortably cross a small budget. */
const bulky = (s: string) => `${s} ${"lorem ipsum dolor sit amet ".repeat(20)}`;

function callFind(plan: ReturnType<typeof planToolSearch>, query: string, limit?: number) {
  const find = plan.extraTools[FIND_TOOL_NAME] as unknown as {
    execute: (a: { query: string; limit?: number }) => Promise<{ matched: { name: string }[]; message: string }>;
  };
  return find.execute({ query, limit });
}

describe("planToolSearch — gating", () => {
  it("is inert when there are no MCP tools", () => {
    const plan = planToolSearch({
      tools: { bash: fakeTool("run a command"), skill: fakeTool("load a skill") },
      effectiveLimit: 1000,
    });
    expect(plan.defer).toBe(false);
    expect(plan.indexText).toBe("");
    expect(plan.extraTools).toEqual({});
    expect(plan.activeToolNames()).toBeUndefined();
  });

  it("does not defer when the connector block fits under the threshold", () => {
    const plan = planToolSearch({
      tools: { bash: fakeTool("x"), mcp__grok__search: fakeTool("search the web") },
      effectiveLimit: 1_000_000, // clamped budget is still far above one tiny tool
      maxTokens: 8192,
    });
    expect(plan.defer).toBe(false);
    expect(plan.activeToolNames()).toBeUndefined();
  });

  it("defers when the connector block exceeds the threshold", () => {
    const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
    for (let i = 0; i < 8; i++) tools[`mcp__firecrawl__firecrawl_tool_${i}`] = fakeTool(bulky(`tool ${i}`));
    const plan = planToolSearch({ tools, effectiveLimit: 2000 }); // budget 200 tokens
    expect(plan.defer).toBe(true);
    expect(plan.extraTools[FIND_TOOL_NAME]).toBeDefined();
    expect(plan.indexText).toContain("firecrawl");
  });

  it("defers on a 1M window when the absolute max is crossed (percent alone would not)", () => {
    // 10% of 1M = 100k — bulky tools fit under that, but not under maxTokens=500.
    const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
    for (let i = 0; i < 8; i++) tools[`mcp__firecrawl__firecrawl_tool_${i}`] = fakeTool(bulky(`tool ${i}`));
    const plan = planToolSearch({ tools, effectiveLimit: 1_000_000, thresholdPct: 10, maxTokens: 500 });
    expect(plan.defer).toBe(true);
    expect(plan.extraTools[FIND_TOOL_NAME]).toBeDefined();
  });

  it("always defers when thresholdPct is 0 (even a tiny connector set)", () => {
    const plan = planToolSearch({
      tools: { bash: fakeTool("x"), mcp__grok__search: fakeTool("search the web") },
      effectiveLimit: 1_000_000,
      thresholdPct: 0,
    });
    expect(plan.defer).toBe(true);
    expect(plan.extraTools[FIND_TOOL_NAME]).toBeDefined();
  });
});

describe("deferTokenBudget", () => {
  it("clamps the percent budget to the absolute max", () => {
    expect(deferTokenBudget(1_000_000, 10, 8192)).toBe(8192);
  });

  it("uses the percent budget when it is smaller than the max", () => {
    expect(deferTokenBudget(20_000, 10, 8192)).toBe(2000);
  });

  it("returns 0 when thresholdPct is 0 (always defer)", () => {
    expect(deferTokenBudget(1_000_000, 0, 8192)).toBe(0);
  });

  it("skips the absolute cap when maxTokens is 0", () => {
    expect(deferTokenBudget(1_000_000, 10, 0)).toBe(100_000);
  });
});

describe("planToolSearch — active-tool accounting", () => {
  const build = () => {
    const tools: Record<string, Tool> = { bash: fakeTool("run a command"), skill: fakeTool("load a skill") };
    for (let i = 0; i < 6; i++) tools[`mcp__firecrawl__firecrawl_tool_${i}`] = fakeTool(bulky(`tool ${i}`));
    return planToolSearch({ tools, effectiveLimit: 2000 });
  };

  it("starts with only the eager core + find_tool active (connector tools hidden)", () => {
    const prevRegion = process.env.CAPKA_REGION;
    const prevChina = process.env.CAPKA_CHINA;
    const prevAlways = process.env.MCP_ALWAYS_LOAD;
    delete process.env.CAPKA_REGION;
    delete process.env.CAPKA_CHINA;
    process.env.MCP_ALWAYS_LOAD = "none";
    try {
      const active = build().activeToolNames();
      expect(active).toContain("bash");
      expect(active).toContain("skill");
      expect(active).toContain(FIND_TOOL_NAME);
      expect(active!.some((n) => n.startsWith("mcp__"))).toBe(false);
    } finally {
      if (prevRegion === undefined) delete process.env.CAPKA_REGION;
      else process.env.CAPKA_REGION = prevRegion;
      if (prevChina === undefined) delete process.env.CAPKA_CHINA;
      else process.env.CAPKA_CHINA = prevChina;
      if (prevAlways === undefined) delete process.env.MCP_ALWAYS_LOAD;
      else process.env.MCP_ALWAYS_LOAD = prevAlways;
    }
  });

  it("preloads MCP_ALWAYS_LOAD / China-default tavily into activeTools", () => {
    const prevAlways = process.env.MCP_ALWAYS_LOAD;
    const prevRegion = process.env.CAPKA_REGION;
    delete process.env.CAPKA_REGION;
    delete process.env.CAPKA_CHINA;
    process.env.MCP_ALWAYS_LOAD = "tavily";
    try {
      const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
      for (let i = 0; i < 6; i++) tools[`mcp__firecrawl__firecrawl_tool_${i}`] = fakeTool(bulky(`tool ${i}`));
      tools["mcp__tavily__tavily_search"] = fakeTool(bulky("Search the web with Tavily"));
      tools["mcp__tavily__tavily_extract"] = fakeTool(bulky("Extract content from URLs"));
      const plan = planToolSearch({ tools, effectiveLimit: 2000 });
      const active = plan.activeToolNames()!;
      expect(active).toContain("mcp__tavily__tavily_search");
      expect(active).toContain("mcp__tavily__tavily_extract");
      expect(active.some((n) => n.startsWith("mcp__firecrawl__"))).toBe(false);
      expect(plan.indexText).toMatch(/tavily.*already configured/i);
    } finally {
      if (prevAlways === undefined) delete process.env.MCP_ALWAYS_LOAD;
      else process.env.MCP_ALWAYS_LOAD = prevAlways;
      if (prevRegion === undefined) delete process.env.CAPKA_REGION;
      else process.env.CAPKA_REGION = prevRegion;
    }
  });

  it("expands matched tools append-only across find_tool calls", async () => {
    const plan = build();
    const r1 = await callFind(plan, "tool 1");
    expect(r1.matched.length).toBeGreaterThan(0);
    const afterFirst = plan.activeToolNames()!;
    for (const m of r1.matched) expect(afterFirst).toContain(m.name);

    // A second call keeps the first call's matches active (append-only).
    await callFind(plan, "tool 3");
    const afterSecond = plan.activeToolNames()!;
    for (const m of r1.matched) expect(afterSecond).toContain(m.name);
    expect(afterSecond.length).toBeGreaterThanOrEqual(afterFirst.length);
  });
});

describe("find_tool — BM25", () => {
  it("matches an English query against an English description", async () => {
    const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
    tools["mcp__firecrawl__firecrawl_scrape"] = fakeTool(bulky("Scrape a single webpage and return its content"));
    tools["mcp__firecrawl__firecrawl_crawl"] = fakeTool(bulky("Crawl an entire website following links"));
    const plan = planToolSearch({ tools, effectiveLimit: 2000 });
    const r = await callFind(plan, "scrape a webpage");
    expect(r.matched[0]?.name).toBe("mcp__firecrawl__firecrawl_scrape");
  });

  it("expands Chinese search intents so find_tool hits tavily", async () => {
    const prevAlways = process.env.MCP_ALWAYS_LOAD;
    process.env.MCP_ALWAYS_LOAD = "none";
    try {
      const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
      for (let i = 0; i < 4; i++) tools[`mcp__firecrawl__firecrawl_tool_${i}`] = fakeTool(bulky(`other ${i}`));
      tools["mcp__tavily__tavily_search"] = fakeTool(bulky("Search the web and return ranked results"));
      const plan = planToolSearch({ tools, effectiveLimit: 2000, thresholdPct: 0 });
      const r = await callFind(plan, "搜索网页");
      expect(r.matched.map((m) => m.name)).toContain("mcp__tavily__tavily_search");
    } finally {
      if (prevAlways === undefined) delete process.env.MCP_ALWAYS_LOAD;
      else process.env.MCP_ALWAYS_LOAD = prevAlways;
    }
  });

  it("expands Chinese legal intents to chineselaw, not tavily", async () => {
    const prevAlways = process.env.MCP_ALWAYS_LOAD;
    process.env.MCP_ALWAYS_LOAD = "none";
    try {
      const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
      for (let i = 0; i < 4; i++) tools[`mcp__noise__noise_tool_${i}`] = fakeTool(bulky(`noise ${i}`));
      tools["mcp__tavily__tavily_search"] = fakeTool(bulky("Search the web and return ranked results"));
      tools["mcp__chineselaw__search_cases"] = fakeTool(bulky("Search Chinese law cases and statutes"));
      tools["mcp__yuandian-case__search"] = fakeTool(bulky("Search 元典 case database"));
      const plan = planToolSearch({ tools, effectiveLimit: 2000, thresholdPct: 0 });
      const r = await callFind(plan, "检索法律案例");
      const names = r.matched.map((m) => m.name);
      expect(names.some((n) => n.includes("chineselaw") || n.includes("yuandian"))).toBe(true);
      expect(names).not.toContain("mcp__tavily__tavily_search");
    } finally {
      if (prevAlways === undefined) delete process.env.MCP_ALWAYS_LOAD;
      else process.env.MCP_ALWAYS_LOAD = prevAlways;
    }
  });

  it("expands 企查查 / wechat Chinese intents to domain connectors", async () => {
    const prevAlways = process.env.MCP_ALWAYS_LOAD;
    process.env.MCP_ALWAYS_LOAD = "none";
    try {
      const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
      for (let i = 0; i < 4; i++) tools[`mcp__noise__noise_tool_${i}`] = fakeTool(bulky(`noise ${i}`));
      tools["mcp__tavily__tavily_search"] = fakeTool(bulky("Search the web and return ranked results"));
      tools["mcp__qcc-company__company_info"] = fakeTool(bulky("Look up company registry and business credit"));
      tools["mcp__wx-article__fetch"] = fakeTool(bulky("Fetch a weixin public account article by URL"));
      const plan = planToolSearch({ tools, effectiveLimit: 2000, thresholdPct: 0 });

      const qcc = await callFind(plan, "企查查查公司信息");
      expect(qcc.matched.map((m) => m.name)).toContain("mcp__qcc-company__company_info");
      expect(qcc.matched.map((m) => m.name)).not.toContain("mcp__tavily__tavily_search");

      const wx = await callFind(plan, "读取微信公众号文章");
      expect(wx.matched.map((m) => m.name)).toContain("mcp__wx-article__fetch");
      expect(wx.matched.map((m) => m.name)).not.toContain("mcp__tavily__tavily_search");
    } finally {
      if (prevAlways === undefined) delete process.env.MCP_ALWAYS_LOAD;
      else process.env.MCP_ALWAYS_LOAD = prevAlways;
    }
  });

  it("matches an English query against a NON-English description via the tool name", async () => {
    // The corpus is mixed-language: an image server described in Ukrainian. The
    // English query has zero lexical overlap with the description, so the match
    // must come from the tokenized tool NAME (generate_image → generate, image).
    const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
    tools["mcp__yunwu__generate_image"] = fakeTool(bulky("Згенерувати зображення за текстовим описом користувача"));
    tools["mcp__yunwu__edit_photo"] = fakeTool(bulky("Відредагувати наявну світлину за інструкцією"));
    const plan = planToolSearch({ tools, effectiveLimit: 2000 });
    const r = await callFind(plan, "generate an image");
    expect(r.matched.map((m) => m.name)).toContain("mcp__yunwu__generate_image");
  });

  it("returns the connector index and expands nothing when nothing matches", async () => {
    const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
    for (let i = 0; i < 6; i++) tools[`mcp__firecrawl__firecrawl_tool_${i}`] = fakeTool(bulky(`tool ${i}`));
    const plan = planToolSearch({ tools, effectiveLimit: 2000 });
    const before = plan.activeToolNames()!.length;
    const r = await callFind(plan, "quantum chromodynamics zzzzz");
    expect(r.matched).toEqual([]);
    expect(r.message).toContain("firecrawl");
    expect(plan.activeToolNames()!.length).toBe(before); // no expansion on a miss
  });
});

describe("connector index — names only", () => {
  it("lists connector name + tool count, not capability essays or tool names", () => {
    const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
    const defs: [string, string][] = [
      ["firecrawl_scrape", "Scrape a webpage"],
      ["firecrawl_search", "Search the web"],
      ["firecrawl_monitor_create", "Monitor a URL for changes"],
      ["firecrawl_monitor_list", "List existing change monitors"],
      ["firecrawl_research_search_papers", "Search academic papers"],
      ["firecrawl_research_read_paper", "Read a paper's full text"],
    ];
    for (const [t, d] of defs) tools[`mcp__firecrawl__${t}`] = fakeTool(`${d}. ${"lorem ipsum ".repeat(20)}`);
    const plan = planToolSearch({ tools, effectiveLimit: 2000 });
    expect(plan.defer).toBe(true);

    expect(plan.indexText).toContain("**firecrawl** (6 tools)");
    // Capability prose and raw tool names stay out of the always-on index.
    expect(plan.indexText).not.toContain("Monitor a URL for changes");
    expect(plan.indexText).not.toContain("Scrape a webpage");
    expect(plan.indexText).not.toContain("firecrawl_monitor_create");
  });

  it("still indexes a connector that ships no descriptions", () => {
    const tools: Record<string, Tool> = { bash: fakeTool("run a command") };
    const schema = { type: "object", properties: Object.fromEntries([...Array(30)].map((_, i) => [`p${i}`, { type: "string", description: "x".repeat(30) }])) };
    for (const t of ["acme_send_message", "acme_list_channels"]) {
      tools[`mcp__acme__${t}`] = { description: "", inputSchema: { jsonSchema: schema } } as unknown as Tool;
    }
    const plan = planToolSearch({ tools, effectiveLimit: 1500 });
    expect(plan.defer).toBe(true);
    expect(plan.indexText).toContain("**acme** (2 tools)");
    expect(plan.indexText).not.toContain("send message");
  });
});
