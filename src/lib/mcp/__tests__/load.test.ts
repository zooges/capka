import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Contract: loadMcpTools must NEVER block the start of a turn on a connector
// connect. stdio servers launch inside the chat sandbox via `docker exec` +
// npx/uvx (tens of seconds); remote http MCP (Cloudflare search etc.) routinely
// costs 1–2s per initialize. Both are served from an in-process schema cache and
// connected lazily on the first tool call; a cold cache is warmed in the
// background so tools appear next turn.

const listEnabledServerConfigs = vi.fn();
const connectMcpServer = vi.fn();
const recordConnectError = vi.fn();
const hasUserTokens = vi.fn<(...a: unknown[]) => Promise<boolean>>(() => Promise.resolve(true));

vi.mock("../service", () => ({ listEnabledServerConfigs: (...a: unknown[]) => listEnabledServerConfigs(...a) }));
vi.mock("../client", () => ({
  connectMcpServer: (...a: unknown[]) => connectMcpServer(...a),
  disconnectMcp: vi.fn(),
}));
vi.mock("../adapt", () => ({
  // Capture the caller passed in so a test can exercise the lazy-connect path.
  adaptMcpTool: (client: unknown, server: string, tool: { name: string }) => ({ __caller: client, __server: server, __tool: tool.name }),
  mcpToolName: (s: string, t: string) => `mcp__${s}__${t}`,
}));
vi.mock("../connect-errors", () => ({
  recordConnectError: (...a: unknown[]) => recordConnectError(...a),
  clearConnectError: vi.fn(),
  recentlyFailed: vi.fn(() => false),
}));
vi.mock("../oauth/provider", () => ({ McpOAuthProvider: class {} }));
vi.mock("../oauth/store", () => ({ hasUserTokens: (...a: unknown[]) => hasUserTokens(...a) }));
vi.mock("../plugin-runtime", () => ({ needsPluginRoot: () => false, resolvePluginRoot: vi.fn() }));
vi.mock("@/lib/settings", () => ({ getBlockPrivateProviderUrls: async () => false }));

import { loadMcpTools } from "../load";
import { getCachedTools, setCachedTools, clearCachedTools } from "../tool-cache";
import { disconnectMcp } from "../client";

const cfg = (name: string, transport: "stdio" | "http") => ({
  id: name, name, transport, enabled: true, authKind: "token",
  url: transport === "http" ? "https://e.x/mcp" : null,
  command: transport === "stdio" ? "server" : undefined,
});

beforeEach(() => {
  vi.clearAllMocks();
  clearCachedTools("plug");
  clearCachedTools("api");
  connectMcpServer.mockResolvedValue({ tools: [], client: { callTool: vi.fn() } });
});

describe("loadMcpTools — http is lazy (like stdio)", () => {
  it("does NOT block startup when an http connector's connect hangs", async () => {
    listEnabledServerConfigs.mockResolvedValue([cfg("api", "http")]);
    connectMcpServer.mockReturnValue(new Promise(() => {})); // never resolves
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession: vi.fn() });
    expect(res.tools).toEqual({}); // cold cache → no tools this turn, but it RETURNED
  });

  it("serves cached http tools without connecting at load", async () => {
    setCachedTools("api", [{ name: "q", inputSchema: { type: "object", properties: {} } }]);
    listEnabledServerConfigs.mockResolvedValue([cfg("api", "http")]);
    connectMcpServer.mockReturnValue(new Promise(() => {})); // would hang if called
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession: vi.fn() });
    expect(Object.keys(res.tools)).toEqual(["mcp__api__q"]);
    expect(connectMcpServer).not.toHaveBeenCalled();
  });

  it("warms a cold http connector's tool cache in the background (then hangs up)", async () => {
    listEnabledServerConfigs.mockResolvedValue([cfg("api", "http")]);
    connectMcpServer.mockResolvedValue({ tools: [{ name: "q" }], client: { callTool: vi.fn() } });
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession: vi.fn() });
    expect(res.tools).toEqual({});
    await res.warming;
    expect(getCachedTools("api")).toEqual([{ name: "q" }]);
    expect(disconnectMcp).toHaveBeenCalled(); // schema warm must not hold the session
  });
  it("eager-connects MCP_ALWAYS_LOAD servers so tools exist this turn (cold)", async () => {
    const prevAlways = process.env.MCP_ALWAYS_LOAD;
    process.env.MCP_ALWAYS_LOAD = "tavily";
    try {
      clearCachedTools("tavily");
      listEnabledServerConfigs.mockResolvedValue([cfg("tavily", "http"), cfg("api", "http")]);
      connectMcpServer.mockImplementation(async (c: { name: string }) => ({
        tools: c.name === "tavily" ? [{ name: "tavily_search" }] : [{ name: "q" }],
        client: { callTool: vi.fn() },
      }));
      const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession: vi.fn() });
      // tavily always-load: tools this turn; api stays cold/background.
      expect(Object.keys(res.tools)).toEqual(["mcp__tavily__tavily_search"]);
      expect(connectMcpServer).toHaveBeenCalled();
      expect(getCachedTools("tavily")).toEqual([{ name: "tavily_search" }]);
      await res.warming;
      expect(getCachedTools("api")).toEqual([{ name: "q" }]);
    } finally {
      if (prevAlways === undefined) delete process.env.MCP_ALWAYS_LOAD;
      else process.env.MCP_ALWAYS_LOAD = prevAlways;
      clearCachedTools("tavily");
      clearCachedTools("api");
    }
  });

  it("pre-dials a cached always-load server without blocking load", async () => {
    const prevAlways = process.env.MCP_ALWAYS_LOAD;
    process.env.MCP_ALWAYS_LOAD = "tavily";
    try {
      setCachedTools("tavily", [{ name: "tavily_search", inputSchema: { type: "object", properties: {} } }]);
      listEnabledServerConfigs.mockResolvedValue([cfg("tavily", "http")]);
      let resolveConnect!: (v: unknown) => void;
      const connectPromise = new Promise((r) => { resolveConnect = r; });
      connectMcpServer.mockReturnValue(connectPromise);
      const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession: vi.fn() });
      expect(Object.keys(res.tools)).toEqual(["mcp__tavily__tavily_search"]);
      // Pre-dial started (connect called) but load already returned with cached tools.
      expect(connectMcpServer).toHaveBeenCalledTimes(1);
      resolveConnect({ tools: [{ name: "tavily_search" }], client: { callTool: vi.fn() } });
      await connectPromise;
    } finally {
      if (prevAlways === undefined) delete process.env.MCP_ALWAYS_LOAD;
      else process.env.MCP_ALWAYS_LOAD = prevAlways;
      clearCachedTools("tavily");
    }
  });
});

describe("loadMcpTools — oauth needs a token", () => {
  it("does NOT eager-connect (or record an error for) an oauth http connector with no stored token", async () => {
    // An unauthenticated OAuth connect is a guaranteed 401 — that's an expected
    // not-signed-in-yet state, not a failure. Attempting it every turn wasted a
    // connect and set a connect-error backoff that then hid the connector for 10
    // min AFTER the user finally signed in (the bug behind "connector didn't work").
    listEnabledServerConfigs.mockResolvedValue([{ ...cfg("api", "http"), authKind: "oauth" }]);
    hasUserTokens.mockResolvedValue(false);
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession: vi.fn() });
    expect(connectMcpServer).not.toHaveBeenCalled();
    expect(recordConnectError).not.toHaveBeenCalled();
    expect(res.tools).toEqual({});
  });

  it("background-warms an oauth http connector once its token exists", async () => {
    listEnabledServerConfigs.mockResolvedValue([{ ...cfg("api", "http"), authKind: "oauth" }]);
    hasUserTokens.mockResolvedValue(true);
    connectMcpServer.mockResolvedValue({ tools: [{ name: "q" }], client: { callTool: vi.fn() } });
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession: vi.fn() });
    // Cold cache: background warm, no tools this turn — but connect IS started.
    expect(res.tools).toEqual({});
    await res.warming;
    expect(connectMcpServer).toHaveBeenCalledTimes(1);
    expect(getCachedTools("api")).toEqual([{ name: "q" }]);
  });
});

describe("loadMcpTools — stdio is lazy", () => {
  it("does NOT block startup when a stdio connector's connect hangs", async () => {
    listEnabledServerConfigs.mockResolvedValue([cfg("plug", "stdio")]);
    connectMcpServer.mockReturnValue(new Promise(() => {})); // never resolves
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession: vi.fn().mockResolvedValue(undefined) });
    expect(res.tools).toEqual({}); // cold cache → no tools this turn, but it RETURNED
  });

  it("serves cached stdio tools without connecting or ensuring the session at load", async () => {
    setCachedTools("plug", [{ name: "scan", inputSchema: { type: "object", properties: {} } }]);
    listEnabledServerConfigs.mockResolvedValue([cfg("plug", "stdio")]);
    connectMcpServer.mockReturnValue(new Promise(() => {})); // would hang if called
    const ensureSession = vi.fn();
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession });
    expect(Object.keys(res.tools)).toEqual(["mcp__plug__scan"]);
    expect(connectMcpServer).not.toHaveBeenCalled();
    expect(ensureSession).not.toHaveBeenCalled();
  });

  it("lazily ensures session and connects when a cached stdio tool is executed", async () => {
    setCachedTools("plug", [{ name: "scan", inputSchema: { type: "object", properties: {} } }]);
    listEnabledServerConfigs.mockResolvedValue([cfg("plug", "stdio")]);
    const callTool = vi.fn().mockResolvedValue({ content: [] });
    connectMcpServer.mockResolvedValue({ tools: [{ name: "scan" }], client: { callTool } });
    const ensureSession = vi.fn().mockResolvedValue(undefined);
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession });
    const caller = (res.tools["mcp__plug__scan"] as unknown as { __caller: { callTool: (...a: unknown[]) => Promise<unknown> } }).__caller;
    await caller.callTool({ name: "scan", arguments: {} }, undefined, {});
    expect(ensureSession).toHaveBeenCalledTimes(1);
    expect(connectMcpServer).toHaveBeenCalledTimes(1);
    expect(callTool).toHaveBeenCalledTimes(1);
  });

  it("warms a cold stdio connector's tool cache in the background", async () => {
    listEnabledServerConfigs.mockResolvedValue([cfg("plug", "stdio")]);
    connectMcpServer.mockResolvedValue({ tools: [{ name: "scan" }], client: { callTool: vi.fn() } });
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession: vi.fn().mockResolvedValue(undefined) });
    expect(res.tools).toEqual({}); // nothing offered this turn
    await res.warming;             // background populate finishes
    expect(getCachedTools("plug")).toEqual([{ name: "scan" }]);
  });

  it("records a connect error (for the UI) when a background warm fails, without throwing", async () => {
    listEnabledServerConfigs.mockResolvedValue([cfg("plug", "stdio")]);
    connectMcpServer.mockRejectedValue(new Error("npx: not found"));
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1", ensureSession: vi.fn().mockResolvedValue(undefined) });
    await res.warming;
    expect(recordConnectError).toHaveBeenCalledWith("u1", "plug", expect.stringContaining("npx"));
  });
});

describe("loadMcpTools — always-load (MCP_ALWAYS_LOAD)", () => {
  const prevAlways = process.env.MCP_ALWAYS_LOAD;
  const prevRegion = process.env.CAPKA_REGION;

  beforeEach(() => {
    clearCachedTools("tavily");
    process.env.MCP_ALWAYS_LOAD = "tavily";
    delete process.env.CAPKA_REGION;
  });

  afterEach(() => {
    if (prevAlways === undefined) delete process.env.MCP_ALWAYS_LOAD;
    else process.env.MCP_ALWAYS_LOAD = prevAlways;
    if (prevRegion === undefined) delete process.env.CAPKA_REGION;
    else process.env.CAPKA_REGION = prevRegion;
  });

  it("eagerly connects a cold always-load http server so tools exist this turn", async () => {
    listEnabledServerConfigs.mockResolvedValue([cfg("tavily", "http")]);
    connectMcpServer.mockResolvedValue({
      tools: [{ name: "tavily_search", inputSchema: { type: "object", properties: {} } }],
      client: { callTool: vi.fn() },
    });
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1" });
    expect(Object.keys(res.tools)).toEqual(["mcp__tavily__tavily_search"]);
    expect(connectMcpServer).toHaveBeenCalledTimes(1);
    expect(getCachedTools("tavily")?.[0]?.name).toBe("tavily_search");
  });

  it("registers cached always-load tools immediately and pre-dials without blocking", async () => {
    setCachedTools("tavily", [{ name: "tavily_search", inputSchema: { type: "object", properties: {} } }]);
    listEnabledServerConfigs.mockResolvedValue([cfg("tavily", "http")]);
    let resolveConnect!: (v: unknown) => void;
    connectMcpServer.mockReturnValue(new Promise((r) => { resolveConnect = r; }));
    const res = await loadMcpTools({ userId: "u1", projectId: null, sessionKey: "s1" });
    expect(Object.keys(res.tools)).toEqual(["mcp__tavily__tavily_search"]);
    expect(connectMcpServer).toHaveBeenCalledTimes(1); // pre-dial started
    resolveConnect({ tools: [{ name: "tavily_search" }], client: { callTool: vi.fn() } });
  });
});
