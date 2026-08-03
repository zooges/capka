import { describe, it, expect } from "vitest";
import { buildSystemPrompt } from "../prompt";
import { SYSTEM_PROMPT, buildSandboxPrompt } from "@/lib/agents/chat-agent";
import { ASSISTANT_PROFILE, RAW_PROFILE, type AgentProfile } from "@/lib/agents/profile";

/** A profile with one capability group flipped off, everything else default. */
const without = (group: keyof AgentProfile["capabilities"]): AgentProfile => ({
  ...ASSISTANT_PROFILE,
  capabilities: { ...ASSISTANT_PROFILE.capabilities, [group]: false },
});

/** Everything a fully-loaded turn feeds the prompt, so a gate that removes too
 *  much (or too little) shows up as a change in an unrelated block. */
const FULL: Parameters<typeof buildSystemPrompt>[0] = {
  project: { systemPrompt: "Be terse." },
  skills: [{ name: "pdf", description: "PDF things", body: "steps" }],
  connectorIndex: "## Available connectors\n- github",
  memoryDocs: { user: "- likes tea", project: "- ships on Fridays" },
  workspaceSnapshot: "report.docx",
  user: { name: "Yura", timezone: "Europe/Kyiv" },
  attachedFolders: [{ name: "reports", readOnly: true }],
  syncedFolders: [{ name: "desktop" }],
  conversationStartedAt: new Date("2026-07-24T10:00:00Z"),
  concierge: true,
  networkMode: "bridge",
};

describe("buildSystemPrompt — concierge", () => {
  it("adds the one-time first-run concierge nudge only when concierge is set, and keeps it out of the cached prefix", () => {
    const withNudge = buildSystemPrompt({ concierge: true });
    const without = buildSystemPrompt({ concierge: false });

    // The nudge lives in the volatile tier (fires once — must not pollute the
    // cache-stable prefix that every other turn reuses).
    expect(withNudge.volatile).toContain("First run");
    expect(withNudge.volatile.toLowerCase()).toContain("manage");
    expect(withNudge.stable).not.toContain("First run");

    // Off by default — an ordinary turn never sees it.
    expect(without.volatile).not.toContain("First run");
  });
});

describe("buildSystemPrompt — network state", () => {
  it("tells the model it has network when egress is bridged", () => {
    const p = buildSystemPrompt({ networkMode: "bridge" });
    expect(p.stable).toContain("outbound network access");
    expect(p.stable).not.toContain("no network access");
  });

  it("tells the model there is no network when egress is cut, and defaults to no network when unspecified", () => {
    const off = buildSystemPrompt({ networkMode: "none" });
    expect(off.stable).toContain("no network access");
    expect(off.stable).not.toContain("outbound network access");

    // Safe default: absent an explicit mode, assume no egress.
    expect(buildSystemPrompt({}).stable).toContain("no network access");
  });

  it("adds China network + search guidance only when CAPKA_REGION=cn and network is bridged", () => {
    const prev = process.env.CAPKA_REGION;
    const prevSteer = process.env.CAPKA_TAVILY_STEER;
    const prevWeb = process.env.CAPKA_WEB_SEARCH;
    process.env.CAPKA_REGION = "cn";
    delete process.env.CAPKA_TAVILY_STEER;
    delete process.env.CAPKA_WEB_SEARCH;
    try {
      const bridged = buildSystemPrompt({ networkMode: "bridge" });
      expect(bridged.stable).toContain("Network & web access (China)");
      expect(bridged.stable).toContain("no built-in web search");
      expect(bridged.stable).toContain("tavily");
      expect(bridged.stable).toMatch(/Tavily replaces general web search only/);
      expect(bridged.stable).toMatch(/Tavily is already configured/);
      expect(bridged.stable).toContain("mcp__tavily__tavily_search");
      expect(bridged.stable).toContain("pip install tavily");
      expect(bridged.stable).toMatch(/find_tool` for Tavily/);
      expect(bridged.stable).toContain("Domain tasks");
      expect(bridged.stable).toMatch(/matching MCP/);
      expect(bridged.stable).toContain("chineselaw");
      expect(bridged.stable).toMatch(/企查查|yuandian|元典/);
      expect(bridged.stable).toContain("find_tool");
      expect(bridged.stable).toContain("curl");
      expect(bridged.stable).toContain("bing.com");
      expect(bridged.stable).toContain("baidu.com");
      expect(bridged.stable).toContain("google.com");
      expect(bridged.stable).toMatch(/domestic and overseas|overseas sites/);
      expect(bridged.stable).toMatch(/Do not invent network blocks/);
      expect(bridged.stable).toMatch(/must.*attempt a real tool call|Before.*claiming any site is unreachable/i);
      expect(bridged.stable).not.toMatch(/still never Google|Do not use .* foreign search|China-accessible|国内可达|mainland China/);
      expect(bridged.stable).not.toMatch(/Keep using Tavily MCP/);
      expect(bridged.stable).not.toMatch(/For any web search/);

      const offline = buildSystemPrompt({ networkMode: "none" });
      expect(offline.stable).not.toContain("Network & web access (China)");
    } finally {
      if (prev === undefined) delete process.env.CAPKA_REGION;
      else process.env.CAPKA_REGION = prev;
      if (prevSteer === undefined) delete process.env.CAPKA_TAVILY_STEER;
      else process.env.CAPKA_TAVILY_STEER = prevSteer;
      if (prevWeb === undefined) delete process.env.CAPKA_WEB_SEARCH;
      else process.env.CAPKA_WEB_SEARCH = prevWeb;
    }
  });

  it("disables Tavily-first steer when CAPKA_TAVILY_STEER=0 (open web)", () => {
    const prev = process.env.CAPKA_REGION;
    const prevSteer = process.env.CAPKA_TAVILY_STEER;
    const prevWeb = process.env.CAPKA_WEB_SEARCH;
    process.env.CAPKA_REGION = "cn";
    process.env.CAPKA_TAVILY_STEER = "0";
    delete process.env.CAPKA_WEB_SEARCH;
    try {
      const bridged = buildSystemPrompt({ networkMode: "bridge" });
      expect(bridged.stable).toContain("Network & web access (China)");
      expect(bridged.stable).toMatch(/Do not invent network blocks/);
      expect(bridged.stable).toMatch(/must.*attempt a real tool call|Before.*claiming any site is unreachable/i);
      expect(bridged.stable).toMatch(/Open web \(this host\)/);
      expect(bridged.stable).toMatch(/Tavily MCP is \*\*optional\*\*|optional if it appears/);
      expect(bridged.stable).toMatch(/do \*\*not\*\* insist on Tavily-first|not mandatory/);
      expect(bridged.stable).toContain("google.com");
      expect(bridged.stable).toContain("YouTube");
      expect(bridged.stable).toContain("Domain tasks");
      expect(bridged.stable).not.toMatch(/Tavily is already configured/);
      expect(bridged.stable).not.toMatch(/Tavily replaces general web search only/);
      expect(bridged.stable).not.toMatch(/Last resort only/);
    } finally {
      if (prev === undefined) delete process.env.CAPKA_REGION;
      else process.env.CAPKA_REGION = prev;
      if (prevSteer === undefined) delete process.env.CAPKA_TAVILY_STEER;
      else process.env.CAPKA_TAVILY_STEER = prevSteer;
      if (prevWeb === undefined) delete process.env.CAPKA_WEB_SEARCH;
      else process.env.CAPKA_WEB_SEARCH = prevWeb;
    }
  });

  it("does not inject China search guidance when CAPKA_REGION is unset", () => {
    const prev = process.env.CAPKA_REGION;
    delete process.env.CAPKA_REGION;
    delete process.env.CAPKA_CHINA;
    try {
      const p = buildSystemPrompt({ networkMode: "bridge" });
      expect(p.stable).not.toContain("Network & web access (China)");
    } finally {
      if (prev !== undefined) process.env.CAPKA_REGION = prev;
    }
  });
});

describe("buildSystemPrompt — tier assembly", () => {
  // The regression this pins: `prompt.stable` carries the first Anthropic cache
  // breakpoint, so ANY change to layer order or the separator between layers
  // invalidates the cached prefix for every existing user exactly once. Asserting
  // the literal composition (not just "contains X") is what makes that impossible
  // to do by accident.
  it("joins the stable layers in a fixed order with a blank line between them", () => {
    const p = buildSystemPrompt({
      project: { systemPrompt: "Be terse." },
      skills: [{ name: "pdf", description: "PDF things", body: "steps" }],
      connectorIndex: "## Available connectors\n- github",
      networkMode: "none",
    });

    // The first two layers, verbatim and blank-line separated.
    expect(p.stable.startsWith(`${SYSTEM_PROMPT}\n\n${buildSandboxPrompt("none")}`)).toBe(true);
    // The rest follow in declaration order, each separated by exactly one blank line.
    const order = ["--- Project Instructions ---", "pdf", "Available connectors", "Managing settings & configuration"];
    const positions = order.map((needle) => p.stable.indexOf(needle));
    expect(positions.every((i) => i > 0)).toBe(true);
    expect([...positions].sort((a, b) => a - b)).toEqual(positions);
    expect(p.stable).not.toMatch(/\n{3}/); // never a double blank line between layers
  });

  it("drops a tier entirely rather than emitting an empty one", () => {
    // An empty `stable` must be FALSY, not "": the runner keys "push a system
    // message" off it, and Anthropic rejects a message with an empty text block.
    const bare = buildSystemPrompt({ profile: RAW_PROFILE });
    expect(bare.stable).toBe("");
    expect(bare.session).toBe("");
    expect(bare.volatile).toBe("");
  });
});

describe("buildSystemPrompt — capability gating", () => {
  it("gives the raw profile nothing but the project's own instructions", () => {
    const p = buildSystemPrompt({ ...FULL, profile: RAW_PROFILE });

    // Verbatim — and specifically WITHOUT the "--- Project Instructions ---"
    // header: in replace mode this text IS the persona, and framing it as a
    // labelled section puts the model in a different posture.
    expect(p.stable).toBe("Be terse.");
    expect(p.stable).not.toContain("Project Instructions");
    expect(p.session).toBe("");
    expect(p.volatile).toBe("");
  });

  it("keeps the base persona in append mode and adds the project's section under it", () => {
    const p = buildSystemPrompt({ ...FULL, profile: ASSISTANT_PROFILE });
    expect(p.stable).toContain(SYSTEM_PROMPT);
    expect(p.stable).toContain("--- Project Instructions ---\nBe terse.");
  });

  it("removes only the sandbox group's own blocks when it is off", () => {
    const p = buildSystemPrompt({ ...FULL, profile: without("sandbox") });

    // Its protocol AND everything that only makes sense with file tools.
    expect(p.stable).not.toContain("/workspace");
    expect(p.volatile).not.toContain("Current workspace files");
    expect(p.volatile).not.toContain("Attached server folders");
    expect(p.volatile).not.toContain("Folders synced");
    // Untouched neighbours — proof the gate isn't over-reaching.
    expect(p.stable).toContain(SYSTEM_PROMPT);
    expect(p.stable).toContain("Managing settings & configuration");
    expect(p.volatile).toContain("likes tea");
  });

  it("removes both memory blocks together, and nothing else, when memory is off", () => {
    const p = buildSystemPrompt({ ...FULL, profile: without("memory") });
    expect(p.volatile).not.toContain("What you remember");
    expect(p.volatile).not.toContain("likes tea");
    expect(p.volatile).not.toContain("ships on Fridays");
    expect(p.volatile).toContain("Current workspace files");
  });

  it("removes the skills index, the connector index, and the manage protocol with their groups", () => {
    expect(buildSystemPrompt({ ...FULL, profile: without("skills") }).stable).not.toContain("PDF things");
    expect(buildSystemPrompt({ ...FULL, profile: without("connectors") }).stable).not.toContain("Available connectors");

    const noManage = buildSystemPrompt({ ...FULL, profile: without("manage") });
    expect(noManage.stable).not.toContain("Managing settings & configuration");
    // The concierge nudge exists purely to offer configuration through `manage`,
    // so it goes with that group rather than lingering as a dead instruction.
    expect(noManage.volatile).not.toContain("First run");
  });

  it("drops the session tier on request without touching the other two", () => {
    const p = buildSystemPrompt({ ...FULL, profile: { ...ASSISTANT_PROFILE, sessionContext: false } });
    expect(p.session).toBe("");
    expect(p.stable).toContain(SYSTEM_PROMPT);
    expect(p.volatile).toContain("likes tea");
  });
});
